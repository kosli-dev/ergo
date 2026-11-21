use super::clause::{self, Clause};
use super::compare::{Cmp, Side, read_side};
use super::tally::{self, Side as TallySide};
use super::{Check, Input, Verdict, lists, push_new, read_path, run_full};
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

/// A value a check can't use, as the name it was read by and what the
/// check says of it, like `("x", "x is \"1\", which isn't a number")`.
pub fn fault(name: &str, value: &Value, kind: &str) -> (String, String) {
    (name.to_string(), isnt(name, value, kind))
}

/// The names of the values `check` can't use, which its message says when
/// it fails as `unusable`.
pub(crate) fn unfit_names(check: &Check, ctx: &Ctx) -> Vec<String> {
    faults(check, ctx)
        .into_iter()
        .map(|(name, _)| name)
        .collect()
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

/// The paths of the values `check` compares or tests, not the keys it reads
/// on the way.
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
        Check::AnyOf(any) => any.options.iter().flatten().flat_map(side_paths).collect(),
        _ => {
            let mut paths: Vec<&Path> = single_path(check).into_iter().collect();
            paths.extend(lists::right_paths(check));
            paths
        }
    }
}

pub fn once_of(all: Vec<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for text in all {
        push_new(&mut out, text);
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
            push_new(&mut out, clause);
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
            push_new(&mut out, clause);
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
    let pieces = lists::join_pieces(check);
    once_of(
        paths
            .into_iter()
            .filter(|path| {
                (rights.contains(path)
                    && !pieces.contains(path)
                    && matches!(path.start, Start::Input | Start::Params))
                    == late
            })
            .filter(|path| !rights.contains(path) || lists::walked_in(check, path, ctx).is_none())
            .flat_map(|path| blocked_of(path, ctx))
            .collect(),
    )
}

fn refs_blocked(check: &tally::Tally, ctx: &Ctx) -> Vec<String> {
    let mut refs = check.refs();
    refs.sort_by_key(name::name);
    once_of(
        refs.iter()
            .flat_map(|r| {
                if lists::input_one_path(r, ctx) {
                    vec![isnt("$input", ctx.input, "an object")]
                } else {
                    blocked_of(r, ctx)
                }
            })
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

/// One part of a check's message: a text, or what a `count of` or `sum of`
/// says, as its clauses.
#[derive(Debug, Clone, PartialEq)]
pub enum Piece {
    Said(String),
    Counted(Vec<Clause>),
}

impl Piece {
    #[must_use]
    pub fn text(&self) -> String {
        match self {
            Piece::Said(text) => text.clone(),
            Piece::Counted(clauses) => clause::text(&clause::shown(clauses)),
        }
    }
}

/// The message the pieces make, joined with `, and `.
#[must_use]
pub fn pieces_text(pieces: &[Piece]) -> String {
    pieces
        .iter()
        .map(Piece::text)
        .collect::<Vec<_>>()
        .join(", and ")
}

/// What a check says, as groups of pieces: the pieces of a group are joined
/// with `, and `, and the groups with `; `.
pub type Said = Vec<Vec<Piece>>;

/// The message `said` makes.
#[must_use]
pub fn said_text(said: &[Vec<Piece>]) -> String {
    said.iter()
        .map(|group| pieces_text(group))
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>()
        .join("; ")
}

/// A message held as one piece of text.
#[must_use]
pub fn said_as_text(text: String) -> Said {
    vec![vec![Piece::Said(text)]]
}

fn push_piece(pieces: &mut Vec<Piece>, piece: Piece) {
    let text = piece.text();
    if !pieces.iter().any(|said| said.text() == text) {
        pieces.push(piece);
    }
}

fn said_all(texts: impl IntoIterator<Item = String>) -> impl Iterator<Item = Piece> {
    texts.into_iter().map(Piece::Said)
}

pub fn blocked_of(path: &Path, ctx: &Ctx) -> Vec<String> {
    let read = path::read(path, ctx);
    if read.outcome != Outcome::Unusable
        || (read.step_unreadable && key_unreadable_off_alias(path, ctx))
    {
        return Vec::new();
    }
    blocked_along(path, ctx)
}

pub fn blocked_before_key(path: &Path, ctx: &Ctx) -> Vec<String> {
    let read = path::read(path, ctx);
    if read.outcome != Outcome::Unusable || !read.step_unreadable {
        return Vec::new();
    }
    blocked_along(path, ctx)
}

fn blocked_along(path: &Path, ctx: &Ctx) -> Vec<String> {
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

fn faults(check: &Check, ctx: &Ctx) -> Vec<(String, String)> {
    let input = single_path(check).and_then(|p| first_input(p, ctx));
    let found = input.as_ref().is_some_and(|i| i.state == Outcome::Found);
    match (check, &input) {
        (Check::Range(_), Some(i)) if found && !i.value.is_number() => {
            vec![fault(&i.name, &i.value, "a number")]
        }
        (Check::Empty(_), Some(i)) if found && !i.value.is_string() && !i.value.is_array() => {
            vec![fault(&i.name, &i.value, "text or a list")]
        }
        (Check::Equals(equals), Some(i))
            if found
                && !equals.value.is_null()
                && crate::value::type_name(&i.value) != crate::value::type_name(&equals.value) =>
        {
            vec![fault(&i.name, &i.value, kind(&equals.value))]
        }
        (Check::In(c), _) => lists::in_faults(c, ctx),
        (Check::Contains(c), _) => lists::contains_faults(c, ctx),
        (Check::Matches(c), _) => lists::matches_faults(c, ctx),
        (Check::Compare(compare), _) => compare_faults(compare, ctx),
        (Check::Tally(tally), _) => tally_faults(tally, ctx)
            .into_iter()
            .map(|(name, piece)| (name, piece.text()))
            .collect(),
        (Check::CompareTime(time_check), _) => time_faults(time_check, ctx),
        _ => Vec::new(),
    }
}

fn compare_faults(compare: &super::compare::Compare, ctx: &Ctx) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let reads = [
        (&compare.left, read_side(&compare.left, ctx)),
        (&compare.right, read_side(&compare.right, ctx)),
    ];
    let wanted = |other: &Value| -> &'static str {
        if compare.ignoring.is_some() {
            "text"
        } else if compare.within.is_some() {
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
                    out.push(fault(&first.name, &first.value, "text"));
                }
            }
        }
    }
    for (index, (side, read)) in reads.iter().enumerate() {
        let Side::Path(_) = side else { continue };
        let (Some(value), Some(first)) = (&read.value, read.inputs.first()) else {
            continue;
        };
        let eq_like = compare.within.is_none()
            && compare.ignoring.is_none()
            && matches!(compare.cmp, Cmp::Eq | Cmp::Ne);
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
            out.push(fault(&first.name, value, want));
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

/// What an `any_of` line that didn't pass says, as its groups of pieces.
pub fn option_line_said(line: &Check, ctx: &Ctx, said: Option<String>, verdict: &Verdict) -> Said {
    if let Some(said) = said {
        return said_as_text(said);
    }
    let mut verdict = verdict.clone();
    if verdict.cause == Cause::Unusable && line.flawed(ctx) {
        verdict.cause = unflawed_cause(line, ctx);
    }
    self::said(line, ctx, &verdict)
}

pub(crate) fn split_outside_quotes<'t>(text: &'t str, by: &str) -> Vec<&'t str> {
    let mut out = Vec::new();
    let mut from = 0;
    let mut quoted = false;
    let mut escaped = false;
    let bytes = text.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        let byte = bytes[at];
        if escaped {
            escaped = false;
        } else if byte == b'\\' && quoted {
            escaped = true;
        } else if byte == b'"' {
            quoted = !quoted;
        } else if !quoted && text[at..].starts_with(by) {
            out.push(&text[from..at]);
            at += by.len();
            from = at;
            continue;
        }
        at += 1;
    }
    out.push(&text[from..]);
    out
}

