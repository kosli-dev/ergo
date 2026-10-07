use crate::render::{LEAF_OPS, combinator, is_key, is_literal, is_operator, is_ref, malformed, out_of_range, path_name, quantified, text, two_sided, unliteral, valid_name, written};
use serde_json::{Map, Value, json};
use std::collections::BTreeSet;

fn required_fields(op: &str) -> &'static [&'static str] {
    match op {
        "range" => &["path", "min", "max"],
        "excludes" | "includes" | "present" | "missing" | "non_empty_string" | "empty" => &["path"],
        "in" => &["path", "values"],
        "equals" => &["path", "value"],
        "matches_any" | "not_matches_any" => &["path", "patterns"],
        "compare" | "compare_time" => &["left", "right", "cmp"],
        "all" | "any" => &["path", "check"],
        "any_of" => &["options"],
        _ => &[],
    }
}

fn op_fields(op: &str) -> Option<Vec<&'static str>> {
    if !is_operator(op) {
        return None;
    }
    let mut f = required_fields(op).to_vec();
    match op {
        "excludes" | "includes" => f.extend(["value", "values"]),
        "all" | "any" => f.extend(["each", "as"]),
        _ => {}
    }
    Some(f)
}

pub fn json_problems(v: &Value) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    if out_of_range(v) {
        out.insert("number out of range".to_string());
    }
    out
}

fn value_list(v: Option<&Value>) -> bool {
    matches!(v, Some(Value::Array(_)))
}

fn valid_pattern(p: Option<&Value>) -> bool {
    p.and_then(Value::as_str).is_some_and(|s| regex::Regex::new(s).is_ok())
}

fn names_of(v: &Value) -> Vec<(Value, &Value)> {
    match v {
        Value::Object(m) => m.iter().map(|(k, x)| (json!(k), x)).collect(),
        Value::Array(a) => a.iter().enumerate().map(|(i, x)| (json!(i), x)).collect(),
        _ => vec![],
    }
}

fn walk<'a>(v: &'a Value, path: &mut Vec<Value>, out: &mut Vec<(Vec<Value>, &'a Value)>) {
    out.push((path.clone(), v));
    for (k, x) in names_of(v) {
        path.push(k);
        walk(x, path, out);
        path.pop();
    }
}

fn walked(v: &Value) -> Vec<(Vec<Value>, &Value)> {
    let mut out = vec![];
    walk(v, &mut vec![], &mut out);
    out
}

fn at<'a>(v: &'a Value, path: &[Value]) -> Option<&'a Value> {
    path.iter().try_fold(v, |x, k| match (x, k) {
        (Value::Object(m), Value::String(s)) => m.get(s),
        (Value::Array(a), Value::Number(n)) => a.get(n.as_u64()? as usize),
        _ => None,
    })
}

fn under(v: &Value, p: &[Value], wrapped: fn(&Value) -> bool) -> bool {
    (0..p.len()).any(|i| at(v, &p[..i]).is_some_and(wrapped))
}

fn wrapper(x: &Value) -> Option<&'static str> {
    if is_ref(x) {
        Some("ref")
    } else if is_literal(x) {
        Some("literal")
    } else {
        None
    }
}

pub fn wrapped_in_where(path: &Value) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let Some(p) = path.as_array() else { return out };
    for seg in p {
        let Some(Value::Object(w)) = seg.get("where").filter(|_| seg.is_object()) else { continue };
        for (_, v) in w {
            for (q, x) in walked(v) {
                if q.is_empty() {
                    continue;
                }
                if let Some(kind) = wrapper(x) {
                    if !under(v, &q, is_literal) && !under(v, &q, is_ref) {
                        out.insert(kind.to_string());
                    }
                }
            }
        }
    }
    out
}

pub fn bad_step(seg: &Value) -> bool {
    (!seg.is_object() && !is_key(seg)) || (is_literal(seg) && !is_key(unliteral(seg)))
}

