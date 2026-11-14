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
        item_by_item: true,
        in_option: false,
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
                said.push(own.unwrap_or_else(|| {
                    if matches!(verdict.cause, Cause::Absent | Cause::Null) {
                        let mut unlabelled = ctx.clone();
                        unlabelled.label = None;
                        ops::message::message(&filter.check, &unlabelled, &verdict)
                    } else {
                        ops::message::message(&filter.check, ctx, &verdict)
                    }
                }));
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
    ctx.item_by_item = !anc.is_empty();
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

fn walked_roots_run(check: &Check, ctx: &Ctx) -> ops::Ran {
    let ran = ops::run_full(check, ctx);
    if !ran.verdict.passed() {
        return ran;
    }
    ops::reading_walked_roots(|| {
        let mut again = ops::run_full(check, ctx);
        if again.verdict.passed() {
            return ran;
        }
        if again.message.is_none() {
            again.message = Some(match check {
                Check::Tally(tally) => ops::tally::with_walked_roots(
                    tally,
                    ctx,
                    ops::message::message(check, ctx, &again.verdict),
                ),
                _ => ops::message::message(check, ctx, &again.verdict),
            });
        }
        again
    })
}

fn check_row(env: &Env, name: &str, plan: &Plan, ctx: &Ctx, judged: &Judged, anc: &[Anc]) -> Row {
    let by_item;
    let ctx = if !ctx.item_by_item && plan.items.iter().any(|item| item.check.reads_by_item()) {
        by_item = ctx.item_by_item();
        &by_item
    } else {
        ctx
    };
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
            let ran = walked_roots_run(check, ctx);
            failed_items = ran.failed_items.map(Value::Array);
            let mut verdict = ran.verdict;
            let mut own = ran.message;
            if !env.unreadable.is_empty() && verdict.cause != Cause::Ambiguous {
                verdict.cause = Cause::Unusable;
                if ops::message::params_that_arent_an_object(check, ctx).is_some() {
                    failed_items = failed_items.take().map(|_| Value::Array(Vec::new()));
                    own = None;
                }
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
            .map(|((check, v), own)| match (own, check) {
                (Some(text), _) => text.clone(),
                (None, Check::Tally(tally)) => {
                    ops::tally::with_walked_roots(tally, ctx, ops::message::message(check, ctx, v))
                }
                (None, _) => ops::message::message(check, ctx, v),
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
mod tests;
