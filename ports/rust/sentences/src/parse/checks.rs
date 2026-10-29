use super::*;

#[derive(Clone)]
pub(crate) enum Note {
    Text(&'static str),
    Hidden(Chain<Condition>),
}

pub(crate) type Notes = Vec<Note>;

pub(crate) const WHOSE_PLACE: &str = "a whose goes after every, some, count of or sum of";
pub(crate) const ITEM_START: &str =
    r#"an item starts with "every", "some" or a position, like "last of""#;
pub(crate) const SORTED_AFTER: &str =
    r#""sorted by" goes after a position, like "last of", not after every or some"#;
pub(crate) const IF_ANY_POSITION: &str = "if any can't go with a position";

fn flatten<T: Clone>(chain: &Chain<Noted<T>>) -> (Vec<T>, Notes) {
    let mut items = Vec::new();
    let mut notes = Vec::new();
    for (item, more) in chain_items(chain) {
        items.push(item);
        notes.extend(more);
    }
    (items, notes)
}

impl Parser {
    fn conditions(&self, i: usize) -> Reads<Chain<Condition>> {
        chain_reads(
            i,
            usize::MAX,
            |at| heads_at(&self.condition_memo, at, || self.condition(at)),
            |end| self.ws(end).and_then(|m| self.lead(m, "and")),
        )
    }

    fn whose_opt(&self, i: usize) -> Reads<Chain<Condition>> {
        let mut out = Vec::new();
        if let Some(k) = self.ws(i).and_then(|m| self.lead(m, "whose")) {
            out.extend(self.conditions(k));
        }
        out.push((None, i));
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
                        if whose.is_none() {
                            continue;
                        }
                        let mut with = chain.clone();
                        let mut notes = Vec::new();
                        match with.last_mut() {
                            Some(Term::Derived(derived)) => derived.whose = chain_items(&whose),
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
                                whose: chain_items(&whose),
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
                    if whose.is_some() {
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

    fn assertions(&self, i: usize) -> Reads<Chain<Noted<Assertion>>> {
        chain_reads(
            i,
            usize::MAX,
            |at| heads_at(&self.assertion_memo, at, || self.assertion(at)),
            |end| self.ws(end).and_then(|m| self.lead(m, "and")),
        )
    }

    pub(crate) fn read_check(&self) -> Option<(Check, Notes)> {
        self.whole(self.assertions(0)).map(|chain| {
            let (assertions, notes) = flatten(&chain);
            (Check { assertions }, notes)
        })
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
                                whose: chain_items(&whose),
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
                                whose: chain_items(&whose),
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
                                    whose: chain_items(&whose),
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
                                        whose: chain_items(&whose),
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

    fn for_items(&self, most: usize) -> Reads<Chain<Noted<ForItem>>> {
        chain_reads(
            0,
            most,
            |at| {
                heads_at(&self.item_memo, at, || {
                    if self.lenient {
                        self.lenient_item(at)
                    } else {
                        self.strict_item(at)
                    }
                })
            },
            |end| self.lit(end, ",").and_then(|m| self.ws(m)),
        )
    }

    pub(crate) fn read_for(&self, most: usize) -> Option<(ForLine, Notes)> {
        self.whole(self.for_items(most)).map(|chain| {
            let (items, notes) = flatten(&chain);
            (ForLine { items }, notes)
        })
    }
}
