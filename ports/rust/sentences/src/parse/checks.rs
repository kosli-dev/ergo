use super::*;

#[derive(Clone)]
pub(crate) enum Note {
    Text(&'static str),
    Hidden(Vec<Condition>),
}

pub(crate) type Notes = Vec<Note>;

pub(crate) const WHOSE_PLACE: &str = "a whose goes after every, some, count of or sum of";
pub(crate) const ITEM_START: &str =
    r#"an item starts with "every", "some" or a position, like "last of""#;
pub(crate) const SORTED_AFTER: &str =
    r#""sorted by" goes after a position, like "last of", not after every or some"#;
pub(crate) const IF_ANY_POSITION: &str = "if any can't go with a position";

fn joined(first: &Notes, second: &Notes) -> Notes {
    first.iter().chain(second.iter()).cloned().collect()
}

impl Parser {
    fn conditions(&self, i: usize) -> Reads<Vec<Condition>> {
        if let Some(done) = self.condition_memo.borrow().get(&i) {
            return done.clone();
        }
        let mut out = Vec::new();
        for (condition, j) in self.condition(i) {
            if let Some(k) = self.ws(j).and_then(|m| self.lead(m, "and")) {
                for (rest, end) in self.conditions(k) {
                    let mut all = vec![condition.clone()];
                    all.extend(rest);
                    out.push((all, end));
                }
            }
            out.push((vec![condition], j));
        }
        self.condition_memo.borrow_mut().insert(i, out.clone());
        out
    }

    fn whose_opt(&self, i: usize) -> Reads<Vec<Condition>> {
        let mut out = Vec::new();
        if let Some(k) = self.ws(i).and_then(|m| self.lead(m, "whose")) {
            out.extend(self.conditions(k));
        }
        out.push((Vec::new(), i));
        out
    }

    fn if_any_opt(&self, i: usize) -> Vec<(bool, usize)> {
        let mut out = Vec::new();
        if let Some(j) = self.if_any(i) {
            out.push((true, j));
        }
        out.push((false, i));
        out
    }

    fn left_terms(&self, i: usize) -> Reads<(Vec<Term>, Notes)> {
        let mut out = Vec::new();
        for (head, j) in self.term(i) {
            for (rest, e) in self.plus_tail(j) {
                let mut chain = vec![head.clone()];
                chain.extend(rest);
                let allowed = chain.len() > 1
                    || match chain[0] {
                        Term::Derived(_) | Term::Elapsed(_) => true,
                        Term::Number(_) => self.lenient,
                        Term::Path(_) => false,
                    };
                if !allowed {
                    continue;
                }
                let last_derived = matches!(chain.last(), Some(Term::Derived(_)));
                if last_derived || self.lenient {
                    for (whose, w) in self.whose_opt(e) {
                        if whose.is_empty() {
                            continue;
                        }
                        let mut with = chain.clone();
                        let mut notes = Vec::new();
                        match with.last_mut() {
                            Some(Term::Derived(derived)) => derived.whose = whose,
                            _ => {
                                notes.push(Note::Text(WHOSE_PLACE));
                                notes.push(Note::Hidden(whose));
                            }
                        }
                        out.push(((with, notes), w));
                    }
                }
                out.push(((chain, Vec::new()), e));
            }
        }
        out
    }

    fn assertion(&self, i: usize) -> Reads<(Assertion, Notes)> {
        let mut out = Vec::new();
        if let Some((quantifier, j)) = self.quantifier(i)
            && let Some(k) = self.ws(j)
        {
            for (path, m) in self.path_or_it(k) {
                for (whose, w) in self.whose_opt(m) {
                    for (if_any, n) in self.if_any_opt(w) {
                        let Some(p) = self.ws(n) else { continue };
                        for (phrase, end) in self.phrase(p, false) {
                            let assertion = Assertion::Quantified {
                                quantifier,
                                path: path.clone(),
                                whose: whose.clone(),
                                if_any,
                                phrase,
                            };
                            out.push(((assertion, Vec::new()), end));
                        }
                    }
                }
            }
        }
        for (path, j) in self.path_or_it(i) {
            let mut starts = vec![(j, Vec::new())];
            if self.lenient {
                for (whose, w) in self.whose_opt(j) {
                    if !whose.is_empty() {
                        starts.push((
                            w,
                            vec![Note::Text(WHOSE_PLACE), Note::Hidden(whose.clone())],
                        ));
                    }
                }
            }
            for (at, notes) in starts {
                let Some(k) = self.ws(at) else { continue };
                for (phrase, end) in self.phrase(k, false) {
                    let assertion = Assertion::Plain {
                        path: path.clone(),
                        phrase,
                    };
                    out.push(((assertion, notes.clone()), end));
                }
            }
        }
        for ((terms, notes), j) in self.left_terms(i) {
            let Some(k) = self.ws(j) else { continue };
            for (phrase, end) in self.phrase(k, !self.lenient) {
                let assertion = Assertion::Derived {
                    terms: terms.clone(),
                    phrase,
                };
                out.push(((assertion, notes.clone()), end));
            }
        }
        out
    }

    fn assertions(&self, i: usize) -> Reads<(Vec<Assertion>, Notes)> {
        if let Some(done) = self.assertion_memo.borrow().get(&i) {
            return done.clone();
        }
        let mut out = Vec::new();
        for ((assertion, notes), j) in self.assertion(i) {
            if let Some(k) = self.ws(j).and_then(|m| self.lead(m, "and")) {
                for ((rest, more), end) in self.assertions(k) {
                    let mut all = vec![assertion.clone()];
                    all.extend(rest);
                    out.push(((all, joined(&notes, &more)), end));
                }
            }
            out.push(((vec![assertion], notes), j));
        }
        self.assertion_memo.borrow_mut().insert(i, out.clone());
        out
    }

