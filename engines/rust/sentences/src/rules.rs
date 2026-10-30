use crate::numbers::{Decimal, above_list_position, out_of_range, valid_pattern, written_time};
use crate::print::{increment, json_string, key_text, number_text, print_path};
use crate::tree::*;
use crate::words::is_word;
use std::cmp::Ordering;
use std::collections::BTreeSet;

const UNKNOWN_NAME: &str = "unknown name ";

/// Lists what is written wrong in a check that was read.
///
/// The messages are in `ergo.rego`'s words and sorted. It only reads the tree and the names in `aliases`. Rules that need the policy's names, like an alias named like a subject, are left to the engine. The list is empty when nothing is wrong.
///
/// ```
/// use ergo_sentences::{check_problems, parse_check};
///
/// let check = parse_check("x is not null").unwrap();
/// assert_eq!(check_problems(&check, &[]), [r#""is not null" is written "exists""#]);
/// ```
pub fn check_problems(check: &Check, aliases: &[&str]) -> Vec<String> {
    let mut found = check_base(check, &[]);
    if found.iter().all(|m| m.starts_with(UNKNOWN_NAME)) {
        found.extend(check_self(check, aliases));
    }
    found.into_iter().collect()
}

/// Lists only the problems of a check that come from a field compared with itself.
///
/// It gives what [`check_problems`] gives when the check has no other problem, and an empty list otherwise.
///
/// ```
/// use ergo_sentences::{check_self_problems, parse_check};
///
/// let check = parse_check("x equals x").unwrap();
/// assert_eq!(check_self_problems(&check, &[]), ["x is compared with itself"]);
/// ```
pub fn check_self_problems(check: &Check, aliases: &[&str]) -> Vec<String> {
    if check_base(check, &[]).is_empty() {
        check_self(check, aliases).into_iter().collect()
    } else {
        Vec::new()
    }
}

/// Lists what is written wrong in a `for` line that was read.
///
/// The messages are in `ergo.rego`'s words and sorted. It only reads the tree and the names in `aliases`. Rules that need the policy's names, like an alias named like a subject, are left to the engine. The list is empty when nothing is wrong.
pub fn for_problems(line: &ForLine, aliases: &[&str]) -> Vec<String> {
    let mut found = for_base(line, &[]);
    if found.iter().all(|m| m.starts_with(UNKNOWN_NAME)) {
        found.extend(for_self(line, aliases));
    }
    found.into_iter().collect()
}

/// Lists what is written wrong in a `from` line that was read.
///
/// The messages are in `ergo.rego`'s words and sorted. Rules that need the policy's names are left to the engine. The list is empty when nothing is wrong.
pub fn from_problems(line: &FromLine) -> Vec<String> {
    from_base(line).into_iter().collect()
}

pub(crate) fn check_base(check: &Check, hidden: &[Condition]) -> BTreeSet<String> {
    let mut walk = Walk::default();
    for condition in hidden {
        walk.condition(condition, false);
    }
    for assertion in &check.assertions {
        walk.assertion(assertion);
    }
    walk.finish()
}

pub(crate) fn for_base(line: &ForLine, hidden: &[Condition]) -> BTreeSet<String> {
    let mut walk = Walk::default();
    for condition in hidden {
        walk.condition(condition, false);
    }
    let aliases: Vec<&str> = line.items.iter().map(alias_of).collect();
    for (n, item) in line.items.iter().enumerate() {
        if aliases[..n].contains(&aliases[n]) {
            walk.out.insert(format!("{} is given twice", aliases[n]));
        }
        walk.item(item, &aliases);
    }
    walk.finish()
}

pub(crate) fn path_base(path: &Path) -> BTreeSet<String> {
    let mut walk = Walk::default();
    walk.path(path);
    walk.finish()
}

pub(crate) fn from_base(line: &FromLine) -> BTreeSet<String> {
    let mut walk = Walk::default();
    walk.path(&line.path);
    if let Some(each) = &line.named_by_each_of {
        walk.path(each);
    }
    for condition in &line.whose {
        match condition {
            FromCondition::Condition(condition) => walk.condition(condition, true),
            FromCondition::Quantified {
                quantifier,
                path,
                if_any,
                phrase,
            } => {
                walk.if_any_with_some(*quantifier, *if_any);
                walk.allowed(path);
                walk.phrase(phrase, true);
            }
        }
    }
    walk.finish()
}

fn alias_of(item: &ForItem) -> &str {
    match item {
        ForItem::Walk { alias, .. } | ForItem::Pick { alias, .. } => alias,
    }
}