/// `text` without the clauses `said` held before it, adding the ones it
/// keeps to `said`. A clause is a piece of `text` between `; ` or `, and `, outside
/// quoted strings.
pub fn unsaid(text: &str, said: &mut Vec<String>) -> String {
    let before = said.len();
    let mut groups: Vec<String> = Vec::new();
    for group in split_outside_quotes(text, "; ") {
        let mut kept: Vec<&str> = Vec::new();
        for clause in split_outside_quotes(group, ", and ") {
            if clause.is_empty() || said[..before].iter().any(|s| s == clause) {
                continue;
            }
            said.push(clause.to_string());
            kept.push(clause);
        }
        if !kept.is_empty() {
            groups.push(kept.join(", and "));
        }
    }
    groups.join("; ")
}

/// `said` without the clauses `seen` held before it, adding the ones it keeps
/// to `seen`.
pub fn unsaid_clauses(said: &Said, seen: &mut Vec<Clause>) -> Said {
    let before = seen.len();
    let mut out: Said = Vec::new();
    for group in said {
        let mut kept: Vec<Piece> = Vec::new();
        for piece in group {
            let clauses = match piece {
                Piece::Said(text) if text.is_empty() => continue,
                Piece::Said(text) => vec![Clause::said(Cause::Value, text.clone())],
                Piece::Counted(clauses) => clauses.clone(),
            };
            let fresh: Vec<Clause> = clauses
                .into_iter()
                .filter(|clause| !seen[..before].contains(clause))
                .collect();
            if fresh.is_empty() {
                continue;
            }
            seen.extend(fresh.iter().cloned());
            kept.push(match piece {
                Piece::Said(_) => piece.clone(),
                Piece::Counted(_) => Piece::Counted(fresh),
            });
        }
        if !kept.is_empty() {
            out.push(kept);
        }
    }
    out
}

/// The groups of pieces `text` holds, cut at `; ` and `, and ` outside quoted
/// strings, for a message that is only text, like a `for` line's.
pub fn said_of_text(text: &str) -> Said {
    split_outside_quotes(text, "; ")
        .into_iter()
        .map(|group| {
            split_outside_quotes(group, ", and ")
                .into_iter()
                .filter(|clause| !clause.is_empty())
                .map(|clause| Piece::Said(clause.to_string()))
                .collect::<Vec<Piece>>()
        })
        .filter(|group| !group.is_empty())
        .collect()
}

/// What a run says, as pieces: its clauses when it has them and they make its
/// message, its message cut into clauses otherwise.
pub fn ran_said(ran: &super::Ran) -> Option<Said> {
    let text = ran.message.as_ref()?;
    match &ran.parts {
        Some(parts) if !parts.is_empty() && clause::text(&clause::shown(parts)) == *text => {
            Some(vec![vec![Piece::Counted(parts.clone())]])
        }
        _ => Some(said_of_text(text)),
    }
}

