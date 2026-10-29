//! Reads YAML the way OPA 1.20.2 does: YAML 1.1 words and numbers, `<<` merge keys, the last of a repeated key, and only the first document.

use crate::number::number;
use saphyr_parser::{Event, Parser, ScalarStyle, Tag};
use serde_json::{Map, Value};
use std::collections::HashMap;

type Events<'a> = Parser<'a, saphyr_parser::StrInput<'a>>;

/// Why a YAML file can't be read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// The text isn't valid YAML.
    Invalid(String),
    /// The YAML is valid, but JSON can't hold one of its values or keys.
    NotJson(String),
    /// The YAML is valid, but OPA refuses it, so `ergo` does too.
    Refused(String),
}

fn invalid(message: impl Into<String>) -> Error {
    Error::Invalid(message.into())
}

const MAX_DEPTH: usize = 10_000;

/// Reads the first document of `text` as a JSON value. An empty file is `null`. It fails on a syntax error, on `.inf` and `.nan`, on a tag it doesn't know, on a key that isn't a scalar or is `null`, on an alias with no anchor, on more than 10,000 levels of nesting, on more aliases than OPA reads, on control characters, and on a `%YAML` version other than 1.1.
pub fn parse(text: &str) -> Result<Value, Error> {
    characters(text)?;
    version(text)?;
    let text = text.replace('\u{85}', "\n");
    let mut events = Parser::new_from_str(&text).keep_tags(true);
    loop {
        match next(&mut events)? {
            Event::StreamStart | Event::Nothing => {}
            Event::StreamEnd => return Ok(Value::Null),
            Event::DocumentStart(_) => return Reader::default().document(&mut events),
            _ => return Err(invalid("unexpected content")),
        }
    }
}

fn characters(text: &str) -> Result<(), Error> {
    let allowed = |c: char| matches!(c, '\t' | '\n' | '\r' | ' '..='~' | '\u{85}' | '\u{a0}'..='\u{d7ff}' | '\u{e000}'..='\u{fffd}' | '\u{10000}'..);
    match text.char_indices().find(|(_, c)| !allowed(*c)) {
        None => Ok(()),
        Some((at, c)) => Err(invalid(format!(
            "line {} holds the control character U+{:04X}, which YAML doesn't allow",
            text[..at].matches('\n').count() + 1,
            c as u32
        ))),
    }
}

fn version(text: &str) -> Result<(), Error> {
    for line in text.trim_start_matches('\u{feff}').lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let Some(directive) = line.strip_prefix('%') else {
            return Ok(());
        };
        let mut words = directive.split_whitespace();
        if words.next() == Some("YAML") {
            let version = words.next().unwrap_or("");
            if version != "1.1" {
                return Err(Error::Refused(format!(
                    "it says %YAML {version}, and only YAML 1.1 is read"
                )));
            }
        }
    }
    Ok(())
}

fn next<'a>(events: &mut Events<'a>) -> Result<Event<'a>, Error> {
    match events.next_event() {
        Some(Ok((event, _))) => Ok(event),
        Some(Err(e)) => Err(invalid(e.to_string())),
        None => Err(invalid("unexpected end of the file")),
    }
}

struct Node {
    value: Result<Value, Error>,
    key: Result<String, Error>,
    size: u64,
    alias: bool,
}

struct Anchor {
    value: Result<Value, Error>,
    key: Result<String, Error>,
    size: u64,
}

enum Slot {
    Key,
    Value(String),
    Merge,
}

enum Collection {
    List(Vec<Value>),
    Map(Map<String, Value>, Slot),
}

struct Frame {
    collection: Collection,
    anchor: usize,
    size: u64,
}

#[derive(Default)]
struct Reader {
    anchors: HashMap<usize, Anchor>,
    frames: Vec<Frame>,
    decoded: u64,
    aliased: u64,
}

