use crate::cause::Cause;
use crate::ops::Input;
use crate::path::Outcome;
use serde_json::{Map, Value, json};

/// What every entry of a failed row's `failures` holds.
#[derive(Debug, Clone, PartialEq)]
pub struct Part {
    pub name: String,
    pub cause: Cause,
    pub inputs: Vec<Value>,
    pub failures: Vec<Failure>,
    pub message: String,
}

/// One entry of a failed row's `failures`: an option, an assertion, an item
/// of a walked list, or a list that failed while walking.
#[derive(Debug, Clone, PartialEq)]
pub enum Failure {
    Option {
        part: Part,
        locations: Vec<String>,
    },
    Assertion {
        part: Part,
        locations: Vec<String>,
    },
    Item {
        part: Part,
        value: Value,
        locations: Vec<String>,
    },
    List(Part),
}

impl Failure {
    pub fn part(&self) -> &Part {
        match self {
            Failure::Option { part, .. }
            | Failure::Assertion { part, .. }
            | Failure::Item { part, .. }
            | Failure::List(part) => part,
        }
    }

    pub fn to_json(&self) -> Value {
        let (kind, part, value, locations) = match self {
            Failure::Option { part, locations } => ("option", part, None, Some(locations)),
            Failure::Assertion { part, locations } => ("assertion", part, None, Some(locations)),
            Failure::Item {
                part,
                value,
                locations,
            } => ("item", part, Some(value), Some(locations)),
            Failure::List(part) => ("list", part, None, None),
        };
        let mut entry = Map::new();
        entry.insert("kind".to_string(), json!(kind));
        entry.insert("name".to_string(), json!(part.name));
        entry.insert("cause".to_string(), json!(part.cause.name()));
        entry.insert("inputs".to_string(), Value::Array(part.inputs.clone()));
        entry.insert(
            "failures".to_string(),
            Value::Array(part.failures.iter().map(Failure::to_json).collect()),
        );
        entry.insert(
            "message".to_string(),
            json!(crate::ops::message::one_line(&part.message)),
        );
        if let Some(value) = value {
            entry.insert("value".to_string(), value.clone());
        }
        if let Some(locations) = locations {
            entry.insert("locations".to_string(), json!(locations));
        }
        Value::Object(entry)
    }
}

/// Turns a list of entries into the JSON list a row's `failures` holds.
pub fn to_json(failures: &[Failure]) -> Value {
    Value::Array(failures.iter().map(Failure::to_json).collect())
}

/// The word an input's `outcome` says, or `None` for an input that doesn't
/// read a path. `message` is what the check says, which names an input whose
/// value the check can't use, and `sides` names the values the check uses.
pub fn outcome(input: &Input, message: &str, sides: &[String]) -> Option<&'static str> {
    if input.worked {
        return None;
    }
    match input.state {
        Outcome::Found if input.value.is_null() => None,
        Outcome::Found
            if (sides.contains(&input.name) || walked_root(&input.name))
                && unfit(&input.name, &input.value, message) =>
        {
            Some("unusable")
        }
        Outcome::Found => Some("usable"),
        Outcome::Null => Some("null"),
        Outcome::Absent => Some("absent"),
        Outcome::Unusable => Some("unusable"),
        Outcome::NotAnObject => Some("not_an_object"),
    }
}

fn walked_root(name: &str) -> bool {
    (name.starts_with("$params.") || name.starts_with("$input.")) && name.contains("[]")
}

fn unfit(name: &str, value: &Value, message: &str) -> bool {
    let said = format!("{}, which ", crate::ops::message::is(name, value));
    if message.contains(&said) {
        return true;
    }
    match name.split_once("[]") {
        Some((list, _)) => {
            message.contains(&format!(" of {list} is ")) && message.contains(", which ")
                || message.contains(&format!("{list} are of more than one"))
        }
        None => false,
    }
}

/// An input as a failed row shows it, with its `outcome`.
pub fn with_outcome(input: &Input, message: &str, sides: &[String]) -> Value {
    let mut entry = input.to_json();
    if let (Some(word), Some(map)) = (outcome(input, message, sides), entry.as_object_mut()) {
        map.insert("outcome".to_string(), json!(word));
    }
    entry
}

/// Whether `rich` is the failed item `plain` with its text and item added.
pub fn same_failed(rich: &Value, plain: &Value) -> bool {
    ["path", "item", "cause", "value", "locations"]
        .iter()
        .all(|key| rich.get(key) == plain.get(key))
}

