use serde_json::Value;

pub mod cause;
pub mod name;
pub mod path;
pub mod value;

pub fn report(_input: &Value, _policy: &Value, _params: &Value) -> Value {
    Value::Null
}

pub fn violations(_report: &Value) -> Value {
    Value::Null
}
