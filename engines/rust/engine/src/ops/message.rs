use super::compare::{Cmp, Side, read_side};
use super::tally::{self, Side as TallySide};
use super::{Check, Input, Verdict, lists, read_path, run_full};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path, Resolved, Start, Step};
use crate::value::json_text;
use serde_json::Value;

const TEXT_LIMIT: usize = 60;
const OBJECT_LIMIT: usize = 80;
const LIST_LIMIT: usize = 3;

fn quoted(text: &str) -> String {
    let shown = if text
        .chars()
        .any(|c| c == '"' || c == '\\' || c.is_control())
    {
        json_text(&Value::String(text.to_string()))
    } else {
        format!("\"{text}\"")
    };
    one_line(&shown)
}

pub fn one_line(text: &str) -> String {
    text.replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
        .replace('\u{85}', "\\u0085")
}

fn text(s: &str) -> String {
    if s.chars().count() <= TEXT_LIMIT {
        quoted(s)
    } else {
        let head: String = s.chars().take(TEXT_LIMIT).collect();
        let shown = quoted(&head);
        format!("{}…\"", shown.strip_suffix('"').unwrap_or(&shown))
    }
}

fn literal(value: &Value) -> String {
    match value {
        Value::Array(items) => format!(
            "[{}]",
            items.iter().map(literal).collect::<Vec<_>>().join(", ")
        ),
        Value::Object(map) => format!(
            "{{{}}}",
            map.iter()
                .map(|(k, v)| format!("{}: {}", json_text(&Value::String(k.clone())), literal(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        other => json_text(other),
    }
}

fn item(value: &Value) -> String {
    match value {
        Value::String(s) => text(s),
        Value::Array(_) => literal(value),
        Value::Object(map) => {
            let whole = literal(value);
            if whole.chars().count() > OBJECT_LIMIT {
                let word = if map.len() == 1 { "key" } else { "keys" };
                format!("an object with {} {word}", map.len())
            } else {
                whole
            }
        }
        other => literal(other),
    }
}

pub fn print(value: &Value) -> String {
    match value {
        Value::Array(items) if items.len() > LIST_LIMIT => {
            let shown: Vec<String> = items.iter().take(LIST_LIMIT).map(item).collect();
            format!(
                "[{}, and {} more]",
                shown.join(", "),
                items.len() - LIST_LIMIT
            )
        }
        Value::Array(items) => {
            let shown: Vec<String> = items.iter().map(item).collect();
            format!("[{}]", shown.join(", "))
        }
        other => item(other),
    }
}

pub fn kind(value: &Value) -> &'static str {
    match value {
        Value::String(_) => "text",
        Value::Number(_) => "a number",
        Value::Bool(_) => "true or false",
        Value::Array(_) => "a list",
        Value::Object(_) => "an object",
        Value::Null => "null",
    }
}

pub fn is(name: &str, value: &Value) -> String {
    format!("{name} is {}", print(value))
}

pub fn isnt(name: &str, value: &Value, kind: &str) -> String {
    format!("{name} is {}, which isn't {kind}", print(value))
}

fn state_word(state: Outcome) -> &'static str {
    match state {
        Outcome::Absent => "missing",
        _ => "null",
    }
}

fn state_clause(input: &Input) -> Option<String> {
    match input.state {
        Outcome::Found => Some(is(&input.name, &input.value)),
        Outcome::Absent | Outcome::Null => Some(format!(
            "{} is {}",
            input.stopped_at(),
            state_word(input.state)
        )),
        _ => None,
    }
}

fn state_of(cause: Cause) -> Option<Outcome> {
    match cause {
        Cause::Absent => Some(Outcome::Absent),
        Cause::Null => Some(Outcome::Null),
        Cause::Unusable => Some(Outcome::Unusable),
        _ => None,
    }
}

fn single_path(check: &Check) -> Option<&Path> {
    match check {
        Check::Present(c) => Some(&c.path),
        Check::Equals(c) => Some(&c.path),
        Check::Range(c) => Some(&c.path),
        Check::HasType(c) => Some(&c.path),
        Check::NonEmptyString(c) => Some(&c.path),
        Check::Empty(c) => Some(&c.path),
        Check::In(c) => Some(&c.path),
        Check::Contains(c) => Some(&c.path),
        Check::Matches(c) => Some(&c.path),
        _ => None,
    }
}

fn first_input(path: &Path, ctx: &Ctx) -> Option<Input> {
    read_path(path, ctx).inputs.into_iter().next()
}

fn sources(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<Input> {
    match check {
        Check::Compare(compare) => [&compare.left, &compare.right]
            .into_iter()
            .flat_map(|side| plain_side_inputs(side, ctx))
            .collect(),
        Check::Tally(tally) => tally::tally_sides(tally)
            .into_iter()
            .flat_map(|side| tally_inputs(side, ctx, verdict.cause))
            .collect(),
        _ => match single_path(check) {
            Some(path) => {
                let mut out: Vec<Input> = first_input(path, ctx).into_iter().collect();
                let mut own = path::step_refs(path);
                own.sort_by_key(name::name);
                own.dedup();
                for reference in own {
                    out.extend(first_input(&reference, ctx));
                }
                out.extend(lists::right_inputs(check, ctx));
                out
            }
            None => verdict.inputs.clone(),
        },
    }
}

fn key_steps(path: &Path) -> impl Iterator<Item = &Path> {
    path.steps.iter().filter_map(|step| match step {
        Step::Ref(p) | Step::Field(p) => Some(&**p),
        _ => None,
    })
}

fn side_paths(check: &Check) -> Vec<&Path> {
    match check {
        Check::Compare(c) => c.left.paths().into_iter().chain(c.right.paths()).collect(),
        Check::CompareTime(c) => c.left.paths().into_iter().chain(c.right.paths()).collect(),
        Check::Tally(t) => tally::tally_sides(t)
            .into_iter()
            .flat_map(|side| match side {
                TallySide::Plain(plain) => plain.paths(),
                TallySide::Derived(derived) => {
                    let (plain, counted, elapsed) = tally::derived_operands(derived);
                    plain
                        .into_iter()
                        .chain(counted)
                        .chain(elapsed.into_iter().flat_map(|(a, b)| [a, b]))
                        .collect()
                }
            })
            .collect(),
        _ => {
            let mut paths: Vec<&Path> = single_path(check).into_iter().collect();
            paths.extend(lists::right_paths(check));
            paths
        }
    }
}

fn once_of(all: Vec<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for text in all {
        if !out.contains(&text) {
            out.push(text);
        }
    }
    out
}

fn key_states(check: &Check, ctx: &Ctx, want: Outcome) -> Vec<String> {
    once_of(
        side_paths(check)
            .into_iter()
            .flat_map(|path| key_states_of(path, ctx, want))
            .collect(),
    )
}

pub fn resolved_name(path: &Path, ctx: &Ctx) -> String {
    let steps = path
        .steps
        .iter()
        .map(|step| match path::resolve(step, ctx) {
            Ok(Resolved::Key(key)) => Step::Key(key),
            Ok(Resolved::Index(at)) => Step::Index(at),
            Err(_) => step.clone(),
        })
        .collect();
    name::name(&Path {
        start: path.start.clone(),
        steps,
    })
}

pub fn stops_at_a_null(path: &Path, ctx: &Ctx) -> bool {
    super::null_step_name(path, ctx).is_some()
}

pub fn key_states_of(path: &Path, ctx: &Ctx, want: Outcome) -> Vec<String> {
    let mut out = Vec::new();
    if stops_at_a_null(path, ctx) {
        return out;
    }
    for key in key_steps(path) {
        if let Some(input) = first_input(key, ctx)
            && input.state == want
        {
            let clause = format!("{} is {}", input.stopped_at(), state_word(want));
            if !out.contains(&clause) {
                out.push(clause);
            }
        }
    }
    out
}

fn key_faults(check: &Check, ctx: &Ctx) -> Vec<String> {
    once_of(
        side_paths(check)
            .into_iter()
            .flat_map(|path| key_faults_of(path, ctx))
            .collect(),
    )
}

pub fn key_faults_of(path: &Path, ctx: &Ctx) -> Vec<String> {
    let mut out = Vec::new();
    if stops_at_a_null(path, ctx) {
        return out;
    }
    for key in key_steps(path) {
        if let Some(input) = first_input(key, ctx)
            && input.state == Outcome::Found
            && !input.value.is_string()
        {
            let clause = isnt(&input.name, &input.value, "text");
            if !out.contains(&clause) {
                out.push(clause);
            }
        }
    }
    out
}

fn aliases_blocked(check: &Check, ctx: &Ctx) -> Vec<String> {
    check
        .sides()
        .iter()
        .flatten()
        .filter_map(|side| {
            let Start::Alias(alias) = &side.path.start else {
                return None;
            };
            let first = side.path.steps.first()?;
            let value = ctx.aliases.get(alias)?.value;
            let holder = match first {
                Step::Index(_) if !value.is_array() => "a list",
                Step::Index(_) => return None,
                _ if value.is_object() => return None,
                _ => "an object",
            };
            Some(isnt(alias, value, holder))
        })
        .collect()
}

fn blocked(check: &Check, ctx: &Ctx, late: bool) -> Vec<String> {
    let paths: Vec<&Path> = match check {
        Check::Tally(t) => tally::tally_sides(t)
            .into_iter()
            .flat_map(|side| match side {
                TallySide::Plain(plain) => plain.paths(),
                TallySide::Derived(derived) => {
                    let (plain, _, elapsed) = tally::derived_operands(derived);
                    plain
                        .into_iter()
                        .chain(elapsed.into_iter().flat_map(|(a, b)| [a, b]))
                        .collect()
                }
            })
            .collect(),
        other => side_paths(other),
    };
    let rights = lists::right_paths(check);
    once_of(
        paths
            .into_iter()
            .filter(|path| {
                (rights.contains(path) && matches!(path.start, Start::Input | Start::Params))
                    == late
            })
            .filter(|path| !rights.contains(path) || lists::walked_in(check, path, ctx).is_none())
            .flat_map(|path| blocked_of(path, ctx))
            .collect(),
    )
}

fn key_unreadable_off_alias(path: &Path, ctx: &Ctx) -> bool {
    !matches!(path.start, Start::Alias(_))
        || path.steps.iter().any(|step| {
            matches!(step, Step::Ref(reference) if !matches!(reference.start, Start::Alias(_)))
                && path::resolve(step, ctx).is_err()
        })
}

fn params_position_fault(check: &Check, ctx: &Ctx) -> Vec<String> {
    let Check::Walk(walk) = check else {
        return Vec::new();
    };
    match (&walk.path.start, walk.path.steps.first(), ctx.params) {
        (Start::Params, Some(Step::Index(_)), Some(params))
            if !params.is_array() && !params.is_null() =>
        {
            vec![isnt("$params", params, "a list")]
        }
        _ => Vec::new(),
    }
}

pub const FALLBACK: &str = "the check is false";

pub fn blocked_of(path: &Path, ctx: &Ctx) -> Vec<String> {
    let read = path::read(path, ctx);
    if read.outcome != Outcome::Unusable
        || (read.step_unreadable && key_unreadable_off_alias(path, ctx))
    {
        return Vec::new();
    }
    let Ok((mut value, _, _)) = path::start_of(&path.start, ctx) else {
        return Vec::new();
    };
    let steps: Vec<&Step> = path::leading_steps(&path.start)
        .iter()
        .chain(path.steps.iter())
        .collect();
    let leading = steps.len() - path.steps.len();
    for (at, step) in steps.iter().enumerate() {
        let Ok(resolved) = path::resolve(step, ctx) else {
            return Vec::new();
        };
        let holds = match (&resolved, value) {
            (Resolved::Key(key), Value::Object(map)) => map.get(key),
            (Resolved::Index(index), Value::Array(items)) => {
                usize::try_from(*index).ok().and_then(|i| items.get(i))
            }
            _ => None,
        };
        match holds {
            Some(next) => value = next,
            None if matches!(
                (&resolved, value),
                (Resolved::Key(_), Value::Object(_)) | (Resolved::Index(_), Value::Array(_))
            ) =>
            {
                return Vec::new();
            }
            None => {
                if at >= leading && !value.is_null() {
                    let prefix = Path {
                        start: path.start.clone(),
                        steps: path.steps[..at - leading].to_vec(),
                    };
                    let holder = if matches!(resolved, Resolved::Index(_)) {
                        "a list"
                    } else {
                        "an object"
                    };
                    let shown = name::name(&prefix);
                    let shown = if shown.is_empty() {
                        "the subject".to_string()
                    } else {
                        shown
                    };
                    return vec![isnt(&shown, value, holder)];
                }
                if let (Start::Part(part), false) = (&path.start, value.is_null()) {
                    let prefix = Path {
                        start: if part.base == Start::Alias(path::OUTER.to_string()) {
                            Start::Subject
                        } else {
                            part.base.clone()
                        },
                        steps: part.steps[..at].to_vec(),
                    };
                    let holder = if matches!(resolved, Resolved::Index(_)) {
                        "a list"
                    } else {
                        "an object"
                    };
                    let shown = name::name(&prefix);
                    let shown = if shown.is_empty() {
                        "the subject".to_string()
                    } else {
                        shown
                    };
                    return vec![format!(
                        "{} can't be read: {}",
                        part.name,
                        isnt(&shown, value, holder)
                    )];
                }
                return Vec::new();
            }
        }
    }
    Vec::new()
}

fn faults(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<String> {
    let input = single_path(check).and_then(|p| first_input(p, ctx));
    let found = input.as_ref().is_some_and(|i| i.state == Outcome::Found);
    match (check, &input) {
        (Check::Range(_), Some(i)) if found && !i.value.is_number() => {
            vec![isnt(&i.name, &i.value, "a number")]
        }
        (Check::Empty(_), Some(i)) if found && !i.value.is_string() && !i.value.is_array() => {
            vec![isnt(&i.name, &i.value, "text or a list")]
        }
        (Check::Equals(equals), Some(i))
            if found
                && !equals.value.is_null()
                && crate::value::type_name(&i.value) != crate::value::type_name(&equals.value) =>
        {
            vec![isnt(&i.name, &i.value, kind(&equals.value))]
        }
        (Check::In(c), _) => lists::in_faults(c, ctx),
        (Check::Contains(c), _) => lists::contains_faults(c, ctx),
        (Check::Matches(c), _) => lists::matches_faults(c, ctx),
        (Check::Compare(compare), _) => compare_faults(compare, ctx),
        (Check::Tally(tally), _) => tally_faults(tally, ctx),
        (Check::CompareTime(time_check), _) => time_faults(time_check, ctx),
        _ => {
            let _ = verdict;
            Vec::new()
        }
    }
}

fn compare_faults(compare: &super::compare::Compare, ctx: &Ctx) -> Vec<String> {
    let mut out = Vec::new();
    let reads = [
        (&compare.left, read_side(&compare.left, ctx)),
        (&compare.right, read_side(&compare.right, ctx)),
    ];
    let wanted = |other: &Value| -> &'static str {
        if compare.within.is_some() {
            "a number"
        } else {
            match compare.cmp {
                Cmp::Eq | Cmp::Ne => kind(other),
                Cmp::StartsWith
                | Cmp::EndsWith
                | Cmp::NotStartsWith
                | Cmp::NotEndsWith
                | Cmp::AlphabeticallyBefore
                | Cmp::AlphabeticallyAfter
                | Cmp::AlphabeticallyOnOrBefore
                | Cmp::AlphabeticallyOnOrAfter => "text",
                _ => "a number",
            }
        }
    };
    for (side, _) in &reads {
        if let Side::Join(pieces) = side {
            for piece in pieces {
                if let Side::Path(_) = piece
                    && let Some(first) = read_side(piece, ctx).inputs.into_iter().next()
                    && first.state == Outcome::Found
                    && !first.value.is_string()
                {
                    out.push(isnt(&first.name, &first.value, "text"));
                }
            }
        }
    }
    for (index, (side, read)) in reads.iter().enumerate() {
        let Side::Path(_) = side else { continue };
        let (Some(value), Some(first)) = (&read.value, read.inputs.first()) else {
            continue;
        };
        let eq_like = compare.within.is_none() && matches!(compare.cmp, Cmp::Eq | Cmp::Ne);
        let left_literal = matches!(compare.left, Side::Value(_));
        if eq_like && ((index == 1) != left_literal) {
            continue;
        }
        let other = &reads[1 - index].1;
        let want = match other.value.as_ref() {
            Some(other_value) => wanted(other_value),
            None if !eq_like && !value.is_null() => wanted(&Value::Null),
            None => continue,
        };
        if kind(value) != want {
            out.push(isnt(&first.name, value, want));
        }
    }
    out
}

fn unflawed_cause(line: &Check, ctx: &Ctx) -> Cause {
    match single_path(line).and_then(|path| first_input(path, ctx)) {
        Some(input) => match input.state {
            Outcome::Absent => Cause::Absent,
            Outcome::Null => Cause::Null,
            _ => Cause::Value,
        },
        None => Cause::Value,
    }
}

fn any_of_message(any: &super::any_of::AnyOf, ctx: &Ctx) -> String {
    let mut parts = Vec::new();
    for (at, option) in any.options.iter().enumerate() {
        let lines: Vec<String> = option
            .iter()
            .filter_map(|line| {
                let ran = run_full(line, ctx);
                if ran.verdict.passed() {
                    return None;
                }
                if let Some(said) = ran.message {
                    return Some(said);
                }
                let mut verdict = ran.verdict;
                if verdict.cause == Cause::Unusable && line.flawed(ctx) {
                    verdict.cause = unflawed_cause(line, ctx);
                }
                Some(message(line, ctx, &verdict))
            })
            .collect();
        if lines.is_empty() {
            continue;
        }
        let name = any.names.get(at).cloned().unwrap_or_default();
        let mut once: Vec<String> = Vec::new();
        for line in lines {
            if !once.contains(&line) {
                once.push(line);
            }
        }
        parts.push(format!("{name}: {}", once.join(", and ")));
    }
    if parts.is_empty() {
        FALLBACK.to_string()
    } else {
        parts.join("; ")
    }
}

pub fn message(check: &Check, ctx: &Ctx, verdict: &Verdict) -> String {
    if let Check::AnyOf(any) = check {
        return any_of_message(any, ctx);
    }
    let clauses: Vec<String> = match verdict.cause {
        Cause::Value => {
            let mut said: Vec<String> = sources(check, ctx, verdict)
                .iter()
                .filter_map(state_clause)
                .collect();
            said.extend(
                lists::walk_fault(check, ctx)
                    .filter(|(cause, _)| *cause == Cause::Value)
                    .map(|(_, text)| text),
            );
            said
        }
        Cause::Absent | Cause::Null => {
            let want = state_of(verdict.cause).unwrap_or(Outcome::Absent);
            let keys = key_states(check, ctx, want);
            if keys.is_empty() {
                let mut found: Vec<String> = sources(check, ctx, verdict)
                    .iter()
                    .filter(|i| i.state == want)
                    .map(|i| format!("{} is {}", i.stopped_at(), state_word(want)))
                    .collect();
                found.extend(
                    lists::walk_fault(check, ctx)
                        .filter(|(cause, _)| *cause == verdict.cause)
                        .map(|(_, text)| text),
                );
                if let Check::Tally(tally_check) = check {
                    for side in tally::tally_sides(tally_check) {
                        if let TallySide::Derived(derived) = side {
                            found.extend(tally::counted_texts(derived, ctx, verdict.cause));
                        }
                    }
                }
                found
            } else {
                keys
            }
        }
        Cause::Unusable => {
            let mut all = key_faults(check, ctx);
            all.extend(blocked(check, ctx, false));
            all.extend(params_position_fault(check, ctx));
            all.extend(faults(check, ctx, verdict));
            all.extend(blocked(check, ctx, true));
            all.extend(
                lists::walk_fault(check, ctx)
                    .filter(|(cause, _)| *cause == Cause::Unusable)
                    .map(|(_, text)| text),
            );
            let digits = " needs more than 15 digits";
            let others = all.iter().any(|c| !c.ends_with(digits))
                || params_that_arent_an_object(check, ctx).is_some();
            let mut once = Vec::new();
            for clause in all {
                if others && clause.ends_with(digits) {
                    continue;
                }
                if !once.contains(&clause) {
                    once.push(clause);
                }
            }
            once
        }
        Cause::NotAnObject => {
            let subject = ctx.subject.value;
            let tallies: Vec<String> = match check {
                Check::Tally(t) => tally::tally_sides(t)
                    .into_iter()
                    .filter_map(|side| match side {
                        TallySide::Derived(d) => Some(d),
                        TallySide::Plain(_) => None,
                    })
                    .flat_map(|d| tally::counted_texts(d, ctx, Cause::NotAnObject))
                    .collect(),
                _ => Vec::new(),
            };
            if subject.is_object() {
                let mut found = aliases_blocked(check, ctx);
                found.extend(lists::input_one_fault(check, ctx));
                found.extend(tallies);
                found
            } else if subject.is_array() && !tallies.is_empty() && !list_read_plainly(check, ctx) {
                tallies
            } else {
                vec![isnt(ctx.subject_label(), subject, "an object")]
            }
        }
        _ => Vec::new(),
    };
    let mut once: Vec<String> = Vec::new();
    for clause in clauses {
        if !once.contains(&clause) {
            once.push(clause);
        }
    }
    if once.is_empty() && verdict.cause == Cause::Unusable {
        once.extend(params_that_arent_an_object(check, ctx));
    }
    if once.is_empty() {
        FALLBACK.to_string()
    } else {
        once.join(", and ")
    }
}

fn list_read_plainly(check: &Check, ctx: &Ctx) -> bool {
    let Check::Tally(t) = check else {
        return false;
    };
    let mut outer = ctx.clone();
    outer
        .aliases
        .insert(path::OUTER.to_string(), ctx.subject.clone());
    tally::tally_sides(t).into_iter().any(|side| match side {
        TallySide::Plain(Side::Path(path)) => path::read(path, ctx).outcome == Outcome::NotAnObject,
        TallySide::Plain(_) => false,
        TallySide::Derived(d) => d.terms.iter().any(|term| match term {
            tally::Term::Counted(counted) => counted.whose.iter().any(|w| {
                root_flaw(&[w], &outer).is_some_and(|(cause, _)| cause == Cause::NotAnObject)
            }),
            _ => false,
        }),
    })
}

pub fn params_that_arent_an_object(check: &Check, ctx: &Ctx) -> Option<String> {
    let params = ctx.params.filter(|p| !p.is_object() && !p.is_null())?;
    let mut paths = Vec::new();
    params_paths(check, &mut paths);
    let paths: Vec<&Path> = paths
        .into_iter()
        .filter(|path| path.start == Start::Params)
        .collect();
    if paths.is_empty() {
        return None;
    }
    let mut clauses: Vec<String> = paths
        .iter()
        .filter_map(|path| params_break(path, params, ctx))
        .collect();
    clauses.sort();
    clauses.dedup();
    if clauses.is_empty() {
        Some(isnt("$params", params, "an object"))
    } else {
        Some(clauses.join(", and "))
    }
}

pub fn params_break(path: &Path, params: &Value, ctx: &Ctx) -> Option<String> {
    let mut at = params;
    for (i, step) in path.steps.iter().enumerate() {
        let key = match step {
            Step::Key(key) => Resolved::Key(key.clone()),
            Step::Index(index) => Resolved::Index(*index),
            Step::Ref(_) => path::resolve(step, ctx).ok()?,
            Step::Field(_) => return None,
        };
        let next = match (&key, at) {
            (Resolved::Key(key), Value::Object(map)) => map.get(key),
            (Resolved::Index(index), Value::Array(items)) => usize::try_from(*index)
                .ok()
                .and_then(|index| items.get(index)),
            (Resolved::Key(_), _) => {
                return Some(isnt(&params_prefix(path, i), at, "an object"));
            }
            (Resolved::Index(_), _) => {
                return Some(isnt(&params_prefix(path, i), at, "a list"));
            }
        };
        match next {
            Some(Value::Null) | None => return None,
            Some(value) => at = value,
        }
    }
    None
}

fn params_prefix(path: &Path, steps: usize) -> String {
    name::name(&Path {
        start: Start::Params,
        steps: path.steps[..steps].to_vec(),
    })
}

fn params_paths<'a>(check: &'a Check, out: &mut Vec<&'a Path>) {
    fn with_steps<'a>(path: &'a Path, out: &mut Vec<&'a Path>) {
        out.push(path);
        for step in &path.steps {
            if let Step::Ref(inner) | Step::Field(inner) = step {
                with_steps(inner, out);
            }
        }
    }
    for path in check.paths().into_iter().chain(lists::right_paths(check)) {
        with_steps(path, out);
    }
    match check {
        Check::Tally(tally) => {
            for side in std::iter::once(&tally.left).chain(tally.right.as_ref()) {
                if let TallySide::Derived(derived) = side {
                    for term in &derived.terms {
                        if let tally::Term::Counted(counted) = term {
                            with_steps(&counted.path, out);
                            for inner in &counted.whose {
                                params_paths(inner, out);
                            }
                        }
                    }
                }
            }
        }
        Check::Walk(walk) => {
            with_steps(&walk.path, out);
            for inner in walk.whose.iter().chain(std::iter::once(&*walk.check)) {
                params_paths(inner, out);
            }
        }
        Check::For(line) => {
            for item in &line.items {
                with_steps(&item.path, out);
                for inner in &item.whose {
                    params_paths(inner, out);
                }
            }
            for sentence in &line.sentences {
                params_paths(&sentence.check, out);
            }
        }
        Check::AnyOf(any) => {
            for inner in any.options.iter().flatten() {
                params_paths(inner, out);
            }
        }
        _ => {}
    }
}

pub fn stated(name: &str, cause: Cause, value: &Value, kind: &str) -> String {
    match cause {
        Cause::Absent => format!("{name} is missing"),
        Cause::Null => format!("{name} is null"),
        Cause::Unusable => isnt(name, value, kind),
        Cause::NotAnObject => isnt(name, value, "an object"),
        _ => is(name, value),
    }
}

pub fn prefixed(item: &str, said: &str) -> String {
    match said.strip_prefix("the subject ") {
        Some(rest) => format!("{item} {rest}"),
        None => format!("{item}: {said}"),
    }
}

pub fn joined(parts: Vec<String>) -> String {
    let mut once: Vec<String> = Vec::new();
    for part in parts {
        if !once.contains(&part) {
            once.push(part);
        }
    }
    if once.len() <= 3 {
        once.join("; ")
    } else {
        let more = once.len() - 3;
        let mut shown: Vec<String> = once.into_iter().take(3).collect();
        shown.push(format!("and {more} more"));
        shown.join("; ")
    }
}

fn join_text(side: &Side) -> String {
    match side {
        Side::Path(path) => {
            let shown = name::name(path);
            match shown.strip_prefix("item 1 of ") {
                Some(rest) => format!("first of {rest}"),
                None => shown,
            }
        }
        Side::Value(value) => print(value),
        Side::Join(pieces) => pieces
            .iter()
            .map(join_text)
            .collect::<Vec<_>>()
            .join(" followed by "),
    }
}

fn plain_side_inputs(side: &Side, ctx: &Ctx) -> Vec<Input> {
    match side {
        Side::Path(_) => read_side(side, ctx).inputs.into_iter().take(1).collect(),
        Side::Value(_) => Vec::new(),
        Side::Join(pieces) => {
            let read = read_side(side, ctx);
            match (read.outcome, read.value) {
                (Outcome::Found, Some(value)) => vec![Input {
                    name: join_text(side),
                    value,
                    locations: Vec::new(),
                    part: None,
                    state: Outcome::Found,
                    null_at: None,
                }],
                _ => pieces
                    .iter()
                    .flat_map(|p| plain_side_inputs(p, ctx))
                    .collect(),
            }
        }
    }
}

fn tally_inputs(side: &TallySide, ctx: &Ctx, cause: Cause) -> Vec<Input> {
    match side {
        TallySide::Plain(plain) => plain_side_inputs(plain, ctx),
        TallySide::Derived(derived) => {
            let (plain, counted, elapsed) = tally::derived_operands(derived);
            match (cause, tally::derived_value(derived, ctx)) {
                (Cause::Value, Ok(number)) => vec![Input {
                    name: derived.text.clone(),
                    value: Value::Number(number),
                    locations: Vec::new(),
                    part: None,
                    state: Outcome::Found,
                    null_at: None,
                }],
                (Cause::Value, Err(_)) | (_, _) => {
                    let _ = counted;
                    plain
                        .into_iter()
                        .chain(elapsed.into_iter().flat_map(|(a, b)| [a, b]))
                        .filter_map(|p| first_input(p, ctx))
                        .collect()
                }
            }
        }
    }
}

fn tally_side_value(side: &TallySide, ctx: &Ctx) -> Option<(String, Value, bool)> {
    match side {
        TallySide::Derived(derived) => tally::derived_value(derived, ctx)
            .ok()
            .map(|number| (derived.text.clone(), Value::Number(number), false)),
        TallySide::Plain(plain) => {
            let literal = matches!(plain, Side::Value(_));
            let read = read_side(plain, ctx);
            match (read.value, read.inputs.first()) {
                (Some(value), Some(first)) if matches!(plain, Side::Path(_)) => {
                    Some((first.name.clone(), value, false))
                }
                (Some(value), None) if literal => Some((String::new(), value, true)),
                _ => None,
            }
        }
    }
}

fn tally_side_faults(check: &tally::Tally, ctx: &Ctx) -> Vec<String> {
    let sides = tally::tally_sides(check);
    let values: Vec<Option<(String, Value, bool)>> = sides
        .iter()
        .map(|side| tally_side_value(side, ctx))
        .collect();
    let mut out = Vec::new();
    for (at, found) in values.iter().enumerate() {
        let Some((name, value, literal)) = found else {
            continue;
        };
        if *literal {
            continue;
        }
        let want: Option<&'static str> = match &check.test {
            tally::Test::Between { .. } => Some("a number"),
            tally::Test::Compare {
                within: Some(_), ..
            } => Some("a number"),
            tally::Test::Compare { cmp, .. } => match cmp {
                Cmp::Eq | Cmp::Ne => {
                    let other = values.get(1 - at.min(1)).and_then(Option::as_ref);
                    let left_literal = values
                        .first()
                        .and_then(Option::as_ref)
                        .is_some_and(|(_, _, literal)| *literal);
                    match other {
                        Some((_, other, _)) if (at == 1) == left_literal => Some(kind(other)),
                        _ => None,
                    }
                }
                Cmp::StartsWith
                | Cmp::EndsWith
                | Cmp::NotStartsWith
                | Cmp::NotEndsWith
                | Cmp::AlphabeticallyBefore
                | Cmp::AlphabeticallyAfter
                | Cmp::AlphabeticallyOnOrBefore
                | Cmp::AlphabeticallyOnOrAfter => Some("text"),
                _ => Some("a number"),
            },
        };
        if let Some(want) = want
            && kind(value) != want
        {
            out.push(isnt(name, value, want));
        }
    }
    out
}

