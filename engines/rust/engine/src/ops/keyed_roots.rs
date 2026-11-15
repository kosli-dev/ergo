use super::compare::Side as Plain;
use super::lists::{Right, Wanted};
use super::tally::{Kind, Side, Term};
use super::walk::{self, Options};
use super::{Check, message, push_new};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, OUTER, Outcome, Path, Start, Step};
use serde_json::Value;
use std::collections::BTreeSet;

#[derive(Clone, Copy)]
enum Wants {
    List,
    Text,
}

struct Keyed<'a> {
    list: &'a Path,
    operand: &'a Path,
    wants: Wants,
    root: &'a Path,
}

/// Returns the cause and the message of a one-line `every … exists`,
/// `some … exists` or `count of` compared with a value, whose one `whose`
/// clause, like `tags contains $input.m named by key`, reads a path from
/// outside the item through a key the item holds, when the part before that
/// key is missing, `null` or not an object. It says that part once, first,
/// and then each item that isn't an object, or whose field or key can't be
/// read, in list order. When the list is empty or can't be read, it says that
/// part and then `list_said`, the row's message about the list, with
/// `list_cause`, the row's cause. It returns `None` for any other check, or
/// when that part reads.
#[must_use]
pub fn rewritten(
    check: &Check,
    ctx: &Ctx,
    list_cause: Cause,
    list_said: impl FnOnce() -> String,
) -> Option<(Cause, String)> {
    let keyed = keyed(check)?;
    let mut outer = ctx.clone();
    outer
        .aliases
        .entry(OUTER.to_string())
        .or_insert_with(|| ctx.subject.clone());
    let (cause, text) = root_fault(keyed.root, &outer)?;
    let walked = walk::walk(
        keyed.list,
        &outer,
        Options {
            if_any: true,
            empty_adds_nothing: true,
        },
    );
    if walked.unreadable.is_some() || !walked.failures.is_empty() || walked.items.is_empty() {
        return Some((
            Cause::worst([cause, list_cause])?,
            message::joined(vec![text, list_said()]),
        ));
    }
    let Some(Step::Field(key)) = keyed.root.steps.last() else {
        return None;
    };
    let mut causes = vec![cause];
    let mut texts = vec![text];
    for item in &walked.items {
        let name = walked.item_name(&item.item_segs);
        if !item.item.value.is_object() {
            causes.push(Cause::NotAnObject);
            texts.push(message::isnt(&name, item.item.value, "an object"));
            continue;
        }
        let mut at = outer.clone();
        at.subject = item.item.clone();
        let mut own: Vec<(Cause, String)> = Vec::new();
        if let Some(found) = operand_problem(keyed.operand, keyed.wants, &at)? {
            own.push(found);
        }
        if let Some(found) = key_problem(key, &at) {
            push_new(&mut own, found);
        }
        if !own.is_empty() {
            causes.extend(own.iter().map(|(cause, _)| *cause));
            let said: Vec<String> = own.into_iter().map(|(_, text)| text).collect();
            texts.push(format!("{name}: {}", said.join(", and ")));
        }
    }
    Some((Cause::worst(causes)?, message::joined(texts)))
}

fn keyed(check: &Check) -> Option<Keyed<'_>> {
    let (list, whose) = match check {
        Check::Walk(walk)
            if !walk.distinct
                && walk.for_aliases.is_empty()
                && matches!(walk.check.as_ref(), Check::Present(present) if !present.missing) =>
        {
            (&walk.path, &walk.whose)
        }
        Check::Tally(tally) => {
            let Side::Derived(derived) = &tally.left else {
                return None;
            };
            if !matches!(tally.right, Some(Side::Plain(Plain::Value(_))))
                || derived.terms.len() != 1
            {
                return None;
            }
            match &derived.terms[0] {
                Term::Counted(counted) if counted.kind == Kind::Count && !counted.distinct => {
                    (&counted.path, &counted.whose)
                }
                _ => return None,
            }
        }
        _ => return None,
    };
    if !plain(list, Start::Subject) || list.steps.len() != 1 || whose.len() != 1 {
        return None;
    }
    let (operand, wants, right) = match &whose[0] {
        Check::Contains(contains) if !contains.not => match &contains.wanted {
            Wanted::One(right) => (&contains.path, Wants::List, right),
            _ => return None,
        },
        Check::Matches(matches) if !matches.not => (&matches.path, Wants::Text, &matches.patterns),
        _ => return None,
    };
    let root = right_path(right)?;
    (plain(operand, Start::Subject) && operand.steps.len() == 1 && keyed_root(root)).then_some(
        Keyed {
            list,
            operand,
            wants,
            root,
        },
    )
}

