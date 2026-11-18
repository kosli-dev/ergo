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

fn item(
    name: String,
    cause: Cause,
    inputs: Vec<Value>,
    failures: Vec<Failure>,
    message: String,
    of: &Value,
) -> Failure {
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
    Some(item(
        text(f, "item"),
        cause_of(l),
        inputs,
        inner,
        message,
        f,
    ))
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
            root: ctx.subject.location.root,
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
                        item(
                            text(x, "item"),
                            cause_of(x),
                            whose_reads(last, x, ctx),
                            Vec::new(),
                            said,
                            x,
                        )
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
    let bare = |f: &Value| {
        text(f, "cause") == "not_an_object"
            && !f.get("value").is_some_and(Value::is_object)
            && !list(f, "failed_assertions").is_empty()
    };
    let mut item_made: Vec<String> = Vec::new();
    for f in failed {
        for piece in text(f, "ergo/text").split("; ") {
            if piece.starts_with("item ") || !text(f, "item").starts_with("item ") {
                ops::push_new(&mut item_made, piece.to_string());
            }
        }
    }
    let whose_roots = line.whose_roots(ctx);
    let list_names: Vec<String> = line
        .items
        .iter()
        .map(|i| crate::name::name(&i.path))
        .collect();
    let mut texts_once: Vec<&str> = Vec::new();
    for s in &line.sentences {
        if !texts_once.contains(&s.text.as_str()) {
            texts_once.push(&s.text);
        }
    }
    let frees: Vec<Option<(Cause, String, Vec<Value>)>> = line
        .sentences
        .iter()
        .map(|sentence| {
            let free = !line
                .items
                .iter()
                .any(|it| for_line::reads_alias(&sentence.check, &it.alias));
            if !free {
                return None;
            }
            let ran = ops::run_full(&sentence.check, ctx);
            if ran.verdict.passed() {
                return None;
            }
            let said = match ran.message {
                Some(text) if matches!(sentence.check, Check::Walk(_)) => text,
                _ => ops::message::message(&sentence.check, ctx, &ran.verdict),
            };
            let sides = ops::message::side_names(&sentence.check);
            let inputs = ran
                .verdict
                .inputs
                .iter()
                .map(|input| crate::parts::with_outcome(input, &said, &sides))
                .collect();
            Some((ran.verdict.cause, said, inputs))
        })
        .collect();
    let free_said: Vec<String> = frees
        .iter()
        .flatten()
        .flat_map(|(_, said, _)| said.split("; ").map(str::to_string).collect::<Vec<_>>())
        .collect();
    let off_subject = row_cause == Cause::NotAnObject && !ctx.subject.value.is_object();
    let owns: Vec<Vec<String>> = (0..line.sentences.len())
        .map(|i| {
            if off_subject {
                Vec::new()
            } else {
                line.sentence_roots(i, ctx)
            }
        })
        .collect();
    let mut owned: Vec<Vec<String>> = vec![Vec::new(); line.sentences.len()];
    let mut walk_texts: Vec<String> = Vec::new();
    let first_key = line.first_key(ctx);
    let key_said: Vec<&str> = first_key
        .iter()
        .flat_map(|k| {
            std::iter::once(k.key_text.as_str()).chain(k.base.iter().map(|(t, _, _)| t.as_str()))
        })
        .collect();
    for clause in message.split("; ") {
        if clause.is_empty()
            || key_said.contains(&clause)
            || ops::message::cap_note(clause).is_some()
            || item_made.iter().any(|t| t == clause)
            || free_said.iter().any(|t| t == clause)
        {
            continue;
        }
        if let Some(i) = owns.iter().position(|o| o.iter().any(|t| t == clause)) {
            ops::push_new(&mut owned[i], clause.to_string());
        } else if off_subject
            || whose_roots.iter().any(|t| t == clause)
            || list_names.iter().any(|n| {
                clause.starts_with(&format!("{n} "))
                    || n.match_indices('.')
                        .any(|(at, _)| clause.starts_with(&format!("{} ", &n[..at])))
            })
            || texts_once.len() != 1
        {
            ops::push_new(&mut walk_texts, clause.to_string());
        } else {
            ops::push_new(&mut owned[0], clause.to_string());
        }
    }
    let roots: Vec<String> = message
        .split("; ")
        .filter(|m| !m.is_empty() && !item_made.iter().any(|t| t == m))
        .map(str::to_string)
        .collect();
    let mut out: Vec<Failure> = Vec::new();
    for (i, sentence) in line.sentences.iter().enumerate() {
        let first = line
            .sentences
            .iter()
            .position(|s| s.text == sentence.text)
            .unwrap_or(i);
        if first != i {
            continue;
        }
        let mut causes: Vec<Cause> = Vec::new();
        let mut inputs: Vec<Value> = Vec::new();
        let mut items: Vec<Failure> = Vec::new();
        let mut moved: Vec<String> = Vec::new();
        for f in failed.iter().filter(|f| !bare(f)) {
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
                if frees[i].is_none()
                    && let Some(entry) = line_item(f, &l, &aliases, &roots, &mut moved)
                {
                    items.push(entry);
                }
            }
        }
        let said = match &frees[i] {
            Some((cause, said, free_inputs)) => {
                if causes.is_empty() {
                    causes.push(*cause);
                    for x in free_inputs {
                        ops::push_new(&mut inputs, x.clone());
                    }
                }
                said.clone()
            }
            None => {
                let mut own: Vec<String> = Vec::new();
                for clause in message.split("; ") {
                    if owned[i].iter().any(|o| o == clause) || moved.iter().any(|m| m == clause) {
                        ops::push_new(&mut own, clause.to_string());
                    }
                }
                for m in moved {
                    ops::push_new(&mut own, m);
                }
                own.join("; ")
            }
        };
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
    let mut lists: Vec<Failure> = Vec::new();
    let mut rest: Vec<Failure> = Vec::new();
    for f in failed
        .iter()
        .filter(|f| list(f, "failed_assertions").is_empty() || bare(f))
    {
        let said = text(f, "ergo/text");
        if !said.is_empty()
            && list(f, "failed_items").is_empty()
            && said.split("; ").all(|p| whose_roots.iter().any(|t| t == p))
        {
            for p in said.split("; ") {
                ops::push_new(&mut walk_texts, p.to_string());
            }
            continue;
        }
        if let Some(entry) = dead_entry(line, f, ctx) {
            match entry {
                Failure::List(_) => lists.push(entry),
                _ => rest.push(entry),
            }
        }
    }
    if !walk_texts.is_empty() {
        let label = list_label(line, &walk_texts[0]);
        lists.insert(
            0,
            Failure::List(Part {
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
                message: walk_texts.join("; "),
            }),
        );
    }
    if let Some((text, cause, input)) = first_key.and_then(|k| k.base) {
        lists.insert(
            0,
            Failure::List(Part {
                name: input.name.clone(),
                cause,
                inputs: vec![crate::parts::with_outcome(&input, &text, &[])],
                failures: Vec::new(),
                message: text,
            }),
        );
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