fn tally_faults(check: &tally::Tally, ctx: &Ctx) -> Vec<String> {
    let mut out = tally_side_faults(check, ctx);
    for side in tally::tally_sides(check) {
        match side {
            TallySide::Derived(derived) => {
                let (plain, counted, elapsed) = tally::derived_operands(derived);
                let mut any = false;
                for (from, to) in elapsed {
                    let (Some(a), Some(b)) = (first_input(from, ctx), first_input(to, ctx)) else {
                        continue;
                    };
                    for part in [&a, &b] {
                        if part.state == Outcome::Found
                            && super::time::read_time(&part.value).is_none()
                        {
                            out.push(isnt(&part.name, &part.value, "a time"));
                            any = true;
                        }
                    }
                    if !any
                        && let (Some(x), Some(y)) = (
                            super::time::read_time(&a.value),
                            super::time::read_time(&b.value),
                        )
                        && std::mem::discriminant(&x) != std::mem::discriminant(&y)
                    {
                        out.push(isnt(
                            &a.name,
                            &a.value,
                            &format!("a time written like {}", print(&b.value)),
                        ));
                        any = true;
                    }
                }
                for path in &plain {
                    if let Some(input) = first_input(path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_number()
                    {
                        out.push(isnt(&input.name, &input.value, "a number"));
                        any = true;
                    }
                }
                for term in &derived.terms {
                    let tally::Term::Counted(term) = term else {
                        continue;
                    };
                    if let Some(said) = tally::counted_text(term, ctx, Cause::Unusable) {
                        out.push(said);
                        any = true;
                    } else if let Some(input) = first_input(&term.path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_array()
                        && !input.value.is_object()
                    {
                        out.push(isnt(&input.name, &input.value, "a list or an object"));
                        any = true;
                    }
                }
                let all_found = counted.iter().chain(plain.iter()).all(|path| {
                    first_input(path, ctx).is_none_or(|input| input.state == Outcome::Found)
                });
                if !any && all_found && tally::derived_value(derived, ctx).is_err() {
                    out.push(format!("{} needs more than 15 digits", derived.text));
                }
            }
            TallySide::Plain(_) => {}
        }
    }
    out
}

fn time_faults(check: &super::time::CompareTime, ctx: &Ctx) -> Vec<String> {
    let reads = [
        (&check.left, read_side(&check.left, ctx)),
        (&check.right, read_side(&check.right, ctx)),
    ];
    let mut out = Vec::new();
    let mut times = Vec::new();
    for (side, read) in &reads {
        let (Side::Path(_), Some(value), Some(first)) = (side, &read.value, read.inputs.first())
        else {
            times.push(read.value.as_ref().and_then(super::time::read_time));
            continue;
        };
        let time = super::time::read_time(value);
        if time.is_none() {
            out.push(isnt(&first.name, value, "a time"));
        }
        times.push(time);
    }
    if out.is_empty()
        && let [Some(a), Some(b)] = times.as_slice()
        && std::mem::discriminant(a) != std::mem::discriminant(b)
        && let (Side::Path(_), Some(first), Some(left), Some(right)) = (
            reads[0].0,
            reads[0].1.inputs.first(),
            reads[0].1.value.as_ref(),
            reads[1].1.value.as_ref(),
        )
    {
        out.push(isnt(
            &first.name,
            left,
            &format!("a time written like {}", print(right)),
        ));
    }
    out
}

pub fn ref_fault_list(checks: &[&Check], ctx: &Ctx) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for check in checks {
        for fault in lists::ref_faults(check, ctx) {
            if !out.contains(&fault) {
                out.push(fault);
            }
        }
    }
    out
}

pub fn first_list_text(path: &Path, ctx: &Ctx) -> Option<String> {
    let from = usize::from(!matches!(path.start, Start::Part(_)));
    (from..=path.steps.len()).find_map(|at| {
        let prefix = Path {
            start: path.start.clone(),
            steps: path.steps[..at].to_vec(),
        };
        let read = path::read(&prefix, ctx);
        read.value
            .filter(|value| value.is_array())
            .map(|value| is(&name::name(&prefix), value))
    })
}

pub struct ForItem<'a> {
    pub path: &'a Path,
    pub whose: &'a [Check],
    pub picks: bool,
}