fn bad_name(name: &str) -> bool {
    is_word(name) || name == "params" || name == "input"
}

fn is_whole_it(path: &Path) -> bool {
    path.start == Start::It && path.steps.is_empty()
}

fn op_name(phrase: &Phrase) -> &'static str {
    match phrase {
        Phrase::Is { not: false, .. } => "is",
        Phrase::Is { not: true, .. } => "is not",
        Phrase::Order { order, .. } => match order {
            Order::AtLeast => "is at least",
            Order::AtMost => "is at most",
            Order::MoreThan => "is more than",
            Order::LessThan => "is less than",
        },
        Phrase::Between { .. } => "is between",
        Phrase::OneOf { not: true, .. } => "is not one of",
        Phrase::OneOf { not: false, .. } => "is one of",
        Phrase::NonEmptyString => "is a non-empty string",
        Phrase::Type(_) => "is a",
        Phrase::Empty { not: true } => "is not empty",
        Phrase::Empty { not: false } => "is empty",
        Phrase::Exists { not: true } => "does not exist",
        Phrase::Exists { not: false } => "exists",
        Phrase::ContainsAll(_) => "contains all of",
        Phrase::ContainsNone(_) => "contains none of",
        Phrase::Contains { not: true, .. } => "does not contain",
        Phrase::Contains { not: false, .. } => "contains",
        Phrase::Matches { not: true, .. } => "does not match",
        Phrase::Matches { not: false, .. } => "matches",
        Phrase::StartsWith(_) => "starts with",
        Phrase::EndsWith(_) => "ends with",
        Phrase::Alphabetically { after: false, .. } => "is alphabetically before",
        Phrase::Alphabetically { after: true, .. } => "is alphabetically after",
        Phrase::Time { time, .. } => match time {
            TimeOrder::Before => "is before",
            TimeOrder::After => "is after",
            TimeOrder::OnOrAfter => "is on or after",
            TimeOrder::OnOrBefore => "is on or before",
        },
    }
}

fn comparable(phrase: &Phrase) -> bool {
    matches!(
        phrase,
        Phrase::Is { .. } | Phrase::Order { .. } | Phrase::Between { .. }
    )
}

fn in_range_number(value: &Value) -> bool {
    matches!(value, Value::Number(n) if !out_of_range(n))
}

#[derive(Default)]
struct Walk {
    out: BTreeSet<String>,
    whole_it: usize,
    allowed_it: usize,
}

impl Walk {
    fn finish(mut self) -> BTreeSet<String> {
        if self.whole_it > self.allowed_it {
            self.out.insert(
                "it can only start an assertion: write it first, like it is not empty".to_string(),
            );
        }
        self.out
    }

    fn if_any_with_some(&mut self, quantifier: Quantifier, if_any: bool) {
        if quantifier == Quantifier::Some && if_any {
            self.out.insert("if any can't go with some".to_string());
        }
    }

    fn index(&mut self, digits: &str) {
        if above_list_position(digits) {
            self.out
                .insert(format!("{digits} can't be a list position"));
        }
    }

    fn path(&mut self, path: &Path) {
        if let Some(Position::Item { number, .. }) = &path.position {
            self.index(number);
        }
        match &path.start {
            Start::Field { key, dot: false } if is_word(key) && key != "it" => {
                self.out
                    .insert(format!("{key} is a word of the grammar: write .{key}"));
            }
            Start::It => match path.steps.first() {
                None => self.whole_it += 1,
                Some(Step::Key(key) | Step::BracketKey(key)) => {
                    let text = key_text(key);
                    self.out.insert(format!(
                        "it is the whole subject: write {text}, not it.{text}"
                    ));
                }
                Some(_) => {
                    self.out
                        .insert("it is the whole subject: nothing can follow it".to_string());
                }
            },
            Start::Unknown(name) => {
                self.out.insert(format!("unknown name {name}"));
            }
            _ => {}
        }
        for step in &path.steps {
            match step {
                Step::Index(digits) => self.index(digits),
                Step::NamedBy(Reference::Unknown { name, .. })
                | Step::Brackets(Reference::Unknown { name, .. }) => {
                    self.out.insert(format!("unknown name {name}"));
                }
                Step::NamedBy(Reference::Name(name)) | Step::Brackets(Reference::Name(name)) => {
                    if name == "it" {
                        self.out.insert("it can't name a key".to_string());
                    } else if bad_name(name) {
                        self.out.insert(format!("{name} can't be an alias"));
                    }
                }
                _ => {}
            }
        }
    }

    fn allowed(&mut self, path: &Path) {
        if is_whole_it(path) {
            self.allowed_it += 1;
        }
        self.path(path);
    }