impl Reader {
    fn document<'a>(mut self, events: &mut Events<'a>) -> Result<Value, Error> {
        self.decoded = 1;
        loop {
            let node = match next(events)? {
                Event::Scalar(text, style, anchor, tag) => {
                    if self.expects_key()
                        && style == ScalarStyle::Plain
                        && tag.is_none()
                        && text == "<<"
                    {
                        self.expect(Slot::Merge);
                        continue;
                    }
                    self.decoded += 1;
                    let scalar = scalar(&text, style, tag.as_deref())?;
                    let node = Node {
                        value: scalar.value(&text),
                        key: scalar.key(&text),
                        size: 1,
                        alias: false,
                    };
                    self.remember(anchor, &node);
                    node
                }
                Event::Alias(id) => {
                    let anchor = self
                        .anchors
                        .get(&id)
                        .ok_or_else(|| invalid("an alias has no anchor"))?;
                    self.decoded += 1 + anchor.size;
                    self.aliased += anchor.size;
                    if excessive(self.decoded, self.aliased) {
                        return Err(Error::Refused("it uses too many aliases".to_string()));
                    }
                    Node {
                        value: anchor.value.clone(),
                        key: anchor.key.clone(),
                        size: 1 + anchor.size,
                        alias: true,
                    }
                }
                Event::SequenceStart(anchor, _) => {
                    self.open(Collection::List(Vec::new()), anchor)?;
                    continue;
                }
                Event::MappingStart(anchor, _) => {
                    self.open(Collection::Map(Map::new(), Slot::Key), anchor)?;
                    continue;
                }
                Event::SequenceEnd | Event::MappingEnd => {
                    let frame = self
                        .frames
                        .pop()
                        .ok_or_else(|| invalid("unexpected content"))?;
                    let value = match frame.collection {
                        Collection::List(items) => Value::Array(items),
                        Collection::Map(map, _) => Value::Object(map),
                    };
                    let node = Node {
                        value: Ok(value),
                        key: Err(Error::NotJson("a key is a list or a mapping".to_string())),
                        size: frame.size,
                        alias: false,
                    };
                    self.remember(frame.anchor, &node);
                    node
                }
                _ => return Err(invalid("unexpected content")),
            };
            match self.frames.last_mut() {
                None => return node.value,
                Some(frame) => {
                    frame.size += node.size;
                    place(&mut frame.collection, node)?;
                }
            }
        }
    }

    fn expects_key(&self) -> bool {
        matches!(
            self.frames.last(),
            Some(Frame {
                collection: Collection::Map(_, Slot::Key),
                ..
            })
        )
    }

    fn expect(&mut self, next: Slot) {
        if let Some(Frame {
            collection: Collection::Map(_, slot),
            ..
        }) = self.frames.last_mut()
        {
            *slot = next;
        }
    }

    fn open(&mut self, collection: Collection, anchor: usize) -> Result<(), Error> {
        if self.frames.len() == MAX_DEPTH {
            return Err(Error::Refused(
                "it nests more than 10,000 levels".to_string(),
            ));
        }
        self.decoded += 1;
        self.frames.push(Frame {
            collection,
            anchor,
            size: 1,
        });
        Ok(())
    }

    fn remember(&mut self, anchor: usize, node: &Node) {
        if anchor != 0 {
            let remembered = Anchor {
                value: node.value.clone(),
                key: node.key.clone(),
                size: node.size,
            };
            self.anchors.insert(anchor, remembered);
        }
    }
}

fn excessive(decoded: u64, aliased: u64) -> bool {
    let allowed = match decoded {
        ..=400_000 => 0.99,
        4_000_000.. => 0.10,
        _ => 0.99 - 0.89 * (decoded - 400_000) as f64 / 3_600_000.0,
    };
    aliased > 100 && decoded > 1000 && aliased as f64 / decoded as f64 > allowed
}

fn place(collection: &mut Collection, node: Node) -> Result<(), Error> {
    match collection {
        Collection::List(items) => items.push(node.value?),
        Collection::Map(map, slot) => match std::mem::replace(slot, Slot::Key) {
            Slot::Key => *slot = Slot::Value(node.key?),
            Slot::Value(name) => {
                map.insert(name, node.value?);
            }
            Slot::Merge => merge(map, node.value?, node.alias)?,
        },
    }
    Ok(())
}

