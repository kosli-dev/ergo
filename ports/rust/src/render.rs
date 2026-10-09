use crate::path::{Ctx, Read, index_key};
use crate::value::rego_order;
use serde_json::{Map, Value, json};

pub const LEAF_OPS: [&str; 13] = [
    "range", "excludes", "includes", "in", "equals", "present", "missing", "non_empty_string", "empty", "matches_any", "not_matches_any", "compare", "compare_time",
];

pub fn is_builtin(op: &str) -> bool {
    LEAF_OPS.contains(&op) || ["all", "any", "any_of"].contains(&op)
}

pub fn is_operator(op: &str) -> bool {
    is_builtin(op) || crate::operators::find(op).is_some()
}

pub fn is_leaf(op: &str) -> bool {
    LEAF_OPS.contains(&op) || (!is_builtin(op) && crate::operators::find(op).is_some())
}

fn custom_text(check: &Value, item: &str, def: &crate::operators::Definition) -> Option<String> {
    let arg = |p: &crate::operators::Param| -> Option<String> {
        if p.kind == crate::operators::Kind::Path {
            path_text(item, check, &p.name)
        } else if p.kind == crate::operators::Kind::Paths {
            match check.get(&p.name) {
                Some(Value::Array(ps)) => Some(format!("[{}]", ps.iter().map(|x| item_path_name(item, x)).collect::<Option<Vec<_>>>()?.join(", "))),
                Some(_) => Some(format!("<invalid {}>", p.name)),
                None => Some(format!("<missing {}>", p.name)),
            }
        } else {
            Some(param_text(check, &p.name))
        }
    };
    match &def.template {
        Some(t) => {
            let mut out = t.clone();
            for p in &def.params {
                out = out.replace(&format!("{{{}}}", p.name), &arg(p)?);
            }
            Some(out)
        }
        None => Some(format!("{}({})", def.name, def.params.iter().map(arg).collect::<Option<Vec<_>>>()?.join(", "))),
    }
}

fn custom_paths(check: &Value) -> Vec<&Value> {
    let Some(def) = op_of(check).filter(|o| !is_builtin(o)).and_then(crate::operators::find) else { return vec![] };
    let mut out = vec![];
    for p in &def.params {
        match (p.kind, check.get(&p.name)) {
            (crate::operators::Kind::Path, Some(v)) => out.push(v),
            (crate::operators::Kind::Paths, Some(Value::Array(ps))) => out.extend(ps.iter()),
            _ => {}
        }
    }
    out
}

pub fn truthy(v: Option<&Value>) -> bool {
    !matches!(v, None | Some(Value::Bool(false)))
}

pub fn op_of(check: &Value) -> Option<&str> {
    check.get("op").and_then(Value::as_str)
}

pub fn quantified(check: &Value) -> bool {
    matches!(check.get("op").and_then(Value::as_str), Some("all" | "any"))
}

pub fn combinator(check: &Value) -> bool {
    check.get("op").and_then(Value::as_str) == Some("any_of")
}

pub fn two_sided(check: &Value) -> bool {
    matches!(check.get("op").and_then(Value::as_str), Some("compare" | "compare_time"))
}

fn only_key<'a>(x: &'a Value, key: &str) -> Option<&'a Value> {
    match x {
        Value::Object(m) if m.len() == 1 => m.get(key),
        _ => None,
    }
}

pub fn is_ref(x: &Value) -> bool {
    only_key(x, "ref").is_some()
}

pub fn is_literal(x: &Value) -> bool {
    only_key(x, "literal").is_some()
}

pub fn malformed(x: &Value) -> bool {
    matches!(x, Value::Object(m) if (m.contains_key("ref") || m.contains_key("literal")) && m.len() > 1)
}

pub fn written(x: &Value) -> Option<&Value> {
    if let Some(l) = only_key(x, "literal") {
        return Some(l);
    }
    (!is_ref(x) && !malformed(x)).then_some(x)
}

pub fn unliteral(x: &Value) -> &Value {
    only_key(x, "literal").unwrap_or(x)
}