pub fn for_empty(items: &[ForItem], ctx: &Ctx, cause: Cause) -> String {
    let want = match cause {
        Cause::Absent => Some(Outcome::Absent),
        Cause::Null => Some(Outcome::Null),
        _ => None,
    };
    let mut said: Vec<String> = Vec::new();
    if let Some(want) = want {
        said = once_of(
            items
                .iter()
                .flat_map(|item| key_states_of(item.path, ctx, want))
                .collect(),
        );
        if said.is_empty() {
            let mut clauses = Vec::new();
            for item in items {
                let mut inputs: Vec<Input> = first_input(item.path, ctx).into_iter().collect();
                let mut own = path::step_refs(item.path);
                let checks: Vec<&Check> = item.whose.iter().collect();
                own.extend(checks.iter().flat_map(|check| check.refs()));
                own.sort_by_key(name::name);
                own.dedup();
                for reference in own {
                    inputs.extend(first_input(&reference, ctx));
                }
                for input in inputs.iter().filter(|input| input.state == want) {
                    clauses.push(format!("{} is {}", input.stopped_at(), state_word(want)));
                }
            }
            said = once_of(clauses);
        }
    } else if cause == Cause::Unusable {
        let mut clauses = Vec::new();
        for item in items {
            clauses.extend(key_faults_of(item.path, ctx));
            let checks: Vec<&Check> = item.whose.iter().collect();
            clauses.extend(ref_fault_list(&checks, ctx));
        }
        said = once_of(clauses);
    }
    if said.is_empty() {
        let narrows = |item: &&ForItem| {
            !item.whose.is_empty()
                || item.picks
                || path::read(item.path, ctx)
                    .value
                    .is_some_and(|value| value.as_array().is_some_and(Vec::is_empty))
        };
        said = once_of(
            items
                .iter()
                .filter(narrows)
                .filter_map(|item| first_list_text(item.path, ctx))
                .collect(),
        );
    }
    if said.is_empty() {
        said = once_of(
            items
                .iter()
                .filter_map(|item| first_list_text(item.path, ctx))
                .collect(),
        );
    }
    if said.is_empty() {
        FALLBACK.to_string()
    } else {
        joined(said)
    }
}