pub fn badly_stepped(p: &Value) -> bool {
    match p {
        Value::Array(steps) => steps.iter().any(bad_step),
        other => bad_step(other),
    }
}

fn own_paths<'a>(node: &'a Map<String, Value>, f: &str) -> Vec<&'a Value> {
    if f != "inputs" {
        return node.get(f).into_iter().collect();
    }
    match node.get("inputs") {
        Some(Value::Array(specs)) => specs
            .iter()
            .flat_map(|s| match s {
                Value::Object(o) => vec![o.get("path").unwrap_or(&EMPTY), o.get("each").unwrap_or(&EMPTY)],
                other => vec![other],
            })
            .collect(),
        _ => vec![],
    }
}

static EMPTY: Value = Value::Array(vec![]);

pub fn known_ref(r: &Value) -> bool {
    let Some(p) = r.as_array() else { return false };
    matches!(p.first().and_then(Value::as_str), Some("$$input" | "$$params")) && p[1..].iter().all(|s| is_key(unliteral(s)))
}

pub fn check_refs(v: &Value) -> Vec<Value> {
    let mut out = vec![];
    for (p, x) in walked(v) {
        if under(v, &p, is_literal) && p.iter().any(|s| s == "literal") {
            continue;
        }
        if let Some(r) = x.as_object().filter(|_| is_ref(x)).and_then(|m| m.get("ref")) {
            out.push(r.clone());
        } else if malformed(x) {
            out.push(json!("<invalid ref>"));
        }
    }
    out
}

fn own_fields(node: &Map<String, Value>) -> Value {
    let mut m = node.clone();
    for f in ["check", "options", "substitute"] {
        m.remove(f);
    }
    Value::Object(m)
}

fn allowed_ops(kinds: &[&str]) -> Vec<&'static str> {
    let mut leaf_and = |extra: &[&'static str]| -> Vec<&'static str> {
        let mut v = LEAF_OPS.to_vec();
        v.extend(extra);
        v
    };
    let Some(last) = kinds.last() else {
        return leaf_and(&["all", "any", "any_of"]);
    };
    let checks = kinds.iter().filter(|k| **k == "check").count();
    match (*last, checks) {
        ("option", 0 | 1) => leaf_and(&["all", "any"]),
        ("option", 2) => leaf_and(&[]),
        ("check", 1) => leaf_and(&["all", "any", "any_of"]),
        ("check", 2) => leaf_and(&["any_of"]),
        _ => vec![],
    }
}

fn too_deep(node: &Value, kinds: &[&str]) -> bool {
    quantified(node) && !allowed_ops(kinds).contains(&node["op"].as_str().unwrap_or(""))
}

struct Node<'a> {
    check: &'a Value,
    loc: Vec<Value>,
    kinds: Vec<&'static str>,
    names: Vec<String>,
}

fn children<'a>(node: &Node<'a>) -> Vec<Node<'a>> {
    let mut out = vec![];
    let c = node.check;
    if too_deep(c, &node.kinds) {
        return out;
    }
    if quantified(c) {
        if let Some(inner) = c.get("check") {
            let mut names = node.names.clone();
            if let Some(n) = valid_name(c.get("as")) {
                names.push(n.to_string());
            }
            let mut kinds = node.kinds.clone();
            kinds.push("check");
            let mut loc = node.loc.clone();
            loc.push(json!("check"));
            out.push(Node { check: inner, loc, kinds, names });
        }
    }
    if combinator(c) && matches!(c.get("options"), Some(Value::Object(_) | Value::Array(_))) {
        for (nm, group) in names_of(&c["options"]) {
            let Value::Array(leaves) = group else { continue };
            for (i, leaf) in leaves.iter().enumerate() {
                let mut kinds = node.kinds.clone();
                kinds.push("option");
                let mut loc = node.loc.clone();
                loc.extend([json!("options"), nm.clone(), json!(i)]);
                out.push(Node { check: leaf, loc, kinds, names: node.names.clone() });
            }
        }
    }
    out
}

