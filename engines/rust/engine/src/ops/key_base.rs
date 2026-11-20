use super::{Check, Input, message};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path, Step};
use serde_json::Value;

/// A `named by` key, a `$input` key or a bracket key that can't be read, and
/// the value before it when that value can't take a key either.
#[derive(Debug, Clone)]
pub struct KeyBase {
    pub path: String,
    pub key: String,
    pub base: Option<(String, Cause, Input)>,
    pub off_object: bool,
    pub key_cause: Cause,
}

pub(super) fn key_flaw(key: &Path, ctx: &Ctx) -> Option<(Outcome, String, Input)> {
    let read = path::read(key, ctx);
    let named = name::name(key);
    let location: Vec<String> = read.location.iter().map(|l| l.render()).collect();
    let input = |state: Outcome, value: Value| Input {
        name: named.clone(),
        value,
        locations: location.clone(),
        part: None,
        state,
        null_at: None,
        worked: false,
    };
    match (read.outcome, read.value) {
        (Outcome::Absent, _) => Some((
            Outcome::Absent,
            format!("{named} is missing"),
            input(Outcome::Absent, Value::Null),
        )),
        (Outcome::Null, _) => Some((
            Outcome::Null,
            format!("{named} is null"),
            input(Outcome::Null, Value::Null),
        )),
        (Outcome::Found, Some(value)) if !value.is_string() => Some((
            Outcome::Unusable,
            message::isnt(&named, value, "text"),
            input(Outcome::Unusable, value.clone()),
        )),
        _ => None,
    }
}

fn base_flaw(
    start: &path::Start,
    keys: &[String],
    tally: bool,
    ctx: &Ctx,
) -> Option<(String, Cause, Input)> {
    let (mut at, mut location, _) = path::start_of(start, ctx).ok()?;
    if !at.is_object() {
        return None;
    }
    let full = Path {
        start: start.clone(),
        steps: keys.iter().map(|k| Step::Key(k.clone())).collect(),
    };
    let input = |name: String, state: Outcome, value: Value, location: &path::Location| Input {
        name,
        value,
        locations: vec![location.render()],
        part: None,
        state,
        null_at: None,
        worked: false,
    };
    for (i, key) in keys.iter().enumerate() {
        let here = Path {
            start: start.clone(),
            steps: keys[..i].iter().map(|k| Step::Key(k.clone())).collect(),
        };
        if i > 0 && at.is_null() {
            let named = name::name(&here);
            return Some((
                format!("{named} is null"),
                Cause::Null,
                input(named, Outcome::Null, Value::Null, &location),
            ));
        }
        let Some(object) = at.as_object() else {
            let named = name::name(&here);
            return Some((
                message::isnt(&named, at, "an object"),
                Cause::Unusable,
                input(named, Outcome::Unusable, at.clone(), &location),
            ));
        };
        match object.get(key) {
            None => {
                let named = name::name(&full);
                return Some((
                    format!("{named} is missing"),
                    Cause::Absent,
                    input(named, Outcome::Absent, Value::Null, &location),
                ));
            }
            Some(next) => {
                at = next;
                location = location.key(key);
            }
        }
    }
    let named = name::name(&full);
    match at {
        Value::Null => Some((
            format!("{named} is null"),
            Cause::Null,
            input(named, Outcome::Null, Value::Null, &location),
        )),
        Value::Object(_) => None,
        Value::Array(_) if tally => None,
        other => Some((
            message::isnt(
                &named,
                other,
                if tally {
                    "a list or an object"
                } else {
                    "an object"
                },
            ),
            Cause::Unusable,
            input(named, Outcome::Unusable, other.clone(), &location),
        )),
    }
}

/// The keys of `path` that can't be read, each with the value before it when
/// that value can't take a key. `tally` says the path is a list a `count of`
/// or a `sum of` walks.
pub fn of_path(path: &Path, tally: bool, ctx: &Ctx) -> Option<KeyBase> {
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, Step::Ref(key) if key_flaw(key, ctx).is_some()))?;
    let Step::Ref(key) = &path.steps[at] else {
        return None;
    };
    let (key_outcome, text, _) = key_flaw(key, ctx)?;
    let keys: Vec<String> = path.steps[..at]
        .iter()
        .map_while(|step| match step {
            Step::Key(k) => Some(k.clone()),
            _ => None,
        })
        .collect();
    let base = (!keys.is_empty()
        && keys.len() == at
        && matches!(path.start, path::Start::Subject | path::Start::Own))
    .then(|| base_flaw(&path.start, &keys, tally, ctx))
    .flatten();
    Some(KeyBase {
        path: name::name(path),
        key: text,
        base,
        off_object: matches!(path.start, path::Start::Subject | path::Start::Own)
            && matches!(path.steps.first(), Some(Step::Key(_)))
            && path::start_of(&path.start, ctx).is_ok_and(|(value, _, _)| !value.is_object()),
        key_cause: key_outcome.cause().unwrap_or(Cause::Unusable),
    })
}

