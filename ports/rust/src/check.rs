use crate::path::*;
use crate::value::*;
use serde_json::{Map, Value, json};

pub enum Arg<'a> {
    Literal(&'a Value),
    Ref(&'a [Value]),
}

pub fn arg(v: &Value) -> Arg<'_> {
    if let Some(r) = ref_of(v) {
        return Arg::Ref(r);
    }
    Arg::Literal(literal_of(v).unwrap_or(v))
}

fn known_arg(v: &Value) -> Option<Arg<'_>> {
    match arg(v) {
        Arg::Ref(r) if !known_ref(r) => None,
        a => Some(a),
    }
}

pub enum Values<'a> {
    Ref(&'a [Value]),
    List(Vec<Arg<'a>>),
}

fn values_of(v: &Value) -> Option<Values<'_>> {
    if let Some(r) = ref_of(v) {
        return known_ref(r).then_some(Values::Ref(r));
    }
    if let Some(l) = literal_of(v) {
        return Some(Values::List(l.as_array()?.iter().map(Arg::Literal).collect()));
    }
    v.as_array()?.iter().map(known_arg).collect::<Option<Vec<_>>>().map(Values::List)
}

pub struct Leaf<'a> {
    pub op: &'a str,
    pub paths: Vec<&'a Value>,
    value: Option<Arg<'a>>,
    values: Option<Values<'a>>,
    patterns: Option<Values<'a>>,
    min: Option<Arg<'a>>,
    max: Option<Arg<'a>>,
    cmp: Option<&'a str>,
}

pub struct List<'a> {
    every: bool,
    path: &'a Value,
    each: Option<&'a Value>,
    as_: Option<&'a str>,
    inner: Box<Check<'a>>,
}

pub enum Kind<'a> {
    Leaf(Leaf<'a>),
    Custom(Custom<'a>),
    List(List<'a>),
    AnyOf(Vec<Vec<Check<'a>>>),
}

pub enum Spec<'a> {
    Path(&'a Value),
    Each(&'a Value),
}

static EMPTY_PATH: Value = Value::Array(vec![]);

pub struct Check<'a> {
    pub kind: Kind<'a>,
    inputs: Option<Vec<Spec<'a>>>,
    pub substitute: Option<Box<Check<'a>>>,
}

#[derive(Clone)]
pub struct Place {
    pub given: Vec<String>,
    pub depth: u8,
    pub in_option: bool,
    pub top: bool,
}

impl Place {
    pub fn top(given: Vec<String>) -> Place {
        Place { given, depth: 0, in_option: false, top: true }
    }
}

fn path_in<'a>(v: Option<&'a Value>, place: &Place) -> Option<&'a Value> {
    let v = v?;
    if matches!(v, Value::String(_) | Value::Number(_)) {
        return Some(v);
    }
    if v.is_object() && literal_of(v).is_none() && ref_of(v).is_none() {
        return Some(v);
    }
    let p = v.as_array()?;
    if !path_ok(p) {
        return None;
    }
    match p.first() {
        Some(Value::String(s)) if s == "$$input" || s == "$$params" => Some(v),
        Some(Value::String(s)) if s.starts_with("$$") => None,
        Some(Value::String(s)) if s.starts_with('$') => place.given.iter().any(|g| g == &s[1..]).then_some(v),
        _ => Some(v),
    }
}

pub fn described(m: &Map<String, Value>) -> bool {
    matches!(m.get("description"), None | Some(Value::Null) | Some(Value::String(_)))
        && matches!(m.get("meta"), None | Some(Value::Null) | Some(Value::Object(_)))
}

const CMPS: [&str; 6] = ["eq", "ne", "gt", "gte", "lt", "lte"];

fn parse_leaf<'a>(raw: &'a Map<String, Value>, op: &'a str, place: &Place) -> Option<(Leaf<'a>, &'static [&'static str])> {
    let fields: &'static [&'static str] = match op {
        "equals" => &["path", "value"],
        "present" | "missing" | "non_empty_string" | "empty" => &["path"],
        "in" => &["path", "values"],
        "includes" | "excludes" => &["path", "value", "values"],
        "range" => &["path", "min", "max"],
        "matches_any" | "not_matches_any" => &["path", "patterns"],
        "compare" | "compare_time" => &["left", "right", "cmp"],
        _ => return None,
    };
    let mut leaf = Leaf { op, paths: vec![], value: None, values: None, patterns: None, min: None, max: None, cmp: None };
    if op.starts_with("compare") {
        leaf.paths = vec![path_in(raw.get("left"), place)?, path_in(raw.get("right"), place)?];
        leaf.cmp = Some(raw.get("cmp")?.as_str().filter(|c| CMPS.contains(c))?);
        return Some((leaf, fields));
    }
    leaf.paths = vec![path_in(raw.get("path"), place)?];
    match op {
        "equals" => leaf.value = Some(known_arg(raw.get("value")?)?),
        "in" => leaf.values = Some(values_of(raw.get("values")?)?),
        "includes" | "excludes" => match (raw.get("value"), raw.get("values")) {
            (Some(v), None) => leaf.value = Some(known_arg(v)?),
            (None, Some(v)) => {
                let values = values_of(v)?;
                if matches!(&values, Values::List(l) if l.is_empty()) {
                    return None;
                }
                leaf.values = Some(values);
            }
            _ => return None,
        },
        "range" => {
            let bound = |f: &str| -> Option<Arg<'a>> {
                match known_arg(raw.get(f)?)? {
                    Arg::Literal(v) if !v.is_number() => None,
                    a => Some(a),
                }
            };
            let (lo, hi) = (bound("min")?, bound("max")?);
            if let (Arg::Literal(l), Arg::Literal(h)) = (&lo, &hi) {
                if holds("gt", l, h) {
                    return None;
                }
            }
            leaf.min = Some(lo);
            leaf.max = Some(hi);
        }
        "matches_any" | "not_matches_any" => {
            let patterns = values_of(raw.get("patterns")?)?;
            if let Values::List(l) = &patterns {
                for p in l {
                    if let Arg::Literal(v) = p {
                        regex::Regex::new(v.as_str()?).ok()?;
                    }
                }
            }
            leaf.patterns = Some(patterns);
        }
        _ => {}
    }
    Some((leaf, fields))
}

