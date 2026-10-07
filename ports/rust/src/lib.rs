mod cel;
mod check;
mod operators;
mod path;
mod problems;
mod render;
mod value;

use check::{Check, Place, Row, described, ill_formed_row, is_list, parse, refs_entry, refs_of};
use path::{Ctx, Read, absent, first_name, from_name, literal_of, ref_of, step_key, valid_name};
use serde_json::{Map, Value, json};
use value::{Cause, literal_text, rego_order, verdict, worst_or_value};

fn well_formed_expression(stepped: bool) -> String {
    let from = if stepped { " and from is well formed" } else { "" };
    format!("fields are known and have the right types and count(checks) >= 1 and require in [\"every\", \"some\"]{from} and steps are keys and numbers fit a float and checks are written right")
}

fn reported_description(m: &Map<String, Value>) -> Value {
    match m.get("description") {
        Some(Value::String(s)) => json!(s),
        _ => json!(""),
    }
}

fn reported_meta(m: &Map<String, Value>) -> Value {
    match m.get("meta") {
        Some(Value::Object(o)) => Value::Object(o.clone()),
        _ => json!({}),
    }
}

struct Step<'a> {
    name: &'a str,
    keys: Option<&'a Value>,
}

struct Named<'a> {
    name: &'a str,
    raw: &'a Value,
    check: Option<Check<'a>>,
    flawed: bool,
}

struct Requirement<'a> {
    name: &'a str,
    raw: &'a Map<String, Value>,
    subject_type: String,
    type_value: Value,
    from: &'a [Value],
    step: Option<Step<'a>>,
    from_ok: bool,
    require: Value,
    min_subjects: Option<f64>,
    checks: Vec<Named<'a>>,
    filters: Vec<Named<'a>>,
    item: String,
    well_formed: bool,
}

fn named_checks<'a>(v: Option<&'a Value>, given: &[String]) -> Option<Vec<Named<'a>>> {
    match v {
        None => Some(vec![]),
        Some(Value::Object(m)) => Some(
            m.iter()
                .map(|(k, c)| {
                    let check = parse(c, &Place::top(given.to_vec()));
                    let flawed = check.is_none() || !problems::check_problems(c, given).is_empty();
                    Named { name: k.as_str(), raw: c, check, flawed }
                })
                .collect(),
        ),
        Some(_) => None,
    }
}

fn requirement<'a>(name: &'a str, raw: &'a Map<String, Value>) -> Requirement<'a> {
    const KNOWN: [&str; 9] = ["subject_type", "from", "id", "checks", "applies_to", "require", "min_subjects", "description", "meta"];
    let empty: &[Value] = &[];
    let from_raw = match raw.get("from") {
        None => Some(empty),
        Some(v) => v.as_array().map(Vec::as_slice),
    };
    let shaped = problems::shape(raw);
    let from_ok = problems::from_well_formed(raw) && from_raw.is_some();
    let (from, step) = match (from_raw, shaped.step) {
        (Some(f), Some(last)) if from_ok => (&f[..f.len() - 1], last.get("each_as").and_then(valid_name).map(|n| Step { name: n, keys: last.get("keys") })),
        (Some(f), _) if from_ok => (f, None),
        _ => (empty, None),
    };
    let given: Vec<String> = step.iter().map(|s| s.name.to_string()).collect();
    let checks = match raw.get("checks") {
        None => None,
        some => named_checks(some, &given),
    };
    let filters = named_checks(raw.get("applies_to"), &given);
    let subject_type = match raw.get("subject_type") {
        None => Some("subject"),
        Some(v) => v.as_str(),
    };
    let require = raw.get("require").cloned().unwrap_or(json!("every"));
    let min_subjects = match raw.get("min_subjects") {
        None => Some(1.0),
        Some(v) => v.as_f64().filter(|_| v.is_number()),
    };
    let _ = (KNOWN, described as fn(&Map<String, Value>) -> bool, &subject_type, &min_subjects);
    let names: Vec<String> = if problems::from_well_formed(raw) { given.clone() } else { vec![] };
    let well_formed = problems::requirement_well_formed(raw, &names);
    let item = match (&step, from) {
        _ if !from_ok => "<invalid from>".into(),
        (Some(s), _) => format!("${}", s.name),
        (None, []) => "$$input".into(),
        (None, f) => format!("{}[]", from_name(f)),
    };
    Requirement {
        name,
        raw,
        type_value: raw.get("subject_type").cloned().unwrap_or(json!("subject")),
        subject_type: match raw.get("subject_type") {
            None => "subject".into(),
            Some(Value::String(s)) => s.clone(),
            Some(other) => literal_text(other),
        },
        from,
        step,
        from_ok,
        require,
        min_subjects,
        checks: checks.unwrap_or_default(),
        filters: filters.unwrap_or_default(),
        item,
        well_formed,
    }
}

