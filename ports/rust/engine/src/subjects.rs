use crate::cause::Cause;
use crate::name;
use crate::ops::{self, Check, Input, Verdict};
use crate::path::{self, Ctx, Located, Location, Outcome, Path, Resolved, Start, Step};
use crate::policy::{Policy, Requirement, SubjectName};
use crate::reading::{Filter, Lowered, Reading, Relation, Source};
use crate::report::{
    Evaluation, Row, min_subjects_row, no_subjects, row_of, unique_ids_row, unreadable_params,
};
use crate::value::{self, json_text};
use serde_json::{Map, Value, json};
use std::cmp::Ordering;

struct Env<'a> {
    reading: &'a Reading,
    requirement_name: &'a str,
    requirement: &'a Requirement,
    subject: &'a str,
    input: &'a Value,
    params: Option<&'a Value>,
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
    if object.outcome != Outcome::Found {
        return Read::Failed(object.outcome.cause().unwrap_or(Cause::Unusable));
    }
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
    let (Some(target), Some(location)) = (object.value, object.location) else {
        return Read::Failed(Cause::Unusable);
    };
    let entries = names
        .into_iter()
        .map(|key| {
            let found = match target {
                Value::Object(map) => map.get(key),
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
    Read::Entries {
        entries,
        broken: Vec::new(),
    }
}

struct Cur<'a> {
    value: &'a Value,
    location: Location,
    name: String,
}

fn joined(name: &str, key: &str) -> String {
    if name.is_empty() {
        name::name(&Path {
            start: Start::Subject,
            steps: vec![Step::Key(key.to_string())],
        })
    } else {
        format!("{name}.{}", name::key_text(key))
    }
}

fn broken_at(cur: &Cur, name: String, cause: Cause) -> Broken {
    Broken {
        path: name,
        cause,
        value: match cause {
            Cause::Unusable => cur.value.clone(),
            _ => Value::Null,
        },
        location: Some(cur.location.render()),
    }
}

fn walk_lists<'a>(
    current: Vec<Cur<'a>>,
    broken: &mut Vec<Broken>,
    walked: &mut bool,
) -> Vec<Cur<'a>> {
    let mut out = Vec::new();
    for cur in current {
        match cur.value {
            Value::Array(items) => {
                *walked = true;
                for (at, item) in items.iter().enumerate() {
                    out.push(Cur {
                        value: item,
                        location: cur.location.index(at as u64),
                        name: format!("{}[{at}]", cur.name),
                    });
                }
            }
            Value::Null => {
                let name = cur.name.clone();
                broken.push(broken_at(&cur, name, Cause::Null));
            }
            _ => {
                let name = cur.name.clone();
                broken.push(broken_at(&cur, name, Cause::Unusable));
            }
        }
    }
    out
}