pub fn subject_key_fault(check: &Check, ctx: &Ctx, cause: Cause) -> Option<String> {
    check
        .paths()
        .into_iter()
        .filter(|path| !stops_at_a_null(path, ctx))
        .flat_map(|path| path.steps.iter())
        .find_map(|step| {
            let Step::Field(field) = step else {
                return None;
            };
            if !path::names_the_subject(&field.start) {
                return None;
            }
            let read = path::read(field, ctx);
            match (read.outcome, read.value) {
                (Outcome::Found, Some(value)) if !value.is_string() && cause == Cause::Unusable => {
                    Some(isnt(&name::name(field), value, "text"))
                }
                (Outcome::Found, _) => None,
                (outcome @ (Outcome::Absent | Outcome::Null), _)
                    if outcome.cause() == Some(cause) =>
                {
                    Some(format!("{} is {}", name::name(field), state_word(outcome)))
                }
                _ => None,
            }
        })
}

pub fn reads_from_a_root(path: &Path) -> bool {
    matches!(
        path.start,
        Start::Alias(_) | Start::Part(_) | Start::Params | Start::Input
    ) && !path.steps.iter().any(|step| {
        matches!(step, Step::Field(field) if matches!(field.start, Start::Subject | Start::Own))
    })
}

fn key_text(step: &Step, ctx: &Ctx) -> Option<String> {
    let key = match step {
        Step::Field(key) | Step::Ref(key) => key,
        _ => return None,
    };
    let read = path::read(key, ctx);
    match (read.outcome, read.value) {
        (Outcome::Found, Some(value)) if !value.is_string() => {
            Some(isnt(&name::name(key), value, "text"))
        }
        (Outcome::Found, _) => None,
        (Outcome::Absent, _) => Some(format!("{} is missing", name::name(key))),
        (Outcome::Null, _) => Some(format!("{} is null", name::name(key))),
        _ => {
            let present = Check::Present(super::present::Present {
                path: (**key).clone(),
                missing: false,
            });
            let verdict = Verdict {
                cause: read.outcome.cause().unwrap_or(Cause::Unusable),
                inputs: Vec::new(),
            };
            Some(message(&present, ctx, &verdict))
        }
    }
}