pub fn number_text(t: &str) -> String {
    let re = regex::Regex::new(r"^(-?)([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$").unwrap();
    let Some(m) = re.captures(t) else { return t.to_string() };
    let sign = &m[1];
    let int = &m[2];
    let frac = m.get(3).map_or("", |x| x.as_str());
    let exp: i64 = m.get(4).map_or(0, |x| x.as_str().trim_start_matches('+').parse().unwrap_or(0));
    let digits = format!("{int}{frac}");
    let point = int.len() as i64 + exp;
    let left = (1 - point).max(0);
    let right = (point - digits.len() as i64).max(0);
    let padded = format!("{}{}{}", "0".repeat(left as usize), digits, "0".repeat(right as usize));
    let split = (point + left) as usize;
    let whole = padded[..split].trim_start_matches('0');
    let fraction = padded[split..].trim_end_matches('0');
    let n = match (whole, fraction) {
        ("", "") => "0".to_string(),
        (w, "") => w.to_string(),
        ("", f) => format!("0.{f}"),
        (w, f) => format!("{w}.{f}"),
    };
    if n == "0" { n } else { format!("{sign}{n}") }
}

fn fits_a_float(n: &serde_json::Number) -> bool {
    match n.as_f64() {
        Some(f) if f == 0.0 => true,
        Some(f) => f.is_finite() && f.abs() >= 2.2250738585072014e-308,
        None => false,
    }
}

pub fn out_of_range(v: &Value) -> bool {
    match v {
        Value::Number(n) => !fits_a_float(n),
        Value::Array(a) => a.iter().any(out_of_range),
        Value::Object(m) => m.values().any(out_of_range),
        _ => false,
    }
}

pub fn json_text(v: &Value) -> String {
    match v {
        Value::Number(n) => number_text(&n.to_string()),
        Value::Array(items) => format!("[{}]", items.iter().map(json_text).collect::<Vec<_>>().join(", ")),
        Value::Object(m) => format!(
            "{{{}}}",
            m.iter().map(|(k, v)| format!("{}: {}", Value::String(k.clone()), json_text(v))).collect::<Vec<_>>().join(", ")
        ),
        other => other.to_string(),
    }
}

pub fn literal_text(v: &Value) -> String {
    if out_of_range(v) { "<number out of range>".into() } else { json_text(v) }
}

pub fn text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => literal_text(other),
    }
}

fn plain_key(k: &str) -> bool {
    let mut chars = k.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_' || c == '$')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '$' || c == '-')
}

pub fn is_key(k: &Value) -> bool {
    match k {
        Value::String(_) => true,
        Value::Number(n) => index_key(n) && fits_a_float(n),
        _ => false,
    }
}

pub fn key_name(k: &Value) -> String {
    match k {
        Value::String(s) if plain_key(s) => s.clone(),
        Value::String(_) => json_text(k),
        Value::Number(_) if is_key(k) => literal_text(k),
        _ => "<invalid step>".into(),
    }
}

pub fn builtin(path: &Value) -> bool {
    path.as_array().and_then(|p| p.first()).and_then(Value::as_str).is_some_and(|s| s.starts_with("$$"))
}

pub fn ref_name(path: &Value) -> String {
    if !builtin(path) {
        return "<invalid ref>".into();
    }
    path.as_array()
        .unwrap()
        .iter()
        .enumerate()
        .map(|(i, seg)| if i == 0 { seg.as_str().unwrap().to_string() } else { key_name(unliteral(seg)) })
        .collect::<Vec<_>>()
        .join(".")
}

pub fn value_text(x: &Value) -> String {
    if let Some(r) = only_key(x, "ref") {
        return ref_name(r);
    }
    if malformed(x) {
        return "<invalid ref>".into();
    }
    literal_text(written(x).unwrap_or(x))
}

pub fn list_text(v: &Value, name: &str) -> String {
    let sorted = |mut texts: Vec<String>| {
        texts.sort();
        format!("[{}]", texts.join(", "))
    };
    if let Value::Array(items) = v {
        return sorted(items.iter().map(value_text).collect());
    }
    if let Some(Value::Array(items)) = only_key(v, "literal") {
        return sorted(items.iter().map(literal_text).collect());
    }
    if let Some(r) = only_key(v, "ref") {
        return ref_name(r);
    }
    if malformed(v) {
        return "<invalid ref>".into();
    }
    format!("<invalid {name}>")
}

