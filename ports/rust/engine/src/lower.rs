use crate::ops::walk::{Quantifier, Walk};
use crate::ops::{Check, present::Present, tally};
use crate::path::{self, OUTER, PartStart, Start, Step};
use crate::value::Decimal;
use ergo_sentences as s;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub const UNSUPPORTED_SUFFIX: &str = " isn't supported by this engine yet";
pub const MAX_POSITION: u64 = 9_007_199_254_740_991;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PartDef {
    pub steps: Vec<Step>,
    pub id: Option<Vec<Step>>,
}

#[derive(Debug, Clone, Default)]
pub struct Scope {
    left_reads_parents: bool,
    as_left: bool,
    item: bool,
    parts: BTreeMap<String, PartDef>,
    parents: BTreeMap<String, BTreeMap<String, PartDef>>,
    for_aliases: BTreeSet<String>,
}

fn not_a_position(number: &str) -> Vec<String> {
    vec![format!("{number} can't be a list position")]
}

fn position_of(number: &str) -> Result<u64, Vec<String>> {
    match number.parse::<u64>() {
        Ok(at) if (1..=MAX_POSITION).contains(&at) => Ok(at - 1),
        _ => Err(not_a_position(number)),
    }
}

fn index_of(number: &str) -> Result<u64, Vec<String>> {
    match number.parse::<u64>() {
        Ok(at) if at <= MAX_POSITION => Ok(at),
        _ => Err(not_a_position(number)),
    }
}

fn last_unsupported() -> Vec<String> {
    vec![
        "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""
            .to_string(),
    ]
}

pub const UNKNOWN_NAME: &str = "unknown name ";

fn reference_path(reference: &s::Reference) -> Option<path::Path> {
    match reference {
        s::Reference::Params(key) => Some(path::Path {
            start: Start::Params,
            steps: vec![Step::Key(key.clone())],
        }),
        s::Reference::Input(key) => Some(path::Path {
            start: Start::Input,
            steps: vec![Step::Key(key.clone())],
        }),
        s::Reference::Name(_) | s::Reference::Unknown { .. } => None,
    }
}

fn position_step(position: &Option<s::Position>) -> Result<Option<Step>, Vec<String>> {
    match position {
        None => Ok(None),
        Some(s::Position::First) => Ok(Some(Step::Index(0))),
        Some(s::Position::Item {
            number,
            from_last: false,
        }) => position_of(number).map(|at| Some(Step::Index(at))),
        Some(_) => Err(last_unsupported()),
    }
}

pub fn keyed_steps(path: &s::Path) -> Result<Vec<Step>, Vec<String>> {
    let mut steps = Vec::new();
    let mut problems = Vec::new();
    for step in &path.steps {
        match step {
            s::Step::Key(key) | s::Step::BracketKey(key) => steps.push(Step::Key(key.clone())),
            s::Step::Index(number) => match index_of(number) {
                Ok(at) => steps.push(Step::Index(at)),
                Err(found) => problems.extend(found),
            },
            s::Step::NamedBy(reference) | s::Step::Brackets(reference) => {
                match reference_path(reference) {
                    Some(reference) => steps.push(Step::Ref(Box::new(reference))),
                    None => match reference {
                        s::Reference::Name(name) => {
                            problems.push(format!("unknown alias {name}"));
                        }
                        s::Reference::Unknown { name, .. } => {
                            problems.push(format!("{UNKNOWN_NAME}{name}"));
                        }
                        s::Reference::Params(_) | s::Reference::Input(_) => {}
                    },
                }
            }
        }
    }
    match position_step(&path.position) {
        Ok(Some(step)) => steps.push(step),
        Ok(None) => {}
        Err(found) => problems.extend(found),
    }
    if problems.is_empty() {
        Ok(steps)
    } else {
        Err(problems)
    }
}

pub fn part_steps(path: &s::Path) -> Result<Vec<Step>, Vec<String>> {
    let first = match &path.start {
        s::Start::Field { key, .. } => Step::Key(key.clone()),
        s::Start::Params | s::Start::Input => {
            return Err(vec![
                "a part reads inside its subject, so it can't start at $params or $input"
                    .to_string(),
            ]);
        }
        s::Start::It => {
            return Err(vec![
                "it can only start an assertion: write it first, like it is not empty".to_string(),
            ]);
        }
        s::Start::Unknown(name) => return Err(vec![format!("{UNKNOWN_NAME}{name}")]),
    };
    let mut steps = vec![first];
    steps.extend(keyed_steps(path)?);
    Ok(steps)
}

impl Scope {
    pub fn new() -> Scope {
        Scope::default()
    }

    pub fn with_part(mut self, alias: &str, part: PartDef) -> Scope {
        self.parts.insert(alias.to_string(), part);
        self
    }