pub fn root_text(path: &Path, ctx: &Ctx, cause: Cause) -> String {
    for at in 0..path.steps.len() {
        let step = &path.steps[at];
        if !matches!(step, Step::Field(_) | Step::Ref(_)) || path::resolve(step, ctx).is_ok() {
            continue;
        }
        let before = Path {
            start: path.start.clone(),
            steps: path.steps[..at].to_vec(),
        };
        let read = path::read(&before, ctx);
        if matches!(read.outcome, Outcome::Found | Outcome::Null)
            && !stops_at_a_null(&before, ctx)
            && let Some(text) = key_text(step, ctx)
        {
            return text;
        }
        break;
    }
    match cause {
        Cause::Absent => format!("{} is missing", name::name(path)),
        Cause::Null => format!(
            "{} is null",
            super::null_step_name(path, ctx).unwrap_or_else(|| name::name(path))
        ),
        _ => {
            let present = Check::Present(super::present::Present {
                path: path.clone(),
                missing: false,
            });
            message(
                &present,
                ctx,
                &Verdict {
                    cause,
                    inputs: Vec::new(),
                },
            )
        }
    }
}

pub fn root_fault(check: &Check, ctx: &Ctx, cause: Cause) -> Option<String> {
    if let Some(fault) = subject_key_fault(check, ctx, cause) {
        return Some(fault);
    }
    if !matches!(cause, Cause::Absent | Cause::Null | Cause::Unusable) {
        return None;
    }
    let mut paths = check.paths();
    paths.extend(super::walk::listed_refs(check));
    paths.into_iter().find_map(|path| {
        if !reads_from_a_root(path) || path::read(path, ctx).outcome.cause() != Some(cause) {
            return None;
        }
        Some(root_text(path, ctx, cause))
    })
}