fn segment_name(i: usize, p: &Value) -> String {
    if !p.is_object() {
        return key_name(p);
    }
    if let Some(l) = only_key(p, "literal") {
        return match l {
            Value::String(s) if i == 0 && s.starts_with('$') => json_text(l),
            _ => key_name(l),
        };
    }
    if let Some(r) = only_key(p, "ref") {
        return format!("[{}]", ref_name(r));
    }
    if malformed(p) {
        return "[<invalid ref>]".into();
    }
    let mut parts: Vec<String> = match p.get("where") {
        Some(Value::Object(w)) => w.iter().map(|(k, v)| format!("{}=={}", key_name(&json!(k)), value_text(v))).collect(),
        Some(Value::Array(w)) => w.iter().enumerate().map(|(k, v)| format!("{}=={}", key_name(&json!(k)), value_text(v))).collect(),
        _ => vec![],
    };
    parts.sort();
    format!("[{}]", parts.join(" and "))
}

pub fn path_name(path: &Value) -> Option<String> {
    match path {
        Value::Array(p) => Some(p.iter().enumerate().map(|(i, s)| segment_name(i, s)).collect::<Vec<_>>().join(".")),
        Value::Object(m) => Some(m.values().map(key_name).collect::<Vec<_>>().join(".")),
        _ => Some(String::new()),
    }
}

pub fn item_path_name(item: &str, path: &Value) -> Option<String> {
    if path == &json!([]) { Some(item.to_string()) } else { path_name(path) }
}

pub fn projection_name(path: &Value, each: &Value) -> Option<String> {
    let base = format!("{}[]", path_name(path)?);
    if each == &json!([]) { Some(base) } else { Some(format!("{base}.{}", path_name(each)?)) }
}

pub fn valid_name(v: Option<&Value>) -> Option<&str> {
    v?.as_str().filter(|n| !n.is_empty() && !n.starts_with('$'))
}

fn names_of(v: &Value) -> Vec<(Value, &Value)> {
    match v {
        Value::Object(m) => m.iter().map(|(k, x)| (json!(k), x)).collect(),
        Value::Array(a) => a.iter().enumerate().map(|(i, x)| (json!(i), x)).collect(),
        _ => vec![],
    }
}

fn path_text(item: &str, check: &Value, f: &str) -> Option<String> {
    match check.get(f) {
        Some(p) if p.is_array() => item_path_name(item, p),
        Some(_) => Some(format!("<invalid {f}>")),
        None => Some(format!("<missing {f}>")),
    }
}

fn param_text(check: &Value, f: &str) -> String {
    match check.get(f) {
        Some(v) => value_text(v),
        None => format!("<missing {f}>"),
    }
}

fn leaf_describe(check: &Value, item: &str) -> Option<String> {
    let Some(m) = check.as_object() else { return Some("<invalid check>".into()) };
    let Some(op_value) = m.get("op") else { return Some("<missing op>".into()) };
    if let Some(def) = op_value.as_str().filter(|o| !is_builtin(o)).and_then(crate::operators::find) {
        return custom_text(check, item, &def);
    }
    let op = match op_value.as_str() {
        Some(op) if is_operator(op) => op,
        _ => return Some(format!("<unknown op {}>", text(op_value))),
    };
    let p = |f: &str| path_text(item, check, f);
    let has = |f: &str| m.contains_key(f);
    let one_value = || match (has("value"), has("values")) {
        (true, false) => value_text(&m["value"]),
        (true, true) => "<both value and values>".into(),
        _ => "<missing value or values>".into(),
    };
    let values_only = has("values") && !has("value");
    let patterns = || if has("patterns") { list_text(&m["patterns"], "patterns") } else { "<missing patterns>".into() };
    Some(match op {
        "range" => {
            let n = p("path")?;
            format!("{n} >= {} and {n} <= {}", param_text(check, "min"), param_text(check, "max"))
        }
        "excludes" if !values_only => format!("not contains({}, {})", p("path")?, one_value()),
        "includes" if !values_only => format!("contains({}, {})", p("path")?, one_value()),
        "excludes" => format!("contains_none({}, {})", p("path")?, list_text(&m["values"], "values")),
        "includes" => format!("contains_all({}, {})", p("path")?, list_text(&m["values"], "values")),
        "in" if has("values") => format!("{} in {}", p("path")?, list_text(&m["values"], "values")),
        "in" => format!("{} in <missing values>", p("path")?),
        "equals" => format!("{} == {}", p("path")?, param_text(check, "value")),
        "present" => format!("{} is present", p("path")?),
        "missing" => format!("{} is missing", p("path")?),
        "non_empty_string" => format!("{} is a non-empty string", p("path")?),
        "empty" => format!("{} is empty", p("path")?),
        "matches_any" => format!("{} matches one of {}", p("path")?, patterns()),
        "not_matches_any" => format!("{} matches none of {}", p("path")?, patterns()),
        "compare" | "compare_time" => {
            let cmp = m.get("cmp").map(text).unwrap_or_else(|| "<missing cmp>".into());
            format!("{} {cmp} {}", p("left")?, p("right")?)
        }
        _ => String::new(),
    })
}

