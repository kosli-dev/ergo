use crate::cause::Cause;
use crate::checks::{CheckRead, Plan, read_checks};
use crate::ops::walk;
use crate::ops::{self, Check, Input, Verdict};
use crate::path::{self, Ctx, Located, Location, Outcome, Path, Start, Step};
use crate::policy::{Policy, Requirement, SubjectName};
use crate::reading::{Filter, Lowered, Reading, Relation, Source};
use crate::report::{
    Evaluation, Row, min_subjects_row, no_subjects, row_of, unique_ancestor_ids_row,
    unique_ids_row, unreadable_params,
};
use crate::value::{self, json_text};
use serde_json::{Map, Value, json};
use std::cmp::Ordering;
use std::collections::BTreeMap;

struct Env<'a> {
    reading: &'a Reading,
    requirement_name: &'a str,
    requirement: &'a Requirement,
    subject: &'a str,
    checks: BTreeMap<String, CheckRead>,
    input: &'a Value,
    params: Option<&'a Value>,
    unreadable: Vec<Value>,
}

#[derive(Clone)]
struct Anc<'a> {
    name: String,
    id: Value,
    at: Located<'a>,
}

struct Entry<'a> {
    at: Located<'a>,
    key: Option<String>,
    copies: Vec<Location>,
}

fn merged_copies(entries: Vec<Entry<'_>>) -> Vec<Entry<'_>> {
    let mut out: Vec<Entry> = Vec::new();
    let mut seen: BTreeMap<String, usize> = BTreeMap::new();
    for entry in entries {
        let key = value::copy_key(entry.at.value);
        match seen.get(&key) {
            Some(&at) => out[at].copies.push(entry.at.location.clone()),
            None => {
                seen.insert(key, out.len());
                out.push(entry);
            }
        }
    }
    out
}

impl<'a> Entry<'a> {
    fn at_each(&self) -> Vec<Located<'a>> {
        std::iter::once(self.at.clone())
            .chain(self.copies.iter().map(|location| Located {
                value: self.at.value,
                location: location.clone(),
            }))
            .collect()
    }
}

fn merged_column(lists: &[&Vec<Value>]) -> Vec<Value> {
    let longest = lists.iter().map(|list| list.len()).max().unwrap_or(0);
    let mut out: Vec<Value> = Vec::new();
    for at in 0..longest {
        let mut column: Vec<Value> = Vec::new();
        for list in lists {
            if let Some(found) = list.get(at)
                && !column.contains(found)
            {
                column.push(found.clone());
            }
        }
        out.extend(column);
    }
    out
}

fn merged_value(values: &[&Value]) -> Value {
    match values[0] {
        Value::Object(map) => {
            let mut out = map.clone();
            for key in [
                "locations",
                "inputs",
                "items",
                "failed_items",
                "failed_assertions",
            ] {
                let found: Vec<&Vec<Value>> = values
                    .iter()
                    .filter_map(|value| value.get(key).and_then(Value::as_array))
                    .collect();
                if found.len() != values.len() {
                    continue;
                }
                let merged = if key == "locations" {
                    merged_column(&found)
                } else {
                    merged_list(&found)
                };
                out.insert(key.to_string(), Value::Array(merged));
            }
            Value::Object(out)
        }
        other => other.clone(),
    }
}

fn merged_list(lists: &[&Vec<Value>]) -> Vec<Value> {
    (0..lists[0].len())
        .map(|at| {
            let column: Vec<&Value> = lists.iter().filter_map(|list| list.get(at)).collect();
            merged_value(&column)
        })
        .collect()
}

fn merged_rows(rows: Vec<Row>) -> Row {
    let inputs: Vec<&Vec<Value>> = rows.iter().map(|row| &row.inputs).collect();
    let merged_inputs = merged_list(&inputs);
    let failed: Vec<&Value> = rows
        .iter()
        .filter_map(|row| row.failed_items.as_ref())
        .collect();
    let merged_failed = (failed.len() == rows.len() && !failed.is_empty()).then(|| {
        let lists: Vec<&Vec<Value>> = failed.iter().filter_map(|v| v.as_array()).collect();
        Value::Array(merged_list(&lists))
    });
    let mut row = rows.into_iter().next().expect("one row for each copy");
    row.inputs = merged_inputs;
    if merged_failed.is_some() {
        row.failed_items = merged_failed;
    }
    row
}

fn merged_evaluations(runs: Vec<Vec<Evaluation>>) -> Vec<Evaluation> {
    let mut runs = runs.into_iter();
    let Some(first) = runs.next() else {
        return Vec::new();
    };
    let rest: Vec<Vec<Evaluation>> = runs.collect();
    first
        .into_iter()
        .enumerate()
        .map(|(at, evaluation)| {
            let others: Vec<&Evaluation> = rest.iter().filter_map(|run| run.get(at)).collect();
            let merge = |pick: &dyn Fn(&Evaluation) -> &Vec<Row>, mine: Vec<Row>| -> Vec<Row> {
                mine.into_iter()
                    .enumerate()
                    .map(|(i, row)| {
                        let mut all = vec![row];
                        all.extend(others.iter().filter_map(|e| pick(e).get(i).cloned()));
                        merged_rows(all)
                    })
                    .collect()
            };
            Evaluation {
                total: evaluation.total,
                matching: evaluation.matching,
                min_subjects: merge(&|e| &e.min_subjects, evaluation.min_subjects),
                unique_ids: merge(&|e| &e.unique_ids, evaluation.unique_ids),
                unique_ancestor_ids: merge(
                    &|e| &e.unique_ancestor_ids,
                    evaluation.unique_ancestor_ids,
                ),
                applies: merge(&|e| &e.applies, evaluation.applies),
                subject_rows: evaluation
                    .subject_rows
                    .into_iter()
                    .enumerate()
                    .map(|(g, group)| {
                        group
                            .into_iter()
                            .enumerate()
                            .map(|(i, row)| {
                                let mut all = vec![row];
                                all.extend(others.iter().filter_map(|e| {
                                    e.subject_rows.get(g).and_then(|rows| rows.get(i)).cloned()
                                }));
                                merged_rows(all)
                            })
                            .collect()
                    })
                    .collect(),
            }
        })
        .collect()
}

struct Broken {
    msg: String,
    rank: u8,
    listed: bool,
    order: Vec<walk::Seg>,
    path: String,
    cause: Cause,
    value: Value,
    location: Option<String>,
}

impl Broken {
    fn to_json(&self) -> Value {
        let locations: Vec<String> = self.location.iter().cloned().collect();
        json!({
            "path": self.path,
            "item": self.path,
            "cause": self.cause.name(),
            "value": self.value,
            "locations": locations,
        })
    }
}

enum Read<'a> {
    Entries {
        entries: Vec<Entry<'a>>,
        broken: Vec<Broken>,
    },
    Failed(Cause),
}

fn context<'a>(env: &Env<'a>, subject: Located<'a>, anc: &[Anc<'a>]) -> Ctx<'a> {
    Ctx {
        label: None,
        subject,
        input: env.input,
        params: env.params,
        aliases: anc.iter().map(|a| (a.name.clone(), a.at.clone())).collect(),
    }
}

fn input_root<'a>(env: &Env<'a>) -> Located<'a> {
    Located {
        value: env.input,
        location: Location::input_root(),
    }
}

fn in_map(anc: &[Anc]) -> Option<Map<String, Value>> {
    if anc.is_empty() {
        None
    } else {
        Some(anc.iter().map(|a| (a.name.clone(), a.id.clone())).collect())
    }
}

fn with_in(mut row: Row, anc: &[Anc]) -> Row {
    row.subject_in = in_map(anc);
    row
}

fn plain_entries<'a>(read: &path::Read<'a>, scalar_ok: bool) -> Result<Vec<Entry<'a>>, Cause> {
    let (Some(value), Some(location)) = (read.value, read.location.clone()) else {
        return Err(Cause::Unusable);
    };
    match value {
        Value::Array(items) => Ok(items
            .iter()
            .enumerate()
            .map(|(at, item)| Entry {
                at: Located {
                    value: item,
                    location: location.index(at as u64),
                },
                key: None,
                copies: Vec::new(),
            })
            .collect()),
        Value::Object(_) => Ok(vec![Entry {
            at: Located { value, location },
            key: None,
            copies: Vec::new(),
        }]),
        Value::String(_) | Value::Number(_) | Value::Bool(_) if scalar_ok => Ok(vec![Entry {
            at: Located { value, location },
            key: None,
            copies: Vec::new(),
        }]),
        _ => Err(Cause::Unusable),
    }
}

fn each_of_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    source: &Source,
    path: &Path,
    each_of: &Path,
    anc: &[Anc<'a>],
) -> Read<'a> {
    if each_of.start == Start::Params && !env.unreadable.is_empty() {
        return Read::Failed(Cause::Unusable);
    }
    let ctx = context(env, input_root(env), anc);
    let object = read_from(path, &ctx);
    let keys = read_from(each_of, &ctx);
    if keys.outcome != Outcome::Found {
        return Read::Failed(keys.outcome.cause().unwrap_or(Cause::Unusable));
    }
    let Some(Value::Array(listed)) = keys.value else {
        return Read::Failed(Cause::Unusable);
    };
    let mut names: Vec<&str> = Vec::new();
    for key in listed {
        match key {
            Value::String(text) => names.push(text),
            _ => return Read::Failed(Cause::Unusable),
        }
    }
    names.sort();
    names.dedup();
    let alias_is_not_an_object = path.steps.is_empty()
        && matches!(path.start, Start::Alias(_))
        && object.value.is_some_and(|value| !value.is_object());
    if object.outcome == Outcome::NotAnObject || alias_is_not_an_object {
        return Read::Failed(Cause::NotAnObject);
    }
    let met = keyed_met(env, path, source, anc);
    let unread = match (object.outcome, object.value) {
        _ if met.is_some() => Some(Cause::Unusable),
        (Outcome::Found, Some(Value::Object(_))) => None,
        (Outcome::Found, _) => Some(Cause::Unusable),
        (other, _) => Some(other.cause().unwrap_or(Cause::Unusable)),
    };
    let target = object.value;
    let Some(location) = object.location else {
        return Read::Failed(unread.unwrap_or(Cause::Unusable));
    };
    let entries = names
        .into_iter()
        .map(|key| {
            let found = match target {
                Some(Value::Object(map)) => map.get(key),
                _ => None,
            };
            let at = match found {
                Some(value) => Located {
                    value,
                    location: location.key(key),
                },
                None => Located {
                    value: empty,
                    location: location.clone(),
                },
            };
            Entry {
                at,
                key: Some(key.to_string()),
                copies: Vec::new(),
            }
        })
        .collect();
    let shown_name = from_name(path, source, anc, &ctx, true);
    let broken = unread
        .map(|cause| Broken {
            rank: 0,
            listed: true,
            msg: if let Some(said) = &met {
                said.clone()
            } else if matches!(object.value, Some(Value::Array(_))) {
                String::new()
            } else {
                target_message(env, empty, source, anc, cause).unwrap_or_else(|| {
                    ops::message::stated(
                        &shown_name,
                        cause,
                        object.value.unwrap_or(&Value::Null),
                        "a list or an object",
                    )
                })
            },
            order: Vec::new(),
            path: String::new(),
            cause,
            value: Value::Null,
            location: Some(location.render()),
        })
        .into_iter()
        .collect();
    Read::Entries { entries, broken }
}

fn broken_from(failure: &walk::Failure) -> Broken {
    let head = failure
        .msg
        .strip_suffix("which isn't a list or an object")
        .or_else(|| failure.msg.strip_suffix("which isn't a list"));
    let msg = match head {
        Some(head) if failure.value.is_object() => format!("{head}which isn't a list"),
        Some(head) => format!("{head}which isn't a list or an object"),
        None => failure.msg.clone(),
    };
    Broken {
        msg,
        rank: 0,
        listed: true,
        order: failure.order.clone(),
        path: failure.path.clone(),
        cause: failure.cause,
        value: failure.value.clone(),
        location: failure.location.as_ref().map(Location::render),
    }
}

fn steps_name(segs: &[walk::Seg]) -> String {
    crate::name::name(&Path {
        start: Start::Subject,
        steps: segs.iter().map(walk::Seg::to_step).collect(),
    })
}

fn start_name(segs: &[walk::Seg], root: &str, child: bool) -> String {
    match segs.first() {
        None => root.to_string(),
        Some(walk::Seg::Index(_)) => crate::name::name(&Path {
            start: if child {
                Start::Alias(root.to_string())
            } else {
                Start::Input
            },
            steps: segs.iter().map(walk::Seg::to_step).collect(),
        }),
        Some(_) => steps_name(segs),
    }
}

fn plain_item_name(segs: &[walk::Seg]) -> String {
    let indexes: Vec<usize> = segs
        .iter()
        .enumerate()
        .filter(|(_, seg)| matches!(seg, walk::Seg::Index(_)))
        .map(|(at, _)| at)
        .collect();
    let Some(first) = indexes.first() else {
        return steps_name(segs);
    };
    let mut parts = vec![steps_name(&segs[..=*first])];
    for pair in indexes.windows(2) {
        let walk::Seg::Index(at) = &segs[pair[1]] else {
            continue;
        };
        let between = &segs[pair[0] + 1..pair[1]];
        parts.push(format!(
            "item {} of {}",
            at + 1,
            if between.is_empty() {
                "it".to_string()
            } else {
                steps_name(between)
            }
        ));
    }
    let tail = &segs[indexes[indexes.len() - 1] + 1..];
    if !tail.is_empty() {
        parts.push(steps_name(tail));
    }
    parts.join(": ")
}

fn from_item_name(segs: &[walk::Seg], root: &str, child: bool) -> String {
    match segs.first() {
        None => root.to_string(),
        Some(walk::Seg::Index(_)) if segs.len() == 1 => start_name(segs, root, child),
        Some(walk::Seg::Index(_)) => format!(
            "{}: {}",
            start_name(&segs[..1], root, child),
            plain_item_name(&segs[1..])
        ),
        Some(_) => plain_item_name(segs),
    }
}

fn type_word(value: &Value) -> &'static str {
    match value {
        Value::Object(_) => "an object",
        Value::Array(_) => "a list",
        Value::String(_) => "text",
        Value::Number(_) => "a number",
        _ => "true or false",
    }
}

struct Note {
    msg: String,
    items: Vec<(Vec<walk::Seg>, Value, Location)>,
}

impl Note {
    fn brokens(self, root: &str, child: bool) -> Vec<Broken> {
        let mut out: Vec<Broken> = self
            .items
            .into_iter()
            .map(|(segs, value, at)| Broken {
                msg: String::new(),
                rank: 1,
                listed: true,
                path: start_name(&segs, root, child),
                order: segs,
                cause: Cause::Unusable,
                value,
                location: Some(at.render()),
            })
            .collect();
        out.push(note_broken(self.msg));
        out
    }
}

fn types_note<'v>(
    values: impl Iterator<Item = (Vec<walk::Seg>, &'v Value, Location)>,
    root: &str,
    child: bool,
    plain: bool,
) -> Option<Note> {
    let mut seen: Vec<&'static str> = Vec::new();
    let mut said: Vec<String> = Vec::new();
    let mut items = Vec::new();
    for (segs, value, at) in values {
        if value.is_null() {
            continue;
        }
        let word = type_word(value);
        if !seen.contains(&word) {
            seen.push(word);
            let name = if plain {
                start_name(&segs, root, child)
            } else {
                from_item_name(&segs, root, child)
            };
            said.push(format!("{name} is {word}"));
            items.push((segs, value.clone(), at));
        }
    }
    (said.len() > 1).then(|| Note {
        msg: said.join(", "),
        items,
    })
}

fn root_name(child: bool, anc: &[Anc]) -> String {
    if child {
        from_root(anc)
    } else {
        "$input".to_string()
    }
}

fn resolved_segs(steps: &[Step], ctx: &Ctx) -> Option<Vec<walk::Seg>> {
    steps
        .iter()
        .map(|step| match path::resolve(step, ctx) {
            Ok(path::Resolved::Key(key)) => Some(walk::Seg::Key(key)),
            Ok(path::Resolved::Index(at)) => Some(walk::Seg::Index(at)),
            Err(_) => None,
        })
        .collect()
}

fn flat_path(path: &Path) -> Path {
    match &path.start {
        Start::Part(part) => Path {
            start: part.base.clone(),
            steps: part
                .steps
                .iter()
                .chain(path.steps.iter())
                .cloned()
                .collect(),
        },
        _ => path.clone(),
    }
}

