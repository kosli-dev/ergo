use crate::numbers::above_list_position;
use crate::tree::*;
use crate::words::{is_bare_key, is_word};

/// Prints a path as a canonical sentence.
///
/// `side` says whether the path is left of a phrase or right of it. `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// ```
/// use ergo_sentences::{Side, parse_path, print_path};
///
/// let path = parse_path("  x.y[1]  ").unwrap();
/// assert_eq!(print_path(&path, Side::Left, &[]), "item 2 of x.y");
/// ```
pub fn print_path(path: &Path, side: Side, aliases: &[&str]) -> String {
    path_text(path, side, aliases, false)
}

/// Prints a term as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
pub fn print_term(term: &Term, aliases: &[&str]) -> String {
    term_text(term, aliases, false)
}

/// Prints a term that stands on the left of a phrase.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// `parents` holds the names of a child subject's parents. On the left of a `whose`, a key named like a parent reads the item's own field, so it prints with a dot.
pub fn print_left_term(term: &Term, aliases: &[&str], parents: &[&str]) -> String {
    match term {
        Term::Derived(derived) => {
            let word = match derived.kind {
                DerivedKind::Count => "count of",
                DerivedKind::Sum => "sum of",
            };
            format!(
                "{word} {}{}",
                left_of_whose(&derived.path, aliases, parents, true),
                whose_text(&derived.whose, aliases)
            )
        }
        other => term_text(other, aliases, true),
    }
}

/// Prints a `whose` condition as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
pub fn print_condition(condition: &Condition, aliases: &[&str]) -> String {
    condition_text(condition, aliases)
}

/// Prints one `whose` condition of a `from` line as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
pub fn print_from_condition(condition: &FromCondition, aliases: &[&str]) -> String {
    print_from_condition_with(condition, aliases, &[])
}

fn left_of_whose(path: &Path, aliases: &[&str], parents: &[&str], own: bool) -> String {
    match &path.start {
        Start::Field { key, .. } if parents.contains(&key.as_str()) => {
            let mut dotted = path.clone();
            dotted.start = Start::Field {
                key: key.clone(),
                dot: true,
            };
            path_text(&dotted, Side::Left, aliases, false)
        }
        _ => path_text(path, Side::Left, aliases, own),
    }
}

/// Prints one `whose` condition of a `from` line, for a child subject.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// `parents` holds the names of a child subject's parents. On the left of a `whose`, a key named like a parent reads the item's own field, so it prints with a dot.
pub fn print_from_condition_with(
    condition: &FromCondition,
    aliases: &[&str],
    parents: &[&str],
) -> String {
    from_condition_text(condition, aliases, parents, true, false)
}

fn from_condition_text(
    condition: &FromCondition,
    aliases: &[&str],
    parents: &[&str],
    dot_derived: bool,
    own: bool,
) -> String {
    match condition {
        FromCondition::Condition(condition) => {
            let left = match &condition.left {
                Left::Path(path) => left_of_whose(path, aliases, parents, own),
                Left::Derived(derived) if dot_derived => {
                    print_left_term(&Term::Derived(derived.clone()), aliases, parents)
                }
                Left::Derived(derived) => derived_text(derived, aliases, true),
                Left::Elapsed(elapsed) => elapsed_text(elapsed, aliases, true),
            };
            format!("{left} {}", phrase_text(&condition.phrase, aliases))
        }
        FromCondition::Quantified {
            quantifier,
            path,
            if_any,
            phrase,
        } => format!(
            "{} {}{} {}",
            quantifier_text(*quantifier),
            left_of_whose(path, aliases, parents, false),
            if_any_text(*if_any),
            phrase_text(phrase, aliases)
        ),
    }
}

/// Prints a `from` line as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// ```
/// use ergo_sentences::{parse_from, print_from};
///
/// let line = parse_from("every  items whose x is 1").unwrap();
/// assert_eq!(print_from(&line, &[]), "every items whose x is 1");
/// ```
pub fn print_from(line: &From, aliases: &[&str]) -> String {
    print_from_with(line, aliases, &[])
}

