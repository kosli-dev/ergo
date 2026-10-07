use crate::value::{Cause, literal_text};
use serde_json::{Number, Value};

pub enum Read<'a> {
    Found(&'a Value),
    Null,
    Absent,
    Unusable,
    NotAnObject,
}

impl<'a> Read<'a> {
    pub fn shown(&self) -> Value {
        match self {
            Read::Found(v) => (*v).clone(),
            _ => Value::Null,
        }
    }

    pub fn problem(&self) -> Option<Cause> {
        match self {
            Read::Found(_) => None,
            Read::Null => Some(Cause::Null),
            Read::Absent => Some(Cause::Absent),
            Read::Unusable => Some(Cause::Unusable),
            Read::NotAnObject => Some(Cause::NotAnObject),
        }
    }

    pub fn found(&self) -> Option<&'a Value> {
        match self {
            Read::Found(v) => Some(*v),
            _ => None,
        }
    }
}

pub fn index_key(n: &Number) -> bool {
    let text = n.to_string();
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_digit())
}

pub fn is_key(v: &Value) -> bool {
    match v {
        Value::String(_) => true,
        Value::Number(n) => index_key(n),
        _ => false,
    }
}

pub fn single<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    match v {
        Value::Object(m) if m.len() == 1 => m.get(key),
        _ => None,
    }
}

pub fn literal_of(v: &Value) -> Option<&Value> {
    single(v, "literal")
}

pub fn ref_of(v: &Value) -> Option<&[Value]> {
    single(v, "ref").and_then(Value::as_array).map(Vec::as_slice)
}

pub fn step_key(step: &Value) -> Option<&Value> {
    if is_key(step) {
        return Some(step);
    }
    literal_of(step).filter(|k| is_key(k))
}

pub fn path_ok(path: &[Value]) -> bool {
    path.iter().all(|s| step_key(s).is_some())
}

fn plain_key(k: &str) -> bool {
    let mut chars = k.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_' || c == '$')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '$' || c == '-')
}

pub fn key_name(k: &Value) -> String {
    match k {
        Value::String(s) if plain_key(s) => s.clone(),
        Value::String(s) => Value::String(s.clone()).to_string(),
        Value::Number(n) if index_key(n) => n.to_string(),
        _ => "<invalid step>".into(),
    }
}

fn segment_name(i: usize, step: &Value) -> String {
    match literal_of(step) {
        Some(Value::String(s)) if i == 0 && s.starts_with('$') => Value::String(s.clone()).to_string(),
        Some(k) => key_name(k),
        None => key_name(step),
    }
}

pub fn path_name(path: &[Value]) -> String {
    path.iter().enumerate().map(|(i, s)| segment_name(i, s)).collect::<Vec<_>>().join(".")
}

pub fn item_path_name(item: &str, path: &[Value]) -> String {
    if path.is_empty() { item.to_string() } else { path_name(path) }
}

pub fn projection(path: &[Value], each: &[Value]) -> String {
    if each.is_empty() { format!("{}[]", path_name(path)) } else { format!("{}[].{}", path_name(path), path_name(each)) }
}

pub fn from_name(from: &[Value]) -> String {
    match from.split_first() {
        None => "$$input".into(),
        Some((Value::String(first), rest)) if first.starts_with('$') => std::iter::once(Value::String(first.clone()).to_string())
            .chain(rest.iter().enumerate().map(|(i, s)| segment_name(i + 1, s)))
            .collect::<Vec<_>>()
            .join("."),
        Some(_) => path_name(from),
    }
}

pub fn first_name(path: &[Value]) -> Option<&str> {
    match path.first() {
        Some(Value::String(s)) if s.starts_with('$') => Some(&s[1..]),
        _ => None,
    }
}

pub fn valid_name(v: &Value) -> Option<&str> {
    v.as_str().filter(|n| !n.is_empty() && !n.starts_with('$'))
}

pub fn known_ref(r: &[Value]) -> bool {
    matches!(r.first().and_then(Value::as_str), Some("$$params" | "$$input")) && path_ok(&r[1..])
}

pub fn absent() -> &'static Value {
    static ABSENT: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    ABSENT.get_or_init(|| serde_json::json!({"ergo/absent": true}))
}

pub fn read_steps<'a>(start: &'a Value, path: &[Value]) -> Read<'a> {
    if std::ptr::eq(start, absent()) {
        return Read::Absent;
    }
    if !path.is_empty() && !start.is_object() {
        return Read::NotAnObject;
    }
    let mut at = start;
    for step in path {
        let Some(key) = step_key(step) else { return Read::Unusable };
        at = match (at, key) {
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

#[derive(Clone)]
pub struct Ctx<'a> {
    pub doc: &'a Value,
    pub params: &'a Value,
    pub names: Vec<(String, &'a Value)>,
}

impl<'a> Ctx<'a> {
    pub fn with(&self, name: Option<&str>, v: &'a Value) -> Ctx<'a> {
        let mut c = self.clone();
        if let Some(n) = name {
            c.names.push((n.to_string(), v));
        }
        c
    }

    pub fn name(&self, n: &str) -> Option<&'a Value> {
        self.names.iter().rev().find(|(k, _)| k == n).map(|(_, v)| *v)
    }

    pub fn read(&self, subject: &'a Value, path: &[Value]) -> Read<'a> {
        match path.first().and_then(Value::as_str) {
            Some("$$input") => read_steps(self.doc, &path[1..]),
            Some("$$params") => read_steps(self.params, &path[1..]),
            Some(s) if s.starts_with('$') => match self.name(&s[1..]) {
                Some(v) => read_steps(v, &path[1..]),
                None => Read::Unusable,
            },
            _ => read_steps(subject, path),
        }
    }

    pub fn value_at(&self, subject: &'a Value, path: &[Value]) -> Value {
        self.read(subject, path).shown()
    }

    pub fn read_ref(&self, r: &[Value]) -> Read<'a> {
        let root = match r.first().and_then(Value::as_str) {
            Some("$$params") => self.params,
            Some("$$input") => self.doc,
            _ => return Read::Unusable,
        };
        match read_steps(root, &r[1..]) {
            Read::NotAnObject => Read::Absent,
            other => other,
        }
    }
}

pub fn ref_text(r: &[Value]) -> String {
    path_name(r)
}
