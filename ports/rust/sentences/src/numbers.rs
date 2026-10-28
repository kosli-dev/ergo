use std::cmp::Ordering;

pub(crate) struct Decimal {
    negative: bool,
    digits: String,
    magnitude: i64,
}

impl Decimal {
    pub(crate) fn read(text: &str) -> Option<Decimal> {
        let (negative, rest) = match text.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, text),
        };
        let (mantissa, exponent) = match rest.find(['e', 'E']) {
            Some(k) => (&rest[..k], &rest[k + 1..]),
            None => (rest, ""),
        };
        let (whole, fraction) = match mantissa.find('.') {
            Some(k) => (&mantissa[..k], &mantissa[k + 1..]),
            None => (mantissa, ""),
        };
        if whole.is_empty()
            || !whole
                .bytes()
                .chain(fraction.bytes())
                .all(|b| b.is_ascii_digit())
        {
            return None;
        }
        let exponent: i64 = if exponent.is_empty() {
            0
        } else {
            let unsigned = exponent.trim_start_matches(['+', '-']);
            let value: i64 = unsigned.parse().unwrap_or(1 << 50).min(1 << 50);
            if exponent.starts_with('-') {
                -value
            } else {
                value
            }
        };
        let all = format!("{whole}{fraction}");
        let leading = all.len() - all.trim_start_matches('0').len();
        let digits = all.trim_matches('0').to_string();
        Some(Decimal {
            negative,
            digits,
            magnitude: whole.len() as i64 + exponent - leading as i64,
        })
    }

    pub(crate) fn is_zero(&self) -> bool {
        self.digits.is_empty()
    }

    pub(crate) fn is_negative(&self) -> bool {
        self.negative && !self.is_zero()
    }

    fn compare_size(&self, other: &Decimal) -> Ordering {
        self.magnitude
            .cmp(&other.magnitude)
            .then_with(|| padded_compare(&self.digits, &other.digits))
    }

    pub(crate) fn compare(&self, other: &Decimal) -> Ordering {
        match (self.sign(), other.sign()) {
            (a, b) if a != b => a.cmp(&b),
            (0, _) => Ordering::Equal,
            (1, _) => self.compare_size(other),
            _ => other.compare_size(self),
        }
    }

    fn sign(&self) -> i8 {
        if self.is_zero() {
            0
        } else if self.negative {
            -1
        } else {
            1
        }
    }

    pub(crate) fn out_of_range(&self) -> bool {
        if self.is_zero() {
            return false;
        }
        let above = self.magnitude > 309
            || (self.magnitude == 309
                && padded_compare(&self.digits, "17976931348623157") == Ordering::Greater);
        let below = self.magnitude < -307
            || (self.magnitude == -307
                && padded_compare(&self.digits, "22250738585072014") == Ordering::Less);
        above || below
    }
}

fn padded_compare(a: &str, b: &str) -> Ordering {
    let width = a.len().max(b.len()).max(17);
    let pad = |s: &str| format!("{s:0<width$}");
    pad(a).cmp(&pad(b))
}

pub(crate) fn out_of_range(text: &str) -> bool {
    Decimal::read(text).is_some_and(|d| d.out_of_range())
}

pub(crate) fn above_list_position(digits: &str) -> bool {
    digits.len() > 16 || (digits.len() == 16 && digits > "9007199254740991")
}

fn digits_at(b: &[u8], from: usize, count: usize) -> Option<u32> {
    let slice = b.get(from..from + count)?;
    if !slice.iter().all(u8::is_ascii_digit) {
        return None;
    }
    std::str::from_utf8(slice).ok()?.parse().ok()
}

fn leap(year: u32) -> bool {
    (year.is_multiple_of(4) && !year.is_multiple_of(100)) || year.is_multiple_of(400)
}