fn any_of_message(any: &super::any_of::AnyOf, ctx: &Ctx) -> String {
    let mut parts = Vec::new();
    for (at, option) in any.options.iter().enumerate() {
        let lines: Vec<Said> = option
            .iter()
            .filter_map(|line| {
                let ran = run_full(line, ctx);
                if ran.verdict.passed() {
                    return None;
                }
                Some(
                    ran_said(&ran)
                        .unwrap_or_else(|| option_line_said(line, ctx, None, &ran.verdict)),
                )
            })
            .collect();
        if lines.is_empty() {
            continue;
        }
        let name = any.names.get(at).cloned().unwrap_or_default();
        let mut seen: Vec<Clause> = Vec::new();
        let once: Vec<String> = lines
            .iter()
            .map(|line| said_text(&unsaid_clauses(line, &mut seen)))
            .filter(|line| !line.is_empty())
            .collect();
        parts.push(format!("{name}: {}", once.join(", and ")));
    }
    if parts.is_empty() {
        FALLBACK.to_string()
    } else {
        parts.join("; ")
    }
}

pub fn null_key_parts(path: &Path, ctx: &Ctx) -> Vec<String> {
    let Some(at) = path.steps.iter().position(|step| {
        matches!(step, Step::Field(_) | Step::Ref(_)) && path::resolve(step, ctx).is_err()
    }) else {
        return Vec::new();
    };
    let first = usize::from(path.start == Start::Subject);
    let null_at = (first..=at).find(|end| {
        let prefix = Path {
            start: path.start.clone(),
            steps: path.steps[..*end].to_vec(),
        };
        path::read(&prefix, ctx).outcome == Outcome::Null
    });
    let (Some(end), Some(key)) = (null_at, key_text(&path.steps[at], ctx)) else {
        return Vec::new();
    };
    let prefix = Path {
        start: path.start.clone(),
        steps: path.steps[..end].to_vec(),
    };
    vec![format!("{} is null", name::name(&prefix)), key]
}

pub fn message(check: &Check, ctx: &Ctx, verdict: &Verdict) -> String {
    said_text(&said(check, ctx, verdict))
}

