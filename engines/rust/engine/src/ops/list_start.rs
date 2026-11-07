use super::Check;
use super::for_line::{How, Item};
use super::lists::{Right, Wanted};
use super::tally::{Counted, Side, Term};
use crate::path::{self, OUTER, PartStart, Path, Start, Step};

/// Returns the check as it reads a subject that is a list: each path in
/// a place that walks lists, after `every`, `some`, `count of`, `sum of`,
/// on a `for` line or on the right of a phrase that takes a list, starts
/// at the subject's name `label` instead of the subject, so the subject
/// is walked as a list.
pub fn read(check: &Check, label: &str) -> Check {
    if reads_root_field(check) || (!matches!(check, Check::AnyOf(_)) && reads_plainly(check, false))
    {
        return check.clone();
    }
    let at = At {
        label,
        rooted: false,
    };
    match check {
        Check::For(line) => {
            let mut line = (**line).clone();
            for item in &mut line.items {
                at.item(item);
            }
            for sentence in &mut line.sentences {
                sentence.check = at.leaf(&sentence.check);
            }
            Check::For(Box::new(line))
        }
        Check::AnyOf(any) => {
            let mut any = any.clone();
            for option in &mut any.options {
                for check in option.iter_mut() {
                    if !reads_plainly(check, false) {
                        *check = at.leaf(check);
                    }
                }
            }
            Check::AnyOf(any)
        }
        other => at.leaf(other),
    }
}

#[derive(Clone, Copy)]
struct At<'a> {
    label: &'a str,
    rooted: bool,
}

impl At<'_> {
    fn inside(self) -> Self {
        At {
            rooted: true,
            ..self
        }
    }

    fn item(self, item: &mut Item) {
        if matches!(item.how, How::Pick { .. }) {
            return;
        }
        item.path = self.path(&item.path);
        item.whose = item.whose.iter().map(|c| self.inside().leaf(c)).collect();
    }

    fn leaf(self, check: &Check) -> Check {
        match check {
            Check::Walk(walk) => {
                let mut walk = (**walk).clone();
                walk.path = self.path(&walk.path);
                walk.check = Box::new(self.inside().leaf(&walk.check));
                walk.whose = walk.whose.iter().map(|c| self.inside().leaf(c)).collect();
                Check::Walk(Box::new(walk))
            }
            Check::Tally(tally) => {
                let mut tally = tally.clone();
                tally.left = self.side(&tally.left);
                tally.right = tally.right.as_ref().map(|side| self.side(side));
                Check::Tally(tally)
            }
            Check::In(check) => {
                let mut check = check.clone();
                check.values = self.right(&check.values);
                Check::In(check)
            }
            Check::Contains(check) => {
                let mut check = check.clone();
                check.wanted = match &check.wanted {
                    Wanted::One(right) => Wanted::One(right.clone()),
                    Wanted::All(right) => Wanted::All(self.right(right)),
                    Wanted::Some(right) => Wanted::Some(self.right(right)),
                };
                Check::Contains(check)
            }
            Check::Matches(check) => {
                let mut check = check.clone();
                check.patterns = self.right(&check.patterns);
                Check::Matches(check)
            }
            other => other.clone(),
        }
    }

    fn right(self, right: &Right) -> Right {
        match right {
            Right::Field(path) => Right::Field(self.path(path)),
            other => other.clone(),
        }
    }

    fn side(self, side: &Side) -> Side {
        match side {
            Side::Derived(derived) => {
                let mut derived = derived.clone();
                derived.terms = derived.terms.iter().map(|term| self.term(term)).collect();
                Side::Derived(derived)
            }
            plain => plain.clone(),
        }
    }

    fn term(self, term: &Term) -> Term {
        match term {
            Term::Counted(counted) => Term::Counted(Counted {
                path: self.path(&counted.path),
                whose: counted
                    .whose
                    .iter()
                    .map(|c| self.inside().condition(c))
                    .collect(),
                ..counted.clone()
            }),
            other => other.clone(),
        }
    }

    fn condition(self, check: &Check) -> Check {
        match check {
            Check::Tally(tally) => {
                let flat = |side: &Side| match side {
                    Side::Derived(derived) => {
                        let mut derived = derived.clone();
                        derived.terms = derived
                            .terms
                            .iter()
                            .map(|term| match term {
                                Term::Counted(counted) => Term::Counted(Counted {
                                    path: self.path(&counted.path),
                                    ..counted.clone()
                                }),
                                other => other.clone(),
                            })
                            .collect();
                        Side::Derived(derived)
                    }
                    plain => plain.clone(),
                };
                let mut tally = tally.clone();
                tally.left = flat(&tally.left);
                tally.right = tally.right.as_ref().map(flat);
                Check::Tally(tally)
            }
            Check::Walk(_) | Check::For(_) | Check::AnyOf(_) => check.clone(),
            other => self.leaf(other),
        }
    }

    fn path(self, path: &Path) -> Path {
        if has_field(path) {
            return path.clone();
        }
        let base = if self.rooted {
            Start::Alias(OUTER.to_string())
        } else {
            Start::Subject
        };
        let steps: Vec<Step> = match &path.start {
            Start::Subject | Start::Own if !self.rooted => path.steps.clone(),
            start if self.rooted && path::is_root(start) => path.steps.clone(),
            Start::Part(part) if part.base == base && !part.steps.is_empty() => part
                .steps
                .iter()
                .chain(path.steps.iter())
                .cloned()
                .collect(),
            _ => return path.clone(),
        };
        if !matches!(steps.first(), Some(Step::Key(_))) {
            return path.clone();
        }
        Path {
            start: Start::Part(Box::new(PartStart {
                name: self.label.to_string(),
                base,
                steps: Vec::new(),
                id: None,
            })),
            steps,
        }
    }
}

