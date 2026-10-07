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

impl Read<'_> {
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

fn path_name(path: &[Value]) -> String {
    path.iter()
        .map(|step| match step {
            Value::String(s) => s.clone(),
            other => literal_text(other),
        })
        .collect::<Vec<_>>()
        .join(".")
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

fn known_ref(r: &[Value]) -> bool {
    matches!(r.first().and_then(Value::as_str), Some("$$params" | "$$input"))
        && r[1..].iter().all(|s| s.is_string() || s.as_u64().is_some())
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

enum Kind<'a> {
    Equals { path: &'a [Value], value: Arg<'a> },
    Present { path: &'a [Value] },
    List { every: bool, path: &'a [Value], inner: Box<Check<'a>> },
}

struct Check<'a> {
    kind: Kind<'a>,
}

fn key_path(v: Option<&Value>) -> Option<&[Value]> {
    v.and_then(Value::as_array).filter(|p| p.iter().all(Value::is_string)).map(Vec::as_slice)
}

fn described(m: &Map<String, Value>) -> bool {
    matches!(m.get("description"), None | Some(Value::Null) | Some(Value::String(_)))
        && matches!(m.get("meta"), None | Some(Value::Null) | Some(Value::Object(_)))
}

fn parse(v: &Value, nested: bool) -> Option<Check<'_>> {
    let raw = v.as_object()?;
    let op = raw.get("op")?.as_str()?;
    let fields: &[&str] = match op {
        "equals" => &["path", "value"],
        "present" => &["path"],
        "all" | "any" if !nested => &["path", "check"],
        _ => return None,
    };
    let known = |k: &str| k == "op" || k == "description" || k == "meta" || fields.contains(&k);
    if !raw.keys().all(|k| known(k)) || !described(raw) {
        return None;
    }
    let path = key_path(raw.get("path"))?;
    let kind = match op {
        "equals" => {
            let value = arg(raw.get("value")?);
            if let Arg::Ref(r) = value {
                if !known_ref(r) {
                    return None;
                }
            }
            Kind::Equals { path, value }
        }
        "present" => Kind::Present { path },
        _ => Kind::List { every: op == "all", path, inner: Box::new(parse(raw.get("check")?, true)?) },
    };
    Some(Check { kind })
}

impl Check<'_> {
    fn expression(&self) -> String {
        match &self.kind {
            Kind::Equals { path, value } => {
                let shown = match value {
                    Arg::Literal(v) => literal_text(v),
                    Arg::Ref(r) => path_name(r),
                };
                format!("{} == {shown}", path_name(path))
            }
            Kind::Present { path } => format!("{} is present", path_name(path)),
            Kind::List { every, path, inner } => {
                format!("{} {}: {}", if *every { "every" } else { "some" }, path_name(path), inner.expression())
            }
        }
    }

    fn refs(&self) -> Vec<&[Value]> {
        match &self.kind {
            Kind::Equals { value: Arg::Ref(r), .. } => vec![*r],
            Kind::List { inner, .. } => inner.refs(),
            _ => vec![],
        }
    }

    fn input_names(&self) -> Vec<String> {
        match &self.kind {
            Kind::Equals { path, .. } | Kind::Present { path } => vec![path_name(path)],
            Kind::List { path, inner, .. } => {
                inner.input_names().into_iter().map(|n| format!("{}[].{n}", path_name(path))).collect()
            }
        }
    }
}

struct Outcome {
    passed: bool,
    cause: Cause,
    inputs: Vec<Value>,
    failed_items: Option<Vec<Value>>,
    answered_missing: bool,
}

impl Outcome {
    fn of(cause: Cause, inputs: Vec<Value>) -> Outcome {
        Outcome { passed: cause == Cause::Satisfied, cause, inputs, failed_items: None, answered_missing: false }
    }
}