fn nodes<'a>(check: &'a Value, names: &[String]) -> Vec<Node<'a>> {
    let mut all = vec![];
    let mut level = vec![Node { check, loc: vec![], kinds: vec![], names: names.to_vec() }];
    for _ in 0..6 {
        let next: Vec<Node> = level.iter().flat_map(children).collect();
        all.extend(level);
        level = next;
    }
    if let Some(s) = check.as_object().and_then(|m| m.get("substitute")) {
        let mut sub = vec![Node { check: s, loc: vec![json!("substitute")], kinds: vec![], names: names.to_vec() }];
        for _ in 0..6 {
            let next: Vec<Node> = sub.iter().flat_map(children).collect();
            all.extend(sub);
            sub = next;
        }
    }
    all
}

fn node_problems(node: &Node) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let Some(m) = node.check.as_object() else {
        out.insert("invalid check".into());
        return out;
    };
    let op = m.get("op");
    let op_str = op.and_then(Value::as_str).filter(|o| is_operator(o));
    match op {
        None => {
            out.insert("missing op".into());
        }
        Some(o) if op_str.is_none() => {
            out.insert(format!("unknown op {}", text(o)));
        }
        _ => {}
    }
    if too_deep(node.check, &node.kinds) {
        out.insert("nested too deep".into());
    }
    if let Some(o) = op_str {
        if !quantified(node.check) && !allowed_ops(&node.kinds).contains(&o) {
            out.insert(format!("{o} can't go here"));
        }
    }
    let op = op_str.unwrap_or("");
    let has = |f: &str| m.contains_key(f);
    if let Some(d) = m.get("description") {
        if !matches!(d, Value::String(_) | Value::Null) {
            out.insert("invalid description".into());
        }
    }
    if let Some(meta) = m.get("meta") {
        if !matches!(meta, Value::Object(_) | Value::Null) {
            out.insert("invalid meta".into());
        }
    }
    if let Some(fields) = op_fields(op) {
        for f in m.keys() {
            if !fields.contains(&f.as_str()) && !["op", "description", "meta", "expression", "substitute", "inputs", "as", "each"].contains(&f.as_str()) {
                out.insert(format!("unknown field {f}"));
            }
        }
    }
    for f in required_fields(op) {
        if !has(f) {
            out.insert(format!("missing {f}"));
        }
    }
    if op == "range" {
        for f in ["min", "max"] {
            if let Some(v) = m.get(f).and_then(written) {
                if !v.is_number() {
                    out.insert(format!("invalid {f}"));
                }
            }
        }
        if let (Some(Value::Number(lo)), Some(Value::Number(hi))) = (m.get("min").and_then(written), m.get("max").and_then(written)) {
            if crate::value::number_order(lo, hi) == Some(std::cmp::Ordering::Greater) {
                out.insert("min above max".into());
            }
        }
    }
    if ["in", "includes", "excludes"].contains(&op) {
        if let Some(v) = m.get("values") {
            if !value_list(written(v)) && !is_ref(v) && !malformed(v) {
                out.insert("invalid values".into());
            }
            if op != "in" && written(v).and_then(Value::as_array).is_some_and(Vec::is_empty) {
                out.insert("empty values".into());
            }
        }
    }
    if ["includes", "excludes"].contains(&op) {
        match (has("value"), has("values")) {
            (false, false) => {
                out.insert("missing value or values".into());
            }
            (true, true) => {
                out.insert("both value and values".into());
            }
            _ => {}
        }
    }
    if ["matches_any", "not_matches_any"].contains(&op) {
        if let Some(v) = m.get("patterns") {
            let ok = match written(v) {
                Some(Value::Array(ps)) => ps.iter().all(|p| is_ref(p) || valid_pattern(written(p))),
                _ => false,
            };
            if !is_ref(v) && !malformed(v) && !ok {
                out.insert("invalid patterns".into());
            }
        }
    }
    if LEAF_OPS.contains(&op) {
        for f in ["value", "values", "patterns", "min", "max"] {
            let Some(v) = m.get(f) else { continue };
            for (p, x) in walked(v) {
                let Some(kind) = wrapper(x) else { continue };
                let read_at = p.is_empty() || (p.len() == 1 && ["values", "patterns"].contains(&f) && value_list(Some(v)));
                if !read_at && !under(v, &p, is_literal) && !under(v, &p, is_ref) {
                    out.insert(format!("{kind} inside {f}"));
                }
            }
        }
    }
    for f in ["path", "left", "right", "each", "inputs"] {
        for p in own_paths(m, f) {
            for kind in wrapped_in_where(p) {
                out.insert(format!("{kind} inside where"));
            }
        }
    }
    if two_sided(node.check) {
        if let Some(c) = m.get("cmp") {
            if !["eq", "ne", "gt", "gte", "lt", "lte"].iter().any(|x| c == *x) {
                out.insert("invalid cmp".into());
            }
        }
    }
    if LEAF_OPS.contains(&op) || op == "any_of" {
        for f in ["as", "each"] {
            if has(f) {
                out.insert(format!("{f} can't go here"));
            }
        }
    }
    if quantified(node.check) && has("each") && !matches!(m["each"], Value::Array(_) | Value::String(_)) {
        out.insert("invalid each".into());
    }
    if combinator(node.check) {
        match m.get("options") {
            Some(o @ (Value::Object(_) | Value::Array(_))) => {
                if names_of(o).is_empty() {
                    out.insert("empty options".into());
                }
                for (nm, group) in names_of(o) {
                    if !matches!(group, Value::Array(a) if !a.is_empty()) {
                        out.insert(format!("empty option {}", text(&nm)));
                    }
                }
            }
            Some(_) => {
                out.insert("invalid options".into());
            }
            None => {}
        }
    }
    let own = own_fields(m);
    if out_of_range(&own) {
        out.insert("number out of range".into());
    }
    if check_refs(&own).iter().any(|r| !known_ref(r)) {
        out.insert("invalid ref".into());
    }
    for f in ["path", "left", "right", "each", "inputs"] {
        if own_paths(m, f).iter().any(|p| badly_stepped(p)) {
            out.insert(format!("step that can't be a key in {f}"));
        }
    }
    if quantified(node.check) {
        if let Some(a) = m.get("as") {
            match valid_name(Some(a)) {
                None => {
                    out.insert("invalid name".into());
                }
                Some(n) if node.names.iter().any(|g| g == n) => {
                    out.insert("name given twice".into());
                }
                _ => {}
            }
        }
    }
    for f in ["path", "left", "right", "each", "inputs"] {
        for p in own_paths(m, f) {
            let Some(first) = p.as_array().and_then(|a| a.first()).and_then(Value::as_str).filter(|s| s.starts_with('$')) else { continue };
            let known = first == "$$input" || first == "$$params" || (!first.starts_with("$$") && node.names.iter().any(|n| n == &first[1..]));
            if !known {
                out.insert(format!("unknown name {first}"));
            }
        }
    }
    out
}