fn real_date(b: &[u8]) -> bool {
    let (Some(year), Some(month), Some(day)) =
        (digits_at(b, 0, 4), digits_at(b, 5, 2), digits_at(b, 8, 2))
    else {
        return false;
    };
    if b[4] != b'-' || b[7] != b'-' || !(1678..=2261).contains(&year) || !(1..=12).contains(&month)
    {
        return false;
    }
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ if leap(year) => 29,
        _ => 28,
    };
    (1..=days).contains(&day)
}

pub(crate) fn written_time(text: &str) -> bool {
    let b = text.as_bytes();
    if b.len() == 10 {
        return real_date(b);
    }
    if b.len() < 20 || !real_date(&b[..10]) || b[10] != b'T' {
        return false;
    }
    let clock = digits_at(b, 11, 2).is_some_and(|h| h < 24)
        && b[13] == b':'
        && digits_at(b, 14, 2).is_some_and(|m| m < 60)
        && b[16] == b':'
        && digits_at(b, 17, 2).is_some_and(|s| s < 60);
    if !clock {
        return false;
    }
    let mut at = 19;
    if b[at] == b'.' {
        let start = at + 1;
        at = start;
        while b.get(at).is_some_and(u8::is_ascii_digit) {
            at += 1;
        }
        if at == start {
            return false;
        }
    }
    match &b[at..] {
        b"Z" => true,
        rest if rest.len() == 6 && (rest[0] == b'+' || rest[0] == b'-') => {
            digits_at(rest, 1, 2).is_some_and(|h| h < 24)
                && rest[3] == b':'
                && digits_at(rest, 4, 2).is_some_and(|m| m < 60)
        }
        _ => false,
    }
}

fn repeat_spec(chars: &[char], at: usize) -> Option<usize> {
    let mut i = at + 1;
    let first = i;
    while chars.get(i).is_some_and(char::is_ascii_digit) {
        i += 1;
    }
    if i == first {
        return None;
    }
    if chars.get(i) == Some(&',') {
        i += 1;
        while chars.get(i).is_some_and(char::is_ascii_digit) {
            i += 1;
        }
    }
    if chars.get(i) == Some(&'}') {
        Some(i + 1)
    } else {
        None
    }
}

fn ascii_class(letter: char, in_class: bool) -> Option<&'static str> {
    match letter {
        'd' => Some("[0-9]"),
        'D' => Some("[^0-9]"),
        'w' => Some("[0-9A-Za-z_]"),
        'W' => Some("[^0-9A-Za-z_]"),
        's' => Some("[\\t\\n\\x0C\\r ]"),
        'S' => Some("[^\\t\\n\\x0C\\r ]"),
        'b' if !in_class => Some("(?-u:\\b)"),
        'B' if !in_class => Some("(?-u:\\B)"),
        _ => None,
    }
}