fn specs<'a>(v: &'a Value, place: &Place) -> Option<Vec<Spec<'a>>> {
    v.as_array()?
        .iter()
        .map(|s| match s {
            Value::Array(_) => path_in(Some(s), place).map(Spec::Path),
            Value::Object(m) if m.keys().all(|k| k == "path" || k == "each") => {
                let empty: &'a Value = &EMPTY_PATH;
                let path = match m.get("path") {
                    None => empty,
                    p => path_in(p, place)?,
                };
                let each = match m.get("each") {
                    None => empty,
                    e => path_in(e, place)?,
                };
                let _ = each;
                Some(Spec::Each(path))
            }
            _ => None,
        })
        .collect()
}

pub fn parse<'a>(v: &'a Value, place: &Place) -> Option<Check<'a>> {
    let raw = v.as_object()?;
    let op = raw.get("op")?.as_str()?;
    if !described(raw) {
        return None;
    }
    let inputs = match raw.get("inputs") {
        None => None,
        Some(v) => Some(specs(v, place)?),
    };
    let substitute = match raw.get("substitute") {
        Some(s) if place.top => {
            let mut p = place.clone();
            p.top = false;
            Some(Box::new(parse(s, &Place { in_option: false, ..p })?))
        }
        _ => None,
    };
    let (kind, fields): (Kind, &[&str]) = match op {
        "all" | "any" => {
            if place.depth >= 2 {
                return None;
            }
            let as_ = match raw.get("as") {
                None => None,
                Some(n) => {
                    let n = valid_name(n)?;
                    if place.given.iter().any(|g| g == n) {
                        return None;
                    }
                    Some(n)
                }
            };
            let path = path_in(raw.get("path"), place)?;
            let each = match raw.get("each") {
                None => None,
                e => Some(path_in(e, place)?),
            };
            let mut inner_place = Place { depth: place.depth + 1, in_option: false, top: false, given: place.given.clone() };
            if let Some(n) = as_ {
                inner_place.given.push(n.to_string());
            }
            let inner = Box::new(parse(raw.get("check")?, &inner_place)?);
            (Kind::List(List { every: op == "all", path, each, as_, inner }), &["path", "check", "each", "as"])
        }
        "any_of" => {
            if place.in_option {
                return None;
            }
            let option_place = Place { in_option: true, top: false, ..place.clone() };
            let groups: Vec<(Value, &Value)> = match raw.get("options")? {
                Value::Object(m) => m.iter().map(|(k, g)| (json!(k), g)).collect(),
                Value::Array(l) => l.iter().enumerate().map(|(i, g)| (json!(i), g)).collect(),
                _ => return None,
            };
            if groups.is_empty() {
                return None;
            }
            let mut options = vec![];
            for (_, group) in groups {
                let checks = group.as_array().filter(|g| !g.is_empty())?;
                options.push(checks.iter().map(|c| parse(c, &option_place)).collect::<Option<Vec<_>>>()?);
            }
            (Kind::AnyOf(options), &["options"])
        }
        _ if !crate::render::is_builtin(op) => {
            let def = crate::operators::find(op)?;
            let mut args = vec![];
            for p in &def.params {
                let arg = match (raw.get(&p.name), p.kind) {
                    (None, _) if p.optional => None,
                    (None, _) => return None,
                    (Some(v), crate::operators::Kind::Path) => Some(path_in(Some(v), place)?),
                    (Some(v), crate::operators::Kind::Paths) => {
                        for p in v.as_array()? {
                            path_in(Some(p), place)?;
                        }
                        Some(v)
                    }
                    (Some(v), kind) => {
                        let a = known_arg(v)?;
                        if let Arg::Literal(l) = a {
                            let fits = match kind {
                                crate::operators::Kind::Number => l.is_number(),
                                crate::operators::Kind::String => l.is_string(),
                                _ => true,
                            };
                            if !fits {
                                return None;
                            }
                        }
                        Some(v)
                    }
                };
                args.push(arg);
            }
            let names: Vec<&str> = def.params.iter().map(|p| p.name.as_str()).collect();
            let common = ["op", "description", "meta", "expression", "substitute", "inputs"];
            if !raw.keys().all(|k| common.contains(&k.as_str()) || names.contains(&k.as_str())) {
                return None;
            }
            return Some(Check { kind: Kind::Custom(Custom { def, args }), inputs, substitute });
        }
        _ => {
            let (leaf, fields) = parse_leaf(raw, op, place)?;
            (Kind::Leaf(leaf), fields)
        }
    };
    let common = ["op", "description", "meta", "expression", "inputs", "substitute"];
    if !raw.keys().all(|k| common.contains(&k.as_str()) || fields.contains(&k.as_str())) {
        return None;
    }
    Some(Check { kind, inputs, substitute })
}