fn merge(into: &mut Map<String, Value>, source: Value, alias: bool) -> Result<(), Error> {
    match source {
        Value::Object(map) => {
            for (k, v) in map {
                into.insert(k, v);
            }
            Ok(())
        }
        Value::Array(_) if alias => Err(Error::Refused(
            "a merge key takes an alias to a list, and only an alias to a mapping is merged"
                .to_string(),
        )),
        Value::Array(items) if items.iter().all(Value::is_object) => {
            for item in items.into_iter().rev() {
                merge(into, item, false)?;
            }
            Ok(())
        }
        _ => Err(invalid("a merge key needs a mapping or a list of mappings")),
    }
}

enum Scalar {
    Null,
    Bool(bool),
    Int(String),
    Uint(String),
    Float(String),
    Special(&'static str),
    Str(String),
}

impl Scalar {
    fn value(&self, text: &str) -> Result<Value, Error> {
        match self {
            Scalar::Null => Ok(Value::Null),
            Scalar::Bool(b) => Ok(Value::Bool(*b)),
            Scalar::Int(digits) | Scalar::Uint(digits) | Scalar::Float(digits) => {
                Ok(number(digits))
            }
            Scalar::Special(_) => Err(Error::NotJson(format!("{text} isn't a JSON number"))),
            Scalar::Str(s) => Ok(Value::String(s.clone())),
        }
    }

    fn key(&self, text: &str) -> Result<String, Error> {
        match self {
            Scalar::Null => Err(Error::NotJson("a key is null".to_string())),
            Scalar::Bool(b) => Ok(b.to_string()),
            Scalar::Int(digits) => Ok(digits.clone()),
            Scalar::Uint(_) => Err(Error::Refused(format!(
                "the key {text} is past the largest 64-bit signed integer"
            ))),
            Scalar::Float(digits) => Ok(match digits.parse::<f64>() {
                Ok(f) if f.is_finite() => shortest(f as f32),
                _ => text.to_string(),
            }),
            Scalar::Special(name) => Ok(name.to_string()),
            Scalar::Str(s) => Ok(s.clone()),
        }
    }
}

fn shortest(f: f32) -> String {
    if f.is_infinite() {
        return if f > 0.0 { ".inf" } else { "-.inf" }.to_string();
    }
    let scientific = format!("{f:e}");
    let (mantissa, exponent) = scientific.split_once('e').unwrap_or((&scientific, "0"));
    let exponent: i32 = exponent.parse().unwrap_or(0);
    let (sign, mantissa) = match mantissa.strip_prefix('-') {
        Some(m) => ("-", m),
        None => ("", mantissa),
    };
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    if !(-4..6).contains(&exponent) {
        let fraction = if digits.len() > 1 {
            format!(".{}", &digits[1..])
        } else {
            String::new()
        };
        let exponent_sign = if exponent < 0 { '-' } else { '+' };
        return format!(
            "{sign}{}{fraction}e{exponent_sign}{:02}",
            &digits[..1],
            exponent.abs()
        );
    }
    let point = exponent + 1;
    if point <= 0 {
        return format!(
            "{sign}0.{}{digits}",
            "0".repeat(point.unsigned_abs() as usize)
        );
    }
    let point = point as usize;
    if digits.len() <= point {
        format!("{sign}{digits}{}", "0".repeat(point - digits.len()))
    } else {
        format!("{sign}{}.{}", &digits[..point], &digits[point..])
    }
}

fn scalar(text: &str, style: ScalarStyle, tag: Option<&Tag>) -> Result<Scalar, Error> {
    let Some(tag) = tag else {
        return Ok(if style == ScalarStyle::Plain {
            resolve(text)
        } else {
            Scalar::Str(text.to_string())
        });
    };
    let core = tag.handle == "!!" || tag.handle == "tag:yaml.org,2002:";
    let resolved = resolve(text);
    let (fits, kind) = match (core, tag.suffix.as_str()) {
        (true, "str") => return Ok(Scalar::Str(text.to_string())),
        (true, "binary") => return base64(text).map(Scalar::Str),
        (true, "timestamp") if timestamp(text) => return Ok(Scalar::Str(text.to_string())),
        (true, "timestamp") => (None, "a date or a time"),
        (true, "int") => (
            matches!(resolved, Scalar::Int(_) | Scalar::Uint(_)).then_some(resolved),
            "an integer",
        ),
        (true, "float") => (
            match resolved {
                Scalar::Int(digits) => Some(Scalar::Float(digits)),
                Scalar::Float(_) | Scalar::Special(_) => Some(resolved),
                _ => None,
            },
            "a number",
        ),
        (true, "bool") => (
            matches!(resolved, Scalar::Bool(_)).then_some(resolved),
            "true or false",
        ),
        (true, "null") => (matches!(resolved, Scalar::Null).then_some(resolved), "null"),
        _ => {
            return Err(invalid(format!(
                "the tag {}{} isn't supported",
                tag.handle, tag.suffix
            )));
        }
    };
    fits.ok_or_else(|| invalid(format!("!!{} `{text}` isn't {kind}", tag.suffix)))
}

fn resolve(text: &str) -> Scalar {
    match text {
        "" | "~" | "null" | "Null" | "NULL" => Scalar::Null,
        "y" | "Y" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" | "true" | "True" | "TRUE" => {
            Scalar::Bool(true)
        }
        "n" | "N" | "no" | "No" | "NO" | "off" | "Off" | "OFF" | "false" | "False" | "FALSE" => {
            Scalar::Bool(false)
        }
        ".nan" | ".NaN" | ".NAN" => Scalar::Special(".nan"),
        ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" => Scalar::Special(".inf"),
        "-.inf" | "-.Inf" | "-.INF" => Scalar::Special("-.inf"),
        _ => numeric(text).unwrap_or_else(|| Scalar::Str(text.to_string())),
    }
}

