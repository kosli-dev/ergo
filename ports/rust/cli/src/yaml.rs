//! Reads YAML the way OPA 1.20.2 does: YAML 1.1 words and numbers, `<<` merge keys, the last of a repeated key, and only the first document.

use crate::number::number;
use saphyr_parser::{Event, Parser, ScalarStyle, Tag};
use serde_json::{Map, Value};
use std::collections::HashMap;

type Events<'a> = Parser<'a, saphyr_parser::StrInput<'a>>;
type Anchors = HashMap<usize, Value>;

/// Reads the first document of `text` as a JSON value. An empty file is `null`. It fails on a syntax error, on `.inf` and `.nan`, on a tag it doesn't know, on a key that isn't a scalar or is `null`, and on an alias with no anchor.
pub fn parse(text: &str) -> Result<Value, String> {
    let mut events = Parser::new_from_str(text).keep_tags(true);
    let mut anchors = Anchors::new();
    loop {
        match next(&mut events)? {
            Event::StreamStart | Event::Nothing => {}
            Event::StreamEnd => return Ok(Value::Null),
            Event::DocumentStart(_) => {
                let first = next(&mut events)?;
                return node(first, &mut events, &mut anchors);
            }
            _ => return Err("unexpected content".to_string()),
        }
    }
}

fn next<'a>(events: &mut Events<'a>) -> Result<Event<'a>, String> {
    match events.next_event() {
        Some(Ok((event, _))) => Ok(event),
        Some(Err(e)) => Err(e.to_string()),
        None => Err("unexpected end of the file".to_string()),
    }
}

fn node<'a>(
    first: Event<'a>,
    events: &mut Events<'a>,
    anchors: &mut Anchors,
) -> Result<Value, String> {
    match first {
        Event::Scalar(text, style, anchor, tag) => {
            let value = scalar(&text, style, tag.as_deref())?;
            remember(anchors, anchor, &value);
            Ok(value)
        }
        Event::Alias(id) => anchors
            .get(&id)
            .cloned()
            .ok_or_else(|| "an alias has no anchor".to_string()),
        Event::SequenceStart(anchor, _) => {
            let mut items = Vec::new();
            loop {
                match next(events)? {
                    Event::SequenceEnd => break,
                    event => items.push(node(event, events, anchors)?),
                }
            }
            let value = Value::Array(items);
            remember(anchors, anchor, &value);
            Ok(value)
        }
        Event::MappingStart(anchor, _) => {
            let value = mapping(events, anchors)?;
            remember(anchors, anchor, &value);
            Ok(value)
        }
        _ => Err("unexpected content".to_string()),
    }
}

fn remember(anchors: &mut Anchors, anchor: usize, value: &Value) {
    if anchor != 0 {
        anchors.insert(anchor, value.clone());
    }
}

fn mapping<'a>(events: &mut Events<'a>, anchors: &mut Anchors) -> Result<Value, String> {
    let mut explicit = Map::new();
    let mut merged = Map::new();
    loop {
        let first = match next(events)? {
            Event::MappingEnd => break,
            event => event,
        };
        let is_merge = matches!(
            &first,
            Event::Scalar(text, ScalarStyle::Plain, _, None) if text == "<<"
        );
        if is_merge {
            let source = next(events)?;
            merge(&mut merged, node(source, events, anchors)?)?;
            continue;
        }
        let key = key(node(first, events, anchors)?)?;
        let source = next(events)?;
        explicit.insert(key, node(source, events, anchors)?);
    }
    merged.extend(explicit);
    Ok(Value::Object(merged))
}

fn merge(into: &mut Map<String, Value>, source: Value) -> Result<(), String> {
    match source {
        Value::Object(map) => {
            for (k, v) in map {
                into.entry(k).or_insert(v);
            }
            Ok(())
        }
        Value::Array(items) if items.iter().all(Value::is_object) => {
            for item in items {
                merge(into, item)?;
            }
            Ok(())
        }
        _ => Err("a merge key needs a mapping or a list of mappings".to_string()),
    }
}

fn key(value: Value) -> Result<String, String> {
    match value {
        Value::String(s) => Ok(s),
        Value::Bool(b) => Ok(b.to_string()),
        Value::Number(n) => Ok(n.to_string()),
        Value::Null => Err("a key can't be null".to_string()),
        _ => Err("a key must be a scalar".to_string()),
    }
}

fn scalar(text: &str, style: ScalarStyle, tag: Option<&Tag>) -> Result<Value, String> {
    if let Some(tag) = tag {
        let core = tag.handle == "!!" || tag.handle == "tag:yaml.org,2002:";
        return match (core, tag.suffix.as_str()) {
            (true, "str") => Ok(Value::String(text.to_string())),
            (true, "int" | "float" | "bool" | "null") => resolve(text),
            _ => Err(format!(
                "the tag {}{} isn't supported",
                tag.handle, tag.suffix
            )),
        };
    }
    if style == ScalarStyle::Plain {
        resolve(text)
    } else {
        Ok(Value::String(text.to_string()))
    }
}

fn resolve(text: &str) -> Result<Value, String> {
    match text {
        "" | "~" | "null" | "Null" | "NULL" => Ok(Value::Null),
        "y" | "Y" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" | "true" | "True" | "TRUE" => {
            Ok(Value::Bool(true))
        }
        "n" | "N" | "no" | "No" | "NO" | "off" | "Off" | "OFF" | "false" | "False" | "FALSE" => {
            Ok(Value::Bool(false))
        }
        ".nan" | ".NaN" | ".NAN" | ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF"
        | "-.inf" | "-.Inf" | "-.INF" => Err(format!("{text} can't be written in JSON")),
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
