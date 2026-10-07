use serde_json::{Map, Value, json};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Cause {
    IllFormed,
    NotAnObject,
    Unusable,
    Absent,
    Null,
    Value,
    Satisfied,
}

impl Cause {
    fn name(self) -> &'static str {
        match self {
            Cause::IllFormed => "ill_formed",
            Cause::NotAnObject => "not_an_object",
            Cause::Unusable => "unusable",
            Cause::Absent => "absent",
            Cause::Null => "null",
            Cause::Value => "value",
            Cause::Satisfied => "satisfied",
        }
    }
}

enum Read<'a> {
    Found(&'a Value),
    Null,
    Absent,
    Unusable,
    NotAnObject,
}

impl<'a> Read<'a> {
    fn shown(&self) -> Value {
        match self {
            Read::Found(v) => (*v).clone(),
            _ => Value::Null,
        }
    }
}

fn read<'a>(start: &'a Value, path: &[Value]) -> Read<'a> {
    if !path.is_empty() && !start.is_object() {
        return Read::NotAnObject;
    }
    let mut at = start;
    for step in path {
        at = match (at, step) {
            (Value::Object(m), Value::String(k)) => match m.get(k) {
                Some(v) => v,
                None => return Read::Absent,
            },
            (Value::Array(items), Value::Number(n)) => match n.as_u64().and_then(|i| items.get(i as usize)) {
                Some(v) => v,
                None => return Read::Absent,
            },
            (Value::Null, _) => return Read::Absent,
            _ => return Read::Unusable,
        };
    }
    match at {
        Value::Null => Read::Null,
        v => Read::Found(v),
    }
}

fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => match (x.as_i64(), y.as_i64(), x.as_u64(), y.as_u64()) {
            (Some(i), Some(j), _, _) => i == j,
            (_, _, Some(i), Some(j)) => i == j,
            _ => x.as_f64() == y.as_f64(),
        },
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(a, b)| same(a, b)),
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| same(v, w)))
        }
        _ => a == b,
    }
}

fn literal_text(v: &Value) -> String {
    match v {
        Value::Array(items) => format!("[{}]", items.iter().map(literal_text).collect::<Vec<_>>().join(", ")),
        Value::Object(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, v)| format!("{}: {}", Value::String(k.clone()), literal_text(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        other => other.to_string(),
    }
}

fn step_text(step: &Value) -> String {
    match step {
        Value::String(s) => s.clone(),
        other => literal_text(other),
    }
}

fn path_name(path: &[Value]) -> String {
    path.iter().map(step_text).collect::<Vec<_>>().join(".")
}

enum Arg<'a> {
    Literal(&'a Value),
    Ref(&'a [Value]),
}

fn arg(v: &Value) -> Arg<'_> {
    match v {
        Value::Object(m) if m.len() == 1 => match (m.get("ref"), m.get("literal")) {
            (Some(Value::Array(r)), _) => Arg::Ref(r),
            (_, Some(l)) => Arg::Literal(l),
            _ => Arg::Literal(v),
        },
        _ => Arg::Literal(v),
    }
}

struct Sources<'a> {
    document: &'a Value,
    params: &'a Value,
}

impl<'a> Sources<'a> {
    fn read_ref(&self, r: &[Value]) -> Read<'a> {
        let root = match r.first().and_then(Value::as_str) {
            Some("$$params") => self.params,
            Some("$$input") => self.document,
            _ => return Read::Unusable,
        };
        match read(root, &r[1..]) {
            Read::NotAnObject => Read::Absent,
            other => other,
        }
    }
}

fn known_ref(r: &[Value]) -> bool {
    matches!(r.first().and_then(Value::as_str), Some("$$params" | "$$input"))
        && r[1..].iter().all(|s| s.is_string() || s.as_u64().is_some())
}

struct Outcome {
    passed: bool,
    cause: Cause,
    inputs: Vec<Value>,
}