    pub fn with_parent(mut self, name: &str, parts: BTreeMap<String, PartDef>) -> Scope {
        self.parents.insert(name.to_string(), parts);
        self
    }

    pub fn with_for_alias(mut self, alias: &str) -> Scope {
        self.for_aliases.insert(alias.to_string());
        self
    }

    #[cfg(test)]
    pub fn parts(&self) -> &BTreeMap<String, PartDef> {
        &self.parts
    }

    pub fn parent_names(&self) -> Vec<String> {
        self.parents.keys().cloned().collect()
    }

    pub fn aliases(&self) -> Vec<String> {
        let mut names: BTreeSet<String> = self.parts.keys().cloned().collect();
        names.extend(self.parents.keys().cloned());
        names.extend(self.for_aliases.iter().cloned());
        names.into_iter().collect()
    }

    fn step(&self, step: &s::Step) -> Result<Step, Vec<String>> {
        match step {
            s::Step::Key(key) | s::Step::BracketKey(key) => Ok(Step::Key(key.clone())),
            s::Step::Index(number) => index_of(number).map(Step::Index),
            s::Step::NamedBy(reference) | s::Step::Brackets(reference) => match reference {
                s::Reference::Name(name) => {
                    if self.parts.contains_key(name) {
                        return Err(vec![format!(
                            "named by {name} reads a part, which isn't supported yet"
                        )]);
                    }
                    if self.for_aliases.contains(name) || self.parents.contains_key(name) {
                        return Ok(Step::Ref(Box::new(path::Path {
                            start: Start::Alias(name.clone()),
                            steps: Vec::new(),
                        })));
                    }
                    Ok(Step::Field(Box::new(path::Path {
                        start: Start::Subject,
                        steps: vec![Step::Key(name.clone())],
                    })))
                }
                other => reference_path(other)
                    .map(|reference| Step::Ref(Box::new(reference)))
                    .ok_or_else(Vec::new),
            },
        }
    }

    pub fn path(&self, path: &s::Path) -> Result<path::Path, Vec<String>> {
        self.read_path(path, true, true)
    }

    pub fn counted_path(&self, path: &s::Path) -> Result<path::Path, Vec<String>> {
        if self.item {
            self.read_path(path, false, false)
        } else if self.as_left {
            self.left_path(path)
        } else {
            self.path(path)
        }
    }

    pub fn term_path(&self, path: &s::Path) -> Result<path::Path, Vec<String>> {
        if self.as_left {
            self.left_path(path)
        } else {
            self.path(path)
        }
    }

    pub fn prints_left(&self) -> bool {
        self.as_left && !self.left_reads_parents && !self.item
    }

    pub fn as_left(&self) -> Scope {
        Scope {
            as_left: true,
            ..self.clone()
        }
    }

    pub fn left_path(&self, path: &s::Path) -> Result<path::Path, Vec<String>> {
        if self.item {
            self.read_path(path, false, false)
        } else {
            self.read_path(path, self.left_reads_parents, true)
        }
    }

    pub fn in_item(&self) -> Scope {
        Scope {
            item: true,
            ..self.clone()
        }
    }

    fn base(&self) -> Start {
        if self.item {
            Start::Alias(OUTER.to_string())
        } else {
            Start::Subject
        }
    }

    pub fn on_subject(&self) -> Scope {
        Scope {
            left_reads_parents: true,
            ..self.clone()
        }
    }

    fn read_path(
        &self,
        written: &s::Path,
        parents: bool,
        parts: bool,
    ) -> Result<path::Path, Vec<String>> {
        let mut problems = Vec::new();
        let mut steps = Vec::new();
        for step in &written.steps {
            match self.step(step) {
                Ok(step) => steps.push(step),
                Err(found) => problems.extend(found),
            }
        }
        match position_step(&written.position) {
            Ok(Some(step)) => steps.push(step),
            Ok(None) => {}
            Err(found) => problems.extend(found),
        }
        if !problems.is_empty() {
            return Err(problems);
        }
        let (start, steps) = match &written.start {
            s::Start::It => (Start::Subject, steps),
            s::Start::Params => (Start::Params, steps),
            s::Start::Input => (Start::Input, steps),
            s::Start::Unknown(name) => return Err(vec![format!("{UNKNOWN_NAME}{name}")]),
            s::Start::Field { key, dot } => self.field_start(key, *dot, parents, parts, steps),
        };
        Ok(path::Path { start, steps })
    }