struct Entry<'a> {
    key: Option<Value>,
    subject: &'a Value,
}

fn target_problem<'a>(doc: &'a Value, from: &[Value], ctx: &Ctx<'a>) -> Option<Cause> {
    match doc {
        Value::Null if from.is_empty() => Some(Cause::Null),
        Value::Null => Some(Cause::Absent),
        Value::Object(_) => match ctx.read_from(doc, from) {
            Read::Found(Value::Array(_) | Value::Object(_)) => None,
            Read::Found(_) => Some(Cause::Unusable),
            Read::NoKeys => Some(blocked_cause(doc, from)),
            r => r.problem(),
        },
        _ => Some(Cause::Unusable),
    }
}

fn blocked_cause(doc: &Value, from: &[Value]) -> Cause {
    let mut at = doc;
    for step in from {
        let holds = match (at, step) {
            (Value::Null, _) => return Cause::Absent,
            (Value::Object(_), Value::String(_)) | (Value::Array(_), Value::Number(_)) => true,
            (Value::Object(_) | Value::Array(_), Value::Object(_)) => true,
            _ => false,
        };
        if !holds {
            return Cause::Unusable;
        }
        if !path::is_key(step) {
            return Cause::Absent;
        }
        at = match (at, step) {
            (Value::Object(m), Value::String(k)) => match m.get(k) {
                Some(v) => v,
                None => return Cause::Absent,
            },
            (Value::Array(a), Value::Number(n)) => match n.as_u64().and_then(|i| a.get(i as usize)) {
                Some(v) => v,
                None => return Cause::Absent,
            },
            _ => return Cause::Absent,
        };
    }
    Cause::Absent
}

fn listed_keys(keys: &Value, ctx: &Ctx) -> Result<Vec<Value>, Cause> {
    if let Some(r) = ref_of(keys) {
        return match ctx.read_ref(r) {
            Read::Found(Value::Array(items)) => Ok(items.clone()),
            Read::Found(_) => Err(Cause::Unusable),
            r => Err(r.problem().unwrap_or(Cause::Absent)),
        };
    }
    if let Some(Value::Array(items)) = literal_of(keys) {
        return Ok(items.clone());
    }
    let items = keys.as_array().ok_or(Cause::Unusable)?;
    let read: Vec<Result<Value, Cause>> = items
        .iter()
        .map(|k| match ref_of(k) {
            Some(r) => match ctx.read_ref(r) {
                Read::Found(v) if path::is_key(v) => Ok(v.clone()),
                Read::Found(_) => Err(Cause::Unusable),
                r => Err(r.problem().unwrap_or(Cause::Absent)),
            },
            None => Ok(step_key(k).cloned().unwrap_or(Value::Null)),
        })
        .collect();
    match read.iter().filter_map(|r| r.as_ref().err()).min() {
        Some(c) => Err(*c),
        None => Ok(read.into_iter().map(Result::unwrap).collect()),
    }
}

fn from_keys<'a>(req: &Requirement<'a>, ctx: &Ctx<'a>) -> Result<Vec<Value>, Cause> {
    let mut keys = vec![];
    let mut unread = vec![];
    let mut wrong = false;
    for seg in req.from {
        if let Some(r) = ref_of(seg) {
            match ctx.read_ref(r) {
                Read::Found(v) if path::is_key(v) => keys.push(v.clone()),
                Read::Found(_) => wrong = true,
                r => unread.push(r.problem().unwrap_or(Cause::Absent)),
            }
        } else {
            keys.push(literal_of(seg).unwrap_or(seg).clone());
        }
    }
    if let Some(Step { keys: Some(k), .. }) = &req.step {
        if let Some(r) = ref_of(k) {
            if let Some(c) = ctx.read_ref(r).problem() {
                unread.push(c);
            }
        }
    }
    match (unread.into_iter().min(), wrong) {
        (Some(c), _) => Err(c),
        (None, true) => Err(Cause::Unusable),
        _ => Ok(keys),
    }
}