fn equals(check: &Map<String, Value>, subject: &Value, sources: &Sources) -> Outcome {
    let path = check["path"].as_array().unwrap();
    let field = read(subject, path);
    let inputs = vec![json!({"name": path_name(path), "value": field.shown()})];
    let expected = match arg(&check["value"]) {
        Arg::Literal(v) => Ok(v),
        Arg::Ref(r) => match sources.read_ref(r) {
            Read::Found(v) => Ok(v),
            Read::Null => Err(Cause::Null),
            Read::Absent | Read::NotAnObject => Err(Cause::Absent),
            Read::Unusable => Err(Cause::Unusable),
        },
    };
    let cause = match (expected, &field) {
        (Err(c), _) => c,
        (Ok(want), Read::Found(v)) if same(v, want) => Cause::Satisfied,
        (Ok(Value::Null), Read::Null) => Cause::Satisfied,
        (Ok(_), Read::Found(_)) => Cause::Value,
        (Ok(_), Read::Null) => Cause::Null,
        (Ok(_), Read::Absent) => Cause::Absent,
        (Ok(_), Read::Unusable) => Cause::Unusable,
        (Ok(_), Read::NotAnObject) => Cause::NotAnObject,
    };
    Outcome { passed: cause == Cause::Satisfied, cause, inputs }
}

fn check_refs(check: &Map<String, Value>) -> Vec<&[Value]> {
    match check.get("value").map(arg) {
        Some(Arg::Ref(r)) => vec![r],
        _ => vec![],
    }
}

fn expression(check: &Map<String, Value>) -> String {
    let path = path_name(check["path"].as_array().unwrap());
    let value = match arg(&check["value"]) {
        Arg::Literal(v) => literal_text(v),
        Arg::Ref(r) => path_name(r),
    };
    format!("{path} == {value}")
}

fn well_formed_check(check: &Value) -> bool {
    let Some(c) = check.as_object() else { return false };
    let fields_known = c.keys().all(|k| ["op", "path", "value", "description", "meta"].contains(&k.as_str()));
    let path_ok = c.get("path").and_then(Value::as_array).is_some_and(|p| p.iter().all(|s| s.is_string()));
    let value_ok = match c.get("value").map(arg) {
        Some(Arg::Ref(r)) => known_ref(r),
        Some(Arg::Literal(_)) => true,
        None => false,
    };
    fields_known
        && c.get("op") == Some(&json!("equals"))
        && path_ok
        && value_ok
        && described(c)
}

fn described(m: &Map<String, Value>) -> bool {
    matches!(m.get("description"), None | Some(Value::Null) | Some(Value::String(_)))
        && matches!(m.get("meta"), None | Some(Value::Null) | Some(Value::Object(_)))
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

const WELL_FORMED_EXPRESSION: &str = "fields are known and have the right types and count(checks) >= 1 and require in [\"every\", \"some\"] and steps are keys and numbers fit a float and checks are written right";

struct Requirement<'a> {
    name: &'a str,
    raw: &'a Map<String, Value>,
    subject_type: String,
    from: &'a [Value],
    id: &'a [Value],
    require: &'a str,
    min_subjects: u64,
    checks: Vec<(&'a str, &'a Value)>,
    well_formed: bool,
}

fn requirement<'a>(name: &'a str, raw: &'a Map<String, Value>) -> Requirement<'a> {
    const KNOWN: [&str; 8] = ["subject_type", "from", "id", "checks", "require", "min_subjects", "description", "meta"];
    let empty: &[Value] = &[];
    let from = raw.get("from").and_then(Value::as_array).map(Vec::as_slice);
    let id = raw.get("id").and_then(Value::as_array).map(Vec::as_slice);
    let checks: Vec<(&str, &Value)> = match raw.get("checks") {
        Some(Value::Object(m)) => m.iter().map(|(k, v)| (k.as_str(), v)).collect(),
        _ => vec![],
    };
    let subject_type = raw.get("subject_type").and_then(Value::as_str);
    let require = match raw.get("require") {
        None => Some("every"),
        Some(v) => v.as_str().filter(|r| ["every", "some"].contains(r)),
    };
    let min_subjects = match raw.get("min_subjects") {
        None => Some(1),
        Some(v) => v.as_u64(),
    };
    let steps_ok = |p: Option<&[Value]>| p.is_some_and(|p| p.iter().all(Value::is_string));
    let well_formed = raw.keys().all(|k| KNOWN.contains(&k.as_str()))
        && subject_type.is_some_and(|s| !s.is_empty())
        && steps_ok(from)
        && steps_ok(id)
        && require.is_some()
        && min_subjects.is_some()
        && !checks.is_empty()
        && checks.iter().all(|(_, c)| well_formed_check(c))
        && described(raw);
    Requirement {
        name,
        raw,
        subject_type: subject_type.unwrap_or("").to_string(),
        from: from.unwrap_or(empty),
        id: id.unwrap_or(empty),
        require: require.unwrap_or("every"),
        min_subjects: min_subjects.unwrap_or(1),
        checks,
        well_formed,
    }
}

