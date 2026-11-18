use crate::cause::Cause;
use crate::ops::for_line::{self, For};
use crate::ops::{self, Check};
use crate::parts::{Failure, Part};
use crate::path::{Ctx, Start};
use serde_json::{Value, json};

fn text(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn texts(value: &Value) -> Vec<String> {
    value
        .get("ergo/texts")
        .and_then(Value::as_array)
        .map(|list| {
            list.iter()
                .filter_map(|t| t.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

fn list(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn cause_of(value: &Value) -> Cause {
    Cause::from_name(&text(value, "cause")).unwrap_or(Cause::Value)
}

fn strings(value: &Value, key: &str) -> Vec<String> {
    list(value, key)
        .iter()
        .filter_map(|v| v.as_str().map(str::to_string))
        .collect()
}

fn alias_start(word: &str, alias: &str) -> bool {
    word == alias
        || word.starts_with(&format!("{alias}."))
        || word.starts_with(&format!("{alias}["))
}

/// Whether the input `name` reads through one of `aliases`.
pub fn alias_named(name: &str, aliases: &[&str]) -> bool {
    name.split(' ')
        .any(|word| aliases.iter().any(|alias| alias_start(word, alias)))
}

fn said_name(value: &Value) -> String {
    let said = text(value, "ergo/said");
    if said.is_empty() {
        text(value, "item")
    } else {
        said
    }
}

fn entry_text(text: &str, name: &str) -> String {
    match text.strip_prefix(&format!("{name}: ")) {
        Some(rest) => rest.to_string(),
        None => text.to_string(),
    }
}

fn item(name: String, cause: Cause, inputs: Vec<Value>, failures: Vec<Failure>, message: String, of: &Value) -> Failure {
    Failure::Item {
        part: Part {
            name,
            cause,
            inputs,
            failures,
            message,
        },
        value: of.get("value").cloned().unwrap_or(Value::Null),
        locations: strings(of, "locations"),
    }
}

fn without_roots(message: &str, roots: &[String], moved: &mut Vec<String>) -> String {
    message
        .split("; ")
        .map(|part| {
            part.split(", and ")
                .filter(|piece| {
                    if roots.iter().any(|r| r == piece) {
                        ops::push_new(moved, (*piece).to_string());
                        false
                    } else {
                        true
                    }
                })
                .collect::<Vec<_>>()
                .join(", and ")
        })
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("; ")
}

fn line_item(
    f: &Value,
    l: &Value,
    aliases: &[&str],
    roots: &[String],
    moved: &mut Vec<String>,
) -> Option<Failure> {
    let inner: Vec<Failure> = list(l, "items")
        .iter()
        .filter_map(|y| {
            let message =
                without_roots(&for_line::rendered(&said_name(y), &texts(y)), roots, moved);
            (!message.is_empty()).then(|| {
                item(
                    text(y, "item"),
                    cause_of(y),
                    list(y, "inputs"),
                    Vec::new(),
                    message,
                    y,
                )
            })
        })
        .collect();
    let message = if l.get("items").is_some() {
        String::new()
    } else {
        without_roots(&for_line::rendered(&said_name(f), &texts(l)), roots, moved)
    };
    if message.is_empty() && inner.is_empty() {
        return None;
    }
    let inputs = list(l, "inputs")
        .into_iter()
        .filter(|x| alias_named(&text(x, "name"), aliases))
        .collect();
    Some(item(text(f, "item"), cause_of(l), inputs, inner, message, f))
}

fn whose_reads(whose: &[Check], f: &Value, ctx: &Ctx) -> Vec<Value> {
    let Some(object) = f.get("value").filter(|v| v.is_object()) else {
        return Vec::new();
    };
    let base = parts_base(&text(f, "item"));
    let mut out = Vec::new();
    let place = strings(f, "locations").first().cloned().unwrap_or_default();
    let mut at = ctx.clone();
    at.subject = crate::path::Located {
        value: object,
        location: crate::path::Location {
            root: ctx.subject.location.root.clone(),
            pointer: place.clone(),
        },
    };
    at.label = None;
    for check in whose {
        let unusable = ops::run(check, &at).cause == Cause::Unusable;
        for path in check.paths() {
            if !matches!(path.start, Start::Subject | Start::Own) {
                continue;
            }
            let keys: Vec<String> = path
                .steps
                .iter()
                .map_while(|step| match step {
                    crate::path::Step::Key(key) => Some(key.clone()),
                    _ => None,
                })
                .collect();
            if keys.is_empty() || keys.len() != path.steps.len() {
                continue;
            }
            let mut at = Some(object);
            for key in &keys {
                at = at.and_then(|v| v.get(key));
            }
            let name = format!("{base}.{}", keys.join("."));
            let locations = strings(f, "locations");
            match at {
                None => out.push(json!({"name": name, "value": null, "locations": locations, "outcome": "absent"})),
                Some(Value::Null) => out.push(json!({"name": name, "value": null, "locations": locations, "outcome": "null"})),
                Some(value) if unusable => {
                    let pointer = keys.iter().fold(place.clone(), |acc, k| {
                        format!("{acc}/{}", crate::parts::escaped(k))
                    });
                    out.push(json!({"name": name, "value": value, "locations": [pointer], "outcome": "unusable"}))
                }
                _ => {}
            }
        }
    }
    out
}

fn parts_base(item: &str) -> String {
    let Some(rest) = item.strip_prefix("item ") else {
        return item.to_string();
    };
    let Some((number, list)) = rest.split_once(" of ") else {
        return item.to_string();
    };
    let at = number.parse::<u64>().unwrap_or(1).saturating_sub(1);
    format!("{list}[{at}]")
}

fn whose_of<'a>(line: &'a For, f: &Value) -> &'a [Check] {
    let base = crate::parts::list_base(&text(f, "item"));
    let names: Vec<String> = line
        .items
        .iter()
        .map(|i| crate::name::name(&i.path))
        .collect();
    if line.items.len() == 2 && names[1] == base && names[0] != base {
        &line.items[1].whose
    } else {
        &line.items[0].whose
    }
}

fn dead_entry(line: &For, f: &Value, ctx: &Ctx) -> Option<Failure> {
    let name = text(f, "item");
    let inner = list(f, "failed_items");
    if !inner.is_empty() {
        let last = &line.items[line.items.len() - 1].whose;
        let kids: Vec<Failure> = inner
            .iter()
            .filter_map(|x| {
                let said = entry_text(&text(x, "ergo/text"), &said_name(x));
                (!said.is_empty()).then(|| {
                    if text(x, "item").starts_with("item ") {
                        item(text(x, "item"), cause_of(x), whose_reads(last, x, ctx), Vec::new(), said, x)
                    } else {
                        Failure::List(Part {
                            name: text(x, "item"),
                            cause: cause_of(x),
                            inputs: vec![item_read(x)],
                            failures: Vec::new(),
                            message: said,
                        })
                    }
                })
            })
            .collect();
        return Some(item(name, cause_of(f), Vec::new(), kids, String::new(), f));
    }
    let said = text(f, "ergo/text");
    if said.is_empty() {
        return None;
    }
    if let Some(sorted) = f.get("ergo/sorted") {
        let input = json!({
            "name": format!("{}.{}", parts_base(&name), text(sorted, "key")),
            "value": f.get("value").cloned().unwrap_or(Value::Null),
            "locations": f.get("locations").cloned().unwrap_or(json!([])),
            "outcome": text(sorted, "outcome"),
        });
        return Some(Failure::Item {
            part: Part {
                name: name.clone(),
                cause: cause_of(f),
                inputs: vec![input],
                failures: Vec::new(),
                message: entry_text(&said, &said_name(f)),
            },
            value: sorted.get("value").cloned().unwrap_or(Value::Null),
            locations: vec![text(sorted, "at")],
        });
    }
    if name.starts_with("item ") {
        Some(item(
            name.clone(),
            cause_of(f),
            whose_reads(whose_of(line, f), f, ctx),
            Vec::new(),
            entry_text(&said, &said_name(f)),
            f,
        ))
    } else {
        Some(Failure::List(Part {
            name,
            cause: cause_of(f),
            inputs: vec![item_read(f)],
            failures: Vec::new(),
            message: said,
        }))
    }
}

fn item_read(f: &Value) -> Value {
    let value = f.get("value").cloned().unwrap_or(Value::Null);
    let outcome = match text(f, "cause").as_str() {
        c @ ("absent" | "null" | "unusable" | "not_an_object") => c.to_string(),
        _ if !value.is_null() => "usable".to_string(),
        _ => "null".to_string(),
    };
    json!({
        "name": f.get("path").cloned().unwrap_or(Value::Null),
        "value": value,
        "locations": f.get("locations").cloned().unwrap_or(json!([])),
        "outcome": outcome,
    })
}

/// The entries of a failed `for` row's `failures`.
pub fn for_failures(
    line: &For,
    row_cause: Cause,
    row_inputs: &[Value],
    message: &str,
    failed: &[Value],
    places: &[String],
    ctx: &Ctx,
) -> Vec<Failure> {
    let aliases: Vec<&str> = line.items.iter().map(|i| i.alias.as_str()).collect();
    let mut out: Vec<Failure> = Vec::new();
    let mut free_texts: Vec<String> = Vec::new();
    let roots: Vec<String> = message
        .split("; ")
        .filter(|m| !m.is_empty() && !m.starts_with("item "))
        .map(str::to_string)
        .collect();
    for (i, sentence) in line.sentences.iter().enumerate() {
        if line.sentences[..i].iter().any(|s| s.text == sentence.text) {
            continue;
        }
        let free = !line
            .items
            .iter()
            .any(|it| for_line::reads_alias(&sentence.check, &it.alias));
        let mut causes: Vec<Cause> = Vec::new();
        let mut inputs: Vec<Value> = Vec::new();
        let mut items: Vec<Failure> = Vec::new();
        let mut moved: Vec<String> = Vec::new();
        for f in failed {
            for l in list(f, "failed_assertions") {
                if text(&l, "assertion") != sentence.text {
                    continue;
                }
                causes.push(cause_of(&l));
                for x in list(&l, "inputs") {
                    if !alias_named(&text(&x, "name"), &aliases) {
                        ops::push_new(&mut inputs, x);
                    }
                }
                if !free && let Some(entry) = line_item(f, &l, &aliases, &roots, &mut moved) {
                    items.push(entry);
                }
            }
        }
        let mut said = String::new();
        if free {
            let ran = ops::run_full(&sentence.check, ctx);
            if !ran.verdict.passed() {
                said = match ran.message {
                    Some(text) if matches!(sentence.check, Check::Walk(_)) => text,
                    _ => ops::message::message(&sentence.check, ctx, &ran.verdict),
                };
                if causes.is_empty() {
                    causes.push(ran.verdict.cause);
                    let sides = ops::message::side_names(&sentence.check);
                    for input in &ran.verdict.inputs {
                        ops::push_new(&mut inputs, crate::parts::with_outcome(input, &said, &sides));
                    }
                }
                free_texts.extend(said.split("; ").map(str::to_string));
            }
        }
        if said.is_empty() {
            said = moved.join("; ");
            free_texts.extend(moved);
        }
        if said.is_empty() && items.is_empty() {
            continue;
        }
        out.push(Failure::Assertion {
            part: Part {
                name: sentence.text.clone(),
                cause: Cause::worst(causes).unwrap_or(row_cause),
                inputs,
                failures: items,
                message: said,
            },
            locations: places.get(i).cloned().into_iter().collect(),
        });
    }
    let mut breaks: Vec<Failure> = failed
        .iter()
        .filter(|f| list(f, "failed_assertions").is_empty())
        .filter_map(|f| dead_entry(line, f, ctx))
        .collect();
    if failed.is_empty() {
        let walk: Vec<&str> = message
            .split("; ")
            .filter(|m| !m.is_empty() && !m.starts_with("item ") && !free_texts.iter().any(|t| t == m))
            .collect();
        if !walk.is_empty() {
            let label = list_label(line, walk[0]);
            breaks.push(Failure::List(Part {
                name: label.clone(),
                cause: row_cause,
                inputs: row_inputs
                    .iter()
                    .filter(|i| {
                        let n = text(i, "name");
                        n == label || n == format!("{label}[]")
                    })
                    .cloned()
                    .collect(),
                failures: Vec::new(),
                message: walk.join("; "),
            }));
        }
    }
    let mut lists: Vec<Failure> = Vec::new();
    let mut rest: Vec<Failure> = Vec::new();
    for b in breaks {
        match b {
            Failure::List(_) => lists.push(b),
            _ => rest.push(b),
        }
    }
    out.extend(lists);
    out.extend(rest);
    out
}

fn list_label(line: &For, said: &str) -> String {
    if line.items.len() == 2 {
        let name = crate::name::name(&line.items[1].path);
        if said.starts_with(&format!("{name} ")) {
            return name;
        }
    }
    crate::name::name(&line.items[0].path)
}
