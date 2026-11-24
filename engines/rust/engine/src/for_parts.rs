use crate::cause::Cause;
use crate::ops::clause::{self, Clause, Kind};
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

fn clauses(text: &str) -> Vec<&str> {
    ops::message::split_outside_quotes(text, "; ")
}

fn walked_under(
    line: &For,
    sentence: &Check,
    f: &Value,
    l: &Value,
    aliases: &[&str],
    ctx: &Ctx,
) -> Option<Failure> {
    let walks = match sentence {
        Check::Walk(_) => true,
        Check::Tally(tally) => tally.counts(),
        _ => false,
    };
    if !walks || line.items.len() != 1 || l.get("items").is_some() {
        return None;
    }
    let at = bound(line, f, ctx)?;
    let cause = cause_of(l);
    let part = crate::subjects::sentence_part(
        sentence,
        &text(l, "assertion"),
        cause,
        list(l, "inputs"),
        &[],
        &at,
        true,
    );
    if part.failures.is_empty() {
        return None;
    }
    let inputs = part
        .inputs
        .into_iter()
        .filter(|x| alias_named(&text(x, "name"), aliases))
        .collect();
    Some(item(
        text(f, "item"),
        cause,
        inputs,
        part.failures,
        String::new(),
        f,
    ))
}

fn root_reads(check: &Check, roots: &[Clause], ctx: &Ctx) -> Vec<Value> {
    let mut out: Vec<Value> = Vec::new();
    let unread = |root: &&Clause| {
        root.kind == Kind::Root
            && matches!(
                root.cause,
                Cause::Absent | Cause::Null | Cause::Unusable | Cause::NotAnObject
            )
    };
    for root in roots.iter().filter(unread) {
        let Some(path) = for_line::all_paths(check)
            .into_iter()
            .chain(ops::walk::listed_refs(check))
            .find(|path| {
                (matches!(
                    path.start,
                    Start::Params | Start::Input | Start::Subject | Start::Own
                ) || matches!(path.start, Start::Part(_))
                    && path.steps.is_empty()
                    && ops::lists::walked(path, ctx).is_none())
                    && crate::name::name(path) == root.name
            })
        else {
            continue;
        };
        if let Some(input) = ops::read_path(path, ctx).inputs.first() {
            ops::push_new(
                &mut out,
                crate::parts::with_outcome(
                    input,
                    root.cause == Cause::Unusable
                        || ops::lists::text_fault(check, path, ctx).is_some(),
                ),
            );
        }
    }
    out
}

fn text_root(check: &Check, input: &Value, ctx: &Ctx) -> bool {
    for_line::all_paths(check)
        .into_iter()
        .chain(ops::walk::listed_refs(check))
        .any(|path| {
            crate::name::name(path) == text(input, "name")
                && ops::lists::text_fault(check, path, ctx).is_some()
        })
}

fn said_clauses(record: &Value) -> Vec<Clause> {
    record
        .get("ergo/clauses")
        .and_then(clause::of_value)
        .unwrap_or_default()
}

fn own_said(record: &Value, roots: &[String]) -> Vec<Clause> {
    said_clauses(record)
        .into_iter()
        .filter(|piece| {
            !matches!(piece.kind, Kind::More(_))
                && !roots.contains(&clause::text(std::slice::from_ref(piece)))
        })
        .collect()
}

fn own_text(record: &Value, said: &[Clause]) -> String {
    for_line::rendered(&said_name(record), &clause::lines(said))
}

fn bound<'a>(line: &For, f: &'a Value, ctx: &Ctx<'a>) -> Option<Ctx<'a>> {
    let value = f.get("value")?;
    let place = strings(f, "locations").first().cloned()?;
    let mut at = ctx.clone();
    at.aliases.insert(
        line.items[0].alias.clone(),
        crate::path::Located {
            value,
            location: crate::path::Location {
                root: ctx.subject.location.root,
                pointer: place,
            },
        },
    );
    Some(at)
}

fn said_under(row: &[Clause], item: &str) -> Vec<String> {
    row.iter()
        .filter(|clause| clause.kind == Kind::Item && clause.name == item)
        .flat_map(|clause| clause.said.iter().map(|said| said.text.clone()))
        .collect()
}