struct Evaluated<'a> {
    req: Requirement<'a>,
    subjects: Vec<&'a Value>,
    from_problem: Option<Cause>,
    repeated_ids: Vec<Value>,
    rows: Vec<Value>,
    status: &'static str,
}

fn subjects<'a>(document: &'a Value, from: &[Value]) -> (Vec<&'a Value>, Option<Cause>) {
    match read(document, from) {
        Read::Found(Value::Array(items)) => (items.iter().collect(), None),
        Read::Found(v @ Value::Object(_)) => (vec![v], None),
        Read::Absent => (vec![], Some(Cause::Absent)),
        Read::Null => (vec![], Some(Cause::Null)),
        _ => (vec![], Some(Cause::Unusable)),
    }
}

fn subject_id(subject: &Value, id: &[Value]) -> Value {
    if !subject.is_object() {
        return subject.clone();
    }
    read(subject, id).shown()
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

fn row(req: &str, subject_type: &str, id: Value, check: &str, inputs: Vec<Value>, passed: bool, cause: Cause) -> Value {
    json!({
        "requirement": req,
        "subject": {"type": subject_type, "id": id},
        "check": check,
        "inputs": inputs,
        "passed": passed,
        "cause": cause.name(),
    })
}

fn verdict(passed: bool) -> Cause {
    if passed { Cause::Satisfied } else { Cause::Value }
}

fn evaluate<'a>(name: &'a str, raw: &'a Map<String, Value>, sources: &Sources<'a>) -> Evaluated<'a> {
    let req = requirement(name, raw);
    let (subjects, from_problem) = subjects(sources.document, req.from);
    let repeated_ids = repeated(subjects.iter().map(|s| subject_id(s, req.id)).collect());
    let mut rows = vec![];
    let mut subjects_passing = 0;
    for subject in &subjects {
        let mut all_passed = true;
        for (check_name, check) in &req.checks {
            let outcome = if req.well_formed {
                equals(check.as_object().unwrap(), subject, sources)
            } else {
                Outcome { passed: false, cause: Cause::IllFormed, inputs: vec![] }
            };
            all_passed &= outcome.passed;
            rows.push(row(name, &req.subject_type, subject_id(subject, req.id), check_name, outcome.inputs, outcome.passed, outcome.cause));
        }
        if all_passed {
            subjects_passing += 1;
        }
    }
    let enough = from_problem.is_none() && subjects.len() as u64 >= req.min_subjects;
    let unique = repeated_ids.is_empty();
    let checks_hold = match req.require {
        "some" => subjects_passing > 0,
        _ => subjects_passing == subjects.len(),
    };
    let holds = req.well_formed && enough && unique && checks_hold;
    let status = match (holds, subjects.is_empty()) {
        (true, false) => "met",
        (true, true) => "not_applicable",
        _ => "not_met",
    };
    Evaluated { req, subjects, from_problem, repeated_ids, rows, status }
}