fn evaluate_check(check: &Check, subject: &Value, sources: &Sources) -> Outcome {
    match &check.kind {
        Kind::Equals { path, value } => {
            let field = read(subject, path);
            let inputs = vec![field.shown()];
            let want = match value {
                Arg::Literal(v) => Ok(*v),
                Arg::Ref(r) => match sources.read_ref(r) {
                    Read::Found(v) => Ok(v),
                    Read::Null => Err(Cause::Null),
                    Read::Absent | Read::NotAnObject => Err(Cause::Absent),
                    Read::Unusable => Err(Cause::Unusable),
                },
            };
            let cause = match (want, &field) {
                (Err(c), _) => c,
                (Ok(want), Read::Found(v)) if same(v, want) => Cause::Satisfied,
                (Ok(Value::Null), Read::Null) => Cause::Satisfied,
                (Ok(_), Read::Found(_)) => Cause::Value,
                (Ok(_), Read::Null) => Cause::Null,
                (Ok(_), Read::Absent) => Cause::Absent,
                (Ok(_), Read::Unusable) => Cause::Unusable,
                (Ok(_), Read::NotAnObject) => Cause::NotAnObject,
            };
            Outcome::of(cause, inputs)
        }
        Kind::Present { path } => {
            let field = read(subject, path);
            let inputs = vec![field.shown()];
            match field {
                Read::Found(_) => Outcome::of(Cause::Satisfied, inputs),
                Read::Null | Read::Absent => Outcome { answered_missing: true, ..Outcome::of(Cause::Value, inputs) },
                Read::Unusable => Outcome::of(Cause::Unusable, inputs),
                Read::NotAnObject => Outcome::of(Cause::NotAnObject, inputs),
            }
        }
        Kind::List { every, path, inner } => {
            let width = inner.input_names().len();
            let items = match read(subject, path) {
                Read::Found(Value::Array(items)) => Ok(items),
                Read::Found(_) | Read::Unusable => Err(Cause::Unusable),
                Read::Null => Err(Cause::Null),
                Read::Absent => Err(Cause::Absent),
                Read::NotAnObject => Err(Cause::NotAnObject),
            };
            let items = match items {
                Ok(items) => items,
                Err(cause) => {
                    let inputs = vec![json!([]); width];
                    return Outcome { failed_items: Some(vec![]), ..Outcome::of(cause, inputs) };
                }
            };
            let outcomes: Vec<Outcome> = items.iter().map(|item| evaluate_check(inner, item, sources)).collect();
            let inputs = (0..width).map(|i| outcomes.iter().map(|o| o.inputs[i].clone()).collect()).collect();
            let passed = !items.is_empty()
                && if *every { outcomes.iter().all(|o| o.passed) } else { outcomes.iter().any(|o| o.passed) };
            if passed || items.is_empty() {
                let cause = if passed { Cause::Satisfied } else { Cause::Value };
                return Outcome { failed_items: Some(vec![]), ..Outcome::of(cause, inputs) };
            }
            let list = path_name(path);
            let failed: Vec<(usize, &Value, Cause)> = items
                .iter()
                .zip(&outcomes)
                .enumerate()
                .filter(|(_, (_, o))| !o.passed)
                .map(|(i, (item, o))| (i, item, o.cause))
                .collect();
            let cause = failed.iter().map(|f| f.2).min().unwrap_or(Cause::Value);
            let failed_items = failed
                .into_iter()
                .map(|(i, item, c)| json!({"path": format!("{list}[{i}]"), "cause": c.name(), "value": item}))
                .collect();
            Outcome { failed_items: Some(failed_items), ..Outcome::of(cause, inputs) }
        }
    }
}

fn named_inputs(check: &Check, values: Vec<Value>) -> Vec<Value> {
    check.input_names().into_iter().zip(values).map(|(n, v)| json!({"name": n, "value": v})).collect()
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

fn refs_entry(refs: Vec<&[Value]>, sources: &Sources) -> Option<Value> {
    let mut named: Vec<(String, Value)> = refs.into_iter().map(|r| (path_name(r), sources.read_ref(r).shown())).collect();
    named.sort_by(|a, b| a.0.cmp(&b.0));
    named.dedup_by(|a, b| a.0 == b.0);
    (!named.is_empty()).then(|| named.into_iter().map(|(n, v)| json!({"name": n, "value": v})).collect())
}

const WELL_FORMED_EXPRESSION: &str = "fields are known and have the right types and count(checks) >= 1 and require in [\"every\", \"some\"] and steps are keys and numbers fit a float and checks are written right";

type Named<'a> = Vec<(&'a str, &'a Value, Option<Check<'a>>)>;

