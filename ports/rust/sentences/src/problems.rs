use crate::error::SyntaxError;
use crate::parse::Parser;
use crate::print::key_text;
use crate::tree::*;
use crate::words::is_word;
use std::collections::BTreeSet;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    From,
    Path,
}

pub(crate) fn errors(text: &str, kind: Kind) -> Vec<SyntaxError> {
    let text = match kind {
        Kind::From => after_every(text),
        Kind::Path => text,
    };
    messages(text, kind)
        .into_iter()
        .map(SyntaxError::new)
        .collect()
}

fn after_every(text: &str) -> &str {
    if let Some(rest) = text.strip_prefix("every ") {
        let rest = rest.trim_start_matches(' ');
        if !rest.is_empty() {
            return rest;
        }
    }
    text
}

fn messages(text: &str, kind: Kind) -> Vec<String> {
    let c: Vec<char> = text.chars().collect();
    let closed = closed_length(&c);
    if closed < c.len() {
        return vec![format!("unclosed quote at column {}", closed + 1)];
    }
    let invalid = invalid_strings(&c);
    if !invalid.is_empty() {
        return invalid;
    }
    let lenient = lenient_problems(text, kind);
    if !lenient.is_empty() {
        return lenient;
    }
    let names = unknown_names(&c);
    if !names.is_empty() {
        return names;
    }
    if kind == Kind::Path {
        return vec!["doesn't parse".to_string()];
    }
    if two_quantifiers(&c) {
        return vec!["two quantifiers in one sentence: put them on a for line".to_string()];
    }
    if text.ends_with(" within") {
        return vec![r#""within" needs a number after it"#.to_string()];
    }
    if is_quantified_path(text) {
        return vec![format!(
            "nothing after the path at column {}: expected a phrase, like \"is\" or \"exists\"",
            c.len() + 1
        )];
    }
    if whose_inside_whose(&c) {
        return vec!["a condition after whose can't have a whose of its own".to_string()];
    }
    vec!["doesn't parse".to_string()]
}

fn closed_length(c: &[char]) -> usize {
    let mut i = 0;
    while i < c.len() {
        match string_end(c, i) {
            Some(Some(end)) => i = end,
            Some(None) => return i,
            None => i += 1,
        }
    }
    i
}

fn string_end(c: &[char], start: usize) -> Option<Option<usize>> {
    let quote = c[start];
    if quote != '"' && quote != '\'' {
        return None;
    }
    let mut j = start + 1;
    while j < c.len() {
        if c[j] == '\\' {
            if j + 1 >= c.len() {
                return Some(None);
            }
            j += 2;
        } else if c[j] == quote {
            return Some(Some(j + 1));
        } else {
            j += 1;
        }
    }
    Some(None)
}

fn invalid_strings(c: &[char]) -> Vec<String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        match string_end(c, i) {
            Some(Some(end)) => {
                let token: String = c[i..end].iter().collect();
                if !Parser::new(&token, false).is_whole_string() {
                    out.push(format!("invalid string at column {}", i + 1));
                }
                i = end;
            }
            _ => i += 1,
        }
    }
    out
}

fn unknown_names(c: &[char]) -> Vec<String> {
    let mut names = BTreeSet::new();
    let mut i = 0;
    while i < c.len() {
        if let Some(Some(end)) = string_end(c, i) {
            i = end;
            continue;
        }
        let at = if i == 0 && c[0] == '$' {
            Some(0)
        } else if matches!(c[i], ' ' | ',' | '[') && c.get(i + 1) == Some(&'$') {
            Some(i + 1)
        } else {
            None
        };
        let Some(at) = at else {
            i += 1;
            continue;
        };
        let mut j = at + 1;
        if c.get(j)
            .is_some_and(|ch| ch.is_ascii_alphabetic() || *ch == '_')
        {
            while c
                .get(j)
                .is_some_and(|ch| ch.is_ascii_alphanumeric() || *ch == '_')
            {
                j += 1;
            }
            let name: String = c[at..j].iter().collect();
            if name != "$params" && name != "$input" {
                names.insert(format!("unknown name {name}"));
            }
            i = j;
        } else {
            i += 1;
        }
    }
    names.into_iter().collect()
}