fn alias_roots(line: &For, idx: usize, f: &Value, row: &[Clause], ctx: &Ctx) -> Vec<Clause> {
    let said = said_under(row, &text(f, "item"));
    if said.is_empty() {
        return Vec::new();
    }
    let Some(at) = bound(line, f, ctx) else {
        return Vec::new();
    };
    line.item_alias_roots(idx, &at)
        .into_iter()
        .filter(|root| said.contains(&root.text))
        .collect()
}

fn broke_entry(
    line: &For,
    idx: usize,
    f: &Value,
    row: &[Clause],
    aliases: &[&str],
    ctx: &Ctx,
) -> Option<(Failure, Vec<Value>)> {
    let under = said_under(row, &text(f, "item"));
    let at = bound(line, f, ctx)?;
    let (_, said, inputs) = line.first_alias_run(idx, &at)?;
    let lifted = alias_roots(line, idx, f, row, ctx);
    let own: Vec<Clause> = said
        .into_iter()
        .filter(|piece| under.contains(&piece.text))
        .collect();
    let said: Vec<Clause> = lifted
        .iter()
        .filter(|root| !own.iter().any(|piece| piece.text == root.text))
        .cloned()
        .chain(own.iter().cloned())
        .collect();
    let cause = Cause::worst(said.iter().map(|piece| piece.cause))?;
    let (own_inputs, outer): (Vec<Value>, Vec<Value>) = inputs
        .into_iter()
        .partition(|x| alias_named(&text(x, "name"), aliases));
    Some((
        item(
            text(f, "item"),
            cause,
            with_root_outcomes(own_inputs, &lifted),
            Vec::new(),
            own_text(f, &said),
            f,
        ),
        outer,
    ))
}

fn said_cause(clauses: &[Clause], said: &str) -> Option<Cause> {
    clauses.iter().find_map(|clause| {
        if clause.kind != Kind::Item {
            return (clause.text == said).then_some(clause.cause);
        }
        if clause.text == said {
            return Some(clause.cause);
        }
        let rest = said.strip_prefix(&format!("{}: ", clause.name))?;
        Cause::worst(
            ops::message::split_outside_quotes(rest, ", and ")
                .into_iter()
                .filter_map(|piece| said_cause(&clause.said, piece)),
        )
    })
}

fn sort_key_said(f: &Value, row: &[Clause]) -> bool {
    row.iter()
        .any(|root| root.kind == Kind::Root && root.text == text(f, "ergo/text"))
}

fn sorted_entry(line: &For, f: &Value, row: &[Clause]) -> Option<Failure> {
    let name = text(f, "item");
    let said = row
        .iter()
        .find(|clause| clause.kind == Kind::Item && clause.name == name)?;
    let sorted = f.get("ergo/sorted")?;
    let key = line.items.iter().find_map(|item| match &item.how {
        for_line::How::Pick {
            sorted: Some(sorted),
            ..
        } => Some(&sorted.path),
        _ => None,
    })?;
    let at = key
        .steps
        .iter()
        .position(|step| matches!(step, crate::path::Step::Ref(_)))?;
    let before = crate::name::name(&crate::path::Path {
        start: key.start.clone(),
        steps: key.steps[..at].to_vec(),
    });
    let outcome = match said.cause {
        Cause::Absent | Cause::Null | Cause::Unusable | Cause::NotAnObject => said.cause.name(),
        _ => "unusable",
    };
    let input = json!({
        "name": format!("{}.{before}", crate::parts::position_name(&name)),
        "value": f.get("value").cloned().unwrap_or(Value::Null),
        "locations": f.get("locations").cloned().unwrap_or(json!([])),
        "outcome": outcome,
    });
    Some(Failure::Item {
        part: Part {
            name: name.clone(),
            cause: said.cause,
            inputs: vec![input],
            failures: Vec::new(),
            message: entry_text(&said.text, &name),
        },
        value: sorted.get("value").cloned().unwrap_or(Value::Null),
        locations: vec![text(sorted, "at")],
    })
}