fn entries<'a>(req: &Requirement<'a>, ctx: &Ctx<'a>) -> (Vec<Entry<'a>>, Option<Cause>) {
    if !req.from_ok {
        return (vec![], Some(Cause::Value));
    }
    let keys = match from_keys(req, ctx) {
        Ok(k) => k,
        Err(c) => return (vec![], Some(c)),
    };
    let doc = ctx.doc;
    let target = if doc.is_object() { ctx.read_from(doc, &keys).found() } else { None };
    let problem = target_problem(doc, &keys, ctx);
    let Some(step) = &req.step else {
        return match target {
            Some(Value::Array(items)) => (items.iter().map(|s| Entry { key: None, subject: s }).collect(), None),
            Some(v @ Value::Object(_)) => (vec![Entry { key: None, subject: v }], None),
            _ => (vec![], problem),
        };
    };
    let Some(keys) = step.keys else {
        return match target {
            Some(Value::Array(items)) => (items.iter().map(|s| Entry { key: None, subject: s }).collect(), None),
            Some(Value::Object(m)) => (m.iter().map(|(k, v)| Entry { key: Some(json!(k)), subject: v }).collect(), None),
            _ => (vec![], problem),
        };
    };
    match listed_keys(keys, ctx) {
        Err(c) => (vec![], Some(c)),
        Ok(mut keys) => {
            keys.sort_by(rego_order);
            keys.dedup();
            let object = target.and_then(Value::as_object);
            let entries = keys
                .into_iter()
                .map(|k| {
                    let subject = match (object, k.as_str()) {
                        (Some(m), Some(s)) => m.get(s).unwrap_or(absent()),
                        _ => absent(),
                    };
                    Entry { key: Some(k), subject }
                })
                .collect();
            (entries, None)
        }
    }
}

fn repeated(ids: Vec<Value>) -> Vec<Value> {
    let mut keyed: Vec<(String, Value)> = ids.into_iter().map(|v| (literal_text(&v), v)).collect();
    keyed.sort_by(|a, b| a.0.cmp(&b.0));
    let mut out: Vec<(String, Value)> = vec![];
    for w in keyed.windows(2) {
        if w[0].0 == w[1].0 && out.last().is_none_or(|l| l.0 != w[0].0) {
            out.push(w[0].clone());
        }
    }
    out.into_iter().map(|(_, v)| v).collect()
}

struct Line {
    check: String,
    id: Value,
    row: Row,
}

impl Line {
    fn json(&self, req: &str, subject_type: &Value) -> Value {
        let mut out = json!({
            "requirement": req,
            "subject": {"type": subject_type, "id": self.id},
            "check": self.check,
            "inputs": self.row.inputs,
            "passed": self.row.passed,
            "cause": self.row.cause.name(),
        });
        if let Some(items) = &self.row.failed_items {
            out["failed_items"] = json!(items);
        }
        out
    }

    fn builtin(check: &str, inputs: Vec<Value>, passed: bool, cause: Cause) -> Line {
        Line { check: check.into(), id: Value::Null, row: Row { passed, cause, inputs, failed_items: None } }
    }
}

struct Evaluated<'a> {
    req: Requirement<'a>,
    total: usize,
    matching: usize,
    builtins: [Line; 3],
    applies: Vec<Line>,
    rows: Vec<Line>,
    status: &'static str,
    ctx: Ctx<'a>,
}

fn subject_id(entry: &Entry, req: &Requirement, ctx: &Ctx) -> Value {
    if let Some(k) = &entry.key {
        return k.clone();
    }
    match req.raw.get("id") {
        None if !entry.subject.is_object() => entry.subject.clone(),
        None => entry.subject.clone(),
        Some(Value::Array(id)) if entry.subject.is_object() || first_name(id).is_some() => ctx.value_at(entry.subject, id),
        Some(Value::Array(_)) => entry.subject.clone(),
        Some(_) => Value::Null,
    }
}