fn text_of(failed: &Value, key: &str) -> String {
    failed
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn is_item(name: &str) -> bool {
    name.starts_with("item ")
}

/// The list an item or list entry belongs to: `xs` for `item 2 of xs` or `xs`.
pub fn list_base(name: &str) -> String {
    let unitemed = match name.strip_prefix("item ") {
        Some(_) => match name.split_once(" of ") {
            Some((_, rest)) => rest,
            None => name,
        },
        None => name,
    };
    match unitemed.split_once('[') {
        Some((base, _)) => base.to_string(),
        None => unitemed.to_string(),
    }
}

/// Whether the row input `name` reads inside one of the lists in `lists`.
pub fn item_input(name: &str, lists: &[String]) -> bool {
    match name.split_once("[]") {
        Some((base, _)) => lists.iter().any(|l| l == base),
        None => false,
    }
}

/// The name of an item read by its position: `xs[1]` for `item 2 of xs`.
pub fn position_name(item: &str) -> String {
    let Some(rest) = item.strip_prefix("item ") else {
        return item.to_string();
    };
    let Some((number, list)) = rest.split_once(" of ") else {
        return item.to_string();
    };
    let at = number.parse::<u64>().unwrap_or(1).saturating_sub(1);
    format!("{list}[{at}]")
}

fn entry_text(text: &str, name: &str) -> String {
    match text.strip_prefix(&format!("{name}: ")) {
        Some(rest) => rest.to_string(),
        None => text.to_string(),
    }
}

fn root_text(item: &str, text: &str) -> bool {
    !text.is_empty() && is_item(item) && !is_item(text)
}

fn item_outcome(cause: &str, value: &Value) -> &'static str {
    match cause {
        "absent" => "absent",
        "null" => "null",
        "unusable" => "unusable",
        "not_an_object" => "not_an_object",
        _ if !value.is_null() => "usable",
        _ => "null",
    }
}

fn item_read(failed: &Value) -> Value {
    let value = failed.get("value").cloned().unwrap_or(Value::Null);
    json!({
        "name": failed.get("path").cloned().unwrap_or(Value::Null),
        "value": value,
        "locations": failed.get("locations").cloned().unwrap_or(json!([])),
        "outcome": item_outcome(failed.get("cause").and_then(Value::as_str).unwrap_or(""), &value),
    })
}

/// What a walk's failed items give: the entries under its assertion, and the
/// texts that belong to the assertion itself because they're about a root
/// read outside the items.
pub struct Walked {
    pub entries: Vec<Failure>,
    pub roots: Vec<String>,
    pub texts: Vec<String>,
}

/// Builds the item and list entries of a walk from its failed items.
pub fn walk_entries(failed_items: &[Value]) -> Walked {
    let texts: Vec<String> = failed_items
        .iter()
        .map(|f| text_of(f, "ergo/text"))
        .collect();
    let items: Vec<String> = failed_items.iter().map(|f| text_of(f, "item")).collect();
    let roots: Vec<String> = items
        .iter()
        .zip(&texts)
        .filter(|(item, text)| root_text(item, text))
        .map(|(_, text)| text.clone())
        .collect();
    let owned: Vec<String> = items
        .iter()
        .zip(&texts)
        .map(|(item, text)| {
            if roots.is_empty() || !root_text(item, text) {
                text.clone()
            } else {
                String::new()
            }
        })
        .collect();
    let mut entries = Vec::new();
    let mut done: Vec<&str> = Vec::new();
    for (k, name) in items.iter().enumerate() {
        if done.contains(&name.as_str()) {
            continue;
        }
        done.push(name);
        let same: Vec<usize> = (0..items.len()).filter(|j| &items[*j] == name).collect();
        if same.iter().all(|j| owned[*j].is_empty()) {
            continue;
        }
        let causes = same.iter().filter_map(|j| {
            Cause::from_name(
                failed_items[*j]
                    .get("cause")
                    .and_then(Value::as_str)
                    .unwrap_or(""),
            )
        });
        let cause = Cause::worst(causes).unwrap_or(Cause::Value);
        let inputs: Vec<Value> = same
            .iter()
            .map(|j| {
                let mut read = item_read(&failed_items[*j]);
                if text_of(&failed_items[*j], "path") == *name && is_item(name) {
                    read["name"] = json!(position_name(name));
                }
                read
            })
            .collect();
        let mut said: Vec<String> = Vec::new();
        for j in &same {
            if !owned[*j].is_empty() {
                crate::ops::push_new(&mut said, entry_text(&owned[*j], name));
            }
        }
        let part = Part {
            name: name.clone(),
            cause,
            inputs,
            failures: Vec::new(),
            message: said.join("; "),
        };
        let first = &failed_items[k];
        entries.push(if is_item(name) {
            let seen = first
                .get("ergo/item")
                .filter(|s| s.is_object())
                .unwrap_or(first);
            Failure::Item {
                part,
                value: seen.get("value").cloned().unwrap_or(Value::Null),
                locations: seen
                    .get("locations")
                    .and_then(Value::as_array)
                    .map(|l| {
                        l.iter()
                            .filter_map(|x| x.as_str().map(str::to_string))
                            .collect()
                    })
                    .unwrap_or_default(),
            }
        } else {
            Failure::List(part)
        });
    }
    Walked {
        entries,
        roots,
        texts,
    }
}

