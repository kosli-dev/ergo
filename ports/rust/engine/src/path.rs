use crate::cause::Cause;
use crate::value::Decimal;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Start {
    Subject,
    Input,
    Params,
    Alias(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    Key(String),
    Index(u64),
    Ref(Box<Path>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Path {
    pub start: Start,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    Found,
    Null,
    Absent,
    Unusable,
    NotAnObject,
}

impl Outcome {
    pub fn cause(self) -> Option<Cause> {
        match self {
            Outcome::Found => None,
            Outcome::Null => Some(Cause::Null),
            Outcome::Absent => Some(Cause::Absent),
            Outcome::Unusable => Some(Cause::Unusable),
            Outcome::NotAnObject => Some(Cause::NotAnObject),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Root {
    Input,
    Params,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Location {
    pub root: Root,
    pub pointer: String,
}

fn escape_token(token: &str) -> String {
    token.replace('~', "~0").replace('/', "~1")
}

impl Location {
    pub fn input_root() -> Location {
        Location {
            root: Root::Input,
            pointer: String::new(),
        }
    }

    pub fn params_root() -> Location {
        Location {
            root: Root::Params,
            pointer: String::new(),
        }
    }

    pub fn key(&self, key: &str) -> Location {
        Location {
            root: self.root,
            pointer: format!("{}/{}", self.pointer, escape_token(key)),
        }
    }

    pub fn index(&self, index: u64) -> Location {
        Location {
            root: self.root,
            pointer: format!("{}/{}", self.pointer, index),
        }
    }

    pub fn render(&self) -> String {
        match self.root {
            Root::Input => self.pointer.clone(),
            Root::Params => format!("$params:{}", self.pointer),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Located<'a> {
    pub value: &'a Value,
    pub location: Location,
}

#[derive(Debug, Clone)]
pub struct Ctx<'a> {
    pub subject: Located<'a>,
    pub input: &'a Value,
    pub params: Option<&'a Value>,
    pub aliases: BTreeMap<String, Located<'a>>,
}

#[derive(Debug, Clone)]
pub struct Read<'a> {
    pub outcome: Outcome,
    pub value: Option<&'a Value>,
    pub location: Option<Location>,
}

enum Resolved {
    Key(String),
    Index(u64),
}

fn ended<'a>(outcome: Outcome, location: Location) -> Read<'a> {
    Read {
        outcome,
        value: None,
        location: Some(location),
    }
}

fn resolve(step: &Step, ctx: &Ctx) -> Result<Resolved, Outcome> {
    match step {
        Step::Key(key) => Ok(Resolved::Key(key.clone())),
        Step::Index(index) => Ok(Resolved::Index(*index)),
        Step::Ref(reference) => {
            let read = read(reference, ctx);
            if read.outcome != Outcome::Found {
                return Err(read.outcome);
            }
            match read.value {
                Some(Value::String(text)) => Ok(Resolved::Key(text.clone())),
                Some(Value::Number(number)) => Decimal::parse(&number.to_string())
                    .and_then(|d| d.as_position())
                    .map(Resolved::Index)
                    .ok_or(Outcome::Unusable),
                _ => Err(Outcome::Unusable),
            }
        }
    }
}

pub fn read<'a>(path: &Path, ctx: &Ctx<'a>) -> Read<'a> {
    let (mut value, mut location, from_subject) = match &path.start {
        Start::Subject => (ctx.subject.value, ctx.subject.location.clone(), true),
        Start::Input => (ctx.input, Location::input_root(), false),
        Start::Params => match ctx.params {
            Some(params) => (params, Location::params_root(), false),
            None => return ended(Outcome::Absent, Location::params_root()),
        },
        Start::Alias(name) => match ctx.aliases.get(name) {
            Some(found) => (found.value, found.location.clone(), true),
            None => {
                return Read {
                    outcome: Outcome::Absent,
                    value: None,
                    location: None,
                };
            }
        },
    };
    for (at, step) in path.steps.iter().enumerate() {
        let resolved = match resolve(step, ctx) {
            Ok(resolved) => resolved,
            Err(outcome) => return ended(outcome, location),
        };
        if at == 0 && from_subject && !value.is_object() && !matches!(resolved, Resolved::Index(_))
        {
            return ended(Outcome::NotAnObject, location);
        }
        match (resolved, value) {
            (_, Value::Null) => return ended(Outcome::Absent, location),
            (Resolved::Key(key), Value::Object(map)) => match map.get(&key) {
                Some(next) => {
                    location = location.key(&key);
                    value = next;
                }
                None => return ended(Outcome::Absent, location),
            },
            (Resolved::Index(index), Value::Array(items)) => {
                match usize::try_from(index).ok().and_then(|i| items.get(i)) {
                    Some(next) => {
                        location = location.index(index);
                        value = next;
                    }
                    None => return ended(Outcome::Absent, location),
                }
            }
            _ => return ended(Outcome::Unusable, location),
        }
    }
    let outcome = if value.is_null() {
        Outcome::Null
    } else {
        Outcome::Found
    };
    Read {
        outcome,
        value: Some(value),
        location: Some(location),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(text: &str) -> Value {
        serde_json::from_str(text).unwrap()
    }

    fn key(k: &str) -> Step {
        Step::Key(k.to_string())
    }

    fn at(start: Start, steps: Vec<Step>) -> Path {
        Path { start, steps }
    }

    fn subject_path(steps: Vec<Step>) -> Path {
        at(Start::Subject, steps)
    }

    struct World {
        subject: Value,
        input: Value,
        params: Option<Value>,
    }

    impl World {
        fn new(subject: &str) -> World {
            World {
                subject: v(subject),
                input: v("{}"),
                params: None,
            }
        }

        fn with_input(mut self, input: &str) -> World {
            self.input = v(input);
            self
        }

        fn with_params(mut self, params: &str) -> World {
            self.params = Some(v(params));
            self
        }

        fn run(&self, path: &Path) -> (Outcome, Option<Value>, Option<String>) {
            let ctx = Ctx {
                subject: Located {
                    value: &self.subject,
                    location: Location::input_root().key("s"),
                },
                input: &self.input,
                params: self.params.as_ref(),
                aliases: BTreeMap::new(),
            };
            let r = read(path, &ctx);
            (r.outcome, r.value.cloned(), r.location.map(|l| l.render()))
        }
    }

    fn loc(s: &str) -> Option<String> {
        Some(s.to_string())
    }

    #[test]
    fn a_present_value_is_found_at_its_own_location() {
        let w = World::new(r#"{"a": {"b": 1}}"#);
        let (o, value, l) = w.run(&subject_path(vec![key("a"), key("b")]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("1")));
        assert_eq!(l, loc("/s/a/b"));
    }

    #[test]
    fn false_and_empty_values_are_found_not_null() {
        let w = World::new(r#"{"a": false, "b": "", "c": []}"#);
        for k in ["a", "b", "c"] {
            assert_eq!(w.run(&subject_path(vec![key(k)])).0, Outcome::Found);
        }
    }

    #[test]
    fn a_path_without_steps_reads_the_subject_whatever_it_is() {
        for text in ["1", "\"s\"", "[1]", "{}", "false"] {
            let (o, value, l) = World::new(text).run(&subject_path(vec![]));
            assert_eq!(o, Outcome::Found, "{text}");
            assert_eq!(value, Some(v(text)));
            assert_eq!(l, loc("/s"));
        }
    }

    #[test]
    fn a_null_subject_without_steps_is_null_not_not_an_object() {
        let (o, value, l) = World::new("null").run(&subject_path(vec![]));
        assert_eq!(o, Outcome::Null);
        assert_eq!(value, Some(Value::Null));
        assert_eq!(l, loc("/s"));
    }

    #[test]
    fn a_key_on_a_subject_that_is_not_an_object_is_not_an_object() {
        for text in ["null", "1", "\"s\"", "[1]", "true"] {
            let (o, value, l) = World::new(text).run(&subject_path(vec![key("a")]));
            assert_eq!(o, Outcome::NotAnObject, "{text}");
            assert_eq!(value, None);
            assert_eq!(l, loc("/s"));
        }
    }

    #[test]
    fn a_key_on_an_alias_that_is_not_an_object_is_not_an_object() {
        let w = World::new("{}");
        let alias_value = v("[1]");
        let mut aliases = BTreeMap::new();
        aliases.insert(
            "pr".to_string(),
            Located {
                value: &alias_value,
                location: Location::input_root().key("prs").index(0),
            },
        );
        let ctx = Ctx {
            subject: Located {
                value: &w.subject,
                location: Location::input_root(),
            },
            input: &w.input,
            params: None,
            aliases,
        };
        let r = read(&at(Start::Alias("pr".into()), vec![key("a")]), &ctx);
        assert_eq!(r.outcome, Outcome::NotAnObject);
        assert_eq!(r.location.unwrap().render(), "/prs/0");
        let r = read(&at(Start::Alias("pr".into()), vec![]), &ctx);
        assert_eq!(r.outcome, Outcome::Found);
    }

    #[test]
    fn an_alias_nothing_holds_is_absent_with_no_location() {
        let w = World::new("{}");
        let ctx = Ctx {
            subject: Located {
                value: &w.subject,
                location: Location::input_root(),
            },
            input: &w.input,
            params: None,
            aliases: BTreeMap::new(),
        };
        let r = read(&at(Start::Alias("nope".into()), vec![key("a")]), &ctx);
        assert_eq!(r.outcome, Outcome::Absent);
        assert!(r.location.is_none());
    }

    #[test]
    fn a_position_on_a_null_subject_is_absent_and_on_an_empty_list_too() {
        let p = subject_path(vec![Step::Index(0)]);
        assert_eq!(World::new("null").run(&p).0, Outcome::Absent);
        assert_eq!(World::new("[]").run(&p).0, Outcome::Absent);
    }

    #[test]
    fn a_position_on_a_string_subject_is_unusable() {
        let p = subject_path(vec![Step::Index(0)]);
        let (o, _, l) = World::new("\"s\"").run(&p);
        assert_eq!(o, Outcome::Unusable);
        assert_eq!(l, loc("/s"));
    }

    #[test]
    fn a_position_on_an_object_subject_is_unusable() {
        let (o, _, _) = World::new("{\"0\": 1}").run(&subject_path(vec![Step::Index(0)]));
        assert_eq!(o, Outcome::Unusable);
    }

    #[test]
    fn a_position_on_a_list_subject_reads_the_item() {
        let (o, value, l) = World::new("[5, 6]").run(&subject_path(vec![Step::Index(1)]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("6")));
        assert_eq!(l, loc("/s/1"));
    }

    #[test]
    fn a_missing_key_is_absent_and_points_at_the_object() {
        let (o, value, l) =
            World::new(r#"{"a": {"b": 1}}"#).run(&subject_path(vec![key("a"), key("c")]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(value, None);
        assert_eq!(l, loc("/s/a"));
    }

    #[test]
    fn an_index_past_the_end_is_absent_and_points_at_the_short_list() {
        let (o, _, l) =
            World::new(r#"{"xs": [1, 2]}"#).run(&subject_path(vec![key("xs"), Step::Index(2)]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(l, loc("/s/xs"));
    }

    #[test]
    fn steps_after_a_missing_value_stay_absent() {
        let (o, _, l) = World::new(r#"{"a": {}}"#).run(&subject_path(vec![
            key("a"),
            key("b"),
            key("c"),
            key("d"),
        ]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(l, loc("/s/a"));
    }

    #[test]
    fn steps_after_null_are_absent_and_point_at_the_null() {
        let (o, _, l) = World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a"), key("b")]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(l, loc("/s/a"));
        let (o, _, _) =
            World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a"), Step::Index(0)]));
        assert_eq!(o, Outcome::Absent);
    }

    #[test]
    fn a_last_step_that_reads_null_is_null() {
        let (o, value, l) = World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a")]));
        assert_eq!(o, Outcome::Null);
        assert_eq!(value, Some(Value::Null));
        assert_eq!(l, loc("/s/a"));
    }

    #[test]
    fn a_key_on_a_string_is_unusable() {
        let (o, _, l) = World::new(r#"{"x": "a"}"#).run(&subject_path(vec![key("x"), key("y")]));
        assert_eq!(o, Outcome::Unusable);
        assert_eq!(l, loc("/s/x"));
    }

    #[test]
    fn a_key_on_a_list_is_unusable() {
        let (o, _, l) =
            World::new(r#"{"x": [{"y": 1}]}"#).run(&subject_path(vec![key("x"), key("y")]));
        assert_eq!(o, Outcome::Unusable);
        assert_eq!(l, loc("/s/x"));
    }

    #[test]
    fn an_index_on_an_object_is_unusable() {
        let (o, _, l) =
            World::new(r#"{"x": {"1": "a"}}"#).run(&subject_path(vec![key("x"), Step::Index(1)]));
        assert_eq!(o, Outcome::Unusable);
        assert_eq!(l, loc("/s/x"));
    }

    #[test]
    fn any_step_after_a_scalar_is_unusable() {
        for text in [r#"{"x": 1}"#, r#"{"x": true}"#, r#"{"x": "s"}"#] {
            for step in [key("y"), Step::Index(0)] {
                let (o, _, _) = World::new(text).run(&subject_path(vec![key("x"), step]));
                assert_eq!(o, Outcome::Unusable, "{text}");
            }
        }
    }

    #[test]
    fn input_paths_start_at_the_input_root() {
        let w = World::new("{}").with_input(r#"{"a": [{"b": 2}]}"#);
        let p = at(Start::Input, vec![key("a"), Step::Index(0), key("b")]);
        let (o, value, l) = w.run(&p);
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("2")));
        assert_eq!(l, loc("/a/0/b"));
    }

    #[test]
    fn an_input_that_is_not_an_object_does_not_give_not_an_object() {
        let w = World::new("{}").with_input("[1]");
        let (o, _, l) = w.run(&at(Start::Input, vec![key("a")]));
        assert_eq!(o, Outcome::Unusable);
        assert_eq!(l, loc(""));
    }

    #[test]
    fn the_input_root_is_found_with_an_empty_pointer() {
        let w = World::new("{}").with_input("{}");
        assert_eq!(w.run(&at(Start::Input, vec![])).2, loc(""));
    }

    #[test]
    fn params_paths_point_into_the_params() {
        let w = World::new("{}").with_params(r#"{"max": {"high": 3}}"#);
        let (o, value, l) = w.run(&at(Start::Params, vec![key("max"), key("high")]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("3")));
        assert_eq!(l, loc("$params:/max/high"));
    }

    #[test]
    fn no_params_ends_absent_at_the_params_root() {
        let w = World::new("{}");
        for steps in [vec![], vec![key("a")], vec![key("a"), key("b")]] {
            let (o, value, l) = w.run(&at(Start::Params, steps));
            assert_eq!(o, Outcome::Absent);
            assert_eq!(value, None);
            assert_eq!(l, loc("$params:"));
        }
    }

    #[test]
    fn a_missing_params_key_points_at_the_params_root() {
        let w = World::new("{}").with_params("{}");
        let (o, _, l) = w.run(&at(Start::Params, vec![key("a")]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(l, loc("$params:"));
    }

    #[test]
    fn keys_are_escaped_in_pointers() {
        let w = World::new(r#"{"a/b": {"c~d": 1}}"#);
        let (_, _, l) = w.run(&subject_path(vec![key("a/b"), key("c~d")]));
        assert_eq!(l, loc("/s/a~1b/c~0d"));
    }

    #[test]
    fn a_tilde_is_escaped_before_a_slash() {
        assert_eq!(Location::input_root().key("~1").render(), "/~01");
    }

    #[test]
    fn a_ref_step_reads_the_key_it_holds() {
        let w = World::new(r#"{"limits": {"high": 3, "low": 9}, "sev": "high"}"#)
            .with_params(r#"{"k": "low"}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("limits"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("9")));
        assert_eq!(l, loc("/s/limits/low"));
    }

    #[test]
    fn a_ref_step_with_a_whole_number_reads_a_list_item() {
        let w = World::new(r#"{"xs": [10, 20, 30]}"#).with_params(r#"{"i": 2.0}"#);
        let reference = at(Start::Params, vec![key("i")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("xs"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("30")));
        assert_eq!(l, loc("/s/xs/2"));
    }

    #[test]
    fn a_ref_that_is_missing_ends_the_path_absent_before_the_step() {
        let w = World::new(r#"{"limits": {"high": 3}}"#).with_params("{}");
        let reference = at(Start::Params, vec![key("k")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("limits"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(value, None);
        assert_eq!(l, loc("/s/limits"));
    }

    #[test]
    fn a_ref_with_no_params_ends_absent() {
        let w = World::new(r#"{"limits": {}}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, _, l) = w.run(&subject_path(vec![
            key("limits"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(l, loc("/s/limits"));
    }

    #[test]
    fn a_ref_that_reads_null_ends_the_path_null() {
        let w = World::new(r#"{"limits": {"null": 1}}"#).with_params(r#"{"k": null}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, value, _) = w.run(&subject_path(vec![
            key("limits"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Null);
        assert_eq!(value, None);
    }

    #[test]
    fn a_ref_that_cannot_be_read_beats_a_subject_that_is_not_an_object() {
        let w = World::new("1").with_params("{}");
        let reference = at(Start::Params, vec![key("k")]);
        let (o, _, _) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
        assert_eq!(o, Outcome::Absent);
    }

    #[test]
    fn a_ref_step_on_a_subject_that_is_not_an_object_is_not_an_object() {
        let w = World::new("1").with_params(r#"{"k": "a"}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, _, l) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
        assert_eq!(o, Outcome::NotAnObject);
        assert_eq!(l, loc("/s"));
    }

    #[test]
    fn a_ref_holding_a_number_on_a_subject_list_reads_the_item() {
        let w = World::new("[7, 8]").with_params(r#"{"k": 1}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, value, _) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("8")));
    }

    #[test]
    fn a_ref_value_that_cannot_be_a_key_is_unusable() {
        for params in [
            r#"{"k": true}"#,
            r#"{"k": 1.5}"#,
            r#"{"k": -1}"#,
            r#"{"k": [0]}"#,
            r#"{"k": {"a": 1}}"#,
            r#"{"k": 9007199254740992}"#,
            r#"{"k": 1e400}"#,
        ] {
            let w = World::new(r#"{"xs": [1], "o": {"a": 1}}"#).with_params(params);
            let reference = at(Start::Params, vec![key("k")]);
            let (o, value, l) = w.run(&subject_path(vec![
                key("xs"),
                Step::Ref(Box::new(reference)),
            ]));
            assert_eq!(o, Outcome::Unusable, "{params}");
            assert_eq!(value, None);
            assert_eq!(l, loc("/s/xs"));
        }
    }

    #[test]
    fn a_string_ref_on_a_list_is_unusable() {
        let w = World::new(r#"{"xs": [1]}"#).with_params(r#"{"k": "0"}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, _, _) = w.run(&subject_path(vec![
            key("xs"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Unusable);
    }

    #[test]
    fn a_number_ref_on_an_object_is_unusable() {
        let w = World::new(r#"{"o": {"1": 1}}"#).with_params(r#"{"k": 1}"#);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, _, _) = w.run(&subject_path(vec![
            key("o"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Unusable);
    }

    #[test]
    fn a_ref_can_read_the_input() {
        let w = World::new(r#"{"o": {"x": 1}}"#).with_input(r#"{"which": "x"}"#);
        let reference = at(Start::Input, vec![key("which")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("o"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Found);
        assert_eq!(value, Some(v("1")));
        assert_eq!(l, loc("/s/o/x"));
    }

    #[test]
    fn outcomes_give_their_causes() {
        assert_eq!(Outcome::Found.cause(), None);
        assert_eq!(Outcome::Null.cause(), Some(Cause::Null));
        assert_eq!(Outcome::Absent.cause(), Some(Cause::Absent));
        assert_eq!(Outcome::Unusable.cause(), Some(Cause::Unusable));
        assert_eq!(Outcome::NotAnObject.cause(), Some(Cause::NotAnObject));
    }
}
