use crate::error::SyntaxError;
use crate::parse::{self, Parser};
use crate::rules;
use crate::tree::*;
use std::collections::BTreeSet;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    Check,
    For,
    From,
    Path,
}

pub(crate) fn errors(text: &str, kind: Kind) -> Vec<SyntaxError> {
    let found = match kind {
        Kind::From => messages(after_every(text), kind),
        Kind::For => for_messages(text),
        Kind::Check | Kind::Path => messages(text, kind),
    };
    found.into_iter().map(SyntaxError::new).collect()
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
    if kind == Kind::From && whose_inside_whose(&c) {
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
    let found = match kind {
        Kind::From => parser
            .whole(parser.read_from_core(0, false))
            .map(|line| rules::from_base(&line)),
        Kind::Path => parser
            .whole(parser.path(0, Side::Left))
            .map(|path| rules::path_base(&path)),
        Kind::Check => parser.read_check().map(|(check, notes)| {
            let (texts, hidden) = split_notes(notes);
            let mut found = rules::check_base(&check, &hidden);
            found.extend(texts);
            found
        }),
        Kind::For => parser.read_for(usize::MAX).map(|(line, notes)| {
            let (texts, hidden) = split_notes(notes);
            let mut found = rules::for_base(&line, &hidden);
            found.extend(texts);
            found
        }),
    };
    found.unwrap_or_default().into_iter().collect()
}

fn split_notes(notes: parse::Notes) -> (Vec<String>, Vec<Condition>) {
    let mut texts = Vec::new();
    let mut hidden = Vec::new();
    for note in notes {
        match note {
            parse::Note::Text(text) => texts.push(text.to_string()),
            parse::Note::Hidden(conditions) => hidden.extend(conditions),
        }
    }
    (texts, hidden)
}

fn ends_with_as_name(text: &str) -> bool {
    let start = text.rfind([' ', ',']).map_or(0, |at| {
        at + text[at..].chars().next().map_or(1, char::len_utf8)
    });
    if start >= text.len() {
        return false;
    }
    let prefix = &text[..start];
    let words = prefix.trim_end_matches(' ');
    words.len() < prefix.len() && words.ends_with(" as")
}

fn starts_with_item_word(text: &str) -> bool {
    ["every ", "some ", "first ", "last ", "item "]
        .iter()
        .any(|word| text.starts_with(word))
}

fn for_messages(text: &str) -> Vec<String> {
    let parser = Parser::new(text, true);
    if let Some((line, _)) = parser.read_for(usize::MAX)
        && line.items.len() > 2
    {
        return vec!["a for line holds two items at most".to_string()];
    }
    if !starts_with_item_word(text) {
        return vec![parse::ITEM_START.to_string()];
    }
    if !ends_with_as_name(text) {
        return vec![
            r#"an item ends with "as" and a name, like "every pull_requests as pr""#.to_string(),
        ];
    }
    messages(text, Kind::For)
}