fn evaluate<'a>(name: &'a str, raw: &'a Map<String, Value>, base: &Ctx<'a>) -> Evaluated<'a> {
    let req = requirement(name, raw);
    let (all, from_problem) = entries(&req, base);
    let step_name = req.step.as_ref().map(|s| s.name);
    let ids: Vec<Value> = all.iter().map(|e| subject_id(e, &req, &base.with(step_name, e.subject))).collect();
    let repeated_ids = repeated(ids.clone());
    let bad_applies = raw.get("applies_to").is_some_and(|v| !v.is_object());
    let mut applies = vec![];
    let mut in_scope = vec![];
    let mut scope_readable = true;
    for (entry, id) in all.iter().zip(&ids) {
        let ctx = base.with(step_name, entry.subject);
        if req.filters.is_empty() && !bad_applies {
            in_scope.push((entry, id, ctx));
            continue;
        }
        let rows: Vec<(Row, bool)> = req
            .filters
            .iter()
            .map(|f| {
                let inputs = render::row_inputs(&ctx, entry.subject, f.raw, &req.item);
                match &f.check {
                    Some(c) if !f.flawed => {
                        let row = c.row(entry.subject, &ctx, &refs_of(f.raw, &ctx), inputs, vec![]);
                        let missing = !row.passed && c.substitute.is_none() && matches!(&c.kind, check::Kind::Leaf(l) if l.op == "present") && c.cause(entry.subject, &ctx) == Cause::Missing;
                        let row = Row { failed_items: None, ..row };
                        (row, missing)
                    }
                    _ => (ill_formed_row(inputs, None), false),
                }
            })
            .collect();
        let passed = !bad_applies && rows.iter().all(|(r, _)| r.passed);
        let inputs = if bad_applies { vec![] } else { rows.iter().flat_map(|(r, _)| r.inputs.clone()).collect() };
        let failed: Vec<&(Row, bool)> = rows.iter().filter(|(r, _)| !r.passed).collect();
        let cause = if passed {
            Cause::Satisfied
        } else if bad_applies || failed.iter().any(|(r, _)| r.cause == Cause::IllFormed) {
            Cause::IllFormed
        } else if failed.iter().any(|(_, m)| *m) {
            Cause::Value
        } else {
            worst_or_value(failed.iter().map(|(r, _)| r.cause))
        };
        scope_readable &= matches!(cause, Cause::Satisfied | Cause::Value);
        applies.push(Line { check: "$applies".into(), id: id.clone(), row: Row { passed, cause, inputs, failed_items: None } });
        if passed {
            in_scope.push((entry, id, ctx));
        }
    }
    let mut rows = vec![];
    let mut subjects_passing = 0;
    for (entry, id, ctx) in &in_scope {
        let mut all_passed = true;
        for named in &req.checks {
            let inputs = render::row_inputs(ctx, entry.subject, named.raw, &req.item);
            let entries = if is_list(named.raw) { Some(render::item_entries(ctx, entry.subject, named.raw, &req.item)) } else { None };
            let row = match &named.check {
                Some(c) if !named.flawed => c.row(entry.subject, ctx, &refs_of(named.raw, ctx), inputs, entries.unwrap_or_default()),
                _ => ill_formed_row(inputs, entries),
            };
            all_passed &= row.passed;
            rows.push(Line { check: named.name.into(), id: (*id).clone(), row });
        }
        if all_passed {
            subjects_passing += 1;
        }
    }
    let matching = in_scope.len();
    let enough = from_problem.is_none() && req.min_subjects.is_some_and(|m| matching as f64 >= m);
    let unique = repeated_ids.is_empty();
    let t = req.subject_type.clone();
    let builtins = [
        Line::builtin("$well_formed", well_formed_inputs(raw, &req), req.well_formed, verdict(req.well_formed)),
        Line::builtin("$min_subjects", vec![json!({"name": format!("in-scope {t} count"), "value": matching})], enough, from_problem.unwrap_or(verdict(enough))),
        Line::builtin("$unique_ids", vec![json!({"name": format!("repeated {t} ids"), "value": repeated_ids})], unique, verdict(unique)),
    ];
    let checks_hold = match req.require.as_str() {
        Some("some") => matching == 0 || subjects_passing > 0,
        _ => subjects_passing == matching,
    };
    let holds = req.well_formed && enough && unique && scope_readable && checks_hold;
    let status = match (holds, matching == 0) {
        (true, false) => "met",
        (true, true) => "not_applicable",
        _ => "not_met",
    };
    Evaluated { total: all.len(), matching, req, builtins, applies, rows, status, ctx: base.clone() }
}

fn well_formed_inputs(raw: &Map<String, Value>, req: &Requirement) -> Vec<Value> {
    let mut out = vec![json!({"name": "count(checks)", "value": raw.get("checks").and_then(Value::as_object).map_or(0, |c| c.len())})];
    if !problems::has_problems(raw, "require") {
        out.push(json!({"name": "require", "value": req.require}));
    }
    if problems::shape(raw).stepped && !problems::has_problems(raw, "from") {
        out.push(json!({"name": "from", "value": raw["from"]}));
    }
    out.extend(problems::field_problem_inputs(raw));
    let names: Vec<String> = if problems::from_well_formed(raw) { req.step.iter().map(|s| s.name.to_string()).collect() } else { vec![] };
    out.extend(problems::check_problem_inputs(raw, &names));
    out
}

