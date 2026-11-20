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
}

const SHOWN_ITEMS: usize = 3;

pub fn shown(clauses: &[Clause]) -> Vec<Clause> {
    let mut out: Vec<Clause> = clauses
        .iter()
        .filter(|clause| clause.kind == Kind::Root)
        .cloned()
        .collect();
    let items: Vec<&Clause> = clauses
        .iter()
        .filter(|clause| clause.kind == Kind::Item)
        .collect();
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

fn pieces(item: &Clause) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
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
    (!kept.said.is_empty()).then_some(kept)
}

#[cfg(test)]
mod tests;
