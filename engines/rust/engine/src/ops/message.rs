use super::compare::{Cmp, Side, read_side};
use super::{Check, Input, Verdict, lists, read_path};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path, Resolved, Step};
use crate::value::json_text;
use serde_json::Value;

const TEXT_LIMIT: usize = 60;
const OBJECT_LIMIT: usize = 80;
const LIST_LIMIT: usize = 3;

fn quoted(text: &str) -> String {
    if text.chars().any(|c| c == '"' || c == '\\' || c.is_control()) {
        json_text(&Value::String(text.to_string()))
    } else {
        format!("\"{text}\"")
    }
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
                format!("an object with {} keys", map.len())
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
        Outcome::Absent | Outcome::Null => {
            Some(format!("{} is {}", input.name, state_word(input.state)))
        }
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

fn sorted_refs(check: &Check) -> Vec<Path> {
    let mut refs = check.refs();
    refs.sort_by_key(name::name);
    refs.dedup();
    refs
}

fn sources(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<Input> {
    match check {
        Check::Compare(compare) => [&compare.left, &compare.right]
            .into_iter()
            .filter_map(|side| match side {
                Side::Path(_) => read_side(side, ctx).inputs.into_iter().next(),
                _ => None,
            })
            .collect(),
        _ => match single_path(check) {
            Some(path) => {
                let mut out: Vec<Input> = first_input(path, ctx).into_iter().collect();
                for reference in sorted_refs(check) {
                    out.extend(first_input(&reference, ctx));
                }
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

fn key_states(check: &Check, ctx: &Ctx, want: Outcome) -> Vec<String> {
    let Some(path) = single_path(check) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for key in key_steps(path) {
        if let Some(input) = first_input(key, ctx) {
            if input.state == want {
                let clause = format!("{} is {}", input.name, state_word(want));
                if !out.contains(&clause) {
                    out.push(clause);
                }
            }
        }
    }
    out
}

fn key_faults(check: &Check, ctx: &Ctx) -> Vec<String> {
    let Some(path) = single_path(check) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for key in key_steps(path) {
        if let Some(input) = first_input(key, ctx) {
            if input.state == Outcome::Found && !input.value.is_string() {
                let clause = isnt(&input.name, &input.value, "text");
                if !out.contains(&clause) {
                    out.push(clause);
                }
            }
        }
    }
    out
}

fn blocked(check: &Check, ctx: &Ctx) -> Vec<String> {
    let Some(path) = single_path(check) else {
        return Vec::new();
    };
    let read = path::read(path, ctx);
    if read.outcome != Outcome::Unusable || read.step_unreadable {
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
            None => {
                if at > leading && !value.is_null() {
                    let prefix = Path {
                        start: path.start.clone(),
                        steps: path.steps[..at - leading].to_vec(),
                    };
                    let holder = if matches!(resolved, Resolved::Index(_)) {
                        "a list"
                    } else {
                        "an object"
                    };
                    return vec![isnt(&name::name(&prefix), value, holder)];
                }
                return Vec::new();
            }
        }
    }
    Vec::new()
}

fn faults(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<String> {
    let input = single_path(check).and_then(|p| first_input(p, ctx));
    let found = input
        .as_ref()
        .is_some_and(|i| i.state == Outcome::Found);
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
    for (index, (side, read)) in reads.iter().enumerate() {
        let Side::Path(_) = side else { continue };
        let (Some(value), Some(first)) = (&read.value, read.inputs.first()) else {
            continue;
        };
        let other = &reads[1 - index].1;
        let want = wanted(other.value.as_ref().unwrap_or(&Value::Null));
        if kind(value) != want {
            out.push(isnt(&first.name, value, want));
        }
    }
    out
}

pub fn message(check: &Check, ctx: &Ctx, verdict: &Verdict) -> String {
    let clauses: Vec<String> = match verdict.cause {
        Cause::Value => sources(check, ctx, verdict)
            .iter()
            .filter_map(state_clause)
            .collect(),
        Cause::Absent | Cause::Null => {
            let want = state_of(verdict.cause).unwrap_or(Outcome::Absent);
            let keys = key_states(check, ctx, want);
            if keys.is_empty() {
                sources(check, ctx, verdict)
                    .iter()
                    .filter(|i| i.state == want)
                    .map(|i| format!("{} is {}", i.name, state_word(want)))
                    .collect()
            } else {
                keys
            }
        }
        Cause::Unusable => {
            let mut all = key_faults(check, ctx);
            all.extend(blocked(check, ctx));
            all.extend(faults(check, ctx, verdict));
            let mut once = Vec::new();
            for clause in all {
                if !once.contains(&clause) {
                    once.push(clause);
                }
            }
            once
        }
        Cause::NotAnObject => {
            let subject = ctx.subject.value;
            if subject.is_object() {
                Vec::new()
            } else {
                vec![isnt("it", subject, "an object")]
            }
        }
        _ => Vec::new(),
    };
    if clauses.is_empty() {
        "the check is false".to_string()
    } else {
        clauses.join(", and ")
    }
}