fn nested_describe(check: &Value, item: &str) -> Option<String> {
    match op_of(check) {
        Some(op) if is_operator(op) && !is_leaf(op) && !quantified(check) => Some(format!("<{op} can't go here>")),
        _ => leaf_describe(check, item),
    }
}

fn quantifier(check: &Value) -> &'static str {
    if op_of(check) == Some("all") { "every" } else { "some" }
}

fn collection_name(check: &Value) -> Option<String> {
    let Some(path) = check.get("path") else { return Some("<missing path>".into()) };
    if truthy(check.get("each")) { projection_name(path, &check["each"]) } else { path_name(path) }
}

fn as_text(check: &Value, given: &[String]) -> String {
    match check.get("as") {
        None => String::new(),
        Some(a) => match valid_name(Some(a)) {
            Some(n) if given.iter().any(|g| g == n) => " as <name given twice>".into(),
            Some(n) => format!(" as ${n}"),
            None => " as <invalid name>".into(),
        },
    }
}

fn given_with(check: &Value, given: &[String]) -> Vec<String> {
    let mut g = given.to_vec();
    if let Some(n) = valid_name(check.get("as")) {
        g.push(n.to_string());
    }
    g
}

fn item_given(item: &str) -> Vec<String> {
    if item.starts_with('$') && !item.starts_with("$$") { vec![item[1..].to_string()] } else { vec![] }
}

fn list_describe(check: &Value, given: &[String]) -> Option<String> {
    let collection = collection_name(check)?;
    let item = match valid_name(check.get("as")) {
        Some(n) => format!("${n}"),
        None => format!("{collection}[]"),
    };
    let inner = match check.get("check") {
        Some(c) => element_describe(c, &item, &given_with(check, given))?,
        None => "<missing check>".into(),
    };
    Some(format!("{} {collection}{}: {inner}", quantifier(check), as_text(check, given)))
}

fn options_describe(check: &Value, item: &str, describe: &dyn Fn(&Value, &str) -> Option<String>) -> Option<String> {
    let mut parts = vec![];
    for (nm, group) in names_of(check.get("options").unwrap_or(&Value::Null)) {
        let body = match group {
            Value::Array(a) if a.is_empty() => "<empty option>".to_string(),
            Value::Array(_) => {
                let inner: Option<Vec<String>> = names_of(group).into_iter().map(|(_, leaf)| describe(leaf, item)).collect();
                inner?.join(" and ")
            }
            _ => "<invalid option>".to_string(),
        };
        parts.push(format!("{}({body})", text(&nm)));
    }
    if parts.is_empty() {
        return Some("one of: <empty options>".into());
    }
    parts.sort();
    Some(format!("one of: {}", parts.join(" | ")))
}

fn element_describe(check: &Value, item: &str, given: &[String]) -> Option<String> {
    if combinator(check) {
        let given = given.to_vec();
        return options_describe(check, item, &move |leaf, item| {
            if quantified(leaf) { element_list_describe(leaf, item, &given) } else { nested_describe(leaf, item) }
        });
    }
    if quantified(check) {
        return element_list_describe(check, item, given);
    }
    nested_describe(check, item)
}

