use super::tally::{Side, Term};
use super::walk::{self, Options};
use super::{Check, message, push_new};
use crate::cause::Cause;
use crate::name;
use crate::path::{self, Ctx, OUTER, Outcome, Path, Start, Step};

struct Fault {
    cause: Cause,
    text: String,
    path: Path,
    at: usize,
}

/// Returns the cause and the message of a one-line `every`, `some` or
/// `count of` whose `whose` reads a path from outside the item through a key
/// the item holds, like `count of xs whose tags contains $input.m named by key
/// is 1`, when the part before that key can't be read. It says that part
/// once, first, and then what each item says on its own, in list order. It
/// returns `None` for any other check, or when that part reads.
#[must_use]
pub fn rewritten(check: &Check, ctx: &Ctx, cause: Cause, said: &str) -> Option<(Cause, String)> {
    let (list, whose) = keyed_list(check)?;
    let mut outer = ctx.clone();
    outer
        .aliases
        .entry(OUTER.to_string())
        .or_insert_with(|| ctx.subject.clone());
    let faults = root_faults(&whose, &outer);
    if faults.is_empty() {
        return None;
    }
    let walked = walk::walk(
        list,
        &outer,
        Options {
            if_any: true,
            empty_adds_nothing: true,
        },
    );
    if walked.unreadable.is_some() || !walked.failures.is_empty() {
        return None;
    }
    let parts: Vec<&str> = said.split("; ").collect();
    let mut causes: Vec<Cause> = faults.iter().map(|f| f.cause).collect();
    let mut texts: Vec<String> = faults.iter().map(|f| f.text.clone()).collect();
    for item in &walked.items {
        let name = walked.item_name(&item.item_segs);
        if !item.item.value.is_object() {
            causes.push(Cause::NotAnObject);
            texts.push(message::isnt(&name, item.item.value, "an object"));
            continue;
        }
        let mut at = outer.clone();
        at.subject = item.item.clone();
        let mut keys: Vec<(Cause, String)> = Vec::new();
        for fault in &faults {
            if let Step::Field(key) = &fault.path.steps[fault.at]
                && let Some(found) = key_problem(key, &at)
            {
                push_new(&mut keys, found);
            }
        }
        let key_texts: Vec<String> = keys.iter().map(|(_, text)| text.clone()).collect();
        let mut own: Vec<String> = Vec::new();
        for clause in said_of(&name, &parts) {
            if !key_texts.contains(&clause) && !root_clause(&clause, &faults) {
                push_new(&mut own, clause);
            }
        }
        if !own.is_empty() {
            causes.push(cause);
        }
        causes.extend(keys.iter().map(|(cause, _)| *cause));
        for text in key_texts {
            push_new(&mut own, text);
        }
        if !own.is_empty() {
            texts.push(format!("{name}: {}", own.join(", and ")));
        }
    }
    Some((Cause::worst(causes)?, message::joined(texts)))
}

fn keyed_list(check: &Check) -> Option<(&Path, Vec<&Check>)> {
    match check {
        Check::Walk(walk) if !walk.whose.is_empty() => {
            Some((&walk.path, walk.whose.iter().collect()))
        }
        Check::Tally(tally) => {
            let lists: Vec<(&Path, Vec<&Check>)> = super::tally::tally_sides(tally)
                .into_iter()
                .filter_map(|side| match side {
                    Side::Derived(derived) if derived.terms.len() == 1 => match &derived.terms[0] {
                        Term::Counted(counted) if !counted.whose.is_empty() => {
                            Some((&counted.path, counted.whose.iter().collect()))
                        }
                        _ => None,
                    },
                    _ => None,
                })
                .collect();
            if lists.len() == 1 {
                lists.into_iter().next()
            } else {
                None
            }
        }
        _ => None,
    }
}

fn item_keyed_at(path: &Path) -> Option<usize> {
    if !matches!(
        path.start,
        Start::Alias(_) | Start::Part(_) | Start::Params | Start::Input
    ) {
        return None;
    }
    path.steps.iter().position(
        |step| matches!(step, Step::Field(key) if matches!(key.start, Start::Subject | Start::Own)),
    )
}

fn root_faults(whose: &[&Check], ctx: &Ctx) -> Vec<Fault> {
    let mut faults: Vec<Fault> = Vec::new();
    for check in whose {
        let mut paths: Vec<Path> = check.paths().into_iter().cloned().collect();
        paths.extend(super::lists::right_paths(check).into_iter().cloned());
        for path in paths {
            let Some(at) = item_keyed_at(&path) else {
                continue;
            };
            if let Some((cause, text)) = prefix_fault(&path, at, ctx)
                && !faults.iter().any(|f| f.path == path)
            {
                faults.push(Fault {
                    cause,
                    text,
                    path,
                    at,
                });
            }
        }
    }
    faults.sort_by(|a, b| a.cause.cmp(&b.cause).then_with(|| a.text.cmp(&b.text)));
    faults
}

fn prefix_fault(path: &Path, at: usize, ctx: &Ctx) -> Option<(Cause, String)> {
    for end in 1..=at {
        let before = Path {
            start: path.start.clone(),
            steps: path.steps[..end].to_vec(),
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

fn said_of(name: &str, parts: &[&str]) -> Vec<String> {
    let head = format!("{name}: ");
    let mut out: Vec<String> = Vec::new();
    let mut mine = false;
    for part in parts {
        let text = if part.starts_with("item ") {
            mine = part.starts_with(&head);
            part.strip_prefix(&head).unwrap_or(part)
        } else {
            part
        };
        if mine {
            out.extend(text.split(", and ").map(str::to_string));
        }
    }
    out
}

fn root_clause(clause: &str, faults: &[Fault]) -> bool {
    faults.iter().any(|fault| {
        (1..=fault.path.steps.len()).any(|end| {
            let before = Path {
                start: fault.path.start.clone(),
                steps: fault.path.steps[..end].to_vec(),
            };
            clause.starts_with(&format!("{} ", name::name(&before)))
        })
    })
}