fn spaces(c: &[char], i: usize) -> Option<usize> {
    let mut j = i;
    while c.get(j) == Some(&' ') {
        j += 1;
    }
    if j > i { Some(j) } else { None }
}

fn quantifier_word(c: &[char], i: usize) -> Option<usize> {
    for word in ["every", "some"] {
        let len = word.chars().count();
        if c.len() >= i + len && c[i..i + len].iter().copied().eq(word.chars()) {
            return Some(i + len);
        }
    }
    None
}

fn word_at(c: &[char], i: usize, word: &str) -> Option<usize> {
    let len = word.chars().count();
    if c.len() >= i + len && c[i..i + len].iter().copied().eq(word.chars()) {
        Some(i + len)
    } else {
        None
    }
}

fn two_quantifiers(c: &[char]) -> bool {
    let Some(i) = quantifier_word(c, 0).and_then(|i| spaces(c, i)) else {
        return false;
    };
    let mut j = i;
    while c.get(j).is_some_and(|ch| !ch.is_whitespace()) {
        j += 1;
    }
    if j == i {
        return false;
    }
    let Some(k) = spaces(c, j).and_then(|k| quantifier_word(c, k)) else {
        return false;
    };
    c.get(k) == Some(&' ')
}

fn is_quantified_path(text: &str) -> bool {
    let parser = Parser::new(text, true);
    let c: Vec<char> = text.chars().collect();
    let mut starts = vec![0];
    if let Some(i) = quantifier_word(&c, 0).and_then(|i| spaces(&c, i)) {
        starts.push(i);
    }
    starts.into_iter().any(|i| {
        parser
            .path(i, Side::Left)
            .iter()
            .any(|(_, end)| *end == parser.len())
    })
}

fn quantified_whose(c: &[char], i: usize) -> bool {
    let after = if let Some(j) = quantifier_word(c, i).and_then(|j| spaces(c, j)) {
        j
    } else if let Some(j) = ["count", "sum"]
        .iter()
        .find_map(|w| word_at(c, i, w))
        .and_then(|j| spaces(c, j))
        .and_then(|j| word_at(c, j, "of"))
        .and_then(|j| spaces(c, j))
    {
        j
    } else {
        return false;
    };
    let mut j = after;
    while c.get(j).is_some_and(|ch| !ch.is_whitespace()) {
        j += 1;
    }
    if j == after {
        return false;
    }
    spaces(c, j)
        .and_then(|k| word_at(c, k, "whose"))
        .and_then(|k| spaces(c, k))
        .is_some()
}

fn whose_inside_whose(c: &[char]) -> bool {
    for start in 0..c.len() {
        let Some(after) = spaces(c, start)
            .and_then(|i| word_at(c, i, "whose"))
            .and_then(|i| spaces(c, i))
        else {
            continue;
        };
        if quantified_whose(c, after) {
            return true;
        }
        for k in after..c.len() {
            if let Some(next) = spaces(c, k)
                .and_then(|i| word_at(c, i, "and"))
                .and_then(|i| spaces(c, i))
                && quantified_whose(c, next)
            {
                return true;
            }
        }
    }
    false
}

fn lenient_problems(text: &str, kind: Kind) -> Vec<String> {
    let parser = Parser::new(text, true);
    let mut found = Found::default();
    match kind {
        Kind::From => {
            let Some(line) = parser.whole(parser.read_from_core(0, false)) else {
                return Vec::new();
            };
            found.from(&line);
        }
        Kind::Path => {
            let Some(path) = parser.whole(parser.path(0, Side::Left)) else {
                return Vec::new();
            };
            found.path(&path);
        }
    }
    let mut messages = found.messages;
    if found.whole_it > found.allowed_it {
        messages.insert(
            "it can only start an assertion: write it first, like it is not empty".to_string(),
        );
    }
    messages.into_iter().collect()
}

#[derive(Default)]
struct Found {
    messages: BTreeSet<String>,
    whole_it: usize,
    allowed_it: usize,
}

