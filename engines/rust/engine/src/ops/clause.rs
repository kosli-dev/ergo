use crate::cause::Cause;
use serde_json::{Value, json};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Root,
    List,
    Item,
    More(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Clause {
    pub kind: Kind,
    pub name: String,
    pub cause: Cause,
    pub text: String,
    pub said: Vec<Clause>,
    pub group: usize,
    pub last_of_cause: bool,
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

    pub fn last_of_its_cause(self) -> Clause {
        Clause {
            last_of_cause: true,
            ..self
        }
    }
}

const SHOWN_ITEMS: usize = 3;

pub fn shown(clauses: &[Clause]) -> Vec<Clause> {
    let mut once: Vec<Clause> = Vec::new();
    for clause in clauses {
        match once.iter_mut().find(|seen| same_but_group(seen, clause)) {
            Some(seen) => seen.group = seen.group.min(clause.group),
            None => once.push(clause.clone()),
        }
    }
    let of_kind = |kind: Kind| once.iter().filter(move |clause| clause.kind == kind);
    let mut out: Vec<Clause> = of_kind(Kind::Root).cloned().collect();
    out.sort_by(|a, b| {
        (a.group, a.cause, a.last_of_cause, &a.name).cmp(&(
            b.group,
            b.cause,
            b.last_of_cause,
            &b.name,
        ))
    });
    out.extend(of_kind(Kind::List).cloned());
    let items: Vec<&Clause> = of_kind(Kind::Item).collect();
    let leaves: usize = items.iter().map(|item| leaves(item)).sum();
    if leaves <= SHOWN_ITEMS {
        out.extend(items.into_iter().cloned());
        return out;
    }
    let mut left = SHOWN_ITEMS;
    out.extend(items.into_iter().filter_map(|item| cut(item, &mut left)));
    out.push(Clause {
        kind: Kind::More(leaves - SHOWN_ITEMS),
        name: String::new(),
        cause: Cause::Value,
        text: String::new(),
        said: Vec::new(),
        group: 0,
        last_of_cause: false,
    });
    out
}

fn same_but_group(a: &Clause, b: &Clause) -> bool {
    (a.kind, &a.name, a.cause, &a.text, &a.said) == (b.kind, &b.name, b.cause, &b.text, &b.said)
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

fn pieces(item: &Clause) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    if !item.text.is_empty() {
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
    out
}

fn cut(item: &Clause, left: &mut usize) -> Option<Clause> {
    let mut kept = Clause {
        said: Vec::new(),
        ..item.clone()
    };
    if !item.text.is_empty() {
        if *left == 0 {
            kept.text.clear();
        }
        *left = left.saturating_sub(1);
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
    (!kept.text.is_empty() || !kept.said.is_empty()).then_some(kept)
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

#[cfg_attr(not(test), expect(dead_code))]
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
                })
            })
            .collect(),
    )
}

#[cfg_attr(not(test), expect(dead_code))]
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
            })
        })
        .collect()
}

#[cfg(test)]
mod tests;