impl<'a> Leaf<'a> {
    fn resolve(&self, a: &Arg<'a>, ctx: &Ctx<'a>) -> Option<&'a Value> {
        match a {
            Arg::Literal(v) => Some(*v),
            Arg::Ref(r) => ctx.read_ref(r).found(),
        }
    }

    fn resolve_values(&self, v: &Values<'a>, ctx: &Ctx<'a>) -> Option<Vec<&'a Value>> {
        match v {
            Values::Ref(r) => match ctx.read_ref(r) {
                Read::Found(Value::Array(items)) => Some(items.iter().collect()),
                _ => None,
            },
            Values::List(items) => items.iter().map(|a| self.resolve(a, ctx)).collect(),
        }
    }

    fn param_broken(&self, ctx: &Ctx<'a>) -> bool {
        let found = |a: &Option<Arg<'a>>| match a {
            Some(Arg::Ref(r)) => ctx.read_ref(r).found().cloned(),
            _ => None,
        };
        match self.op {
            "range" => {
                let refs = matches!(self.min, Some(Arg::Ref(_))) || matches!(self.max, Some(Arg::Ref(_)));
                let wrong = [found(&self.min), found(&self.max)].iter().any(|v| v.as_ref().is_some_and(|v| !v.is_number()));
                let lo = self.min.as_ref().and_then(|a| self.resolve(a, ctx));
                let hi = self.max.as_ref().and_then(|a| self.resolve(a, ctx));
                let reversed = matches!((lo, hi), (Some(l), Some(h)) if l.is_number() && h.is_number() && holds("gt", l, h));
                wrong || (refs && reversed)
            }
            "in" => match &self.values {
                Some(Values::Ref(r)) => ctx.read_ref(r).found().is_some_and(|v| !v.is_array()),
                _ => false,
            },
            "includes" | "excludes" => match &self.values {
                Some(Values::Ref(r)) => ctx.read_ref(r).found().is_some_and(|v| v.as_array().is_none_or(Vec::is_empty)),
                _ => false,
            },
            "matches_any" | "not_matches_any" => {
                let valid = |ps: &[&Value]| ps.iter().all(|p| p.as_str().is_some_and(|s| regex::Regex::new(s).is_ok()));
                match &self.patterns {
                    Some(Values::Ref(r)) => match ctx.read_ref(r) {
                        Read::Found(Value::Array(items)) => !valid(&items.iter().collect::<Vec<_>>()),
                        Read::Found(_) => true,
                        _ => false,
                    },
                    Some(v @ Values::List(items)) if items.iter().any(|a| matches!(a, Arg::Ref(_))) => {
                        self.resolve_values(v, ctx).is_some_and(|ps| !valid(&ps))
                    }
                    _ => false,
                }
            }
            _ => false,
        }
    }

    fn passed(&self, x: &'a Value, ctx: &Ctx<'a>) -> bool {
        let reads: Vec<Read> = self.paths.iter().map(|p| crate::render::read_raw(ctx, x, p)).collect();
        let v = reads[0].found();
        match self.op {
            "equals" => {
                let Some(want) = self.value.as_ref().and_then(|a| self.resolve(a, ctx)) else { return false };
                match &reads[0] {
                    Read::Found(v) => same(v, want),
                    Read::Null => want.is_null(),
                    _ => false,
                }
            }
            "present" => v.is_some(),
            "missing" => matches!(reads[0], Read::Absent | Read::Null) && !self.params_not_given(ctx),
            "non_empty_string" => v.and_then(Value::as_str).is_some_and(|s| !s.is_empty()),
            "empty" => v.and_then(Value::as_array).is_some_and(Vec::is_empty),
            "in" => {
                let Some(wants) = self.values.as_ref().and_then(|vs| self.resolve_values(vs, ctx)) else { return false };
                v.is_some_and(|v| wants.iter().any(|w| same(w, v)))
            }
            "includes" | "excludes" => {
                let wants: Option<Vec<&Value>> = match (&self.value, &self.values) {
                    (Some(a), _) => self.resolve(a, ctx).map(|w| vec![w]),
                    (_, Some(vs)) => self.resolve_values(vs, ctx),
                    _ => None,
                };
                let (Some(wants), Some(items)) = (wants, v.and_then(Value::as_array)) else { return false };
                !wants.is_empty()
                    && if self.op == "includes" {
                        wants.iter().all(|w| contains(items, w))
                    } else {
                        wants.iter().all(|w| !contains(items, w))
                    }
            }
            "range" => {
                let lo = self.min.as_ref().and_then(|a| self.resolve(a, ctx));
                let hi = self.max.as_ref().and_then(|a| self.resolve(a, ctx));
                match (v, lo, hi) {
                    (Some(v), Some(lo), Some(hi)) => v.is_number() && lo.is_number() && hi.is_number() && holds("gte", v, lo) && holds("lte", v, hi),
                    _ => false,
                }
            }
            "matches_any" | "not_matches_any" => {
                let Some(patterns) = self.patterns.as_ref().and_then(|ps| self.resolve_values(ps, ctx)) else { return false };
                let Some(s) = v.and_then(Value::as_str) else { return false };
                let mut compiled = vec![];
                for p in patterns {
                    match p.as_str().and_then(|p| regex::Regex::new(p).ok()) {
                        Some(r) => compiled.push(r),
                        None => return false,
                    }
                }
                if self.op == "matches_any" { compiled.iter().any(|r| r.is_match(s)) } else { compiled.iter().all(|r| !r.is_match(s)) }
            }
            "compare" => {
                let cmp = self.cmp.unwrap_or("");
                match (reads[0].found(), reads[1].found()) {
                    (Some(l), Some(r)) => usable_pair(cmp, l, r) && holds(cmp, l, r),
                    _ => false,
                }
            }
            _ => {
                let cmp = self.cmp.unwrap_or("");
                match (reads[0].found(), reads[1].found()) {
                    (Some(l), Some(r)) => match (timestamp_ns(l), timestamp_ns(r)) {
                        (Some(a), Some(b)) => ordered(cmp, a.cmp(&b)),
                        _ => l.is_number() && r.is_number() && holds(cmp, l, r),
                    },
                    _ => false,
                }
            }
        }
    }

    fn unusable(&self, x: &'a Value, ctx: &Ctx<'a>) -> bool {
        let reads: Vec<Read> = self.paths.iter().map(|p| crate::render::read_raw(ctx, x, p)).collect();
        let f = |i: usize| reads[i].found();
        match self.op {
            "range" => f(0).is_some_and(|v| !v.is_number()),
            "matches_any" | "not_matches_any" => f(0).is_some_and(|v| !v.is_string()),
            "includes" | "excludes" | "empty" => f(0).is_some_and(|v| !v.is_array()),
            "compare" => matches!((f(0), f(1)), (Some(l), Some(r)) if !usable_pair(self.cmp.unwrap_or(""), l, r)),
            "compare_time" => matches!((f(0), f(1)), (Some(l), Some(r))
                if !((timestamp_ns(l).is_some() && timestamp_ns(r).is_some()) || (l.is_number() && r.is_number()))),
            _ => false,
        }
    }

    fn params_not_given(&self, ctx: &Ctx<'a>) -> bool {
        self.paths[0].as_array().and_then(|p| p.first()).and_then(Value::as_str) == Some("$$params") && !ctx.params.is_object()
    }

    fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        if self.passed(x, ctx) {
            return Cause::Satisfied;
        }
        let reads: Vec<Read> = self.paths.iter().map(|p| crate::render::read_raw(ctx, x, p)).collect();
        if self.op == "present" && matches!(reads[0], Read::Absent | Read::Null) && !self.params_not_given(ctx) {
            return Cause::Missing;
        }
        let states: Vec<Option<Cause>> = reads.iter().map(Read::problem).collect();
        let mut causes: Vec<Cause> = states.into_iter().flatten().collect();
        if self.unusable(x, ctx) {
            causes.push(Cause::Unusable);
        }
        worst_or_value(causes)
    }
}