fn walk_every<'a>(env: &Env<'a>, path: &Path, anc: &[Anc<'a>]) -> Read<'a> {
    let ctx = context(env, input_root(env), anc);
    let mut broken = Vec::new();
    let mut walked = false;
    let mut current = vec![Cur {
        value: env.input,
        location: Location::input_root(),
        name: String::new(),
    }];
    for step in &path.steps {
        if !matches!(step, Step::Index(_)) && current.iter().any(|c| c.value.is_array()) {
            current = walk_lists(current, &mut broken, &mut walked);
        }
        let resolved = match path::resolve(step, &ctx) {
            Ok(resolved) => resolved,
            Err(outcome) => {
                if let Some(first) = current.first() {
                    broken.push(broken_at(
                        first,
                        first.name.clone(),
                        outcome.cause().unwrap_or(Cause::Unusable),
                    ));
                }
                return finish(Vec::new(), broken);
            }
        };
        let mut next = Vec::new();
        for cur in current {
            match (&resolved, cur.value) {
                (_, Value::Null) => {
                    let name = cur.name.clone();
                    broken.push(broken_at(&cur, name, Cause::Absent));
                }
                (Resolved::Key(key), Value::Object(map)) => match map.get(key) {
                    Some(value) => next.push(Cur {
                        value,
                        location: cur.location.key(key),
                        name: joined(&cur.name, key),
                    }),
                    None => {
                        let name = joined(&cur.name, key);
                        broken.push(broken_at(&cur, name, Cause::Absent));
                    }
                },
                (Resolved::Index(at), Value::Array(items)) => {
                    match usize::try_from(*at).ok().and_then(|i| items.get(i)) {
                        Some(value) => next.push(Cur {
                            value,
                            location: cur.location.index(*at),
                            name: format!("{}[{at}]", cur.name),
                        }),
                        None => {
                            let name = format!("{}[{at}]", cur.name);
                            broken.push(broken_at(&cur, name, Cause::Absent));
                        }
                    }
                }
                _ => {
                    let name = cur.name.clone();
                    broken.push(broken_at(&cur, name, Cause::Unusable));
                }
            }
        }
        current = next;
    }
    let ends = if current.iter().any(|c| c.value.is_array()) {
        let mut kept = Vec::new();
        let mut rest = Vec::new();
        for cur in current {
            if cur.value.is_array() {
                kept.push(cur);
            } else {
                rest.push(cur);
            }
        }
        let mut items = walk_lists(kept, &mut broken, &mut walked);
        items.extend(rest);
        items
    } else {
        current
    };
    let mut entries = Vec::new();
    for cur in ends {
        match cur.value {
            Value::Object(_) if walked => entries.push(entry_of(cur)),
            Value::Null => {
                let name = cur.name.clone();
                broken.push(broken_at(&cur, name, Cause::Null));
            }
            _ if walked && !cur.value.is_object() && is_list_item(&cur.name) => {
                entries.push(entry_of(cur));
            }
            _ => {
                let name = cur.name.clone();
                broken.push(broken_at(&cur, name, Cause::Unusable));
            }
        }
    }
    finish(entries, broken)
}

fn is_list_item(name: &str) -> bool {
    name.ends_with(']')
}

fn entry_of(cur: Cur) -> Entry {
    Entry {
        at: Located {
            value: cur.value,
            location: cur.location,
        },
        key: None,
    }
}

fn finish<'a>(entries: Vec<Entry<'a>>, mut broken: Vec<Broken>) -> Read<'a> {
    broken.sort_by(|a, b| a.path.cmp(&b.path));
    Read::Entries { entries, broken }
}