struct Level {
    name: String,
    value: Value,
    locations: Vec<String>,
}

struct Leveled {
    entry: Failure,
    levels: Vec<Level>,
}

fn level_field(field: &str) -> String {
    if field.is_empty() {
        "it".to_string()
    } else {
        field.to_string()
    }
}

fn level_bits(path: &str) -> Option<(Vec<u64>, Vec<String>)> {
    let pieces: Vec<&str> = path.split('[').collect();
    let mut idx = Vec::new();
    let mut fields = vec![pieces[0].to_string()];
    for piece in &pieces[1..] {
        let (number, rest) = piece.split_once(']')?;
        idx.push(number.parse::<u64>().ok()?);
        fields.push(rest.trim_start_matches('.').to_string());
    }
    Some((idx, fields))
}

fn levels_of(entry: Failure, input: &Value) -> Leveled {
    let name = entry.part().name.clone();
    let (lead, path) = match name
        .strip_prefix("item ")
        .and_then(|rest| rest.split_once(" of "))
    {
        Some((position, path)) => (Some(position.to_string()), path.to_string()),
        None => (None, name.clone()),
    };
    let Some((idx, fields)) = level_bits(&path).filter(|(idx, _)| !idx.is_empty() && idx.len() < 4)
    else {
        return Leveled {
            entry,
            levels: Vec::new(),
        };
    };
    let m = idx.len();
    let mut names: Vec<String> = (0..m)
        .map(|j| format!("item {} of {}", idx[j] + 1, level_field(&fields[j])))
        .collect();
    let leaf = match &lead {
        Some(position) => format!("item {position} of {}", level_field(&fields[m])),
        None => fields[m].clone(),
    };
    names.push(leaf.clone());
    let place = match &entry {
        Failure::Item { locations, .. } => locations.first().cloned(),
        _ => entry
            .part()
            .inputs
            .first()
            .and_then(|i| i.get("locations"))
            .and_then(|l| l.get(0))
            .and_then(Value::as_str)
            .map(str::to_string),
    };
    let tokens: Vec<String> = place
        .unwrap_or_default()
        .split('/')
        .map(str::to_string)
        .collect();
    let mut cut = tokens.len();
    if lead.is_some() {
        cut = cut.saturating_sub(1);
    }
    let stopped_short = matches!(&entry, Failure::List(part) if part.cause == Cause::Absent);
    let mut ends = vec![0usize; m];
    for j in (0..m).rev() {
        if !(stopped_short && j == m - 1) {
            cut = cut.saturating_sub(fields[j + 1].split('.').filter(|f| !f.is_empty()).count());
        }
        ends[j] = cut;
        cut = cut.saturating_sub(1);
    }
    let levels: Vec<Level> = (0..m)
        .map(|j| {
            let pointer = tokens[..ends[j].min(tokens.len())].join("/");
            Level {
                name: names[j].clone(),
                value: input.pointer(&pointer).cloned().unwrap_or(Value::Null),
                locations: vec![pointer],
            }
        })
        .collect();
    let said: Vec<String> = match entry {
        Failure::List(_) => names[..m].to_vec(),
        _ => names.clone(),
    };
    let text = entry.part().message.clone();
    let full = format!("{}: ", said.join(": "));
    let outer = format!("{}: ", said[..said.len() - 1].join(": "));
    let message = if let Some(rest) = text.strip_prefix(&full) {
        rest.to_string()
    } else if let Some(rest) = text.strip_prefix(&outer).filter(|_| said.len() > 1) {
        rest.to_string()
    } else {
        entry_text(&text, &leaf)
    };
    let mut entry = entry;
    match &mut entry {
        Failure::Item { part, .. }
        | Failure::List(part)
        | Failure::Option { part, .. }
        | Failure::Assertion { part, .. } => {
            part.name = leaf;
            part.message = message;
        }
    }
    Leveled { entry, levels }
}