/// The value before the first `named by` key of `path` when the value can't
/// take a key, and the key can't be read or comes from the item while the
/// value comes from outside it.
#[allow(dead_code)]
pub fn base_of(path: &Path, ctx: &Ctx) -> Option<(String, String, Cause)> {
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, Step::Ref(_) | Step::Field(_)))?;
    match &path.steps[at] {
        Step::Ref(key) => {
            key_flaw(key, ctx)?;
        }
        _ if super::walk::reads_outside(path) || path.start == path::Start::Params => {}
        _ => return None,
    }
    let keys: Vec<String> = path.steps[..at]
        .iter()
        .map_while(|step| match step {
            Step::Key(k) => Some(k.clone()),
            _ => None,
        })
        .collect();
    if keys.is_empty() || keys.len() != at {
        return None;
    }
    base_flaw(&path.start, &keys, false, ctx).map(|(text, cause, input)| (input.name, text, cause))
}

/// The key and base problems of every path `check` reads.
pub fn of_check(check: &Check, ctx: &Ctx) -> Vec<KeyBase> {
    let counted: Vec<&Path> = match check {
        Check::Tally(tally) => tally.counted_paths(),
        _ => Vec::new(),
    };
    let mut paths: Vec<(&Path, bool)> = counted.into_iter().map(|p| (p, true)).collect();
    paths.extend(check.paths().into_iter().map(|p| (p, false)));
    let mut out: Vec<KeyBase> = Vec::new();
    for (path, tally) in paths {
        if let Some(found) = of_path(path, tally, ctx)
            && !out.iter().any(|o| o.path == found.path)
        {
            out.push(found);
        }
    }
    out
}

/// Says each base after its key in `said`, and gives the worst cause.
pub fn said_with_bases(said: &str, cause: Cause, bases: &[KeyBase]) -> (String, Cause) {
    let mut pieces: Vec<String> = said
        .split("; ")
        .filter(|p| !p.is_empty())
        .map(str::to_string)
        .collect();
    let mut causes = vec![cause];
    for kb in bases {
        let Some((text, base_cause, _)) = &kb.base else {
            continue;
        };
        causes.push(*base_cause);
        pieces.retain(|p| p != text);
        match pieces.iter().position(|p| *p == kb.key) {
            Some(at) => pieces.insert(at + 1, text.clone()),
            None => {
                pieces.push(kb.key.clone());
                pieces.push(text.clone());
            }
        }
    }
    (pieces.join("; "), Cause::worst(causes).unwrap_or(cause))
}

fn outcome_of(cause: Cause) -> Outcome {
    match cause {
        Cause::Absent => Outcome::Absent,
        Cause::Null => Outcome::Null,
        Cause::Unusable => Outcome::Unusable,
        Cause::NotAnObject => Outcome::NotAnObject,
        _ => Outcome::Found,
    }
}

/// The outcome of an input whose own outcome is `state`, once a base problem
/// with `cause` is added to it, when that is worse.
pub fn worse_state(state: Outcome, cause: Cause) -> Option<Outcome> {
    let now = state.cause();
    let worse = Cause::worst(now.into_iter().chain([cause]))?;
    (Some(worse) != now).then(|| outcome_of(worse))
}

fn cause_of(state: Outcome) -> Option<Cause> {
    state.cause()
}

/// Rewrites a failed plain check's message and cause so that a base that
/// can't take a key is said after its key, and gives each path input the
/// worst outcome of its problems.
pub fn rewrite(
    check: &Check,
    ctx: &Ctx,
    cause: &mut Cause,
    inputs: &mut [Input],
    said: String,
) -> Option<String> {
    if !matches!(cause, Cause::Absent | Cause::Null | Cause::Unusable)
        || matches!(check, Check::Walk(_) | Check::For(_) | Check::AnyOf(_))
    {
        return None;
    }
    let bases = of_check(check, ctx);
    for kb in bases.iter().filter(|kb| kb.off_object) {
        for input in inputs.iter_mut().filter(|i| i.name == kb.path) {
            input.state = Outcome::NotAnObject;
        }
    }
    if !bases.iter().any(|b| b.base.is_some()) {
        return None;
    }
    let (text, worst) = said_with_bases(&said, *cause, &bases);
    *cause = worst;
    for kb in &bases {
        let Some((_, base_cause, _)) = &kb.base else {
            continue;
        };
        for input in inputs.iter_mut().filter(|i| i.name == kb.path) {
            let now = cause_of(input.state);
            let worse = Cause::worst(now.into_iter().chain([*base_cause, kb.key_cause]))
                .unwrap_or(*base_cause);
            input.state = outcome_of(worse);
        }
    }
    Some(text)
}