fn prepare(pattern: &str) -> Option<String> {
    let chars: Vec<char> = pattern.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    let mut in_class = false;
    let mut class_start = 0;
    let mut repeated: Option<bool> = None;
    while i < chars.len() {
        let ch = chars[i];
        if ch == '\\' {
            repeated = None;
            let Some(&next) = chars.get(i + 1) else {
                out.push('\\');
                i += 1;
                continue;
            };
            if next == 'Q' {
                let mut literal = String::new();
                i += 2;
                while i < chars.len() {
                    if chars[i] == '\\' && chars.get(i + 1) == Some(&'E') {
                        i += 2;
                        break;
                    }
                    literal.push(chars[i]);
                    i += 1;
                }
                out.push_str(&regex_syntax::escape(&literal));
                continue;
            }
            match ascii_class(next, in_class) {
                Some(set) => out.push_str(set),
                None => {
                    out.push('\\');
                    out.push(next);
                }
            }
            i += 2;
            if "pPx".contains(next) && chars.get(i) == Some(&'{') {
                while i < chars.len() && chars[i - 1] != '}' {
                    out.push(chars[i]);
                    i += 1;
                }
                continue;
            }
            if "dDwWsS".contains(next)
                && chars.get(i) == Some(&'-')
                && chars.get(i + 1).is_some_and(|c| *c != ']')
            {
                out.push_str("\\-");
                i += 1;
            }
            continue;
        }
        if in_class {
            if ch == '[' && chars.get(i + 1) == Some(&':') {
                while i < chars.len() && !(chars[i] == ']' && chars[i - 1] == ':') {
                    out.push(chars[i]);
                    i += 1;
                }
                continue;
            }
            if ch == ']' && i > class_start {
                in_class = false;
            }
            out.push(ch);
            i += 1;
            continue;
        }
        match ch {
            '[' => {
                in_class = true;
                repeated = None;
                out.push(ch);
                i += 1;
                class_start = i;
                if chars.get(i) == Some(&'^') {
                    out.push('^');
                    i += 1;
                    class_start = i;
                }
                if chars.get(i) == Some(&']') {
                    out.push_str("\\]");
                    i += 1;
                }
            }
            '(' if chars.get(i + 1) == Some(&'?') => {
                repeated = None;
                let mut k = i + 2;
                while chars
                    .get(k)
                    .is_some_and(|c| c.is_ascii_alphabetic() || *c == '-')
                {
                    k += 1;
                }
                if k > i + 2
                    && matches!(chars.get(k), Some(')' | ':'))
                    && !chars[i + 2..k].iter().all(|c| "imsU-".contains(*c))
                {
                    return None;
                }
                out.push('(');
                i += 1;
            }
            '*' | '+' | '?' => {
                match repeated {
                    Some(false) if ch == '?' => repeated = Some(true),
                    Some(_) => return None,
                    None => repeated = Some(false),
                }
                out.push(ch);
                i += 1;
            }
            '{' => match repeat_spec(&chars, i) {
                Some(end) => {
                    if repeated.is_some() {
                        return None;
                    }
                    repeated = Some(false);
                    out.extend(&chars[i..end]);
                    i = end;
                }
                None => {
                    repeated = None;
                    out.push_str("\\{");
                    i += 1;
                }
            },
            _ => {
                repeated = None;
                out.push(ch);
                i += 1;
            }
        }
    }
    Some(out)
}

fn repeats_too_much(ast: &regex_syntax::ast::Ast, left: u32) -> bool {
    use regex_syntax::ast::{Ast, RepetitionKind, RepetitionRange};
    match ast {
        Ast::Repetition(r) => {
            let count = match &r.op.kind {
                RepetitionKind::Range(
                    RepetitionRange::Exactly(n) | RepetitionRange::AtLeast(n),
                ) => Some(*n),
                RepetitionKind::Range(RepetitionRange::Bounded(_, b)) => Some(*b),
                _ => None,
            };
            match count {
                Some(m) if m > left => true,
                Some(m) if m > 0 => repeats_too_much(&r.ast, left / m),
                _ => repeats_too_much(&r.ast, left),
            }
        }
        Ast::Group(g) => repeats_too_much(&g.ast, left),
        Ast::Concat(c) => c.asts.iter().any(|a| repeats_too_much(a, left)),
        Ast::Alternation(a) => a.asts.iter().any(|x| repeats_too_much(x, left)),
        _ => false,
    }
}

/// Gives a `matches` pattern as the `regex` crate should read it, or `None` when it is not valid.
///
/// Validity follows RE2, which `ergo.rego` uses. The result reads `\d`, `\w`, `\s` and `\b` as ASCII only, as RE2 does.
///
/// ```
/// use ergo_sentences::rust_pattern;
///
/// assert!(rust_pattern("^v[0-9]+$").is_some());
/// assert_eq!(rust_pattern("("), None);
/// ```
pub fn rust_pattern(pattern: &str) -> Option<String> {
    let text = prepare(pattern)?;
    let ast = regex_syntax::ast::parse::Parser::new().parse(&text).ok()?;
    if repeats_too_much(&ast, 1000) || regex_syntax::Parser::new().parse(&text).is_err() {
        return None;
    }
    Some(text)
}

pub(crate) fn valid_pattern(pattern: &str) -> bool {
    rust_pattern(pattern).is_some()
}
