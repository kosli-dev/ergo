use crate::value::{Decimal, fits_a_float, too_long};
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};

/// The version of the spec this engine implements, in the form a policy's `ergo_spec` and a report's `ergo` use.
pub const SPEC: &str = "v0.7-dev";

pub use crate::names::written_name_problems;

pub type Problems = BTreeMap<String, BTreeSet<String>>;

pub const LISTED_LAST: char = '\u{1}';

pub fn add_problem(problems: &mut Problems, name: String, text: impl Into<String>) {
    problems.entry(name).or_default().insert(text.into());
}

pub fn merge_problems(into: &mut Problems, from: &Problems) {
    for (name, texts) in from {
        into.entry(name.clone())
            .or_default()
            .extend(texts.iter().cloned());
    }
}

fn is_plain_key(key: &str) -> bool {
    let mut bytes = key.bytes();
    match bytes.next() {
        Some(b) if b.is_ascii_alphabetic() || b == b'_' || b == b'$' => {}
        _ => return false,
    }
    bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'$' || b == b'-')
}

pub fn field_name(keys: &[&str]) -> String {
    keys.iter()
        .map(|key| {
            if is_plain_key(key) {
                (*key).to_string()
            } else {
                serde_json::to_string(key).unwrap_or_default()
            }
        })
        .collect::<Vec<_>>()
        .join(".")
}

#[derive(Debug, Clone, PartialEq)]
pub enum Text {
    Missing,
    Written(String),
    Invalid,
}

