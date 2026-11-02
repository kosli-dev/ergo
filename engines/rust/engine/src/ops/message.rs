use super::compare::{Cmp, Side, read_side};
use super::tally::{self, Side as TallySide};
use super::{Check, Input, Verdict, lists, read_path, run as run_check};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, Outcome, Path, Resolved, Step};
use crate::value::json_text;
use serde_json::Value;

const TEXT_LIMIT: usize = 60;
const OBJECT_LIMIT: usize = 80;
const LIST_LIMIT: usize = 3;

fn quoted(text: &str) -> String {
    if text
        .chars()
        .any(|c| c == '"' || c == '\\' || c.is_control())
    {
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

pub fn shown_names(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<String> {
    sources(check, ctx, verdict)
        .into_iter()
        .map(|i| i.name)
        .collect()
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
        _ => single_path(check).into_iter().collect(),
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

pub fn key_states_of(path: &Path, ctx: &Ctx, want: Outcome) -> Vec<String> {
    let mut out = Vec::new();
    for key in key_steps(path) {
        if let Some(input) = first_input(key, ctx)
            && input.state == want
        {
            let clause = format!("{} is {}", input.name, state_word(want));
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

fn blocked(check: &Check, ctx: &Ctx) -> Vec<String> {
    single_path(check).map_or_else(Vec::new, |path| blocked_of(path, ctx))
}

pub fn blocked_of(path: &Path, ctx: &Ctx) -> Vec<String> {
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
                        "it".to_string()
                    } else {
                        shown
                    };
                    return vec![isnt(&shown, value, holder)];
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
        let want = wanted(other.value.as_ref().unwrap_or(&Value::Null));
        if kind(value) != want {
            out.push(isnt(&first.name, value, want));
        }
    }
    out
}

fn any_of_message(any: &super::any_of::AnyOf, ctx: &Ctx) -> String {
    let mut parts = Vec::new();
    for (at, option) in any.options.iter().enumerate() {
        let lines: Vec<String> = option
            .iter()
            .filter_map(|line| {
                let verdict = run_check(line, ctx);
                (!verdict.passed()).then(|| message(line, ctx, &verdict))
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
        "the check is false".to_string()
    } else {
        parts.join("; ")
    }
}

pub fn message(check: &Check, ctx: &Ctx, verdict: &Verdict) -> String {
    if let Check::AnyOf(any) = check {
        return any_of_message(any, ctx);
    }
    let clauses: Vec<String> = match verdict.cause {
        Cause::Value => sources(check, ctx, verdict)
            .iter()
            .filter_map(state_clause)
            .collect(),
        Cause::Absent | Cause::Null => {
            let want = state_of(verdict.cause).unwrap_or(Outcome::Absent);
            let keys = key_states(check, ctx, want);
            if keys.is_empty() {
                let mut found: Vec<String> = sources(check, ctx, verdict)
                    .iter()
                    .filter(|i| i.state == want)
                    .map(|i| format!("{} is {}", i.name, state_word(want)))
                    .collect();
                if let Check::Tally(tally_check) = check {
                    for side in tally::tally_sides(tally_check) {
                        if let TallySide::Derived(derived) = side {
                            let said = tally::counted_texts(derived, ctx, verdict.cause);
                            if !said.is_empty() {
                                found.push(joined(said));
                            }
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
    let mut once: Vec<String> = Vec::new();
    for clause in clauses {
        if !once.contains(&clause) {
            once.push(clause);
        }
    }
    if once.is_empty() {
        "the check is false".to_string()
    } else {
        once.join(", and ")
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
    match said.strip_prefix("it ") {
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
        Side::Path(path) => name::name(path),
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
            let (plain, counted) = tally::derived_operands(derived);
            match (cause, tally::derived_value(derived, ctx)) {
                (Cause::Value, Ok(number)) => vec![Input {
                    name: derived.text.clone(),
                    value: Value::Number(number),
                    locations: Vec::new(),
                    part: None,
                    state: Outcome::Found,
                }],
                (Cause::Value, Err(_)) | (_, _) => {
                    let _ = counted;
                    plain
                        .into_iter()
                        .filter_map(|p| first_input(p, ctx))
                        .collect()
                }
            }
        }
    }
}

fn tally_faults(check: &tally::Tally, ctx: &Ctx) -> Vec<String> {
    let mut out = Vec::new();
    for side in tally::tally_sides(check) {
        match side {
            TallySide::Derived(derived) => {
                let (plain, counted) = tally::derived_operands(derived);
                let mut any = false;
                for path in plain {
                    if let Some(input) = first_input(path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_number()
                    {
                        out.push(isnt(&input.name, &input.value, "a number"));
                        any = true;
                    }
                }
                for path in counted {
                    if let Some(input) = first_input(path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_array()
                        && !input.value.is_object()
                    {
                        out.push(isnt(&input.name, &input.value, "a list or an object"));
                        any = true;
                    }
                }
                let counted_said = tally::counted_texts(derived, ctx, Cause::Unusable);
                if !counted_said.is_empty() {
                    out.push(joined(counted_said));
                    any = true;
                }
                if !any && tally::derived_value(derived, ctx).is_err() {
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

pub fn flawed_text(checks: &[&Check], ctx: &Ctx) -> Option<String> {
    let mut out: Vec<String> = Vec::new();
    for check in checks {
        for fault in lists::ref_faults(check, ctx) {
            if !out.contains(&fault) {
                out.push(fault);
            }
        }
    }
    (!out.is_empty()).then(|| out.join(", and "))
}