impl Found {
    fn path(&mut self, path: &Path) {
        match &path.start {
            Start::Field { key, dot: false } if is_word(key) => {
                self.messages
                    .insert(format!("{key} is a word of the grammar: write .{key}"));
            }
            Start::It => match path.steps.first() {
                None => self.whole_it += 1,
                Some(Step::Key(key) | Step::BracketKey(key)) => {
                    let text = key_text(key);
                    self.messages.insert(format!(
                        "it is the whole subject: write {text}, not it.{text}"
                    ));
                }
                Some(_) => {
                    self.messages
                        .insert("it is the whole subject: nothing can follow it".to_string());
                }
            },
            _ => {}
        }
        for step in &path.steps {
            if let Step::NamedBy(Reference::Name(name)) | Step::Brackets(Reference::Name(name)) =
                step
            {
                if name == "it" {
                    self.messages.insert("it can't name a key".to_string());
                } else if is_word(name) || name == "params" || name == "input" {
                    self.messages.insert(format!("{name} can't be an alias"));
                }
            }
        }
    }

    fn allowed(&mut self, path: &Path) {
        if path.start == Start::It && path.steps.is_empty() {
            self.allowed_it += 1;
        }
        self.path(path);
    }

    fn derived(&mut self, derived: &Derived, allowed: bool) {
        if allowed {
            self.allowed(&derived.path);
        } else {
            self.path(&derived.path);
        }
    }

    fn elapsed(&mut self, elapsed: &Elapsed) {
        self.path(&elapsed.from);
        self.path(&elapsed.to);
    }

    fn term(&mut self, term: &Term) {
        match term {
            Term::Path(path) => self.path(path),
            Term::Number(_) => {}
            Term::Derived(derived) => self.derived(derived, false),
            Term::Elapsed(elapsed) => self.elapsed(elapsed),
        }
    }

    fn operand(&mut self, operand: &Operand) {
        if let Operand::Field(terms) = operand {
            for term in terms {
                self.term(term);
            }
        }
    }

    fn list(&mut self, list: &List) {
        if let List::Path(path) = list {
            self.path(path);
        }
    }

    fn phrase(&mut self, phrase: &Phrase) {
        match phrase {
            Phrase::Is { operand, .. }
            | Phrase::Order { operand, .. }
            | Phrase::Contains { operand, .. }
            | Phrase::StartsWith(operand)
            | Phrase::EndsWith(operand)
            | Phrase::Alphabetically { operand, .. }
            | Phrase::Time { operand, .. } => self.operand(operand),
            Phrase::OneOf { list, .. }
            | Phrase::ContainsAll(list)
            | Phrase::ContainsNone(list)
            | Phrase::Matches { list, .. } => self.list(list),
            Phrase::Between { .. }
            | Phrase::Exists { .. }
            | Phrase::Empty { .. }
            | Phrase::NonEmptyString
            | Phrase::Type(_) => {}
        }
    }

    fn condition(&mut self, condition: &Condition) {
        match &condition.left {
            Left::Path(path) => self.allowed(path),
            Left::Derived(derived) => {
                self.derived(derived, true);
                self.compare_only(&condition.phrase);
            }
            Left::Elapsed(elapsed) => {
                self.elapsed(elapsed);
                self.compare_only(&condition.phrase);
            }
        }
        self.phrase(&condition.phrase);
    }

    fn compare_only(&mut self, phrase: &Phrase) {
        let op = match phrase {
            Phrase::Is { .. } | Phrase::Order { .. } | Phrase::Between { .. } => return,
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
        };
        self.messages
            .insert(format!("{op} can't follow a count of, a sum of or a plus"));
    }

    fn from(&mut self, line: &From) {
        self.path(&line.path);
        if let Some(each) = &line.named_by_each_of {
            self.path(each);
        }
        for condition in &line.whose {
            match condition {
                FromCondition::Condition(condition) => self.condition(condition),
                FromCondition::Quantified { path, phrase, .. } => {
                    self.allowed(path);
                    self.phrase(phrase);
                }
            }
        }
    }
}
