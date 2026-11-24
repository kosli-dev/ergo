use crate::cause::Cause;
use serde_json::{Value, json};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Root,
    List,
    Item,
    More(usize),
}

/// The entry of a `for` row that says a clause: the assertion with that
/// index, the item it is about, or the list the line walks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Owner {
    Sentence(usize),
    Item,
    List,
}

#[derive(Debug, Clone, Eq)]
pub struct Clause {
    pub kind: Kind,
    pub name: String,
    pub cause: Cause,
    pub text: String,
    pub said: Vec<Clause>,
    pub group: usize,
    pub last_of_cause: bool,
    pub said_first: bool,
    pub owners: Vec<Owner>,
}

impl PartialEq for Clause {
    fn eq(&self, other: &Clause) -> bool {
        self.kind == other.kind
            && self.name == other.name
            && self.cause == other.cause
            && self.text == other.text
            && self.said == other.said
            && self.group == other.group
            && self.last_of_cause == other.last_of_cause
            && self.said_first == other.said_first
    }
}

impl Clause {
    pub fn root(name: &str, cause: Cause, text: String) -> Clause {
        Clause {
            kind: Kind::Root,
            name: name.to_string(),
            cause,
            text,
            said: Vec::new(),
            group: 0,
            last_of_cause: false,
            said_first: false,
            owners: Vec::new(),
        }
    }

    pub fn said(cause: Cause, text: String) -> Clause {
        Clause::root(&text.clone(), cause, text)
    }

    pub fn list(name: &str, cause: Cause, text: String) -> Clause {
        Clause {
            kind: Kind::List,
            ..Clause::root(name, cause, text)
        }
    }

    pub fn item(name: &str, cause: Cause, text: String, said: Vec<Clause>) -> Clause {
        Clause {
            kind: Kind::Item,
            said,
            ..Clause::root(name, cause, text)
        }
    }

    pub fn in_group(self, group: usize) -> Clause {
        Clause { group, ..self }
    }

    /// The same clause, said by `owner` too.
    pub fn owned_by(mut self, owner: Owner) -> Clause {
        self.take_owners(&[owner]);
        self
    }

    /// Adds each of `owners` this clause doesn't have yet.
    pub fn take_owners(&mut self, owners: &[Owner]) {
        for owner in owners {
            if !self.owners.contains(owner) {
                self.owners.push(*owner);
            }
        }
    }

    pub fn last_of_its_cause(self) -> Clause {
        Clause {
            last_of_cause: true,
            ..self
        }
    }

    pub fn said_first(self) -> Clause {
        Clause {
            said_first: true,
            ..self
        }
    }
}

const SHOWN_ITEMS: usize = 3;

pub fn shown(clauses: &[Clause]) -> Vec<Clause> {
    let mut once = said_once(clauses);
    let rank = |clause: &Clause| match clause.kind {
        Kind::Root => 0,
        Kind::List => 1,
        Kind::Item | Kind::More(_) => 2,
    };
    once.sort_by(|a, b| {
        (a.group, rank(a)).cmp(&(b.group, rank(b))).then_with(|| {
            if a.kind == Kind::Root && b.kind == Kind::Root {
                (a.cause, a.last_of_cause, &a.name).cmp(&(b.cause, b.last_of_cause, &b.name))
            } else {
                std::cmp::Ordering::Equal
            }
        })
    });
    let leaves: usize = once
        .iter()
        .filter(|clause| clause.kind == Kind::Item)
        .map(leaves)
        .sum();
    if leaves <= SHOWN_ITEMS {
        return once;
    }
    let mut out: Vec<Clause> = Vec::new();
    let mut left = SHOWN_ITEMS;
    for clause in once {
        if clause.kind == Kind::Item {
            out.extend(cut(&clause, &mut left));
        } else {
            out.push(clause);
        }
    }
    out.push(Clause {
        kind: Kind::More(leaves - SHOWN_ITEMS),
        name: String::new(),
        cause: Cause::Value,
        text: String::new(),
        said: Vec::new(),
        group: 0,
        last_of_cause: false,
        said_first: false,
        owners: Vec::new(),
    });
    out
}