fn usable_pair(cmp: &str, l: &Value, r: &Value) -> bool {
    type_name(l) == type_name(r) && (cmp == "eq" || cmp == "ne" || l.is_number() || l.is_string())
}

impl<'a> List<'a> {
    fn collection(&self, x: &'a Value, ctx: &Ctx<'a>) -> Option<&'a Vec<Value>> {
        match crate::render::read_raw(ctx, x, self.path) {
            Read::Found(Value::Array(items)) => Some(items),
            _ => None,
        }
    }

    fn elements(&self, x: &'a Value, ctx: &Ctx<'a>) -> Option<Vec<&'a Value>> {
        let coll = self.collection(x, ctx).filter(|c| !c.is_empty())?;
        match self.each {
            None => Some(coll.iter().collect()),
            Some(each) => {
                let mut out = vec![];
                for outer in coll {
                    match crate::render::read_raw(ctx, outer, each) {
                        Read::Found(Value::Array(inner)) if !inner.is_empty() => out.extend(inner.iter()),
                        _ => return None,
                    }
                }
                Some(out)
            }
        }
    }

    fn items(&self, x: &'a Value, ctx: &Ctx<'a>) -> Vec<&'a Value> {
        let Some(coll) = self.collection(x, ctx) else { return vec![] };
        match self.each {
            None => coll.iter().collect(),
            Some(each) => coll
                .iter()
                .flat_map(|outer| match crate::render::read_raw(ctx, outer, each) {
                    Read::Found(Value::Array(inner)) => inner.iter().collect(),
                    _ => vec![],
                })
                .collect(),
        }
    }

    fn item_ctx(&self, elem: &'a Value, ctx: &Ctx<'a>) -> Ctx<'a> {
        ctx.with(self.as_, elem)
    }

    fn item_passed(&self, elem: &'a Value, ctx: &Ctx<'a>) -> bool {
        self.inner.passed(elem, &self.item_ctx(elem, ctx))
    }

    fn item_cause(&self, elem: &'a Value, ctx: &Ctx<'a>) -> Cause {
        self.inner.cause(elem, &self.item_ctx(elem, ctx))
    }

    fn passed(&self, x: &'a Value, ctx: &Ctx<'a>) -> bool {
        let Some(elements) = self.elements(x, ctx) else { return false };
        if self.every {
            elements.iter().all(|e| self.item_passed(e, ctx))
        } else {
            elements.iter().any(|e| self.item_passed(e, ctx))
        }
    }

    fn each_state(&self, outer: &'a Value, each: &Value, ctx: &Ctx<'a>) -> Option<Cause> {
        match crate::render::read_raw(ctx, outer, each) {
            Read::Found(v) if !v.is_array() => Some(Cause::Unusable),
            r => r.problem(),
        }
    }

    fn states(&self, x: &'a Value, ctx: &Ctx<'a>) -> Vec<Cause> {
        let mut out = vec![];
        match crate::render::read_raw(ctx, x, self.path) {
            Read::Found(v) if !v.is_array() => out.push(Cause::Unusable),
            r => out.extend(r.problem()),
        }
        if let (Some(each), Some(coll)) = (self.each, self.collection(x, ctx)) {
            out.extend(coll.iter().filter_map(|outer| self.each_state(outer, each, ctx)));
        }
        out
    }

    fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        if self.passed(x, ctx) {
            return Cause::Satisfied;
        }
        let mut causes = self.states(x, ctx);
        causes.extend(self.items(x, ctx).into_iter().map(|e| self.item_cause(e, ctx)));
        worst_or_value(causes)
    }

}

