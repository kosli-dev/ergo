use super::*;

fn read(kind: Kind, name: &str, cause: Cause, text: &str) -> Clause {
    Clause {
        kind,
        name: name.to_string(),
        cause,
        text: text.to_string(),
        said: Vec::new(),
    }
}

fn root(name: &str, cause: Cause, text: &str) -> Clause {
    read(Kind::Root, name, cause, text)
}

fn item(name: &str, cause: Cause, said: Vec<Clause>) -> Clause {
    Clause {
        said,
        ..read(Kind::Item, name, cause, "")
    }
}

fn missing(name: &str) -> Clause {
    root(name, Cause::Absent, &format!("{name} is missing"))
}

#[test]
fn and_n_more_comes_after_the_roots_and_the_lists_in_a_count() {
    let mut clauses: Vec<Clause> = (1..=5)
        .map(|n| item(&format!("item {n} of xs"), Cause::Absent, vec![missing("v")]))
        .collect();
    clauses.push(root(
        "$params.min",
        Cause::Unusable,
        "$params.min is \"s\", which isn't a number",
    ));
    assert_eq!(
        text(&shown(&clauses)),
        "$params.min is \"s\", which isn't a number; item 1 of xs: v is missing; item 2 of xs: v is missing; item 3 of xs: v is missing; and 2 more"
    );
}