fn said_once(clauses: &[Clause]) -> Vec<Clause> {
    let mut once: Vec<Clause> = Vec::new();
    for clause in clauses {
        let clause = if clause.kind == Kind::Item {
            Clause {
                said: said_once(&clause.said),
                ..clause.clone()
            }
        } else {
            clause.clone()
        };
        match once.iter_mut().find(|seen| says_alike(seen, &clause)) {
            Some(seen) => {
                seen.group = seen.group.min(clause.group);
                seen.take_owners(&clause.owners);
            }
            None => once.push(clause),
        }
    }
    once
}

fn says_alike(a: &Clause, b: &Clause) -> bool {
    let bare = |clause: &Clause| clause.kind != Kind::Item || clause.said.is_empty();
    match (a.kind, b.kind) {
        (Kind::Item, Kind::Item) => pieces(a) == pieces(b),
        (Kind::More(_), _) | (_, Kind::More(_)) => false,
        _ => bare(a) && bare(b) && a.text == b.text,
    }
}

pub fn text(clauses: &[Clause]) -> String {
    clauses
        .iter()
        .flat_map(|clause| match clause.kind {
            Kind::More(count) => vec![format!("and {count} more")],
            Kind::Item => pieces(clause),
            Kind::Root | Kind::List => vec![clause.text.clone()],
        })
        .collect::<Vec<_>>()
        .join("; ")
}

/// The text each clause gives on its own, the way it reads in a row.
pub fn lines(clauses: &[Clause]) -> Vec<String> {
    clauses
        .iter()
        .map(|clause| text(std::slice::from_ref(clause)))
        .collect()
}

