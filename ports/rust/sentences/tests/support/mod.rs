#![allow(dead_code)]

use ergo_sentences::*;

pub fn key(name: &str) -> Path {
    Path {
        position: None,
        start: Start::Field {
            key: name.into(),
            dot: false,
        },
        steps: Vec::new(),
    }
}

pub fn dotted(name: &str) -> Path {
    Path {
        position: None,
        start: Start::Field {
            key: name.into(),
            dot: true,
        },
        steps: Vec::new(),
    }
}

pub fn with_steps(mut path: Path, steps: Vec<Step>) -> Path {
    path.steps = steps;
    path
}

pub fn dot(name: &str) -> Step {
    Step::Key(name.into())
}

pub fn it() -> Path {
    Path {
        position: None,
        start: Start::It,
        steps: Vec::new(),
    }
}

pub fn text(value: &str) -> Value {
    Value::String(value.into())
}

pub fn number(value: &str) -> Value {
    Value::Number(value.into())
}

pub fn value(value: Value) -> Operand {
    Operand::Value(value)
}

pub fn field(name: &str) -> Operand {
    Operand::Field(vec![Term::Path(key(name))])
}

pub fn from(line: &str) -> From {
    match parse_from(line) {
        Ok(read) => read,
        Err(errors) => panic!("{line:?} did not parse: {errors:?}"),
    }
}

pub fn path(line: &str) -> Path {
    match parse_path(line) {
        Ok(read) => read,
        Err(errors) => panic!("{line:?} did not parse: {errors:?}"),
    }
}

pub fn failure(line: &str) -> Vec<String> {
    match parse_from(line) {
        Ok(read) => panic!("{line:?} parsed as {read:?}"),
        Err(errors) => errors.into_iter().map(|e| e.message).collect(),
    }
}

pub fn condition(line: &str) -> Condition {
    let mut read = from(&format!("x whose {line}"));
    assert_eq!(read.whose.len(), 1, "{line:?}");
    match read.whose.remove(0) {
        FromCondition::Condition(condition) => condition,
        other => panic!("{line:?} read as {other:?}"),
    }
}

pub fn phrase(line: &str) -> Phrase {
    condition(&format!("y {line}")).phrase
}

pub fn printed(line: &str) -> String {
    print_from(&from(line), &[])
}

pub fn printed_phrase(line: &str) -> String {
    let read = from(&format!("x whose y {line}"));
    print_from(&read, &[])
        .strip_prefix("x whose y ")
        .unwrap_or_default()
        .to_string()
}

pub fn check(line: &str) -> Check {
    match parse_check(line) {
        Ok(read) => read,
        Err(errors) => panic!("{line:?} did not parse: {errors:?}"),
    }
}

pub fn for_line(line: &str) -> For {
    match parse_for(line) {
        Ok(read) => read,
        Err(errors) => panic!("{line:?} did not parse: {errors:?}"),
    }
}

pub fn check_failure(line: &str) -> Vec<String> {
    match parse_check(line) {
        Ok(read) => panic!("{line:?} parsed as {read:?}"),
        Err(errors) => errors.into_iter().map(|e| e.message).collect(),
    }
}

pub fn for_failure(line: &str) -> Vec<String> {
    match parse_for(line) {
        Ok(read) => panic!("{line:?} parsed as {read:?}"),
        Err(errors) => errors.into_iter().map(|e| e.message).collect(),
    }
}

pub fn assertion(line: &str) -> Assertion {
    let mut read = check(line);
    assert_eq!(read.assertions.len(), 1, "{line:?}");
    read.assertions.remove(0)
}

pub fn problems(line: &str) -> Vec<String> {
    check_problems(&check(line), &[])
}

pub fn problems_with(line: &str, aliases: &[&str]) -> Vec<String> {
    check_problems(&check(line), aliases)
}

pub fn printed_check(line: &str) -> String {
    print_check(&check(line), &[])
}

pub fn printed_for(line: &str) -> String {
    print_for(&for_line(line), &[])
}