fn from_text(r: &Requirement) -> String {
    if !problems::from_well_formed(r.raw) {
        return "<invalid from>".into();
    }
    match r.from.split_first() {
        None => "$$input".into(),
        Some((Value::String(first), rest)) if first.starts_with('$') => {
            let mut p = vec![json!({"literal": first})];
            p.extend(rest.iter().cloned());
            render::path_name(&Value::Array(p)).unwrap_or_default()
        }
        Some(_) => render::path_name(&Value::Array(r.from.to_vec())).unwrap_or_default(),
    }
}

fn definitions(e: &Evaluated) -> Value {
    let r = &e.req;
    let t = &r.subject_type;
    let from = from_text(r);
    let listed_from = match r.raw.get("from") {
        Some(f @ Value::Array(_)) => f.clone(),
        _ => json!([]),
    };
    let id = r.raw.get("id").cloned().unwrap_or(json!([]));
    let mut defs = Map::new();
    defs.insert("$well_formed".into(), json!({"description": "The requirement is written correctly", "expression": well_formed_expression(problems::shape(r.raw).stepped), "meta": {}}));
    let keyed = problems::shape(r.raw).step.is_some_and(|s| s.contains_key("keys"));
    let n = render::literal_text(r.raw.get("min_subjects").unwrap_or(&json!(1)));
    let mut min_subjects = match r.min_subjects {
        Some(m) if m == 0.0 && !keyed => json!({"description": format!("The {t} list can be read"), "expression": format!("{from} can be read"), "meta": {}}),
        _ => json!({"description": format!("The in-scope {t} count is at least {n}"), "expression": format!("count(matching({from})) >= {n}"), "meta": {}}),
    };
    if let Some(refs) = refs_entry(&refs_of(&json!({"from": listed_from}), &e.ctx)) {
        min_subjects["$refs"] = refs;
    }
    defs.insert("$min_subjects".into(), min_subjects);
    let mut unique = json!({"description": format!("Every {t} id is unique"), "expression": format!("count(repeated(ids({from}))) == 0"), "meta": {}});
    if let Some(refs) = refs_entry(&refs_of(&json!({"from": listed_from, "id": id}), &e.ctx)) {
        unique["$refs"] = refs;
    }
    defs.insert("$unique_ids".into(), unique);
    if r.raw.get("applies_to").is_some_and(|v| !v.is_object()) {
        defs.insert("$applies".into(), json!({"description": format!("The {t} is in scope"), "expression": "<invalid applies_to>", "meta": {}}));
    } else if !r.filters.is_empty() {
        let expression = r.filters.iter().map(|f| render::expression_of(f.raw, &r.item).unwrap_or_default()).collect::<Vec<_>>().join(" and ");
        let mut def = json!({"description": format!("The {t} is in scope"), "expression": expression, "meta": {}});
        let refs = r.raw.get("applies_to").map(|a| refs_of(a, &e.ctx)).unwrap_or_default();
        if let Some(refs) = refs_entry(&refs) {
            def["$refs"] = refs;
        }
        defs.insert("$applies".into(), def);
    }
    for named in &r.checks {
        let mut def = match render::definition(named.raw, &r.item) {
            Value::Object(m) => m,
            _ => Map::new(),
        };
        if let Some(c) = named.raw.as_object() {
            def.insert("description".into(), reported_description(c));
            def.insert("meta".into(), reported_meta(c));
        } else {
            def.insert("description".into(), json!(""));
            def.insert("meta".into(), json!({}));
        }
        if let Some(refs) = refs_entry(&refs_of(named.raw, &e.ctx)) {
            def.insert("$refs".into(), refs);
        }
        defs.insert(named.name.into(), Value::Object(def));
    }
    Value::Object(defs)
}

pub use operators::Operators;

pub fn report_with(document: &Value, params: Option<&Value>, requirements: &Value, operators: &Operators) -> Value {
    let mut out = operators::with_active(std::sync::Arc::new(operators.clone()), || report(document, params, requirements));
    let mut used = Map::new();
    fn walk(v: &Value, operators: &Operators, used: &mut Map<String, Value>) {
        match v {
            Value::Object(m) => {
                if let Some(def) = m.get("op").and_then(Value::as_str).filter(|o| !render::is_builtin(o)).and_then(|o| operators.find(o)) {
                    used.insert(def.name.clone(), def.record.clone());
                }
                m.values().for_each(|x| walk(x, operators, used));
            }
            Value::Array(a) => a.iter().for_each(|x| walk(x, operators, used)),
            _ => {}
        }
    }
    walk(requirements, operators, &mut used);
    if !used.is_empty() {
        out["operators"] = Value::Object(used);
    }
    out
}