/// The key and base inputs a failed plain check's assertion entry adds after
/// `inputs`.
pub fn entry_inputs(
    check: &Check,
    ctx: &Ctx,
    cause: Cause,
    inputs: &[serde_json::Value],
) -> Vec<serde_json::Value> {
    if !matches!(cause, Cause::Absent | Cause::Null | Cause::Unusable)
        || matches!(check, Check::Walk(_) | Check::For(_) | Check::AnyOf(_))
    {
        return Vec::new();
    }
    let named = |v: &serde_json::Value| {
        v.get("name")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string)
    };
    let mut seen: Vec<String> = inputs.iter().filter_map(named).collect();
    let bases = of_check(check, ctx);
    let mut keys: Vec<serde_json::Value> = Vec::new();
    for path in every_path(check) {
        for step in &path.steps {
            let Step::Ref(key) = step else {
                continue;
            };
            let Some((_, _, input)) = key_flaw(key, ctx) else {
                continue;
            };
            if seen.contains(&input.name) {
                continue;
            }
            seen.push(input.name.clone());
            keys.push(crate::parts::with_outcome(&input, false));
        }
    }
    keys.sort_by_key(|a| named(a));
    for kb in &bases {
        if let Some((_, _, input)) = &kb.base
            && !seen.contains(&input.name)
        {
            seen.push(input.name.clone());
            keys.push(crate::parts::with_outcome(input, false));
        }
    }
    keys
}

/// Every path `check` reads, in its `whose` and inner checks too.
pub fn every_path(check: &Check) -> Vec<&Path> {
    let mut out: Vec<&Path> = Vec::new();
    for inner in super::for_line::nested_checks(check) {
        out.extend(inner.paths());
        if let Check::Walk(walk) = inner {
            out.push(&walk.path);
        }
        if let Check::Tally(tally) = inner {
            out.extend(tally.counted_paths());
        }
    }
    out
}

/// `o is []` when the value before the first key of `path` that can't be
/// read is an empty list.
pub fn empty_base(path: &Path, ctx: &Ctx) -> Option<String> {
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, Step::Ref(key) if key_flaw(key, ctx).is_some()))?;
    if at == 0 || !path.steps[..at].iter().all(|s| matches!(s, Step::Key(_))) {
        return None;
    }
    let before = Path {
        start: path.start.clone(),
        steps: path.steps[..at].to_vec(),
    };
    let read = path::read(&before, ctx);
    match (read.outcome, read.value) {
        (Outcome::Found, Some(Value::Array(items))) if items.is_empty() => {
            Some(format!("{} is []", name::name(&before)))
        }
        _ => None,
    }
}

/// A `for` line's first list whose `named by` key can't be read: the key's
/// input and text, and the problem of the value before the key, when it has
/// one (an empty list is one unless the line says `, if any,`).
pub struct ForKey {
    pub key: Input,
    pub key_text: String,
    pub base: Option<(String, Cause, Input)>,
}

/// The [`ForKey`] of a `for` line's first list `path`.
pub fn for_list(path: &Path, if_any: bool, ctx: &Ctx) -> Option<ForKey> {
    if !matches!(path.start, path::Start::Subject | path::Start::Own) {
        return None;
    }
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, Step::Ref(key) if key_flaw(key, ctx).is_some()))?;
    let Step::Ref(key) = &path.steps[at] else {
        return None;
    };
    let (_, key_text, key) = key_flaw(key, ctx)?;
    let keys: Vec<String> = path.steps[..at]
        .iter()
        .map_while(|step| match step {
            Step::Key(k) => Some(k.clone()),
            _ => None,
        })
        .collect();
    let mut base = None;
    if !keys.is_empty() && keys.len() == at {
        base = base_flaw(&path.start, &keys, true, ctx);
        if base.is_none() && !if_any {
            let before = Path {
                start: path.start.clone(),
                steps: path.steps[..at].to_vec(),
            };
            let read = path::read(&before, ctx);
            if let (Outcome::Found, Some(Value::Array(items))) = (read.outcome, read.value)
                && items.is_empty()
            {
                let named = name::name(&before);
                base = Some((
                    format!("{named} is []"),
                    Cause::Value,
                    Input {
                        name: named,
                        value: Value::Array(Vec::new()),
                        locations: read.location.iter().map(|l| l.render()).collect(),
                        part: None,
                        state: Outcome::Found,
                        null_at: None,
                        worked: false,
                    },
                ));
            }
        }
    }
    Some(ForKey {
        key,
        key_text,
        base,
    })
}