    fn number(&mut self, text: &str) {
        if out_of_range(text) {
            self.out.insert(format!("number out of range: {text}"));
        }
    }

    fn value(&mut self, value: &Value) {
        if let Value::Number(text) = value {
            self.number(text);
        }
    }

    fn derived(&mut self, derived: &Derived, allow_it: bool) {
        if allow_it {
            self.allowed(&derived.path);
        } else {
            self.path(&derived.path);
        }
        for condition in &derived.whose {
            self.condition(condition, false);
        }
    }

    fn elapsed(&mut self, elapsed: &Elapsed) {
        self.path(&elapsed.from);
        self.path(&elapsed.to);
    }

    fn term(&mut self, term: &Term) {
        match term {
            Term::Path(path) => self.path(path),
            Term::Number(text) => self.number(text),
            Term::Derived(derived) => self.derived(derived, false),
            Term::Elapsed(elapsed) => self.elapsed(elapsed),
        }
    }

    fn operand(&mut self, operand: &Operand) {
        match operand {
            Operand::Value(value) => self.value(value),
            Operand::Field(terms) => terms.iter().for_each(|t| self.term(t)),
        }
    }

    fn list(&mut self, list: &List) {
        match list {
            List::Values(values) => values.iter().for_each(|v| self.value(v)),
            List::Path(path) => self.path(path),
        }
    }

    fn phrase(&mut self, phrase: &Phrase, quantified: bool) {
        let op = op_name(phrase);
        if quantified
            && matches!(
                phrase,
                Phrase::Contains { .. } | Phrase::ContainsAll(_) | Phrase::ContainsNone(_)
            )
        {
            self.out.insert(format!(
                "\"{op}\" after every or some would check each item of the last list, not the list: put the walk on a for line"
            ));
        }
        match phrase {
            Phrase::Is {
                not,
                operand,
                within,
            } => {
                if *not && matches!(operand, Operand::Value(Value::Null)) {
                    self.out
                        .insert("\"is not null\" is written \"exists\"".to_string());
                }
                if let Some(within) = within {
                    if let Operand::Value(value) = operand
                        && !in_range_number(value)
                    {
                        self.out
                            .insert("\"within\" only compares numbers".to_string());
                    }
                    if let Some(decimal) = Decimal::read(within)
                        && !decimal.out_of_range()
                        && decimal.is_negative()
                    {
                        self.out
                            .insert("\"within\" needs a number of 0 or more".to_string());
                    }
                    self.number(within);
                }
                self.operand(operand);
            }
            Phrase::Order { operand, .. } => {
                if let Operand::Value(value) = operand
                    && !matches!(value, Value::Number(_))
                {
                    self.out.insert(format!("\"{op}\" takes a number"));
                }
                self.operand(operand);
            }
            Phrase::Time { operand, .. } => {
                if let Operand::Value(value) = operand {
                    let fine = match value {
                        Value::Number(_) => true,
                        Value::String(text) => written_time(text),
                        _ => false,
                    };
                    if !fine {
                        self.out
                            .insert(format!("\"{op}\" takes a time or a number"));
                    }
                }
                self.operand(operand);
            }
            Phrase::StartsWith(operand)
            | Phrase::EndsWith(operand)
            | Phrase::Alphabetically { operand, .. } => {
                if let Operand::Value(value) = operand
                    && !matches!(value, Value::String(_))
                {
                    self.out.insert(format!("\"{op}\" takes text"));
                }
                self.operand(operand);
            }
            Phrase::Contains { operand, .. } => self.operand(operand),
            Phrase::Between { min, max } => {
                self.number(min);
                self.number(max);
                if let (Some(low), Some(high)) = (Decimal::read(min), Decimal::read(max))
                    && !low.out_of_range()
                    && !high.out_of_range()
                    && low.compare(&high) == Ordering::Greater
                {
                    self.out.insert("min above max".to_string());
                }
            }
            Phrase::OneOf { list, .. } | Phrase::ContainsAll(list) | Phrase::ContainsNone(list) => {
                self.list(list);
            }
            Phrase::Matches { list, .. } => {
                if let List::Values(values) = list {
                    for value in values {
                        let text = match value {
                            Value::String(text) if valid_pattern(text) => continue,
                            Value::String(text) => json_string(text),
                            Value::Number(text) if out_of_range(text) => continue,
                            Value::Number(text) => number_text(text),
                            Value::True => "true".to_string(),
                            Value::False => "false".to_string(),
                            Value::Null => "null".to_string(),
                        };
                        self.out.insert(format!("invalid pattern {text}"));
                    }
                }
                self.list(list);
            }
            Phrase::Exists { .. }
            | Phrase::Empty { .. }
            | Phrase::NonEmptyString
            | Phrase::Type(_) => {}
        }
    }