fn keyed_entry(line: &For, f: &Value, row: &[Clause], ctx: &Ctx) -> Option<Failure> {
    let under = said_under(row, &text(f, "item"));
    let path = &line.items.get(1)?.path;
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, crate::path::Step::Ref(_)))?;
    let before = crate::path::Path {
        start: path.start.clone(),
        steps: path.steps[..at].to_vec(),
    };
    let bound = bound(line, f, ctx)?;
    let read = ops::read_path(&before, &bound).inputs.into_iter().next()?;
    let kids: Vec<Failure> = list(f, "failed_items")
        .iter()
        .filter(|x| under.contains(&text(x, "ergo/text")))
        .map(|x| {
            let cause = cause_of(x);
            Failure::List(Part {
                name: read.name.clone(),
                cause,
                inputs: vec![crate::parts::with_outcome(&read, cause == Cause::Unusable)],
                failures: Vec::new(),
                message: text(x, "ergo/text"),
            })
        })
        .collect();
    let cause = Cause::worst(kids.iter().map(|kid| kid.part().cause))?;
    Some(item(
        text(f, "item"),
        cause,
        Vec::new(),
        kids,
        String::new(),
        f,
    ))
}

fn with_root_outcomes(inputs: Vec<Value>, lifted: &[Clause]) -> Vec<Value> {
    inputs
        .into_iter()
        .map(|mut input| {
            let name = text(&input, "name");
            if let Some(root) = lifted
                .iter()
                .find(|root| root.text.starts_with(&format!("{name} ")))
                && matches!(
                    root.cause,
                    Cause::Absent | Cause::Null | Cause::Unusable | Cause::NotAnObject
                )
                && let Some(map) = input.as_object_mut()
            {
                map.insert("outcome".to_string(), json!(root.cause.name()));
            }
            input
        })
        .collect()
}

fn item_entry(
    f: &Value,
    l: &Value,
    aliases: &[&str],
    roots: &[String],
    lifted: &[Clause],
    walked: Option<Failure>,
) -> Option<Failure> {
    if let Some(pairs) = l.get("items").and_then(Value::as_array) {
        let inner: Vec<Failure> = pairs
            .iter()
            .filter_map(|y| {
                let said = own_said(y, roots);
                let message = own_text(y, &said);
                (!message.is_empty()).then(|| {
                    item(
                        text(y, "item"),
                        Cause::worst(said.iter().map(|piece| piece.cause))
                            .unwrap_or_else(|| cause_of(y)),
                        alias_inputs(y, aliases),
                        Vec::new(),
                        message,
                        y,
                    )
                })
            })
            .collect();
        let cause = Cause::worst(inner.iter().map(|y| y.part().cause))?;
        return Some(item(
            text(f, "item"),
            cause,
            alias_inputs(l, aliases),
            inner,
            String::new(),
            f,
        ));
    }
    let own = own_said(l, roots);
    let said: Vec<Clause> = lifted
        .iter()
        .filter(|root| !own.iter().any(|piece| piece.text == root.text))
        .cloned()
        .chain(own.iter().cloned())
        .collect();
    let message = own_text(f, &said);
    let walked = walked.filter(|walked| {
        let mut lines: Vec<String> = Vec::new();
        for kid in &walked.part().failures {
            said_by(kid, &[], &mut lines);
        }
        !message.is_empty() && said.iter().all(|piece| covered(piece, &lines, ""))
    });
    if let Some(walked) = walked {
        let part = walked.part().clone();
        let cause = Cause::worst(part.failures.iter().map(|kid| kid.part().cause))?;
        return Some(item(
            text(f, "item"),
            cause,
            part.inputs,
            part.failures,
            String::new(),
            f,
        ));
    }
    let cause = Cause::worst(said.iter().map(|piece| piece.cause))?;
    (!message.is_empty()).then(|| {
        item(
            text(f, "item"),
            cause,
            with_root_outcomes(alias_inputs(l, aliases), lifted),
            Vec::new(),
            message,
            f,
        )
    })
}

fn covered(piece: &Clause, lines: &[String], lead: &str) -> bool {
    match piece.kind {
        Kind::More(_) => true,
        Kind::Item if !piece.said.is_empty() => {
            let lead = format!("{lead}{}: ", piece.name);
            piece.said.iter().all(|inner| covered(inner, lines, &lead))
        }
        _ => lines.contains(&format!("{lead}{}", piece.text)),
    }
}