fn text_of(map: &Map<String, Value>, key: &str) -> Text {
    match map.get(key) {
        None => Text::Missing,
        Some(Value::String(text)) => Text::Written(text.clone()),
        Some(_) => Text::Invalid,
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Part {
    pub from: Text,
    pub identified_by: Text,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Has {
    Missing,
    NotAnObject,
    Parts(BTreeMap<String, Part>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct SubjectDef {
    pub description: String,
    pub from: Text,
    pub identified_by: Text,
    pub has: Has,
    pub says_how: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Subject {
    pub def: Option<SubjectDef>,
    pub problems: Problems,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Subjects {
    Map(BTreeMap<String, Subject>),
    NotAnObject,
}

#[derive(Debug, Clone, PartialEq)]
pub enum OptionLines {
    Lines(Vec<Option<String>>),
    Invalid,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Form {
    Line(String),
    Assert {
        lines: Vec<Option<String>>,
        for_line: Option<String>,
    },
    AnyOf(Option<BTreeMap<String, OptionLines>>),
    MissingAssert,
    Invalid,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Check {
    pub description: String,
    pub meta: Value,
    pub form: Form,
    pub problems: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SubjectName {
    Missing,
    Named(String),
    Invalid(Value),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Requirement {
    pub description: String,
    pub meta: Value,
    pub not_an_object: Option<Value>,
    pub subject: SubjectName,
    pub require: Value,
    pub min_subjects: Value,
    pub min_subjects_count: u64,
    pub checks: BTreeMap<String, Check>,
    pub checks_count: u64,
    pub problems: Problems,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Policy {
    pub description: String,
    pub meta: Value,
    pub problems: Problems,
    pub subjects: Subjects,
    pub requirements: BTreeMap<String, Requirement>,
    pub requirements_problem: &'static str,
}

fn empty_meta() -> Value {
    Value::Object(Map::new())
}

fn reported_description(map: &Map<String, Value>) -> String {
    match map.get("description") {
        Some(Value::String(text)) => text.clone(),
        _ => String::new(),
    }
}

fn number_flaws(value: &Value, flaws: &mut BTreeSet<&'static str>) {
    match value {
        Value::Number(number) if !fits_a_float(number) => {
            flaws.insert("number out of range");
        }
        Value::Number(number) if too_long(number) => {
            flaws.insert("number with more than 15 significant digits");
        }
        Value::Array(items) => items.iter().for_each(|item| number_flaws(item, flaws)),
        Value::Object(map) => map.values().for_each(|item| number_flaws(item, flaws)),
        _ => {}
    }
}

fn meta_number_flaws(map: &Map<String, Value>) -> BTreeSet<&'static str> {
    let mut flaws = BTreeSet::new();
    if let Some(meta @ Value::Object(_)) = map.get("meta") {
        number_flaws(meta, &mut flaws);
    }
    flaws
}

fn reported_meta(map: &Map<String, Value>) -> Value {
    match map.get("meta") {
        Some(meta @ Value::Object(_)) if meta_number_flaws(map).is_empty() => meta.clone(),
        _ => empty_meta(),
    }
}

fn is_version(text: &str) -> bool {
    let body = match text.strip_prefix('v') {
        Some(body) => body,
        None => return false,
    };
    let body = body.strip_suffix("-dev").unwrap_or(body);
    let mut parts = body.split('.');
    let digits = |part: Option<&str>| {
        part.is_some_and(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
    };
    digits(parts.next()) && digits(parts.next()) && parts.next().is_none()
}

fn spec_problem(value: Option<&Value>) -> Option<String> {
    match value {
        None | Some(Value::Null) => Some("missing".to_string()),
        Some(Value::String(text)) => {
            if !is_version(text) {
                Some(format!("not a version {text}"))
            } else if text != SPEC {
                Some(format!("unsupported version {text}, expected {SPEC}"))
            } else {
                None
            }
        }
        Some(_) => Some("not a string".to_string()),
    }
}

fn policy_problems(map: &Map<String, Value>) -> Problems {
    let mut problems = Problems::new();
    if let Some(problem) = spec_problem(map.get("ergo_spec")) {
        add_problem(&mut problems, "policy ergo_spec".to_string(), problem);
    }
    if !matches!(
        map.get("description"),
        None | Some(Value::Null) | Some(Value::String(_))
    ) {
        add_problem(
            &mut problems,
            "policy description".to_string(),
            "not a string",
        );
    }
    if !matches!(
        map.get("meta"),
        None | Some(Value::Null) | Some(Value::Object(_))
    ) {
        add_problem(&mut problems, "policy meta".to_string(), "not an object");
    }
    for flaw in meta_number_flaws(map) {
        add_problem(&mut problems, "policy meta".to_string(), flaw);
    }
    problems
}

fn read_part(value: &Value, name: &str, alias: &str, problems: &mut Problems) -> Part {
    let at = field_name(&["subjects", name, "has", alias]);
    match value {
        Value::String(text) => Part {
            from: Text::Written(text.clone()),
            identified_by: Text::Missing,
        },
        Value::Object(map) => {
            for key in map.keys() {
                if key != "from" && key != "identified_by" {
                    add_problem(problems, at.clone(), format!("unknown field {key}"));
                }
            }
            if !map.contains_key("from") {
                add_problem(problems, at.clone(), "missing from");
            }
            for key in ["from", "identified_by"] {
                if text_of(map, key) == Text::Invalid {
                    add_problem(problems, at.clone(), format!("invalid {key}"));
                }
            }
            Part {
                from: text_of(map, "from"),
                identified_by: text_of(map, "identified_by"),
            }
        }
        _ => {
            add_problem(problems, at, "not a string or an object");
            Part {
                from: Text::Invalid,
                identified_by: Text::Missing,
            }
        }
    }
}

fn read_has(map: &Map<String, Value>, name: &str, problems: &mut Problems) -> Has {
    match map.get("has") {
        None => Has::Missing,
        Some(Value::Object(parts)) => Has::Parts(
            parts
                .iter()
                .map(|(alias, part)| (alias.clone(), read_part(part, name, alias, problems)))
                .collect(),
        ),
        Some(_) => {
            add_problem(
                problems,
                field_name(&["subjects", name, "has"]),
                "not an object",
            );
            Has::NotAnObject
        }
    }
}

fn read_subject(name: &str, value: &Value) -> Subject {
    let mut problems = Problems::new();
    let def = match value {
        Value::Null => Some(SubjectDef {
            description: String::new(),
            from: Text::Missing,
            identified_by: Text::Missing,
            has: Has::Missing,
            says_how: false,
        }),
        Value::Object(map) => {
            for key in map.keys() {
                if !["from", "identified_by", "description", "has"].contains(&key.as_str()) {
                    add_problem(
                        &mut problems,
                        field_name(&["subjects", name, key]),
                        "unknown field",
                    );
                }
            }
            for key in ["from", "identified_by"] {
                if text_of(map, key) == Text::Invalid {
                    add_problem(
                        &mut problems,
                        field_name(&["subjects", name, key]),
                        "not a string",
                    );
                }
            }
            if !matches!(
                map.get("description"),
                None | Some(Value::Null) | Some(Value::String(_))
            ) {
                add_problem(
                    &mut problems,
                    field_name(&["subjects", name, "description"]),
                    "not a string",
                );
            }
            let has = read_has(map, name, &mut problems);
            Some(SubjectDef {
                description: reported_description(map),
                from: text_of(map, "from"),
                identified_by: text_of(map, "identified_by"),
                has,
                says_how: map.contains_key("applies_to") || map.contains_key("of"),
            })
        }
        _ => {
            add_problem(
                &mut problems,
                field_name(&["subjects", name]),
                "not an object",
            );
            None
        }
    };
    for problem in written_name_problems(name) {
        add_problem(&mut problems, field_name(&["subjects", name]), problem);
    }
    Subject { def, problems }
}

fn read_subjects(policy: &Map<String, Value>) -> Subjects {
    match policy.get("subjects") {
        None => Subjects::Map(BTreeMap::new()),
        Some(Value::Object(map)) => Subjects::Map(
            map.iter()
                .map(|(name, def)| (name.clone(), read_subject(name, def)))
                .collect(),
        ),
        Some(_) => Subjects::NotAnObject,
    }
}

fn string_lines(value: &Value) -> Option<Vec<Option<String>>> {
    match value {
        Value::String(text) => Some(vec![Some(text.clone())]),
        Value::Array(items) => Some(
            items
                .iter()
                .map(|item| item.as_str().map(str::to_string))
                .collect(),
        ),
        _ => None,
    }
}

fn read_option(value: &Value) -> OptionLines {
    match value {
        Value::String(_) => OptionLines::Lines(string_lines(value).unwrap_or_default()),
        Value::Array(items) if items.iter().all(Value::is_string) => {
            OptionLines::Lines(string_lines(value).unwrap_or_default())
        }
        _ => OptionLines::Invalid,
    }
}

fn read_any_of(
    value: &Value,
    problems: &mut BTreeSet<String>,
) -> Option<BTreeMap<String, OptionLines>> {
    match value {
        Value::Object(options) if options.is_empty() => {
            problems.insert("empty any_of".to_string());
            Some(BTreeMap::new())
        }
        Value::Object(options) => Some(
            options
                .iter()
                .map(|(name, option)| {
                    let read = read_option(option);
                    let wrong = written_name_problems(name);
                    match &read {
                        _ if !wrong.is_empty() => {
                            for problem in wrong {
                                problems.insert(format!("option {name}: {problem}"));
                            }
                        }
                        OptionLines::Lines(lines) if lines.is_empty() => {
                            problems.insert(format!("empty option {name}"));
                        }
                        OptionLines::Invalid => {
                            problems.insert(format!("invalid option {name}"));
                        }
                        OptionLines::Lines(_) => {}
                    }
                    (name.clone(), read)
                })
                .collect(),
        ),
        _ => {
            problems.insert("invalid any_of".to_string());
            None
        }
    }
}

fn read_assert(map: &Map<String, Value>, problems: &mut BTreeSet<String>) -> Vec<Option<String>> {
    match map.get("assert") {
        None => {
            problems.insert("missing assert".to_string());
            Vec::new()
        }
        Some(Value::String(text)) => vec![Some(text.clone())],
        Some(Value::Array(items)) if items.is_empty() => {
            problems.insert("empty assert".to_string());
            Vec::new()
        }
        Some(Value::Array(items)) => {
            if !items.iter().all(Value::is_string) {
                problems.insert("invalid assert".to_string());
            }
            items
                .iter()
                .map(|item| item.as_str().map(str::to_string))
                .collect()
        }
        Some(_) => {
            problems.insert("invalid assert".to_string());
            vec![None]
        }
    }
}

fn read_check(value: &Value) -> Check {
    let mut problems = BTreeSet::new();
    let map = match value {
        Value::String(text) => {
            return Check {
                description: String::new(),
                meta: empty_meta(),
                form: Form::Line(text.clone()),
                problems,
            };
        }
        Value::Object(map) => map,
        _ => {
            problems.insert("invalid check".to_string());
            return Check {
                description: String::new(),
                meta: empty_meta(),
                form: Form::Invalid,
                problems,
            };
        }
    };
    if !matches!(
        map.get("description"),
        None | Some(Value::Null) | Some(Value::String(_))
    ) {
        problems.insert("invalid description".to_string());
    }
    if !matches!(
        map.get("meta"),
        None | Some(Value::Null) | Some(Value::Object(_))
    ) {
        problems.insert("invalid meta".to_string());
    }
    for flaw in meta_number_flaws(map) {
        problems.insert(flaw.to_string());
    }
    let any_of_form = map.contains_key("any_of") && !map.contains_key("assert");
    let allowed: &[&str] = if any_of_form {
        &["any_of", "description", "meta"]
    } else {
        &["assert", "description", "meta", "for"]
    };
    for key in map.keys() {
        if !allowed.contains(&key.as_str()) {
            problems.insert(format!("unknown field {key}"));
        }
    }
    let form = if any_of_form {
        Form::AnyOf(
            map.get("any_of")
                .and_then(|options| read_any_of(options, &mut problems)),
        )
    } else {
        let for_line = match map.get("for") {
            Some(Value::String(text)) => Some(text.clone()),
            Some(_) => {
                problems.insert("invalid for".to_string());
                None
            }
            None => None,
        };
        if map.contains_key("assert") {
            Form::Assert {
                lines: read_assert(map, &mut problems),
                for_line,
            }
        } else {
            problems.insert("missing assert".to_string());
            Form::MissingAssert
        }
    };
    Check {
        description: reported_description(map),
        meta: reported_meta(map),
        form,
        problems,
    }
}

fn subject_name(map: &Map<String, Value>) -> SubjectName {
    match map.get("subject") {
        None => SubjectName::Missing,
        Some(Value::String(text)) if !text.trim().is_empty() => SubjectName::Named(text.clone()),
        Some(other) => SubjectName::Invalid(other.clone()),
    }
}

const MAX_MIN_SUBJECTS: u64 = 1_000_000;

const NOT_A_MIN_SUBJECTS: &str = "not a whole number from 0 to 1000000";

fn read_min_subjects(map: &Map<String, Value>, problems: &mut Problems) -> (Value, u64) {
    match map.get("min_subjects") {
        None => (Value::from(1), 1),
        Some(Value::Number(number)) if !fits_a_float(number) => {
            add_problem(problems, "min_subjects".to_string(), "number out of range");
            (Value::Number(number.clone()), 1)
        }
        Some(Value::Number(number)) if too_long(number) => {
            add_problem(
                problems,
                "min_subjects".to_string(),
                "number with more than 15 significant digits",
            );
            (Value::Number(number.clone()), 1)
        }
        Some(Value::Number(number)) => {
            let count = Decimal::parse(&number.to_string())
                .filter(Decimal::is_non_negative_whole)
                .and_then(|decimal| decimal.as_position())
                .filter(|count| *count <= MAX_MIN_SUBJECTS);
            match count {
                Some(count) => (Value::Number(number.clone()), count),
                None => {
                    add_problem(problems, "min_subjects".to_string(), NOT_A_MIN_SUBJECTS);
                    (Value::Number(number.clone()), 1)
                }
            }
        }
        Some(other) => {
            add_problem(problems, "min_subjects".to_string(), NOT_A_MIN_SUBJECTS);
            (other.clone(), 1)
        }
    }
}

fn read_requirement(value: &Value, subjects: &Subjects) -> Requirement {
    let map = match value {
        Value::Object(map) => map,
        other => {
            return Requirement {
                description: String::new(),
                meta: empty_meta(),
                not_an_object: Some(other.clone()),
                subject: SubjectName::Missing,
                require: Value::from("every"),
                min_subjects: Value::from(1),
                min_subjects_count: 1,
                checks: BTreeMap::new(),
                checks_count: 0,
                problems: Problems::new(),
            };
        }
    };
    let mut problems = Problems::new();
    let subject = subject_name(map);
    match &subject {
        SubjectName::Missing => add_problem(&mut problems, "subject".to_string(), "missing"),
        SubjectName::Invalid(_) => add_problem(
            &mut problems,
            "subject".to_string(),
            "empty or not a string",
        ),
        SubjectName::Named(name) => match subjects {
            Subjects::NotAnObject => {
                add_problem(&mut problems, "subjects".to_string(), "not an object")
            }
            Subjects::Map(map) => match map.get(name) {
                None => add_problem(&mut problems, "subject".to_string(), "not in subjects"),
                Some(found) => merge_problems(&mut problems, &found.problems),
            },
        },
    }
    let require = map
        .get("require")
        .cloned()
        .unwrap_or_else(|| Value::from("every"));
    if !matches!(require.as_str(), Some("every") | Some("some")) {
        add_problem(
            &mut problems,
            "require".to_string(),
            "neither every nor some",
        );
    }
    let (min_subjects, min_subjects_count) = read_min_subjects(map, &mut problems);
    if !matches!(
        map.get("description"),
        None | Some(Value::Null) | Some(Value::String(_))
    ) {
        add_problem(&mut problems, "description".to_string(), "not a string");
    }
    if !matches!(
        map.get("meta"),
        None | Some(Value::Null) | Some(Value::Object(_))
    ) {
        add_problem(&mut problems, "meta".to_string(), "not an object");
    }
    for flaw in meta_number_flaws(map) {
        add_problem(&mut problems, "meta".to_string(), flaw);
    }
    for key in map.keys() {
        if ![
            "subject",
            "checks",
            "require",
            "min_subjects",
            "description",
            "meta",
        ]
        .contains(&key.as_str())
        {
            add_problem(&mut problems, field_name(&[key]), "unknown field");
        }
    }
    let checks: BTreeMap<String, Check> = match map.get("checks") {
        None => {
            add_problem(&mut problems, "checks".to_string(), "missing");
            BTreeMap::new()
        }
        Some(Value::Object(checks)) => {
            if checks.is_empty() {
                add_problem(&mut problems, "checks".to_string(), "empty");
            }
            checks
                .iter()
                .map(|(name, check)| (name.clone(), read_check(check)))
                .collect()
        }
        Some(_) => {
            add_problem(&mut problems, "checks".to_string(), "not an object");
            BTreeMap::new()
        }
    };
    for (name, check) in &checks {
        for problem in &check.problems {
            add_problem(
                &mut problems,
                field_name(&["checks", name]),
                problem.clone(),
            );
        }
        for problem in written_name_problems(name) {
            add_problem(&mut problems, field_name(&["checks", name]), problem);
        }
    }
    Requirement {
        description: reported_description(map),
        meta: reported_meta(map),
        not_an_object: None,
        subject,
        require,
        min_subjects,
        min_subjects_count,
        checks_count: checks.len() as u64,
        checks,
        problems,
    }
}

impl Policy {
    pub fn read(policy: &Value) -> Policy {
        let map = match policy {
            Value::Object(map) => map,
            _ => {
                let mut problems = Problems::new();
                problems.insert(
                    "policy".to_string(),
                    BTreeSet::from(["not an object".to_string()]),
                );
                return Policy {
                    description: String::new(),
                    meta: empty_meta(),
                    problems,
                    subjects: Subjects::Map(BTreeMap::new()),
                    requirements: BTreeMap::new(),
                    requirements_problem: "",
                };
            }
        };
        let subjects = read_subjects(map);
        let requirements = match map.get("requirements") {
            Some(Value::Object(requirements)) => requirements
                .iter()
                .map(|(name, req)| (name.clone(), read_requirement(req, &subjects)))
                .collect(),
            _ => BTreeMap::new(),
        };
        let requirements_problem = match map.get("requirements") {
            None | Some(Value::Null) => "missing",
            Some(Value::Object(found)) if found.is_empty() => "empty",
            Some(Value::Object(_)) => "",
            Some(_) => "not an object",
        };
        Policy {
            description: reported_description(map),
            meta: reported_meta(map),
            problems: policy_problems(map),
            subjects,
            requirements,
            requirements_problem,
        }
    }

    pub fn subject(&self, name: &str) -> Option<&Subject> {
        match &self.subjects {
            Subjects::Map(map) => map.get(name),
            Subjects::NotAnObject => None,
        }
    }

    pub fn subject_of(&self, requirement: &Requirement) -> Option<(&str, &Subject)> {
        match (&requirement.subject, &self.subjects) {
            (SubjectName::Named(name), Subjects::Map(map)) => {
                map.get_key_value(name).map(|(k, v)| (k.as_str(), v))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests;