fn found_list(path: &Path, j: usize, ctx: &Ctx) -> bool {
    let prefix = Path {
        start: path.start.clone(),
        steps: path.steps[..j].to_vec(),
    };
    let read = read_from(&prefix, ctx);
    read.outcome == Outcome::Found && matches!(read.value, Some(Value::Array(_)))
}

fn named_steps(steps: &[Step]) -> usize {
    steps
        .iter()
        .filter(|step| !matches!(step, Step::Index(_)))
        .count()
}

fn keyed_message(env: &Env, source: &Source, anc: &[Anc]) -> Option<String> {
    match source {
        Source::Root {
            path,
            each_of: Some(_),
            ..
        }
        | Source::Child {
            path,
            each_of: Some(_),
            ..
        } => keyed_met(env, path, source, anc),
        _ => None,
    }
}

fn plain_met(env: &Env, source: &Source, anc: &[Anc]) -> Option<(usize, String)> {
    let (path, names, every_text, child) = match source {
        Source::Root {
            path,
            every: false,
            each_of: None,
            names,
            every_text,
            ..
        } => (path, *names, every_text, false),
        Source::Child {
            path,
            every: false,
            each_of: None,
            names,
            every_text,
            ..
        } => (path, *names, every_text, true),
        _ => return None,
    };
    if names < 2 {
        return None;
    }
    let path = &flat_path(path);
    let named_start = child || names > named_steps(&path.steps);
    let ctx = context(env, input_root(env), anc);
    let n = path.steps.len();
    let at = (0..=n).find(|&j| {
        let point = j == n || (!matches!(path.steps[j], Step::Index(_)) && (j > 0 || named_start));
        point && found_list(path, j, &ctx)
    })?;
    let root = root_name(child, anc);
    let segs = resolved_segs(&path.steps[..at], &ctx)?;
    let name = start_name(&segs, &root, child);
    Some((
        at,
        format!("{name} is a list: write {every_text} to read each item"),
    ))
}

fn keyed_met(env: &Env, path: &Path, source: &Source, anc: &[Anc]) -> Option<String> {
    let names = match source {
        Source::Root { names, .. } | Source::Child { names, .. } => *names,
    };
    let path = &flat_path(path);
    let child = matches!(path.start, Start::Alias(_));
    let named_start = child || names > named_steps(&path.steps);
    let ctx = context(env, input_root(env), anc);
    let n = path.steps.len();
    let at = (0..=n).find(|&j| {
        let point = if j == 0 {
            named_start && !matches!(path.steps.first(), Some(Step::Index(_)))
        } else {
            j == n || !matches!(path.steps[j], Step::Index(_))
        };
        point && found_list(path, j, &ctx)
    })?;
    let segs = resolved_segs(&path.steps[..at], &ctx)?;
    let name = start_name(&segs, &root_name(child, anc), child);
    Some(format!(
        "{name} is a list, but named by each of reads the keys of one object: make each item a subject and read the keys in it"
    ))
}

fn plain_types(read: &path::Read, path: &Path, ctx: &Ctx, anc: &[Anc]) -> Vec<Broken> {
    let (Some(Value::Array(items)), Some(location)) = (read.value, read.location.as_ref()) else {
        return Vec::new();
    };
    let path = &flat_path(path);
    let child = matches!(path.start, Start::Alias(_));
    let Some(segs) = resolved_segs(&path.steps, ctx) else {
        return Vec::new();
    };
    let root = root_name(child, anc);
    types_note(
        items.iter().enumerate().map(|(at, item)| {
            let mut here = segs.clone();
            here.push(walk::Seg::Index(at as u64));
            (here, item, location.index(at as u64))
        }),
        &root,
        child,
        true,
    )
    .map(|note| note.brokens(&root, child))
    .unwrap_or_default()
}

#[derive(Clone)]
enum Fv<'a> {
    Val(&'a Value),
    Absent,
    Unusable,
}

#[derive(Clone)]
struct Why {
    segs: Vec<walk::Seg>,
    value: Value,
    kind: &'static str,
}

#[derive(Clone)]
struct Fe<'a> {
    segs: Vec<walk::Seg>,
    item: usize,
    v: Fv<'a>,
    listed: bool,
    at: Location,
    why: Option<Why>,
}

fn fv_gone(v: &Fv) -> bool {
    matches!(v, Fv::Absent | Fv::Unusable | Fv::Val(Value::Null))
}

fn fv_list(v: &Fv) -> bool {
    matches!(v, Fv::Val(Value::Array(_)))
}

fn fv_cause(v: &Fv) -> Cause {
    match v {
        Fv::Absent => Cause::Absent,
        Fv::Val(Value::Null) => Cause::Null,
        _ => Cause::Unusable,
    }
}

fn fv_shown(v: &Fv) -> Value {
    match v {
        Fv::Val(value) => (*value).clone(),
        _ => Value::Null,
    }
}

fn fl_read<'a>(e: &Fe<'a>, seg: &walk::Seg) -> Fe<'a> {
    let mut segs = e.segs.clone();
    segs.push(seg.clone());
    let (v, at) = match (&e.v, seg) {
        (Fv::Val(Value::Object(map)), walk::Seg::Key(key)) => match map.get(key) {
            Some(found) => (Fv::Val(found), e.at.key(key)),
            None => (Fv::Absent, e.at.clone()),
        },
        (Fv::Val(Value::Array(items)), walk::Seg::Index(index)) => {
            match usize::try_from(*index).ok().and_then(|i| items.get(i)) {
                Some(found) => (Fv::Val(found), e.at.index(*index)),
                None => (Fv::Absent, e.at.clone()),
            }
        }
        (Fv::Absent | Fv::Val(Value::Null), _) => (Fv::Absent, e.at.clone()),
        _ => (Fv::Unusable, e.at.clone()),
    };
    let why = match (&e.v, seg) {
        (Fv::Unusable, _) => e.why.clone(),
        (Fv::Val(value), walk::Seg::Key(_)) if !value.is_object() && !value.is_null() => {
            Some(Why {
                segs: e.segs.clone(),
                value: (*value).clone(),
                kind: "an object",
            })
        }
        (Fv::Val(value), walk::Seg::Index(_)) if !value.is_array() && !value.is_null() => {
            Some(Why {
                segs: e.segs.clone(),
                value: (*value).clone(),
                kind: "a list",
            })
        }
        _ => None,
    };
    Fe {
        segs,
        item: e.item,
        v,
        listed: false,
        at,
        why,
    }
}

fn mixed_note(list: &Fe, other: &Fe, root: &str, child: bool) -> Note {
    let field = steps_name(&list.segs[list.item..]);
    let first = from_item_name(&list.segs[..list.item], root, child);
    let second = from_item_name(&other.segs[..other.item], root, child);
    let split = |name: &str| -> Option<(String, String)> {
        let rest = name.strip_prefix("item ")?;
        let (number, of) = rest.split_once(" of ")?;
        (!number.is_empty() && number.chars().all(|c| c.is_ascii_digit()))
            .then(|| (number.to_string(), of.to_string()))
    };
    let shown_second = match (split(&first), split(&second)) {
        (Some((_, a)), Some((number, b))) if a == b && !a.contains(':') => {
            format!("item {number}")
        }
        _ => second,
    };
    Note {
        msg: format!(
            "{field} is a list in {first} but {} in {shown_second}",
            ops::message::print(&fv_shown(&other.v))
        ),
        items: vec![
            (list.segs.clone(), fv_shown(&list.v), list.at.clone()),
            (other.segs.clone(), fv_shown(&other.v), other.at.clone()),
        ],
    }
}

fn fl_broken(e: &Fe, cause: Cause, root: &str, child: bool) -> Broken {
    let shown = fv_shown(&e.v);
    let kind = if shown.is_object() {
        "a list"
    } else {
        "a list or an object"
    };
    let msg = match &e.why {
        Some(why) => ops::message::isnt(
            &from_item_name(&why.segs, root, child),
            &why.value,
            why.kind,
        ),
        None => ops::message::stated(&from_item_name(&e.segs, root, child), cause, &shown, kind),
    };
    Broken {
        msg,
        rank: 0,
        listed: true,
        order: e.segs.clone(),
        path: start_name(&e.segs, root, child),
        cause,
        value: shown,
        location: Some(e.at.render()),
    }
}

fn note_broken(msg: String) -> Broken {
    Broken {
        msg,
        rank: 1,
        listed: false,
        order: Vec::new(),
        path: String::new(),
        cause: Cause::Unusable,
        value: Value::Null,
        location: None,
    }
}

fn fl_walk<'a>(
    base: &Located<'a>,
    segs: &[walk::Seg],
    root: &str,
    child: bool,
) -> Option<(Vec<Entry<'a>>, Vec<Broken>)> {
    let n = segs.len();
    let mut entries = vec![Fe {
        segs: Vec::new(),
        item: 0,
        v: Fv::Val(base.value),
        listed: false,
        at: base.location.clone(),
        why: None,
    }];
    let mut broken: Vec<Broken> = Vec::new();
    let mut notes: Vec<Note> = Vec::new();
    let mut any = false;
    for i in 0..=n {
        let seg = segs.get(i);
        let reads = !matches!(seg, Some(walk::Seg::Index(_)));
        let lists = reads && entries.iter().any(|e| fv_list(&e.v));
        any |= lists;
        if lists
            && let (Some(first), Some(other)) = (
                entries.iter().find(|e| fv_list(&e.v)),
                entries.iter().find(|e| !fv_list(&e.v) && !fv_gone(&e.v)),
            )
        {
            notes.push(mixed_note(first, other, root, child));
        }
        let mut expanded = Vec::new();
        for e in entries {
            if lists && let Fv::Val(Value::Array(items)) = e.v {
                for (j, item) in items.iter().enumerate() {
                    let mut here = e.segs.clone();
                    here.push(walk::Seg::Index(j as u64));
                    let at = here.len();
                    expanded.push(Fe {
                        segs: here,
                        item: at,
                        v: Fv::Val(item),
                        listed: true,
                        at: e.at.index(j as u64),
                        why: None,
                    });
                }
            } else if lists && fv_gone(&e.v) {
                broken.push(fl_broken(&e, fv_cause(&e.v), root, child));
            } else {
                expanded.push(e);
            }
        }
        let Some(seg) = seg else {
            entries = expanded;
            break;
        };
        let mut next = Vec::new();
        for x in expanded {
            let item_read = matches!(seg, walk::Seg::Key(_))
                && x.listed
                && matches!(x.v, Fv::Val(v) if !v.is_object() && !v.is_null());
            if item_read {
                let cause = if fv_list(&x.v) {
                    Cause::NotAnObject
                } else {
                    Cause::Unusable
                };
                let mut said = x.clone();
                said.why = Some(Why {
                    segs: x.segs.clone(),
                    value: fv_shown(&x.v),
                    kind: "an object",
                });
                broken.push(fl_broken(&said, cause, root, child));
            } else {
                next.push(fl_read(&x, seg));
            }
        }
        entries = next;
    }
    if !any {
        return None;
    }
    let mut kept: Vec<Fe<'a>> = Vec::new();
    for e in entries {
        match e.v {
            Fv::Val(value) if !value.is_null() || e.listed => kept.push(e),
            _ => broken.push(fl_broken(&e, fv_cause(&e.v), root, child)),
        }
    }
    if let Some(note) = types_note(
        kept.iter().filter_map(|e| match e.v {
            Fv::Val(value) => Some((e.segs.clone(), value, e.at.clone())),
            _ => None,
        }),
        root,
        child,
        false,
    ) {
        notes.push(note);
    }
    for note in notes {
        broken.extend(note.brokens(root, child));
    }
    broken.sort_by(|a, b| a.order.cmp(&b.order));
    broken.dedup_by(|a, b| {
        a.listed
            && b.listed
            && a.msg.is_empty()
            && a.order == b.order
            && a.cause == b.cause
            && a.value == b.value
            && a.location == b.location
    });
    let entries = kept
        .into_iter()
        .filter_map(|e| match e.v {
            Fv::Val(value) => Some(Entry {
                at: Located {
                    value,
                    location: e.at,
                },
                key: None,
                copies: Vec::new(),
            }),
            _ => None,
        })
        .collect();
    Some((entries, broken))
}

fn every_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    path: &Path,
    anc: &[Anc<'a>],
    source: &Source,
) -> Read<'a> {
    let child = matches!(source, Source::Child { .. });
    let base = if child {
        let Some(parent) = anc.last() else {
            return Read::Failed(Cause::Unusable);
        };
        if std::ptr::eq(parent.at.value, empty) {
            return Read::Failed(Cause::Absent);
        }
        if !matches!(parent.at.value, Value::Object(_) | Value::Array(_)) {
            return Read::Failed(match (flat_path(path).steps.first(), parent.at.value) {
                (Some(Step::Index(_)), Value::Null) => Cause::Absent,
                (Some(Step::Index(_)), _) => Cause::Unusable,
                _ => Cause::NotAnObject,
            });
        }
        parent.at.clone()
    } else {
        input_root(env)
    };
    let path = &flat_path(path);
    let ctx = context(env, input_root(env), anc);
    let Some(segs) = resolved_segs(&path.steps, &ctx) else {
        return Read::Failed(Cause::Unusable);
    };
    let root = root_name(child, anc);
    match fl_walk(&base, &segs, &root, child) {
        Some((entries, broken)) => Read::Entries { entries, broken },
        None => match walk_from(env, path, anc, base) {
            Read::Entries {
                entries,
                mut broken,
            } if child => {
                for each in &mut broken {
                    each.path = start_name(&each.order, &root, true);
                }
                Read::Entries { entries, broken }
            }
            other => other,
        },
    }
}

fn walk_from<'a>(env: &Env<'a>, path: &Path, anc: &[Anc<'a>], base: Located<'a>) -> Read<'a> {
    let ctx = context(env, base.clone(), anc);
    let from = Path {
        start: Start::Subject,
        steps: path.steps.clone(),
    };
    let walked = walk::walk(
        &from,
        &ctx,
        walk::Options {
            if_any: true,
            empty_adds_nothing: false,
        },
    );
    if let Some(outcome) = walked.unreadable {
        let cause = match outcome.cause() {
            Some(Cause::NotAnObject) | None => Cause::Unusable,
            Some(cause) => cause,
        };
        return Read::Entries {
            entries: Vec::new(),
            broken: vec![Broken {
                msg: String::new(),
                rank: 0,
                listed: true,
                order: Vec::new(),
                path: String::new(),
                cause,
                value: match cause {
                    Cause::Unusable => base.value.clone(),
                    _ => Value::Null,
                },
                location: Some(base.location.render()),
            }],
        };
    }
    let last = walked.walked_last();
    let mut broken: Vec<Broken> = walked.failures.iter().map(broken_from).collect();
    let mut entries = Vec::new();
    for item in &walked.items {
        match item.end {
            Some(value) if last || value.is_object() => entries.push(Entry {
                at: Located {
                    value,
                    location: item.end_location.clone(),
                },
                key: None,
                copies: Vec::new(),
            }),
            _ => {
                let miss = if item.miss == Cause::NotAnObject {
                    let null = env
                        .input
                        .pointer(&item.end_location.render())
                        .is_some_and(Value::is_null);
                    if null { Cause::Absent } else { Cause::Unusable }
                } else {
                    item.miss
                };
                broken.push(Broken {
                    rank: 0,
                    listed: true,
                    msg: ops::message::stated(
                        &walked.item_name(&item.end_segs),
                        miss,
                        &item.shown(),
                        "a list or an object",
                    ),
                    order: item.end_segs.clone(),
                    path: walked.name_of(&item.end_segs, false),
                    cause: item.miss,
                    value: item.shown(),
                    location: Some(item.end_location.render()),
                });
            }
        }
    }
    for each in &mut broken {
        if each.cause == Cause::NotAnObject {
            let null = each
                .location
                .as_deref()
                .and_then(|at| env.input.pointer(at))
                .is_some_and(Value::is_null);
            each.cause = if null { Cause::Absent } else { Cause::Unusable };
        }
    }
    if anc.is_empty() {
        for each in &mut broken {
            match each.order.first() {
                Some(walk::Seg::Index(_)) => {
                    each.path = crate::name::name(&Path {
                        start: Start::Input,
                        steps: each.order.iter().map(walk::Seg::to_step).collect(),
                    });
                }
                None => each.path = "$input".to_string(),
                _ => {}
            }
        }
    }
    let root = from_root(anc);
    for each in &mut broken {
        if let Some((number, tail)) = each
            .msg
            .strip_prefix("item ")
            .and_then(|rest| rest.split_once(" of the subject"))
            && (tail.is_empty() || tail.starts_with([':', ' ']))
        {
            each.msg = format!("item {number} of {root}{tail}");
        } else if let Some(rest) = each.msg.strip_prefix("the subject ") {
            each.msg = format!("{root} {rest}");
        }
    }
    broken.sort_by(|a, b| (a.rank, &a.order).cmp(&(b.rank, &b.order)));
    Read::Entries { entries, broken }
}