fn inner_collection_name(check: &Value, item: &str) -> Option<String> {
    let Some(path) = check.get("path") else { return Some("<missing path>".into()) };
    let base = item_path_name(item, path)?;
    if truthy(check.get("each")) { Some(format!("{base}[].{}", path_name(&check["each"])?)) } else { Some(base) }
}

fn element_list_describe(check: &Value, item: &str, given: &[String]) -> Option<String> {
    let collection = inner_collection_name(check, item)?;
    let inner_item = match valid_name(check.get("as")) {
        Some(n) => format!("${n}"),
        None => format!("{collection}[]"),
    };
    let inner = match check.get("check") {
        Some(c) => inner_describe(c, &inner_item)?,
        None => "<missing check>".into(),
    };
    Some(format!("{} {collection}{}: {inner}", quantifier(check), as_text(check, given)))
}

fn inner_describe(check: &Value, item: &str) -> Option<String> {
    if combinator(check) {
        return options_describe(check, item, &|leaf, item| if quantified(leaf) { Some("<nested too deep>".into()) } else { nested_describe(leaf, item) });
    }
    if quantified(check) {
        return Some("<nested too deep>".into());
    }
    nested_describe(check, item)
}

pub fn expression_of(check: &Value, item: &str) -> Option<String> {
    if let Some(Value::String(e)) = check.get("expression") {
        return Some(e.clone());
    }
    if quantified(check) {
        return list_describe(check, &item_given(item));
    }
    if combinator(check) {
        if check.get("options").is_none() {
            return Some("one of: <missing options>".into());
        }
        let given = item_given(item);
        return options_describe(check, item, &move |leaf, item| if quantified(leaf) { list_describe(leaf, &given) } else { nested_describe(leaf, item) });
    }
    leaf_describe(check, item)
}

pub fn described(check: &Value, item: &str) -> Option<String> {
    match check.get("substitute") {
        Some(s) if truthy(Some(s)) => Some(format!("{}, or substitute: {}", expression_of(check, item)?, expression_of(s, item)?)),
        _ => expression_of(check, item),
    }
}

pub fn read_raw<'a>(ctx: &Ctx<'a>, subject: &'a Value, path: &Value) -> Read<'a> {
    match path {
        Value::Array(p) => ctx.read(subject, p),
        Value::String(_) | Value::Number(_) => ctx.read_from(subject, std::slice::from_ref(path)),
        _ if !subject.is_object() => Read::NotAnObject,
        _ => Read::NoKeys,
    }
}

fn value_at<'a>(ctx: &Ctx<'a>, subject: &'a Value, path: &Value) -> Value {
    read_raw(ctx, subject, path).shown()
}

fn list_at<'a>(ctx: &Ctx<'a>, subject: &'a Value, path: &Value) -> Vec<&'a Value> {
    match read_raw(ctx, subject, path) {
        Read::Found(Value::Array(items)) => items.iter().collect(),
        _ => vec![],
    }
}

fn entry(name: String, value: Value) -> Value {
    json!({"name": name, "value": value})
}

fn named_path(p: &Value) -> Option<&str> {
    p.as_array()?.first()?.as_str().filter(|s| s.starts_with('$'))
}

fn leaf_paths(leaf: &Value) -> Vec<&Value> {
    let custom = custom_paths(leaf);
    if !custom.is_empty() {
        return custom;
    }
    if two_sided(leaf) {
        return [leaf.get("left"), leaf.get("right")].into_iter().flatten().collect();
    }
    match leaf.get("path") {
        Some(p) if truthy(Some(p)) => vec![p],
        _ => vec![],
    }
}

fn element_leaves(check: &Value) -> Vec<&Value> {
    if combinator(check) {
        return names_of(check.get("options").unwrap_or(&Value::Null)).into_iter().flat_map(|(_, g)| names_of(g).into_iter().map(|(_, l)| l)).collect();
    }
    vec![check]
}

fn names_given(check: &Value) -> Vec<String> {
    check.get("as").and_then(Value::as_str).map(|s| vec![s.to_string()]).unwrap_or_default()
}