fn numeric(text: &str) -> Option<Scalar> {
    if !text.starts_with(|c: char| matches!(c, '+' | '-' | '.' | '0'..='9')) {
        return None;
    }
    if text.starts_with('.') && !underscores_between_digits(text) {
        return None;
    }
    let plain: String = text.chars().filter(|c| *c != '_').collect();
    let (negative, body) = match plain.as_bytes().first() {
        Some(b'-') => (true, &plain[1..]),
        Some(b'+') => (false, &plain[1..]),
        _ => (false, plain.as_str()),
    };
    if let Some(scalar) = integer(negative, body) {
        return scalar;
    }
    float(negative, body).map(Scalar::Float)
}

fn underscores_between_digits(text: &str) -> bool {
    let bytes = text.as_bytes();
    bytes.iter().enumerate().all(|(i, b)| {
        *b != b'_'
            || (i > 0
                && bytes[i - 1].is_ascii_digit()
                && bytes.get(i + 1).is_some_and(u8::is_ascii_digit))
    })
}

fn integer(negative: bool, body: &str) -> Option<Option<Scalar>> {
    let (radix, digits, prefixed) = match body.get(..2) {
        Some("0x" | "0X") => (16, &body[2..], true),
        Some("0b" | "0B") => (2, &body[2..], true),
        Some("0o" | "0O") => (8, &body[2..], true),
        _ if body.len() > 1
            && body.bytes().all(|b| (b'0'..=b'7').contains(&b))
            && body.starts_with('0') =>
        {
            (8, &body[1..], false)
        }
        _ if !body.is_empty()
            && body.bytes().all(|b| b.is_ascii_digit())
            && (body == "0" || !body.starts_with('0')) =>
        {
            (10, body, false)
        }
        _ => return None,
    };
    let magnitude = if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        None
    } else {
        u128::from_str_radix(digits, radix).ok()
    };
    let largest = if negative {
        1 << 63
    } else {
        u128::from(u64::MAX)
    };
    match magnitude {
        Some(m) if m <= largest => {
            let sign = if negative && m != 0 { "-" } else { "" };
            let digits = format!("{sign}{m}");
            Some(Some(if m > i64::MAX as u128 && !negative {
                Scalar::Uint(digits)
            } else {
                Scalar::Int(digits)
            }))
        }
        _ if prefixed => Some(None),
        _ => None,
    }
}