/// Prints a `from` line for a child subject.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// `parents` holds the names of a child subject's parents. On the left of a `whose`, a key named like a parent reads the item's own field, so it prints with a dot.
pub fn print_from_with(line: &From, aliases: &[&str], parents: &[&str]) -> String {
    let mut out = String::new();
    if line.every {
        out.push_str("every ");
    }
    out.push_str(&path_text(&line.path, Side::Left, aliases, false));
    if let Some(each) = &line.named_by_each_of {
        out.push_str(" named by each of ");
        out.push_str(&path_text(each, Side::Right, aliases, false));
    }
    if !line.whose.is_empty() {
        out.push_str(" whose ");
        let parts: Vec<String> = line
            .whose
            .iter()
            .map(|c| from_condition_text(c, aliases, parents, false, true))
            .collect();
        out.push_str(&parts.join(" and "));
    }
    out
}

fn quantifier_text(quantifier: Quantifier) -> &'static str {
    match quantifier {
        Quantifier::Every => "every",
        Quantifier::Some => "some",
    }
}

fn if_any_text(if_any: bool) -> &'static str {
    if if_any { ", if any," } else { "" }
}

pub(crate) fn key_text(key: &str) -> String {
    if is_bare_key(key) {
        key.to_string()
    } else {
        json_string(key)
    }
}

pub(crate) fn json_string(text: &str) -> String {
    let mut out = String::from("\"");
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out.push('"');
    out
}

fn string_text(text: &str) -> String {
    let single = text.contains('\\')
        && !text.contains('\'')
        && !text.contains("\\\\")
        && !text.ends_with('\\')
        && !text.chars().any(|ch| (ch as u32) < 0x20);
    if single {
        format!("'{text}'")
    } else {
        json_string(text)
    }
}

fn zeros(count: i64) -> String {
    "0".repeat(usize::try_from(count).unwrap_or(0))
}

pub(crate) fn number_text(text: &str) -> String {
    let (negative, rest) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    let (mantissa, exponent) = match rest.find(['e', 'E']) {
        Some(k) => (&rest[..k], &rest[k + 1..]),
        None => (rest, ""),
    };
    let (whole_digits, fraction_digits) = match mantissa.find('.') {
        Some(k) => (&mantissa[..k], &mantissa[k + 1..]),
        None => (mantissa, ""),
    };
    let exponent: i64 = if exponent.is_empty() {
        0
    } else {
        match exponent.trim_start_matches('+').parse() {
            Ok(value) if (-1_000_000..=1_000_000).contains(&value) => value,
            _ => return text.to_string(),
        }
    };
    let digits = format!("{whole_digits}{fraction_digits}");
    let point = whole_digits.len() as i64 + exponent;
    let left = (1 - point).max(0);
    let padded = format!(
        "{}{}{}",
        zeros(left),
        digits,
        zeros(point - digits.len() as i64)
    );
    let split = (point + left) as usize;
    let whole = padded[..split].trim_start_matches('0');
    let fraction = padded[split..].trim_end_matches('0');
    let body = match (whole.is_empty(), fraction.is_empty()) {
        (true, true) => "0".to_string(),
        (false, true) => whole.to_string(),
        (true, false) => format!("0.{fraction}"),
        (false, false) => format!("{whole}.{fraction}"),
    };
    if negative && body != "0" {
        format!("-{body}")
    } else {
        body
    }
}

pub(crate) fn increment(digits: &str) -> String {
    let mut bytes: Vec<u8> = digits.bytes().collect();
    let mut k = bytes.len();
    while k > 0 {
        k -= 1;
        if bytes[k] == b'9' {
            bytes[k] = b'0';
        } else {
            bytes[k] += 1;
            return String::from_utf8(bytes).unwrap_or_default();
        }
    }
    format!("1{}", String::from_utf8(bytes).unwrap_or_default())
}

