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
    out.extend(items.iter().take(SHOWN_ITEMS).map(|item| (*item).clone()));
    if items.len() > SHOWN_ITEMS {
        out.push(Clause {
            kind: Kind::More(items.len() - SHOWN_ITEMS),
            name: String::new(),
            cause: Cause::Value,
            text: String::new(),
            said: Vec::new(),
        });
    }
    out
}

pub fn text(clauses: &[Clause]) -> String {
    clauses
        .iter()
        .map(|clause| match clause.kind {
            Kind::More(count) => format!("and {count} more"),
            Kind::Item => format!("{}: {}", clause.name, said_text(&clause.said)),
            Kind::Root | Kind::List => clause.text.clone(),
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn said_text(said: &[Clause]) -> String {
    said.iter()
        .map(|clause| clause.text.as_str())
        .collect::<Vec<_>>()
        .join(", and ")
}

#[cfg(test)]
mod tests;