fn nested(entries: Vec<Leveled>, depth: usize) -> Vec<Failure> {
    let key = |e: &Leveled| e.levels.get(depth).map(|l| l.name.clone());
    let mut out: Vec<Failure> = Vec::new();
    let mut groups: Vec<(String, Vec<Leveled>)> = Vec::new();
    let mut order: Vec<Option<usize>> = Vec::new();
    let mut leaves: Vec<Option<Failure>> = Vec::new();
    for e in entries {
        match key(&e) {
            Some(k) => match groups.iter().position(|(name, _)| *name == k) {
                Some(at) => groups[at].1.push(e),
                None => {
                    order.push(Some(groups.len()));
                    leaves.push(None);
                    groups.push((k, vec![e]));
                }
            },
            None => {
                order.push(None);
                leaves.push(Some(e.entry));
            }
        }
    }
    let mut groups: Vec<Option<(String, Vec<Leveled>)>> = groups.into_iter().map(Some).collect();
    for (slot, leaf) in order.into_iter().zip(leaves) {
        match (slot, leaf) {
            (None, Some(leaf)) => out.push(leaf),
            (Some(at), _) => {
                let (name, kids) = groups[at].take().expect("each group once");
                let level = &kids[0].levels[depth];
                let (value, locations) = (level.value.clone(), level.locations.clone());
                let kids = nested(kids, depth + 1);
                out.push(Failure::Item {
                    part: Part {
                        name,
                        cause: Cause::worst(kids.iter().map(|k| k.part().cause))
                            .unwrap_or(Cause::Value),
                        inputs: Vec::new(),
                        failures: kids,
                        message: String::new(),
                    },
                    value,
                    locations,
                });
            }
            _ => {}
        }
    }
    out
}

/// Puts entries of a list walked several levels deep under the items they
/// sit in, reading each outer item from `input`.
pub fn nest(entries: Vec<Failure>, input: &Value) -> Vec<Failure> {
    let leveled: Vec<Leveled> = entries.into_iter().map(|e| levels_of(e, input)).collect();
    if leveled.iter().all(|e| e.levels.is_empty()) {
        return leveled.into_iter().map(|e| e.entry).collect();
    }
    nested(leveled, 0)
}

/// Escapes one key of a JSON pointer.
pub fn escaped(key: &str) -> String {
    key.replace('~', "~0").replace('/', "~1")
}

/// Joins `keys` onto a `$policy:` pointer.
pub fn joined(base: &str, keys: &[&str]) -> String {
    let mut out = base.to_string();
    for key in keys {
        out.push('/');
        out.push_str(&escaped(key));
    }
    out
}

fn assertions_in(line: &str) -> usize {
    ergo_policy_sentences::parse_check(line)
        .map(|tree| tree.assertions.len())
        .unwrap_or(1)
        .max(1)
}

/// Where each of `count` assertions sits in the policy, for a check written
/// as `written`, or for its `any_of` option `option`.
pub fn assertion_locations(
    requirement: &str,
    check: &str,
    written: &Value,
    option: Option<&str>,
    count: usize,
) -> Vec<String> {
    let base = joined("$policy:", &["requirements", requirement, "checks", check]);
    let (at, lines) = match (option, written) {
        (None, Value::String(_)) => (base, None),
        (None, Value::Object(map)) => (
            joined(&base, &["assert"]),
            map.get("assert").and_then(Value::as_array),
        ),
        (Some(name), Value::Object(map)) => (
            joined(&base, &["any_of", name]),
            map.get("any_of")
                .and_then(|o| o.get(name))
                .and_then(Value::as_array),
        ),
        _ => (base, None),
    };
    match lines {
        None if count <= 1 => vec![at],
        None => (1..=count).map(|k| format!("{at}#{k}")).collect(),
        Some(lines) if lines.len() == count => {
            (0..count).map(|j| joined(&at, &[&j.to_string()])).collect()
        }
        Some(lines) => lines
            .iter()
            .enumerate()
            .flat_map(|(j, line)| {
                let n = line.as_str().map(assertions_in).unwrap_or(1);
                let place = joined(&at, &[&j.to_string()]);
                (1..=n).map(move |k| {
                    if n == 1 {
                        place.clone()
                    } else {
                        format!("{place}#{k}")
                    }
                })
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests;