fn unread_ref_cause(env: &Env, source: &Source, anc: &[Anc]) -> Option<Cause> {
    let ctx = context(env, input_root(env), anc);
    let (path, each_of) = match source {
        Source::Root { path, each_of, .. } | Source::Child { path, each_of, .. } => {
            (path, each_of.as_ref())
        }
    };
    let first_bad_ref = path::step_refs(path).iter().find_map(|reference| {
        let step = Step::Ref(Box::new(reference.clone()));
        path::resolve(&step, &ctx)
            .err()
            .map(|outcome| outcome.cause().unwrap_or(Cause::Unusable))
    });
    if first_bad_ref.is_some() {
        return first_bad_ref;
    }
    let read = read_from(each_of?, &ctx);
    match read.outcome {
        Outcome::Found => None,
        other => Some(other.cause().unwrap_or(Cause::Unusable)),
    }
}

fn read_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    lowered: &Lowered,
    anc: &[Anc<'a>],
) -> Read<'a> {
    if let Some(cause) = unread_ref_cause(env, &lowered.source, anc) {
        return Read::Failed(cause);
    }
    match &lowered.source {
        Source::Root {
            path,
            every: true,
            distinct,
            each_of: None,
            ..
        }
        | Source::Child {
            path,
            every: true,
            distinct,
            each_of: None,
            ..
        } => match every_entries(env, empty, path, anc, &lowered.source) {
            Read::Entries { entries, broken } if *distinct => Read::Entries {
                entries: merged_copies(entries),
                broken,
            },
            other => other,
        },
        Source::Root {
            path,
            each_of: Some(each_of),
            ..
        } => each_of_entries(env, empty, &lowered.source, path, each_of, anc),
        Source::Child {
            path,
            each_of: Some(each_of),
            ..
        } => each_of_entries(env, empty, &lowered.source, path, each_of, anc),
        Source::Root { path, .. } | Source::Child { path, .. } => {
            if matches!(&lowered.source, Source::Child { .. })
                && matches!(path.steps.first(), Some(Step::Index(_)))
                && anc
                    .last()
                    .is_some_and(|parent| std::ptr::eq(parent.at.value, empty))
            {
                return Read::Failed(Cause::Absent);
            }
            if let Some((at, _)) = plain_met(env, &lowered.source, anc) {
                let child = matches!(&lowered.source, Source::Child { .. });
                return Read::Failed(if child && at == 0 {
                    Cause::NotAnObject
                } else {
                    Cause::Unusable
                });
            }
            let ctx = context(env, input_root(env), anc);
            let read = read_from(path, &ctx);
            let scalar_ok =
                !path.steps.is_empty() || matches!(&lowered.source, Source::Child { .. });
            match read.outcome {
                Outcome::Found => match plain_entries(&read, scalar_ok) {
                    Ok(entries) => {
                        let broken = plain_types(&read, path, &ctx, anc);
                        Read::Entries { entries, broken }
                    }
                    Err(cause) => Read::Failed(cause),
                },
                other => Read::Failed(other.cause().unwrap_or(Cause::Unusable)),
            }
        }
    }
}

fn from_name(path: &Path, source: &Source, anc: &[Anc], ctx: &Ctx, resolved: bool) -> String {
    let mut name = if resolved {
        ops::message::resolved_name(path, ctx)
    } else {
        crate::name::name(path)
    };
    if let Some(bare) = name.strip_prefix("$input.") {
        name = bare.to_string();
    }
    if let (Source::Child { .. }, Some(parent)) = (source, anc.last())
        && let Some(rest) = name.strip_prefix(&format!("{}.", parent.name))
    {
        name = rest.to_string();
    }
    name = name.replace(" of $input.", " of ");
    if let (Source::Child { .. }, Some(parent)) = (source, anc.last()) {
        name = name.replace(&format!(" of {}.", parent.name), " of ");
    }
    if name.is_empty() {
        from_root(anc)
    } else {
        name
    }
}

fn from_root(anc: &[Anc]) -> String {
    anc.last()
        .map_or_else(|| "$input".to_string(), |parent| parent.name.clone())
}

fn ref_fits(value: &Value, kind: &str) -> bool {
    match kind {
        "text" => value.is_string(),
        _ => matches!(value, Value::Array(items) if items.iter().all(Value::is_string)),
    }
}

type RefState<'a> = (String, Outcome, Option<Value>, &'a str, Option<String>);

fn ref_message(env: &Env, lowered: &Lowered, anc: &[Anc], cause: Cause) -> Option<String> {
    let (Source::Root { path, each_of, .. } | Source::Child { path, each_of, .. }) =
        &lowered.source;
    let ctx = context(env, input_root(env), anc);
    let mut refs: Vec<Path> = path::step_refs(path);
    refs.sort_by_key(crate::name::name);
    refs.dedup();
    let mut listed: Vec<(Path, &str)> = refs.into_iter().map(|r| (r, "text")).collect();
    if let Some(keys) = each_of {
        listed.push((keys.clone(), "a list of text"));
    }
    let states: Vec<RefState> = listed
        .iter()
        .map(|(reference, kind)| {
            let read = read_from(reference, &ctx);
            let blocked = path::start_of(&reference.start, &ctx)
                .is_ok_and(|(start, _, _)| start.is_object())
                .then(|| ops::message::blocked_of(reference, &ctx).into_iter().next())
                .flatten();
            (
                crate::name::name(reference),
                read.outcome,
                read.value.cloned(),
                *kind,
                blocked,
            )
        })
        .collect();
    let says = |(name, outcome, value, kind, blocked): &RefState, want: Option<Cause>| match (
        *outcome, value,
    ) {
        (Outcome::Unusable, _) if want.is_none_or(|c| c == Cause::Unusable) => blocked.clone(),
        (Outcome::Absent, _) if want.is_none_or(|c| c == Cause::Absent) => {
            Some(format!("{name} is missing"))
        }
        (Outcome::Null, _) if want.is_none_or(|c| c == Cause::Null) => {
            Some(format!("{name} is null"))
        }
        (Outcome::Found, Some(value))
            if want.is_none_or(|c| c == Cause::Unusable) && !ref_fits(value, kind) =>
        {
            Some(ops::message::isnt(name, value, kind))
        }
        _ => None,
    };
    let unread_params = ctx.params.filter(|p| !p.is_object() && !p.is_null());
    if let Some(params) = unread_params
        && listed.iter().any(|(r, _)| r.start == Start::Params)
    {
        let mut said: Vec<String> = Vec::new();
        for ((reference, _), state) in listed.iter().zip(&states) {
            let (name, outcome, value, kind, _) = state;
            let text = if reference.start != Start::Params {
                says(state, None)
            } else if let (Outcome::Found, Some(found)) = (outcome, value)
                && !ref_fits(found, kind)
            {
                Some(ops::message::isnt(name, found, kind))
            } else {
                Some(
                    ops::message::params_break(reference, params, &ctx)
                        .unwrap_or_else(|| ops::message::isnt("$params", params, "an object")),
                )
            };
            if let Some(text) = text
                && !said.contains(&text)
            {
                said.push(text);
            }
        }
        return (!said.is_empty()).then(|| ops::message::joined(said));
    }
    let mut said: Vec<String> = states
        .iter()
        .filter_map(|state| says(state, Some(cause)))
        .collect();
    if said.is_empty() {
        said = states
            .iter()
            .filter_map(|state| says(state, None))
            .collect();
    }
    (!said.is_empty()).then(|| ops::message::joined(said))
}

fn target_message(
    env: &Env,
    empty: &Value,
    source: &Source,
    anc: &[Anc],
    cause: Cause,
) -> Option<String> {
    let (Source::Root { path, .. } | Source::Child { path, .. }) = source;
    let child = matches!(source, Source::Child { .. });
    let doc: &Value = if child {
        anc.last()?.at.value
    } else {
        env.input
    };
    let root = from_root(anc);
    if child {
        if std::ptr::eq(doc, empty) {
            return Some(format!("{root} is missing"));
        }
        match doc {
            Value::Null => return Some(format!("{root} is null")),
            Value::Object(_) | Value::Array(_) => {}
            _ => {
                let kind = if cause == Cause::NotAnObject {
                    "an object"
                } else {
                    "a list or an object"
                };
                return Some(ops::message::isnt(&root, doc, kind));
            }
        }
    }
    let ctx = context(env, input_root(env), anc);
    match (doc, path.steps.first()) {
        (Value::Array(items), Some(Step::Index(at)))
            if usize::try_from(*at).is_ok_and(|at| at >= items.len()) =>
        {
            return Some(format!("item {} of {root} is missing", at + 1));
        }
        (Value::Array(items), Some(Step::Key(key))) if cause == Cause::NotAnObject => {
            let said: Vec<String> = items
                .iter()
                .enumerate()
                .filter(|(_, item)| !item.is_object())
                .map(|(at, _)| {
                    format!(
                        "item {} of {root}: {}",
                        at + 1,
                        ops::message::isnt(
                            &crate::name::key_text(key),
                            &Value::Null,
                            "a list or an object"
                        )
                    )
                })
                .collect();
            if !said.is_empty() {
                return Some(ops::message::joined(said));
            }
        }
        (Value::Object(_), _) if cause == Cause::Unusable => {
            if let Some(k) = path
                .steps
                .iter()
                .position(|step| matches!(step, Step::Index(_)))
            {
                let Some(Step::Index(at)) = path.steps.get(k) else {
                    return None;
                };
                let prefix = Path {
                    start: path.start.clone(),
                    steps: path.steps[..k].to_vec(),
                };
                let read = read_from(&prefix, &ctx);
                if read.outcome == Outcome::Found && read.value.is_some_and(Value::is_object) {
                    let shown = if k == 0 {
                        root.clone()
                    } else {
                        from_name(&prefix, source, anc, &ctx, true)
                    };
                    return Some(ops::message::isnt(
                        &format!("item {} of {shown}", at + 1),
                        &Value::Null,
                        "a list or an object",
                    ));
                }
            }
        }
        _ => {}
    }
    let read = read_from(path, &ctx);
    let name = from_name(path, source, anc, &ctx, !read.step_unreadable);
    match cause {
        Cause::Absent | Cause::Null => {
            let want = if cause == Cause::Absent {
                Outcome::Absent
            } else {
                Outcome::Null
            };
            let keys = ops::message::key_states_of(path, &ctx, want).join(", and ");
            if !keys.is_empty() {
                return Some(keys);
            }
            let word = if cause == Cause::Absent {
                "missing"
            } else {
                "null"
            };
            Some(format!("{name} is {word}"))
        }
        Cause::Unusable => {
            let faults = ops::message::key_faults_of(path, &ctx);
            if !faults.is_empty() {
                return Some(faults.join(", and "));
            }
            let value = read.value?;
            let kind = match value {
                Value::Array(_) => return None,
                Value::Object(_) => "a list",
                _ => "a list or an object",
            };
            Some(ops::message::isnt(&name, value, kind))
        }
        Cause::NotAnObject => {
            let parent = anc.last()?.at.value;
            if parent.is_array() || parent.is_object() {
                return None;
            }
            Some(ops::message::isnt(&root, parent, "an object"))
        }
        _ => None,
    }
}

fn walk_message(env: &Env, empty: &Value, lowered: &Lowered, anc: &[Anc]) -> Option<String> {
    let (Source::Root { path, .. } | Source::Child { path, .. }) = &lowered.source;
    match &lowered.source {
        Source::Root { every: true, .. }
        | Source::Child { every: true, .. }
        | Source::Root {
            each_of: Some(_), ..
        }
        | Source::Child {
            each_of: Some(_), ..
        } => return None,
        _ => {}
    }
    let base = match (&lowered.source, anc.last()) {
        (Source::Child { .. }, Some(parent)) => {
            if std::ptr::eq(parent.at.value, empty)
                || !matches!(parent.at.value, Value::Object(_) | Value::Array(_))
            {
                return None;
            }
            parent.at.clone()
        }
        (Source::Child { .. }, None) => return None,
        _ => input_root(env),
    };
    let Read::Entries { broken, .. } = walk_from(env, path, anc, base) else {
        return None;
    };
    let mut said: Vec<&Broken> = broken.iter().filter(|b| !b.msg.is_empty()).collect();
    said.sort_by(|a, b| (a.rank, &a.order).cmp(&(b.rank, &b.order)));
    if said.is_empty() {
        return None;
    }
    Some(ops::message::joined(
        said.iter().map(|b| b.msg.clone()).collect(),
    ))
}

fn from_message(
    env: &Env,
    empty: &Value,
    lowered: &Lowered,
    anc: &[Anc],
    cause: Cause,
) -> Option<String> {
    ref_message(env, lowered, anc, cause)
        .or_else(|| plain_met(env, &lowered.source, anc).map(|(_, said)| said))
        .or_else(|| keyed_message(env, &lowered.source, anc))
        .or_else(|| walk_message(env, empty, lowered, anc))
        .or_else(|| target_message(env, empty, &lowered.source, anc, cause))
}

fn object_target_message(env: &Env, lowered: &Lowered, anc: &[Anc]) -> Option<String> {
    let (Source::Root { path, .. } | Source::Child { path, .. }) = &lowered.source;
    let ctx = context(env, input_root(env), anc);
    let read = read_from(path, &ctx);
    match (read.outcome, read.value) {
        (Outcome::Found, Some(value @ Value::Object(_))) => {
            let name = from_name(path, &lowered.source, anc, &ctx, true);
            Some(ops::message::isnt(&name, value, "a list"))
        }
        _ => None,
    }
}

fn order_rank(value: &Value) -> u8 {
    match value {
        Value::Null => 0,
        Value::Bool(_) => 1,
        Value::Number(_) => 2,
        Value::String(_) => 3,
        Value::Array(_) => 4,
        Value::Object(_) => 5,
    }
}

pub(crate) fn order(a: &Value, b: &Value) -> Ordering {
    match (a, b) {
        (Value::Bool(x), Value::Bool(y)) => x.cmp(y),
        (Value::Number(x), Value::Number(y)) => value::compare_numbers(x, y).unwrap_or_else(|| {
            value::is_readable(y)
                .cmp(&value::is_readable(x))
                .then_with(|| x.to_string().cmp(&y.to_string()))
        }),
        (Value::String(x), Value::String(y)) => x.cmp(y),
        (Value::Array(x), Value::Array(y)) => {
            for (p, q) in x.iter().zip(y) {
                let found = order(p, q);
                if found != Ordering::Equal {
                    return found;
                }
            }
            x.len().cmp(&y.len())
        }
        (Value::Object(x), Value::Object(y)) => {
            let mut left: Vec<(&String, &Value)> = x.iter().collect();
            let mut right: Vec<(&String, &Value)> = y.iter().collect();
            left.sort_by(|p, q| p.0.cmp(q.0));
            right.sort_by(|p, q| p.0.cmp(q.0));
            for (p, q) in left.iter().zip(&right) {
                let found = p.0.cmp(q.0).then_with(|| order(p.1, q.1));
                if found != Ordering::Equal {
                    return found;
                }
            }
            left.len().cmp(&right.len())
        }
        _ => order_rank(a).cmp(&order_rank(b)),
    }
}

pub(crate) fn merge_inputs(mut inputs: Vec<Input>) -> Vec<Input> {
    inputs.sort_by(|a, b| {
        a.name
            .cmp(&b.name)
            .then_with(|| order(&a.value, &b.value))
            .then_with(|| {
                let left = a.part.as_ref().map(|p| (&p.name, &p.id));
                let right = b.part.as_ref().map(|p| (&p.name, &p.id));
                match (left, right) {
                    (None, None) => Ordering::Equal,
                    (None, Some(_)) => Ordering::Less,
                    (Some(_), None) => Ordering::Greater,
                    (Some(p), Some(q)) => p.0.cmp(q.0).then_with(|| order(p.1, q.1)),
                }
            })
            .then_with(|| a.locations.cmp(&b.locations))
    });
    inputs.dedup();
    inputs
}