    fn field_start(
        &self,
        key: &str,
        dot: bool,
        parents: bool,
        parts: bool,
        mut steps: Vec<Step>,
    ) -> (Start, Vec<Step>) {
        if !dot {
            if parts && let Some(part) = self.parts.get(key) {
                return (part_start(key, self.base(), part), steps);
            }
            if parents {
                if let Some(found) = self.parents.get(key) {
                    if let Some(Step::Key(next)) = steps.first()
                        && let Some(part) = found.get(next)
                    {
                        let name = format!("{key}.{next}");
                        let start = part_start(&name, Start::Alias(key.to_string()), part);
                        steps.remove(0);
                        return (start, steps);
                    }
                    return (Start::Alias(key.to_string()), steps);
                }
                if self.for_aliases.contains(key) {
                    return (Start::Alias(key.to_string()), steps);
                }
            }
        }
        steps.insert(0, Step::Key(key.to_string()));
        (Start::Subject, steps)
    }

    pub fn value(&self, value: &s::Value) -> Result<Value, Vec<String>> {
        match value {
            s::Value::String(text) => Ok(Value::String(text.clone())),
            s::Value::True => Ok(Value::Bool(true)),
            s::Value::False => Ok(Value::Bool(false)),
            s::Value::Null => Ok(Value::Null),
            s::Value::Number(text) => number(text),
        }
    }
}

fn part_start(name: &str, base: Start, part: &PartDef) -> Start {
    Start::Part(Box::new(PartStart {
        name: name.to_string(),
        base,
        steps: part.steps.clone(),
        id: part.id.clone(),
    }))
}

fn number(text: &str) -> Result<Value, Vec<String>> {
    let out_of_range = || vec![format!("number out of range: {text}")];
    let decimal = Decimal::parse(text).ok_or_else(out_of_range)?;
    let float: f64 = text.parse().map_err(|_| out_of_range())?;
    if !float.is_finite() {
        return Err(out_of_range());
    }
    if decimal.is_zero() {
        if float != 0.0 {
            return Err(out_of_range());
        }
    } else if float.abs() < f64::MIN_POSITIVE {
        return Err(out_of_range());
    }
    serde_json::from_str::<Value>(text).map_err(|_| out_of_range())
}

const AFTER_QUANTIFIER: &str = "count of, sum of and plus after every or some aren't supported yet";

fn phrase_terms(phrase: &s::Phrase) -> &[s::Term] {
    match phrase {
        s::Phrase::Is { operand, .. }
        | s::Phrase::Order { operand, .. }
        | s::Phrase::Contains { operand, .. }
        | s::Phrase::StartsWith(operand)
        | s::Phrase::EndsWith(operand)
        | s::Phrase::Alphabetically { operand, .. }
        | s::Phrase::Time { operand, .. } => match operand {
            s::Operand::Field(terms) => terms,
            s::Operand::Value(_) => &[],
        },
        _ => &[],
    }
}

fn one_path(terms: &[s::Term]) -> bool {
    matches!(terms, [s::Term::Path(_)])
}

fn phrase_words(phrase: &s::Phrase) -> &'static str {
    match phrase {
        s::Phrase::Contains { not: false, .. } => "contains",
        s::Phrase::Contains { not: true, .. } => "does not contain",
        s::Phrase::StartsWith(_) => "starts with",
        s::Phrase::EndsWith(_) => "ends with",
        s::Phrase::Alphabetically { after: false, .. } => "is alphabetically before",
        s::Phrase::Alphabetically { after: true, .. } => "is alphabetically after",
        s::Phrase::Time { time, .. } => match time {
            s::TimeOrder::Before => "is before",
            s::TimeOrder::After => "is after",
            s::TimeOrder::OnOrAfter => "is on or after",
            s::TimeOrder::OnOrBefore => "is on or before",
        },
        s::Phrase::Is { not: false, .. } => "equals",
        s::Phrase::Is { not: true, .. } => "does not equal",
        s::Phrase::Order { order, .. } => match order {
            s::Order::AtLeast => "is at least",
            s::Order::AtMost => "is at most",
            s::Order::MoreThan => "is more than",
            s::Order::LessThan => "is less than",
        },
        _ => "",
    }
}

fn argument_problems(phrase: &s::Phrase) -> Vec<String> {
    let terms = phrase_terms(phrase);
    if terms.is_empty()
        || one_path(terms)
        || matches!(phrase, s::Phrase::Is { .. } | s::Phrase::Order { .. })
    {
        return Vec::new();
    }
    vec![format!(
        "\"{}\" can't take a count of, a sum of or a plus",
        phrase_words(phrase)
    )]
}

fn after_quantifier_problems(phrase: &s::Phrase) -> Vec<String> {
    let terms = phrase_terms(phrase);
    if terms.is_empty() || one_path(terms) {
        return Vec::new();
    }
    vec![AFTER_QUANTIFIER.to_string()]
}

pub const ELAPSED_AFTER_QUANTIFIER: &str =
    "an elapsed time isn't supported yet after every or some, or in a from line";