    pub(crate) fn read_check(&self) -> Option<(Check, Notes)> {
        self.whole(self.assertions(0))
            .map(|(assertions, notes)| (Check { assertions }, notes))
    }

    fn sorted_opt(&self, i: usize) -> Reads<Option<SortedBy>> {
        let mut out = Vec::new();
        if let Some(j) = self.ws(i).and_then(|m| self.lead(m, "sorted by")) {
            let paths: Reads<Path> = if self.lenient {
                self.path(j, Side::Left)
            } else {
                self.plain_path(j, Side::Left)
                    .into_iter()
                    .filter(|(p, _)| matches!(p.start, Start::Field { .. }))
                    .collect()
            };
            for (path, k) in paths {
                if let Some(end) = self.ws(k).and_then(|m| self.lit(m, "alphabetically")) {
                    out.push((
                        Some(SortedBy {
                            path: path.clone(),
                            alphabetically: true,
                        }),
                        end,
                    ));
                }
                out.push((
                    Some(SortedBy {
                        path,
                        alphabetically: false,
                    }),
                    k,
                ));
            }
        }
        out.push((None, i));
        out
    }

    fn alias_after(&self, i: usize) -> Option<(String, usize)> {
        let j = self.ws(i).and_then(|m| self.lead(m, "as"))?;
        self.bare_key(j)
    }

    fn strict_item(&self, i: usize) -> Reads<(ForItem, Notes)> {
        let mut out = Vec::new();
        if let Some((quantifier, j)) = self.quantifier(i)
            && let Some(k) = self.ws(j)
        {
            for (path, m) in self.path(k, Side::Left) {
                for (whose, w) in self.whose_opt(m) {
                    for (if_any, n) in self.if_any_opt(w) {
                        if let Some((alias, end)) = self.alias_after(n) {
                            let item = ForItem::Walk {
                                quantifier,
                                path: path.clone(),
                                whose: whose.clone(),
                                if_any,
                                alias,
                            };
                            out.push(((item, Vec::new()), end));
                        }
                    }
                }
            }
        }
        for (position, k) in self.after_position(i) {
            for (path, m) in self.plain_path(k, Side::Left) {
                for (whose, w) in self.whose_opt(m) {
                    for (sorted_by, s) in self.sorted_opt(w) {
                        if let Some((alias, end)) = self.alias_after(s) {
                            let item = ForItem::Pick {
                                position: position.clone(),
                                path: path.clone(),
                                whose: whose.clone(),
                                sorted_by,
                                alias,
                            };
                            out.push(((item, Vec::new()), end));
                        }
                    }
                }
            }
        }
        out
    }

    fn lenient_item(&self, i: usize) -> Reads<(ForItem, Notes)> {
        let mut heads: Vec<(Option<Quantifier>, usize)> = Vec::new();
        if let Some((quantifier, j)) = self.quantifier(i)
            && let Some(k) = self.ws(j)
        {
            heads.push((Some(quantifier), k));
        }
        heads.push((None, i));
        let mut out = Vec::new();
        for (quantifier, k) in heads {
            for (path, m) in self.path(k, Side::Left) {
                for (whose, w) in self.whose_opt(m) {
                    for (sorted_by, s) in self.sorted_opt(w) {
                        for (if_any, n) in self.if_any_opt(s) {
                            let Some((alias, end)) = self.alias_after(n) else {
                                continue;
                            };
                            let mut notes = Vec::new();
                            let item = match (quantifier, sorted_by.clone()) {
                                (Some(quantifier), None) => ForItem::Walk {
                                    quantifier,
                                    path: path.clone(),
                                    whose: whose.clone(),
                                    if_any,
                                    alias,
                                },
                                (q, sorted_by) => {
                                    if q.is_some() {
                                        notes.push(Note::Text(SORTED_AFTER));
                                    } else if path.position.is_none() {
                                        notes.push(Note::Text(ITEM_START));
                                    }
                                    if q.is_none() && if_any {
                                        notes.push(Note::Text(IF_ANY_POSITION));
                                    }
                                    let mut bare = path.clone();
                                    let position = bare.position.take().unwrap_or(Position::First);
                                    ForItem::Pick {
                                        position,
                                        path: bare,
                                        whose: whose.clone(),
                                        sorted_by,
                                        alias,
                                    }
                                }
                            };
                            out.push(((item, notes), end));
                        }
                    }
                }
            }
        }
        out
    }

    fn for_items(&self, i: usize, most: usize) -> Reads<(Vec<ForItem>, Notes)> {
        let items = if self.lenient {
            self.lenient_item(i)
        } else {
            self.strict_item(i)
        };
        let mut out = Vec::new();
        for ((item, notes), j) in items {
            if most > 1
                && let Some(k) = self.lit(j, ",").and_then(|m| self.ws(m))
            {
                for ((rest, more), end) in self.for_items(k, most - 1) {
                    let mut all = vec![item.clone()];
                    all.extend(rest);
                    out.push(((all, joined(&notes, &more)), end));
                }
            }
            out.push(((vec![item], notes), j));
        }
        out
    }

    pub(crate) fn read_for(&self, most: usize) -> Option<(For, Notes)> {
        self.whole(self.for_items(0, most))
            .map(|(items, notes)| (For { items }, notes))
    }
}