fn element_name_reads(check: &Value) -> Vec<Value> {
    let given = names_given(check);
    let mut reads: Vec<(Value, Vec<String>)> = vec![];
    let inner = check.get("check").unwrap_or(&Value::Null);
    for leaf in element_leaves(inner) {
        if quantified(leaf) {
            if let Some(p) = leaf.get("path") {
                reads.push((p.clone(), given.clone()));
            }
            if let Some(e) = leaf.get("each").filter(|e| named_path(e).is_some()) {
                reads.push((e.clone(), given.clone()));
            }
            let mut deeper = given.clone();
            deeper.extend(names_given(leaf));
            for l in element_leaves(leaf.get("check").unwrap_or(&Value::Null)) {
                reads.extend(leaf_paths(l).into_iter().map(|p| (p.clone(), deeper.clone())));
            }
        } else {
            reads.extend(leaf_paths(leaf).into_iter().map(|p| (p.clone(), given.clone())));
        }
    }
    let mut named: Vec<Value> = reads
        .into_iter()
        .filter(|(p, g)| named_path(p).is_some_and(|n| !g.iter().any(|x| x == &n[1..])))
        .map(|(p, _)| p)
        .collect();
    named.sort_by(rego_order);
    named.dedup();
    named
}

fn list_reads(check: &Value) -> Vec<Value> {
    let mut out: Vec<Value> = check.get("path").cloned().into_iter().collect();
    if let Some(e) = check.get("each").filter(|e| named_path(e).is_some()) {
        out.push(e.clone());
    }
    out.extend(element_name_reads(check));
    out
}

fn inner_path(check: &Value) -> Option<Value> {
    match check.get("check") {
        Some(Value::Object(m)) => Some(m.get("path").cloned().unwrap_or(json!([]))),
        _ => None,
    }
}

fn quantified_inputs<'a>(ctx: &Ctx<'a>, subject: &'a Value, check: &Value) -> Option<Vec<Value>> {
    let path = check.get("path")?;
    if truthy(check.get("each")) {
        let each = &check["each"];
        let vals = list_at(ctx, subject, path).into_iter().map(|el| value_at(ctx, el, each)).collect();
        return Some(vec![entry(projection_name(path, each)?, Value::Array(vals))]);
    }
    let inner = inner_path(check)?;
    let as_ = check.get("as").and_then(Value::as_str);
    let outer_named = named_path(&inner).is_some_and(|n| Some(&n[1..]) != as_);
    if outer_named {
        return Some(vec![entry(projection_name(path, &json!([]))?, value_at(ctx, subject, path)), entry(path_name(&inner)?, value_at(ctx, subject, &inner))]);
    }
    let rel = match (&inner, named_path(&inner)) {
        (Value::Array(p), Some(n)) if Some(&n[1..]) == as_ => Value::Array(p[1..].to_vec()),
        _ => inner.clone(),
    };
    let vals = list_at(ctx, subject, path).into_iter().map(|el| value_at(ctx, el, &rel)).collect();
    Some(vec![entry(projection_name(path, &rel)?, Value::Array(vals))])
}