pub fn check_problems(check: &Value, names: &[String]) -> Vec<(Vec<Value>, String)> {
    let mut out = vec![];
    for node in nodes(check, names) {
        for msg in node_problems(&node) {
            out.push((node.loc.clone(), msg));
        }
    }
    out
}

pub fn check_problem_inputs(req: &Map<String, Value>, names: &[String]) -> Vec<Value> {
    let mut grouped: std::collections::BTreeMap<String, BTreeSet<String>> = Default::default();
    for f in ["applies_to", "checks"] {
        let Some(Value::Object(checks)) = req.get(f) else { continue };
        for (n, check) in checks {
            for (loc, msg) in check_problems(check, names) {
                let mut p = vec![json!(f), json!(n)];
                p.extend(loc);
                grouped.entry(path_name(&Value::Array(p)).unwrap_or_default()).or_default().insert(msg);
            }
        }
    }
    grouped.into_iter().map(|(name, msgs)| json!({"name": name, "value": msgs.into_iter().collect::<Vec<_>>()})).collect()
}

pub struct Shape<'a> {
    pub stepped: bool,
    pub step: Option<&'a Map<String, Value>>,
}

pub fn shape(req: &Map<String, Value>) -> Shape<'_> {
    let step = req
        .get("from")
        .and_then(Value::as_array)
        .and_then(|f| f.last())
        .and_then(Value::as_object)
        .filter(|s| !is_ref(&Value::Object((*s).clone())) && !is_literal(&Value::Object((*s).clone())));
    Shape { stepped: step.is_some(), step }
}