fn value_text(value: &Value) -> String {
    match value {
        Value::String(text) => string_text(text),
        Value::Number(number) => number_text(number),
        Value::True => "true".to_string(),
        Value::False => "false".to_string(),
        Value::Null => "null".to_string(),
    }
}

fn reference_text(reference: &Reference) -> String {
    match reference {
        Reference::Params(key) => format!("$params.{}", key_text(key)),
        Reference::Input(key) => format!("$input.{}", key_text(key)),
        Reference::Name(name) => name.clone(),
    }
}

fn position_text(position: &Position) -> String {
    match position {
        Position::First => "first of ".to_string(),
        Position::Last => "last of ".to_string(),
        Position::Item { number, from_last } => {
            format!(
                "item {number}{} of ",
                if *from_last { " from last" } else { "" }
            )
        }
    }
}

fn step_text(step: &Step) -> String {
    match step {
        Step::Key(key) | Step::BracketKey(key) => format!(".{}", key_text(key)),
        Step::NamedBy(reference) | Step::Brackets(reference) => {
            format!(" named by {}", reference_text(reference))
        }
        Step::Index(number) => format!("[{number}]"),
    }
}

fn path_text(path: &Path, side: Side, aliases: &[&str], own: bool) -> String {
    path_text_with(path, side, aliases, own, true)
}

fn path_text_with(path: &Path, side: Side, aliases: &[&str], own: bool, lift: bool) -> String {
    let lifted = match (&path.position, &path.start, path.steps.last()) {
        (None, start, Some(Step::Index(number)))
            if lift && *start != Start::It && !above_list_position(number) =>
        {
            Some(Position::Item {
                number: increment(number),
                from_last: false,
            })
        }
        _ => None,
    };
    let (position, steps) = match &lifted {
        Some(position) => (Some(position), &path.steps[..path.steps.len() - 1]),
        None => (path.position.as_ref(), &path.steps[..]),
    };
    let mut out = String::new();
    if let Some(position) = position {
        out.push_str(&position_text(position));
    }
    match &path.start {
        Start::It => out.push_str("it"),
        Start::Params => out.push_str("$params"),
        Start::Input => out.push_str("$input"),
        Start::Field { key, dot } => {
            let dotted = is_word(key)
                || (matches!(side, Side::Right) && !is_bare_key(key))
                || (*dot && !own && aliases.contains(&key.as_str()));
            if dotted {
                out.push('.');
            }
            out.push_str(&key_text(key));
        }
    }
    for step in steps {
        out.push_str(&step_text(step));
    }
    out
}

fn derived_text(derived: &Derived, aliases: &[&str], own: bool) -> String {
    let word = match derived.kind {
        DerivedKind::Count => "count of",
        DerivedKind::Sum => "sum of",
    };
    format!(
        "{word} {}{}",
        path_text(&derived.path, Side::Left, aliases, own),
        whose_text(&derived.whose, aliases)
    )
}

fn whose_text(whose: &[Condition], aliases: &[&str]) -> String {
    if whose.is_empty() {
        return String::new();
    }
    let parts: Vec<String> = whose.iter().map(|c| condition_text(c, aliases)).collect();
    format!(" whose {}", parts.join(" and "))
}

fn elapsed_text(elapsed: &Elapsed, aliases: &[&str], own: bool) -> String {
    let unit = match elapsed.unit {
        Unit::Seconds => "seconds",
        Unit::Minutes => "minutes",
        Unit::Hours => "hours",
        Unit::Days => "days",
        Unit::Weeks => "weeks",
    };
    format!(
        "{unit} elapsed from {} to {}",
        path_text(&elapsed.from, Side::Left, aliases, own),
        path_text(&elapsed.to, Side::Left, aliases, own)
    )
}

fn term_text(term: &Term, aliases: &[&str], own: bool) -> String {
    match term {
        Term::Path(path) => path_text(path, Side::Right, aliases, false),
        Term::Number(number) => number_text(number),
        Term::Derived(derived) => derived_text(derived, aliases, own),
        Term::Elapsed(elapsed) => elapsed_text(elapsed, aliases, own),
    }
}