fn first_null_step(root: &Path, ctx: &Ctx) -> Option<(Cause, String)> {
    for at in 0..root.steps.len() {
        let prefix = Path {
            start: root.start.clone(),
            steps: root.steps[..at].to_vec(),
        };
        match path::read(&prefix, ctx).outcome {
            Outcome::Found => continue,
            Outcome::Null => {
                return Some((Cause::Null, format!("{} is null", name::name(&prefix))));
            }
            _ => return None,
        }
    }
    None
}

pub fn root_flaw(checks: &[&Check], ctx: &Ctx) -> Option<(Cause, String)> {
    let mut found: Vec<(usize, Cause, String, bool)> = Vec::new();
    for (at, check) in checks.iter().enumerate() {
        if matches!(check, Check::Present(_)) {
            continue;
        }
        let mut paths = check.paths();
        paths.extend(super::walk::listed_refs(check));
        for path in paths {
            let mut roots: Vec<(Path, bool)> = Vec::new();
            for step in &path.steps {
                if let Step::Field(field) = step
                    && path::names_the_subject(&field.start)
                {
                    roots.push(((**field).clone(), true));
                }
            }
            if reads_from_a_root(path) {
                roots.push((path.clone(), false));
            }
            for (root, is_key) in roots {
                if let Start::Alias(name) = &root.start
                    && !ctx.aliases.contains_key(name)
                {
                    continue;
                }
                if lists::walked_in(check, &root, ctx).is_some() {
                    continue;
                }
                let counted = match check {
                    Check::Tally(tally) => tally.counted_paths().contains(&path),
                    _ => false,
                };
                if counted && !is_key && lists::starts_at_a_list(&root, ctx) {
                    continue;
                }
                if counted && let Some(found) = first_null_step(&root, ctx) {
                    return Some(found);
                }
                if !is_key
                    && lists::one_rights(check).contains(&&root)
                    && let Some(text) = lists::input_one_fault(check, ctx).into_iter().next()
                {
                    found.push((at, Cause::NotAnObject, text, false));
                    continue;
                }
                let read = path::read(&root, ctx);
                if let Some(cause) = read.outcome.cause() {
                    found.push((at, cause, root_text(&root, ctx, cause), is_key));
                } else if is_key && let Some(value) = read.value.filter(|value| !value.is_string())
                {
                    found.push((
                        at,
                        Cause::Unusable,
                        isnt(&name::name(&root), value, "text"),
                        true,
                    ));
                } else if !is_key
                    && lists::haystacks(check).contains(&&root)
                    && let Some(value) = read.value.filter(|value| !value.is_array())
                {
                    found.push((
                        at,
                        Cause::Unusable,
                        isnt(&name::name(&root), value, "a list"),
                        false,
                    ));
                }
            }
        }
    }
    let worst = Cause::worst(
        found
            .iter()
            .map(|(_, cause, _, _)| *cause)
            .collect::<Vec<_>>(),
    )?;
    let worst_found: Vec<&(usize, Cause, String, bool)> = found
        .iter()
        .filter(|(_, cause, _, _)| *cause == worst)
        .collect();
    let mut texts: Vec<String> = Vec::new();
    for (at, _, text, is_key) in &worst_found {
        let keyed = worst_found
            .iter()
            .any(|(other, _, _, key)| other == at && *key);
        if (*is_key || !keyed) && !texts.contains(text) {
            texts.push(text.clone());
        }
    }
    Some((worst, texts.join("; ")))
}

