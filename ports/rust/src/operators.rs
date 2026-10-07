use crate::cel::{Body, compile};
use crate::render::{is_builtin, json_text};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Path,
    Paths,
    Value,
    Number,
    String,
}

pub struct Param {
    pub name: String,
    pub kind: Kind,
    pub expects: Option<String>,
    pub optional: bool,
    pub default: Option<Value>,
}

pub struct Definition {
    pub name: String,
    pub params: Vec<Param>,
    pub template: Option<String>,
    pub body: Body,
    pub record: Value,
}

#[derive(Default, Clone)]
pub struct Operators {
    defs: BTreeMap<String, Arc<Definition>>,
}

const RESERVED: [&str; 10] = ["op", "description", "meta", "expression", "substitute", "inputs", "as", "each", "check", "options"];
const TYPES: [&str; 5] = ["list", "number", "string", "object", "boolean"];

fn identifier(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_') && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn param(name: &str, spec: &Value) -> Result<Param, String> {
    let (kind, rest) = match spec {
        Value::String(k) => (k.as_str(), Map::new()),
        Value::Object(m) => (m.get("kind").and_then(Value::as_str).ok_or("needs a kind")?, m.clone()),
        _ => return Err("must be a kind or an object with one".into()),
    };
    let kind = match kind {
        "path" => Kind::Path,
        "paths" => Kind::Paths,
        "value" => Kind::Value,
        "number" => Kind::Number,
        "string" => Kind::String,
        other => return Err(format!("has an unknown kind {other}")),
    };
    for k in rest.keys() {
        if !["kind", "type", "optional", "default"].contains(&k.as_str()) {
            return Err(format!("has an unknown field {k}"));
        }
    }
    let expects = match rest.get("type") {
        None => None,
        Some(Value::String(t)) if kind == Kind::Path && TYPES.contains(&t.as_str()) => Some(t.clone()),
        Some(_) => return Err("has a type that isn't list, number, string, object or boolean, or isn't on a path".into()),
    };
    let optional = match rest.get("optional") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err("has an optional that isn't true or false".into()),
    };
    let default = rest.get("default").cloned();
    if default.is_some() && (!optional || matches!(kind, Kind::Path | Kind::Paths)) {
        return Err("has a default but isn't an optional value".into());
    }
    Ok(Param { name: name.to_string(), kind, expects, optional, default })
}

fn definition(name: &str, spec: &Value) -> Result<Definition, String> {
    if !identifier(name) || is_builtin(name) {
        return Err("its name must be a plain identifier that isn't a built-in operator".into());
    }
    let m = spec.as_object().ok_or("it isn't an object")?;
    for k in m.keys() {
        if !["params", "expression", "passes", "version", "description"].contains(&k.as_str()) {
            return Err(format!("it has an unknown field {k}"));
        }
    }
    let params: Vec<Param> = match m.get("params") {
        None => vec![],
        Some(Value::Object(p)) => p
            .iter()
            .map(|(n, s)| {
                if !identifier(n) || RESERVED.contains(&n.as_str()) || n == "ergo" {
                    return Err(format!("param {n} can't be called that"));
                }
                param(n, s).map_err(|e| format!("param {n} {e}"))
            })
            .collect::<Result<_, _>>()?,
        Some(_) => return Err("its params isn't an object".into()),
    };
    let names: Vec<String> = params.iter().map(|p| p.name.clone()).collect();
    let passes = m.get("passes").and_then(Value::as_str).ok_or("it needs passes, a CEL expression")?;
    let body = compile(passes, &names)?;
    let template = match m.get("expression") {
        None => None,
        Some(Value::String(t)) => {
            let mut rest = t.as_str();
            while let Some(i) = rest.find('{') {
                let end = rest[i..].find('}').ok_or("its expression has a { without a }")?;
                let placeholder = &rest[i + 1..i + end];
                if !names.iter().any(|n| n == placeholder) {
                    return Err(format!("its expression names {{{placeholder}}}, which isn't one of its params"));
                }
                rest = &rest[i + end + 1..];
            }
            Some(t.clone())
        }
        Some(_) => return Err("its expression isn't a string".into()),
    };
    let digest = Sha256::digest(json_text(spec).as_bytes());
    let hash: String = digest.iter().map(|b| format!("{b:02x}")).collect();
    let mut record = json!({"sha256": hash});
    if let Some(v) = m.get("version") {
        record["version"] = v.clone();
    }
    Ok(Definition { name: name.to_string(), params, template, body, record })
}

impl Operators {
    pub fn load(defs: &Value) -> Result<Operators, Vec<String>> {
        let Some(m) = defs.as_object() else { return Err(vec!["operator definitions must be an object".into()]) };
        let mut out = Operators::default();
        let mut errors = vec![];
        for (name, spec) in m {
            match definition(name, spec) {
                Ok(d) => {
                    out.defs.insert(name.clone(), Arc::new(d));
                }
                Err(e) => errors.push(format!("operator {name}: {e}")),
            }
        }
        if errors.is_empty() { Ok(out) } else { Err(errors) }
    }

    pub fn find(&self, name: &str) -> Option<Arc<Definition>> {
        self.defs.get(name).cloned()
    }
}

thread_local! {
    static ACTIVE: RefCell<Option<Arc<Operators>>> = const { RefCell::new(None) };
}

pub fn with_active<R>(ops: Arc<Operators>, f: impl FnOnce() -> R) -> R {
    let previous = ACTIVE.with(|a| a.replace(Some(ops)));
    let out = f();
    ACTIVE.with(|a| a.replace(previous));
    out
}

pub fn find(name: &str) -> Option<Arc<Definition>> {
    ACTIVE.with(|a| a.borrow().as_ref().and_then(|ops| ops.find(name)))
}