/// What `check` says for `verdict`, with each `null` value before a key and
/// each key it stops at in a group of its own.
pub fn said(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Said {
    let parts = null_keys(check, ctx, verdict);
    if parts.is_empty() {
        vec![pieces(check, ctx, verdict)]
    } else {
        parts
            .into_iter()
            .map(|part| vec![Piece::Said(part)])
            .collect()
    }
}

/// What `check` says for `verdict` as a row of its own: a `count of` or a
/// `sum of` also says the roots and the items it can't read.
pub fn row_said(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Said {
    let said = said(check, ctx, verdict);
    match check {
        Check::Tally(tally) => tally::row_said(tally, ctx, verdict.cause, said),
        _ => said,
    }
}

fn null_keys(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<String> {
    if matches!(check, Check::AnyOf(_))
        || !matches!(verdict.cause, Cause::Absent | Cause::Null | Cause::Unusable)
    {
        return Vec::new();
    }
    once_of(
        side_paths(check)
            .into_iter()
            .flat_map(|path| null_key_parts(path, ctx))
            .collect(),
    )
}

/// The pieces of the message `check` gives for `verdict`, with what each
/// `count of` or `sum of` says kept as its clauses.
pub fn pieces(check: &Check, ctx: &Ctx, verdict: &Verdict) -> Vec<Piece> {
    if let Check::AnyOf(any) = check {
        return vec![Piece::Said(any_of_message(any, ctx))];
    }
    let parts = null_keys(check, ctx, verdict);
    if !parts.is_empty() {
        return vec![Piece::Said(parts.join("; "))];
    }
    let clauses: Vec<Piece> = match verdict.cause {
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
            said_all(said).collect()
        }
        Cause::Absent | Cause::Null => {
            let want = state_of(verdict.cause).unwrap_or(Outcome::Absent);
            let keys = key_states(check, ctx, want);
            if keys.is_empty() {
                let roots: Vec<String> = check
                    .paths()
                    .into_iter()
                    .chain(super::walk::listed_refs(check))
                    .filter(|path| reads_from_a_root(path))
                    .map(name::name)
                    .collect();
                let mut found: Vec<Piece> = said_all(
                    sources(check, ctx, verdict)
                        .iter()
                        .filter(|i| {
                            i.state == want
                                || ctx.label.is_some()
                                    && !roots.contains(&i.name)
                                    && matches!(i.state, Outcome::Absent | Outcome::Null)
                        })
                        .map(|i| format!("{} is {}", i.stopped_at(), state_word(i.state))),
                )
                .collect();
                found.extend(said_all(
                    lists::walk_fault(check, ctx)
                        .filter(|(cause, _)| *cause == verdict.cause)
                        .map(|(_, text)| text),
                ));
                if let Check::Tally(tally_check) = check {
                    for side in tally::tally_sides(tally_check) {
                        if let TallySide::Derived(derived) = side {
                            found.extend(
                                tally::derived_clauses(derived, ctx)
                                    .into_iter()
                                    .map(Piece::Counted),
                            );
                        }
                    }
                }
                found
            } else {
                said_all(keys).collect()
            }
        }
        Cause::Unusable => {
            let mut all: Vec<Piece> = said_all(key_faults(check, ctx)).collect();
            all.extend(said_all(blocked(check, ctx, false)));
            all.extend(said_all(params_position_fault(check, ctx)));
            match check {
                Check::Tally(tally_check) => {
                    all.extend(tally_faults(tally_check, ctx).into_iter().map(|(_, p)| p));
                }
                _ => all.extend(said_all(faults(check, ctx).into_iter().map(|(_, t)| t))),
            }
            all.extend(said_all(blocked(check, ctx, true)));
            all.extend(said_all(
                lists::walk_fault(check, ctx)
                    .filter(|(cause, _)| *cause == Cause::Unusable)
                    .map(|(_, text)| text),
            ));
            let input_key = lists::input_key_fault(check, ctx);
            if matches!(check, Check::Tally(_))
                && !input_key.is_empty()
                && let Some(params) = params_that_arent_an_object(check, ctx)
            {
                all.extend(said_all(input_key));
                all.push(Piece::Said(params));
            }
            let digits = " needs more than 15 digits";
            let digits_only = |piece: &Piece| piece.text().ends_with(digits);
            if let Check::Tally(tally_check) = check
                && all.iter().all(digits_only)
            {
                all.extend(said_all(refs_blocked(tally_check, ctx)));
            }
            let others = all.iter().any(|piece| !digits_only(piece))
                || params_that_arent_an_object(check, ctx).is_some();
            let mut once = Vec::new();
            for piece in all {
                if others && digits_only(&piece) {
                    continue;
                }
                push_piece(&mut once, piece);
            }
            if once.is_empty()
                && ctx.params.is_none_or(|p| p.is_object() || p.is_null())
                && let Check::Tally(t) = check
            {
                for side in tally::tally_sides(t) {
                    if let TallySide::Derived(derived) = side {
                        push_piece(&mut once, Piece::Said(format!("{}{digits}", derived.text)));
                    }
                }
            }
            once
        }
        Cause::NotAnObject => {
            let subject = ctx.subject.value;
            let tallies: Vec<Piece> = match check {
                Check::Tally(t) => tally::tally_sides(t)
                    .into_iter()
                    .filter_map(|side| match side {
                        TallySide::Derived(d) => Some(d),
                        TallySide::Plain(_) => None,
                    })
                    .flat_map(|d| tally::derived_clauses(d, ctx))
                    .map(Piece::Counted)
                    .collect(),
                _ => Vec::new(),
            };
            let keyed = lists::input_key_fault(check, ctx);
            if subject.is_object() {
                let mut found: Vec<Piece> = said_all(aliases_blocked(check, ctx)).collect();
                found.extend(said_all(lists::input_one_fault(check, ctx)));
                found.extend(said_all(keyed));
                found.retain(|piece| {
                    !tallies.iter().any(|tally| match tally {
                        Piece::Counted(clauses) => clauses.iter().any(|c| c.text == piece.text()),
                        Piece::Said(_) => false,
                    })
                });
                found.extend(tallies);
                found
            } else if subject.is_array() && !tallies.is_empty() && !list_read_plainly(check, ctx) {
                tallies
            } else if !keyed.is_empty() {
                said_all(keyed).collect()
            } else {
                vec![Piece::Said(isnt(ctx.subject_label(), subject, "an object"))]
            }
        }
        _ => Vec::new(),
    };
    let mut once: Vec<Piece> = Vec::new();
    for piece in clauses {
        push_piece(&mut once, piece);
    }
    if once.is_empty() && verdict.cause == Cause::Unusable {
        once.extend(said_all(params_that_arent_an_object(check, ctx)));
    }
    if once.is_empty() {
        vec![Piece::Said(FALLBACK.to_string())]
    } else {
        once
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
                root_flaw_with(&[w], &outer, &[], &[], false)
                    .is_some_and(|(cause, _)| cause == Cause::NotAnObject)
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
            Step::Field(_) | Step::Members => return None,
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

pub fn with_roots(said: Vec<String>, roots: &str) -> Vec<String> {
    let roots: Vec<String> = roots.split("; ").map(str::to_string).collect();
    if said.iter().all(|part| roots.contains(part)) {
        return roots;
    }
    let mut out: Vec<String> = roots
        .into_iter()
        .filter(|root| !said.iter().any(|part| part.contains(root.as_str())))
        .collect();
    out.extend(said);
    out
}

pub fn joined(parts: Vec<String>) -> String {
    let mut once: Vec<String> = Vec::new();
    let mut hidden = 0;
    let mut fresh: Vec<bool> = Vec::new();
    for part in parts {
        if let Some(more) = cap_note(&part) {
            if fresh.iter().rev().take(3).any(|new| *new) {
                hidden += more;
            }
            fresh.push(false);
        } else if once.contains(&part) {
            fresh.push(false);
        } else {
            once.push(part);
            fresh.push(true);
        }
    }
    let items = once
        .iter()
        .filter(|part| crate::parts::is_item(part))
        .count();
    let counted = if items == 0 { once.len() } else { items };
    if counted + hidden <= 3 {
        once.join("; ")
    } else {
        let more = counted + hidden - 3;
        let mut left = 3;
        let mut shown: Vec<String> = Vec::new();
        for part in once {
            if items > 0 && !crate::parts::is_item(&part) {
                shown.push(part);
            } else if left > 0 {
                left -= 1;
                shown.push(part);
            }
        }
        shown.push(format!("and {more} more"));
        shown.join("; ")
    }
}

pub fn capped_units(parts: Vec<String>) -> Vec<String> {
    let mut units: Vec<(String, bool)> = Vec::new();
    for part in parts {
        let at = units.len().saturating_sub(3);
        if cap_note(&part).is_some()
            && units.len() >= 3
            && units[at..].iter().all(|(_, whole)| !whole)
        {
            let mut list: Vec<String> = units.drain(at..).map(|(text, _)| text).collect();
            list.push(part);
            units.push((list.join("; "), true));
        } else {
            units.push((part, false));
        }
    }
    units.into_iter().map(|(text, _)| text).collect()
}

pub fn cap_note(part: &str) -> Option<usize> {
    part.strip_prefix("and ")
        .and_then(|rest| rest.strip_suffix(" more"))
        .filter(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|n| n.parse().ok())
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
                    worked: true,
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
                    worked: true,
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

fn tally_side_faults(check: &tally::Tally, ctx: &Ctx) -> Vec<(String, String)> {
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
            out.push(fault(name, value, want));
        }
    }
    out
}

fn tally_faults(check: &tally::Tally, ctx: &Ctx) -> Vec<(String, Piece)> {
    let said = |(name, text): (String, String)| (name, Piece::Said(text));
    let mut out: Vec<(String, Piece)> = tally_side_faults(check, ctx)
        .into_iter()
        .map(said)
        .collect();
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
                            out.push(said(fault(&part.name, &part.value, "a time")));
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
                        out.push(said(fault(
                            &a.name,
                            &a.value,
                            &format!("a time written like {}", print(&b.value)),
                        )));
                        any = true;
                    }
                }
                for path in &plain {
                    if let Some(input) = first_input(path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_number()
                    {
                        out.push(said(fault(&input.name, &input.value, "a number")));
                        any = true;
                    }
                }
                for term in &derived.terms {
                    let tally::Term::Counted(term) = term else {
                        continue;
                    };
                    if let Some(clauses) = tally::counted_clauses(term, ctx) {
                        out.push((String::new(), Piece::Counted(clauses)));
                        any = true;
                    } else if let Some(input) = first_input(&term.path, ctx)
                        && input.state == Outcome::Found
                        && !input.value.is_array()
                        && !input.value.is_object()
                    {
                        out.push(said(fault(
                            &input.name,
                            &input.value,
                            "a list or an object",
                        )));
                        any = true;
                    }
                }
                let all_found = counted.iter().chain(plain.iter()).all(|path| {
                    first_input(path, ctx).is_none_or(|input| input.state == Outcome::Found)
                });
                if !any && all_found && tally::derived_value(derived, ctx).is_err() {
                    out.push(said((
                        derived.text.clone(),
                        format!("{} needs more than 15 digits", derived.text),
                    )));
                }
            }
            TallySide::Plain(_) => {}
        }
    }
    out
}