    fn after_terms(&mut self, terms: &[Term], phrase: &Phrase) {
        if !comparable(phrase) {
            self.out.insert(format!(
                "{} can't follow a count of, a sum of or a plus",
                op_name(phrase)
            ));
        }
        if let [Term::Number(text)] = terms
            && !out_of_range(text)
        {
            self.out
                .insert("a number can't start a sentence".to_string());
        }
    }

    fn condition(&mut self, condition: &Condition, allow_it: bool) {
        match &condition.left {
            Left::Path(path) => {
                if allow_it {
                    self.allowed(path);
                } else {
                    self.path(path);
                }
            }
            Left::Derived(derived) => {
                self.derived(derived, allow_it);
                self.after_terms(&[], &condition.phrase);
            }
            Left::Elapsed(elapsed) => {
                self.elapsed(elapsed);
                self.after_terms(&[], &condition.phrase);
            }
        }
        self.phrase(&condition.phrase, false);
    }

    fn assertion(&mut self, assertion: &Assertion) {
        match assertion {
            Assertion::Plain { path, phrase } => {
                self.allowed(path);
                self.phrase(phrase, false);
            }
            Assertion::Quantified {
                quantifier,
                path,
                whose,
                if_any,
                phrase,
            } => {
                self.if_any_with_some(*quantifier, *if_any);
                self.allowed(path);
                for condition in whose {
                    self.condition(condition, false);
                }
                self.phrase(phrase, true);
            }
            Assertion::Derived { terms, phrase } => {
                for term in terms {
                    match term {
                        Term::Derived(derived) => self.derived(derived, true),
                        other => self.term(other),
                    }
                }
                self.after_terms(terms, phrase);
                self.phrase(phrase, false);
            }
        }
    }

    fn item(&mut self, item: &ForItem, aliases: &[&str]) {
        let alias = alias_of(item);
        if bad_name(alias) {
            self.out.insert(format!("{alias} can't be an alias"));
        }
        match item {
            ForItem::Walk {
                quantifier,
                path,
                whose,
                if_any,
                ..
            } => {
                self.if_any_with_some(*quantifier, *if_any);
                self.path(path);
                for condition in whose {
                    self.condition(condition, false);
                }
            }
            ForItem::Pick {
                position,
                path,
                whose,
                sorted_by,
                ..
            } => {
                if let Position::Item { number, .. } = position {
                    self.index(number);
                }
                self.path(path);
                for condition in whose {
                    self.condition(condition, false);
                }
                if let Some(sorted) = sorted_by {
                    self.path(&sorted.path);
                    if sorted.path.position.is_some()
                        || matches!(
                            sorted.path.start,
                            Start::Params | Start::Input | Start::Unknown(_)
                        )
                    {
                        self.out
                            .insert("\"sorted by\" reads a field of each item".to_string());
                    } else {
                        let name = match &sorted.path.start {
                            Start::Field { key, dot: false } => Some(key.as_str()),
                            Start::It => Some("it"),
                            _ => None,
                        };
                        if let Some(name) = name
                            && aliases.contains(&name)
                        {
                            self.out.insert(format!(
                                "\"sorted by\" reads a field of the item, not {name}: write .{name}"
                            ));
                        }
                    }
                }
            }
        }
    }
}

#[derive(PartialEq)]
enum Kind {
    It,
    Params,
    Input,
    Unknown(String),
    Field(String),
}

fn normal_step(step: &Step) -> Step {
    match step {
        Step::BracketKey(key) => Step::Key(key.clone()),
        Step::Brackets(reference) => Step::NamedBy(reference.clone()),
        other => other.clone(),
    }
}

fn lifted(path: &Path) -> (Option<Position>, Vec<Step>) {
    match (&path.position, &path.start, path.steps.last()) {
        (None, start, Some(Step::Index(number))) if *start != Start::It => (
            Some(Position::Item {
                number: increment(number),
                from_last: false,
            }),
            path.steps[..path.steps.len() - 1]
                .iter()
                .map(normal_step)
                .collect(),
        ),
        _ => (
            path.position.clone(),
            path.steps.iter().map(normal_step).collect(),
        ),
    }
}

fn kind_of(path: &Path) -> Kind {
    match &path.start {
        Start::It => Kind::It,
        Start::Params => Kind::Params,
        Start::Input => Kind::Input,
        Start::Unknown(name) => Kind::Unknown(name.clone()),
        Start::Field { key, .. } | Start::Quoted(key) => Kind::Field(key.clone()),
    }
}