pub fn keys_well_formed(step: &Map<String, Value>) -> bool {
    match step.get("keys") {
        None => true,
        Some(Value::Array(ks)) => ks.iter().all(|k| !malformed(k)),
        Some(k) if is_ref(k) => true,
        Some(k) if is_literal(k) => k.get("literal").is_some_and(Value::is_array),
        _ => false,
    }
}

pub fn from_well_formed(req: &Map<String, Value>) -> bool {
    let Some(Value::Array(from)) = req.get("from").or(Some(&EMPTY)) else { return false };
    match shape(req).step {
        None => true,
        Some(step) => {
            from[..from.len() - 1].iter().all(|s| !s.is_object() || is_literal(s))
                && step.keys().all(|k| k == "each_as" || k == "keys")
                && valid_name(step.get("each_as")).is_some()
                && keys_well_formed(step)
        }
    }
}

pub fn req_problems(req: &Map<String, Value>) -> Vec<(String, String)> {
    let mut out: BTreeSet<(String, String)> = BTreeSet::new();
    let wrong = |f: &str, v: &Value| -> bool {
        match f {
            "applies_to" | "checks" => !v.is_object(),
            "from" | "id" => !v.is_array(),
            "min_subjects" => !(v.as_f64().is_some_and(|n| n >= 0.0 && n.fract() == 0.0) && !out_of_range(v)),
            "subject_type" => !v.as_str().is_some_and(|s| !s.trim().is_empty()),
            "description" => !matches!(v, Value::String(_) | Value::Null),
            "meta" => !matches!(v, Value::Object(_) | Value::Null),
            _ => false,
        }
    };
    let messages = [
        ("applies_to", "not an object"),
        ("checks", "not an object"),
        ("from", "not a list"),
        ("id", "not a list"),
        ("min_subjects", "not a whole number of 0 or more"),
        ("subject_type", "empty or not a string"),
        ("description", "not a string"),
        ("meta", "not an object"),
    ];
    for (f, msg) in messages {
        if let Some(v) = req.get(f) {
            if wrong(f, v) && !(f == "min_subjects" && v.is_number() && out_of_range(v)) {
                out.insert((f.into(), msg.into()));
            }
        }
    }
    if let Some(v) = req.get("min_subjects") {
        if v.is_number() && out_of_range(v) {
            out.insert(("min_subjects".into(), "number out of range".into()));
        }
    }
    if let Some(Value::Object(meta)) = req.get("meta") {
        for p in json_problems(&Value::Object(meta.clone())) {
            out.insert(("meta".into(), p));
        }
    }
    const KNOWN: [&str; 9] = ["applies_to", "checks", "from", "id", "min_subjects", "subject_type", "description", "meta", "require"];
    for f in req.keys() {
        if !KNOWN.contains(&f.as_str()) {
            out.insert((f.clone(), "unknown field".into()));
        }
    }
    match req.get("checks") {
        None => {
            out.insert(("checks".into(), "missing".into()));
        }
        Some(Value::Object(c)) if c.is_empty() => {
            out.insert(("checks".into(), "empty".into()));
        }
        _ => {}
    }
    if !matches!(req.get("require").map(Value::as_str), None | Some(Some("every" | "some"))) {
        out.insert(("require".into(), "neither every nor some".into()));
    }
    for f in ["from", "id"] {
        if let Some(p @ Value::Array(_)) = req.get(f) {
            if badly_stepped(p) {
                out.insert((f.into(), "step that can't be a key".into()));
            }
            if out_of_range(p) {
                out.insert((f.into(), "number out of range".into()));
            }
        }
    }
    if let Some(Value::Array(from)) = req.get("from") {
        for (i, seg) in from.iter().enumerate() {
            let Value::Object(s) = seg else { continue };
            if is_ref(seg) {
                continue;
            }
            if i + 1 != from.len() {
                out.insert(("from".into(), "object step before the last".into()));
                continue;
            }
            if !s.contains_key("each_as") {
                out.insert(("from".into(), "object step without each_as".into()));
                continue;
            }
            for k in s.keys() {
                if k != "each_as" && k != "keys" {
                    out.insert(("from".into(), format!("unknown field {k} in naming step")));
                }
            }
            if valid_name(s.get("each_as")).is_none() {
                out.insert(("from".into(), "invalid name".into()));
            }
            if !keys_well_formed(s) {
                out.insert(("from".into(), "invalid keys".into()));
            }
        }
    }
    if let Some(id) = req.get("id") {
        for kind in wrapped_in_where(id) {
            out.insert(("id".into(), format!("{kind} inside where")));
        }
    }
    out.into_iter().collect()
}

