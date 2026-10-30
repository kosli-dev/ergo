use crate::cause::Cause;
use crate::checks::{CheckRead, Plan, read_checks};
use crate::ops::walk;
use crate::ops::{self, Check, Input, Verdict};
use crate::path::{self, Ctx, Located, Location, Outcome, Path, Start, Step};
use crate::policy::{Policy, Requirement, SubjectName};
use crate::reading::{Filter, Lowered, Reading, Relation, Source};
use crate::report::{
    Evaluation, Row, min_subjects_row, no_subjects, row_of, unique_ids_row, unreadable_params,
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
}

struct Broken {
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

fn plain_entries<'a>(read: &path::Read<'a>) -> Result<Vec<Entry<'a>>, Cause> {
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
            })
            .collect()),
        Value::Object(_) => Ok(vec![Entry {
            at: Located { value, location },
            key: None,
        }]),
        _ => Err(Cause::Unusable),
    }
}

fn each_of_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    path: &Path,
    each_of: &Path,
    anc: &[Anc<'a>],
) -> Read<'a> {
    let ctx = context(env, input_root(env), anc);
    let object = path::read(path, &ctx);
    let keys = path::read(each_of, &ctx);
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
    let unread = match (object.outcome, object.value) {
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
            }
        })
        .collect();
    let broken = unread
        .map(|cause| Broken {
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
    Broken {
        order: failure.order.clone(),
        path: failure.path.clone(),
        cause: failure.cause,
        value: failure.value.clone(),
        location: failure.location.as_ref().map(Location::render),
    }
}

fn walk_every<'a>(env: &Env<'a>, path: &Path, anc: &[Anc<'a>]) -> Read<'a> {
    let ctx = context(env, input_root(env), anc);
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
                order: Vec::new(),
                path: String::new(),
                cause,
                value: match cause {
                    Cause::Unusable => env.input.clone(),
                    _ => Value::Null,
                },
                location: Some(Location::input_root().render()),
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
            }),
            _ => broken.push(Broken {
                order: item.end_segs.clone(),
                path: walked.name_of(&item.end_segs, false),
                cause: item.miss,
                value: item.shown(),
                location: Some(item.end_location.render()),
            }),
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
    broken.sort_by(|a, b| a.order.cmp(&b.order));
    Read::Entries { entries, broken }
}

fn unread_ref_cause(env: &Env, source: &Source, anc: &[Anc]) -> Option<Cause> {
    let ctx = context(env, input_root(env), anc);
    let (path, each_of) = match source {
        Source::Root { path, each_of, .. } | Source::Child { path, each_of } => {
            (path, each_of.as_ref())
        }
    };
    let mut causes: Vec<Cause> = path::step_refs(path)
        .iter()
        .filter_map(|reference| {
            let step = Step::Ref(Box::new(reference.clone()));
            path::resolve(&step, &ctx)
                .err()
                .map(|outcome| outcome.cause().unwrap_or(Cause::Unusable))
        })
        .collect();
    if let Some(each_of) = each_of {
        let read = path::read(each_of, &ctx);
        match (read.outcome, read.value) {
            (Outcome::Found, _) => {}
            (other, _) => causes.push(other.cause().unwrap_or(Cause::Unusable)),
        }
    }
    Cause::worst(causes)
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
            each_of: None,
        } => walk_every(env, path, anc),
        Source::Root {
            path,
            each_of: Some(each_of),
            ..
        } => each_of_entries(env, empty, path, each_of, anc),
        Source::Child {
            path,
            each_of: Some(each_of),
        } => each_of_entries(env, empty, path, each_of, anc),
        Source::Root { path, .. } | Source::Child { path, .. } => {
            let ctx = context(env, input_root(env), anc);
            let read = path::read(path, &ctx);
            match read.outcome {
                Outcome::Found => match plain_entries(&read) {
                    Ok(entries) => Read::Entries {
                        entries,
                        broken: Vec::new(),
                    },
                    Err(cause) => Read::Failed(cause),
                },
                other => Read::Failed(other.cause().unwrap_or(Cause::Unusable)),
            }
        }
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
    merge_inputs(inputs).iter().map(Input::to_json).collect()
}