fn named_checks(v: Option<&Value>) -> Option<Named<'_>> {
    match v {
        None => Some(vec![]),
        Some(Value::Object(m)) => Some(m.iter().map(|(k, c)| (k.as_str(), c, parse(c, false))).collect()),
        Some(_) => None,
    }
}

struct Requirement<'a> {
    name: &'a str,
    raw: &'a Map<String, Value>,
    subject_type: String,
    from: &'a [Value],
    id: &'a [Value],
    require: &'a str,
    min_subjects: u64,
    checks: Named<'a>,
    filters: Named<'a>,
    well_formed: bool,
}

fn requirement<'a>(name: &'a str, raw: &'a Map<String, Value>) -> Requirement<'a> {
    const KNOWN: [&str; 9] = ["subject_type", "from", "id", "checks", "applies_to", "require", "min_subjects", "description", "meta"];
    let from = key_path(raw.get("from"));
    let id = key_path(raw.get("id"));
    let checks = match raw.get("checks") {
        None => None,
        some => named_checks(some),
    };
    let filters = named_checks(raw.get("applies_to"));
    let subject_type = raw.get("subject_type").and_then(Value::as_str);
    let require = match raw.get("require") {
        None => Some("every"),
        Some(v) => v.as_str().filter(|r| ["every", "some"].contains(r)),
    };
    let min_subjects = match raw.get("min_subjects") {
        None => Some(1),
        Some(v) => v.as_u64(),
    };
    let all_parsed = |n: &Option<Named>| n.as_ref().is_some_and(|n| n.iter().all(|c| c.2.is_some()));
    let well_formed = raw.keys().all(|k| KNOWN.contains(&k.as_str()))
        && subject_type.is_some_and(|s| !s.is_empty())
        && from.is_some()
        && id.is_some()
        && require.is_some()
        && min_subjects.is_some()
        && checks.as_ref().is_some_and(|c| !c.is_empty())
        && all_parsed(&checks)
        && all_parsed(&filters)
        && described(raw);
    Requirement {
        name,
        raw,
        subject_type: subject_type.unwrap_or("").to_string(),
        from: from.unwrap_or(&[]),
        id: id.unwrap_or(&[]),
        require: require.unwrap_or("every"),
        min_subjects: min_subjects.unwrap_or(1),
        checks: checks.unwrap_or_default(),
        filters: filters.unwrap_or_default(),
        well_formed,
    }
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

fn verdict(passed: bool) -> Cause {
    if passed { Cause::Satisfied } else { Cause::Value }
}

struct Row {
    check: String,
    id: Value,
    inputs: Vec<Value>,
    passed: bool,
    cause: Cause,
    failed_items: Option<Vec<Value>>,
}

impl Row {
    fn json(&self, req: &str, subject_type: &str) -> Value {
        let mut row = json!({
            "requirement": req,
            "subject": {"type": subject_type, "id": self.id},
            "check": self.check,
            "inputs": self.inputs,
            "passed": self.passed,
            "cause": self.cause.name(),
        });
        if let Some(items) = &self.failed_items {
            row["failed_items"] = json!(items);
        }
        row
    }

    fn builtin(check: &str, inputs: Vec<Value>, passed: bool, cause: Cause) -> Row {
        Row { check: check.into(), id: Value::Null, inputs, passed, cause, failed_items: None }
    }
}

fn scope_cause(failed: &[Outcome]) -> Cause {
    if failed.iter().any(|o| o.cause == Cause::IllFormed) {
        Cause::IllFormed
    } else if failed.iter().any(|o| o.answered_missing) {
        Cause::Value
    } else {
        failed.iter().map(|o| o.cause).min().unwrap_or(Cause::Value)
    }
}

struct Evaluated<'a> {
    req: Requirement<'a>,
    total: usize,
    matching: usize,
    builtins: [Row; 3],
    applies: Vec<Row>,
    rows: Vec<Row>,
    status: &'static str,
}