pub fn field_problem_inputs(req: &Map<String, Value>) -> Vec<Value> {
    let mut grouped: std::collections::BTreeMap<String, Vec<String>> = Default::default();
    for (f, msg) in req_problems(req) {
        grouped.entry(f).or_default().push(msg);
    }
    grouped
        .into_iter()
        .map(|(f, mut msgs)| {
            msgs.sort();
            json!({"name": path_name(&json!([f])).unwrap_or_default(), "value": msgs})
        })
        .collect()
}

pub fn has_problems(req: &Map<String, Value>, f: &str) -> bool {
    req_problems(req).iter().any(|(g, _)| g == f)
}

pub fn requirement_well_formed(req: &Map<String, Value>, names: &[String]) -> bool {
    let typed = req_problems(req).iter().all(|(f, msg)| {
        !(["applies_to", "checks", "from", "id", "min_subjects", "subject_type", "description", "meta"].contains(&f.as_str())
            && (msg.starts_with("not ") || msg.starts_with("empty or")))
    });
    let unknown = req.keys().all(|k| ["applies_to", "checks", "from", "id", "min_subjects", "subject_type", "description", "meta", "require"].contains(&k.as_str()));
    let checks = matches!(req.get("checks"), Some(Value::Object(c)) if !c.is_empty());
    let require = matches!(req.get("require").map(Value::as_str), None | Some(Some("every" | "some")));
    let from = req.get("from").unwrap_or(&EMPTY);
    let id = req.get("id").unwrap_or(&EMPTY);
    let min = req.get("min_subjects").cloned().unwrap_or(json!(1));
    let meta_ok = match req.get("meta") {
        Some(Value::Object(m)) => json_problems(&Value::Object(m.clone())).is_empty(),
        _ => true,
    };
    typed
        && meta_ok
        && unknown
        && checks
        && require
        && from_well_formed(req)
        && !out_of_range(&json!([from, id, min]))
        && !badly_stepped(from)
        && !badly_stepped(id)
        && wrapped_in_where(id).is_empty()
        && check_problem_inputs(req, names).is_empty()
}
