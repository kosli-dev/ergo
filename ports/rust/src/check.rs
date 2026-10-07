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
    let items = literal_of(v).unwrap_or(v).as_array()?;
    items.iter().map(known_arg).collect::<Option<Vec<_>>>().map(Values::List)
}

pub struct Leaf<'a> {
    pub op: &'a str,
    pub paths: Vec<&'a [Value]>,
    value: Option<Arg<'a>>,
    values: Option<Values<'a>>,
    patterns: Option<Values<'a>>,
    min: Option<Arg<'a>>,
    max: Option<Arg<'a>>,
    cmp: Option<&'a str>,
}

pub struct List<'a> {
    every: bool,
    path: &'a [Value],
    each: Option<&'a [Value]>,
    as_: Option<&'a str>,
    inner: Box<Check<'a>>,
}

pub enum Kind<'a> {
    Leaf(Leaf<'a>),
    List(List<'a>),
    AnyOf(Vec<(Value, Vec<Check<'a>>)>),
}

pub enum Spec<'a> {
    Path(&'a [Value]),
    Each(&'a [Value], &'a [Value]),
}

pub struct Check<'a> {
    pub raw: &'a Map<String, Value>,
    pub kind: Kind<'a>,
    expression: Option<&'a str>,
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

fn path_in<'a>(v: Option<&'a Value>, place: &Place) -> Option<&'a [Value]> {
    let p = v?.as_array()?;
    if !path_ok(p) {
        return None;
    }
    match p.first() {
        Some(Value::String(s)) if s == "$$input" || s == "$$params" => Some(p),
        Some(Value::String(s)) if s.starts_with("$$") => None,
        Some(Value::String(s)) if s.starts_with('$') => place.given.iter().any(|g| g == &s[1..]).then_some(p.as_slice()),
        _ => Some(p),
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
                let empty: &'a [Value] = &[];
                let path = match m.get("path") {
                    None => empty,
                    p => path_in(p, place)?,
                };
                let each = match m.get("each") {
                    None => empty,
                    e => path_in(e, place)?,
                };
                Some(Spec::Each(path, each))
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
    let expression = match raw.get("expression") {
        None => None,
        Some(Value::String(s)) => Some(s.as_str()),
        Some(_) => return None,
    };
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
            for (name, group) in groups {
                let checks = group.as_array().filter(|g| !g.is_empty())?;
                options.push((name, checks.iter().map(|c| parse(c, &option_place)).collect::<Option<Vec<_>>>()?));
            }
            (Kind::AnyOf(options), &["options"])
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
    Some(Check { raw, kind, expression, inputs, substitute })
}

fn arg_text(a: &Arg) -> String {
    match a {
        Arg::Literal(v) => literal_text(v),
        Arg::Ref(r) => ref_text(r),
    }
}

fn list_text(values: &Values) -> String {
    match values {
        Values::Ref(r) => ref_text(r),
        Values::List(items) => {
            let mut texts: Vec<String> = items.iter().map(arg_text).collect();
            texts.sort();
            format!("[{}]", texts.join(", "))
        }
    }
}

impl<'a> Leaf<'a> {
    fn expression(&self, item: &str) -> String {
        let p = |i: usize| item_path_name(item, self.paths[i]);
        let one = || self.value.as_ref().map(arg_text).unwrap_or_default();
        let many = |v: &Option<Values>| v.as_ref().map(list_text).unwrap_or_default();
        match self.op {
            "equals" => format!("{} == {}", p(0), one()),
            "present" => format!("{} is present", p(0)),
            "missing" => format!("{} is missing", p(0)),
            "non_empty_string" => format!("{} is a non-empty string", p(0)),
            "empty" => format!("{} is empty", p(0)),
            "in" => format!("{} in {}", p(0), many(&self.values)),
            "includes" if self.value.is_some() => format!("contains({}, {})", p(0), one()),
            "excludes" if self.value.is_some() => format!("not contains({}, {})", p(0), one()),
            "includes" => format!("contains_all({}, {})", p(0), many(&self.values)),
            "excludes" => format!("contains_none({}, {})", p(0), many(&self.values)),
            "range" => {
                let n = p(0);
                let b = |a: &Option<Arg>| a.as_ref().map(arg_text).unwrap_or_default();
                format!("{n} >= {} and {n} <= {}", b(&self.min), b(&self.max))
            }
            "matches_any" => format!("{} matches one of {}", p(0), many(&self.patterns)),
            "not_matches_any" => format!("{} matches none of {}", p(0), many(&self.patterns)),
            _ => format!("{} {} {}", p(0), self.cmp.unwrap_or(""), p(1)),
        }
    }

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
        let reads: Vec<Read> = self.paths.iter().map(|p| ctx.read(x, p)).collect();
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
            "missing" => matches!(reads[0], Read::Absent | Read::Null),
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
        let reads: Vec<Read> = self.paths.iter().map(|p| ctx.read(x, p)).collect();
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

    fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        if self.passed(x, ctx) {
            return Cause::Satisfied;
        }
        let states: Vec<Option<Cause>> = self.paths.iter().map(|p| ctx.read(x, p).problem()).collect();
        if self.op == "present" && matches!(states[0], Some(Cause::Absent | Cause::Null)) {
            return Cause::Missing;
        }
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

fn raw_path(check: &Map<String, Value>) -> &[Value] {
    check.get("path").and_then(Value::as_array).map_or(&[], Vec::as_slice)
}

impl<'a> List<'a> {
    fn collection(&self, x: &'a Value, ctx: &Ctx<'a>) -> Option<&'a Vec<Value>> {
        match ctx.read(x, self.path) {
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
                    match ctx.read(outer, each) {
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
                .flat_map(|outer| match ctx.read(outer, each) {
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

    fn each_state(&self, outer: &'a Value, each: &[Value], ctx: &Ctx<'a>) -> Option<Cause> {
        match ctx.read(outer, each) {
            Read::Found(v) if !v.is_array() => Some(Cause::Unusable),
            r => r.problem(),
        }
    }

    fn states(&self, x: &'a Value, ctx: &Ctx<'a>) -> Vec<Cause> {
        let mut out = vec![];
        match ctx.read(x, self.path) {
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

    fn entries(&self, x: &'a Value, item: &str, ctx: &Ctx<'a>) -> Vec<(String, Value, Option<Cause>, Option<&'a Value>)> {
        let Some(coll) = self.collection(x, ctx) else { return vec![] };
        let list = item_path_name(item, self.path);
        match self.each {
            None => coll.iter().enumerate().map(|(i, v)| (format!("{list}[{i}]"), v.clone(), None, Some(v))).collect(),
            Some(each) => {
                let suffix = if each.is_empty() { String::new() } else { format!(".{}", path_name(each)) };
                let mut out = vec![];
                for (i, outer) in coll.iter().enumerate() {
                    let name = format!("{list}[{i}]{suffix}");
                    match ctx.read(outer, each) {
                        Read::Found(Value::Array(inner)) if !inner.is_empty() => {
                            out.extend(inner.iter().enumerate().map(|(j, v)| (format!("{name}[{j}]"), v.clone(), None, Some(v))))
                        }
                        Read::Found(Value::Array(_)) => out.push((name, json!([]), Some(Cause::Value), None)),
                        r => out.push((name, r.shown(), self.each_state(outer, each, ctx), None)),
                    }
                }
                out
            }
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
            Kind::List(l) => l.passed(x, ctx),
            Kind::AnyOf(options) => options.iter().any(|(_, group)| group.iter().all(|c| c.passed(x, ctx))),
        }
    }

    pub fn cause(&self, x: &'a Value, ctx: &Ctx<'a>) -> Cause {
        match &self.kind {
            Kind::Leaf(l) => l.cause(x, ctx),
            Kind::List(l) => l.cause(x, ctx),
            Kind::AnyOf(options) => {
                if self.passed(x, ctx) {
                    return Cause::Satisfied;
                }
                worst_or_value(options.iter().map(|(_, group)| group_cause(&group.iter().map(|c| c.cause(x, ctx)).collect::<Vec<_>>())))
            }
        }
    }

    fn leaves(&self) -> Vec<&Check<'a>> {
        match &self.kind {
            Kind::AnyOf(options) => options.iter().flat_map(|(_, g)| g.iter()).collect(),
            _ => vec![self],
        }
    }

    fn all_leaves(&self) -> Vec<&Leaf<'a>> {
        let mut out = vec![];
        match &self.kind {
            Kind::Leaf(l) => out.push(l),
            Kind::List(l) => out.extend(l.inner.all_leaves()),
            Kind::AnyOf(options) => out.extend(options.iter().flat_map(|(_, g)| g.iter().flat_map(|c| c.all_leaves()))),
        }
        if let Some(s) = &self.substitute {
            out.extend(s.all_leaves());
        }
        out
    }

    fn param_broken(&self, ctx: &Ctx<'a>) -> bool {
        self.all_leaves().iter().any(|l| l.param_broken(ctx))
    }

    pub fn expression(&self, item: &str, top: bool) -> String {
        if let Some(e) = self.expression {
            return e.to_string();
        }
        match &self.kind {
            Kind::Leaf(l) => l.expression(item),
            Kind::List(l) => {
                let base = if top { path_name(l.path) } else { item_path_name(item, l.path) };
                let collection = match l.each {
                    Some(each) => format!("{base}[].{}", path_name(each)),
                    None => base,
                };
                let item_name = match l.as_ {
                    Some(n) => format!("${n}"),
                    None => format!("{collection}[]"),
                };
                let as_text = l.as_.map(|n| format!(" as ${n}")).unwrap_or_default();
                format!("{} {collection}{as_text}: {}", if l.every { "every" } else { "some" }, l.inner.expression(&item_name, false))
            }
            Kind::AnyOf(options) => {
                let mut parts: Vec<String> = options
                    .iter()
                    .map(|(nm, group)| format!("{}({})", text(nm), group.iter().map(|c| c.expression(item, top)).collect::<Vec<_>>().join(" and ")))
                    .collect();
                parts.sort();
                format!("one of: {}", parts.join(" | "))
            }
        }
    }

    pub fn described(&self, item: &str) -> String {
        match &self.substitute {
            Some(s) => format!("{}, or substitute: {}", self.expression(item, true), s.expression(item, true)),
            None => self.expression(item, true),
        }
    }

    fn leaf_paths(&self) -> Vec<&'a [Value]> {
        match &self.kind {
            Kind::Leaf(l) => l.paths.clone(),
            _ => self.raw.get("path").and_then(Value::as_array).map(|p| vec![p.as_slice()]).unwrap_or_default(),
        }
    }

    fn name_reads(list: &List<'a>) -> Vec<&'a [Value]> {
        let given: Vec<&str> = list.as_.into_iter().collect();
        let mut reads: Vec<(&'a [Value], Vec<&str>)> = vec![];
        for leaf in list.inner.leaves() {
            match &leaf.kind {
                Kind::List(inner) => {
                    reads.push((inner.path, given.clone()));
                    if let Some(each) = inner.each.filter(|e| first_name(e).is_some()) {
                        reads.push((each, given.clone()));
                    }
                    let mut deeper = given.clone();
                    deeper.extend(inner.as_);
                    for l in inner.inner.leaves() {
                        reads.extend(l.leaf_paths().into_iter().map(|p| (p, deeper.clone())));
                    }
                }
                _ => reads.extend(leaf.leaf_paths().into_iter().map(|p| (p, given.clone()))),
            }
        }
        let mut named: Vec<&'a [Value]> = reads
            .into_iter()
            .filter(|(p, g)| first_name(p).is_some_and(|n| !g.contains(&n)))
            .map(|(p, _)| p)
            .collect();
        named.sort_by(|a, b| rego_order(&json!(a), &json!(b)));
        named.dedup_by(|a, b| a == b);
        named
    }

    fn check_reads(&self) -> Vec<&'a [Value]> {
        match &self.kind {
            Kind::List(l) => {
                let mut out = vec![l.path];
                if let Some(each) = l.each.filter(|e| first_name(e).is_some()) {
                    out.push(each);
                }
                out.extend(Self::name_reads(l));
                out
            }
            _ => self.leaf_paths(),
        }
    }

    fn own_inputs(&self, x: &'a Value, item: &str, ctx: &Ctx<'a>) -> Vec<Value> {
        let entry = |name: String, value: Value| json!({"name": name, "value": value});
        if let Some(specs) = &self.inputs {
            return specs
                .iter()
                .map(|s| match s {
                    Spec::Path(p) => entry(item_path_name(item, p), ctx.value_at(x, p)),
                    Spec::Each(p, e) => {
                        let list = match ctx.read(x, p) {
                            Read::Found(Value::Array(items)) => items.iter().map(|el| ctx.value_at(el, e)).collect(),
                            _ => vec![],
                        };
                        entry(projection(p, e), Value::Array(list))
                    }
                })
                .collect();
        }
        match &self.kind {
            Kind::Leaf(l) => l.paths.iter().map(|p| entry(item_path_name(item, p), ctx.value_at(x, p))).collect(),
            Kind::AnyOf(options) => {
                let mut reads: Vec<(String, Value)> = options
                    .iter()
                    .flat_map(|(_, g)| g.iter())
                    .flat_map(|c| c.check_reads())
                    .map(|p| (item_path_name(item, p), ctx.value_at(x, p)))
                    .collect();
                reads.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| rego_order(&a.1, &b.1)));
                reads.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
                reads.into_iter().map(|(n, v)| entry(n, v)).collect()
            }
            Kind::List(l) => {
                let list_at = || match ctx.read(x, l.path) {
                    Read::Found(Value::Array(items)) => items.iter().collect::<Vec<_>>(),
                    _ => vec![],
                };
                let inner_path = raw_path(l.inner.raw);
                let mut out = match l.each {
                    Some(each) => vec![entry(projection(l.path, each), Value::Array(list_at().into_iter().map(|el| ctx.value_at(el, each)).collect()))],
                    None => {
                        let outer_named = first_name(inner_path).is_some_and(|n| l.as_ != Some(n));
                        if outer_named {
                            vec![entry(projection(l.path, &[]), ctx.value_at(x, l.path)), entry(path_name(inner_path), ctx.value_at(x, inner_path))]
                        } else {
                            let rel = if first_name(inner_path).is_some() { &inner_path[1..] } else { inner_path };
                            let vals = list_at().into_iter().map(|el| ctx.value_at(el, rel)).collect();
                            vec![entry(projection(l.path, rel), Value::Array(vals))]
                        }
                    }
                };
                out.extend(Self::name_reads(l).into_iter().filter(|p| *p != inner_path).map(|p| entry(path_name(p), ctx.value_at(x, p))));
                out
            }
        }
    }

    pub fn inputs(&self, x: &'a Value, item: &str, ctx: &Ctx<'a>) -> Vec<Value> {
        let mut out = self.own_inputs(x, item, ctx);
        if let Some(s) = &self.substitute {
            out.extend(s.own_inputs(x, item, ctx));
        }
        out
    }

    fn override_states(&self, x: &'a Value, ctx: &Ctx<'a>) -> Option<Vec<Cause>> {
        let specs = self.inputs.as_ref()?;
        Some(
            specs
                .iter()
                .filter_map(|s| match s {
                    Spec::Path(p) | Spec::Each(p, _) => ctx.read(x, p).problem(),
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

    pub fn row(&self, x: &'a Value, item: &str, ctx: &Ctx<'a>, refs: &[(String, Value, Option<Cause>)]) -> Row {
        let inputs = self.inputs(x, item, ctx);
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
            if let Some(s) = &self.substitute {
                if s.leaves().iter().any(|l| matches!(&l.kind, Kind::Leaf(leaf) if leaf.unusable(x, ctx))) {
                    causes.push(Cause::Unusable);
                }
            }
            worst_or_value(causes)
        };
        let failed_items = match &self.kind {
            Kind::List(l) => Some(self.failed_items(l, x, item, ctx, flaw, &unreadable, main)),
            _ => None,
        };
        Row { passed: main || sub, cause, inputs, failed_items }
    }

    fn failed_items(&self, l: &List<'a>, x: &'a Value, item: &str, ctx: &Ctx<'a>, flaw: Option<Cause>, unreadable: &[Cause], main: bool) -> Vec<Value> {
        let entries = l.entries(x, item, ctx);
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
                        l.item_cause(e, ctx)
                    };
                    (c != Cause::Satisfied).then(|| shown(p, c, v))
                }
                _ => None,
            })
            .collect()
    }
}

pub fn ill_formed_row(is_list: bool) -> Row {
    Row { passed: false, cause: Cause::IllFormed, inputs: vec![], failed_items: is_list.then(Vec::new) }
}

pub fn raw_refs(v: &Value) -> Vec<&[Value]> {
    let mut out = vec![];
    fn walk<'a>(v: &'a Value, out: &mut Vec<&'a [Value]>) {
        if let Some(r) = ref_of(v) {
            out.push(r);
            return;
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
    walk(v, &mut out);
    out
}

pub fn refs_of<'a>(v: &'a Value, ctx: &Ctx<'a>) -> Vec<(String, Value, Option<Cause>)> {
    let mut refs: Vec<(String, Value, Option<Cause>)> = raw_refs(v)
        .into_iter()
        .map(|r| {
            let read = ctx.read_ref(r);
            (ref_text(r), read.shown(), read.problem())
        })
        .collect();
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

pub fn path_ok_with(p: &[Value], given: &[String]) -> bool {
    let place = Place::top(given.to_vec());
    let v = Value::Array(p.to_vec());
    path_in(Some(&v), &place).is_some()
}