fn merged_inputs(inputs: Vec<Input>) -> Vec<Value> {
    let mut entries: Vec<Value> = merge_inputs(inputs).iter().map(Input::to_json).collect();
    entries.dedup();
    entries
}

fn inputs_in_order(inputs: Vec<Input>) -> Vec<Value> {
    let mut kept: Vec<Value> = Vec::new();
    for input in inputs {
        let entry = input.to_json();
        if !kept.contains(&entry) {
            kept.push(entry);
        }
    }
    kept
}

struct Applied {
    matched: bool,
    cause: Cause,
    inputs: Vec<Value>,
    failed_assertions: Option<Value>,
    failed_items: Option<Value>,
    message: Option<String>,
}

fn answers_presence(filter: &Filter, verdict: &Verdict) -> bool {
    matches!(&filter.check, Check::Present(present) if !present.missing)
        && verdict.cause == Cause::Value
}

fn apply(filters: &[Filter], ctx: &Ctx, unreadable: bool) -> Applied {
    let mut failed_items = None;
    let mut said: Vec<String> = Vec::new();
    let verdicts: Vec<(&Filter, Verdict)> = filters
        .iter()
        .map(|filter| {
            let ran = ops::run_full(&filter.check, ctx);
            let mut verdict = ran.verdict;
            failed_items = ran.failed_items.map(Value::Array);
            let mut own = ran.message;
            if unreadable {
                verdict.cause = Cause::Unusable;
                failed_items = failed_items.take().map(|_| Value::Array(Vec::new()));
                own = None;
            }
            if !verdict.passed() {
                said.push(
                    own.unwrap_or_else(|| ops::message::message(&filter.check, ctx, &verdict)),
                );
            }
            (filter, verdict)
        })
        .collect();
    let failing: Vec<Cause> = verdicts
        .iter()
        .filter(|(_, v)| !v.passed())
        .map(|(_, v)| v.cause)
        .collect();
    let matched = failing.is_empty();
    let cause = if matched {
        Cause::Satisfied
    } else if verdicts.iter().any(|(f, v)| answers_presence(f, v))
        || failing.iter().all(|c| *c == Cause::Value)
    {
        Cause::Value
    } else {
        Cause::worst(failing.iter().copied()).unwrap_or(Cause::Value)
    };
    let failed_assertions = (filters.len() > 1).then(|| {
        Value::Array(
            verdicts
                .iter()
                .filter(|(_, v)| !v.passed())
                .map(|(f, v)| json!({"assertion": f.text, "cause": v.cause.name()}))
                .collect(),
        )
    });
    let inputs = merged_inputs(
        verdicts
            .iter()
            .flat_map(|(_, v)| v.inputs.iter().cloned())
            .collect(),
    );
    let mut once: Vec<String> = Vec::new();
    for text in said {
        if !once.contains(&text) {
            once.push(text);
        }
    }
    let message = if matched {
        None
    } else if once.is_empty() {
        Some(format!("{} doesn't match", ctx.subject_label()))
    } else {
        Some(once.join("; "))
    };
    Applied {
        matched,
        message,
        cause,
        inputs,
        failed_assertions,
        failed_items: if filters.len() == 1 {
            failed_items
        } else {
            None
        },
    }
}

fn id_of(lowered: &Lowered, entry: &Entry, ctx: &Ctx) -> (Value, Option<String>) {
    if let Some(key) = &entry.key {
        return (json!(key), Some(entry.at.location.render()));
    }
    if !entry.at.value.is_object() {
        return (entry.at.value.clone(), Some(entry.at.location.render()));
    }
    match &lowered.id {
        None => (entry.at.value.clone(), Some(entry.at.location.render())),
        Some(steps) => {
            let read = read_from(
                &Path {
                    start: Start::Subject,
                    steps: steps.clone(),
                },
                ctx,
            );
            let location = read.location.as_ref().map(Location::render);
            match (read.outcome, read.value) {
                (Outcome::Found, Some(found)) => (found.clone(), location),
                _ => (Value::Null, location),
            }
        }
    }
}

struct Judged<'a> {
    entry: Entry<'a>,
    id: Value,
    id_location: Option<String>,
    applied: Option<Applied>,
}

impl Judged<'_> {
    fn in_scope(&self) -> bool {
        self.applied.as_ref().is_none_or(|applied| applied.matched)
    }
}

fn judge<'a>(
    env: &Env<'a>,
    lowered: &Lowered,
    entries: Vec<Entry<'a>>,
    anc: &[Anc<'a>],
) -> Vec<Judged<'a>> {
    entries
        .into_iter()
        .map(|entry| {
            let mut ctx = context(env, entry.at.clone(), anc);
            let (id, id_location) = id_of(lowered, &entry, &ctx);
            ctx.label = Some(env.subject.to_string());
            let applied = (!lowered.filters.is_empty())
                .then(|| apply(&lowered.filters, &ctx, !env.unreadable.is_empty()));
            Judged {
                entry,
                id,
                id_location,
                applied,
            }
        })
        .collect()
}

fn same_id(a: &Value, b: &Value) -> bool {
    match value::equal(a, b) {
        Some(same) => same,
        None => order(a, b) == Ordering::Equal,
    }
}

fn repeated_ids(judged: &[Judged]) -> (Vec<Value>, Vec<String>) {
    let mut sorted: Vec<(usize, &Judged)> = judged.iter().enumerate().collect();
    sorted.sort_by(|a, b| order(&a.1.id, &b.1.id));
    let mut groups: Vec<Vec<(usize, &Judged)>> = Vec::new();
    for item in sorted {
        match groups.last_mut() {
            Some(group) if same_id(&group[0].1.id, &item.1.id) => group.push(item),
            _ => groups.push(vec![item]),
        }
    }
    let several = judged.len() > 1;
    let mut repeated: Vec<Vec<(usize, &Judged)>> = groups
        .into_iter()
        .filter(|g| g.len() > 1 || (several && !value::all_readable(&g[0].1.id)))
        .collect();
    repeated.sort_by(|a, b| {
        json_text(&a[0].1.id)
            .cmp(&json_text(&b[0].1.id))
            .then_with(|| order(&a[0].1.id, &b[0].1.id))
    });
    let mut ids = Vec::new();
    let mut locations = Vec::new();
    for group in &mut repeated {
        ids.push(group[0].1.id.clone());
        group.sort_by_key(|(index, _)| *index);
        for (_, item) in group.iter() {
            if let Some(at) = &item.id_location {
                let copies: Vec<String> = item.entry.copies.iter().map(Location::render).collect();
                locations.extend(value::copied_locations(
                    std::slice::from_ref(at),
                    &item.entry.at.location.render(),
                    &copies,
                ));
            }
        }
    }
    (ids, locations)
}

fn applies_row(env: &Env, judged: &Judged, applied: &Applied, anc: &[Anc]) -> Row {
    let mut row = row_of(
        env.requirement_name,
        env.requirement,
        "$applies",
        applied.cause,
        applied.inputs.clone(),
    );
    row.subject_id = judged.id.clone();
    row.failed_assertions = applied.failed_assertions.clone();
    row.failed_items = applied.failed_items.clone();
    row.message = applied.message.clone();
    with_in(row, anc)
}

fn min_row(env: &Env, count: u64, locations: &[String], read: Option<Cause>) -> Row {
    let read = if env.unreadable.is_empty() {
        read
    } else {
        Some(Cause::Unusable)
    };
    min_subjects_row(
        env.requirement_name,
        env.requirement,
        count,
        locations,
        read,
        env.unreadable.clone(),
    )
}

fn evaluate_level(env: &Env, lowered: &Lowered, anc: &[Anc], empty: &Value) -> Evaluation {
    let (entries, broken) = match read_entries(env, empty, lowered, anc) {
        Read::Entries { entries, broken } => (entries, broken),
        Read::Failed(cause) => {
            let mut level = failed_level(env, anc, cause, true);
            if let Some(said) = from_message(env, empty, lowered, anc, cause) {
                for row in &mut level.min_subjects {
                    row.message = Some(said.clone());
                }
            }
            if is_every(&lowered.source) {
                for row in &mut level.min_subjects {
                    row.failed_items = Some(Value::Array(Vec::new()));
                }
            }
            return level;
        }
    };
    let judged = judge(env, lowered, entries, anc);
    let (repeated, id_locations) = repeated_ids(&judged);
    let in_scope: Vec<&Judged> = judged.iter().filter(|j| j.in_scope()).collect();
    let locations: Vec<String> = in_scope
        .iter()
        .flat_map(|j| {
            std::iter::once(j.entry.at.location.render())
                .chain(j.entry.copies.iter().map(Location::render))
        })
        .collect();
    let every = is_every(&lowered.source);
    let read = Cause::worst(broken.iter().map(|b| b.cause));
    let mut min = min_row(env, in_scope.len() as u64, &locations, read);
    let mut explained = false;
    if !every && env.unreadable.is_empty() && read.is_some() && min.cause != Cause::Satisfied {
        let said: Vec<String> = broken
            .iter()
            .filter(|b| !b.msg.is_empty())
            .map(|b| b.msg.clone())
            .collect();
        if !said.is_empty() {
            min.message = Some(ops::message::joined(said));
            explained = true;
        }
    }
    if !every
        && env.unreadable.is_empty()
        && min.cause != Cause::Satisfied
        && !explained
        && let Some(said) = object_target_message(env, lowered, anc)
    {
        min.message = Some(said);
    }
    if !every
        && env.unreadable.is_empty()
        && min.cause != Cause::Satisfied
        && broken.iter().any(|b| b.listed && b.rank == 1)
    {
        min.failed_items = Some(Value::Array(
            broken
                .iter()
                .filter(|b| b.listed && b.rank == 1)
                .map(Broken::to_json)
                .collect(),
        ));
    }
    if every {
        let listed = if env.unreadable.is_empty() {
            broken
                .iter()
                .filter(|b| b.listed)
                .map(Broken::to_json)
                .collect()
        } else {
            Vec::new()
        };
        min.failed_items = Some(Value::Array(listed));
        if env.unreadable.is_empty() && min.cause != Cause::Satisfied {
            let mut sorted: Vec<&Broken> = broken.iter().filter(|b| !b.msg.is_empty()).collect();
            sorted.sort_by(|a, b| (a.rank, &a.order).cmp(&(b.rank, &b.order)));
            if !sorted.is_empty() {
                min.message = Some(ops::message::joined(
                    sorted.iter().map(|b| b.msg.clone()).collect(),
                ));
            }
        }
    }
    let unique = unique_ids_row(
        env.requirement_name,
        env.requirement,
        repeated,
        &id_locations,
    );
    let applies = judged
        .iter()
        .filter_map(|j| {
            j.applied.as_ref().map(|a| {
                let mut rows = vec![applies_row(env, j, a, anc)];
                for at in j.entry.at_each().into_iter().skip(1) {
                    let mut ctx = context(env, at, anc);
                    ctx.label = Some(env.subject.to_string());
                    let applied = apply(&lowered.filters, &ctx, !env.unreadable.is_empty());
                    rows.push(applies_row(env, j, &applied, anc));
                }
                merged_rows(rows)
            })
        })
        .collect();
    let subject_rows = in_scope
        .iter()
        .map(|j| {
            let runs: Vec<Vec<Row>> = j
                .entry
                .at_each()
                .into_iter()
                .map(|at| check_rows(env, j, at, anc))
                .collect();
            let mut runs = runs.into_iter();
            let first = runs.next().unwrap_or_default();
            let rest: Vec<Vec<Row>> = runs.collect();
            first
                .into_iter()
                .enumerate()
                .map(|(i, row)| {
                    let mut all = vec![row];
                    all.extend(rest.iter().filter_map(|run| run.get(i).cloned()));
                    merged_rows(all)
                })
                .collect::<Vec<Row>>()
        })
        .filter(|rows| !rows.is_empty())
        .collect();
    Evaluation {
        total: judged.len() as u64,
        matching: in_scope.len() as u64,
        min_subjects: vec![with_in(min, anc)],
        unique_ids: vec![with_in(unique, anc)],
        unique_ancestor_ids: Vec::new(),
        applies,
        subject_rows,
    }
}

fn read_from<'a>(path: &Path, ctx: &Ctx<'a>) -> path::Read<'a> {
    let mut read = path::read(path, ctx);
    if path.start == Start::Input && read.outcome == Outcome::NotAnObject {
        read.outcome = Outcome::Unusable;
    }
    if read.outcome == Outcome::Null && read.value.is_none() && !read.step_unreadable {
        read.outcome = Outcome::Absent;
    }
    read
}

fn check_rows<'a>(
    env: &Env<'a>,
    judged: &Judged<'a>,
    at: Located<'a>,
    anc: &[Anc<'a>],
) -> Vec<Row> {
    let mut ctx = context(env, at, anc);
    ctx.label = Some(env.subject.to_string());
    env.checks
        .iter()
        .filter(|(name, _)| !name.starts_with('$'))
        .filter_map(|(name, read)| {
            read.plan.as_ref().map(|plan| {
                let mut row = check_row(env, name, plan, &ctx, judged, anc);
                if row.message.as_deref() == Some(ops::message::FALLBACK) {
                    let named = (row.cause == Cause::Unusable)
                        .then(|| {
                            plan.items.iter().find_map(|item| {
                                ops::message::params_that_arent_an_object(&item.check, &ctx)
                            })
                        })
                        .flatten();
                    row.message =
                        Some(named.unwrap_or_else(|| format!("{} is false", read.expression)));
                }
                row
            })
        })
        .collect()
}

fn check_row(env: &Env, name: &str, plan: &Plan, ctx: &Ctx, judged: &Judged, anc: &[Anc]) -> Row {
    let mut failed_items = None;
    let mut said: Vec<Option<String>> = Vec::new();
    let checks: Vec<Check> = plan
        .items
        .iter()
        .map(|item| match (&ctx.label, ctx.subject.value.is_array()) {
            (Some(label), true) => ops::list_start::read(&item.check, label),
            _ => item.check.clone(),
        })
        .collect();
    let verdicts: Vec<Verdict> = checks
        .iter()
        .map(|check| {
            let ran = ops::run_full(check, ctx);
            failed_items = ran.failed_items.map(Value::Array);
            let mut verdict = ran.verdict;
            let mut own = ran.message;
            if !env.unreadable.is_empty() {
                verdict.cause = Cause::Unusable;
                failed_items = failed_items.take().map(|_| Value::Array(Vec::new()));
                own = None;
            }
            said.push(own);
            verdict
        })
        .collect();
    let cause = Cause::worst(verdicts.iter().map(|v| v.cause)).unwrap_or(Cause::Satisfied);
    let read: Vec<Input> = verdicts
        .iter()
        .flat_map(|v| v.inputs.iter().cloned())
        .collect();
    let inputs = if plan.all_of {
        merged_inputs(read)
    } else {
        inputs_in_order(read)
    };
    let mut row = row_of(env.requirement_name, env.requirement, name, cause, inputs);
    row.subject_id = judged.id.clone();
    if cause != Cause::Satisfied {
        let messages: Vec<String> = checks
            .iter()
            .zip(&verdicts)
            .zip(&said)
            .filter(|((_, v), _)| !v.passed())
            .map(|((check, v), own)| match own {
                Some(text) => text.clone(),
                None => ops::message::message(check, ctx, v),
            })
            .collect();
        let mut once: Vec<String> = Vec::new();
        for text in messages {
            if !once.contains(&text) {
                once.push(text);
            }
        }
        row.message = Some(once.join("; "));
    }
    if plan.items.len() == 1 {
        row.failed_items = failed_items;
    }
    if plan.all_of {
        row.failed_assertions = Some(Value::Array(
            plan.items
                .iter()
                .zip(&verdicts)
                .filter(|(_, v)| !v.passed())
                .map(|(item, v)| json!({"assertion": item.text, "cause": v.cause.name()}))
                .collect(),
        ));
    }
    with_in(row, anc)
}

fn every_subject(env: &Env) -> bool {
    env.reading
        .lowered(env.subject)
        .is_some_and(|lowered| is_every(&lowered.source))
}

fn is_every(source: &Source) -> bool {
    matches!(
        source,
        Source::Root { every: true, .. } | Source::Child { every: true, .. }
    )
}

fn failed_level(env: &Env, anc: &[Anc], cause: Cause, with_unique: bool) -> Evaluation {
    let mut min = min_row(env, 0, &[], Some(cause));
    if every_subject(env) {
        min.failed_items = Some(Value::Array(Vec::new()));
    }
    let unique = unique_ids_row(env.requirement_name, env.requirement, Vec::new(), &[]);
    Evaluation {
        total: 0,
        matching: 0,
        min_subjects: vec![with_in(min, anc)],
        unique_ids: if with_unique {
            vec![with_in(unique, anc)]
        } else {
            Vec::new()
        },
        unique_ancestor_ids: Vec::new(),
        applies: Vec::new(),
        subject_rows: Vec::new(),
    }
}