fn said_by(entry: &Failure, lead: &[String], out: &mut Vec<String>) {
    let part = entry.part();
    let mut here = lead.to_vec();
    if let Failure::Item { .. } = entry {
        here.push(part.name.clone());
    }
    if !part.message.is_empty() {
        let mut names = here.clone();
        if matches!(entry, Failure::Item { .. }) && part.message.starts_with(&part.name) {
            names.pop();
        }
        names.push(part.message.clone());
        out.push(names.join(": "));
    }
    for kid in &part.failures {
        said_by(kid, &here, out);
    }
}

fn alias_inputs(l: &Value, aliases: &[&str]) -> Vec<Value> {
    list(l, "inputs")
        .into_iter()
        .filter(|x| alias_named(&text(x, "name"), aliases))
        .collect()
}

fn whose_reads(whose: &[Check], f: &Value, ctx: &Ctx) -> Vec<Value> {
    let Some(object) = f.get("value").filter(|v| v.is_object()) else {
        return Vec::new();
    };
    let base = crate::parts::position_name(&text(f, "item"));
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
            if keys.len() != path.steps.len() {
                if ops::key_base::of_path(path, false, &at).is_some() {
                    out.push(json!({
                        "name": format!("{base}.{}", crate::name::name(path)),
                        "value": null,
                        "locations": [place.clone()],
                        "outcome": "absent",
                    }));
                }
                continue;
            }
            if keys.is_empty() {
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
                    if crate::parts::is_item(&text(x, "item")) {
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
            "name": format!("{}.{}", crate::parts::position_name(&name), text(sorted, "key")),
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
    if crate::parts::is_item(&name) {
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

/// A failed `for` row: its cause, its `inputs`, its message and the
/// clauses the message was made from.
pub struct LineRow<'a> {
    pub cause: Cause,
    pub inputs: &'a [Value],
    pub message: &'a str,
    pub clauses: &'a [Clause],
}

/// The entries of a failed `for` row's `failures`.
pub fn for_failures(
    line: &For,
    said: &LineRow,
    failed: &[Value],
    places: &[String],
    ctx: &Ctx,
) -> Vec<Failure> {
    let (row_cause, row_inputs, message, row) =
        (said.cause, said.inputs, said.message, said.clauses);
    let aliases: Vec<&str> = line.items.iter().map(|i| i.alias.as_str()).collect();
    let bare = |f: &Value| {
        text(f, "cause") == "not_an_object"
            && !f.get("value").is_some_and(Value::is_object)
            && !list(f, "failed_assertions").is_empty()
    };
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
            let inputs = ran
                .verdict
                .inputs
                .iter()
                .map(|input| {
                    crate::parts::with_outcome(
                        input,
                        crate::checks::input_unfit(&[&sentence.check], input, ctx),
                    )
                })
                .collect();
            Some((ran.verdict.cause, said, inputs))
        })
        .collect();
    let free_said: Vec<String> = frees
        .iter()
        .flatten()
        .flat_map(|(_, said, _)| {
            clauses(said)
                .into_iter()
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .collect();
    let root_texts = line.root_texts(ctx);
    let free_texts: Vec<String> = line
        .sentences
        .iter()
        .zip(&frees)
        .filter(|(_, free)| free.is_some())
        .map(|(sentence, _)| sentence.text.clone())
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
    let line_roots: Vec<String> = clause::lines(&line.whose_root_clauses(ctx));
    let first_key = line.first_key(ctx);
    let whose_keys = line.whose_keys(ctx);
    let key_said: Vec<&str> = first_key
        .iter()
        .flat_map(|k| {
            std::iter::once(k.key_text.as_str()).chain(k.base.iter().map(|(t, _, _)| t.as_str()))
        })
        .chain(whose_keys.iter().map(|(_, text, _)| text.as_str()))
        .collect();
    let first_reads: Option<String> = (line.items.len() == 2
        && matches!(line.items[0].how, for_line::How::Some { .. }))
    .then(|| format!(" of {}: {}.", list_names[0], line.items[0].alias));
    let odd_params = ctx.params.is_some_and(|p| !p.is_object() && !p.is_null());
    let mut skipped: Vec<&str> = key_said.clone();
    let base = first_key.as_ref().and_then(|k| k.base.clone());
    if let Some((text, _, _)) = &base {
        skipped.push(text);
    }
    let later_keys = line.later_key_texts(ctx);
    skipped.extend(later_keys.iter().map(String::as_str));
    let mut walked: Vec<(String, Vec<String>)> = Vec::new();
    let unread = odd_params || off_subject;
    if !odd_params {
        let dead_said: Vec<String> = failed
            .iter()
            .filter(|f| list(f, "failed_assertions").is_empty())
            .flat_map(|f| {
                let mut said = clause::lines(&said_clauses(f));
                said.push(text(f, "ergo/text"));
                said
            })
            .collect();
        for clause in row {
            let said = clause::text(std::slice::from_ref(clause));
            if skipped.contains(&said.as_str()) {
                continue;
            }
            let name = match clause.kind {
                Kind::Root if line_roots.contains(&said) => list_names[0].clone(),
                Kind::List if !dead_said.contains(&said) => list_names
                    .iter()
                    .find(|n| **n == clause.name)
                    .unwrap_or(&list_names[0])
                    .clone(),
                _ => continue,
            };
            match walked.first_mut() {
                Some((_, texts)) => ops::push_new(texts, said),
                None => walked.push((name, vec![said])),
            }
        }
    }
    let broke_runs: Vec<(usize, usize, (Failure, Vec<Value>))> = (0..line.sentences.len())
        .flat_map(|i| {
            failed
                .iter()
                .enumerate()
                .filter(|(_, f)| {
                    list(f, "failed_assertions").is_empty() && !list(f, "failed_items").is_empty()
                })
                .filter_map(|(at, f)| Some((i, at, broke_entry(line, i, f, row, &aliases, ctx)?)))
                .collect::<Vec<_>>()
        })
        .collect();
    let broke_rest = |clause: &str| -> Option<String> {
        broke_runs.iter().find_map(|(_, _, (entry, _))| {
            let name = &entry.part().name;
            let rest = clause.strip_prefix(&format!("{name}: "))?;
            let said: Vec<&str> = broke_runs
                .iter()
                .filter(|(_, _, (other, _))| other.part().name == *name)
                .flat_map(|(_, _, (other, _))| clauses(&other.part().message))
                .collect();
            let pieces = ops::message::split_outside_quotes(rest, ", and ");
            let mut left: Vec<&str> = Vec::new();
            let mut at = 0;
            while at < pieces.len() {
                match (at + 1..=pieces.len())
                    .rev()
                    .find(|end| said.contains(&pieces[at..*end].join(", and ").as_str()))
                {
                    Some(end) => at = end,
                    None => {
                        left.push(pieces[at]);
                        at += 1;
                    }
                }
            }
            (left.len() < pieces.len()).then(|| match left.is_empty() {
                true => String::new(),
                false => format!("{name}: {}", left.join(", and ")),
            })
        })
    };
    let sorted_said: Vec<String> = failed
        .iter()
        .filter(|f| f.get("ergo/sorted").is_some() && sort_key_said(f, row))
        .flat_map(|f| {
            row.iter()
                .filter(|clause| clause.kind == Kind::Item && clause.name == text(f, "item"))
                .map(|clause| clause.text.clone())
                .collect::<Vec<_>>()
        })
        .collect();
    let mut leftover: Vec<String> = Vec::new();
    let first_items: Vec<String> = failed
        .iter()
        .filter(|f| list(f, "failed_assertions").is_empty())
        .map(|f| text(f, "item"))
        .chain(
            row.iter()
                .filter(|piece| piece.kind == Kind::Item)
                .map(|piece| piece.name.clone()),
        )
        .filter(|n| crate::parts::is_item(n) && crate::parts::list_base(n) == list_names[0])
        .filter(|n| {
            !failed
                .iter()
                .any(|f| text(f, "item") == *n && !list(f, "failed_assertions").is_empty())
        })
        .collect();
    let walk_broke: Vec<String> = failed
        .iter()
        .filter(|f| !list(f, "failed_assertions").is_empty())
        .flat_map(|f| {
            list(f, "failed_items")
                .iter()
                .map(|x| format!("{}: {}", text(f, "item"), text(x, "ergo/text")))
                .collect::<Vec<_>>()
        })
        .collect();
    let walk_pieces: Vec<&str> = walked
        .iter()
        .flat_map(|(_, texts)| texts.iter().flat_map(|t| clauses(t)))
        .collect();
    let mut lists: Vec<Failure> = Vec::new();
    let mut rest: Vec<Failure> = Vec::new();
    for f in failed
        .iter()
        .filter(|f| !list(f, "failed_assertions").is_empty() && !bare(f))
    {
        if let Some(Failure::Item {
            mut part,
            value,
            locations,
        }) = dead_entry(line, f, ctx).filter(|_| !list(f, "failed_items").is_empty())
        {
            part.cause = Cause::worst(part.failures.iter().map(|kid| kid.part().cause))
                .unwrap_or(part.cause);
            rest.push(Failure::Item {
                part,
                value,
                locations,
            });
        }
    }
    for f in failed
        .iter()
        .filter(|f| list(f, "failed_assertions").is_empty() || bare(f))
    {
        let said = text(f, "ergo/text");
        if !said.is_empty()
            && list(f, "failed_items").is_empty()
            && clauses(&said)
                .into_iter()
                .all(|p| whose_roots.iter().any(|t| t == p))
        {
            let second = line.items.len() == 2
                && !matches!(line.items[1].how, for_line::How::Pick { .. })
                && cause_of(f) != Cause::NotAnObject
                && crate::parts::is_item(&text(f, "item"))
                && crate::parts::list_base(&text(f, "item")) == list_names[1];
            if !second {
                continue;
            }
        }
        if f.get("ergo/sorted").is_some() && sort_key_said(f, row) {
            if let Some(entry) = sorted_entry(line, f, row) {
                rest.push(entry);
            }
            continue;
        }
        if !later_keys.is_empty() && !list(f, "failed_items").is_empty() {
            if let Some(entry) = keyed_entry(line, f, row, ctx) {
                rest.push(entry);
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
    let mut under: Vec<(Vec<Cause>, Vec<Value>, Vec<Failure>)> = line
        .sentences
        .iter()
        .enumerate()
        .map(|(i, sentence)| {
            let mut causes: Vec<Cause> = Vec::new();
            let mut inputs: Vec<Value> = Vec::new();
            let mut items: Vec<Failure> = Vec::new();
            if line.sentences.iter().position(|s| s.text == sentence.text) != Some(i) {
                return (causes, inputs, items);
            }
            for (at, f) in failed.iter().enumerate().filter(|(_, f)| !bare(f)) {
                if let Some((_, _, (entry, outer))) = broke_runs
                    .iter()
                    .find(|(idx, found, _)| *idx == i && *found == at)
                {
                    causes.push(entry.part().cause);
                    items.push(entry.clone());
                    for x in outer {
                        ops::push_new(&mut inputs, x.clone());
                    }
                }
                for l in list(f, "failed_assertions") {
                    if text(&l, "assertion") != sentence.text {
                        continue;
                    }
                    causes.push(cause_of(&l));
                    let pairs = list(&l, "items");
                    for x in list(&l, "inputs")
                        .into_iter()
                        .chain(pairs.iter().flat_map(|y| list(y, "inputs")))
                    {
                        if !alias_named(&text(&x, "name"), &aliases) {
                            ops::push_new(&mut inputs, x);
                        }
                    }
                    if frees[i].is_none() {
                        let walked = walked_under(line, &sentence.check, f, &l, &aliases, ctx);
                        let lifted = alias_roots(line, i, f, row, ctx);
                        if let Some(entry) =
                            item_entry(f, &l, &aliases, &root_texts, &lifted, walked)
                        {
                            causes.push(entry.part().cause);
                            items.push(entry);
                        }
                    }
                }
            }
            (causes, inputs, items)
        })
        .collect();
    let mut row_said: Vec<String> = Vec::new();
    for entry in lists
        .iter()
        .chain(&rest)
        .chain(under.iter().flat_map(|(_, _, items)| items))
    {
        said_by(entry, &[], &mut row_said);
    }
    for entry in &rest {
        let part = entry.part();
        for clause in row.iter().filter(|clause| {
            clause.kind == Kind::Item
                && !clause.text.is_empty()
                && (clause.name == part.name || clause.text == part.message)
        }) {
            ops::push_new(&mut row_said, clause.text.clone());
        }
        let dead = failed
            .iter()
            .any(|f| text(f, "item") == part.name && list(f, "failed_assertions").is_empty());
        for clause in row
            .iter()
            .filter(|clause| dead && clause.kind == Kind::Item && clause.name == part.name)
        {
            let mut kids_said: Vec<String> = Vec::new();
            said_by(entry, &[], &mut kids_said);
            for inner in clause.said.iter().filter(|inner| inner.kind == Kind::Item) {
                let named = part
                    .failures
                    .iter()
                    .any(|kid| kid.part().name == inner.name);
                for line in clause::lines(std::slice::from_ref(inner))
                    .into_iter()
                    .filter(|line| !named || kids_said.contains(&format!("{}: {line}", part.name)))
                {
                    for piece in clauses(&line) {
                        ops::push_new(&mut row_said, format!("{}: {piece}", part.name));
                    }
                }
            }
        }
    }
    for whole in clauses(message) {
        let rest = broke_rest(whole);
        if let Some(rest) = rest.as_ref().filter(|rest| !rest.is_empty()) {
            ops::push_new(&mut leftover, rest.clone());
            continue;
        }
        let clause = rest.as_deref().unwrap_or(whole);
        if let Some(middle) = &first_reads
            && crate::parts::is_item(clause)
            && clause.contains(middle.as_str())
            && (clause.ends_with(" is missing")
                || clause.ends_with(" is null")
                || clause.contains(", which isn't "))
        {
            let alias = &line.items[0].alias;
            let at = line
                .sentences
                .iter()
                .position(|s| for_line::reads_alias(&s.check, alias))
                .unwrap_or(0);
            ops::push_new(&mut owned[at], clause.to_string());
            continue;
        }
        if clause.is_empty()
            || skipped.contains(&clause)
            || failed.iter().any(|f| {
                let named = text(f, "item");
                crate::parts::is_item(&named)
                    && clause
                        .strip_prefix(&format!("{named}: "))
                        .is_some_and(|rest| {
                            let sentences = list(f, "failed_assertions");
                            let joined: Vec<String> = sentences
                                .iter()
                                .filter(|l| !free_texts.contains(&text(l, "assertion")))
                                .flat_map(|l| clause::lines(&own_said(l, &root_texts)))
                                .collect();
                            joined.join(", and ") == rest
                                || sentences.iter().any(|l| {
                                    texts(l)
                                        .iter()
                                        .any(|t| clauses(t).into_iter().any(|p| p == rest))
                                })
                        })
            })
            || failed.iter().any(|f| {
                list(f, "failed_assertions").iter().any(|l| {
                    list(l, "items").iter().any(|pair| {
                        clause.starts_with(&format!(
                            "{}: {}: ",
                            text(f, "item"),
                            text(pair, "item")
                        ))
                    })
                })
            })
            || ops::message::cap_note(clause).is_some()
            || row_said.iter().any(|t| t == clause)
            || walk_broke.iter().any(|t| t == clause)
            || sorted_said.iter().any(|t| t == clause)
            || free_said.iter().any(|t| t == clause)
        {
            continue;
        }
        if let Some(i) = owns.iter().position(|o| o.iter().any(|t| t == clause)) {
            ops::push_new(&mut owned[i], clause.to_string());
        } else if walk_pieces.contains(&clause) {
        } else if off_subject
            || whose_roots.iter().any(|t| t == clause)
            || list_names.iter().any(|n| {
                clause.starts_with(&format!("{n} "))
                    || n.match_indices('.')
                        .any(|(at, _)| clause.starts_with(&format!("{} ", &n[..at])))
            })
            || texts_once.len() != 1
        {
            let first_item = first_items.iter().any(|n| {
                clause.starts_with(&format!("{n}: ")) || clause.starts_with(&format!("{n} "))
            });
            if unread || (texts_once.len() != 1 && first_item) {
                ops::push_new(&mut leftover, clause.to_string());
            }
        } else {
            ops::push_new(&mut owned[0], clause.to_string());
        }
    }
    let only_items = walked.is_empty();
    if !leftover.is_empty() {
        match walked.first_mut() {
            Some((_, texts)) => texts.extend(leftover),
            None => walked.push((list_names[0].clone(), leftover)),
        }
    }
    let empty_first = line.items.first().is_some_and(|first| {
        matches!(&ops::read_path(&first.path, ctx).inputs.first(), Some(input) if input.value == json!([]))
    });
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
        let (mut causes, mut inputs, items) = std::mem::take(&mut under[i]);
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
            None if off_subject => String::new(),
            None => {
                let roots = if odd_params {
                    Vec::new()
                } else {
                    line.assertion_roots(i, ctx)
                };

                let all_read = !causes.is_empty() || empty_first;
                if all_read {
                    causes.extend(roots.iter().map(|root| root.cause));
                }
                for input in root_reads(&sentence.check, &roots, ctx) {
                    let walked = |x: &Value| text(x, "name").replace("[]", "");
                    let shown = all_read || text_root(&sentence.check, &input, ctx);
                    if shown && !inputs.iter().any(|x| walked(x) == walked(&input)) {
                        inputs.push(input);
                    }
                }
                let mut own: Vec<String> = Vec::new();
                if !roots.is_empty() {
                    own.push(clause::text(&clause::shown(&roots)));
                }
                let root_lines = clause::lines(&roots);
                for piece in clauses(message) {
                    let a_root = !odd_params
                        && (root_texts.iter().any(|t| t == piece)
                            || owns.iter().flatten().any(|t| t == piece)
                            || root_lines.iter().any(|line| clauses(line).contains(&piece)));
                    if owned[i].iter().any(|o| o == piece) && !a_root {
                        ops::push_new(&mut own, piece.to_string());
                    }
                }
                own.join("; ")
            }
        };
        let mut named: Vec<String> = Vec::new();
        inputs.retain(|x| {
            let name = text(x, "name");
            let first = !named.contains(&name);
            named.push(name);
            first
        });
        if said.is_empty() && items.is_empty() {
            continue;
        }
        if inputs.is_empty()
            && items.is_empty()
            && ctx.params.is_some_and(|p| !p.is_object() && !p.is_null())
        {
            inputs = crate::subjects::root_inputs(
                &ops::key_base::every_path(&sentence.check),
                &sentence.check,
                ctx,
            );
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
    for (at, (label, texts)) in walked.into_iter().enumerate() {
        lists.insert(
            at,
            Failure::List(Part {
                name: label.clone(),
                cause: Cause::worst(
                    texts
                        .iter()
                        .flat_map(|said| clauses(said))
                        .filter_map(|said| said_cause(row, said)),
                )
                .filter(|_| only_items)
                .unwrap_or(row_cause),
                inputs: row_inputs
                    .iter()
                    .filter(|i| {
                        let n = text(i, "name");
                        n == label || n == format!("{label}[]")
                    })
                    .cloned()
                    .collect(),
                failures: Vec::new(),
                message: texts.join("; "),
            }),
        );
    }
    if let Some((text, cause, input)) = base {
        lists.insert(
            0,
            Failure::List(Part {
                name: input.name.clone(),
                cause,
                inputs: vec![crate::parts::with_outcome(&input, false)],
                failures: Vec::new(),
                message: text,
            }),
        );
    }
    out.extend(lists);
    out.extend(rest.into_iter().filter_map(said_item));
    out
}

fn said_item(entry: Failure) -> Option<Failure> {
    let Failure::Item {
        mut part,
        value,
        locations,
    } = entry
    else {
        return Some(entry);
    };
    part.failures = std::mem::take(&mut part.failures)
        .into_iter()
        .filter_map(said_item)
        .collect();
    (!part.message.is_empty() || !part.failures.is_empty()).then_some(Failure::Item {
        part,
        value,
        locations,
    })
}

#[cfg(test)]
mod tests;
