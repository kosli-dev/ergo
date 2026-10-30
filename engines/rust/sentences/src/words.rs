pub(crate) const WORDS: [&str; 42] = [
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
    "each",
    "empty",
    "equal",
    "every",
    "false",
    "first",
    "hours",
    "in",
    "it",
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
    "to",
    "true",
    "weeks",
    "whose",
    "within",
];

pub(crate) fn is_word(key: &str) -> bool {
    WORDS.contains(&key)
}

pub(crate) fn is_bare_key(key: &str) -> bool {
    let mut chars = key.chars();
    match chars.next() {
        Some(first) if first.is_ascii_alphabetic() || first == '_' => {}
        _ => return false,
    }
    chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-')
}