fn reads_plainly(check: &Check, top: bool) -> bool {
    let read = |path: &Path| plain_path(path, top);
    match check {
        Check::Walk(walk) => {
            reads_plainly(&walk.check, false) || walk.whose.iter().any(|c| reads_plainly(c, false))
        }
        Check::For(line) => {
            line.items
                .iter()
                .any(|item| item.whose.iter().any(|c| reads_plainly(c, false)))
                || line
                    .sentences
                    .iter()
                    .any(|sentence| reads_plainly(&sentence.check, true))
        }
        Check::AnyOf(any) => any.options.iter().flatten().any(|c| reads_plainly(c, top)),
        Check::Tally(tally) => std::iter::once(&tally.left)
            .chain(tally.right.as_ref())
            .any(|side| match side {
                Side::Plain(plain) => plain.paths().into_iter().any(read),
                Side::Derived(derived) => derived.terms.iter().any(|term| match term {
                    Term::Path(path) => read(path),
                    Term::Elapsed(elapsed) => read(&elapsed.from) || read(&elapsed.to),
                    Term::Counted(counted) => counted.whose.iter().any(|c| reads_plainly(c, false)),
                    Term::Number(_) => false,
                }),
            }),
        Check::In(c) => read(&c.path),
        Check::Matches(c) => read(&c.path),
        Check::Contains(c) => {
            read(&c.path)
                || match &c.wanted {
                    Wanted::One(Right::Ref(path) | Right::Field(path)) => read(path),
                    _ => false,
                }
        }
        other => other.paths().into_iter().any(read),
    }
}

fn plain_path(path: &Path, top: bool) -> bool {
    let first = path::leading_steps(&path.start)
        .iter()
        .chain(path.steps.iter())
        .next();
    if matches!(first, Some(Step::Index(_))) {
        return false;
    }
    let steps = !path.steps.is_empty();
    match &path.start {
        start if path::is_root(start) => steps,
        Start::Part(part) if part.base == Start::Alias(OUTER.to_string()) => {
            steps || !part.steps.is_empty()
        }
        Start::Part(part) if part.base == Start::Subject => !part.steps.is_empty(),
        Start::Subject | Start::Own if top => steps,
        _ => {
            top && path
                .steps
                .iter()
                .any(|step| matches!(step, Step::Field(field) if field.start == Start::Subject))
        }
    }
}

fn has_field(path: &Path) -> bool {
    path::leading_steps(&path.start)
        .iter()
        .chain(path.steps.iter())
        .any(|step| matches!(step, Step::Field(_)))
}