pub struct Custom<'a> {
    def: std::sync::Arc<crate::operators::Definition>,
    args: Vec<Option<&'a Value>>,
}

fn has_type(v: &Value, expects: &str) -> bool {
    match expects {
        "list" => v.is_array(),
        "number" => v.is_number(),
        "string" => v.is_string(),
        "object" => v.is_object(),
        _ => v.is_boolean(),
    }
}

impl<'a> Custom<'a> {
    fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        use crate::operators::Kind as K;
        let mut bound = vec![];
        let mut problems = vec![];
        for (p, raw) in self.def.params.iter().zip(&self.args) {
            let Some(raw) = raw else {
                bound.push((p.name.clone(), p.default.clone().unwrap_or(Value::Null)));
                continue;
            };
            if p.kind == K::Paths {
                let mut values = vec![];
                for path in raw.as_array().map(Vec::as_slice).unwrap_or(&[]) {
                    match crate::render::read_raw(ctx, x, path) {
                        Read::Found(v) => values.push(v.clone()),
                        r => problems.push(r.problem().unwrap_or(Cause::Absent)),
                    }
                }
                bound.push((p.name.clone(), Value::Array(values)));
                continue;
            }
            let value = match p.kind {
                K::Path => crate::render::read_raw(ctx, x, raw),
                _ => match arg(raw) {
                    Arg::Literal(v) => Read::Found(v),
                    Arg::Ref(r) => ctx.read_ref(r),
                },
            };
            match value {
                Read::Found(v) => {
                    let fits = match (p.kind, &p.expects) {
                        (K::Path, Some(t)) => has_type(v, t),
                        (K::Number, _) => v.is_number(),
                        (K::String, _) => v.is_string(),
                        _ => true,
                    };
                    if fits {
                        bound.push((p.name.clone(), v.clone()));
                    } else {
                        problems.push(Cause::Unusable);
                    }
                }
                r => problems.push(r.problem().unwrap_or(Cause::Absent)),
            }
        }
        if let Some(c) = problems.into_iter().min() {
            return c;
        }
        match self.def.body.run(&bound) {
            crate::cel::Verdict::True => Cause::Satisfied,
            crate::cel::Verdict::False => Cause::Value,
            crate::cel::Verdict::Failed => Cause::Unusable,
        }
    }
}

