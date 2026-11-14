use crate::path::{Path, Start, Step};
use std::collections::BTreeSet;

const WORDS: &[&str] = &[
    "a",
    "after",
    "alphabetically",
    "an",
    "and",
    "as",
    "at",
    "before",
    "between",
    "count",
    "days",
    "distinct",
    "each",
    "empty",
    "equal",
    "every",
    "false",
    "first",
    "hours",
    "in",
    "item",
    "last",
    "less",
    "minutes",
    "more",
    "named",
    "not",
    "null",
    "of",
    "on",
    "one",
    "or",
    "plus",
    "seconds",
    "some",
    "sorted",
    "sum",
    "that",
    "to",
    "true",
    "weeks",
    "whose",
    "within",
];

pub fn is_word(key: &str) -> bool {
    WORDS.contains(&key)
}

fn is_bare(key: &str) -> bool {
    let mut bytes = key.bytes();
    match bytes.next() {
        Some(b) if b.is_ascii_alphabetic() || b == b'_' => {}
        _ => return false,
    }
    bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

pub fn key_text(key: &str) -> String {
    if is_bare(key) {
        key.to_string()
    } else {
        serde_json::to_string(key).unwrap_or_default()
    }
}

pub fn parent_key_text(key: &str) -> String {
    if is_word(key) {
        serde_json::to_string(key).unwrap_or_default()
    } else {
        key_text(key)
    }
}

pub fn name(path: &Path) -> String {
    render(path, None)
}

pub fn marked_name(path: &Path, marks: &BTreeSet<usize>) -> String {
    render(path, Some(marks))
}

fn render(path: &Path, marks: Option<&BTreeSet<usize>>) -> String {
    let mark = |out: &mut String, at: usize| {
        if marks.is_some_and(|marks| marks.contains(&at)) {
            if out.is_empty() {
                out.push_str("the subject");
            }
            out.push_str("[]");
        }
    };
    let mut out = match &path.start {
        Start::Subject | Start::Own => String::new(),
        Start::Alias(alias) if alias == crate::path::OUTER => String::new(),
        Start::Input => "$input".to_string(),
        Start::Params => "$params".to_string(),
        Start::Alias(alias) => parent_key_text(alias),
        Start::Part(_) if crate::path::is_root(&path.start) => String::new(),
        Start::Part(part) => part.name.clone(),
    };
    let last = path.steps.len().saturating_sub(1);
    for (at, step) in path.steps.iter().enumerate() {
        mark(&mut out, at);
        match step {
            Step::Key(key) => {
                if out.is_empty() {
                    if is_word(key)
                        || (at == 0
                            && (path.start == Start::Own || crate::path::is_root_own(&path.start)))
                    {
                        out.push('.');
                    }
                } else {
                    out.push('.');
                }
                out.push_str(&key_text(key));
            }
            Step::Index(index) => {
                if at == last && marks.is_none() {
                    let rest = if out.is_empty() { "the subject" } else { &out };
                    out = format!("item {} of {}", index.saturating_add(1), rest);
                } else {
                    if out.is_empty() && marks.is_some() {
                        out.push_str("the subject");
                    }
                    out.push_str(&format!("[{index}]"));
                }
            }
            Step::Ref(reference) | Step::Field(reference) => {
                let ref_name = name(reference);
                let one_key = ((matches!(
                    reference.start,
                    Start::Input | Start::Params | Start::Subject | Start::Own
                ) || crate::path::is_root(&reference.start)
                    || crate::path::names_the_subject(&reference.start))
                    && matches!(reference.steps.as_slice(), [Step::Key(_)]))
                    || (matches!(reference.start, Start::Alias(_)) && reference.steps.is_empty());
                if one_key && !out.is_empty() {
                    out.push_str(&format!(" named by {ref_name}"));
                } else {
                    out.push_str(&format!("[{ref_name}]"));
                }
            }
        }
    }
    mark(&mut out, path.steps.len());
    if out.is_empty() {
        "the subject".to_string()
    } else {
        out
    }
}

#[cfg(test)]
mod tests;