fn read_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    lowered: &Lowered,
    anc: &[Anc<'a>],
) -> Read<'a> {
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
        Source::Root { path, .. } | Source::Child { path, .. } => {
            let ctx = context(env, input_root(env), anc);
            let read = path::read(path, &ctx);
            let whole_input =
                matches!(&lowered.source, Source::Root { .. }) && path.steps.is_empty();
            match read.outcome {
                Outcome::Found if whole_input && read.value.is_some_and(Value::is_array) => {
                    Read::Failed(Cause::Unusable)
                }
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

fn order(a: &Value, b: &Value) -> Ordering {
    match (a, b) {
        (Value::Bool(x), Value::Bool(y)) => x.cmp(y),
        (Value::Number(x), Value::Number(y)) => value::compare_numbers(x, y),
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

fn merged_inputs(mut inputs: Vec<Input>) -> Vec<Value> {
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
    inputs.iter().map(Input::to_json).collect()
}

struct Applied {
    matched: bool,
    cause: Cause,
    inputs: Vec<Value>,
    failed_assertions: Option<Value>,
}

fn answers_presence(filter: &Filter, verdict: &Verdict) -> bool {
    matches!(&filter.check, Check::Present(present) if !present.missing)
        && verdict.cause == Cause::Value
}

fn apply(filters: &[Filter], ctx: &Ctx) -> Applied {
    let verdicts: Vec<(&Filter, Verdict)> = filters
        .iter()
        .map(|filter| (filter, ops::run(&filter.check, ctx)))
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
            let applied = (!lowered.filters.is_empty()).then(|| apply(&lowered.filters, &ctx));
            Judged {
                entry,
                id,
                id_location,
                applied,
            }
        })
        .collect()
}

fn repeated_ids(judged: &[Judged]) -> (Vec<Value>, Vec<String>) {
    let mut sorted: Vec<&Judged> = judged.iter().collect();
    sorted.sort_by(|a, b| order(&a.id, &b.id));
    let mut groups: Vec<Vec<&Judged>> = Vec::new();
    for item in sorted {
        match groups.last_mut() {
            Some(group) if value::equal(&group[0].id, &item.id) => group.push(item),
            _ => groups.push(vec![item]),
        }
    }
    let mut repeated: Vec<Vec<&Judged>> = groups.into_iter().filter(|g| g.len() > 1).collect();
    repeated.sort_by(|a, b| {
        json_text(&a[0].id)
            .cmp(&json_text(&b[0].id))
            .then_with(|| order(&a[0].id, &b[0].id))
    });
    let mut ids = Vec::new();
    let mut locations = Vec::new();
    for group in &mut repeated {
        ids.push(group[0].id.clone());
        let mut in_order: Vec<&&Judged> = group.iter().collect();
        in_order.sort_by_key(|item| {
            judged
                .iter()
                .position(|j| std::ptr::eq(j, **item))
                .unwrap_or(usize::MAX)
        });
        for item in in_order {
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
    with_in(row, anc)
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
    let mut min = min_subjects_row(
        env.requirement_name,
        env.requirement,
        in_scope.len() as u64,
        &locations,
        read,
        Vec::new(),
    );
    if every {
        min.failed_items = Some(Value::Array(broken.iter().map(Broken::to_json).collect()));
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
    Evaluation {
        total: judged.len() as u64,
        matching: in_scope.len() as u64,
        min_subjects: vec![with_in(min, anc)],
        unique_ids: vec![with_in(unique, anc)],
        applies,
        subject_rows: Vec::new(),
    }
}

fn failed_level(env: &Env, anc: &[Anc], cause: Cause, with_unique: bool) -> Evaluation {
    let min = min_subjects_row(
        env.requirement_name,
        env.requirement,
        0,
        &[],
        Some(cause),
        Vec::new(),
    );
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
    let Some(lowered) = env.reading.lowered(parent) else {
        return vec![failed_level(env, anc, Cause::Unusable, anc.is_empty())];
    };
    let (entries, broken) = match read_entries(env, empty, lowered, anc) {
        Read::Entries { entries, broken } => (entries, broken),
        Read::Failed(cause) => return vec![failed_level(env, anc, cause, anc.is_empty())],
    };
    if let Some(cause) = Cause::worst(broken.iter().map(|b| b.cause)) {
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
    if !unreadable_params(params).is_empty() {
        return no_subjects(requirement_name, requirement, params);
    }
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
        input,
        params: params.as_object().map(|_| params),
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
    if requirement.min_subjects_count == 0 {
        for row in &mut evaluation.min_subjects {
            row.cause = Cause::Unusable;
        }
    }
    evaluation
}

fn none_found(env: &Env) -> Evaluation {
    let min = min_subjects_row(
        env.requirement_name,
        env.requirement,
        0,
        &[],
        None,
        Vec::new(),
    );
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
            "ergo_spec": "v0.2",
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
    fn the_whole_input_is_one_subject_when_it_is_an_object_and_unusable_as_a_list() {
        let r = run(json!({"thing": {"from": "$input"}}), json!({"x": 1}));
        assert_eq!(
            input_of(&rows(&r, "$min_subjects")[0], 0),
            json!({"name": "in-scope thing count", "value": 1, "locations": [""]})
        );
        let r = run(json!({"thing": {"from": "$input"}}), json!([1]));
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
            "ergo_spec": "v0.2", "subjects": {"thing": {}},
            "requirements": {"s": {"checks": {"c": "x exists"}}}
        });
        let r = report(&json!({}), &policy, &json!({}));
        assert!(rows(&r, "$min_subjects").is_empty());
    }

    #[test]
    fn params_that_are_not_an_object_leave_no_subjects_and_fail_min_subjects() {
        let r = report(
            &json!({"ds": [1]}),
            &policy(json!({"thing": {"from": "ds"}}), json!(0)),
            &json!([1]),
        );
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
        assert_eq!(r["requirements"]["s"]["subjects"]["total"], json!(0));
    }

    #[test]
    fn a_condition_no_operator_reads_yet_finds_nothing_and_fails_closed_even_with_min_zero() {
        let r = run(
            json!({"thing": {"from": "ds whose x is 1"}}),
            json!({"ds": [{"x": 1}]}),
        );
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
        assert_eq!(r["requirements"]["s"]["status"], json!("not_met"));
        assert_eq!(rows(&r, "$well_formed")[0]["passed"], json!(true));
    }

    #[test]
    fn a_child_of_a_subject_with_such_a_condition_fails_closed_too() {
        let r = run(
            json!({"art": {"from": "arts whose x is 1"}, "thing": {"from": "art.prs"}}),
            json!({"arts": [{"x": 1, "prs": [{}]}]}),
        );
        assert_eq!(rows(&r, "$min_subjects")[0]["cause"], json!("unusable"));
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
}
