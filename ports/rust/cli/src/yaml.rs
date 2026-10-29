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

/// Reads the first document of `text` as a JSON value. An empty file is `null`. It fails on a syntax error, on `.inf` and `.nan`, on a tag it doesn't know, on a key that isn't a scalar or is `null`, on an alias with no anchor, on more than 10,000 levels of nesting, and on more aliases than OPA reads.
pub fn parse(text: &str) -> Result<Value, Error> {
    let mut events = Parser::new_from_str(text).keep_tags(true);
    loop {
        match next(&mut events)? {
            Event::StreamStart | Event::Nothing => {}
            Event::StreamEnd => return Ok(Value::Null),
            Event::DocumentStart(_) => return Reader::default().document(&mut events),
            _ => return Err(invalid("unexpected content")),
        }
    }
}

fn next<'a>(events: &mut Events<'a>) -> Result<Event<'a>, Error> {
    match events.next_event() {
        Some(Ok((event, _))) => Ok(event),
        Some(Err(e)) => Err(invalid(e.to_string())),
        None => Err(invalid("unexpected end of the file")),
    }
}

struct Anchor {
    value: Value,
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
            let (value, size) = match next(events)? {
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
                    let value = scalar(&text, style, tag.as_deref())?;
                    self.remember(anchor, &value, 1);
                    (value, 1)
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
                    (anchor.value.clone(), 1 + anchor.size)
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
                    self.remember(frame.anchor, &value, frame.size);
                    (value, frame.size)
                }
                _ => return Err(invalid("unexpected content")),
            };
            match self.frames.last_mut() {
                None => return Ok(value),
                Some(frame) => {
                    frame.size += size;
                    place(&mut frame.collection, value)?;
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

    fn remember(&mut self, anchor: usize, value: &Value, size: u64) {
        if anchor != 0 {
            let value = value.clone();
            self.anchors.insert(anchor, Anchor { value, size });
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

fn place(collection: &mut Collection, value: Value) -> Result<(), Error> {
    match collection {
        Collection::List(items) => items.push(value),
        Collection::Map(map, slot) => match std::mem::replace(slot, Slot::Key) {
            Slot::Key => *slot = Slot::Value(key(value)?),
            Slot::Value(name) => {
                map.insert(name, value);
            }
            Slot::Merge => merge(map, value)?,
        },
    }
    Ok(())
}

fn merge(into: &mut Map<String, Value>, source: Value) -> Result<(), Error> {
    match source {
        Value::Object(map) => {
            for (k, v) in map {
                into.insert(k, v);
            }
            Ok(())
        }
        Value::Array(items) if items.iter().all(Value::is_object) => {
            for item in items.into_iter().rev() {
                merge(into, item)?;
            }
            Ok(())
        }
        _ => Err(invalid("a merge key needs a mapping or a list of mappings")),
    }
}

fn key(value: Value) -> Result<String, Error> {
    match value {
        Value::String(s) => Ok(s),
        Value::Bool(b) => Ok(b.to_string()),
        Value::Number(n) => Ok(n.to_string()),
        Value::Null => Err(Error::NotJson("a key is null".to_string())),
        _ => Err(Error::NotJson("a key is a list or a mapping".to_string())),
    }
}

fn scalar(text: &str, style: ScalarStyle, tag: Option<&Tag>) -> Result<Value, Error> {
    if let Some(tag) = tag {
        let core = tag.handle == "!!" || tag.handle == "tag:yaml.org,2002:";
        return match (core, tag.suffix.as_str()) {
            (true, "str") => Ok(Value::String(text.to_string())),
            (true, "int" | "float" | "bool" | "null") => resolve(text),
            (true, "timestamp") => Ok(Value::String(text.to_string())),
            (true, "binary") => base64(text).map(Value::String),
            _ => Err(invalid(format!(
                "the tag {}{} isn't supported",
                tag.handle, tag.suffix
            ))),
        };
    }
    if style == ScalarStyle::Plain {
        resolve(text)
    } else {
        Ok(Value::String(text.to_string()))
    }
}

fn resolve(text: &str) -> Result<Value, Error> {
    match text {
        "" | "~" | "null" | "Null" | "NULL" => Ok(Value::Null),
        "y" | "Y" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" | "true" | "True" | "TRUE" => {
            Ok(Value::Bool(true))
        }
        "n" | "N" | "no" | "No" | "NO" | "off" | "Off" | "OFF" | "false" | "False" | "FALSE" => {
            Ok(Value::Bool(false))
        }
        ".nan" | ".NaN" | ".NAN" | ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF"
        | "-.inf" | "-.Inf" | "-.INF" => Err(Error::NotJson(format!("{text} isn't a JSON number"))),
        _ => Ok(numeric(text).unwrap_or_else(|| Value::String(text.to_string()))),
    }
}

fn numeric(text: &str) -> Option<Value> {
    if !text.starts_with(|c: char| matches!(c, '+' | '-' | '.' | '0'..='9')) {
        return None;
    }
    let plain: String = text.chars().filter(|c| *c != '_').collect();
    let (negative, body) = match plain.as_bytes().first() {
        Some(b'-') => (true, &plain[1..]),
        Some(b'+') => (false, &plain[1..]),
        _ => (false, plain.as_str()),
    };
    if let Some(value) = integer(negative, body) {
        return value;
    }
    float(negative, body).map(|t| number(&t))
}

fn integer(negative: bool, body: &str) -> Option<Option<Value>> {
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
        _ => return None,
    };
    let magnitude = if digits.is_empty() || !digits.chars().all(|c| c.is_digit(radix)) {
        None
    } else {
        u128::from_str_radix(digits, radix).ok()
    };
    match magnitude {
        Some(m)
            if m <= if negative {
                1 << 63
            } else {
                u128::from(u64::MAX)
            } =>
        {
            let sign = if negative && m != 0 { "-" } else { "" };
            Some(Some(number(&format!("{sign}{m}"))))
        }
        _ if prefixed => Some(None),
        _ => None,
    }
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