fn timestamp(text: &str) -> bool {
    let b = text.as_bytes();
    let mut i = 0;
    let Some(year) = number_at(b, &mut i, 4, 4) else {
        return false;
    };
    let Some(month) = after(b, &mut i, b'-', 2) else {
        return false;
    };
    let Some(day) = after(b, &mut i, b'-', 2) else {
        return false;
    };
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = match month {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        1..=12 => 31,
        _ => return false,
    };
    if day < 1 || day > days {
        return false;
    }
    if i == b.len() {
        return true;
    }
    let zoned = match b[i] {
        b'T' | b't' => true,
        b' ' => false,
        _ => return false,
    };
    i += 1;
    let Some(hour) = number_at(b, &mut i, 1, 2) else {
        return false;
    };
    let (Some(minute), Some(second)) = (after(b, &mut i, b':', 2), after(b, &mut i, b':', 2))
    else {
        return false;
    };
    if hour > 23 || minute > 59 || second > 59 {
        return false;
    }
    if matches!(b.get(i), Some(b'.' | b',')) && b.get(i + 1).is_some_and(u8::is_ascii_digit) {
        i += 1;
        while b.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
        }
    }
    if !zoned {
        return i == b.len();
    }
    match &b[i..] {
        [b'Z'] => true,
        [b'+' | b'-', h1, h2, b':', m1, m2] => {
            let two = |a: u8, b: u8| {
                (a.is_ascii_digit() && b.is_ascii_digit())
                    .then(|| u32::from(a - b'0') * 10 + u32::from(b - b'0'))
            };
            matches!((two(*h1, *h2), two(*m1, *m2)), (Some(h), Some(m)) if h <= 24 && m <= 60)
        }
        _ => false,
    }
}

fn after(b: &[u8], i: &mut usize, separator: u8, most: usize) -> Option<u32> {
    if b.get(*i) != Some(&separator) {
        return None;
    }
    *i += 1;
    number_at(b, i, 1, most)
}

fn number_at(b: &[u8], i: &mut usize, least: usize, most: usize) -> Option<u32> {
    let start = *i;
    while *i - start < most && b.get(*i).is_some_and(u8::is_ascii_digit) {
        *i += 1;
    }
    if *i - start < least {
        return None;
    }
    std::str::from_utf8(&b[start..*i]).ok()?.parse().ok()
}

fn float(negative: bool, body: &str) -> Option<String> {
    let bytes = body.as_bytes();
    let mut i = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
    }
    let whole = &body[..i];
    let mut fraction = "";
    if bytes.get(i) == Some(&b'.') {
        let start = i + 1;
        i = start;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            i += 1;
        }
        fraction = &body[start..i];
    }
    if whole.is_empty() && fraction.is_empty() {
        return None;
    }
    let mut exponent = "";
    if matches!(bytes.get(i), Some(b'e' | b'E')) {
        let start = i;
        i += 1;
        if matches!(bytes.get(i), Some(b'+' | b'-')) {
            i += 1;
        }
        let digits = i;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            i += 1;
        }
        if i == digits {
            return None;
        }
        exponent = &body[start..i];
    }
    if i != bytes.len() {
        return None;
    }
    let whole = whole.trim_start_matches('0');
    let mut out = String::new();
    if negative {
        out.push('-');
    }
    out.push_str(if whole.is_empty() { "0" } else { whole });
    if !fraction.is_empty() {
        out.push('.');
        out.push_str(fraction);
    }
    out.push_str(exponent);
    Some(out)
}

fn base64(text: &str) -> Result<String, Error> {
    let mut bytes = Vec::new();
    let mut bits: u32 = 0;
    let mut count = 0;
    let mut padding = 0;
    for c in text.chars().filter(|c| !matches!(c, '\r' | '\n')) {
        let digit = match c {
            'A'..='Z' => c as u32 - 'A' as u32,
            'a'..='z' => c as u32 - 'a' as u32 + 26,
            '0'..='9' => c as u32 - '0' as u32 + 52,
            '+' => 62,
            '/' => 63,
            '=' => {
                padding += 1;
                continue;
            }
            _ => return Err(invalid("!!binary isn't base64")),
        };
        if padding > 0 {
            return Err(invalid("!!binary isn't base64"));
        }
        bits = bits << 6 | digit;
        count += 1;
        if count == 4 {
            bytes.extend([(bits >> 16) as u8, (bits >> 8) as u8, bits as u8]);
            bits = 0;
            count = 0;
        }
    }
    match (count, padding) {
        (0, 0) => {}
        (2, 2) => bytes.push((bits >> 4) as u8),
        (3, 1) => bytes.extend([(bits >> 10) as u8, (bits >> 2) as u8]),
        _ => return Err(invalid("!!binary isn't base64")),
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}