const IN_COUNT_WHOSE: &str =
    "a sum of or a plus in the whose of a count of or a sum of isn't supported yet";

fn has_elapsed(terms: &[s::Term]) -> bool {
    terms.iter().any(|term| match term {
        s::Term::Elapsed(_) => true,
        s::Term::Derived(derived) => derived.whose.iter().any(|condition| {
            matches!(condition.left, s::Left::Elapsed(_))
                || has_elapsed(phrase_terms(&condition.phrase))
        }),
        _ => false,
    })
}

pub fn in_from_line(found: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for problem in found {
        let argument = problem.ends_with(" can't take a count of, a sum of or a plus");
        if problem == ELAPSED_AFTER_QUANTIFIER {
            out.push(problem.clone());
        }
        if argument || problem == AFTER_QUANTIFIER || problem == ELAPSED_AFTER_QUANTIFIER {
            out.push(format!("whose: {problem}"));
        } else {
            out.push(problem);
        }
    }
    out
}

pub fn condition_elapsed_problems(condition: &s::Condition) -> Vec<String> {
    if matches!(condition.left, s::Left::Elapsed(_)) {
        return vec![ELAPSED_AFTER_QUANTIFIER.to_string()];
    }
    elapsed_after_quantifier_problems(&condition.phrase)
}

fn elapsed_after_quantifier_problems(phrase: &s::Phrase) -> Vec<String> {
    if has_elapsed(phrase_terms(phrase)) {
        vec![ELAPSED_AFTER_QUANTIFIER.to_string()]
    } else {
        Vec::new()
    }
}

fn counted_or_elapsed(terms: &[s::Term]) -> bool {
    matches!(
        terms,
        [s::Term::Path(_)
            | s::Term::Elapsed(_)
            | s::Term::Derived(s::Derived {
                kind: s::DerivedKind::Count,
                ..
            })]
    )
}

pub fn tally_condition_problems(condition: &s::Condition) -> Vec<String> {
    let left_flawed = matches!(
        condition.left,
        s::Left::Derived(s::Derived {
            kind: s::DerivedKind::Sum,
            ..
        })
    );
    let terms = phrase_terms(&condition.phrase);
    let right_flawed = !terms.is_empty() && !counted_or_elapsed(terms);
    let mut problems = argument_problems(&condition.phrase);
    if left_flawed || right_flawed {
        problems.push(IN_COUNT_WHOSE.to_string());
    }
    problems
}

pub fn lower_tally_condition(
    condition: &s::Condition,
    scope: &Scope,
) -> Result<Check, Vec<String>> {
    with_problems(
        lower_condition(condition, scope),
        tally_condition_problems(condition)
            .into_iter()
            .filter(|problem| problem == IN_COUNT_WHOSE)
            .collect(),
    )
}

fn with_problems(
    lowered: Result<Check, Vec<String>>,
    extra: Vec<String>,
) -> Result<Check, Vec<String>> {
    if extra.is_empty() {
        return lowered;
    }
    Err(lowered
        .err()
        .into_iter()
        .flatten()
        .filter(|problem| !problem.ends_with(UNSUPPORTED_SUFFIX))
        .chain(extra)
        .collect())
}

pub fn lower_condition(condition: &s::Condition, scope: &Scope) -> Result<Check, Vec<String>> {
    with_problems(
        lower_condition_phrase(condition, scope),
        argument_problems(&condition.phrase),
    )
}

fn lower_condition_phrase(condition: &s::Condition, scope: &Scope) -> Result<Check, Vec<String>> {
    let aliases = scope.aliases();
    let names: Vec<&str> = aliases.iter().map(String::as_str).collect();
    if let Some(lowered) = tally::lower_condition(&condition.left, &condition.phrase, scope) {
        return match lowered {
            Ok(Some(check)) => Ok(check),
            Ok(None) => Err(unsupported(condition, &names)),
            Err(found) => Err(found),
        };
    }
    let s::Left::Path(left) = &condition.left else {
        return Err(unsupported(condition, &names));
    };
    if let s::Phrase::Exists { not } = &condition.phrase {
        return Ok(Check::Present(Present {
            path: scope.left_path(left)?,
            missing: *not,
        }));
    }
    match lower_with_operator_modules(left, &condition.phrase, scope) {
        Some(lowered) => lowered,
        None => Err(unsupported(condition, &names)),
    }
}

pub fn lower_assertion(assertion: &s::Assertion, scope: &Scope) -> Result<Check, Vec<String>> {
    let extra = match assertion {
        s::Assertion::Plain { phrase, .. } | s::Assertion::Derived { phrase, .. } => {
            argument_problems(phrase)
        }
        s::Assertion::Quantified { .. } => Vec::new(),
    };
    with_problems(lower_assertion_phrase(assertion, scope), extra)
}