fn ancestor_level(
    env: &Env,
    ancestor: &str,
    repeated: Vec<Value>,
    locations: &[String],
    anc: &[Anc],
) -> Evaluation {
    let row = unique_ancestor_ids_row(
        env.requirement_name,
        env.requirement,
        ancestor,
        repeated,
        locations,
    );
    Evaluation {
        unique_ancestor_ids: vec![with_in(row, anc)],
        ..Evaluation::default()
    }
}

fn descend<'a>(
    env: &Env<'a>,
    chain: &[String],
    anc: &mut Vec<Anc<'a>>,
    empty: &'a Value,
) -> Vec<Evaluation> {
    let Some(parent) = chain.first() else {
        return match env.reading.lowered(env.subject) {
            Some(lowered) => vec![evaluate_level(env, lowered, anc, empty)],
            None => Vec::new(),
        };
    };
    let unread = |cause: Cause, anc: &[Anc]| {
        vec![
            ancestor_level(env, parent, Vec::new(), &[], anc),
            failed_level(env, anc, cause, anc.is_empty()),
        ]
    };
    if !env.unreadable.is_empty() {
        return unread(Cause::Unusable, anc);
    }
    let Some(lowered) = env.reading.lowered(parent) else {
        return unread(Cause::Unusable, anc);
    };
    let (entries, broken) = match read_entries(env, empty, lowered, anc) {
        Read::Entries { entries, broken } => (entries, broken),
        Read::Failed(cause) => return unread(cause, anc),
    };
    let keyed_child = matches!(
        &lowered.source,
        Source::Child {
            each_of: Some(_),
            ..
        }
    );
    if !keyed_child
        && let Some(cause) = Cause::worst(broken.iter().filter(|b| b.rank == 0).map(|b| b.cause))
    {
        return unread(cause, anc);
    }
    let judged_all = judge(env, lowered, entries, anc);
    let (repeated, id_locations) = repeated_ids(&judged_all);
    let mut out = vec![ancestor_level(env, parent, repeated, &id_locations, anc)];
    for judged in judged_all {
        let mut here = Anc {
            name: parent.clone(),
            id: judged.id.clone(),
            at: judged.entry.at.clone(),
        };
        let cause = match &judged.applied {
            None => Cause::Satisfied,
            Some(applied) => applied.cause,
        };
        if cause == Cause::Satisfied {
            let mut runs = Vec::new();
            for at in judged.entry.at_each() {
                anc.push(Anc { at, ..here.clone() });
                runs.push(descend(env, &chain[1..], anc, empty));
                anc.pop();
            }
            out.extend(merged_evaluations(runs));
        } else if cause != Cause::Value {
            here.name = parent.clone();
            anc.push(here);
            out.push(failed_level(env, anc, cause, false));
            anc.pop();
        }
    }
    out
}

fn merge(evaluations: Vec<Evaluation>) -> Evaluation {
    let mut merged = Evaluation::default();
    for evaluation in evaluations {
        merged.total += evaluation.total;
        merged.matching += evaluation.matching;
        merged.min_subjects.extend(evaluation.min_subjects);
        merged.unique_ids.extend(evaluation.unique_ids);
        merged
            .unique_ancestor_ids
            .extend(evaluation.unique_ancestor_ids);
        merged.applies.extend(evaluation.applies);
        merged.subject_rows.extend(evaluation.subject_rows);
    }
    merged
}

fn chain_of(reading: &Reading, subject: &str) -> Vec<String> {
    let mut chain = Vec::new();
    let mut at = subject.to_string();
    while let Some(Relation::Child(parent)) = reading.infos.get(&at).map(|i| i.relation.clone()) {
        if chain.contains(&parent) {
            break;
        }
        chain.push(parent.clone());
        at = parent;
    }
    chain.reverse();
    chain
}

pub fn find_subjects(
    reading: &Reading,
    _policy: &Policy,
    requirement_name: &str,
    requirement: &Requirement,
    input: &Value,
    params: &Value,
) -> Evaluation {
    let SubjectName::Named(subject) = &requirement.subject else {
        return no_subjects(requirement_name, requirement, params);
    };
    if reading.unsupported(subject) {
        return nothing_readable(requirement_name, requirement, params);
    }
    if reading.lowered(subject).is_none() {
        return no_subjects(requirement_name, requirement, params);
    }
    let env = Env {
        reading,
        requirement_name,
        requirement,
        subject,
        checks: read_checks(reading, requirement),
        input,
        params: (!params.is_null()).then_some(params),
        unreadable: unreadable_params(params),
    };
    let empty = &path::ABSENT;
    let chain = chain_of(reading, subject);
    let mut anc = Vec::new();
    let evaluations = descend(&env, &chain, &mut anc, empty);
    if evaluations.iter().all(|e| e.min_subjects.is_empty()) {
        let mut found = none_found(&env);
        found.unique_ancestor_ids = evaluations
            .into_iter()
            .flat_map(|e| e.unique_ancestor_ids)
            .collect();
        return found;
    }
    merge(evaluations)
}

fn nothing_readable(name: &str, requirement: &Requirement, params: &Value) -> Evaluation {
    let mut evaluation = no_subjects(name, requirement, params);
    for row in &mut evaluation.min_subjects {
        row.cause = Cause::Unusable;
    }
    evaluation
}

