mod check;
mod path;
mod value;

use check::{Check, Place, Row, described, ill_formed_row, is_list, parse, refs_entry, refs_of};
use path::{Ctx, Read, absent, first_name, from_name, literal_of, path_ok, ref_of, step_key, valid_name};
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
}

struct Requirement<'a> {
    name: &'a str,
    raw: &'a Map<String, Value>,
    subject_type: String,
    from: &'a [Value],
    step: Option<Step<'a>>,
    from_ok: bool,
    id: &'a [Value],
    require: Value,
    min_subjects: u64,
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
                .map(|(k, c)| Named { name: k.as_str(), raw: c, check: parse(c, &Place::top(given.to_vec())) })
                .collect(),
        ),
        Some(_) => None,
    }
}

fn keys_ok(keys: &Value) -> bool {
    if let Some(r) = ref_of(keys) {
        return path::known_ref(r);
    }
    match (literal_of(keys), keys) {
        (Some(Value::Array(items)), _) => items.iter().all(path::is_key),
        (Some(_), _) => false,
        (None, Value::Array(items)) => items.iter().all(|k| step_key(k).is_some() || ref_of(k).is_some_and(path::known_ref)),
        _ => false,
    }
}

fn requirement<'a>(name: &'a str, raw: &'a Map<String, Value>) -> Requirement<'a> {
    const KNOWN: [&str; 9] = ["subject_type", "from", "id", "checks", "applies_to", "require", "min_subjects", "description", "meta"];
    let empty: &[Value] = &[];
    let from_raw = match raw.get("from") {
        None => Some(empty),
        Some(v) => v.as_array().map(Vec::as_slice),
    };
    let (from, step, from_ok) = match from_raw {
        None => (empty, None, false),
        Some(f) => match f.split_last() {
            Some((Value::Object(last), rest)) if last.contains_key("each_as") => {
                let name = last.get("each_as").and_then(valid_name);
                let keys = last.get("keys");
                let ok = name.is_some() && last.keys().all(|k| k == "each_as" || k == "keys") && keys.is_none_or(keys_ok) && path_ok(rest);
                (rest, name.map(|n| Step { name: n, keys }), ok)
            }
            _ => (f, None, path_ok(f)),
        },
    };
    let given: Vec<String> = step.iter().map(|s| s.name.to_string()).collect();
    let id = match raw.get("id") {
        None => Some(empty),
        Some(v) => v.as_array().map(Vec::as_slice).filter(|p| check::path_ok_with(p, &given)),
    };
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
        None => Some(1),
        Some(v) => v.as_u64(),
    };
    let all_parsed = |n: &Option<Vec<Named>>| n.as_ref().is_some_and(|n| n.iter().all(|c| c.check.is_some()));
    let well_formed = raw.keys().all(|k| KNOWN.contains(&k.as_str()))
        && subject_type.is_some_and(|s| !s.trim().is_empty())
        && from_ok
        && id.is_some()
        && matches!(require.as_str(), Some("every" | "some"))
        && min_subjects.is_some()
        && checks.as_ref().is_some_and(|c| !c.is_empty())
        && all_parsed(&checks)
        && all_parsed(&filters)
        && described(raw);
    let item = match (&step, from) {
        (Some(s), _) => format!("${}", s.name),
        (None, []) => "$$input".into(),
        (None, f) => format!("{}[]", from_name(f)),
    };
    Requirement {
        name,
        raw,
        subject_type: match raw.get("subject_type") {
            None => "subject".into(),
            Some(Value::String(s)) => s.clone(),
            Some(other) => literal_text(other),
        },
        from,
        step,
        from_ok,
        id: id.unwrap_or(empty),
        require,
        min_subjects: min_subjects.unwrap_or(1),
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

fn target_problem(doc: &Value, from: &[Value]) -> Option<Cause> {
    match doc {
        Value::Null if from.is_empty() => Some(Cause::Null),
        Value::Null => Some(Cause::Absent),
        Value::Object(_) => match path::read_steps(doc, from) {
            Read::Found(Value::Array(_) | Value::Object(_)) => None,
            Read::Found(_) => Some(Cause::Unusable),
            r => r.problem(),
        },
        _ => Some(Cause::Unusable),
    }
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

fn entries<'a>(req: &Requirement<'a>, ctx: &Ctx<'a>) -> (Vec<Entry<'a>>, Option<Cause>) {
    if !req.from_ok {
        return (vec![], Some(Cause::Value));
    }
    let doc = ctx.doc;
    let target = if doc.is_object() { path::read_steps(doc, req.from).found() } else { None };
    let problem = target_problem(doc, req.from);
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
    fn json(&self, req: &str, subject_type: &str) -> Value {
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
    if !entry.subject.is_object() && first_name(req.id).is_none() {
        return entry.subject.clone();
    }
    ctx.value_at(entry.subject, req.id)
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
            .map(|f| match &f.check {
                Some(c) => {
                    let row = c.row(entry.subject, &req.item, &ctx, &refs_of(f.raw, &ctx));
                    let missing = !row.passed && c.substitute.is_none() && matches!(&c.kind, check::Kind::Leaf(l) if l.op == "present") && c.cause(entry.subject, &ctx) == Cause::Missing;
                    (row, missing)
                }
                None => (ill_formed_row(false), false),
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
            let row = match &named.check {
                Some(c) => c.row(entry.subject, &req.item, ctx, &refs_of(named.raw, ctx)),
                None => ill_formed_row(is_list(named.raw)),
            };
            all_passed &= row.passed;
            rows.push(Line { check: named.name.into(), id: (*id).clone(), row });
        }
        if all_passed {
            subjects_passing += 1;
        }
    }
    let matching = in_scope.len();
    let enough = from_problem.is_none() && matching as u64 >= req.min_subjects;
    let unique = repeated_ids.is_empty();
    let t = req.subject_type.clone();
    let builtins = [
        Line::builtin("$well_formed", vec![json!({"name": "count(checks)", "value": req.checks.len()}), json!({"name": "require", "value": req.require})], req.well_formed, verdict(req.well_formed)),
        Line::builtin("$min_subjects", vec![json!({"name": format!("in-scope {t} count"), "value": matching})], enough, from_problem.unwrap_or(verdict(enough))),
        Line::builtin("$unique_ids", vec![json!({"name": format!("repeated {t} ids"), "value": repeated_ids})], unique, verdict(unique)),
    ];
    let checks_hold = match req.require.as_str() {
        Some("some") => subjects_passing > 0,
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

fn definitions(e: &Evaluated) -> Value {
    let r = &e.req;
    let t = &r.subject_type;
    let from = from_name(r.from);
    let mut defs = Map::new();
    defs.insert("$well_formed".into(), json!({"description": "The requirement is written correctly", "expression": well_formed_expression(r.step.is_some()), "meta": {}}));
    let min_subjects = match r.min_subjects {
        0 => json!({"description": format!("The {t} list can be read"), "expression": format!("{from} can be read"), "meta": {}}),
        n => json!({"description": format!("The in-scope {t} count is at least {n}"), "expression": format!("count(matching({from})) >= {n}"), "meta": {}}),
    };
    defs.insert("$min_subjects".into(), min_subjects);
    defs.insert("$unique_ids".into(), json!({"description": format!("Every {t} id is unique"), "expression": format!("count(repeated(ids({from}))) == 0"), "meta": {}}));
    if !r.filters.is_empty() || r.raw.get("applies_to").is_some_and(|v| !v.is_object()) {
        let expression = r.filters.iter().filter_map(|f| f.check.as_ref()).map(|c| c.expression(&r.item, true)).collect::<Vec<_>>().join(" and ");
        let mut def = json!({"description": format!("The {t} is in scope"), "expression": expression, "meta": {}});
        let refs = r.raw.get("applies_to").map(|a| refs_of(a, &e.ctx)).unwrap_or_default();
        if let Some(refs) = refs_entry(&refs) {
            def["$refs"] = refs;
        }
        defs.insert("$applies".into(), def);
    }
    for named in &r.checks {
        let Some(c) = named.raw.as_object() else { continue };
        let mut def = c.clone();
        def.insert("description".into(), reported_description(c));
        def.insert("meta".into(), reported_meta(c));
        if let Some(check) = &named.check {
            def.insert("expression".into(), json!(check.described(&r.item)));
        }
        if let Some(refs) = refs_entry(&refs_of(named.raw, &e.ctx)) {
            def.insert("$refs".into(), refs);
        }
        defs.insert(named.name.into(), Value::Object(def));
    }
    Value::Object(defs)
}

pub fn report(document: &Value, params: Option<&Value>, requirements: &Value) -> Value {
    let no_params = json!({});
    let ctx = Ctx { doc: document, params: params.unwrap_or(&no_params), names: vec![] };
    let named: Vec<(&str, &Map<String, Value>)> = match requirements {
        Value::Object(m) => m.iter().filter_map(|(k, v)| v.as_object().map(|o| (k.as_str(), o))).collect(),
        _ => vec![],
    };
    let evaluated: Vec<Evaluated> = named.into_iter().map(|(n, r)| evaluate(n, r, &ctx)).collect();
    let mut results = vec![];
    for i in 0..3 {
        for e in &evaluated {
            results.push(e.builtins[i].json(e.req.name, &e.req.subject_type));
        }
    }
    for e in &evaluated {
        results.extend(e.applies.iter().map(|r| r.json(e.req.name, &e.req.subject_type)));
    }
    for e in &evaluated {
        results.extend(e.rows.iter().map(|r| r.json(e.req.name, &e.req.subject_type)));
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
    json!({"compliant": compliant, "requirements": reqs, "results": results})
}

pub fn violations(report: &Value) -> Value {
    let rows = report["results"].as_array().cloned().unwrap_or_default();
    rows.into_iter()
        .filter(|r| r["passed"] == json!(false))
        .filter(|r| !(r["check"] == json!("$applies") && r["cause"] == json!("value")))
        .map(|r| {
            let def = &report["requirements"][r["requirement"].as_str().unwrap_or("")]["checks"][r["check"].as_str().unwrap_or("")];
            let mut inputs = r["inputs"].as_array().cloned().unwrap_or_default();
            inputs.extend(def["$refs"].as_array().cloned().unwrap_or_default());
            let mut v = json!({
                "cause": r["cause"],
                "check": r["check"],
                "description": def["description"],
                "expression": def["expression"],
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