fn reads_root_field(check: &Check) -> bool {
    fn root_field(path: &Path) -> bool {
        path::leading_steps(&path.start)
            .iter()
            .chain(path.steps.iter())
            .any(|step| match step {
                Step::Field(field) => {
                    path::is_root(&field.start) || path::names_the_subject(&field.start)
                }
                _ => false,
            })
    }
    let mut paths = Vec::new();
    every_path(check, &mut paths);
    paths.into_iter().any(root_field)
}

fn every_path<'a>(check: &'a Check, out: &mut Vec<&'a Path>) {
    out.extend(check.paths());
    match check {
        Check::Walk(walk) => {
            out.push(&walk.path);
            every_path(&walk.check, out);
            for inner in &walk.whose {
                every_path(inner, out);
            }
        }
        Check::Tally(tally) => {
            for side in std::iter::once(&tally.left).chain(tally.right.as_ref()) {
                if let Side::Derived(derived) = side {
                    for term in &derived.terms {
                        if let Term::Counted(counted) = term {
                            out.push(&counted.path);
                            for inner in &counted.whose {
                                every_path(inner, out);
                            }
                        }
                    }
                }
            }
        }
        Check::For(line) => {
            for item in &line.items {
                out.push(&item.path);
                for inner in &item.whose {
                    every_path(inner, out);
                }
            }
            for sentence in &line.sentences {
                every_path(&sentence.check, out);
            }
        }
        Check::AnyOf(any) => {
            for check in any.options.iter().flatten() {
                every_path(check, out);
            }
        }
        Check::In(check) => out.extend(check.values.ref_paths()),
        Check::Matches(check) => out.extend(check.patterns.ref_paths()),
        Check::Contains(check) => match &check.wanted {
            Wanted::One(right) | Wanted::All(right) | Wanted::Some(right) => {
                out.extend(right.ref_paths())
            }
        },
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    fn row(check: Value, subject: Value) -> Value {
        let policy = json!({
            "ergo_spec": "v0.6-dev",
            "subjects": {"t": {"from": "every xs"}},
            "requirements": {"r": {"subject": "t", "checks": {"c": check}}}
        });
        let report = crate::report(&json!({"xs": [subject]}), &policy, &json!({"w": "a"}));
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["check"] == "c")
            .unwrap()
            .clone()
    }

    #[test]
    fn every_walks_a_subject_that_is_a_list_and_names_it_after_the_subject() {
        let found = row(
            json!("every name is \"a\""),
            json!([{"name": "a"}, {"name": "b"}]),
        );
        assert_eq!(found["cause"], "value");
        assert_eq!(found["inputs"][0]["name"], "t[].name");
        assert_eq!(found["failed_items"][0]["path"], "t[1].name");
        assert_eq!(found["message"], "item 2 of t: name is \"b\"");
    }

    #[test]
    fn the_right_side_of_is_in_walks_a_subject_that_is_a_list_but_contains_does_not() {
        let subject = json!([{"name": "a"}, {"name": "b"}]);
        assert_eq!(
            row(json!("$params.w is in name"), subject.clone())["cause"],
            "satisfied"
        );
        assert_eq!(
            row(json!("$params.w contains name"), subject)["cause"],
            "not_an_object"
        );
    }

    #[test]
    fn a_path_without_a_walking_word_still_fails_on_a_subject_that_is_a_list() {
        assert_eq!(
            row(json!("name is \"a\""), json!([{"name": "a"}]))["cause"],
            "not_an_object"
        );
    }

    #[test]
    fn a_for_item_with_a_position_reads_a_list_subject_as_before() {
        let check = json!({"for": "first of owner as o", "assert": "o is \"a\""});
        assert_eq!(
            row(check, json!([{"owner": "a"}]))["cause"],
            "not_an_object"
        );
    }

    #[test]
    fn a_named_by_key_read_from_a_subject_that_is_a_list_fails_the_whole_check() {
        let found = row(
            json!("every n is less than $params.m named by k"),
            json!([{"n": 1, "k": "a"}]),
        );
        assert_eq!(found["cause"], "not_an_object");
        assert_eq!(found["failed_items"], json!([]));
    }
}