fn terms_text(terms: &[Term], aliases: &[&str]) -> String {
    let parts: Vec<String> = terms.iter().map(|t| term_text(t, aliases, false)).collect();
    parts.join(" plus ")
}

fn operand_text(operand: &Operand, aliases: &[&str]) -> String {
    match operand {
        Operand::Value(value) => value_text(value),
        Operand::Field(terms) => terms_text(terms, aliases),
    }
}

fn list_text(list: &List, aliases: &[&str]) -> String {
    match list {
        List::Values(values) => {
            let parts: Vec<String> = values.iter().map(value_text).collect();
            parts.join(", ")
        }
        List::Path(path) => path_text(path, Side::Right, aliases, true),
    }
}

fn condition_text(condition: &Condition, aliases: &[&str]) -> String {
    let left = match &condition.left {
        Left::Path(path) => path_text(path, Side::Left, aliases, true),
        Left::Derived(derived) => derived_text(derived, aliases, true),
        Left::Elapsed(elapsed) => elapsed_text(elapsed, aliases, true),
    };
    format!("{left} {}", phrase_text(&condition.phrase, aliases))
}

fn phrase_text(phrase: &Phrase, aliases: &[&str]) -> String {
    let operand =
        |words: &str, operand: &Operand| format!("{words} {}", operand_text(operand, aliases));
    let list = |words: &str, list: &List| format!("{words} {}", list_text(list, aliases));
    match phrase {
        Phrase::Is {
            not,
            operand: o,
            within,
        } => {
            let field = matches!(o, Operand::Field(_));
            let words = match (*not, field) {
                (false, false) => "is",
                (false, true) => "equals",
                (true, false) => "is not",
                (true, true) => "does not equal",
            };
            match within {
                Some(within) => format!(
                    "{words} {} within {}",
                    operand_text(o, aliases),
                    number_text(within)
                ),
                None => operand(words, o),
            }
        }
        Phrase::Order { order, operand: o } => {
            let words = match order {
                Order::AtLeast => "is at least",
                Order::AtMost => "is at most",
                Order::MoreThan => "is more than",
                Order::LessThan => "is less than",
            };
            operand(words, o)
        }
        Phrase::Between { min, max } => {
            format!("is between {} and {}", number_text(min), number_text(max))
        }
        Phrase::OneOf { not, list: l } => {
            let path = matches!(l, List::Path(_));
            let words = match (*not, path) {
                (false, false) => "is one of",
                (false, true) => "is in",
                (true, false) => "is not one of",
                (true, true) => "is not in",
            };
            list(words, l)
        }
        Phrase::Exists { not } => if *not { "does not exist" } else { "exists" }.to_string(),
        Phrase::Empty { not } => if *not { "is not empty" } else { "is empty" }.to_string(),
        Phrase::NonEmptyString => "is a non-empty string".to_string(),
        Phrase::Type(kind) => match kind {
            Type::List => "is a list",
            Type::String => "is a string",
            Type::Number => "is a number",
            Type::Boolean => "is a boolean",
            Type::Object => "is an object",
        }
        .to_string(),
        Phrase::Contains { not, operand: o } => {
            operand(if *not { "does not contain" } else { "contains" }, o)
        }
        Phrase::ContainsAll(l) => list("contains all of", l),
        Phrase::ContainsNone(l) => list("contains none of", l),
        Phrase::Matches { not, list: l } => {
            list(if *not { "does not match" } else { "matches" }, l)
        }
        Phrase::StartsWith(o) => operand("starts with", o),
        Phrase::EndsWith(o) => operand("ends with", o),
        Phrase::Alphabetically { after, operand: o } => operand(
            if *after {
                "is alphabetically after"
            } else {
                "is alphabetically before"
            },
            o,
        ),
        Phrase::Time { time, operand: o } => {
            let words = match time {
                TimeOrder::Before => "is before",
                TimeOrder::After => "is after",
                TimeOrder::OnOrAfter => "is on or after",
                TimeOrder::OnOrBefore => "is on or before",
            };
            operand(words, o)
        }
    }
}