pub struct Row {
    pub passed: bool,
    pub cause: Cause,
    pub inputs: Vec<Value>,
    pub failed_items: Option<Vec<Value>>,
}

impl<'a> Check<'a> {
    pub fn passed(&self, x: &'a Value, ctx: &Ctx<'a>) -> bool {
        match &self.kind {
            Kind::Leaf(l) => l.passed(x, ctx),
            Kind::Custom(c) => c.cause(x, ctx) == Cause::Satisfied,
            Kind::List(l) => l.passed(x, ctx),
            Kind::AnyOf(options) => options.iter().any(|group| group.iter().all(|c| c.passed(x, ctx))),
        }
    }

    pub fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        match &self.kind {
            Kind::Leaf(l) => l.cause(x, ctx),
            Kind::Custom(c) => c.cause(x, ctx),
            Kind::List(l) => l.cause(x, ctx),
            Kind::AnyOf(options) => {
                if self.passed(x, ctx) {
                    return Cause::Satisfied;
                }
                worst_or_value(options.iter().map(|group| group_cause(&group.iter().map(|c| c.cause(x, ctx)).collect::<Vec<_>>())))
            }
        }
    }

    fn all_leaves(&self) -> Vec<&Leaf<'a>> {
        let mut out = vec![];
        match &self.kind {
            Kind::Leaf(l) => out.push(l),
            Kind::Custom(_) => {}
            Kind::List(l) => out.extend(l.inner.all_leaves()),
            Kind::AnyOf(options) => out.extend(options.iter().flat_map(|g| g.iter().flat_map(|c| c.all_leaves()))),
        }
        if let Some(s) = &self.substitute {
            out.extend(s.all_leaves());
        }
        out
    }

    fn param_broken(&self, ctx: &Ctx<'a>) -> bool {
        self.all_leaves().iter().any(|l| l.param_broken(ctx))
    }

    fn override_states(&self, x: &'a Value, ctx: &Ctx<'a>) -> Option<Vec<Cause>> {
        let specs = self.inputs.as_ref()?;
        Some(
            specs
                .iter()
                .filter_map(|s| match s {
                    Spec::Path(p) | Spec::Each(p) => crate::render::read_raw(ctx, x, p).problem(),
                })
                .collect(),
        )
    }

    fn base_cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        match self.override_states(x, ctx) {
            Some(states) => worst_or_value(states),
            None => self.cause(x, ctx),
        }
    }

    pub fn substitute_problems(&self, x: &'a Value, ctx: &Ctx<'a>) -> Vec<Cause> {
        self.substitute
            .iter()
            .map(|s| s.base_cause(x, ctx))
            .filter(|c| !matches!(c, Cause::Absent | Cause::Null | Cause::Missing | Cause::Value))
            .collect()
    }

    pub fn row(&self, x: &'a Value, ctx: &Ctx<'a>, refs: &[(String, Value, Option<Cause>)], inputs: Vec<Value>, entries: Vec<crate::render::Entry<'a>>) -> Row {
        let flaw = self.param_broken(ctx).then_some(Cause::Unusable);
        let unreadable: Vec<Cause> = refs.iter().filter_map(|r| r.2).collect();
        let main = flaw.is_none() && self.passed(x, ctx);
        let sub = flaw.is_none() && self.substitute.as_ref().is_some_and(|s| s.passed(x, ctx));
        let cause = if let Some(f) = flaw {
            f
        } else if main {
            Cause::Satisfied
        } else if sub {
            Cause::Substituted
        } else if !unreadable.is_empty() {
            unreadable.iter().copied().min().unwrap()
        } else {
            let mut causes = vec![self.base_cause(x, ctx)];
            causes.extend(self.substitute_problems(x, ctx));
            worst_or_value(causes)
        };
        let failed_items = match &self.kind {
            Kind::List(l) => Some(self.failed_items(l, ctx, entries, flaw, &unreadable, main)),
            _ => None,
        };
        Row { passed: main || sub, cause, inputs, failed_items }
    }

    fn failed_items(&self, l: &List<'a>, ctx: &Ctx<'a>, entries: Vec<crate::render::Entry<'a>>, flaw: Option<Cause>, unreadable: &[Cause], main: bool) -> Vec<Value> {
        let shown = |p: String, c: Cause, v: Value| json!({"path": p, "cause": c.name(), "value": v});
        if let Some(f) = flaw {
            return entries.into_iter().map(|(p, v, _, _)| shown(p, f, v)).collect();
        }
        if main {
            return vec![];
        }
        entries
            .into_iter()
            .filter_map(|(p, v, c, elem)| match (c, elem) {
                (Some(c), _) => Some(shown(p, c, v)),
                (None, Some(e)) => {
                    let c = if l.item_passed(e, ctx) {
                        Cause::Satisfied
                    } else if let Some(r) = unreadable.iter().copied().min() {
                        r
                    } else {
                        match l.item_cause(e, ctx) {
                            Cause::Missing => Cause::Value,
                            c => c,
                        }
                    };
                    (c != Cause::Satisfied).then(|| shown(p, c, v))
                }
                _ => None,
            })
            .collect()
    }
}