fn evaluate<'a>(name: &'a str, raw: &'a Map<String, Value>, sources: &Sources<'a>) -> Evaluated<'a> {
    let req = requirement(name, raw);
    let (all_subjects, from_problem) = subjects(sources.document, req.from);
    let repeated_ids = repeated(all_subjects.iter().map(|s| subject_id(s, req.id)).collect());
    let mut applies = vec![];
    let mut in_scope = vec![];
    let mut scope_readable = true;
    for subject in &all_subjects {
        if req.filters.is_empty() {
            in_scope.push(*subject);
            continue;
        }
        let outcomes: Vec<Outcome> = req
            .filters
            .iter()
            .map(|(_, _, f)| match f {
                Some(f) => evaluate_check(f, subject, sources),
                None => Outcome::of(Cause::IllFormed, vec![]),
            })
            .collect();
        let passed = outcomes.iter().all(|o| o.passed);
        let inputs = req
            .filters
            .iter()
            .zip(&outcomes)
            .flat_map(|((_, _, f), o)| f.as_ref().map(|f| named_inputs(f, o.inputs.clone())).unwrap_or_default())
            .collect();
        let failed: Vec<Outcome> = outcomes.into_iter().filter(|o| !o.passed).collect();
        let cause = if passed { Cause::Satisfied } else { scope_cause(&failed) };
        scope_readable &= matches!(cause, Cause::Satisfied | Cause::Value);
        if passed {
            in_scope.push(*subject);
        }
        applies.push(Row { check: "$applies".into(), id: subject_id(subject, req.id), inputs, passed, cause, failed_items: None });
    }
    let mut rows = vec![];
    let mut subjects_passing = 0;
    for subject in &in_scope {
        let mut all_passed = true;
        for (check_name, _, check) in &req.checks {
            let outcome = match check {
                Some(c) if req.well_formed => {
                    let o = evaluate_check(c, subject, sources);
                    Outcome { inputs: named_inputs(c, o.inputs), ..o }
                }
                _ => Outcome::of(Cause::IllFormed, vec![]),
            };
            all_passed &= outcome.passed;
            rows.push(Row {
                check: (*check_name).into(),
                id: subject_id(subject, req.id),
                inputs: outcome.inputs,
                passed: outcome.passed,
                cause: outcome.cause,
                failed_items: outcome.failed_items,
            });
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
        Row::builtin("$well_formed", vec![json!({"name": "count(checks)", "value": req.checks.len()}), json!({"name": "require", "value": req.require})], req.well_formed, verdict(req.well_formed)),
        Row::builtin("$min_subjects", vec![json!({"name": format!("in-scope {t} count"), "value": matching})], enough, from_problem.unwrap_or(verdict(enough))),
        Row::builtin("$unique_ids", vec![json!({"name": format!("repeated {t} ids"), "value": repeated_ids})], unique, verdict(unique)),
    ];
    let checks_hold = match req.require {
        "some" => subjects_passing > 0,
        _ => subjects_passing == matching,
    };
    let holds = req.well_formed && enough && unique && scope_readable && checks_hold;
    let status = match (holds, matching == 0) {
        (true, false) => "met",
        (true, true) => "not_applicable",
        _ => "not_met",
    };
    Evaluated { total: all_subjects.len(), matching, req, builtins, applies, rows, status }
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
    if !r.filters.is_empty() {
        let parsed: Vec<&Check> = r.filters.iter().filter_map(|f| f.2.as_ref()).collect();
        let expression = parsed.iter().map(|f| f.expression()).collect::<Vec<_>>().join(" and ");
        let mut def = json!({"description": format!("The {t} is in scope"), "expression": expression, "meta": {}});
        if let Some(refs) = refs_entry(parsed.iter().flat_map(|f| f.refs()).collect(), sources) {
            def["$refs"] = refs;
        }
        defs.insert("$applies".into(), def);
    }
    for (name, raw, check) in &r.checks {
        let Some(c) = raw.as_object() else { continue };
        let mut def = c.clone();
        def.insert("description".into(), reported_description(c));
        def.insert("meta".into(), reported_meta(c));
        if let Some(check) = check {
            def.insert("expression".into(), json!(check.expression()));
            if let Some(refs) = refs_entry(check.refs(), sources) {
                def.insert("$refs".into(), refs);
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
                "checks": definitions(e, &sources),
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