fn dot_of(path: &Path) -> bool {
    matches!(
        path.start,
        Start::Field { dot: true, .. } | Start::Quoted(_)
    )
}

fn first_key(path: &Path) -> Option<&str> {
    match &path.start {
        Start::Field { key, .. } | Start::Quoted(key) => Some(key),
        _ => None,
    }
}

fn same_path(left: &Path, right: &Path, aliases: &[&str], left_own: bool) -> bool {
    if kind_of(left) != kind_of(right) || lifted(left) != lifted(right) {
        return false;
    }
    match first_key(left) {
        Some(key) if aliases.contains(&key) => {
            if left_own {
                dot_of(right)
            } else {
                dot_of(left) == dot_of(right)
            }
        }
        _ => true,
    }
}

fn self_term(phrase: &Phrase) -> Option<&Path> {
    let operand = match phrase {
        Phrase::Is { operand, .. }
        | Phrase::Order { operand, .. }
        | Phrase::Time { operand, .. }
        | Phrase::StartsWith(operand)
        | Phrase::EndsWith(operand)
        | Phrase::Alphabetically { operand, .. } => operand,
        _ => return None,
    };
    match operand {
        Operand::Field(terms) => match terms.as_slice() {
            [Term::Path(path)] => Some(path),
            _ => None,
        },
        _ => None,
    }
}

fn full_steps(path: &Path) -> Vec<Step> {
    let (_, steps) = lifted(path);
    let mut all = Vec::new();
    match &path.start {
        Start::Field { key, .. } | Start::Quoted(key) => all.push(Step::Key(key.clone())),
        Start::It => all.push(Step::Key("it".to_string())),
        _ => {}
    }
    all.extend(steps);
    all
}

fn whose_self(whose: &[Condition], aliases: &[&str], derived_holder: bool) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for condition in whose {
        let Left::Path(path) = &condition.left else {
            continue;
        };
        let Some(term) = self_term(&condition.phrase) else {
            continue;
        };
        if same_path(path, term, aliases, true) {
            let text = print_path(path, Side::Left, &[]);
            let advice = if derived_holder {
                ", and a count or a sum can't read the subject's field there yet".to_string()
            } else {
                format!(": to read the subject's {text}, compare under assert")
            };
            out.insert(format!(
                "{text} is compared with itself, because in a whose it's read from the item{advice}"
            ));
        }
    }
    out
}

fn check_self(check: &Check, aliases: &[&str]) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for assertion in &check.assertions {
        match assertion {
            Assertion::Plain { path, phrase } => {
                if let Some(term) = self_term(phrase)
                    && same_path(path, term, aliases, false)
                {
                    out.insert(format!(
                        "{} is compared with itself",
                        print_path(path, Side::Left, aliases)
                    ));
                }
            }
            Assertion::Quantified {
                path,
                whose,
                phrase,
                ..
            } => {
                out.extend(whose_self(whose, aliases, false));
                if let Some(term) = self_term(phrase)
                    && first_key(term).is_none_or(|key| dot_of(term) || !aliases.contains(&key))
                    && term.position.is_none()
                    && term.start != Start::Params
                    && term.start != Start::Input
                    && !matches!(term.start, Start::Unknown(_))
                    && term.start != Start::It
                    && !matches!(term.steps.last(), Some(Step::Index(_)))
                {
                    let walked = full_steps(path);
                    let steps = full_steps(term);
                    if steps.len() < walked.len()
                        && walked[walked.len() - steps.len()..] == steps[..]
                    {
                        let text = print_path(term, Side::Left, &[]);
                        out.insert(format!(
                            "{text} is compared with itself, because after every or some it's read from the item: to read the subject's {text}, put the list on the for line and compare under assert"
                        ));
                    }
                }
            }
            Assertion::Derived { terms, .. } => {
                if let Some(Term::Derived(derived)) = terms.last() {
                    out.extend(whose_self(&derived.whose, aliases, true));
                }
            }
        }
    }
    out
}

fn for_self(line: &ForLine, aliases: &[&str]) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for (n, item) in line.items.iter().enumerate() {
        let names: Vec<&str> = aliases
            .iter()
            .copied()
            .chain(line.items[..n].iter().map(alias_of))
            .collect();
        let whose = match item {
            ForItem::Walk { whose, .. } | ForItem::Pick { whose, .. } => whose,
        };
        out.extend(whose_self(whose, &names, false));
    }
    out
}