fn time_faults(check: &super::time::CompareTime, ctx: &Ctx) -> Vec<(String, String)> {
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
            out.push(fault(&first.name, value, "a time"));
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
        out.push(fault(
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
            push_new(&mut out, fault);
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

pub fn for_empty(items: &[ForItem], ctx: &Ctx, cause: Cause) -> Vec<String> {
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
    said
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

pub(super) fn root_kind_fault(check: &Check, root: &Path, ctx: &Ctx) -> Option<String> {
    if lists::haystacks(check).contains(&root) {
        return lists::ref_faults(check, ctx).into_iter().next();
    }
    if let Check::Tally(tally) = check
        && let Some(super::tally::Side::Plain(super::compare::Side::Path(right))) = &tally.right
        && right == root
        && let super::tally::Test::Compare { cmp, within } = &tally.test
    {
        let compare = Check::Compare(super::compare::Compare {
            left: super::compare::Side::Value(serde_json::Value::Null),
            right: super::compare::Side::Path(right.clone()),
            cmp: *cmp,
            within: within.clone(),
            ignoring: None,
        });
        return root_kind_fault(&compare, root, ctx);
    }
    let sides = match check {
        Check::Compare(c) => [&c.left, &c.right],
        Check::CompareTime(c) => [&c.left, &c.right],
        _ => return None,
    };
    if !sides
        .iter()
        .any(|side| matches!(side, super::compare::Side::Path(path) if path == root))
    {
        return None;
    }
    let read = path::read(root, ctx);
    let value = read.value.filter(|_| read.outcome == Outcome::Found)?;
    super::walk::right_needs(check, value).map(|kind| isnt(&name::name(root), value, kind))
}

pub fn root_flaw(checks: &[&Check], ctx: &Ctx) -> Option<(Cause, String)> {
    root_flaw_ordered(checks, ctx, &[], &[])
}

/// What [`root_flaw`] says, one text for each root.
pub fn root_texts(checks: &[&Check], ctx: &Ctx) -> Option<(Cause, Vec<String>)> {
    root_texts_with(checks, ctx, &[], &[], true)
}

pub fn root_flaw_ordered(
    checks: &[&Check],
    ctx: &Ctx,
    refs_first: &[&Check],
    keys_left: &[&Check],
) -> Option<(Cause, String)> {
    root_flaw_with(checks, ctx, refs_first, keys_left, true)
}

fn root_flaw_with(
    checks: &[&Check],
    ctx: &Ctx,
    refs_first: &[&Check],
    keys_left: &[&Check],
    walked_counts: bool,
) -> Option<(Cause, String)> {
    root_texts_with(checks, ctx, refs_first, keys_left, walked_counts)
        .map(|(cause, texts)| (cause, texts.join("; ")))
}

pub fn key_cause(checks: &[&Check], ctx: &Ctx) -> Option<(Cause, String)> {
    worst_texts(key_problems(checks, ctx, false))
}

pub fn worse_key_cause(
    flaw: Option<(Cause, String)>,
    checks: &[&Check],
    ctx: &Ctx,
) -> Option<(Cause, String)> {
    match (flaw, key_cause(checks, ctx)) {
        (Some(flaw), Some(key)) if key.0 >= flaw.0 => Some(flaw),
        (flaw, None) => flaw,
        (_, key) => key,
    }
}

fn key_problems(checks: &[&Check], ctx: &Ctx, listed: bool) -> Vec<Clause> {
    let mut keys: Vec<Path> = Vec::new();
    for check in checks {
        let mut own: Vec<Path> = check
            .paths()
            .into_iter()
            .chain(
                listed
                    .then(|| super::walk::listed_refs(check))
                    .into_iter()
                    .flatten(),
            )
            .flat_map(path::step_refs)
            .collect();
        own.sort_by_key(name::name);
        for key in own {
            push_new(&mut keys, key);
        }
    }
    keys.iter()
        .filter_map(|key| {
            let read = path::read(key, ctx);
            let named = name::name(key);
            match (read.outcome.cause(), read.value) {
                (Some(Cause::NotAnObject), _) => Some(Clause::root(
                    "$input",
                    Cause::NotAnObject,
                    isnt("$input", ctx.input, "an object"),
                )),
                (Some(cause), _) => Some(Clause::root(&named, cause, root_text(key, ctx, cause))),
                (None, Some(value)) if !value.is_string() => Some(Clause::root(
                    &named,
                    Cause::Unusable,
                    isnt(&named, value, "text"),
                )),
                (None, _) => None,
            }
        })
        .collect()
}

fn worst_texts(found: Vec<Clause>) -> Option<(Cause, String)> {
    let worst = Cause::worst(found.iter().map(|clause| clause.cause))?;
    let mut texts: Vec<String> = Vec::new();
    for clause in found {
        if clause.cause == worst && !texts.contains(&clause.text) {
            texts.push(clause.text);
        }
    }
    Some((worst, joined(texts)))
}

pub fn walked_roots_ahead(
    message: Option<String>,
    checks: &[&Check],
    ctx: &Ctx,
    refs_first: &[&Check],
) -> Option<String> {
    let message = message?;
    if !walks_a_root(checks, ctx) {
        return Some(message);
    }
    let roots = ordered_roots(checks, ctx, refs_first);
    Some(joined(roots_ahead(&message, &roots)))
}

/// Whether one of `checks` reads a list from outside the item whose values
/// can't be used.
pub fn walks_a_root(checks: &[&Check], ctx: &Ctx) -> bool {
    checks.iter().any(|check| {
        lists::right_paths(check).into_iter().any(|path| {
            reads_from_a_root(path)
                && lists::walked_root_fault(check, path, ctx)
                    .is_some_and(|(cause, _)| cause != Cause::Value)
        })
    })
}

pub fn ordered_roots(checks: &[&Check], ctx: &Ctx, refs_first: &[&Check]) -> Vec<String> {
    let mut first: Vec<String> = Vec::new();
    let mut rest: Vec<String> = Vec::new();
    for check in checks {
        let counted = refs_first.iter().any(|c| std::ptr::eq(*c, *check));
        let mut texts: Vec<String> = root_texts_with(&[check], ctx, &[], &[], true)
            .map(|(_, texts)| texts)
            .unwrap_or_default();
        for path in lists::right_paths(check) {
            if reads_from_a_root(path)
                && let Some((cause, text)) = lists::walked_root_fault(check, path, ctx)
                && cause != Cause::Value
            {
                texts.push(text);
            }
        }
        for text in texts {
            if counted && ref_first(&text) {
                first.push(text);
            } else {
                rest.push(text);
            }
        }
    }
    first.sort();
    let mut out: Vec<String> = Vec::new();
    for text in first.into_iter().chain(rest) {
        push_new(&mut out, text);
    }
    out
}

fn ref_first(text: &str) -> bool {
    text.starts_with('$') && (text.ends_with(" is missing") || text.ends_with(" is null"))
}

pub fn roots_ahead(message: &str, roots: &[String]) -> Vec<String> {
    let mut rest = format!("; {message}; ");
    for root in roots {
        let said = regex::Regex::new(&format!(
            r"; (?:item [0-9]+ of [^;:]+: )*{}; ",
            regex::escape(root)
        ))
        .expect("a valid pattern");
        while said.is_match(&rest) {
            rest = said.replace(&rest, "; ").into_owned();
        }
    }
    let mut out: Vec<String> = roots.to_vec();
    for part in capped_units(
        rest.split("; ")
            .filter(|part| !part.is_empty())
            .map(str::to_string)
            .collect(),
    ) {
        push_new(&mut out, part);
    }
    out
}

fn root_texts_with(
    checks: &[&Check],
    ctx: &Ctx,
    refs_first: &[&Check],
    keys_left: &[&Check],
    walked_counts: bool,
) -> Option<(Cause, Vec<String>)> {
    root_reads_with(checks, ctx, refs_first, keys_left, walked_counts)
        .map(|(cause, reads)| (cause, reads.into_iter().map(|(text, _)| text).collect()))
}

pub type RootRead = (String, Vec<Clause>);

fn root_reads_with(
    checks: &[&Check],
    ctx: &Ctx,
    refs_first: &[&Check],
    keys_left: &[&Check],
    walked_counts: bool,
) -> Option<(Cause, Vec<RootRead>)> {
    let mut found: Vec<(usize, Cause, String, bool, Vec<Clause>)> = Vec::new();
    let mut refs: Vec<String> = Vec::new();
    let one = |root: &Path, cause: Cause, text: &str| {
        vec![Clause::root(&name::name(root), cause, text.to_string())]
    };
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
                if is_key && keys_left.iter().any(|left| std::ptr::eq(*left, *check)) {
                    continue;
                }
                if let Start::Alias(name) = &root.start
                    && !ctx.aliases.contains_key(name)
                {
                    continue;
                }
                if root.steps.iter().any(|step| {
                    matches!(step, Step::Ref(key) | Step::Field(key)
                        if matches!(&key.start, Start::Alias(name) if !ctx.aliases.contains_key(name)))
                }) {
                    continue;
                }
                if lists::right_paths(check).contains(&&root)
                    && lists::walked_in(check, &root, ctx).is_some()
                {
                    if super::walked_roots_on()
                        && !is_key
                        && let Some((cause, text)) = lists::walked_root_fault(check, &root, ctx)
                        && cause != Cause::Value
                    {
                        let said = one(&root, cause, &text);
                        found.push((at, cause, text, false, said));
                    }
                    continue;
                }
                let counted = match check {
                    Check::Tally(tally) => tally.counted_paths().contains(&path),
                    _ => false,
                };
                if counted
                    && !is_key
                    && (lists::starts_at_a_list(&root, ctx) || lists::walked(&root, ctx).is_some())
                {
                    if walked_counts && let Check::Tally(tally) = check {
                        for (cause, said) in super::tally::counted_fault_clauses(tally, path, ctx) {
                            let text = clause::text(&clause::shown(&said));
                            let said = listed(&name::name(&root), said);
                            found.push((at, cause, text, false, said));
                        }
                    }
                    continue;
                }
                if counted && let Some((cause, text)) = first_null_step(&root, ctx) {
                    let said = one(&root, cause, &text);
                    return Some((cause, vec![(text, said)]));
                }
                if !is_key
                    && lists::one_rights(check).contains(&&root)
                    && let Some(text) = lists::input_one_fault(check, ctx).into_iter().next()
                {
                    let said = vec![Clause::root("$input", Cause::NotAnObject, text.clone())];
                    found.push((at, Cause::NotAnObject, text, false, said));
                    continue;
                }
                let read = path::read(&root, ctx);
                if let Some(cause) = read.outcome.cause() {
                    let text = root_text(&root, ctx, cause);
                    if refs_first.iter().any(|first| std::ptr::eq(*first, *check))
                        && !is_key
                        && matches!(root.start, Start::Params | Start::Input)
                        && matches!(cause, Cause::Absent | Cause::Null)
                    {
                        refs.push(text.clone());
                    }
                    let said = one(&root, cause, &text);
                    found.push((at, cause, text, is_key, said));
                } else if is_key && let Some(value) = read.value.filter(|value| !value.is_string())
                {
                    let text = isnt(&name::name(&root), value, "text");
                    let said = one(&root, Cause::Unusable, &text);
                    found.push((at, Cause::Unusable, text, true, said));
                } else if !is_key && let Some(text) = root_kind_fault(check, &root, ctx) {
                    let said = one(&root, Cause::Unusable, &text);
                    found.push((at, Cause::Unusable, text, false, said));
                }
            }
        }
    }
    let worst = Cause::worst(
        found
            .iter()
            .map(|(_, cause, _, _, _)| *cause)
            .collect::<Vec<_>>(),
    )?;
    let mut kept: Vec<(String, bool, Vec<Clause>)> = Vec::new();
    for (at, cause, text, is_key, said) in &found {
        let keyed = found.iter().any(|(other, other_cause, _, key, _)| {
            other == at && *key && (other_cause == cause || *other_cause == Cause::Unusable)
        });
        if (*is_key || !keyed) && !kept.iter().any(|(text_said, _, _)| text_said == text) {
            kept.push((text.clone(), *is_key, said.clone()));
        }
    }
    refs.retain(|text| kept.iter().any(|(said, _, _)| said == text));
    refs.sort();
    let keys = kept
        .iter()
        .filter(|(text, is_key, _)| *is_key && !refs.is_empty() && !refs.contains(text))
        .map(|(text, _, _)| text.clone());
    let mut texts: Vec<String> = Vec::new();
    for text in keys
        .chain(refs.clone())
        .chain(kept.iter().map(|(text, _, _)| text.clone()))
    {
        push_new(&mut texts, text);
    }
    let reads = texts
        .into_iter()
        .map(|text| {
            let said = kept
                .iter()
                .find(|(kept_text, _, _)| *kept_text == text)
                .map(|(_, _, said)| said.clone())
                .unwrap_or_default();
            (text, said)
        })
        .collect();
    Some((worst, reads))
}

pub fn walked_root_clauses(checks: &[&Check], ctx: &Ctx) -> Vec<Clause> {
    walked_root_clauses_with(checks, ctx, false)
}

pub fn walked_root_clauses_with(checks: &[&Check], ctx: &Ctx, empty: bool) -> Vec<Clause> {
    checks
        .iter()
        .flat_map(|check| {
            lists::right_paths(check)
                .into_iter()
                .filter(|root| {
                    reads_from_a_root(root) && lists::walked_in(check, root, ctx).is_some()
                })
                .filter_map(|root| {
                    lists::walked_root_fault(check, root, ctx)
                        .filter(|(cause, _)| empty || *cause != Cause::Value)
                        .map(|(cause, text)| Clause::root(&name::name(root), cause, text))
                })
        })
        .collect()
}

fn listed(list: &str, said: Vec<Clause>) -> Vec<Clause> {
    let (items, mut out): (Vec<Clause>, Vec<Clause>) = said
        .into_iter()
        .partition(|clause| clause.kind == clause::Kind::Item);
    if !items.is_empty() {
        let cause = Cause::worst(items.iter().map(|item| item.cause)).unwrap_or(Cause::Value);
        let text = clause::text(&clause::shown(&items));
        out.push(Clause {
            said: items,
            ..Clause::root(list, cause, text)
        });
    }
    out
}

fn is_listed(clause: &Clause) -> bool {
    clause.kind == clause::Kind::Root && !clause.said.is_empty()
}

pub fn unlisted(clause: Clause) -> Vec<Clause> {
    if is_listed(&clause) {
        clause.said
    } else {
        vec![clause]
    }
}

pub fn root_clauses(checks: &[&Check], ctx: &Ctx) -> Vec<Clause> {
    roots_with(checks, ctx, true, false)
}

pub fn side_root_clauses(checks: &[&Check], ctx: &Ctx) -> Vec<Clause> {
    roots_with(checks, ctx, false, false)
}

/// The roots `root_clauses` gives, or `side_root_clauses` without
/// `item_keys`, with the items of each list a root walks under that root.
pub fn listed_root_clauses(checks: &[&Check], ctx: &Ctx, item_keys: bool) -> Vec<Clause> {
    roots_with(checks, ctx, item_keys, true)
}

fn roots_with(checks: &[&Check], ctx: &Ctx, item_keys: bool, keep_lists: bool) -> Vec<Clause> {
    let reads = root_reads_with(checks, ctx, &[], &[], true)
        .map(|(_, reads)| reads)
        .unwrap_or_default();
    let bases = checks
        .iter()
        .flat_map(|check| {
            check
                .paths()
                .into_iter()
                .chain(super::walk::listed_refs(check))
        })
        .filter_map(|path| {
            super::key_base::base_of(path, item_keys, ctx)
                .map(|(name, text, cause)| Clause::root(&name, cause, text))
        });
    let counted = checks
        .iter()
        .filter(|check| matches!(check, Check::Tally(_)))
        .flat_map(|check| off_item(check, ctx, Cause::Unusable))
        .map(|text| Clause::said(Cause::Unusable, text));
    let aliased: Vec<Clause> = checks
        .iter()
        .flat_map(|check| {
            check
                .paths()
                .into_iter()
                .chain(super::walk::listed_refs(check))
        })
        .flat_map(|path| path.steps.iter())
        .filter_map(|step| match step {
            Step::Field(key) | Step::Ref(key)
                if matches!(&key.start, Start::Alias(alias)
                    if alias != path::OUTER && ctx.aliases.contains_key(alias)) =>
            {
                let (outcome, text, _) = super::key_base::key_flaw(key, ctx)?;
                Some(Clause::root(&name::name(key), outcome.cause()?, text))
            }
            _ => None,
        })
        .collect();
    let stopped: Vec<String> = checks
        .iter()
        .flat_map(|check| {
            check
                .paths()
                .into_iter()
                .chain(super::walk::listed_refs(check))
        })
        .filter(|path| {
            path::step_refs(path)
                .iter()
                .any(|key| super::key_base::key_flaw(key, ctx).is_some())
        })
        .map(name::name)
        .collect();
    let mut said: Vec<Clause> = Vec::new();
    for clause in key_problems(checks, ctx, true)
        .into_iter()
        .chain(aliased)
        .chain(bases)
        .chain(counted)
        .chain(
            reads
                .into_iter()
                .flat_map(|(_, said)| said)
                .flat_map(|clause| {
                    if keep_lists {
                        vec![clause]
                    } else {
                        unlisted(clause)
                    }
                })
                .filter(|clause| is_listed(clause) || !stopped.contains(&clause.name)),
        )
    {
        let root = clause.kind == clause::Kind::Root;
        if !said
            .iter()
            .any(|found| *found == clause || root && found.text == clause.text)
        {
            said.push(clause);
        }
    }
    said.sort_by(|a, b| match (a.kind, b.kind) {
        (clause::Kind::Root, clause::Kind::Root) => (a.cause, &a.name).cmp(&(b.cause, &b.name)),
        (clause::Kind::Root, _) => std::cmp::Ordering::Less,
        (_, clause::Kind::Root) => std::cmp::Ordering::Greater,
        _ => std::cmp::Ordering::Equal,
    });
    said
}

pub fn off_item(check: &Check, ctx: &Ctx, cause: Cause) -> Vec<String> {
    let want = match cause {
        Cause::Absent => Outcome::Absent,
        Cause::Null => Outcome::Null,
        Cause::Unusable => return off_item_lists(check, ctx),
        Cause::NotAnObject => return lists::input_key_fault(check, ctx),
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
                push_new(&mut out, clause);
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
            push_new(&mut out, clause);
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
            push_new(&mut out, clause);
        }
    }
    out
}

#[cfg(test)]
mod tests;