pub fn ill_formed_row(inputs: Vec<Value>, entries: Option<Vec<crate::render::Entry>>) -> Row {
    let failed_items = entries.map(|es| es.into_iter().map(|(p, v, _, _)| json!({"path": p, "cause": "ill_formed", "value": v})).collect());
    Row { passed: false, cause: Cause::IllFormed, inputs, failed_items }
}

fn step_refs(v: &Value) -> Vec<&[Value]> {
    let mut out = vec![];
    fn walk<'a>(v: &'a Value, field: Option<&str>, out: &mut Vec<&'a [Value]>) {
        if literal_of(v).is_some() {
            return;
        }
        match v {
            Value::Object(m) => m.iter().for_each(|(k, x)| walk(x, Some(k), out)),
            Value::Array(a) => {
                for x in a {
                    if let (Some("path" | "left" | "right" | "each"), Some(r)) = (field, ref_of(x)) {
                        out.push(r);
                    }
                    walk(x, None, out);
                }
            }
            _ => {}
        }
    }
    walk(v, None, &mut out);
    out
}

pub fn refs_of<'a>(v: &Value, ctx: &Ctx<'a>) -> Vec<(String, Value, Option<Cause>)> {
    let steps = step_refs(v);
    let mut found: Vec<(String, Value, Option<Cause>)> = vec![];
    fn walk<'v>(v: &'v Value, out: &mut Vec<&'v Value>) {
        if crate::render::is_ref(v) || crate::render::malformed(v) {
            out.push(v);
        }
        if literal_of(v).is_some() {
            return;
        }
        match v {
            Value::Object(m) => m.values().for_each(|x| walk(x, out)),
            Value::Array(a) => a.iter().for_each(|x| walk(x, out)),
            _ => {}
        }
    }
    let mut wrapped = vec![];
    walk(v, &mut wrapped);
    for w in wrapped {
        if crate::render::malformed(w) {
            found.push(("<invalid ref>".into(), Value::Null, Some(Cause::Absent)));
            continue;
        }
        let r = &w["ref"];
        let read = match r.as_array() {
            Some(p) if crate::render::builtin(r) => ctx.read_ref(p),
            _ => Read::Absent,
        };
        let wrong_step = r.as_array().is_some_and(|p| steps.contains(&p.as_slice())) && read.found().is_some_and(|x| !is_key(x));
        let problem = if wrong_step { Some(Cause::Unusable) } else { read.problem() };
        found.push((crate::render::ref_name(r), read.shown(), problem));
    }
    let mut refs = found;
    refs.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| rego_order(&a.1, &b.1)));
    refs.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
    refs
}

pub fn refs_entry(refs: &[(String, Value, Option<Cause>)]) -> Option<Value> {
    (!refs.is_empty()).then(|| refs.iter().map(|(n, v, _)| json!({"name": n, "value": v})).collect())
}

pub fn is_list(v: &Value) -> bool {
    matches!(v.get("op").and_then(Value::as_str), Some("all" | "any"))
}