fn check_inputs<'a>(ctx: &Ctx<'a>, subject: &'a Value, check: &Value, item: &str) -> Option<Vec<Value>> {
    let Some(m) = check.as_object() else { return None };
    if truthy(m.get("inputs")) {
        let specs = names_of(&m["inputs"]);
        return specs
            .into_iter()
            .map(|(_, spec)| match spec {
                Value::Object(s) => {
                    let path = s.get("path").cloned().unwrap_or(json!([]));
                    let each = s.get("each").cloned().unwrap_or(json!([]));
                    let vals = list_at(ctx, subject, &path).into_iter().map(|el| value_at(ctx, el, &each)).collect();
                    Some(entry(projection_name(&path, &each)?, Value::Array(vals)))
                }
                Value::Array(_) => Some(entry(item_path_name(item, spec)?, value_at(ctx, subject, spec))),
                _ => None,
            })
            .collect();
    }
    if two_sided(check) {
        let side = |f: &str| -> Option<Value> {
            let p = m.get(f).filter(|p| p.is_array())?;
            Some(entry(item_path_name(item, p)?, value_at(ctx, subject, p)))
        };
        return Some(vec![side("left")?, side("right")?]);
    }
    if quantified(check) {
        let mut out = quantified_inputs(ctx, subject, check)?;
        let inner = inner_path(check);
        for p in element_name_reads(check) {
            if Some(&p) != inner.as_ref() {
                out.push(entry(path_name(&p)?, value_at(ctx, subject, &p)));
            }
        }
        return Some(out);
    }
    if combinator(check) {
        let mut reads: Vec<(String, Value)> = vec![];
        for leaf in element_leaves(check) {
            let paths: Vec<Value> = if quantified(leaf) { list_reads(leaf) } else { leaf_paths(leaf).into_iter().cloned().collect() };
            for p in paths {
                reads.push((item_path_name(item, &p)?, value_at(ctx, subject, &p)));
            }
        }
        reads.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| rego_order(&a.1, &b.1)));
        reads.dedup();
        return Some(reads.into_iter().map(|(n, v)| entry(n, v)).collect());
    }
    if op_of(check).is_some_and(|o| !is_builtin(o) && crate::operators::find(o).is_some()) {
        return custom_paths(check).into_iter().map(|p| Some(entry(item_path_name(item, p)?, value_at(ctx, subject, p)))).collect();
    }
    let p = m.get("path").filter(|p| p.is_array())?;
    Some(vec![entry(item_path_name(item, p)?, value_at(ctx, subject, p))])
}

pub fn row_inputs<'a>(ctx: &Ctx<'a>, subject: &'a Value, check: &Value, item: &str) -> Vec<Value> {
    let mut all = check_inputs(ctx, subject, check, item).unwrap_or_default();
    if let Some(s) = check.get("substitute").filter(|s| truthy(Some(s))) {
        for input in check_inputs(ctx, subject, s, item).unwrap_or_default() {
            if !all.contains(&input) {
                all.push(input);
            }
        }
    }
    all
}

pub fn definition(check: &Value, item: &str) -> Value {
    let mut def = match check {
        Value::Object(m) => m.clone(),
        _ => Map::new(),
    };
    if let Some(e) = described(check, item) {
        def.insert("expression".into(), json!(e));
    }
    Value::Object(def)
}

pub type Entry<'a> = (String, Value, Option<crate::value::Cause>, Option<&'a Value>);

fn each_state<'a>(ctx: &Ctx<'a>, outer: &'a Value, each: &Value) -> Option<crate::value::Cause> {
    match read_raw(ctx, outer, each) {
        Read::Found(v) if !v.is_array() => Some(crate::value::Cause::Unusable),
        Read::Found(_) => None,
        Read::Unusable if !each.is_array() => Some(crate::value::Cause::Absent),
        r => r.problem(),
    }
}

pub fn item_entries<'a>(ctx: &Ctx<'a>, subject: &'a Value, check: &Value, item: &str) -> Vec<Entry<'a>> {
    let Some(path) = check.get("path") else { return vec![] };
    let Read::Found(Value::Array(coll)) = read_raw(ctx, subject, path) else { return vec![] };
    let Some(list) = item_path_name(item, path) else { return vec![] };
    if !truthy(check.get("each")) {
        return coll.iter().enumerate().map(|(i, v)| (format!("{list}[{i}]"), v.clone(), None, Some(v))).collect();
    }
    let each = &check["each"];
    let suffix = if each == &json!([]) { String::new() } else { format!(".{}", path_name(each).unwrap_or_default()) };
    let mut out = vec![];
    for (i, outer) in coll.iter().enumerate() {
        let name = format!("{list}[{i}]{suffix}");
        match read_raw(ctx, outer, each) {
            Read::Found(Value::Array(inner)) if !inner.is_empty() => out.extend(inner.iter().enumerate().map(|(j, v)| (format!("{name}[{j}]"), v.clone(), None, Some(v)))),
            Read::Found(Value::Array(_)) => out.push((name, json!([]), Some(crate::value::Cause::Value), None)),
            r => out.push((name, r.shown(), each_state(ctx, outer, each), None)),
        }
    }
    out
}