fn lower_assertion_phrase(assertion: &s::Assertion, scope: &Scope) -> Result<Check, Vec<String>> {
    let scope = scope.on_subject();
    match assertion {
        s::Assertion::Plain { path, phrase } => match phrase {
            s::Phrase::Exists { not } => Ok(Check::Present(Present {
                path: scope.left_path(path)?,
                missing: *not,
            })),
            other => match tally::lower_assertion(assertion, &scope)
                .or_else(|| lower_with_operator_modules(path, other, &scope))
            {
                Some(lowered) => lowered,
                None => Err(unsupported_assertion(assertion, &scope)),
            },
        },
        s::Assertion::Quantified {
            quantifier,
            path,
            whose,
            if_any,
            phrase,
        } => lower_quantified(*quantifier, path, whose, *if_any, phrase, &scope),
        s::Assertion::Derived { .. } => tally::lower_assertion(assertion, &scope)
            .unwrap_or_else(|| Err(unsupported_assertion(assertion, &scope))),
    }
}

fn unsupported_assertion(assertion: &s::Assertion, scope: &Scope) -> Vec<String> {
    let aliases = scope.aliases();
    let names: Vec<&str> = aliases.iter().map(String::as_str).collect();
    vec![format!(
        "{}{UNSUPPORTED_SUFFIX}",
        s::print_assertion(assertion, &names)
    )]
}

pub fn lower_for(
    line: &s::ForLine,
    assertions: &[s::Assertion],
    places: &[String],
    scope: &Scope,
) -> Result<Check, Vec<String>> {
    crate::ops::for_line::lower_for(line, assertions, places, scope)
}

pub const MOST_WALK_STEPS: usize = 10;

pub fn walk_steps(path: &path::Path) -> usize {
    let start = match &path.start {
        Start::Subject | Start::Input | Start::Params => 0,
        Start::Alias(_) => 1,
        Start::Part(part) => part.steps.len(),
    };
    start + path.steps.len()
}

pub fn walk_too_long(path: &path::Path) -> Option<String> {
    (walk_steps(path) > MOST_WALK_STEPS)
        .then(|| "every and some over more than ten steps aren't supported yet".to_string())
}

pub fn lower_quantified(
    quantifier: s::Quantifier,
    path: &s::Path,
    whose: &[s::Condition],
    if_any: bool,
    phrase: &s::Phrase,
    scope: &Scope,
) -> Result<Check, Vec<String>> {
    let mut problems = argument_problems(phrase);
    problems.extend(after_quantifier_problems(phrase));
    problems.extend(elapsed_after_quantifier_problems(phrase));
    let walk_path = match scope.left_path(path) {
        Ok(found) => {
            problems.extend(walk_too_long(&found));
            Some(found)
        }
        Err(found) => {
            problems.extend(found);
            None
        }
    };
    let item = scope.in_item();
    let mut conditions = Vec::new();
    for condition in whose {
        match lower_condition(condition, &item) {
            Ok(check) => conditions.push(check),
            Err(found) => problems.extend(found),
        }
    }
    let on_item = s::Path {
        position: None,
        start: s::Start::It,
        steps: Vec::new(),
    };
    let check = match phrase {
        s::Phrase::Exists { not } => match item.left_path(&on_item) {
            Ok(path) => Some(Check::Present(Present {
                path,
                missing: *not,
            })),
            Err(found) => {
                problems.extend(found);
                None
            }
        },
        other => match lower_with_operator_modules(&on_item, other, &item) {
            Some(Ok(check)) => Some(check),
            Some(Err(found)) => {
                problems.extend(found);
                None
            }
            None => None,
        },
    };
    if !problems.is_empty() {
        return Err(problems);
    }
    match (walk_path, check) {
        (Some(path), Some(check)) => Ok(Check::Walk(Box::new(Walk {
            quantifier: match quantifier {
                s::Quantifier::Every => Quantifier::Every,
                s::Quantifier::Some => Quantifier::Some,
            },
            path,
            whose: conditions,
            if_any,
            check: Box::new(check),
        }))),
        _ => Err(vec![format!("every or some{UNSUPPORTED_SUFFIX}")]),
    }
}

fn unsupported(condition: &s::Condition, names: &[&str]) -> Vec<String> {
    vec![format!(
        "{}{UNSUPPORTED_SUFFIX}",
        s::print_condition(condition, names)
    )]
}