fn builtin_rows(e: &Evaluated) -> [Value; 3] {
    let r = &e.req;
    let t = &r.subject_type;
    let enough = e.from_problem.is_none() && e.subjects.len() as u64 >= r.min_subjects;
    let min_cause = e.from_problem.unwrap_or(verdict(enough));
    [
        row(r.name, t, Value::Null, "$well_formed", vec![json!({"name": "count(checks)", "value": r.checks.len()}), json!({"name": "require", "value": r.require})], r.well_formed, verdict(r.well_formed)),
        row(r.name, t, Value::Null, "$min_subjects", vec![json!({"name": format!("in-scope {t} count"), "value": e.subjects.len()})], enough, min_cause),
        row(r.name, t, Value::Null, "$unique_ids", vec![json!({"name": format!("repeated {t} ids"), "value": e.repeated_ids})], e.repeated_ids.is_empty(), verdict(e.repeated_ids.is_empty())),
    ]
}

fn definitions(e: &Evaluated, sources: &Sources) -> Value {
    let r = &e.req;
    let t = &r.subject_type;
    let from = path_name(r.from);
    let mut defs = Map::new();
    defs.insert("$well_formed".into(), json!({"description": "The requirement is written correctly", "expression": WELL_FORMED_EXPRESSION, "meta": {}}));
    let min_subjects = match r.min_subjects {
        0 => json!({"description": format!("The {t} list can be read"), "expression": format!("{from} can be read"), "meta": {}}),
        n => json!({"description": format!("The in-scope {t} count is at least {n}"), "expression": format!("count(matching({from})) >= {n}"), "meta": {}}),
    };
    defs.insert("$min_subjects".into(), min_subjects);
    defs.insert("$unique_ids".into(), json!({"description": format!("Every {t} id is unique"), "expression": format!("count(repeated(ids({from}))) == 0"), "meta": {}}));
    for (name, check) in &r.checks {
        let Some(c) = check.as_object() else { continue };
        let mut def = c.clone();
        def.insert("description".into(), reported_description(c));
        def.insert("meta".into(), reported_meta(c));
        if r.well_formed {
            def.insert("expression".into(), json!(expression(c)));
            let mut refs: Vec<(String, Value)> = check_refs(c).into_iter().map(|p| (path_name(p), sources.read_ref(p).shown())).collect();
            refs.sort_by(|a, b| a.0.cmp(&b.0));
            if !refs.is_empty() {
                def.insert("$refs".into(), refs.into_iter().map(|(n, v)| json!({"name": n, "value": v})).collect());
            }
        }
        defs.insert((*name).into(), Value::Object(def));
    }
    Value::Object(defs)
}

pub fn report(document: &Value, params: Option<&Value>, requirements: &Value) -> Value {
    let no_params = json!({});
    let sources = Sources { document, params: params.unwrap_or(&no_params) };
    let named: Vec<(&str, &Map<String, Value>)> = match requirements {
        Value::Object(m) => m.iter().filter_map(|(k, v)| v.as_object().map(|o| (k.as_str(), o))).collect(),
        _ => vec![],
    };
    let evaluated: Vec<Evaluated> = named.into_iter().map(|(n, r)| evaluate(n, r, &sources)).collect();
    let mut results = vec![];
    for i in 0..3 {
        for e in &evaluated {
            results.push(builtin_rows(e)[i].clone());
        }
    }
    for e in &evaluated {
        results.extend(e.rows.iter().cloned());
    }
    let mut reqs = Map::new();
    for e in &evaluated {
        reqs.insert(
            e.req.name.into(),
            json!({
                "checks": definitions(e, &sources),
                "description": reported_description(e.req.raw),
                "meta": reported_meta(e.req.raw),
                "require": e.req.require,
                "status": e.status,
                "subjects": {"matching": e.subjects.len(), "total": e.subjects.len()},
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
        .map(|r| {
            let def = &report["requirements"][r["requirement"].as_str().unwrap_or("")]["checks"][r["check"].as_str().unwrap_or("")];
            let mut inputs = r["inputs"].as_array().cloned().unwrap_or_default();
            inputs.extend(def["$refs"].as_array().cloned().unwrap_or_default());
            json!({
                "cause": r["cause"],
                "check": r["check"],
                "description": def["description"],
                "expression": def["expression"],
                "inputs": inputs,
                "requirement": r["requirement"],
                "subject": r["subject"],
            })
        })
        .collect()
}
