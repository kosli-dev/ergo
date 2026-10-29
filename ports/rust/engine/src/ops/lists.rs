use super::compare::joined;
use super::kinds::{Empty, HasType, Kind, NonEmptyString};
use super::{Check, Input, Verdict, read_path, verdict};
use crate::cause::Cause;
use crate::lower::Scope;
use crate::path::{Ctx, Outcome, Path, Start, is_ref, step_refs};
use crate::value;
use ergo_sentences as tree;
use regex::Regex;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq)]
pub enum Right {
    Written(Value),
    Ref(Path),
    Field(Path),
}

impl Right {
    pub fn refs(&self) -> Vec<Path> {
        match self {
            Right::Written(_) => Vec::new(),
            Right::Ref(path) if is_ref(path) => std::iter::once(path.clone())
                .chain(step_refs(path))
                .collect(),
            Right::Ref(path) => step_refs(path),
            Right::Field(path) => step_refs(path),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct In {
    pub path: Path,
    pub values: Right,
    pub not: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Wanted {
    One(Right),
    All(Right),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Contains {
    pub path: Path,
    pub wanted: Wanted,
    pub not: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Matches {
    pub path: Path,
    pub patterns: Right,
    pub not: bool,
}

impl Right {
    fn shown_path(&self) -> Option<&Path> {
        match self {
            Right::Written(_) | Right::Ref(_) => None,
            Right::Field(path) => Some(path),
        }
    }
}

impl In {
    pub fn paths(&self) -> Vec<&Path> {
        std::iter::once(&self.path)
            .chain(self.values.shown_path())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
            .into_iter()
            .chain(self.values.refs())
            .collect()
    }
}

impl Contains {
    pub fn paths(&self) -> Vec<&Path> {
        let right = match &self.wanted {
            Wanted::One(right) | Wanted::All(right) => right,
        };
        std::iter::once(&self.path)
            .chain(right.shown_path())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        let right = match &self.wanted {
            Wanted::One(right) | Wanted::All(right) => right,
        };
        step_refs(&self.path)
            .into_iter()
            .chain(right.refs())
            .collect()
    }
}

impl Matches {
    pub fn paths(&self) -> Vec<&Path> {
        std::iter::once(&self.path)
            .chain(self.patterns.shown_path())
            .collect()
    }

    pub fn refs(&self) -> Vec<Path> {
        step_refs(&self.path)
            .into_iter()
            .chain(self.patterns.refs())
            .collect()
    }
}

struct RightRead {
    outcome: Outcome,
    value: Option<Value>,
    inputs: Vec<Input>,
}

fn read_right(right: &Right, ctx: &Ctx) -> RightRead {
    match right {
        Right::Written(value) => RightRead {
            outcome: Outcome::Found,
            value: Some(value.clone()),
            inputs: Vec::new(),
        },
        Right::Ref(path) => {
            let read = read_path(path, ctx);
            RightRead {
                outcome: read.outcome,
                value: read.value,
                inputs: read.inputs.into_iter().skip(1).collect(),
            }
        }
        Right::Field(path) => {
            let read = read_path(path, ctx);
            RightRead {
                outcome: read.outcome,
                value: read.value,
                inputs: read.inputs,
            }
        }
    }
}

fn one_type<'a>(values: impl Iterator<Item = &'a Value>) -> Result<Option<&'static str>, ()> {
    let mut kind = None;
    for v in values.filter(|v| !v.is_null()) {
        let name = value::type_name(v);
        match kind {
            None => kind = Some(name),
            Some(seen) if seen != name => return Err(()),
            Some(_) => {}
        }
    }
    Ok(kind)
}

fn judged<F>(path: &Path, right: &Right, ctx: &Ctx, decide: F) -> Verdict
where
    F: FnOnce(&Value, &Outcome, Option<&Value>) -> Cause,
{
    let read = read_right(right, ctx);
    let left = read_path(path, ctx);
    let inputs = left.inputs.into_iter().chain(read.inputs).collect();
    let cause = match (read.outcome.cause(), &read.value) {
        (Some(cause), _) => cause,
        (None, Some(right_value)) => decide(right_value, &left.outcome, left.value.as_ref()),
        (None, None) => Cause::Unusable,
    };
    Verdict { cause, inputs }
}

fn left_cause(outcome: &Outcome, found: Option<&Value>) -> Result<Value, Cause> {
    match (outcome.cause(), found) {
        (Some(cause), _) => Err(cause),
        (None, Some(v)) => Ok(v.clone()),
        (None, None) => Err(Cause::Unusable),
    }
}

fn ref_read(right: &Right, ctx: &Ctx) -> Option<Value> {
    match right {
        Right::Ref(path) => {
            let read = read_path(path, ctx);
            match read.outcome {
                Outcome::Found => read.value,
                _ => None,
            }
        }
        Right::Written(_) | Right::Field(_) => None,
    }
}

fn usable_values(values: &Value, non_empty: bool) -> bool {
    match values {
        Value::Array(items) => (!non_empty || !items.is_empty()) && one_type(items.iter()).is_ok(),
        _ => false,
    }
}

fn usable_patterns(patterns: &Value) -> bool {
    match patterns {
        Value::Array(items) => items.iter().all(|p| compiled(p).is_some()),
        _ => false,
    }
}

impl In {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        ref_read(&self.values, ctx).is_some_and(|v| !usable_values(&v, false))
    }
}

impl Contains {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        match &self.wanted {
            Wanted::One(_) => false,
            Wanted::All(right) => ref_read(right, ctx).is_some_and(|v| !usable_values(&v, true)),
        }
    }
}

impl Matches {
    pub fn flawed(&self, ctx: &Ctx) -> bool {
        ref_read(&self.patterns, ctx).is_some_and(|v| !usable_patterns(&v))
    }
}

pub fn run_in(check: &In, ctx: &Ctx) -> Verdict {
    judged(&check.path, &check.values, ctx, |values, outcome, found| {
        let Value::Array(values) = values else {
            return Cause::Unusable;
        };
        let Ok(kind) = one_type(values.iter()) else {
            return Cause::Unusable;
        };
        let found = match left_cause(outcome, found) {
            Ok(v) => v,
            Err(cause) => return cause,
        };
        if values.is_empty() {
            return verdict(check.not);
        }
        if kind.is_some_and(|k| k != value::type_name(&found)) {
            return Cause::Unusable;
        }
        let Some(hits) = values
            .iter()
            .map(|v| value::equal(&found, v))
            .collect::<Option<Vec<bool>>>()
        else {
            return Cause::Unusable;
        };
        verdict(hits.contains(&true) != check.not)
    })
}

pub fn run_contains(check: &Contains, ctx: &Ctx) -> Verdict {
    let (right, all) = match &check.wanted {
        Wanted::One(right) => (right, false),
        Wanted::All(right) => (right, true),
    };
    judged(&check.path, right, ctx, |wanted, outcome, found| {
        let wanted: Vec<Value> = if all {
            match wanted {
                Value::Array(values) if !values.is_empty() => values.clone(),
                _ => return Cause::Unusable,
            }
        } else {
            vec![wanted.clone()]
        };
        if one_type(wanted.iter()).is_err() {
            return Cause::Unusable;
        }
        let items = match left_cause(outcome, found) {
            Ok(Value::Array(items)) => items,
            Ok(_) => return Cause::Unusable,
            Err(cause) => return cause,
        };
        if one_type(items.iter().chain(wanted.iter())).is_err() {
            return Cause::Unusable;
        }
        let Some(held) = wanted
            .iter()
            .map(|w| {
                items
                    .iter()
                    .map(|item| value::equal(item, w))
                    .collect::<Option<Vec<bool>>>()
                    .map(|hits| hits.contains(&true))
            })
            .collect::<Option<Vec<bool>>>()
        else {
            return Cause::Unusable;
        };
        verdict(if check.not {
            !held.contains(&true)
        } else {
            !held.contains(&false)
        })
    })
}

pub fn compiled(pattern: &Value) -> Option<Regex> {
    let text = ergo_sentences::rust_pattern(pattern.as_str()?)?;
    Regex::new(&text).ok()
}

pub fn run_matches(check: &Matches, ctx: &Ctx) -> Verdict {
    judged(
        &check.path,
        &check.patterns,
        ctx,
        |patterns, outcome, found| {
            let Value::Array(patterns) = patterns else {
                return Cause::Unusable;
            };
            let Some(regexes) = patterns.iter().map(compiled).collect::<Option<Vec<_>>>() else {
                return Cause::Unusable;
            };
            let text = match left_cause(outcome, found) {
                Ok(Value::String(text)) => text,
                Ok(_) => return Cause::Unusable,
                Err(cause) => return cause,
            };
            let hit = regexes.iter().any(|r| r.is_match(&text));
            verdict(hit != check.not)
        },
    )
}

fn path_right(path: &tree::Path, scope: &Scope) -> Result<Right, Vec<String>> {
    scope.path(path).map(|p| {
        if matches!(p.start, Start::Params | Start::Input) {
            Right::Ref(p)
        } else {
            Right::Field(p)
        }
    })
}

fn list_right(list: &tree::List, scope: &Scope) -> Result<Right, Vec<String>> {
    match list {
        tree::List::Values(values) => {
            let mut read = Vec::new();
            let mut problems = Vec::new();
            for v in values {
                match scope.value(v) {
                    Ok(v) => read.push(v),
                    Err(found) => problems.extend(found),
                }
            }
            if problems.is_empty() {
                Ok(Right::Written(Value::Array(read)))
            } else {
                Err(problems)
            }
        }
        tree::List::Path(path) => path_right(path, scope),
    }
}

fn one_typed(right: Result<Right, Vec<String>>) -> Result<Right, Vec<String>> {
    match &right {
        Ok(Right::Written(Value::Array(values))) if one_type(values.iter()).is_err() => {
            Err(vec!["values of mixed types".to_string()])
        }
        _ => right,
    }
}

fn operand_right(operand: &tree::Operand, scope: &Scope) -> Option<Result<Right, Vec<String>>> {
    match operand {
        tree::Operand::Value(v) => Some(scope.value(v).map(Right::Written)),
        tree::Operand::Field(terms) => match terms.as_slice() {
            [tree::Term::Path(p)] => Some(path_right(p, scope)),
            _ => None,
        },
    }
}

pub fn lower_phrase(
    path: &tree::Path,
    phrase: &tree::Phrase,
    scope: &Scope,
) -> Option<Result<Check, Vec<String>>> {
    let left = || scope.left_path(path);
    let contains = |wanted: Result<Wanted, Vec<String>>, not: bool| {
        joined(left(), wanted).map(|(path, wanted)| Check::Contains(Contains { path, wanted, not }))
    };
    Some(match phrase {
        tree::Phrase::OneOf { not, list } => joined(left(), one_typed(list_right(list, scope)))
            .map(|(path, values)| {
                Check::In(In {
                    path,
                    values,
                    not: *not,
                })
            }),
        tree::Phrase::Contains { not, operand } => {
            contains(operand_right(operand, scope)?.map(Wanted::One), *not)
        }
        tree::Phrase::ContainsAll(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::All), false)
        }
        tree::Phrase::ContainsNone(list) => {
            contains(one_typed(list_right(list, scope)).map(Wanted::All), true)
        }
        tree::Phrase::Matches { not, list } => {
            joined(left(), list_right(list, scope)).map(|(path, patterns)| {
                Check::Matches(Matches {
                    path,
                    patterns,
                    not: *not,
                })
            })
        }
        tree::Phrase::Type(kind) => left().map(|path| {
            Check::HasType(HasType {
                path,
                kind: match kind {
                    tree::Type::List => Kind::List,
                    tree::Type::String => Kind::String,
                    tree::Type::Number => Kind::Number,
                    tree::Type::Boolean => Kind::Boolean,
                    tree::Type::Object => Kind::Object,
                },
            })
        }),
        tree::Phrase::NonEmptyString => {
            left().map(|path| Check::NonEmptyString(NonEmptyString { path }))
        }
        tree::Phrase::Empty { not } => left().map(|path| Check::Empty(Empty { path, not: *not })),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::path::{Located, Location, Step};
    use serde_json::json;
    use std::collections::BTreeMap;

    fn key_path(start: Start, keys: &[&str]) -> Path {
        Path {
            start,
            steps: keys.iter().map(|k| Step::Key(k.to_string())).collect(),
        }
    }

    fn x() -> Path {
        key_path(Start::Subject, &["x"])
    }

    fn on(subject: Value, params: Option<Value>, run: impl Fn(&Ctx) -> Verdict) -> Verdict {
        let input = json!({"things": [subject]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: params.as_ref(),
            aliases: BTreeMap::new(),
        };
        run(&ctx)
    }

    fn is_in(subject: Value, values: Right, not: bool) -> Cause {
        let check = In {
            path: x(),
            values,
            not,
        };
        on(subject, None, |ctx| run_in(&check, ctx)).cause
    }

    fn written(values: Value) -> Right {
        Right::Written(values)
    }

    #[test]
    fn in_passes_on_one_of_the_values_by_value() {
        let values = written(json!([1, 2]));
        assert_eq!(
            is_in(
                serde_json::from_str(r#"{"x": 1.0}"#).unwrap(),
                values.clone(),
                false
            ),
            Cause::Satisfied
        );
        assert_eq!(is_in(json!({"x": 3}), values.clone(), false), Cause::Value);
        assert_eq!(is_in(json!({"x": "1"}), values, false), Cause::Unusable);
    }

    #[test]
    fn not_in_passes_on_none_of_the_values_and_on_an_empty_list() {
        let values = written(json!(["prod", "staging"]));
        assert_eq!(
            is_in(json!({"x": "dev"}), values.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            is_in(json!({"x": "prod"}), values.clone(), true),
            Cause::Value
        );
        assert_eq!(is_in(json!({"x": 5}), values, true), Cause::Unusable);
        assert_eq!(
            is_in(json!({"x": 5}), written(json!([])), true),
            Cause::Satisfied
        );
        assert_eq!(
            is_in(json!({"x": 5}), written(json!([])), false),
            Cause::Value
        );
    }

    #[test]
    fn a_missing_or_null_field_fails_in_even_when_the_values_hold_null() {
        let values = written(json!(["a", null]));
        assert_eq!(is_in(json!({}), values.clone(), false), Cause::Absent);
        assert_eq!(
            is_in(json!({"x": null}), values.clone(), false),
            Cause::Null
        );
        assert_eq!(is_in(json!({"x": "a"}), values, false), Cause::Satisfied);
    }

    #[test]
    fn values_read_from_a_field_that_are_not_one_list_of_one_type_fail_as_unusable_first() {
        let field = Right::Field(key_path(Start::Subject, &["ys"]));
        assert_eq!(
            is_in(json!({"ys": "a"}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"x": "a", "ys": ["a", 1]}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"ys": ["a", 1]}), field.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            is_in(json!({"x": "a"}), field.clone(), false),
            Cause::Absent
        );
        assert_eq!(
            is_in(json!({"x": "a", "ys": ["b", "a"]}), field, false),
            Cause::Satisfied
        );
    }

    #[test]
    fn a_field_on_the_right_is_an_input_and_a_ref_is_not() {
        let field = In {
            path: x(),
            values: Right::Field(key_path(Start::Subject, &["ys"])),
            not: false,
        };
        let names = |v: Verdict| v.inputs.into_iter().map(|i| i.name).collect::<Vec<_>>();
        assert_eq!(
            names(on(json!({"x": "a", "ys": ["a"]}), None, |ctx| run_in(
                &field, ctx
            ))),
            ["x", "ys"]
        );
        let reference = In {
            path: x(),
            values: Right::Ref(key_path(Start::Params, &["k"])),
            not: false,
        };
        let v = on(json!({"x": "a"}), Some(json!({"k": ["a"]})), |ctx| {
            run_in(&reference, ctx)
        });
        assert_eq!(v.cause, Cause::Satisfied);
        assert_eq!(names(v), ["x"]);
    }

    #[test]
    fn a_ref_that_is_missing_or_null_fails_with_its_outcome_whatever_the_field_holds() {
        let check = In {
            path: x(),
            values: Right::Ref(key_path(Start::Params, &["k"])),
            not: false,
        };
        assert_eq!(
            on(json!({}), Some(json!({})), |ctx| run_in(&check, ctx)).cause,
            Cause::Absent
        );
        assert_eq!(
            on(json!({"x": 1}), Some(json!({"k": null})), |ctx| run_in(
                &check, ctx
            ))
            .cause,
            Cause::Null
        );
    }

    fn contains(subject: Value, wanted: Wanted, not: bool) -> Cause {
        let check = Contains {
            path: x(),
            wanted,
            not,
        };
        on(subject, None, |ctx| run_contains(&check, ctx)).cause
    }

    #[test]
    fn includes_and_excludes_need_a_list() {
        let one = Wanted::One(written(json!("a")));
        assert_eq!(
            contains(json!({"x": ["b", "a"]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["b"]}), one.clone(), false),
            Cause::Value
        );
        assert_eq!(contains(json!({"x": []}), one.clone(), false), Cause::Value);
        assert_eq!(
            contains(json!({"x": []}), one.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": "abc"}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": {"a": "a"}}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(contains(json!({}), one.clone(), true), Cause::Absent);
        assert_eq!(contains(json!({"x": null}), one, false), Cause::Null);
    }

    #[test]
    fn items_and_values_of_more_than_one_type_fail_as_unusable_leaving_null_aside() {
        let one = Wanted::One(written(json!(1)));
        assert_eq!(
            contains(json!({"x": ["1", 1]}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": ["1"]}), one.clone(), false),
            Cause::Unusable
        );
        assert_eq!(
            contains(json!({"x": [1, null]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(contains(json!({"x": [2]}), one, true), Cause::Satisfied);
    }

    #[test]
    fn contains_all_of_and_none_of_take_every_value() {
        let all = Wanted::All(written(json!(["b", "a"])));
        assert_eq!(
            contains(json!({"x": ["a", "c", "b"]}), all.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["a"]}), all.clone(), false),
            Cause::Value
        );
        assert_eq!(
            contains(json!({"x": ["c"]}), all.clone(), true),
            Cause::Satisfied
        );
        assert_eq!(contains(json!({"x": ["c", "a"]}), all, true), Cause::Value);
    }

    #[test]
    fn values_read_as_an_empty_list_a_non_list_or_mixed_types_fail_as_unusable() {
        let field = || Wanted::All(Right::Field(key_path(Start::Subject, &["ys"])));
        for ys in [json!([]), json!("a"), json!(["a", 1])] {
            assert_eq!(
                contains(json!({"x": ["a"], "ys": ys.clone()}), field(), true),
                Cause::Unusable,
                "{ys}"
            );
            assert_eq!(
                contains(json!({"ys": ys.clone()}), field(), false),
                Cause::Unusable,
                "{ys}"
            );
        }
    }

    #[test]
    fn one_value_that_is_a_list_is_looked_for_as_a_list() {
        let one = Wanted::One(Right::Field(key_path(Start::Subject, &["y"])));
        assert_eq!(
            contains(json!({"x": [["a"]], "y": ["a"]}), one.clone(), false),
            Cause::Satisfied
        );
        assert_eq!(
            contains(json!({"x": ["a"], "y": ["a"]}), one, false),
            Cause::Unusable
        );
    }

    fn matches(text: Value, patterns: Value, not: bool) -> Cause {
        let check = Matches {
            path: x(),
            patterns: written(patterns),
            not,
        };
        on(json!({"x": text}), None, |ctx| run_matches(&check, ctx)).cause
    }

    #[test]
    fn a_pattern_matches_anywhere_unless_anchored() {
        assert_eq!(
            matches(json!("my_svc_x"), json!(["z", "^b", "svc_"]), false),
            Cause::Satisfied
        );
        assert_eq!(matches(json!("a"), json!(["z", "^b"]), false), Cause::Value);
        assert_eq!(matches(json!("bob"), json!(["^b"]), true), Cause::Value);
        assert_eq!(matches(json!("a"), json!(["^b"]), true), Cause::Satisfied);
        assert_eq!(matches(json!("a"), json!([]), false), Cause::Value);
        assert_eq!(matches(json!("a"), json!([]), true), Cause::Satisfied);
    }

    #[test]
    fn matching_works_as_re2_does() {
        assert_eq!(
            matches(json!("a\nb"), json!(["^a.b$"]), false),
            Cause::Value
        );
        assert_eq!(matches(json!("a\n"), json!(["a$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("abc"), json!(["(?i)^A"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("été"), json!([r"^\p{L}+$"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("\u{212a}"), json!(["(?i)^k$"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("a+b"), json!([r"\Qa+b\E"]), false),
            Cause::Satisfied
        );
    }

    #[test]
    fn digit_word_space_and_boundary_classes_are_ascii_as_in_re2() {
        assert_eq!(matches(json!("٣"), json!([r"^\d$"]), false), Cause::Value);
        assert_eq!(matches(json!("٣"), json!([r"^[\d]$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("٣"), json!([r"^\D$"]), false),
            Cause::Satisfied
        );
        assert_eq!(matches(json!("é"), json!([r"^\w$"]), false), Cause::Value);
        assert_eq!(
            matches(json!("\u{b}"), json!([r"^\s$"]), false),
            Cause::Value
        );
        assert_eq!(
            matches(json!("\u{a0}"), json!([r"^\s$"]), false),
            Cause::Value
        );
        assert_eq!(
            matches(json!("aé"), json!([r"a\b"]), false),
            Cause::Satisfied
        );
        assert_eq!(
            matches(json!("é"), json!(["^[[:alpha:]]$"]), false),
            Cause::Value
        );
    }

    #[test]
    fn a_pattern_that_cannot_be_used_fails_as_unusable() {
        assert_eq!(matches(json!("a"), json!(["("]), false), Cause::Unusable);
        assert_eq!(matches(json!("a"), json!([1]), false), Cause::Unusable);
        assert_eq!(matches(json!("a"), json!("a"), false), Cause::Unusable);
        assert_eq!(
            matches(json!("a"), json!(["a", r"a\Z"]), true),
            Cause::Unusable
        );
    }

    #[test]
    fn matching_anything_but_a_string_fails_as_unusable() {
        assert_eq!(matches(json!(1), json!(["1"]), false), Cause::Unusable);
        assert_eq!(matches(json!(["a"]), json!(["a"]), true), Cause::Unusable);
    }

    #[test]
    fn a_whole_ref_is_listed_in_refs_and_a_params_path_with_a_field_step_only_by_its_ref_steps() {
        let k = key_path(Start::Params, &["k"]);
        assert_eq!(Right::Ref(k.clone()).refs(), vec![k.clone()]);
        let named = Path {
            start: Start::Params,
            steps: vec![Step::Key("lists".into()), Step::Ref(Box::new(k.clone()))],
        };
        assert_eq!(Right::Ref(named).refs(), vec![k.clone()]);
        let by_field = Path {
            start: Start::Params,
            steps: vec![
                Step::Key("lists".into()),
                Step::Field(Box::new(key_path(Start::Subject, &["y"]))),
            ],
        };
        assert!(Right::Ref(by_field).refs().is_empty());
        assert!(
            Right::Field(key_path(Start::Subject, &["ys"]))
                .refs()
                .is_empty()
        );
        assert!(written(json!(["a"])).refs().is_empty());
    }

    fn lowered(sentence: &str) -> Option<Result<Check, Vec<String>>> {
        let check = tree::parse_check(sentence).unwrap();
        match &check.assertions[0] {
            tree::Assertion::Plain { path, phrase } => {
                lower_phrase(path, phrase, &Scope::new().on_subject())
            }
            other => panic!("{sentence} isn't a plain assertion: {other:?}"),
        }
    }

    fn lowered_check(sentence: &str) -> Check {
        lowered(sentence).unwrap().unwrap()
    }

    #[test]
    fn one_of_reads_into_in_with_written_values_a_ref_or_a_field() {
        match lowered_check("x is not one of \"a\", \"b\"") {
            Check::In(c) => {
                assert!(c.not);
                assert_eq!(c.values, written(json!(["a", "b"])));
            }
            other => panic!("{other:?}"),
        }
        assert!(matches!(
            lowered_check("x is in $params.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in $input.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in ys"),
            Check::In(In {
                values: Right::Field(_),
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is in $params.lists named by $params.k"),
            Check::In(In {
                values: Right::Ref(_),
                ..
            })
        ));
    }

    #[test]
    fn each_contains_phrase_reads_into_contains() {
        for (sentence, all, not) in [
            ("x contains \"a\"", false, false),
            ("x does not contain $params.v", false, true),
            ("x contains all of \"a\", \"b\"", true, false),
            ("x contains none of ys", true, true),
        ] {
            match lowered_check(sentence) {
                Check::Contains(c) => {
                    assert_eq!(matches!(c.wanted, Wanted::All(_)), all, "{sentence}");
                    assert_eq!(c.not, not, "{sentence}");
                }
                other => panic!("{sentence}: {other:?}"),
            }
        }
    }

    #[test]
    fn matches_type_non_empty_string_and_empty_read_into_their_checks() {
        assert!(matches!(
            lowered_check("x does not match \"^a\""),
            Check::Matches(Matches { not: true, .. })
        ));
        assert!(matches!(
            lowered_check("x is an object"),
            Check::HasType(HasType {
                kind: Kind::Object,
                ..
            })
        ));
        assert!(matches!(
            lowered_check("x is a non-empty string"),
            Check::NonEmptyString(_)
        ));
        assert!(matches!(
            lowered_check("x is not empty"),
            Check::Empty(Empty { not: true, .. })
        ));
    }

    #[test]
    fn a_phrase_compare_reads_or_a_count_on_the_right_is_not_read_here() {
        for sentence in [
            "x is 1",
            "x is at least 2",
            "x exists",
            "x contains count of ys",
        ] {
            assert!(lowered(sentence).is_none(), "{sentence}");
        }
    }

    #[test]
    fn written_values_of_mixed_types_are_written_wrong_leaving_null_aside() {
        for sentence in [
            "x is one of \"a\", 1",
            "x is not one of true, 1e2",
            "x contains all of true, 1",
            "x contains none of \"a\", false",
        ] {
            assert_eq!(
                lowered(sentence).unwrap().unwrap_err(),
                ["values of mixed types"],
                "{sentence}"
            );
        }
        assert!(lowered("x is one of \"a\", null").unwrap().is_ok());
        assert!(lowered("x contains all of 1, 2").unwrap().is_ok());
    }

    fn flawed_with(check: &Check, params: Value) -> bool {
        let input = json!({"things": [{"x": "a"}]});
        let ctx = Ctx {
            subject: Located {
                value: &input["things"][0],
                location: Location::input_root().key("things").index(0),
            },
            input: &input,
            params: Some(&params),
            aliases: BTreeMap::new(),
        };
        check.flawed(&ctx)
    }

    #[test]
    fn a_ref_that_reads_the_wrong_kind_of_value_is_a_flaw_and_a_missing_one_is_not() {
        let in_list = lowered_check("x is in $params.l");
        assert!(flawed_with(&in_list, json!({"l": "a"})));
        assert!(flawed_with(&in_list, json!({"l": ["a", 1]})));
        assert!(!flawed_with(&in_list, json!({"l": []})));
        assert!(!flawed_with(&in_list, json!({"l": ["a"]})));
        assert!(!flawed_with(&in_list, json!({})));
        assert!(!flawed_with(&in_list, json!({"l": null})));
        let all = lowered_check("x contains all of $params.l");
        assert!(flawed_with(&all, json!({"l": []})));
        assert!(flawed_with(&all, json!({"l": "a"})));
        assert!(!flawed_with(&all, json!({"l": ["a"]})));
        let one = lowered_check("x contains $params.v");
        assert!(!flawed_with(&one, json!({"v": [1, "a"]})));
        let patterns = lowered_check("x matches $params.p");
        assert!(flawed_with(&patterns, json!({"p": ["("]})));
        assert!(flawed_with(&patterns, json!({"p": "a"})));
        assert!(!flawed_with(&patterns, json!({"p": ["^a"]})));
    }

    #[test]
    fn a_written_list_or_a_field_on_the_right_is_never_a_flaw() {
        assert!(!flawed_with(
            &lowered_check("x is one of \"a\", \"b\""),
            json!({})
        ));
        assert!(!flawed_with(&lowered_check("x is in ys"), json!({})));
    }
}
