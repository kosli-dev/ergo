use crate::cause::Cause;

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

    #[cfg_attr(not(test), expect(dead_code))]
    pub fn in_group(self, group: usize) -> Clause {
        Clause { group, ..self }
    }
}

const SHOWN_ITEMS: usize = 3;

pub fn shown(clauses: &[Clause]) -> Vec<Clause> {
    let mut once: Vec<&Clause> = Vec::new();
    for clause in clauses {
        if !once.contains(&clause) {
            once.push(clause);
        }
    }
    let of_kind = |kind: Kind| {
        once.iter()
            .copied()
            .filter(move |clause| clause.kind == kind)
    };
    let mut out: Vec<Clause> = of_kind(Kind::Root).cloned().collect();
    out.sort_by(|a, b| (a.cause, &a.name).cmp(&(b.cause, &b.name)));
    out.extend(of_kind(Kind::List).cloned());
    let items: Vec<&Clause> = of_kind(Kind::Item).collect();
    let leaves: usize = items.iter().map(|item| pieces(item).len()).sum();
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
    });
    out
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
    let mut run_kept: Option<bool> = None;
    for clause in &item.said {
        if clause.kind == Kind::Item {
            run_kept = None;
            kept.said.extend(cut(clause, left));
        } else {
            let keep = *run_kept.get_or_insert_with(|| {
                let keep = *left > 0;
                *left = left.saturating_sub(1);
                keep
            });
            if keep {
                kept.said.push(clause.clone());
            }
        }
    }
    (!kept.text.is_empty() || !kept.said.is_empty()).then_some(kept)
}

#[cfg(test)]
mod tests;