pub fn off_item(check: &Check, ctx: &Ctx, cause: Cause) -> Vec<String> {
    let want = match cause {
        Cause::Absent => Outcome::Absent,
        Cause::Null => Outcome::Null,
        Cause::Unusable => return off_item_lists(check, ctx),
        _ => return Vec::new(),
    };
    let mut paths: Vec<&Path> = check
        .paths()
        .into_iter()
        .filter(|path| matches!(path.start, Start::Alias(_) | Start::Part(_)))
        .filter(|path| {
            path::is_root(&path.start)
                || !path.steps.iter().any(|step| matches!(step, Step::Field(_)))
        })
        .collect();
    paths.sort_by_key(|path| name::name(path));
    paths.dedup();
    let mut out: Vec<String> = Vec::new();
    for path in paths {
        for at in 0..=path.steps.len() {
            let prefix = Path {
                start: path.start.clone(),
                steps: path.steps[..at].to_vec(),
            };
            if path::read(&prefix, ctx).outcome == want {
                let clause = format!("{} is {}", name::name(&prefix), state_word(want));
                if !out.contains(&clause) {
                    out.push(clause);
                }
                break;
            }
        }
    }
    out
}

fn off_item_lists(check: &Check, ctx: &Ctx) -> Vec<String> {
    let Check::Tally(tally_check) = check else {
        return off_item_rights(check, ctx);
    };
    let mut paths: Vec<&Path> = Vec::new();
    for side in tally::tally_sides(tally_check) {
        if let TallySide::Derived(derived) = side {
            paths.extend(
                derived
                    .terms
                    .iter()
                    .filter_map(|term| match term {
                        tally::Term::Counted(counted) => Some(&counted.path),
                        _ => None,
                    })
                    .filter(|path| matches!(path.start, Start::Alias(_) | Start::Part(_))),
            );
        }
    }
    paths.sort_by_key(|path| name::name(path));
    paths.dedup();
    let mut out: Vec<String> = Vec::new();
    for path in paths {
        let read = path::read(path, ctx);
        if let (Outcome::Found, Some(value)) = (read.outcome, read.value)
            && !value.is_array()
            && !value.is_null()
        {
            let clause = isnt(&name::name(path), value, "a list");
            if !out.contains(&clause) {
                out.push(clause);
            }
        }
    }
    out
}

fn off_item_rights(check: &Check, ctx: &Ctx) -> Vec<String> {
    let ones = lists::one_rights(check);
    let mut out: Vec<String> = Vec::new();
    for path in lists::right_paths(check) {
        if ones.contains(&path)
            || !matches!(
                path.start,
                Start::Alias(_) | Start::Part(_) | Start::Params | Start::Input
            )
            || lists::walked_in(check, path, ctx).is_some()
        {
            continue;
        }
        let read = path::read(path, ctx);
        if let (Outcome::Found, Some(value)) = (read.outcome, read.value)
            && !value.is_array()
        {
            let clause = isnt(&name::name(path), value, "a list");
            if !out.contains(&clause) {
                out.push(clause);
            }
        }
    }
    out
}