fn none_found(env: &Env) -> Evaluation {
    let mut min = min_row(env, 0, &[], None);
    if every_subject(env) {
        min.failed_items = Some(Value::Array(Vec::new()));
    }
    let unique = unique_ids_row(env.requirement_name, env.requirement, Vec::new(), &[]);
    Evaluation {
        total: 0,
        matching: 0,
        min_subjects: vec![min],
        unique_ids: vec![unique],
        unique_ancestor_ids: Vec::new(),
        applies: Vec::new(),
        subject_rows: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use crate::SPEC;
    use crate::report;
    use serde_json::{Value, json};

    fn policy(subjects: Value, min: Value) -> Value {
        json!({
            "ergo_spec": SPEC,
            "subjects": subjects,
            "requirements": {"s": {"subject": "thing", "min_subjects": min, "checks": {"c": "x exists"}}}
        })
    }

    fn rows(report: &Value, check: &str) -> Vec<Value> {
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|row| row["check"] == check)
            .cloned()
            .collect()
    }

    fn run(subjects: Value, input: Value) -> Value {
        report(&input, &policy(subjects, json!(0)), &json!({}))
    }

    fn input_of(row: &Value, at: usize) -> Value {
        row["inputs"][at].clone()
    }

    #[test]
    fn each_item_of_the_list_is_a_subject_with_its_id_and_location() {
        let r = run(
            json!({"thing": {"from": "every data.ds", "identified_by": "id"}}),
            json!({"data": {"ds": [{"id": "b"}, {"id": 7}]}}),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(
            input_of(min, 0),
            json!({"name": "in-scope thing count", "value": 2, "locations": ["/data/ds/0", "/data/ds/1"]})
        );
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 2, "matching": 2})
        );
    }

    #[test]
    fn a_missing_path_fails_min_subjects_with_the_outcome_even_with_min_zero() {
        let r = run(json!({"thing": {"from": "ds"}}), json!({}));
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!("absent"));
        assert_eq!(min["passed"], json!(false));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    }

    #[test]
    fn a_from_line_that_ends_on_a_number_gives_it_as_one_subject_and_null_is_null() {
        let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": 3}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("satisfied"));
        let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": null}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("null"));
    }

    #[test]
    fn an_object_is_the_only_subject() {
        let r = run(
            json!({"thing": {"identified_by": "id"}}),
            json!({"thing": {"id": 1}}),
        );
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 1, "matching": 1})
        );
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
            json!(["/thing"])
        );
    }

    #[test]
    fn the_whole_input_is_one_subject_when_it_is_an_object_and_a_list_of_subjects_when_it_is_a_list()
     {
        let r = run(json!({"thing": {"from": "$input"}}), json!({"x": 1}));
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0),
            json!({"name": "in-scope thing count", "value": 1, "locations": [""]})
        );
        let r = run(
            json!({"thing": {"from": "$input"}}),
            json!([{"a": 1}, {"a": 2}]),
        );
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 2, "matching": 2})
        );
        let p = policy(json!({"thing": {"from": "$input"}}), json!(1));
        let r = report(&json!([]), &p, &json!({}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("value"));
        let r = run(json!({"thing": {"from": "$input"}}), json!("x"));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
        let r = run(json!({"thing": {"from": "$input"}}), Value::Null);
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("null"));
    }

    #[test]
    fn a_from_that_reaches_a_list_of_subjects_through_a_param_key() {
        let p = policy(
            json!({"thing": {"from": "every ds named by $params.k"}}),
            json!(1),
        );
        let r = report(&json!({"ds": {"a": [1, 2]}}), &p, &json!({"k": "a"}));
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(2));
        let r = report(&json!({"ds": {"a": [1, 2]}}), &p, &json!({"k": "b"}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("absent"));
    }

    #[test]
    fn a_subject_without_a_readable_id_has_a_null_id_and_points_at_where_the_read_stopped() {
        let r = run(
            json!({"thing": {"from": "ds", "identified_by": "meta.id"}}),
            json!({"ds": [{"meta": {}}, {"x": 1}]}),
        );
        let unique = &rows(&r, "$unique_ids")[0];
        assert_eq!(unique["passed"], json!(false));
        assert_eq!(
            input_of(unique, 0),
            json!({"name": "repeated thing ids", "value": [null], "locations": ["/ds/0/meta", "/ds/1"]})
        );
    }

    #[test]
    fn an_item_that_is_not_an_object_is_its_own_id_when_nothing_names_the_id() {
        let r = run(
            json!({"thing": {"from": "ds"}}),
            json!({"ds": ["a", "a", 1]}),
        );
        let unique = &rows(&r, "$unique_ids")[0];
        assert_eq!(input_of(unique, 0)["value"], json!(["a"]));
        assert_eq!(input_of(unique, 0)["locations"], json!(["/ds/0", "/ds/1"]));
    }

    #[test]
    fn repeated_ids_are_sorted_by_their_json_text() {
        let r = run(
            json!({"thing": {"from": "ds", "identified_by": "id"}}),
            json!({"ds": [{"id": 3}, {"id": 10}, {"id": "b"}, {"id": 3}, {"id": 10}, {"id": "b"}]}),
        );
        assert_eq!(
            input_of(&rows(&r, "$unique_ids")[0], 0)["value"],
            json!(["b", 10, 3])
        );
    }

    #[test]
    fn the_places_of_repeated_ids_follow_the_order_of_the_list_within_each_id() {
        let r = run(
            json!({"thing": {"from": "ds", "identified_by": "id"}}),
            json!({"ds": [{"id": "b"}, {"id": "a"}, {"id": "b"}, {"id": "a"}, {"id": "c"}, {"id": "b"}]}),
        );
        let row = &rows(&r, "$unique_ids")[0];
        assert_eq!(input_of(row, 0)["value"], json!(["a", "b"]));
        assert_eq!(
            input_of(row, 0)["locations"],
            json!(["/ds/1/id", "/ds/3/id", "/ds/0/id", "/ds/2/id", "/ds/5/id"])
        );
    }

    #[test]
    fn two_ids_that_are_the_same_number_written_differently_are_repeated() {
        let r = run(
            json!({"thing": {"from": "ds", "identified_by": "id"}}),
            serde_json::from_str(r#"{"ds": [{"id": 1}, {"id": 1.0}]}"#).unwrap(),
        );
        assert_eq!(rows(&r, "$unique_ids")[0]["passed"], json!(false));
    }

    #[test]
    fn ids_that_are_out_of_scope_still_count_for_unique_ids() {
        let r = run(
            json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
            json!({"ds": [{"id": 1, "keep": 1}, {"id": 1}]}),
        );
        assert_eq!(rows(&r, "$unique_ids")[0]["passed"], json!(false));
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 2, "matching": 1})
        );
    }

    #[test]
    fn a_filter_row_is_listed_for_every_subject_and_out_of_scope_ones_fail_with_value() {
        let r = run(
            json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
            json!({"ds": [{"id": "a", "keep": 1}, {"id": "b"}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies.len(), 2);
        assert_eq!(applies[0]["passed"], json!(true));
        assert_eq!(applies[0]["subject"], json!({"type": "thing", "id": "a"}));
        assert_eq!(applies[1]["cause"], json!("value"));
        assert_eq!(
            input_of(&applies[1], 0),
            json!({"name": "keep", "value": null, "locations": ["/ds/1"]})
        );
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
            json!(["/ds/0"])
        );
    }

    #[test]
    fn a_filter_that_cannot_read_its_subject_fails_the_requirement_even_with_min_zero() {
        let r = run(
            json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
            json!({"ds": [1]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["cause"], json!("not_an_object"));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    }

    #[test]
    fn a_present_filter_that_finds_its_field_missing_rules_the_subject_out_whatever_the_others_say()
    {
        let r = run(
            json!({"thing": {"from": "ds whose keep exists and whose b.c exists"}}),
            json!({"ds": [{"b": 1}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["cause"], json!("value"));
        assert_eq!(
            applies[0]["failed_assertions"],
            json!([
                {"assertion": "keep exists", "cause": "value"},
                {"assertion": "b.c exists", "cause": "unusable"}
            ])
        );
        assert_eq!(r["requirements"]["s"]["status"], json!("not_applicable"));
    }

    #[test]
    fn several_filters_give_failed_assertions_and_one_filter_gives_none() {
        let r = run(
            json!({"thing": {"from": "ds whose fa exists and whose fb exists"}}),
            json!({"ds": [{"fa": 1, "fb": 1}]}),
        );
        assert_eq!(rows(&r, "$applies")[0]["failed_assertions"], json!([]));
        let r = run(
            json!({"thing": {"from": "ds whose fa exists"}}),
            json!({"ds": [{"fa": 1}]}),
        );
        assert!(rows(&r, "$applies")[0].get("failed_assertions").is_none());
    }

    #[test]
    fn an_applies_row_lists_a_field_read_twice_once_sorted_by_name() {
        let r = run(
            json!({"thing": {"from": "ds whose fb exists and whose fa exists and whose fb does not exist"}}),
            json!({"ds": [{"fa": 1, "fb": 1}]}),
        );
        let row = &rows(&r, "$applies")[0];
        assert_eq!(row["inputs"].as_array().unwrap().len(), 2);
        assert_eq!(row["inputs"][0]["name"], json!("fa"));
        assert_eq!(row["inputs"][1]["name"], json!("fb"));
    }

    #[test]
    fn a_subject_with_no_filters_has_no_applies_row() {
        let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": [{}]}));
        assert!(rows(&r, "$applies").is_empty());
    }

    #[test]
    fn named_by_each_of_makes_each_sorted_key_a_subject_and_a_missing_key_points_at_the_object() {
        let p = policy(
            json!({"thing": {"from": "scans named by each of $params.l"}}),
            json!(1),
        );
        let input = json!({"scans": {"sast": {"name": "other"}, "sca": {}}});
        let r = report(&input, &p, &json!({"l": ["sca", "zzz", "sast", "sca"]}));
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0),
            json!({"name": "in-scope thing count", "value": 3,
                "locations": ["/scans/sast", "/scans/sca", "/scans"]})
        );
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(3));
    }

    #[test]
    fn a_key_with_a_slash_is_escaped_in_the_location() {
        let p = policy(
            json!({"thing": {"from": "scans named by each of $params.l"}}),
            json!(1),
        );
        let r = report(&json!({"scans": {"a/b": {}}}), &p, &json!({"l": ["a/b"]}));
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
            json!(["/scans/a~1b"])
        );
    }

    #[test]
    fn keys_that_are_not_a_list_of_strings_fail_min_subjects_as_unusable() {
        let p = policy(
            json!({"thing": {"from": "scans named by each of $params.l"}}),
            json!(0),
        );
        for params in [json!({"l": "a"}), json!({"l": [1]}), json!({"l": {"a": 1}})] {
            let r = report(&json!({"scans": {}}), &p, &params);
            assert_eq!(
                rows(&r, "$min_subjects")[0]["cause"],
                json!("unusable"),
                "{params}"
            );
        }
        let r = report(&json!({"scans": {}}), &p, &json!({}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("absent"));
    }

    #[test]
    fn every_reads_one_flat_list_from_every_list_along_the_path() {
        let r = run(
            json!({"thing": {"from": "every arts.prs", "identified_by": "url"}}),
            json!({"arts": [{"prs": [{"url": "a"}, {"url": "b"}]}, {"prs": []}, {"prs": [{"url": "c"}]}]}),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["failed_items"], json!([]));
        assert_eq!(
            input_of(min, 0)["locations"],
            json!(["/arts/0/prs/0", "/arts/0/prs/1", "/arts/2/prs/0"])
        );
        assert!(min["subject"].get("in").is_none());
    }

    #[test]
    fn every_over_only_empty_lists_finds_none_without_failing_anything() {
        let r = report(
            &json!({"arts": [{"prs": []}]}),
            &policy(json!({"thing": {"from": "every arts.prs"}}), json!(1)),
            &json!({}),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!("value"));
        assert_eq!(min["failed_items"], json!([]));
    }

    #[test]
    fn every_lists_each_place_it_broke_with_the_worst_cause_and_keeps_the_subjects_it_read() {
        let r = run(
            json!({"thing": {"from": "every arts.prs"}}),
            json!({"arts": [{"prs": [{"u": 1}]}, {}, {"prs": null}, {"prs": "none"}]}),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!("unusable"));
        assert_eq!(
            min["failed_items"],
            json!([
                {"path": "arts[0].prs", "item": "arts[0].prs", "cause": "unusable", "value": [{"u": 1}], "locations": ["/arts/0/prs"]},
                {"path": "item 1 of arts[0].prs", "item": "item 1 of arts[0].prs", "cause": "unusable", "value": {"u": 1}, "locations": ["/arts/0/prs/0"]},
                {"path": "arts[1].prs", "item": "arts[1].prs", "cause": "absent", "value": null, "locations": ["/arts/1"]},
                {"path": "arts[2].prs", "item": "arts[2].prs", "cause": "null", "value": null, "locations": ["/arts/2/prs"]},
                {"path": "arts[3].prs", "item": "arts[3].prs", "cause": "unusable", "value": "none", "locations": ["/arts/3/prs"]}
            ])
        );
        assert_eq!(
            min["message"],
            json!(
                "item 2 of arts: prs is missing; item 3 of arts: prs is null; prs is a list in item 1 of arts but \"none\" in item 4; and 1 more"
            )
        );
        assert_eq!(input_of(min, 0)["value"], json!(2));
    }

    #[test]
    fn every_names_a_broken_walk_from_a_list_input_from_dollar_input() {
        let r = run(
            json!({"thing": {"from": "every $input.commits"}}),
            json!([{"commits": [{"x": 1}]}, {"commits": null}]),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(
            min["failed_items"],
            json!([{"path": "$input[1].commits", "item": "$input[1].commits", "cause": "null", "value": null, "locations": ["/1/commits"]}])
        );
        let r = run(
            json!({"thing": {"from": "every $input[1].commits"}}),
            json!([{"commits": []}, 5]),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["failed_items"][0]["path"], json!("item 2 of $input"));
        assert_eq!(min["failed_items"][0]["item"], json!("item 2 of $input"));
    }

    #[test]
    fn every_dollar_input_names_an_input_that_is_not_a_list_dollar_input() {
        let r = run(json!({"thing": {"from": "every $input"}}), json!({"x": 1}));
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(
            min["failed_items"],
            json!([{"path": "$input", "item": "$input", "cause": "unusable", "value": {"x": 1}, "locations": [""]}])
        );
    }

    #[test]
    fn a_position_on_a_list_input_is_named_from_dollar_input_in_expressions() {
        let cases = [
            ("$input[0]", "item 1 of $input"),
            ("$input[1]", "item 2 of $input"),
            ("first of $input", "item 1 of $input"),
            ("every $input[1].commits", "every $input[1].commits"),
            ("every $input.commits", "every commits"),
            ("$input", "$input"),
            ("every $input", "every $input"),
        ];
        for (from, name) in cases {
            let r = report(
                &json!([]),
                &policy(json!({"thing": {"from": from}}), json!(1)),
                &json!({}),
            );
            let checks = &r["requirements"]["s"]["checks"];
            assert_eq!(
                checks["$min_subjects"]["expression"],
                json!(format!("count(matching({name})) >= 1")),
                "{from}"
            );
            assert_eq!(
                checks["$unique_ids"]["expression"],
                json!(format!("count(repeated(ids({name}))) == 0")),
                "{from}"
            );
        }
    }

    #[test]
    fn every_with_no_list_along_the_path_fails_unusable_at_the_value_it_ends_at() {
        let r = run(
            json!({"thing": {"from": "every arts.prs"}}),
            json!({"arts": {"prs": {"u": 1}}}),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(min["cause"], json!("unusable"));
        assert_eq!(
            min["failed_items"],
            json!([{"path": "arts.prs", "item": "arts.prs", "cause": "unusable", "value": {"u": 1}, "locations": ["/arts/prs"]}])
        );
        assert_eq!(input_of(min, 0)["value"], json!(0));
    }

    #[test]
    fn every_whose_named_by_reads_a_param_that_is_missing_keeps_the_requirement_and_fails_absent() {
        let subjects = json!({"thing": {"from": "every x named by $params.k"}});
        for (params, cause) in [
            (json!({}), "absent"),
            (json!({"k": null}), "null"),
            (json!({"k": ["x"]}), "unusable"),
        ] {
            let r = report(
                &json!({"x": [{"id": 1}]}),
                &policy(subjects.clone(), json!(1)),
                &params,
            );
            let min = &rows(&r, "$min_subjects")[0];
            assert_eq!(min["cause"], json!(cause));
            assert_eq!(min["failed_items"], json!([]));
            assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        }
    }

    #[test]
    fn a_position_under_a_keyed_parent_the_object_lacks_fails_absent_and_not_unusable() {
        for from in ["p[0]", "first of p", "p[0].x"] {
            let policy = json!({
                "ergo_spec": SPEC,
                "subjects": {"p": {"from": "m named by each of $params.ks"}, "k": {"from": from}},
                "requirements": {"r": {"subject": "k", "checks": {"c": "x exists"}}}
            });
            let r = report(
                &json!({"m": {"a": [{"x": 1}]}}),
                &policy,
                &json!({"ks": ["c"]}),
            );
            let causes: Vec<Value> = rows(&r, "$min_subjects")
                .iter()
                .map(|row| row["cause"].clone())
                .collect();
            assert_eq!(causes, vec![json!("absent")], "{from}");
        }
    }

    #[test]
    fn a_key_the_object_lacks_reads_as_missing_in_every_check() {
        let cases = [
            ("it exists", false, "value"),
            ("it does not exist", true, "satisfied"),
            ("it is an object", false, "absent"),
            ("it is empty", false, "absent"),
            ("x exists", false, "value"),
            ("x does not exist", true, "satisfied"),
        ];
        for (check, passed, cause) in cases {
            let p = json!({
                "ergo_spec": SPEC,
                "subjects": {"s": {"from": "things named by each of $params.k"}},
                "requirements": {"r": {"subject": "s", "checks": {"c": check}}}
            });
            let r = report(
                &json!({"things": {"b": {"x": 1}}}),
                &p,
                &json!({"k": ["a"]}),
            );
            let row = &rows(&r, "c")[0];
            assert_eq!(row["passed"], json!(passed), "{check}");
            assert_eq!(row["cause"], json!(cause), "{check}");
            assert_eq!(row["inputs"][0]["value"], Value::Null, "{check}");
            assert_eq!(row["inputs"][0]["locations"], json!(["/things"]), "{check}");
        }
    }

    #[test]
    fn a_missing_key_fails_its_check_when_the_input_is_not_an_object() {
        let p = json!({
            "ergo_spec": SPEC,
            "subjects": {"s": {"from": "$input named by each of $params.k"}},
            "requirements": {"r": {"subject": "s", "checks": {"c": "it exists"}}}
        });
        for input in [json!([{"id": 1}]), json!("text")] {
            let r = report(&input, &p, &json!({"k": ["a"]}));
            let min = &rows(&r, "$min_subjects")[0];
            assert_eq!(min["cause"], json!("unusable"), "{input}");
            assert_eq!(input_of(min, 0)["value"], json!(1), "{input}");
            let row = &rows(&r, "c")[0];
            assert_eq!(row["passed"], json!(false), "{input}");
            assert_eq!(row["subject"]["id"], json!("a"), "{input}");
        }
    }

    #[test]
    fn every_counts_ids_across_every_list() {
        let r = run(
            json!({"thing": {"from": "every arts.prs", "identified_by": "url"}}),
            json!({"arts": [{"prs": [{"url": "x"}]}, {"prs": [{"url": "x"}]}]}),
        );
        assert_eq!(
            input_of(&rows(&r, "$unique_ids")[0], 0)["locations"],
            json!(["/arts/0/prs/0/url", "/arts/1/prs/0/url"])
        );
    }

    #[test]
    fn every_takes_a_list_of_scalars_as_subjects() {
        let r = run(
            json!({"thing": {"from": "every xs"}}),
            json!({"xs": ["a", "b"]}),
        );
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(2));
        assert_eq!(rows(&r, "$min_subjects")[0]["failed_items"], json!([]));
    }

    fn chain() -> Value {
        json!({
            "art": {"from": "arts whose live exists", "identified_by": "id"},
            "thing": {"from": "every art.prs", "identified_by": "id"}
        })
    }

    #[test]
    fn a_child_subject_is_read_from_each_parent_and_every_row_carries_the_parents_id() {
        let r = run(
            chain(),
            json!({"arts": [
                {"id": "a1", "live": 1, "prs": [{"id": 1}, {"id": 2}]},
                {"id": "a2", "live": 1, "prs": [{"id": 1}]}
            ]}),
        );
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 2);
        assert_eq!(
            min[0]["subject"],
            json!({"type": "thing", "id": null, "in": {"art": "a1"}})
        );
        assert_eq!(input_of(&min[1], 0)["locations"], json!(["/arts/1/prs/0"]));
        let unique = rows(&r, "$unique_ids");
        assert_eq!(unique.len(), 2);
        assert!(unique.iter().all(|row| row["passed"] == json!(true)));
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 3, "matching": 3})
        );
    }

    #[test]
    fn a_repeated_parent_id_fails_one_ancestor_row_counting_the_parents_left_out() {
        let r = run(
            chain(),
            json!({"arts": [
                {"id": "a1", "live": 1, "prs": [{"id": 1}]},
                {"id": "a1", "prs": [{"id": 2}]}
            ]}),
        );
        let ancestors = rows(&r, "$unique_ancestor_ids");
        assert_eq!(ancestors.len(), 1);
        assert_eq!(ancestors[0]["subject"], json!({"type": "art", "id": null}));
        assert_eq!(
            input_of(&ancestors[0], 0),
            json!({"name": "repeated art ids", "value": ["a1"], "locations": ["/arts/0/id", "/arts/1/id"]})
        );
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        assert_eq!(
            r["requirements"]["s"]["checks"]["$unique_ancestor_ids"]["expression"],
            json!("count(repeated(ids(arts))) == 0")
        );
    }

    #[test]
    fn a_subject_with_no_parent_has_no_ancestor_row_and_no_ancestor_check() {
        let r = run(
            json!({"thing": {"from": "ds", "identified_by": "id"}}),
            json!({"ds": [{"id": 1}]}),
        );
        assert!(rows(&r, "$unique_ancestor_ids").is_empty());
        assert!(
            r["requirements"]["s"]["checks"]
                .get("$unique_ancestor_ids")
                .is_none()
        );
    }

    #[test]
    fn a_parent_its_filters_leave_out_gives_no_rows_at_all() {
        let r = run(
            chain(),
            json!({"arts": [
                {"id": "a1", "prs": [{"id": 1}, {"id": 1}]},
                {"id": "a2", "live": 1, "prs": [{"id": 5}]}
            ]}),
        );
        assert_eq!(rows(&r, "$min_subjects").len(), 1);
        assert_eq!(rows(&r, "$unique_ids").len(), 1);
        assert!(rows(&r, "$applies").is_empty());
    }

    #[test]
    fn a_parent_a_filter_cannot_decide_gets_one_failing_min_row_and_nothing_below_it() {
        let r = run(chain(), json!({"arts": [5, 6]}));
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 2);
        assert_eq!(min[1]["cause"], json!("not_an_object"));
        assert_eq!(min[1]["subject"]["in"], json!({"art": 6}));
        assert_eq!(rows(&r, "$unique_ids").len(), 0);
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
    }

    #[test]
    fn with_no_parent_at_all_one_min_row_without_in_fails_as_value_or_passes_with_min_zero() {
        let p = |min: Value| policy(chain(), min);
        let r = report(&json!({"arts": []}), &p(json!(1)), &json!({}));
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 1);
        assert_eq!(min[0]["cause"], json!("value"));
        assert!(min[0]["subject"].get("in").is_none());
        assert_eq!(rows(&r, "$unique_ids").len(), 1);
        let r = report(&json!({"arts": []}), &p(json!(0)), &json!({}));
        assert_eq!(rows(&r, "$min_subjects")[0]["passed"], json!(true));
    }

    #[test]
    fn a_parent_that_cannot_be_read_fails_min_subjects_with_its_cause_on_one_row_without_in() {
        let r = run(chain(), json!({}));
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 1);
        assert_eq!(min[0]["cause"], json!("absent"));
        assert!(min[0]["subject"].get("in").is_none());
    }

    #[test]
    fn a_child_whose_own_list_is_missing_fails_on_the_row_of_its_parent() {
        let r = run(chain(), json!({"arts": [{"id": "a1", "live": 1}]}));
        let min = rows(&r, "$min_subjects");
        assert_eq!(min[0]["cause"], json!("absent"));
        assert_eq!(min[0]["subject"]["in"], json!({"art": "a1"}));
    }

    #[test]
    fn three_levels_carry_every_ancestors_id_and_count_per_direct_parent() {
        let r = run(
            json!({
                "art": {"from": "arts", "identified_by": "id"},
                "pr": {"from": "every art.prs", "identified_by": "id"},
                "thing": {"from": "every pr.cs", "identified_by": "sha"},
            }),
            json!({"arts": [{"id": "a", "prs": [{"id": 1, "cs": [{"sha": "x"}]}, {"id": 2, "cs": [{"sha": "x"}, {"sha": "y"}]}]}]}),
        );
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 2);
        assert_eq!(min[1]["subject"]["in"], json!({"art": "a", "pr": 2}));
        assert_eq!(input_of(&min[1], 0)["value"], json!(2));
        assert_eq!(
            r["requirements"]["s"]["subjects"],
            json!({"total": 3, "matching": 3})
        );
    }

    #[test]
    fn a_subject_out_of_scope_at_any_level_leaves_out_everything_below_it() {
        let r = run(
            json!({
                "art": {"from": "arts whose live exists", "identified_by": "id"},
                "pr": {"from": "every art.prs whose open exists", "identified_by": "id"},
                "thing": {"from": "every pr.cs", "identified_by": "sha"},
            }),
            json!({"arts": [{"id": "a", "live": 1, "prs": [
                {"id": 1, "cs": [{"sha": "x"}]}, {"id": 2, "open": 1, "cs": [{"sha": "y"}]}
            ]}]}),
        );
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 1);
        assert_eq!(min[0]["subject"]["in"], json!({"art": "a", "pr": 2}));
    }

    #[test]
    fn an_undecidable_middle_level_gets_a_row_with_in_up_to_that_ancestor() {
        let r = run(
            json!({
                "art": {"from": "arts", "identified_by": "id"},
                "pr": {"from": "every art.prs whose open exists", "identified_by": "id"},
                "thing": {"from": "every pr.cs"},
            }),
            json!({"arts": [{"id": "a", "prs": [7]}]}),
        );
        let min = rows(&r, "$min_subjects");
        assert_eq!(min.len(), 1);
        assert_eq!(min[0]["cause"], json!("not_an_object"));
        assert_eq!(min[0]["subject"]["in"], json!({"art": "a", "pr": 7}));
    }

    #[test]
    fn a_child_is_read_from_a_part_of_its_parent() {
        let r = run(
            json!({
                "art": {"from": "arts", "identified_by": "id", "has": {"att": {"from": "x.b", "identified_by": "aid"}}},
                "thing": {"from": "every art.att.prs whose id exists", "identified_by": "id"},
            }),
            json!({"arts": [{"id": "a1", "x": {"b": {"aid": 9, "prs": [{"id": 1}]}}}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["passed"], json!(true));
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0)["locations"],
            json!(["/arts/0/x/b/prs/0"])
        );
        assert_eq!(
            rows(&r, "$min_subjects")[0]["subject"]["in"],
            json!({"art": "a1"})
        );
        assert_eq!(
            r["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
            json!("every art.att.prs can be read")
        );
    }

    #[test]
    fn the_left_of_a_condition_reads_the_childs_own_field_even_when_a_parent_has_that_name() {
        let r = run(
            json!({
                "b": {"from": "bs", "identified_by": "id"},
                "thing": {"from": "every b.kids whose b.x exists", "identified_by": "id"},
            }),
            json!({"bs": [{"id": "b1", "x": 1, "kids": [{"id": "k1", "b": {"x": 2}}, {"id": "k2"}]}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["passed"], json!(true));
        assert_eq!(
            input_of(&applies[0], 0)["locations"],
            json!(["/bs/0/kids/0/b/x"])
        );
        assert_eq!(applies[1]["cause"], json!("value"));
        assert_eq!(
            input_of(&applies[1], 0)["locations"],
            json!(["/bs/0/kids/1"])
        );
    }

    fn kid_report(subjects: Value, input: Value) -> Value {
        report(
            &input,
            &json!({
                "ergo_spec": SPEC,
                "subjects": subjects,
                "requirements": {"s": {"subject": "kid", "checks": {"c": "id exists"}}}
            }),
            &json!({}),
        )
    }

    #[test]
    fn a_from_line_prints_a_key_named_like_a_parent_without_a_dot_and_its_filter_with_one() {
        let r = kid_report(
            json!({
                "b": {"from": "bs", "identified_by": "id"},
                "kid": {"from": "every b.kids whose b.x equals v", "identified_by": "id"}
            }),
            json!({"bs": [{"id": "b1", "kids": [{"id": "k1", "v": 1}]}]}),
        );
        assert_eq!(
            r["subjects"]["kid"]["from"],
            json!("every b.kids whose b.x equals v")
        );
        assert_eq!(
            r["requirements"]["s"]["checks"]["$applies"]["expression"],
            json!(".b.x equals v")
        );
    }

    #[test]
    fn a_filter_keeps_the_dot_of_a_field_named_like_a_part() {
        let r = kid_report(
            json!({"kid": {
                "from": "kids whose .att.id is 1",
                "identified_by": "id",
                "has": {"att": {"from": "atts.pr", "identified_by": "id"}}
            }}),
            json!({"kids": [{"id": "k1", "att": {"id": 1}, "atts": {"pr": [{"id": 1}]}}]}),
        );
        assert_eq!(
            r["requirements"]["s"]["checks"]["$applies"]["expression"],
            json!(".att.id is 1")
        );
        assert_eq!(
            r["subjects"]["kid"]["from"],
            json!("kids whose .att.id is 1")
        );
    }

    #[test]
    fn a_subject_that_narrows_another_has_its_id_and_every_condition_outermost_first() {
        let r = run(
            json!({
                "defect": {"from": "defects whose status exists", "identified_by": "id"},
                "thing": {"from": "defect whose severity exists"},
            }),
            json!({"defects": [
                {"id": "d1", "status": 1, "severity": 1},
                {"id": "d2", "severity": 1},
                {"id": "d3", "status": 1}
            ]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies.len(), 3);
        assert_eq!(applies[0]["subject"]["id"], json!("d1"));
        assert_eq!(
            applies[2]["failed_assertions"],
            json!([{"assertion": "severity exists", "cause": "value"}])
        );
        assert_eq!(
            r["requirements"]["s"]["checks"]["$applies"]["expression"],
            json!("status exists and severity exists")
        );
        assert_eq!(r["subjects"]["thing"]["identified_by"], json!("id"));
        assert_eq!(
            r["subjects"]["defect"]["from"],
            json!("defects whose status exists")
        );
    }

    #[test]
    fn a_part_in_a_condition_names_the_alias_and_tags_the_input_with_the_parts_id() {
        let r = run(
            json!({"thing": {"from": "ds whose cov.x exists", "identified_by": "id",
                "has": {"cov": {"from": "d.b", "identified_by": "cid"}}}}),
            json!({"ds": [{"id": "a", "d": {"b": {"x": 1, "cid": "c1"}}}]}),
        );
        assert_eq!(
            input_of(&rows(&r, "$applies")[0], 0),
            json!({"name": "cov.x", "value": 1, "locations": ["/ds/0/d/b/x"],
                "part": {"name": "cov", "id": "c1"}})
        );
    }

    #[test]
    fn a_dot_reads_the_field_and_not_the_part_and_the_name_keeps_the_dot() {
        let r = run(
            json!({"thing": {"from": "ds whose .att.id exists", "has": {"att": "atts.pr"}}}),
            json!({"ds": [{"att": {"id": 1}, "atts": {"pr": {"id": 2}}}, {"atts": {"pr": {"id": 1}}}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["passed"], json!(true));
        assert_eq!(input_of(&applies[0], 0)["name"], json!(".att.id"));
        assert!(input_of(&applies[0], 0).get("part").is_none());
        assert_eq!(applies[1]["cause"], json!("value"));
    }

    #[test]
    fn a_part_that_is_missing_fails_the_condition_as_the_full_path_would() {
        let r = run(
            json!({"thing": {"from": "ds whose cov.x exists", "has": {"cov": "d.b"}}}),
            json!({"ds": [{"d": {}}, 3]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["cause"], json!("value"));
        assert_eq!(input_of(&applies[0], 0)["locations"], json!(["/ds/0/d"]));
        assert_eq!(applies[1]["cause"], json!("not_an_object"));
    }

    #[test]
    fn a_requirement_that_names_no_subject_gets_no_subjects() {
        let policy = json!({
            "ergo_spec": SPEC, "subjects": {"thing": {}},
            "requirements": {"s": {"checks": {"c": "x exists"}}}
        });
        let r = report(&json!({}), &policy, &json!({}));
        assert!(rows(&r, "$min_subjects").is_empty());
    }

    #[test]
    fn params_that_are_not_an_object_keep_the_subjects_and_fail_min_subjects() {
        let r = report(
            &json!({"ds": [1]}),
            &policy(json!({"thing": {"from": "ds"}}), json!(0)),
            &json!([1]),
        );
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(1));
    }

    #[test]
    fn a_condition_with_a_count_on_the_right_keeps_the_subjects_that_pass_it() {
        let r = run(
            json!({"thing": {"from": "ds whose x is at least count of ys"}}),
            json!({"ds": [{"x": 2, "ys": [1, 2]}, {"x": 1, "ys": [1, 2]}, {"x": 3}]}),
        );
        assert_eq!(r["requirements"]["s"]["subjects"]["matching"], json!(1));
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(3));
        assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(true));
    }

    #[test]
    fn a_child_of_a_subject_with_a_count_on_the_right_reads_under_the_parents_that_pass() {
        let r = run(
            json!({"art": {"from": "arts whose x is at least count of ys"}, "thing": {"from": "every art.prs"}}),
            json!({"arts": [{"x": 1, "ys": [1], "prs": [{}]}, {"x": 0, "ys": [1], "prs": [{}]}]}),
        );
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("satisfied"));
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(1));
    }

    #[test]
    fn a_requirement_whose_subject_is_written_wrong_reads_no_subjects() {
        let r = run(json!({"thing": {"from": "ds whose"}}), json!({"ds": [1]}));
        assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(false));
        assert!(rows(&r, "$min_subjects").is_empty());
    }

    #[test]
    fn a_subjects_entry_is_listed_for_every_subject_the_requirement_uses_and_no_other() {
        let r = run(
            json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "every art.prs"}, "other": {}}),
            json!({"arts": []}),
        );
        let names: Vec<&String> = r["subjects"].as_object().unwrap().keys().collect();
        assert_eq!(names, ["art", "thing"]);
        assert_eq!(r["subjects"]["thing"]["from"], json!("every art.prs"));
        assert_eq!(
            r["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
            json!("every art.prs can be read")
        );
    }

    fn with_checks(subjects: Value, checks: Value, input: Value) -> Value {
        let policy = json!({
            "ergo_spec": SPEC, "subjects": subjects,
            "requirements": {"s": {"subject": "thing", "checks": checks}}
        });
        report(&input, &policy, &json!({}))
    }

    fn checked(r: &Value) -> Vec<(String, String, String)> {
        rows(r, "a")
            .into_iter()
            .chain(rows(r, "b"))
            .map(|row| {
                (
                    row["check"].as_str().unwrap().to_string(),
                    row["subject"]["id"].to_string(),
                    row["cause"].as_str().unwrap().to_string(),
                )
            })
            .collect()
    }

    #[test]
    fn every_in_scope_subject_gets_a_row_for_each_check_in_name_order() {
        let r = with_checks(
            json!({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}),
            json!({"b": "x exists", "a": "x exists"}),
            json!({"ds": [{"id": 1, "keep": 1, "x": 1}, {"id": 2}, {"id": 3, "keep": 1}]}),
        );
        let order: Vec<(String, String)> = r["results"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|row| !row["check"].as_str().unwrap().starts_with('$'))
            .map(|row| (row["check"].to_string(), row["subject"]["id"].to_string()))
            .collect();
        assert_eq!(
            order,
            [
                ("\"a\"".into(), "1".into()),
                ("\"b\"".into(), "1".into()),
                ("\"a\"".into(), "3".into()),
                ("\"b\"".into(), "3".into())
            ]
        );
        let causes: Vec<String> = checked(&r).into_iter().map(|c| c.2).collect();
        assert_eq!(causes, ["satisfied", "value", "satisfied", "value"]);
    }

    #[test]
    fn a_check_row_reads_the_subject_and_a_requirement_with_a_failing_check_is_not_met() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x exists"}),
            json!({"ds": [{"x": 1}, {}]}),
        );
        let a = rows(&r, "a");
        assert_eq!(a[0]["passed"], json!(true));
        assert_eq!(
            a[1]["inputs"],
            json!([{"name": "x", "value": null, "locations": ["/ds/1"]}])
        );
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        assert_eq!(
            r["requirements"]["s"]["causes"],
            json!([{"cause": "value", "rows": 1}])
        );
    }

    #[test]
    fn several_assertions_are_one_row_with_failed_assertions_the_worst_cause_and_merged_inputs() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x exists and y.z exists and x exists"}),
            json!({"ds": [{"x": 1, "y": 5}, {"x": 1, "y": {"z": 1}}]}),
        );
        let a = rows(&r, "a");
        assert_eq!(a[0]["cause"], json!("unusable"));
        assert_eq!(
            a[0]["failed_assertions"],
            json!([{"assertion": "y.z exists", "cause": "unusable"}])
        );
        assert_eq!(a[0]["inputs"].as_array().unwrap().len(), 2);
        assert_eq!(a[0]["inputs"][0]["name"], json!("x"));
        assert_eq!(a[1]["failed_assertions"], json!([]));
        assert_eq!(a[1]["passed"], json!(true));
    }

    #[test]
    fn one_assertion_keeps_its_inputs_in_the_order_it_read_them_left_then_right() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x is less than $input.limit"}),
            json!({"limit": 5, "ds": [{"x": 1}]}),
        );
        let names: Vec<_> = rows(&r, "a")[0]["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["name"].clone())
            .collect();
        assert_eq!(names, [json!("x"), json!("$input.limit")]);
    }

    #[test]
    fn several_assertions_sort_their_inputs_by_name() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x is less than $input.limit and x exists"}),
            json!({"limit": 5, "ds": [{"x": 1}]}),
        );
        let names: Vec<_> = rows(&r, "a")[0]["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["name"].clone())
            .collect();
        assert_eq!(names, [json!("$input.limit"), json!("x")]);
    }

    #[test]
    fn one_assertion_has_no_failed_assertions() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x exists"}),
            json!({"ds": [{}]}),
        );
        assert!(rows(&r, "a")[0].get("failed_assertions").is_none());
    }

    #[test]
    fn a_check_written_with_a_count_after_every_fails_the_requirement_so_nothing_passes_by_accident()
     {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "every xs.y is at least count of zs"}),
            json!({"ds": [{"xs": [{"y": 1}]}]}),
        );
        assert_eq!(rows(&r, "a").len(), 0);
        assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(false));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        assert_eq!(r["compliant"], json!(false));
    }

    #[test]
    fn a_for_check_is_run_and_fails_as_absent_when_its_list_is_missing() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": {"for": "every xs as x", "assert": "x.y exists"}}),
            json!({"ds": [{}]}),
        );
        assert_eq!(rows(&r, "a")[0]["cause"], json!("absent"));
    }

    #[test]
    fn an_any_of_row_passes_with_one_option_and_lists_its_inputs_sorted() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": {"any_of": {"o": "z exists", "p": ["y exists", "x exists"]}}}),
            json!({"ds": [{"y": 1, "x": 2}]}),
        );
        let row = &rows(&r, "a")[0];
        assert_eq!(row["cause"], json!("satisfied"));
        let names: Vec<&Value> = row["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| &i["name"])
            .collect();
        assert_eq!(names, [&json!("x"), &json!("y"), &json!("z")]);
        assert!(row.get("failed_assertions").is_none());
    }

    #[test]
    fn a_check_read_through_a_part_tags_its_input() {
        let r = with_checks(
            json!({"thing": {"from": "ds", "has": {"cov": {"from": "d", "identified_by": "cid"}}}}),
            json!({"a": "cov.x exists"}),
            json!({"ds": [{"d": {"x": 1, "cid": 4}}]}),
        );
        assert_eq!(
            rows(&r, "a")[0]["inputs"][0]["part"],
            json!({"name": "cov", "id": 4})
        );
    }

    #[test]
    fn a_check_written_wrong_gives_the_requirement_no_check_rows_and_lists_the_problem() {
        let r = with_checks(
            json!({"thing": {"from": "ds"}}),
            json!({"a": "x exists", "b": "y is \"a"}),
            json!({"ds": [{"x": 1}]}),
        );
        assert!(rows(&r, "a").is_empty());
        let well = &rows(&r, "$well_formed")[0];
        assert_eq!(
            well["inputs"][2],
            json!({"name": "checks.b", "value": ["unclosed quote at column 6"], "locations": []})
        );
        assert_eq!(
            r["requirements"]["s"]["checks"]["b"]["expression"],
            json!("y is \"a")
        );
    }

    #[test]
    fn a_check_row_of_a_child_subject_carries_the_parents_id_and_reads_the_parent() {
        let r = with_checks(
            json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "every art.ps", "identified_by": "id"}}),
            json!({"a": "art.owner exists"}),
            json!({"arts": [{"id": "a1", "owner": 1, "ps": [{"id": 1}]}]}),
        );
        let a = rows(&r, "a");
        assert_eq!(
            a[0]["subject"],
            json!({"type": "thing", "id": 1, "in": {"art": "a1"}})
        );
        assert_eq!(a[0]["passed"], json!(true));
        assert_eq!(a[0]["inputs"][0]["locations"], json!(["/arts/0/owner"]));
    }

    #[test]
    fn a_keyed_parent_with_identified_by_is_written_wrong_under_the_childs_requirement() {
        let mut p = policy(
            json!({
                "suite": {"from": "suites named by each of $params.names", "identified_by": "aid"},
                "thing": {"from": "every suite.items", "identified_by": "id"}
            }),
            json!(0),
        );
        p["requirements"]["s"]["checks"] = json!({"c": "ok is true"});
        let input = json!({"suites": {"unit": {"aid": "att-u", "items": [{"id": 1, "ok": true}]}}});
        let r = report(&input, &p, &json!({"names": ["unit"]}));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        let well_formed = &rows(&r, "$well_formed")[0];
        assert_eq!(well_formed["passed"], json!(false));
        assert_eq!(
            well_formed["inputs"][2],
            json!({
                "name": "subjects.suite.identified_by",
                "value": ["not allowed with named by each of: the key is the id"],
                "locations": []
            })
        );
        assert_eq!(rows(&r, "c").len(), 0);
    }

    #[test]
    fn identified_by_that_is_not_a_string_next_to_named_by_each_of_lists_both_problems() {
        for bad in [json!(5), json!(null), json!(["id"])] {
            let r = run(
                json!({"thing": {"from": "suites named by each of $params.names", "identified_by": bad}}),
                json!({}),
            );
            let well_formed = &rows(&r, "$well_formed")[0];
            assert_eq!(
                well_formed["inputs"][2],
                json!({
                    "name": "subjects.thing.identified_by",
                    "value": [
                        "not a string",
                        "not allowed with named by each of: the key is the id"
                    ],
                    "locations": []
                }),
                "{bad}"
            );
            assert_eq!(
                r["subjects"]["thing"]["identified_by"],
                json!("<invalid identified_by>")
            );
        }
    }

    fn min_message(subjects: Value, input: Value) -> Value {
        rows(&run(subjects, input), "$min_subjects")[0]["message"].clone()
    }

    fn deep_message(subjects: Value, input: Value) -> Value {
        let r = report(
            &input,
            &json!({
                "ergo_spec": SPEC,
                "subjects": subjects,
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        rows(&r, "$min_subjects")[0]["message"].clone()
    }

    #[test]
    fn a_position_on_the_input_names_the_list_without_dollar_input() {
        assert_eq!(
            min_message(
                json!({"thing": {"from": "item 2 of things"}}),
                json!({"things": [{"x": 1}]})
            ),
            json!("item 2 of things is missing")
        );
        assert_eq!(
            min_message(
                json!({"thing": {"from": "item 2 of things"}}),
                json!({"things": [{"x": 1}, null]})
            ),
            json!("item 2 of things is null")
        );
        assert_eq!(
            min_message(
                json!({"thing": {"from": "first of things"}}),
                json!({"things": []})
            ),
            json!("item 1 of things is missing")
        );
    }

    #[test]
    fn a_child_names_the_path_it_walks_in_its_parent_without_the_parent() {
        let subjects = |from: &str| json!({"p": {"from": "ps"}, "thing": {"from": from}});
        let said =
            |from: &str, parent: Value| deep_message(subjects(from), json!({"ps": [parent]}));
        assert_eq!(said("p.ws", json!({"id": 1})), json!("ws is missing"));
        assert_eq!(said("p.ws", json!({"ws": null})), json!("ws is null"));
        assert_eq!(
            said("p.ws", json!({"ws": [5]})),
            json!("ws is a list: write every p.ws to read each item")
        );
        assert_eq!(
            said("first of p.ws", json!({"ws": []})),
            json!("item 1 of ws is missing")
        );
        assert_eq!(
            said("item 2 of p.ws", json!({"ws": [{"x": 1}]})),
            json!("item 2 of ws is missing")
        );
        assert_eq!(
            said("p.meta.owner", json!({"meta": {}})),
            json!("meta.owner is missing")
        );
        assert_eq!(
            said("p.meta.owner", json!({"meta": 5})),
            json!("meta is 5, which isn't a list or an object")
        );
    }

    #[test]
    fn a_grandchild_names_the_path_in_its_nearest_parent() {
        assert_eq!(
            deep_message(
                json!({
                    "t": {"from": "ts"},
                    "w": {"from": "every t.ws"},
                    "thing": {"from": "every w.kids"}
                }),
                json!({"ts": [{"ws": [{"id": 1}]}]})
            ),
            json!("kids is missing")
        );
    }

    #[test]
    fn a_name_in_a_child_filter_that_reads_a_grandparent_is_unknown_when_the_parent_is_written_wrong()
     {
        let r = report(
            &json!({"ts": []}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {
                    "t": {"from": "ts"},
                    "w": {"from": "every t.ws named by zz"},
                    "thing": {"from": "every w.kids whose lo is at least t.cov.x"}
                },
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        let inputs = rows(&r, "$well_formed")[0]["inputs"].clone();
        let listed: Vec<(String, Value)> = inputs
            .as_array()
            .unwrap()
            .iter()
            .filter(|input| {
                input["name"]
                    .as_str()
                    .is_some_and(|n| n.starts_with("subjects."))
            })
            .map(|input| {
                (
                    input["name"].as_str().unwrap().to_string(),
                    input["value"].clone(),
                )
            })
            .collect();
        assert_eq!(
            listed,
            [
                ("subjects.w.from".to_string(), json!(["unknown alias zz"])),
                (
                    "subjects.thing.from".to_string(),
                    json!(["unknown alias $t"])
                ),
            ]
        );
    }

    #[test]
    fn a_name_in_a_child_filter_that_reads_a_grandparent_is_known_when_the_parent_is_fine() {
        let r = report(
            &json!({"ts": []}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {
                    "t": {"from": "ts"},
                    "w": {"from": "every t.ws"},
                    "thing": {"from": "every w.kids whose lo is at least t.cov.x"}
                },
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(true));
    }

    #[test]
    fn a_filter_comparing_two_unusable_sides_names_both() {
        let r = report(
            &json!({"ts": [{"cov": 5, "ws": [{"lo": true}]}]}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {
                    "t": {"from": "ts"},
                    "thing": {"from": "every t.ws whose lo is at least t.cov.x"}
                },
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        assert_eq!(
            rows(&r, "$applies")[0]["message"],
            json!("t.cov is 5, which isn't an object, and lo is true, which isn't a number")
        );
    }

    #[test]
    fn an_any_of_tags_an_input_with_the_part_that_reads_the_same_path() {
        let r = report(
            &json!({"things": [{"id": "a", "name": 1}]}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {"thing": {"from": "things", "has": {"cv": "name"}}},
                "requirements": {"s": {"subject": "thing", "checks": {
                    "c": {"any_of": {"a": "name is 2", "b": "cv is 2"}}
                }}}
            }),
            &json!({}),
        );
        let inputs = rows(&r, "c")[0]["inputs"].clone();
        assert_eq!(
            inputs,
            json!([
                {"name": "cv", "value": 1, "locations": ["/things/0/name"], "part": {"name": "cv", "id": null}},
                {"name": "name", "value": 1, "locations": ["/things/0/name"], "part": {"name": "cv", "id": null}}
            ])
        );
    }

    #[test]
    fn a_from_name_that_is_a_word_of_the_grammar_gets_one_problem() {
        let r = run(
            json!({"p": {"from": "ps"}, "thing": {"from": "every p.ws named by one"}}),
            json!({}),
        );
        let texts: Vec<Value> = rows(&r, "$well_formed")[0]["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|input| input["name"] == json!("subjects.thing.from"))
            .map(|input| input["value"].clone())
            .collect();
        assert_eq!(texts, [json!(["one can't be an alias"])]);
    }

    fn from_problems_of(from: &str, parent: &str) -> Vec<Value> {
        let r = report(
            &json!({"ts": []}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {
                    "t": {"from": "ts"},
                    "w": {"from": parent},
                    "thing": {"from": from}
                },
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        rows(&r, "$well_formed")[0]["inputs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|input| {
                input["name"]
                    .as_str()
                    .is_some_and(|n| n.starts_with("subjects."))
            })
            .map(|input| json!([input["name"], input["value"]]))
            .collect()
    }

    #[test]
    fn a_dotted_right_side_reads_the_input_field_so_it_never_names_a_grandparent() {
        let listed = from_problems_of("w.kids whose lo is at least .t.cov.x", "t.ws named by zz");
        assert_eq!(listed, [json!(["subjects.w.from", ["unknown alias zz"]])]);
    }

    #[test]
    fn a_from_line_whose_that_compares_a_field_with_itself_is_written_wrong() {
        assert_eq!(
            from_problems_of("w.kids whose lo is at least lo", "t.ws"),
            [json!([
                "subjects.thing.from",
                ["whose: lo is compared with itself"]
            ])]
        );
    }

    #[test]
    fn a_from_whose_that_reads_the_parent_on_both_sides_is_accepted() {
        for whose in ["t.lo is at least t.lo", "t is t", "t.lo is not t.lo"] {
            assert_eq!(
                from_problems_of(&format!("t.ws whose {whose}"), "t.ws"),
                Vec::<Value>::new(),
                "{whose}"
            );
        }
    }

    #[test]
    fn a_from_whose_that_reads_the_item_field_on_both_sides_is_written_wrong() {
        for (whose, said) in [
            ("t.lo is at most .t.lo", ".t.lo"),
            ("t is .t", ".t"),
            (".t.lo ends with .t.lo", ".t.lo"),
            ("x is x", "x"),
        ] {
            assert_eq!(
                from_problems_of(&format!("t.ws whose {whose}"), "t.ws"),
                [json!([
                    "subjects.thing.from",
                    [format!("whose: {said} is compared with itself")]
                ])],
                "{whose}"
            );
        }
    }

    #[test]
    fn a_parent_written_wrong_by_comparing_with_itself_blocks_the_grandparent_for_its_child() {
        let listed = from_problems_of(
            "w.kids whose lo is at least t.cov.x",
            "t.ws whose lo is at least lo",
        );
        assert_eq!(
            listed,
            [
                json!(["subjects.w.from", ["whose: lo is compared with itself"]]),
                json!(["subjects.thing.from", ["unknown alias $t"]])
            ]
        );
    }

    #[test]
    fn a_child_blocked_by_an_unknown_grandparent_is_an_invalid_from_in_the_report() {
        let r = report(
            &json!({"ts": []}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {
                    "t": {"from": "ts"},
                    "w": {"from": "every t.ws whose x is x"},
                    "thing": {"from": "every w.kids whose t.lo is more than t.lo"}
                },
                "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}
            }),
            &json!({}),
        );
        assert_eq!(r["subjects"]["thing"]["from"], json!("<invalid from>"));
        assert_eq!(r["subjects"]["w"]["from"], json!("<invalid from>"));
    }

    fn message_of(check: Value, input: Value, params: Value) -> Value {
        let r = report(
            &input,
            &json!({
                "ergo_spec": SPEC,
                "subjects": {"thing": {"from": "things", "identified_by": "id"}},
                "requirements": {"s": {"subject": "thing", "checks": {"c": check}}}
            }),
            &params,
        );
        rows(&r, "c")[0]["message"].clone()
    }

    #[test]
    fn a_for_line_that_reads_params_that_arent_an_object_names_them() {
        let input = json!({"things": [{"id": "t", "ws": [1]}]});
        for check in [
            json!({"for": "every $params as p", "assert": "p.v is 1"}),
            json!({"for": "every $params.v as p", "assert": "p is 1"}),
            json!({"for": "every ws as w", "assert": "w is in $params.v"}),
        ] {
            assert_eq!(
                message_of(check, input.clone(), json!(3)),
                json!("$params is 3, which isn't an object")
            );
        }
    }

    #[test]
    fn a_named_by_or_a_whose_that_reads_params_that_arent_an_object_names_them() {
        let input = json!({"things": [{"id": "t", "x": {"a": 1}, "ws": [{"x": 1}]}]});
        for check in [
            "x named by $params.v is 1",
            "every ws whose x is $params.v is 1",
        ] {
            assert_eq!(
                message_of(json!(check), input.clone(), json!("s")),
                json!("$params is \"s\", which isn't an object")
            );
        }
    }

    #[test]
    fn a_count_whose_whose_reads_params_that_are_a_list_names_them_not_the_digits() {
        assert_eq!(
            message_of(
                json!("count of $params whose v is 1 is 1"),
                json!({"things": [{"id": "t"}]}),
                json!([3])
            ),
            json!("$params is [3], which isn't an object")
        );
    }

    #[test]
    fn a_ref_on_the_right_is_named_after_the_left_side_and_a_subject_field_before_it() {
        let input = json!({"things": [{"id": "t", "zz": "v", "y": 3}], "y": 3});
        assert_eq!(
            message_of(json!("zz contains $params.v"), input.clone(), json!(3)),
            json!("zz is \"v\", which isn't a list, and $params is 3, which isn't an object")
        );
        assert_eq!(
            message_of(json!("zz contains $input.y.v"), input.clone(), json!({})),
            json!("zz is \"v\", which isn't a list, and $input.y is 3, which isn't an object")
        );
        assert_eq!(
            message_of(json!("zz contains y.v"), input, json!({})),
            json!("y is 3, which isn't an object, and zz is \"v\", which isn't a list")
        );
    }

    #[test]
    fn a_key_after_a_position_of_params_holding_a_list_names_the_item() {
        assert_eq!(
            message_of(
                json!("x is in $params[0].v"),
                json!({"things": [{"id": "t", "x": 1}]}),
                json!([[1]])
            ),
            json!("item 1 of $params is [1], which isn't an object")
        );
    }

    #[test]
    fn a_count_through_a_position_names_the_item_once() {
        let input = json!({"things": [{"id": "t", "y": [{"v": 1}]}], "y": [{"v": 1}]});
        assert_eq!(
            message_of(json!("count of y[0].v is 1"), input.clone(), json!({})),
            json!("item 1 of y: v is 1, which isn't a list or an object")
        );
        assert_eq!(
            message_of(json!("count of $input.y[0].v is 1"), input, json!({})),
            json!("item 1 of $input.y: v is 1, which isn't a list or an object")
        );
        assert_eq!(
            message_of(
                json!("count of $params[0].v is 1"),
                json!({"things": [{"id": "t"}]}),
                json!([{"v": 1}])
            ),
            json!("item 1 of $params: v is 1, which isn't a list or an object")
        );
    }

    fn from_rows(line: &str, params: Value) -> Vec<(String, String, Value)> {
        let r = report(
            &json!({"things": {"k": {"id": "t"}}}),
            &json!({
                "ergo_spec": SPEC,
                "subjects": {"s": {"from": line}},
                "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}
            }),
            &params,
        );
        r["results"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|row| row["check"] != "$well_formed" && row["check"] != "$unique_ids")
            .map(|row| {
                (
                    row["check"].as_str().unwrap().to_string(),
                    row["cause"].as_str().unwrap().to_string(),
                    row["message"].clone(),
                )
            })
            .collect()
    }

    fn min_subjects(cause: &str, message: &str) -> Vec<(String, String, Value)> {
        vec![(
            "$min_subjects".to_string(),
            cause.to_string(),
            json!(message),
        )]
    }

    #[test]
    fn a_from_line_that_reads_params_that_arent_an_object_names_the_params_and_not_the_object() {
        for (params, shown) in [
            (json!(3), "3"),
            (json!("s"), "\"s\""),
            (json!(true), "true"),
            (json!([]), "[]"),
            (json!([3]), "[3]"),
            (json!([[1]]), "[[1]]"),
            (json!([{"v": 1}]), "[{\"v\": 1}]"),
            (json!([["k"]]), "[[\"k\"]]"),
        ] {
            let said = format!("$params is {shown}, which isn't an object");
            for line in [
                "things named by each of $params.ks",
                "things named by $params.env named by each of $params.ks",
                "every things named by $params.env",
            ] {
                assert_eq!(
                    from_rows(line, params.clone()),
                    min_subjects("unusable", &said),
                    "{line} with {params}"
                );
            }
        }
    }

    #[test]
    fn a_from_line_that_reads_a_position_of_the_params_names_what_it_found_there() {
        assert_eq!(
            from_rows("things named by each of $params[0]", json!(3)),
            min_subjects("unusable", "$params is 3, which isn't a list")
        );
        assert_eq!(
            from_rows("things named by each of $params[0]", json!([3])),
            min_subjects(
                "unusable",
                "item 1 of $params is 3, which isn't a list of text"
            )
        );
        assert_eq!(
            from_rows("things named by each of $params[0].ks", json!([3])),
            min_subjects("unusable", "item 1 of $params is 3, which isn't an object")
        );
        assert_eq!(
            from_rows("things named by each of $params[0].ks", json!([{"ks": 3}])),
            min_subjects("unusable", "$params[0].ks is 3, which isn't a list of text")
        );
    }

    #[test]
    fn a_from_line_that_reads_the_input_and_params_that_arent_an_object_names_both() {
        assert_eq!(
            from_rows(
                "things named by $input.nope named by each of $params.ks",
                json!(3)
            ),
            min_subjects(
                "unusable",
                "$input.nope is missing; $params is 3, which isn't an object"
            )
        );
    }

    #[test]
    fn a_from_line_makes_no_subjects_from_keys_in_params_that_arent_an_object() {
        assert_eq!(
            from_rows("things named by each of $params[0]", json!([["k"]])),
            min_subjects("unusable", "$params is [[\"k\"]], which isn't an object")
        );
        assert_eq!(
            from_rows(
                "things named by each of $params[0].ks",
                json!([{"ks": ["k"]}])
            ),
            min_subjects(
                "unusable",
                "$params is [{\"ks\": [\"k\"]}], which isn't an object"
            )
        );
    }

    #[test]
    fn a_from_line_that_reads_null_params_says_the_param_is_missing() {
        assert_eq!(
            from_rows("things named by each of $params.ks", Value::Null),
            min_subjects("absent", "$params.ks is missing")
        );
        assert_eq!(
            from_rows("things named by $params.env", Value::Null),
            min_subjects("absent", "$params.env is missing")
        );
    }
}