/// For a path that starts at a `for` alias and whose `$params` or `$input`
/// key can't be read: the key's text, and the problem of the value before
/// the key with its cause, when that value can't take a key.
pub fn alias_base(path: &Path, ctx: &Ctx) -> Option<(String, String, Cause)> {
    if !matches!(path.start, path::Start::Alias(_)) {
        return None;
    }
    let at = path.steps.iter().position(|step| {
        matches!(step, Step::Ref(key) if matches!(key.start, path::Start::Params | path::Start::Input) && key_flaw(key, ctx).is_some())
    })?;
    let Step::Ref(key) = &path.steps[at] else {
        return None;
    };
    let (_, key_text, _) = key_flaw(key, ctx)?;
    let keys: Vec<String> = path.steps[..at]
        .iter()
        .map_while(|step| match step {
            Step::Key(k) => Some(k.clone()),
            _ => None,
        })
        .collect();
    if keys.is_empty() || keys.len() != at {
        return None;
    }
    let (start, _, _) = path::start_of(&path.start, ctx).ok()?;
    if start.is_null() {
        let named = name::name(&Path {
            start: path.start.clone(),
            steps: Vec::new(),
        });
        return Some((key_text, format!("{named} is null"), Cause::Null));
    }
    let (text, cause, _) = base_flaw(&path.start, &keys, false, ctx)?;
    Some((key_text, text, cause))
}

/// What a `whose` check says about each `$params` or `$input` key it reads
/// that is missing or `null`, with the cause: said once, before any item.
pub fn missing_keys(check: &Check, ctx: &Ctx) -> Vec<(Cause, String)> {
    let mut out: Vec<(Cause, String)> = Vec::new();
    for path in check.paths() {
        for step in &path.steps {
            let Step::Ref(key) = step else {
                continue;
            };
            if !matches!(key.start, path::Start::Params | path::Start::Input) {
                continue;
            }
            match key_flaw(key, ctx) {
                Some((outcome @ (Outcome::Absent | Outcome::Null), text, _)) => {
                    if !out.iter().any(|(_, t)| *t == text) {
                        out.push((outcome.cause().unwrap_or(Cause::Absent), text));
                    }
                }
                Some(_) => return Vec::new(),
                None => {}
            }
        }
    }
    out
}

/// What a check says about each `$params` or `$input` key it reads that
/// holds something other than text.
pub fn unusable_keys(check: &Check, ctx: &Ctx) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for path in check.paths() {
        for step in &path.steps {
            if let Step::Ref(key) = step
                && matches!(key.start, path::Start::Params | path::Start::Input)
                && let Some((Outcome::Unusable, text, _)) = key_flaw(key, ctx)
                && !out.contains(&text)
            {
                out.push(text);
            }
        }
    }
    out
}

/// Whether `path` has a `named by` key read from the subject or an alias,
/// not from `$params` or `$input`, that can't be read or isn't text.
pub fn field_key_flawed(path: &Path, ctx: &Ctx) -> bool {
    path.steps.iter().any(|step| match step {
        Step::Ref(key) | Step::Field(key) => {
            !matches!(key.start, path::Start::Params | path::Start::Input)
                && key_flaw(key, ctx).is_some()
        }
        _ => false,
    })
}

/// The problem of the value before the first key of a `from` line's `path`
/// that can't be read, when that value can't take a key, with its cause.
pub fn from_base(path: &Path, ctx: &Ctx) -> Option<(String, Cause)> {
    let at = path
        .steps
        .iter()
        .position(|step| matches!(step, Step::Ref(key) if key_flaw(key, ctx).is_some()))?;
    let keys: Vec<String> = path.steps[..at]
        .iter()
        .map_while(|step| match step {
            Step::Key(k) => Some(k.clone()),
            _ => None,
        })
        .collect();
    if keys.is_empty() || keys.len() != at {
        return None;
    }
    base_flaw(&path.start, &keys, true, ctx).map(|(text, cause, _)| (text, cause))
}

#[cfg(test)]
mod tests;