/// Prints one assertion of a check as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
pub fn print_assertion(assertion: &Assertion, aliases: &[&str]) -> String {
    match assertion {
        Assertion::Plain { path, phrase } => format!(
            "{} {}",
            path_text(path, Side::Left, aliases, false),
            phrase_text(phrase, aliases)
        ),
        Assertion::Quantified {
            quantifier,
            path,
            whose,
            if_any,
            phrase,
        } => format!(
            "{} {}{}{} {}",
            quantifier_text(*quantifier),
            path_text(path, Side::Left, aliases, false),
            whose_text(whose, aliases),
            if_any_text(*if_any),
            phrase_text(phrase, aliases)
        ),
        Assertion::Derived { terms, phrase } => format!(
            "{} {}",
            terms_text(terms, aliases),
            phrase_text(phrase, aliases)
        ),
    }
}

/// Prints a check as a canonical sentence: one space between words, `is` before a value and numbers in plain decimal form.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// ```
/// use ergo_sentences::{parse_check, print_check};
///
/// let check = parse_check("approvals   is at least 2").unwrap();
/// assert_eq!(print_check(&check, &[]), "approvals is at least 2");
/// ```
pub fn print_check(check: &Check, aliases: &[&str]) -> String {
    let parts: Vec<String> = check
        .assertions
        .iter()
        .map(|a| print_assertion(a, aliases))
        .collect();
    parts.join(" and ")
}

fn for_item_text(item: &ForItem, names: &[&str], sorted_names: &[&str]) -> String {
    match item {
        ForItem::Walk {
            quantifier,
            path,
            whose,
            if_any,
            alias,
        } => format!(
            "{} {}{}{} as {alias}",
            quantifier_text(*quantifier),
            path_text(path, Side::Left, names, false),
            whose_text(whose, names),
            if_any_text(*if_any)
        ),
        ForItem::Pick {
            position,
            path,
            whose,
            sorted_by,
            alias,
        } => {
            let mut placed = path.clone();
            placed.position = Some(position.clone());
            let sorted = match sorted_by {
                Some(sorted) => format!(
                    " sorted by {}{}",
                    path_text_with(&sorted.path, Side::Left, sorted_names, false, false),
                    if sorted.alphabetically {
                        " alphabetically"
                    } else {
                        ""
                    }
                ),
                None => String::new(),
            };
            format!(
                "{}{}{sorted} as {alias}",
                path_text(&placed, Side::Left, names, false),
                whose_text(whose, names)
            )
        }
    }
}

fn alias_of(item: &ForItem) -> &str {
    match item {
        ForItem::Walk { alias, .. } | ForItem::Pick { alias, .. } => alias,
    }
}

/// Prints one item of a `for` line as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
pub fn print_for_item(item: &ForItem, aliases: &[&str]) -> String {
    for_item_text(item, aliases, aliases)
}

/// Prints a `for` line as a canonical sentence.
///
/// `aliases` holds the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot.
///
/// ```
/// use ergo_sentences::{parse_for, print_for};
///
/// let line = parse_for("every  xs as x").unwrap();
/// assert_eq!(print_for(&line, &[]), "every xs as x");
/// ```
pub fn print_for(line: &For, aliases: &[&str]) -> String {
    let all: Vec<&str> = aliases
        .iter()
        .copied()
        .chain(line.items.iter().map(alias_of))
        .collect();
    let parts: Vec<String> = line
        .items
        .iter()
        .enumerate()
        .map(|(n, item)| {
            let earlier: Vec<&str> = aliases
                .iter()
                .copied()
                .chain(line.items[..n].iter().map(alias_of))
                .collect();
            for_item_text(item, &earlier, &all)
        })
        .collect();
    parts.join(", ")
}