pub fn lower_with_operator_modules(
    path: &s::Path,
    phrase: &s::Phrase,
    scope: &Scope,
) -> Option<Result<Check, Vec<String>>> {
    crate::ops::compare::lower_phrase(path, phrase, scope)
        .or_else(|| crate::ops::lists::lower_phrase(path, phrase, scope))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn path(text: &str) -> s::Path {
        s::parse_path(text).unwrap()
    }

    fn key(text: &str) -> Step {
        Step::Key(text.to_string())
    }

    fn it(position: Option<s::Position>) -> s::Path {
        s::Path {
            position,
            start: s::Start::It,
            steps: Vec::new(),
        }
    }

    fn lowered(scope: &Scope, text: &str) -> path::Path {
        scope.path(&path(text)).unwrap()
    }

    fn part(steps: &[&str], id: Option<&[&str]>) -> PartDef {
        PartDef {
            steps: steps.iter().map(|k| key(k)).collect(),
            id: id.map(|ids| ids.iter().map(|k| key(k)).collect()),
        }
    }

    fn scope() -> Scope {
        Scope::new()
            .with_part("cov", part(&["d", "b"], Some(&["id"])))
            .with_parent(
                "artifact",
                BTreeMap::from([("att".to_string(), part(&["a", "t"], None))]),
            )
            .with_for_alias("pr")
    }

    #[test]
    fn a_bare_first_key_is_a_field_of_the_subject() {
        let p = lowered(&Scope::new(), "a1.b");
        assert_eq!(p.start, Start::Subject);
        assert_eq!(p.steps, [key("a1"), key("b")]);
    }

    #[test]
    fn it_is_the_subject_and_params_and_input_start_there() {
        let p = Scope::new().path(&it(None)).unwrap();
        assert_eq!((p.start, p.steps), (Start::Subject, vec![]));
        let p = lowered(&Scope::new(), "$params.k.j");
        assert_eq!(
            (p.start, p.steps),
            (Start::Params, vec![key("k"), key("j")])
        );
        let p = lowered(&Scope::new(), "$input.k");
        assert_eq!((p.start, p.steps), (Start::Input, vec![key("k")]));
    }

    #[test]
    fn a_dot_always_reads_a_field_even_when_an_alias_has_the_name() {
        let p = lowered(&scope(), ".cov.x");
        assert_eq!(p.start, Start::Subject);
        assert_eq!(p.steps, [key("cov"), key("x")]);
        let p = lowered(&scope(), ".artifact.x");
        assert_eq!(p.start, Start::Subject);
        let p = lowered(&scope(), ".pr.x");
        assert_eq!(p.start, Start::Subject);
        let p = lowered(&Scope::new(), ".empty");
        assert_eq!(p.steps, [key("empty")]);
    }

    #[test]
    fn a_part_alias_starts_at_the_part_with_its_id() {
        let p = lowered(&scope(), "cov.x");
        let Start::Part(found) = p.start else {
            panic!("not a part");
        };
        assert_eq!(found.name, "cov");
        assert_eq!(found.base, Start::Subject);
        assert_eq!(found.steps, [key("d"), key("b")]);
        assert_eq!(found.id, Some(vec![key("id")]));
        assert_eq!(p.steps, [key("x")]);
    }

    #[test]
    fn a_parent_name_starts_at_the_parent_and_a_part_of_it_at_the_part() {
        let p = lowered(&scope(), "artifact.owner");
        assert_eq!(p.start, Start::Alias("artifact".into()));
        assert_eq!(p.steps, [key("owner")]);
        let p = lowered(&scope(), "artifact.att.n");
        let Start::Part(found) = p.start else {
            panic!("not a part");
        };
        assert_eq!(found.name, "artifact.att");
        assert_eq!(found.base, Start::Alias("artifact".into()));
        assert_eq!(p.steps, [key("n")]);
        let p = lowered(&scope(), "artifact");
        assert_eq!(
            (p.start, p.steps),
            (Start::Alias("artifact".into()), vec![])
        );
    }

    #[test]
    fn a_for_alias_starts_at_the_alias() {
        let p = lowered(&scope(), "pr.author");
        assert_eq!(p.start, Start::Alias("pr".into()));
    }

    #[test]
    fn the_left_of_a_condition_reads_parts_but_never_parents_or_for_aliases() {
        let left = |text: &str| scope().left_path(&path(text)).unwrap();
        assert!(matches!(left("cov.x").start, Start::Part(_)));
        let p = left("artifact.owner");
        assert_eq!(p.start, Start::Subject);
        assert_eq!(p.steps, [key("artifact"), key("owner")]);
        assert_eq!(left("pr.author").start, Start::Subject);
        assert!(matches!(left(".cov.x").start, Start::Subject));
    }

    #[test]
    fn steps_read_keys_brackets_indexes_and_refs() {
        let p = lowered(&Scope::new(), "a1.\"b c\"[\"k\"][2].d");
        assert_eq!(
            p.steps,
            [key("a1"), key("b c"), key("k"), Step::Index(2), key("d")]
        );
        let p = lowered(&Scope::new(), "m named by $params.k.v");
        assert_eq!(
            p.steps,
            [
                key("m"),
                Step::Ref(Box::new(path::Path {
                    start: Start::Params,
                    steps: vec![key("k")]
                })),
                key("v")
            ]
        );
        let p = lowered(&Scope::new(), "m[$input.k]");
        assert!(matches!(&p.steps[1], Step::Ref(r) if r.start == Start::Input));
    }

    #[test]
    fn a_bare_name_after_named_by_is_a_field_step_unless_an_alias_has_the_name() {
        let p = lowered(&Scope::new(), "m named by sev");
        assert!(matches!(&p.steps[1], Step::Field(f) if f.steps == [key("sev")]));
        let p = lowered(&scope(), "m named by pr");
        assert!(matches!(&p.steps[1], Step::Ref(r) if r.start == Start::Alias("pr".into())));
    }

    #[test]
    fn named_by_a_part_alias_is_written_wrong() {
        assert_eq!(
            scope().path(&path("m named by cov")).unwrap_err(),
            ["named by cov reads a part, which isn't supported yet"]
        );
    }

    #[test]
    fn positions_become_a_last_step_counting_from_zero() {
        assert_eq!(
            lowered(&Scope::new(), "first of xs").steps,
            [key("xs"), Step::Index(0)]
        );
        assert_eq!(
            lowered(&Scope::new(), "item 3 of xs.ys").steps,
            [key("xs"), key("ys"), Step::Index(2)]
        );
        let p = Scope::new().path(&it(Some(s::Position::First))).unwrap();
        assert_eq!(p.steps, [Step::Index(0)]);
    }

    #[test]
    fn a_last_position_and_one_counted_from_the_end_are_not_read_yet() {
        for text in ["last of xs", "item 2 from last of xs"] {
            let problems = Scope::new().path(&path(text)).unwrap_err();
            assert_eq!(
                problems,
                [
                    "last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""
                ]
            );
        }
    }

    #[test]
    fn a_position_past_the_largest_a_float_holds_is_written_wrong() {
        let mut written = path("xs");
        written
            .steps
            .push(s::Step::Index("9007199254740992".to_string()));
        assert_eq!(
            Scope::new().path(&written).unwrap_err(),
            ["9007199254740992 can't be a list position"]
        );
        let picked = s::Position::Item {
            number: "9007199254740992".to_string(),
            from_last: false,
        };
        assert_eq!(
            Scope::new().path(&it(Some(picked))).unwrap_err(),
            ["9007199254740992 can't be a list position"]
        );
        assert_eq!(
            lowered(&Scope::new(), "xs[9007199254740991]").steps,
            [key("xs"), Step::Index(9_007_199_254_740_991)]
        );
        let zero = s::Position::Item {
            number: "0".to_string(),
            from_last: false,
        };
        assert!(Scope::new().path(&it(Some(zero))).is_err());
    }

    #[test]
    fn the_aliases_a_scope_knows_are_listed_sorted_and_once() {
        assert_eq!(scope().aliases(), ["artifact", "cov", "pr"]);
        assert_eq!(scope().parts().keys().collect::<Vec<_>>(), ["cov"]);
    }

    #[test]
    fn a_part_path_keeps_its_first_key_and_rejects_params_input_and_it() {
        let steps = part_steps(&path("d.b[1]")).unwrap();
        assert_eq!(steps, [key("d"), key("b"), Step::Index(1)]);
        assert_eq!(
            part_steps(&path("$params.x")).unwrap_err(),
            ["a part reads inside its subject, so it can't start at $params or $input"]
        );
        assert_eq!(
            part_steps(&path("$input.x")).unwrap_err(),
            ["a part reads inside its subject, so it can't start at $params or $input"]
        );
        assert_eq!(
            part_steps(&it(None)).unwrap_err(),
            ["it can only start an assertion: write it first, like it is not empty"]
        );
        assert_eq!(
            part_steps(&path("a1 named by foo")).unwrap_err(),
            ["unknown alias foo"]
        );
    }

    #[test]
    fn values_keep_their_type_and_numbers_as_they_were_written() {
        let scope = Scope::new();
        assert_eq!(
            scope.value(&s::Value::String("a".into())).unwrap(),
            json!("a")
        );
        assert_eq!(scope.value(&s::Value::True).unwrap(), json!(true));
        assert_eq!(scope.value(&s::Value::False).unwrap(), json!(false));
        assert_eq!(scope.value(&s::Value::Null).unwrap(), Value::Null);
        let number = scope.value(&s::Value::Number("1.50".into())).unwrap();
        assert_eq!(number.to_string(), "1.50");
        let number = scope.value(&s::Value::Number("1e2".into())).unwrap();
        assert_eq!(crate::value::equal(&number, &json!(100)), Some(true));
    }

    #[test]
    fn a_number_a_float_cannot_hold_is_written_wrong() {
        let scope = Scope::new();
        for text in ["1e400", "-1e400", "1e-400"] {
            assert_eq!(
                scope.value(&s::Value::Number(text.into())).unwrap_err(),
                [format!("number out of range: {text}")],
                "{text}"
            );
        }
        for text in [
            "0",
            "0.0",
            "-0",
            "2.2250738585072014e-308",
            "1.7976931348623157e308",
            "0e500",
        ] {
            assert!(
                scope.value(&s::Value::Number(text.into())).is_ok(),
                "{text}"
            );
        }
    }

    fn condition(text: &str) -> s::Condition {
        let line = s::parse_from(&format!("xs whose {text}")).unwrap();
        match line.whose.into_iter().next().unwrap() {
            s::FromCondition::Condition(condition) => condition,
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn exists_and_does_not_exist_lower_to_present_and_missing() {
        let Check::Present(found) = lower_condition(&condition("x exists"), &Scope::new()).unwrap()
        else {
            panic!("not present");
        };
        assert!(!found.missing);
        assert_eq!(found.path.steps, [key("x")]);
        let Check::Present(found) =
            lower_condition(&condition("x does not exist"), &Scope::new()).unwrap()
        else {
            panic!("not present");
        };
        assert!(found.missing);
    }

    #[test]
    fn the_left_side_of_a_condition_is_read_without_parents() {
        let Check::Present(found) =
            lower_condition(&condition("artifact.x exists"), &scope()).unwrap()
        else {
            panic!("not present");
        };
        assert_eq!(found.path.start, Start::Subject);
        assert_eq!(found.path.steps, [key("artifact"), key("x")]);
    }

    #[test]
    fn a_problem_in_the_path_of_a_condition_comes_back() {
        assert_eq!(
            lower_condition(&condition("xs[9007199254740992] exists"), &Scope::new()).unwrap_err(),
            ["9007199254740992 can't be a list position"]
        );
    }

    #[test]
    fn a_count_or_a_plus_on_the_right_of_a_from_condition_is_read_into_a_tally() {
        for text in [
            "x is at least count of ys",
            "x equals y plus 1",
            "x is less than sum of ys.n",
        ] {
            assert!(
                matches!(
                    lower_condition(&condition(text), &Scope::new()),
                    Ok(Check::Tally(_))
                ),
                "{text}"
            );
        }
    }

    #[test]
    fn a_count_on_the_left_of_a_from_condition_never_reads_a_parent() {
        let Ok(Check::Tally(found)) =
            lower_condition(&condition("count of artifact.xs is at least 1"), &scope())
        else {
            panic!("not a tally");
        };
        let paths = found.paths();
        assert_eq!(paths[0].start, Start::Subject);
        assert_eq!(paths[0].steps, [key("artifact"), key("xs")]);
    }

    #[test]
    fn a_count_on_the_left_is_read_into_a_tally() {
        assert!(matches!(
            lower_condition(&condition("count of xs is at least 1"), &Scope::new()),
            Ok(Check::Tally(_))
        ));
        assert!(matches!(
            lower_condition(&condition("sum of xs.n is between 1 and 2"), &Scope::new()),
            Ok(Check::Tally(_))
        ));
    }

    #[test]
    fn a_walk_counts_each_name_and_position_but_not_input_or_params() {
        let steps = |text: &str| walk_steps(&Scope::new().on_subject().path(&path(text)).unwrap());
        assert_eq!(steps("k1.k2.k3"), 3);
        assert_eq!(steps("first of k1.k2"), 3);
        assert_eq!(steps("$input.k1.k2"), 2);
        assert_eq!(steps("$params.k1"), 1);
    }

    #[test]
    fn a_walk_of_ten_steps_reads_and_one_of_eleven_is_written_wrong() {
        let ten = path::Path {
            start: Start::Subject,
            steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
        };
        assert_eq!(walk_too_long(&ten), None);
        let mut eleven = ten.clone();
        eleven.steps.push(Step::Key("k11".into()));
        assert_eq!(
            walk_too_long(&eleven).as_deref(),
            Some("every and some over more than ten steps aren't supported yet")
        );
    }

    #[test]
    fn an_alias_is_a_step_and_a_part_counts_its_own_path_in_place_of_its_alias() {
        let alias = path::Path {
            start: Start::Alias("z".into()),
            steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
        };
        assert_eq!(walk_steps(&alias), 11);
        let part = path::Path {
            start: Start::Part(Box::new(PartStart {
                name: "x".into(),
                base: Start::Subject,
                steps: (1..=10).map(|n| Step::Key(format!("k{n}"))).collect(),
                id: None,
            })),
            steps: vec![Step::Key("z".into())],
        };
        assert_eq!(walk_steps(&part), 11);
    }
}