fn inputs_in_order(inputs: Vec<Input>) -> Vec<Value> {
    let mut kept: Vec<Input> = Vec::new();
    for input in inputs {
        if !kept.contains(&input) {
            kept.push(input);
        }
    }
    kept.iter().map(Input::to_json).collect()
}

struct Applied {
    matched: bool,
    cause: Cause,
    inputs: Vec<Value>,
    failed_assertions: Option<Value>,
    failed_items: Option<Value>,
}

fn answers_presence(filter: &Filter, verdict: &Verdict) -> bool {
    matches!(&filter.check, Check::Present(present) if !present.missing)
        && verdict.cause == Cause::Value
}

fn apply(filters: &[Filter], ctx: &Ctx, unreadable: bool) -> Applied {
    let mut failed_items = None;
    let verdicts: Vec<(&Filter, Verdict)> = filters
        .iter()
        .map(|filter| {
            let ran = ops::run_full(&filter.check, ctx);
            let mut verdict = ran.verdict;
            failed_items = ran.failed_items.map(Value::Array);
            if unreadable {
                verdict.cause = Cause::Unusable;
                failed_items = failed_items.take().map(|_| Value::Array(Vec::new()));
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
    Applied {
        matched,
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
            let read = path::read(
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
            let ctx = context(env, entry.at.clone(), anc);
            let (id, id_location) = id_of(lowered, &entry, &ctx);
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
            locations.extend(item.id_location.iter().cloned());
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
        Read::Failed(cause) => return failed_level(env, anc, cause, true),
    };
    let judged = judge(env, lowered, entries, anc);
    let (repeated, id_locations) = repeated_ids(&judged);
    let in_scope: Vec<&Judged> = judged.iter().filter(|j| j.in_scope()).collect();
    let locations: Vec<String> = in_scope
        .iter()
        .map(|j| j.entry.at.location.render())
        .collect();
    let every = matches!(&lowered.source, Source::Root { every: true, .. });
    let read = Cause::worst(broken.iter().map(|b| b.cause));
    let mut min = min_row(env, in_scope.len() as u64, &locations, read);
    if every {
        let listed = if env.unreadable.is_empty() {
            broken.iter().map(Broken::to_json).collect()
        } else {
            Vec::new()
        };
        min.failed_items = Some(Value::Array(listed));
    }
    let unique = unique_ids_row(
        env.requirement_name,
        env.requirement,
        repeated,
        &id_locations,
    );
    let applies = judged
        .iter()
        .filter_map(|j| j.applied.as_ref().map(|a| applies_row(env, j, a, anc)))
        .collect();
    let subject_rows = in_scope
        .iter()
        .map(|j| check_rows(env, j, anc))
        .filter(|rows| !rows.is_empty())
        .collect();
    Evaluation {
        total: judged.len() as u64,
        matching: in_scope.len() as u64,
        min_subjects: vec![with_in(min, anc)],
        unique_ids: vec![with_in(unique, anc)],
        applies,
        subject_rows,
    }
}

fn check_rows(env: &Env, judged: &Judged, anc: &[Anc]) -> Vec<Row> {
    let ctx = context(env, judged.entry.at.clone(), anc);
    env.checks
        .iter()
        .filter(|(name, _)| !crate::policy::RESERVED_CHECKS.contains(&name.as_str()))
        .filter_map(|(name, read)| {
            read.plan
                .as_ref()
                .map(|plan| check_row(env, name, plan, &ctx, judged, anc))
        })
        .collect()
}

fn check_row(env: &Env, name: &str, plan: &Plan, ctx: &Ctx, judged: &Judged, anc: &[Anc]) -> Row {
    let mut failed_items = None;
    let verdicts: Vec<Verdict> = plan
        .items
        .iter()
        .map(|item| {
            let ran = ops::run_full(&item.check, ctx);
            failed_items = ran.failed_items.map(Value::Array);
            let mut verdict = ran.verdict;
            if !env.unreadable.is_empty() {
                verdict.cause = Cause::Unusable;
                failed_items = failed_items.take().map(|_| Value::Array(Vec::new()));
            }
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

fn failed_level(env: &Env, anc: &[Anc], cause: Cause, with_unique: bool) -> Evaluation {
    let min = min_row(env, 0, &[], Some(cause));
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
        applies: Vec::new(),
        subject_rows: Vec::new(),
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
    if !env.unreadable.is_empty() {
        return vec![failed_level(env, anc, Cause::Unusable, anc.is_empty())];
    }
    let Some(lowered) = env.reading.lowered(parent) else {
        return vec![failed_level(env, anc, Cause::Unusable, anc.is_empty())];
    };
    let (entries, broken) = match read_entries(env, empty, lowered, anc) {
        Read::Entries { entries, broken } => (entries, broken),
        Read::Failed(cause) => return vec![failed_level(env, anc, cause, anc.is_empty())],
    };
    let keyed_child = matches!(
        &lowered.source,
        Source::Child {
            each_of: Some(_),
            ..
        }
    );
    if !keyed_child && let Some(cause) = Cause::worst(broken.iter().map(|b| b.cause)) {
        return vec![failed_level(env, anc, cause, anc.is_empty())];
    }
    let mut out = Vec::new();
    for judged in judge(env, lowered, entries, anc) {
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
            anc.push(here);
            out.extend(descend(env, &chain[1..], anc, empty));
            anc.pop();
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
        params: params.as_object().map(|_| params),
        unreadable: unreadable_params(params),
    };
    let empty = Value::Object(Map::new());
    let chain = chain_of(reading, subject);
    let mut anc = Vec::new();
    let evaluations = descend(&env, &chain, &mut anc, &empty);
    if evaluations.is_empty() {
        return none_found(&env);
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
    let min = min_row(env, 0, &[], None);
    let unique = unique_ids_row(env.requirement_name, env.requirement, Vec::new(), &[]);
    Evaluation {
        total: 0,
        matching: 0,
        min_subjects: vec![min],
        unique_ids: vec![unique],
        applies: Vec::new(),
        subject_rows: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use crate::report;
    use serde_json::{Value, json};

    fn policy(subjects: Value, min: Value) -> Value {
        json!({
            "ergo_spec": "v0.3-dev",
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
            json!({"thing": {"from": "data.ds", "identified_by": "id"}}),
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
    fn a_list_that_ends_on_a_scalar_is_unusable_and_null_is_null() {
        let r = run(json!({"thing": {"from": "ds"}}), json!({"ds": 3}));
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
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
            json!({"thing": {"from": "ds named by $params.k"}}),
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
            json!({"thing": {"from": "ds whose keep exists and b.c exists"}}),
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
            json!({"thing": {"from": "ds whose fa exists and fb exists"}}),
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
            json!({"thing": {"from": "ds whose fb exists and fa exists and fb does not exist"}}),
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
            json!({"thing": {"from": "scans named by each of $params.l", "identified_by": "name"}}),
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
                {"path": "arts[1].prs", "item": "arts[1].prs", "cause": "absent", "value": null, "locations": ["/arts/1"]},
                {"path": "arts[2].prs", "item": "arts[2].prs", "cause": "null", "value": null, "locations": ["/arts/2/prs"]},
                {"path": "arts[3].prs", "item": "arts[3].prs", "cause": "unusable", "value": "none", "locations": ["/arts/3/prs"]}
            ])
        );
        assert_eq!(input_of(min, 0)["value"], json!(1));
    }

    #[test]
    fn every_names_a_broken_walk_from_a_list_input_from_dollar_input() {
        let r = run(
            json!({"thing": {"from": "every $input.commits"}}),
            json!([{"commits": [{"x": 1}]}, {"commits": 5}]),
        );
        let min = &rows(&r, "$min_subjects")[0];
        assert_eq!(
            min["failed_items"],
            json!([{"path": "$input[1].commits", "item": "$input[1].commits", "cause": "unusable", "value": 5, "locations": ["/1/commits"]}])
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
            "thing": {"from": "art.prs", "identified_by": "id"}
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
        let r = run(
            chain(),
            json!({"arts": [{"id": "a1", "live": 1, "prs": [{"id": 1}]}, 5]}),
        );
        assert_eq!(rows(&r, "$min_subjects").len(), 2);
        let min = rows(&r, "$min_subjects");
        assert_eq!(min[1]["cause"], json!("not_an_object"));
        assert_eq!(min[1]["subject"]["in"], json!({"art": 5}));
        assert_eq!(rows(&r, "$unique_ids").len(), 1);
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
                "pr": {"from": "art.prs", "identified_by": "id"},
                "thing": {"from": "pr.cs", "identified_by": "sha"},
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
                "pr": {"from": "art.prs whose open exists", "identified_by": "id"},
                "thing": {"from": "pr.cs", "identified_by": "sha"},
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
                "pr": {"from": "art.prs whose open exists", "identified_by": "id"},
                "thing": {"from": "pr.cs"},
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
                "thing": {"from": "art.att.prs whose id exists", "identified_by": "id"},
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
            json!("art.att.prs can be read")
        );
    }

    #[test]
    fn the_left_of_a_condition_reads_the_childs_own_field_even_when_a_parent_has_that_name() {
        let r = run(
            json!({
                "b": {"from": "bs", "identified_by": "id"},
                "thing": {"from": "b.kids whose b.x exists", "identified_by": "id"},
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
                "ergo_spec": "v0.3-dev",
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
                "kid": {"from": "b.kids whose b.x equals v", "identified_by": "id"}
            }),
            json!({"bs": [{"id": "b1", "kids": [{"id": "k1", "v": 1}]}]}),
        );
        assert_eq!(
            r["subjects"]["kid"]["from"],
            json!("b.kids whose b.x equals v")
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
            json!("kids whose att.id is 1")
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
    fn a_dot_reads_the_field_and_not_the_part_and_the_name_has_no_dot() {
        let r = run(
            json!({"thing": {"from": "ds whose .att.id exists", "has": {"att": "atts.pr"}}}),
            json!({"ds": [{"att": {"id": 1}, "atts": {"pr": {"id": 2}}}, {"atts": {"pr": {"id": 1}}}]}),
        );
        let applies = rows(&r, "$applies");
        assert_eq!(applies[0]["passed"], json!(true));
        assert_eq!(input_of(&applies[0], 0)["name"], json!("att.id"));
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
            "ergo_spec": "v0.3-dev", "subjects": {"thing": {}},
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
            json!({"art": {"from": "arts whose x is at least count of ys"}, "thing": {"from": "art.prs"}}),
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
            json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "art.prs"}, "other": {}}),
            json!({"arts": []}),
        );
        let names: Vec<&String> = r["subjects"].as_object().unwrap().keys().collect();
        assert_eq!(names, ["art", "thing"]);
        assert_eq!(r["subjects"]["thing"]["from"], json!("art.prs"));
        assert_eq!(
            r["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
            json!("art.prs can be read")
        );
    }

    fn with_checks(subjects: Value, checks: Value, input: Value) -> Value {
        let policy = json!({
            "ergo_spec": "v0.3-dev", "subjects": subjects,
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
            json!({"art": {"from": "arts", "identified_by": "id"}, "thing": {"from": "art.ps", "identified_by": "id"}}),
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
}