fn right_path(right: &Right) -> Option<&Path> {
    match right {
        Right::Ref(root) | Right::Field(root) => Some(root),
        Right::Join(parts) if parts.len() == 1 => right_path(&parts[0]),
        _ => None,
    }
}

fn plain(path: &Path, start: Start) -> bool {
    path.start == start
        && !path.steps.is_empty()
        && path.steps.iter().all(|step| matches!(step, Step::Key(_)))
}

fn keyed_root(root: &Path) -> bool {
    let Some((Step::Field(key), before)) = root.steps.split_last() else {
        return false;
    };
    matches!(
        root.start,
        Start::Alias(_) | Start::Part(_) | Start::Params | Start::Input
    ) && !before.is_empty()
        && before.iter().all(|step| matches!(step, Step::Key(_)))
        && plain(key, Start::Subject)
        && key.steps.len() == 1
}

fn root_fault(root: &Path, ctx: &Ctx) -> Option<(Cause, String)> {
    let at = root.steps.len() - 1;
    let first = usize::from(!matches!(root.start, Start::Part(_)));
    for end in first..=at {
        let before = Path {
            start: root.start.clone(),
            steps: root.steps[..end].to_vec(),
        };
        let read = path::read(&before, ctx);
        match (read.outcome, read.value) {
            (Outcome::Absent, _) => {
                return Some((Cause::Absent, format!("{} is missing", name::name(&before))));
            }
            (Outcome::Null, _) => {
                return Some((Cause::Null, format!("{} is null", name::name(&before))));
            }
            (Outcome::Found, Some(value)) if end == at && !value.is_object() => {
                return Some((
                    Cause::Unusable,
                    message::isnt(&name::name(&before), value, "an object"),
                ));
            }
            (Outcome::Found, _) => {}
            _ => return None,
        }
    }
    None
}

fn operand_problem(operand: &Path, wants: Wants, ctx: &Ctx) -> Option<Option<(Cause, String)>> {
    let read = path::read(operand, ctx);
    let named = name::name(operand);
    match (read.outcome, read.value, wants) {
        (Outcome::Absent, _, _) => Some(Some((Cause::Absent, format!("{named} is missing")))),
        (Outcome::Null, _, _) => Some(Some((Cause::Null, format!("{named} is null")))),
        (Outcome::Found, Some(Value::Array(items)), Wants::List) => {
            let kinds: BTreeSet<&str> = items.iter().map(kind).collect();
            (kinds.len() <= 1).then_some(None)
        }
        (Outcome::Found, Some(Value::String(_)), Wants::Text) => Some(None),
        (Outcome::Found, Some(value), Wants::List) => Some(Some((
            Cause::Unusable,
            message::isnt(&named, value, "a list"),
        ))),
        (Outcome::Found, Some(value), Wants::Text) => Some(Some((
            Cause::Unusable,
            message::isnt(&named, value, "text"),
        ))),
        _ => None,
    }
}

fn kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

fn key_problem(key: &Path, ctx: &Ctx) -> Option<(Cause, String)> {
    let read = path::read(key, ctx);
    match (read.outcome, read.value) {
        (Outcome::Absent, _) => Some((Cause::Absent, format!("{} is missing", name::name(key)))),
        (Outcome::Null, _) => Some((Cause::Null, format!("{} is null", name::name(key)))),
        (Outcome::Found, Some(value)) if !value.is_string() => Some((
            Cause::Unusable,
            message::isnt(&name::name(key), value, "text"),
        )),
        _ => None,
    }
}
