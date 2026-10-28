pub mod present;

use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path};
use serde_json::{Map, Value, json};

#[derive(Debug, Clone, PartialEq)]
pub struct Part {
    pub name: String,
    pub id: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Input {
    pub name: String,
    pub value: Value,
    pub locations: Vec<String>,
    pub part: Option<Part>,
}

impl Input {
    pub fn to_json(&self) -> Value {
        let mut entry = Map::new();
        entry.insert("name".to_string(), json!(self.name));
        entry.insert("value".to_string(), self.value.clone());
        entry.insert("locations".to_string(), json!(self.locations));
        if let Some(part) = &self.part {
            entry.insert(
                "part".to_string(),
                json!({"name": part.name, "id": part.id}),
            );
        }
        Value::Object(entry)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Verdict {
    pub cause: Cause,
    pub inputs: Vec<Input>,
}

impl Verdict {
    pub fn passed(&self) -> bool {
        self.cause == Cause::Satisfied
    }
}

pub struct ReadPath {
    pub outcome: Outcome,
    pub value: Option<Value>,
    pub input: Input,
}

pub fn read_path(path: &Path, ctx: &Ctx) -> ReadPath {
    let read = path::read(path, ctx);
    let value = read.value.cloned();
    let input = Input {
        name: name::name(path),
        value: value.clone().unwrap_or(Value::Null),
        locations: read.location.iter().map(|l| l.render()).collect(),
        part: None,
    };
    ReadPath {
        outcome: read.outcome,
        value,
        input,
    }
}

pub fn verdict(passed: bool) -> Cause {
    if passed {
        Cause::Satisfied
    } else {
        Cause::Value
    }
}
