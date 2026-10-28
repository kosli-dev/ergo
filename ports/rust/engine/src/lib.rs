use serde_json::Value;

pub const NAME: &str = "ergo-engine";

pub fn sentences_crate() -> &'static str {
    ergo_sentences::NAME
}

pub fn report(_input: &Value, _policy: &Value, _params: &Value) -> Value {
    Value::Null
}

pub fn violations(_report: &Value) -> Value {
    Value::Null
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_the_sentences_crate() {
        assert_eq!(sentences_crate(), "ergo-sentences");
    }
}