pub fn report(document: &Value, params: Option<&Value>, requirements: &Value) -> Value {
    let no_params = json!({});
    let ctx = Ctx { doc: document, params: params.unwrap_or(&no_params), names: vec![] };
    static NOT_AN_OBJECT: std::sync::OnceLock<Map<String, Value>> = std::sync::OnceLock::new();
    let placeholder = NOT_AN_OBJECT.get_or_init(|| {
        let mut m = Map::new();
        m.insert("from".into(), json!({"ergo/not_an_object": true}));
        m
    });
    let named: Vec<(&str, &Map<String, Value>, Option<&Value>)> = match requirements {
        Value::Object(m) => m
            .iter()
            .map(|(k, v)| match v.as_object() {
                Some(o) => (k.as_str(), o, None),
                None => (k.as_str(), placeholder, Some(v)),
            })
            .collect(),
        _ => vec![],
    };
    let evaluated: Vec<Evaluated> = named
        .into_iter()
        .map(|(n, r, not_object)| {
            let mut e = evaluate(n, r, &ctx);
            if let Some(v) = not_object {
                e.builtins[0].row.inputs = vec![json!({"name": "count(checks)", "value": 0}), json!({"name": "require", "value": "every"}), json!({"name": "requirement", "value": v})];
                e.builtins[1].row.cause = Cause::Value;
            }
            e
        })
        .collect();
    let mut results = vec![];
    for i in 0..3 {
        for e in &evaluated {
            results.push(e.builtins[i].json(e.req.name, &e.req.type_value));
        }
    }
    for e in &evaluated {
        results.extend(e.applies.iter().map(|r| r.json(e.req.name, &e.req.type_value)));
    }
    for e in &evaluated {
        results.extend(e.rows.iter().map(|r| r.json(e.req.name, &e.req.type_value)));
    }
    let mut reqs = Map::new();
    for e in &evaluated {
        reqs.insert(
            e.req.name.into(),
            json!({
                "checks": definitions(e),
                "description": reported_description(e.req.raw),
                "meta": reported_meta(e.req.raw),
                "require": e.req.require,
                "status": e.status,
                "subjects": {"matching": e.matching, "total": e.total},
            }),
        );
    }
    let compliant = !evaluated.is_empty() && evaluated.iter().all(|e| e.status != "not_met");
    plain(json!({"compliant": compliant, "requirements": reqs, "results": results}))
}

fn plain(v: Value) -> Value {
    match v {
        Value::Number(n) if !render::out_of_range(&Value::Number(n.clone())) => serde_json::from_str(&render::number_text(&n.to_string())).unwrap_or(Value::Number(n)),
        Value::Array(a) => Value::Array(a.into_iter().map(plain).collect()),
        Value::Object(m) => Value::Object(m.into_iter().map(|(k, x)| (k, plain(x))).collect()),
        other => other,
    }
}

pub fn violations(report: &Value) -> Value {
    let rows = report["results"].as_array().cloned().unwrap_or_default();
    rows.into_iter()
        .filter(|r| r["passed"] == json!(false))
        .filter(|r| !(r["check"] == json!("$applies") && r["cause"] == json!("value")))
        .filter(|r| !matches!(report["requirements"][r["requirement"].as_str().unwrap_or("")]["status"].as_str(), Some("met" | "not_applicable")))
        .map(|r| {
            let def = &report["requirements"][r["requirement"].as_str().unwrap_or("")]["checks"][r["check"].as_str().unwrap_or("")];
            let field = |k: &str| if def.get(k).is_some() { def[k].clone() } else { json!("") };
            let mut inputs = r["inputs"].as_array().cloned().unwrap_or_default();
            inputs.extend(def["$refs"].as_array().cloned().unwrap_or_default());
            let mut v = json!({
                "cause": r["cause"],
                "check": r["check"],
                "description": field("description"),
                "expression": field("expression"),
                "inputs": inputs,
                "requirement": r["requirement"],
                "subject": r["subject"],
            });
            if let Some(items) = r.get("failed_items") {
                v["failed_items"] = items.clone();
            }
            v
        })
        .collect()
}
