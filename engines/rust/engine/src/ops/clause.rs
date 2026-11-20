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

pub fn shown(clauses: &[Clause]) -> Vec<Clause> {
    let _ = clauses;
    todo!()
}

pub fn text(clauses: &[Clause]) -> String {
    let _ = clauses;
    todo!()
}