/// What the entry of the item `name` says, from the clauses `said` of it.
/// Clauses about the same item under it share one piece, joined with
/// `, and `, and a clause about `alias` alone that leads its piece reads as
/// the item itself, like `item 1 of xs is 2` for `x is 2`.
pub fn item_says(name: &str, alias: &str, said: &[Clause]) -> String {
    let whole = |clause: &Clause| {
        clause.kind == Kind::Item
            && clause.said.is_empty()
            && clause.name == alias
            && clause.text.starts_with(&format!("{alias} "))
    };
    let mut lines: Vec<(String, bool)> = Vec::new();
    for clause in said {
        let line = (text(std::slice::from_ref(clause)), whole(clause));
        if !lines.contains(&line) {
            lines.push(line);
        }
    }
    if let [(one, false)] = lines.as_slice() {
        return one.clone();
    }
    let mut leads: Vec<String> = Vec::new();
    for (line, _) in &lines {
        let lead = super::for_line::lead_of(line);
        if !leads.contains(&lead) {
            leads.push(lead);
        }
    }
    leads
        .iter()
        .map(|lead| {
            let group: Vec<&(String, bool)> = lines
                .iter()
                .filter(|(line, _)| super::for_line::lead_of(line) == *lead)
                .collect();
            let rest: Vec<&str> = group[1..]
                .iter()
                .map(|(line, _)| match lead.is_empty() {
                    true => line.as_str(),
                    false => line.strip_prefix(&format!("{lead}: ")).unwrap_or(line),
                })
                .collect();
            let (first, first_whole) = group[0];
            let mut said = match first.strip_prefix(alias) {
                Some(after) if *first_whole => format!("{name}{after}"),
                _ => first.clone(),
            };
            for text in rest {
                said.push_str(", and ");
                said.push_str(text);
            }
            said
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn pieces(item: &Clause) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    if !item.text.is_empty() && !item.said_first {
        out.push(item.text.clone());
    }
    let mut own: Vec<&str> = Vec::new();
    let flush = |own: &mut Vec<&str>, out: &mut Vec<String>| {
        if !own.is_empty() {
            out.push(format!("{}: {}", item.name, own.join(", and ")));
            own.clear();
        }
    };
    for clause in &item.said {
        if clause.kind == Kind::Item {
            flush(&mut own, &mut out);
            out.extend(
                pieces(clause)
                    .into_iter()
                    .map(|piece| format!("{}: {piece}", item.name)),
            );
        } else {
            own.push(&clause.text);
        }
    }
    flush(&mut own, &mut out);
    if !item.text.is_empty() && item.said_first {
        out.push(item.text.clone());
    }
    out
}

fn cut(item: &Clause, left: &mut usize) -> Option<Clause> {
    let mut kept = Clause {
        said: Vec::new(),
        ..item.clone()
    };
    if !item.said_first {
        cut_text(item, &mut kept, left);
    }
    if has_items(item) {
        for clause in &item.said {
            if clause.kind == Kind::Item {
                kept.said.extend(cut(clause, left));
            } else {
                kept.said.push(clause.clone());
            }
        }
        if !has_items(&kept) {
            kept.said.clear();
        }
    } else if !item.said.is_empty() {
        if *left > 0 {
            kept.said = item.said.clone();
        }
        *left = left.saturating_sub(1);
    }
    if item.said_first {
        cut_text(item, &mut kept, left);
    }
    (!kept.text.is_empty() || !kept.said.is_empty()).then_some(kept)
}

fn cut_text(item: &Clause, kept: &mut Clause, left: &mut usize) {
    if !item.text.is_empty() {
        if *left == 0 {
            kept.text.clear();
        }
        *left = left.saturating_sub(1);
    }
}

fn has_items(item: &Clause) -> bool {
    item.said.iter().any(|clause| clause.kind == Kind::Item)
}

fn leaves(item: &Clause) -> usize {
    let own = !item.said.is_empty() && !has_items(item);
    let under: usize = item
        .said
        .iter()
        .filter(|clause| clause.kind == Kind::Item)
        .map(leaves)
        .sum();
    usize::from(!item.text.is_empty()) + usize::from(own) + under
}

pub fn to_value(clauses: &[Clause]) -> Value {
    Value::Array(
        clauses
            .iter()
            .map(|clause| {
                let (kind, count) = match clause.kind {
                    Kind::Root => ("root", 0),
                    Kind::List => ("list", 0),
                    Kind::Item => ("item", 0),
                    Kind::More(count) => ("more", count),
                };
                json!({
                    "kind": kind,
                    "count": count,
                    "name": clause.name,
                    "cause": clause.cause.name(),
                    "text": clause.text,
                    "said": to_value(&clause.said),
                    "group": clause.group,
                    "said_first": clause.said_first,
                    "owners": clause.owners.iter().map(|owner| match owner {
                        Owner::Sentence(idx) => json!(idx),
                        Owner::Item => json!("item"),
                        Owner::List => json!("list"),
                    }).collect::<Vec<_>>(),
                })
            })
            .collect(),
    )
}

pub fn of_value(value: &Value) -> Option<Vec<Clause>> {
    let number = |clause: &Value, key: &str| usize::try_from(clause.get(key)?.as_u64()?).ok();
    let text = |clause: &Value, key: &str| clause.get(key)?.as_str().map(str::to_string);
    value
        .as_array()?
        .iter()
        .map(|clause| {
            let kind = match clause.get("kind")?.as_str()? {
                "root" => Kind::Root,
                "list" => Kind::List,
                "item" => Kind::Item,
                "more" => Kind::More(number(clause, "count")?),
                _ => return None,
            };
            Some(Clause {
                kind,
                name: text(clause, "name")?,
                cause: Cause::from_name(clause.get("cause")?.as_str()?)?,
                text: text(clause, "text")?,
                said: of_value(clause.get("said")?)?,
                group: number(clause, "group")?,
                last_of_cause: false,
                said_first: clause
                    .get("said_first")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                owners: match clause.get("owners") {
                    None => Vec::new(),
                    Some(owners) => owners
                        .as_array()?
                        .iter()
                        .map(|owner| match (owner.as_u64(), owner.as_str()) {
                            (Some(idx), _) => usize::try_from(idx).ok().map(Owner::Sentence),
                            (_, Some("item")) => Some(Owner::Item),
                            (_, Some("list")) => Some(Owner::List),
                            _ => None,
                        })
                        .collect::<Option<Vec<_>>>()?,
                },
            })
        })
        .collect()
}

#[cfg(test)]
mod tests;
