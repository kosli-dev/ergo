use crate::tree::*;
use crate::words::is_word;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

mod checks;

pub(crate) use checks::{ITEM_START, Note, Notes};

pub(crate) type Reads<T> = Vec<(T, usize)>;
pub(crate) type Noted<T> = (T, Notes);
pub(crate) type Chain<T> = Option<Rc<Link<T>>>;
type Heads<T> = RefCell<HashMap<usize, Rc<Reads<T>>>>;

pub(crate) struct Link<T> {
    item: T,
    before: Chain<T>,
}

impl<T> Drop for Link<T> {
    fn drop(&mut self) {
        let mut next = self.before.take();
        while let Some(link) = next {
            match Rc::try_unwrap(link) {
                Ok(mut link) => next = link.before.take(),
                Err(_) => break,
            }
        }
    }
}

pub(crate) fn chain_items<T: Clone>(chain: &Chain<T>) -> Vec<T> {
    let mut items = Vec::new();
    let mut at = chain.as_deref();
    while let Some(link) = at {
        items.push(link.item.clone());
        at = link.before.as_deref();
    }
    items.reverse();
    items
}

fn heads_at<T>(memo: &Heads<T>, i: usize, make: impl FnOnce() -> Reads<T>) -> Rc<Reads<T>> {
    if let Some(done) = memo.borrow().get(&i) {
        return Rc::clone(done);
    }
    let made = Rc::new(make());
    memo.borrow_mut().insert(i, Rc::clone(&made));
    made
}

pub(crate) fn chain_reads<T: Clone>(
    start: usize,
    most: usize,
    heads: impl Fn(usize) -> Rc<Reads<T>>,
    after: impl Fn(usize) -> Option<usize>,
) -> Reads<Chain<T>> {
    struct Frame<T> {
        heads: Rc<Reads<T>>,
        next: usize,
        before: Chain<T>,
        length: usize,
        pending: Option<(Chain<T>, usize)>,
    }
    let mut out = Vec::new();
    let mut stack = vec![Frame {
        heads: heads(start),
        next: 0,
        before: None,
        length: 0,
        pending: None,
    }];
    while let Some(frame) = stack.last_mut() {
        if let Some(done) = frame.pending.take() {
            out.push(done);
        }
        let Some((item, end)) = frame.heads.get(frame.next).cloned() else {
            stack.pop();
            continue;
        };
        frame.next += 1;
        let link = Some(Rc::new(Link {
            item,
            before: frame.before.clone(),
        }));
        let length = frame.length + 1;
        frame.pending = Some((link.clone(), end));
        if length < most
            && let Some(k) = after(end)
        {
            stack.push(Frame {
                heads: heads(k),
                next: 0,
                before: link,
                length,
                pending: None,
            });
        }
    }
    out
}

pub(crate) struct FromRead {
    every: bool,
    path: Path,
    named_by_each_of: Option<Path>,
    whose: Chain<FromCondition>,
}

impl FromRead {
    pub(crate) fn build(self) -> FromLine {
        FromLine {
            every: self.every,
            path: self.path,
            named_by_each_of: self.named_by_each_of,
            whose: chain_items(&self.whose),
        }
    }
}

pub(crate) struct Parser {
    c: Vec<char>,
    lenient: bool,
    memo: Heads<FromCondition>,
    condition_memo: Heads<Condition>,
    assertion_memo: Heads<Noted<Assertion>>,
    item_memo: Heads<Noted<ForItem>>,
}

fn is_key_start(ch: char) -> bool {
    ch.is_ascii_alphabetic() || ch == '_'
}

fn is_key_char(ch: char) -> bool {
    ch.is_ascii_alphanumeric() || ch == '_' || ch == '-'
}

impl Parser {
    pub(crate) fn new(text: &str, lenient: bool) -> Self {
        Parser {
            c: text.chars().collect(),
            lenient,
            memo: RefCell::new(HashMap::new()),
            condition_memo: RefCell::new(HashMap::new()),
            assertion_memo: RefCell::new(HashMap::new()),
            item_memo: RefCell::new(HashMap::new()),
        }
    }

    pub(crate) fn len(&self) -> usize {
        self.c.len()
    }

    fn at(&self, i: usize) -> Option<char> {
        self.c.get(i).copied()
    }

    fn lit(&self, i: usize, text: &str) -> Option<usize> {
        let mut j = i;
        for ch in text.chars() {
            if self.at(j) != Some(ch) {
                return None;
            }
            j += 1;
        }
        Some(j)
    }

    fn ws(&self, i: usize) -> Option<usize> {
        let mut j = i;
        while self.at(j) == Some(' ') {
            j += 1;
        }
        if j > i { Some(j) } else { None }
    }

    fn words(&self, i: usize, spelling: &str) -> Option<usize> {
        let mut j = i;
        for (n, word) in spelling.split(' ').enumerate() {
            if n > 0 {
                j = self.ws(j)?;
            }
            j = self.lit(j, word)?;
        }
        Some(j)
    }

    fn lead(&self, i: usize, spelling: &str) -> Option<usize> {
        let j = self.words(i, spelling)?;
        self.ws(j)
    }

    fn bare_key(&self, i: usize) -> Option<(String, usize)> {
        let first = self.at(i)?;
        if !is_key_start(first) {
            return None;
        }
        let mut j = i + 1;
        while self.at(j).is_some_and(is_key_char) {
            j += 1;
        }
        Some((self.c[i..j].iter().collect(), j))
    }

    fn hex4(&self, i: usize) -> Option<u32> {
        let mut value = 0;
        for k in 0..4 {
            value = value * 16 + self.at(i + k)?.to_digit(16)?;
        }
        Some(value)
    }

    fn dq(&self, i: usize) -> Option<(String, usize)> {
        if self.at(i) != Some('"') {
            return None;
        }
        let mut out = String::new();
        let mut j = i + 1;
        loop {
            let ch = self.at(j)?;
            match ch {
                '"' => return Some((out, j + 1)),
                '\\' => {
                    let esc = self.at(j + 1)?;
                    j += 2;
                    match esc {
                        '"' | '\\' | '/' => out.push(esc),
                        'b' => out.push('\u{8}'),
                        'f' => out.push('\u{c}'),
                        'n' => out.push('\n'),
                        'r' => out.push('\r'),
                        't' => out.push('\t'),
                        'u' => {
                            let unit = self.hex4(j)?;
                            j += 4;
                            if (0xD800..0xDC00).contains(&unit) {
                                let low = if self.at(j) == Some('\\') && self.at(j + 1) == Some('u')
                                {
                                    self.hex4(j + 2)
                                        .filter(|low| (0xDC00..0xE000).contains(low))
                                } else {
                                    None
                                };
                                match low {
                                    Some(low) => {
                                        j += 6;
                                        let code =
                                            0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
                                        out.push(char::from_u32(code).unwrap_or('\u{FFFD}'));
                                    }
                                    None => out.push('\u{FFFD}'),
                                }
                            } else {
                                out.push(char::from_u32(unit).unwrap_or('\u{FFFD}'));
                            }
                        }
                        _ => return None,
                    }
                }
                ch if (ch as u32) < 0x20 => return None,
                ch => {
                    out.push(ch);
                    j += 1;
                }
            }
        }
    }

    fn sq(&self, i: usize) -> Option<(String, usize)> {
        if self.at(i) != Some('\'') {
            return None;
        }
        let mut out = String::new();
        let mut j = i + 1;
        loop {
            let ch = self.at(j)?;
            match ch {
                '\'' => return Some((out, j + 1)),
                '\\' => {
                    let next = self.at(j + 1)?;
                    if (next as u32) < 0x20 {
                        return None;
                    }
                    if next != '\'' && next != '\\' {
                        out.push('\\');
                    }
                    out.push(next);
                    j += 2;
                }
                ch if (ch as u32) < 0x20 => return None,
                ch => {
                    out.push(ch);
                    j += 1;
                }
            }
        }
    }

    fn digits(&self, i: usize) -> usize {
        let mut j = i;
        while self.at(j).is_some_and(|ch| ch.is_ascii_digit()) {
            j += 1;
        }
        j
    }

    fn int(&self, i: usize) -> Option<usize> {
        match self.at(i)? {
            '0' => Some(i + 1),
            '1'..='9' => Some(self.digits(i)),
            _ => None,
        }
    }

    fn number(&self, i: usize) -> Option<(String, usize)> {
        let mut j = i;
        if self.at(j) == Some('-') {
            j += 1;
        }
        j = self.int(j)?;
        if self.at(j) == Some('.') {
            let end = self.digits(j + 1);
            if end > j + 1 {
                j = end;
            }
        }
        if matches!(self.at(j), Some('e' | 'E')) {
            let mut k = j + 1;
            if matches!(self.at(k), Some('+' | '-')) {
                k += 1;
            }
            let end = self.digits(k);
            if end > k {
                j = end;
            }
        }
        Some((self.c[i..j].iter().collect(), j))
    }

    fn value(&self, i: usize) -> Reads<Value> {
        let mut out = Vec::new();
        match self.at(i) {
            Some('"') => out.extend(self.dq(i).map(|(s, j)| (Value::String(s), j))),
            Some('\'') => out.extend(self.sq(i).map(|(s, j)| (Value::String(s), j))),
            Some('-' | '0'..='9') => out.extend(self.number(i).map(|(n, j)| (Value::Number(n), j))),
            _ => {
                if let Some(j) = self.lit(i, "true") {
                    out.push((Value::True, j));
                } else if let Some(j) = self.lit(i, "false") {
                    out.push((Value::False, j));
                } else if let Some(j) = self.lit(i, "null") {
                    out.push((Value::Null, j));
                }
            }
        }
        out
    }

    fn values(&self, i: usize) -> Reads<Vec<Value>> {
        let mut all = Vec::new();
        let mut at = i;
        let mut end = i;
        while let Some((value, j)) = self.value(at).into_iter().next() {
            all.push(value);
            end = j;
            if self.at(j) != Some(',') {
                break;
            }
            at = self.ws(j + 1).unwrap_or(j + 1);
        }
        if all.is_empty() {
            Vec::new()
        } else {
            vec![(all, end)]
        }
    }

    pub(crate) fn list(&self, i: usize) -> Reads<List> {
        let mut out: Reads<List> = self
            .values(i)
            .into_iter()
            .map(|(v, j)| (List::Values(v), j))
            .collect();
        out.extend(
            self.path(i, Side::Right)
                .into_iter()
                .map(|(p, j)| (List::Path(p), j)),
        );
        out
    }

    fn key(&self, i: usize) -> Option<(String, usize)> {
        self.bare_key(i).or_else(|| self.dq(i))
    }

    fn dollar_name(&self, i: usize) -> Option<(String, usize)> {
        let j = self.lit(i, "$")?;
        let first = self.at(j)?;
        if !(first.is_ascii_alphabetic() || first == '_') {
            return None;
        }
        let mut end = j + 1;
        while self
            .at(end)
            .is_some_and(|ch| ch.is_ascii_alphanumeric() || ch == '_')
        {
            end += 1;
        }
        Some((self.c[i..end].iter().collect(), end))
    }

    fn reference(&self, i: usize) -> Option<(Reference, usize)> {
        if let Some((name, end)) = self.dollar_name(i) {
            let keyed = self
                .lit(end, ".")
                .and_then(|j| self.key(j))
                .map(|(key, after)| (Some(key), after));
            return match (name.as_str(), keyed) {
                ("$params", Some((Some(key), after))) => Some((Reference::Params(key), after)),
                ("$input", Some((Some(key), after))) => Some((Reference::Input(key), after)),
                ("$params" | "$input", _) => None,
                (_, Some((key, after))) => Some((Reference::Unknown { name, key }, after)),
                (_, None) => Some((Reference::Unknown { name, key: None }, end)),
            };
        }
        let (name, end) = self.bare_key(i)?;
        Some((Reference::Name(name), end))
    }

    fn step(&self, i: usize) -> Option<(Step, usize)> {
        match self.at(i)? {
            '.' => {
                let (key, end) = self.key(i + 1)?;
                Some((Step::Key(key), end))
            }
            ' ' => {
                let j = self.ws(i)?;
                let j = self.lead(j, "named by")?;
                let (reference, end) = self.reference(j)?;
                Some((Step::NamedBy(reference), end))
            }
            '[' => {
                let j = i + 1;
                if let Some((reference, k)) = self.reference(j) {
                    return self.lit(k, "]").map(|end| (Step::Brackets(reference), end));
                }
                if let Some((key, k)) = self.dq(j) {
                    return self.lit(k, "]").map(|end| (Step::BracketKey(key), end));
                }
                let k = self.int(j)?;
                let digits: String = self.c[j..k].iter().collect();
                self.lit(k, "]").map(|end| (Step::Index(digits), end))
            }
            _ => None,
        }
    }

    fn steps(&self, i: usize) -> Reads<Vec<Step>> {
        let mut all = Vec::new();
        let mut ends = vec![i];
        let mut at = i;
        while let Some((step, j)) = self.step(at) {
            all.push(step);
            ends.push(j);
            at = j;
        }
        let whole = all.len();
        let mut out: Reads<Vec<Step>> = Vec::new();
        for n in (0..whole).rev() {
            if self
                .ws(ends[n])
                .and_then(|m| self.lead(m, "named by each of"))
                .is_some()
            {
                out.push((all[..n].to_vec(), ends[n]));
            }
        }
        out.insert(0, (all, ends[whole]));
        out
    }

    fn start(&self, i: usize, side: Side) -> Option<(Start, usize)> {
        match self.at(i)? {
            '$' => {
                let (name, end) = self.dollar_name(i)?;
                let start = match name.as_str() {
                    "$params" => Start::Params,
                    "$input" => Start::Input,
                    _ => Start::Unknown(name),
                };
                Some((start, end))
            }
            '.' => {
                let (key, end) = self.key(i + 1)?;
                Some((Start::Field { key, dot: true }, end))
            }
            '"' if matches!(side, Side::Left) => {
                let (key, end) = self.dq(i)?;
                if is_word(&key) && !self.lenient {
                    Some((Start::Quoted(key), end))
                } else {
                    let dot = is_word(&key);
                    Some((Start::Field { key, dot }, end))
                }
            }
            _ => {
                let (key, end) = self.bare_key(i)?;
                if key == "it" {
                    if self.lenient {
                        Some((Start::It, end))
                    } else {
                        None
                    }
                } else if is_word(&key) && !self.lenient {
                    None
                } else {
                    Some((Start::Field { key, dot: false }, end))
                }
            }
        }
    }

    fn plain_path(&self, i: usize, side: Side) -> Reads<Path> {
        let Some((start, j)) = self.start(i, side) else {
            return Vec::new();
        };
        self.steps(j)
            .into_iter()
            .map(|(steps, end)| {
                (
                    Path {
                        position: None,
                        start: start.clone(),
                        steps,
                    },
                    end,
                )
            })
            .collect()
    }

    fn positions(&self, i: usize) -> Reads<Position> {
        let mut out = Vec::new();
        if let Some(j) = self.lit(i, "first") {
            out.push((Position::First, j));
        }
        if let Some(j) = self.lit(i, "last") {
            out.push((Position::Last, j));
        }
        if let Some(j) = self.lead(i, "item")
            && matches!(self.at(j), Some('1'..='9'))
        {
            let k = self.digits(j);
            let number: String = self.c[j..k].iter().collect();
            if let Some(end) = self
                .ws(k)
                .and_then(|m| self.lead(m, "from"))
                .and_then(|m| self.lit(m, "last"))
            {
                out.push((
                    Position::Item {
                        number: number.clone(),
                        from_last: true,
                    },
                    end,
                ));
            }
            out.push((
                Position::Item {
                    number,
                    from_last: false,
                },
                k,
            ));
        }
        out
    }

    fn after_position(&self, i: usize) -> Vec<(Position, usize)> {
        let mut out = Vec::new();
        for (position, j) in self.positions(i) {
            if let Some(k) = self.ws(j).and_then(|m| self.lead(m, "of")) {
                out.push((position, k));
            }
        }
        out
    }

    pub(crate) fn path(&self, i: usize, side: Side) -> Reads<Path> {
        let mut out = Vec::new();
        for (position, k) in self.after_position(i) {
            for (mut path, end) in self.plain_path(k, side) {
                path.position = Some(position.clone());
                out.push((path, end));
            }
        }
        out.extend(self.plain_path(i, side));
        out
    }

    fn it_whole(&self, i: usize) -> Option<usize> {
        let j = self.lit(i, "it")?;
        if self.at(j).is_some_and(is_key_char) {
            None
        } else {
            Some(j)
        }
    }

    pub(crate) fn it_path(&self, i: usize) -> Reads<Path> {
        if self.lenient {
            return Vec::new();
        }
        let it = |position: Option<Position>, j: usize| {
            self.it_whole(j).map(|end| {
                (
                    Path {
                        position,
                        start: Start::It,
                        steps: Vec::new(),
                    },
                    end,
                )
            })
        };
        let mut out = Vec::new();
        out.extend(it(None, i));
        for (position, k) in self.after_position(i) {
            out.extend(it(Some(position), k));
        }
        out
    }

    pub(crate) fn path_or_it(&self, i: usize) -> Reads<Path> {
        let mut out = self.it_path(i);
        out.extend(self.path(i, Side::Left));
        out
    }

    fn derived(&self, i: usize) -> Reads<Derived> {
        let mut out = Vec::new();
        for (spelling, kind) in [
            ("count of", DerivedKind::Count),
            ("sum of", DerivedKind::Sum),
        ] {
            if let Some(j) = self.lead(i, spelling) {
                for (path, end) in self.path_or_it(j) {
                    out.push((
                        Derived {
                            kind,
                            path,
                            whose: Vec::new(),
                        },
                        end,
                    ));
                }
            }
        }
        out
    }

    fn elapsed(&self, i: usize) -> Reads<Elapsed> {
        let mut out = Vec::new();
        for (spelling, unit) in [
            ("seconds elapsed from", Unit::Seconds),
            ("minutes elapsed from", Unit::Minutes),
            ("hours elapsed from", Unit::Hours),
            ("days elapsed from", Unit::Days),
            ("weeks elapsed from", Unit::Weeks),
        ] {
            let Some(j) = self.lead(i, spelling) else {
                continue;
            };
            for (from, k) in self.path(j, Side::Left) {
                let Some(m) = self.ws(k).and_then(|m| self.lead(m, "to")) else {
                    continue;
                };
                for (to, end) in self.path(m, Side::Left) {
                    out.push((
                        Elapsed {
                            unit,
                            from: from.clone(),
                            to,
                        },
                        end,
                    ));
                }
            }
        }
        out
    }

    fn term(&self, i: usize) -> Reads<Term> {
        let mut out: Reads<Term> = self
            .derived(i)
            .into_iter()
            .map(|(d, j)| (Term::Derived(d), j))
            .collect();
        out.extend(
            self.elapsed(i)
                .into_iter()
                .map(|(e, j)| (Term::Elapsed(e), j)),
        );
        out.extend(
            self.path(i, Side::Right)
                .into_iter()
                .map(|(p, j)| (Term::Path(p), j)),
        );
        out.extend(self.number(i).map(|(n, j)| (Term::Number(n), j)));
        out
    }

    fn plus_tail(&self, i: usize) -> Reads<Vec<Term>> {
        let mut done = Vec::new();
        let mut pending: Vec<(Vec<Term>, usize)> = vec![(Vec::new(), i)];
        while let Some((terms, at)) = pending.pop() {
            let next = self
                .ws(at)
                .and_then(|m| self.lead(m, "plus"))
                .map(|j| self.term(j))
                .unwrap_or_default();
            if next.is_empty() {
                done.push((terms, at));
                continue;
            }
            let mut terms = Some(terms);
            let last = next.len() - 1;
            let mut children = Vec::with_capacity(next.len());
            for (n, (term, k)) in next.into_iter().enumerate() {
                let mut grown = if n == last {
                    terms.take().unwrap_or_default()
                } else {
                    terms.clone().unwrap_or_default()
                };
                grown.push(term);
                children.push((grown, k));
            }
            pending.extend(children.into_iter().rev());
        }
        done
    }

    pub(crate) fn operand(&self, i: usize) -> Reads<Operand> {
        let mut out = Vec::new();
        if let Some((number, j)) = self.number(i) {
            for (rest, end) in self.plus_tail(j) {
                if !rest.is_empty() {
                    let mut all = vec![Term::Number(number.clone())];
                    all.extend(rest);
                    out.push((Operand::Field(all), end));
                }
            }
        }
        out.extend(
            self.value(i)
                .into_iter()
                .map(|(v, j)| (Operand::Value(v), j)),
        );
        let mut heads: Reads<Term> = self
            .derived(i)
            .into_iter()
            .map(|(d, j)| (Term::Derived(d), j))
            .collect();
        heads.extend(
            self.elapsed(i)
                .into_iter()
                .map(|(e, j)| (Term::Elapsed(e), j)),
        );
        heads.extend(
            self.path(i, Side::Right)
                .into_iter()
                .map(|(p, j)| (Term::Path(p), j)),
        );
        for (head, j) in heads {
            for (rest, end) in self.plus_tail(j) {
                let mut all = vec![head.clone()];
                all.extend(rest);
                out.push((Operand::Field(all), end));
            }
        }
        out
    }

    fn list_phrases(
        &self,
        out: &mut Reads<Phrase>,
        i: usize,
        spellings: &[&str],
        make: impl Fn(List) -> Phrase,
    ) {
        for spelling in spellings {
            if let Some(j) = self.lead(i, spelling) {
                for (list, end) in self.list(j) {
                    out.push((make(list), end));
                }
            }
        }
    }

    fn operand_phrases(
        &self,
        out: &mut Reads<Phrase>,
        i: usize,
        spellings: &[&str],
        make: impl Fn(Operand) -> Phrase,
    ) {
        for spelling in spellings {
            if let Some(j) = self.lead(i, spelling) {
                for (operand, end) in self.operand(j) {
                    out.push((make(operand), end));
                }
            }
        }
    }

    fn bare_phrases(&self, out: &mut Reads<Phrase>, i: usize, spelling: &str, phrase: Phrase) {
        if let Some(j) = self.words(i, spelling) {
            out.push((phrase, j));
        }
    }

    fn type_phrases(&self, out: &mut Reads<Phrase>, i: usize) {
        for spelling in ["is an", "is a"] {
            let Some(j) = self.lead(i, spelling) else {
                continue;
            };
            for (word, kind) in [
                ("list", Type::List),
                ("string", Type::String),
                ("number", Type::Number),
                ("boolean", Type::Boolean),
                ("object", Type::Object),
            ] {
                if let Some(end) = self.lit(j, word) {
                    out.push((Phrase::Type(kind), end));
                }
            }
        }
    }

    fn between_phrases(&self, out: &mut Reads<Phrase>, i: usize) {
        let Some(j) = self.lead(i, "is between") else {
            return;
        };
        let Some((min, k)) = self.number(j) else {
            return;
        };
        let Some(m) = self.ws(k).and_then(|m| self.lead(m, "and")) else {
            return;
        };
        if let Some((max, end)) = self.number(m) {
            out.push((Phrase::Between { min, max }, end));
        }
    }

    fn is_phrases(&self, out: &mut Reads<Phrase>, i: usize) {
        for spelling in ["is not", "does not equal"] {
            if let Some(j) = self.lead(i, spelling) {
                for (operand, end) in self.operand(j) {
                    out.push((
                        Phrase::Is {
                            not: true,
                            operand,
                            within: None,
                        },
                        end,
                    ));
                }
            }
        }
        for spelling in ["is equal to", "equals", "is"] {
            let Some(j) = self.lead(i, spelling) else {
                continue;
            };
            for (operand, end) in self.operand(j) {
                if let Some(k) = self.ws(end).and_then(|m| self.lead(m, "within"))
                    && let Some((within, stop)) = self.number(k)
                {
                    out.push((
                        Phrase::Is {
                            not: false,
                            operand: operand.clone(),
                            within: Some(within),
                        },
                        stop,
                    ));
                }
                out.push((
                    Phrase::Is {
                        not: false,
                        operand,
                        within: None,
                    },
                    end,
                ));
            }
        }
    }

    pub(crate) fn phrase(&self, i: usize, compare_only: bool) -> Reads<Phrase> {
        let mut out = Vec::new();
        if !compare_only {
            self.list_phrases(&mut out, i, &["is not one of", "is not in"], |list| {
                Phrase::OneOf { not: true, list }
            });
            self.list_phrases(&mut out, i, &["is one of", "is in"], |list| Phrase::OneOf {
                not: false,
                list,
            });
            self.bare_phrases(&mut out, i, "is a non-empty string", Phrase::NonEmptyString);
            self.type_phrases(&mut out, i);
            self.bare_phrases(&mut out, i, "is not empty", Phrase::Empty { not: true });
            self.bare_phrases(&mut out, i, "is empty", Phrase::Empty { not: false });
            self.bare_phrases(&mut out, i, "does not exist", Phrase::Exists { not: true });
            self.bare_phrases(&mut out, i, "exists", Phrase::Exists { not: false });
            self.list_phrases(&mut out, i, &["contains all of"], Phrase::ContainsAll);
            self.list_phrases(&mut out, i, &["contains none of"], Phrase::ContainsNone);
            self.operand_phrases(&mut out, i, &["does not contain"], |operand| {
                Phrase::Contains { not: true, operand }
            });
            self.operand_phrases(&mut out, i, &["contains"], |operand| Phrase::Contains {
                not: false,
                operand,
            });
            self.list_phrases(&mut out, i, &["does not match"], |list| Phrase::Matches {
                not: true,
                list,
            });
            self.list_phrases(&mut out, i, &["matches"], |list| Phrase::Matches {
                not: false,
                list,
            });
            self.operand_phrases(&mut out, i, &["starts with"], Phrase::StartsWith);
            self.operand_phrases(&mut out, i, &["ends with"], Phrase::EndsWith);
            self.operand_phrases(&mut out, i, &["is alphabetically before"], |operand| {
                Phrase::Alphabetically {
                    after: false,
                    operand,
                }
            });
            self.operand_phrases(&mut out, i, &["is alphabetically after"], |operand| {
                Phrase::Alphabetically {
                    after: true,
                    operand,
                }
            });
        }
        for (spelling, order) in [
            ("is at least", Order::AtLeast),
            ("is at most", Order::AtMost),
            ("is more than", Order::MoreThan),
            ("is less than", Order::LessThan),
        ] {
            self.operand_phrases(&mut out, i, &[spelling], |operand| Phrase::Order {
                order,
                operand,
            });
        }
        self.between_phrases(&mut out, i);
        if !compare_only {
            for (spelling, time) in [
                ("is on or after", TimeOrder::OnOrAfter),
                ("is on or before", TimeOrder::OnOrBefore),
                ("is before", TimeOrder::Before),
                ("is after", TimeOrder::After),
            ] {
                self.operand_phrases(&mut out, i, &[spelling], |operand| Phrase::Time {
                    time,
                    operand,
                });
            }
        }
        self.is_phrases(&mut out, i);
        out
    }

    pub(crate) fn condition(&self, i: usize) -> Reads<Condition> {
        let mut out = Vec::new();
        for (path, j) in self.path_or_it(i) {
            if let Some(k) = self.ws(j) {
                for (phrase, end) in self.phrase(k, false) {
                    out.push((
                        Condition {
                            left: Left::Path(path.clone()),
                            phrase,
                        },
                        end,
                    ));
                }
            }
        }
        let mut lefts: Reads<Left> = self
            .derived(i)
            .into_iter()
            .map(|(d, j)| (Left::Derived(d), j))
            .collect();
        lefts.extend(
            self.elapsed(i)
                .into_iter()
                .map(|(e, j)| (Left::Elapsed(e), j)),
        );
        for (left, j) in lefts {
            if let Some(k) = self.ws(j) {
                for (phrase, end) in self.phrase(k, !self.lenient) {
                    out.push((
                        Condition {
                            left: left.clone(),
                            phrase,
                        },
                        end,
                    ));
                }
            }
        }
        out
    }

    pub(crate) fn quantifier(&self, i: usize) -> Option<(Quantifier, usize)> {
        if let Some(j) = self.lit(i, "every") {
            Some((Quantifier::Every, j))
        } else {
            self.lit(i, "some").map(|j| (Quantifier::Some, j))
        }
    }

    pub(crate) fn if_any(&self, i: usize) -> Option<usize> {
        let j = self.lit(i, ",")?;
        let j = self.ws(j)?;
        let j = self.lead(j, "if")?;
        self.lit(j, "any,")
    }

    fn read_from_condition(&self, i: usize) -> Reads<FromCondition> {
        let mut out = Vec::new();
        if let Some((quantifier, j)) = self.quantifier(i)
            && let Some(k) = self.ws(j)
        {
            for (path, m) in self.path_or_it(k) {
                let mut ends = Vec::new();
                if let Some(n) = self.if_any(m) {
                    ends.push((true, n));
                }
                ends.push((false, m));
                for (if_any, n) in ends {
                    if let Some(p) = self.ws(n) {
                        for (phrase, end) in self.phrase(p, false) {
                            out.push((
                                FromCondition::Quantified {
                                    quantifier,
                                    path: path.clone(),
                                    if_any,
                                    phrase,
                                },
                                end,
                            ));
                        }
                    }
                }
            }
        }
        out.extend(
            self.condition(i)
                .into_iter()
                .map(|(c, j)| (FromCondition::Condition(c), j)),
        );
        out
    }

    fn read_from_conditions(&self, i: usize) -> Reads<Chain<FromCondition>> {
        chain_reads(
            i,
            usize::MAX,
            |at| heads_at(&self.memo, at, || self.read_from_condition(at)),
            |end| self.ws(end).and_then(|m| self.lead(m, "and")),
        )
    }

    pub(crate) fn read_from_core(&self, i: usize, every: bool) -> Reads<FromRead> {
        let mut out = Vec::new();
        for (path, j) in self.path(i, Side::Left) {
            let mut eaches: Reads<Option<Path>> = Vec::new();
            if let Some(k) = self.ws(j).and_then(|m| self.lead(m, "named by each of")) {
                for (each, end) in self.path(k, Side::Right) {
                    eaches.push((Some(each), end));
                }
            }
            eaches.push((None, j));
            for (each, j2) in eaches {
                if let Some(k) = self.ws(j2).and_then(|m| self.lead(m, "whose")) {
                    for (whose, end) in self.read_from_conditions(k) {
                        out.push((
                            FromRead {
                                every,
                                path: path.clone(),
                                named_by_each_of: each.clone(),
                                whose,
                            },
                            end,
                        ));
                    }
                }
                out.push((
                    FromRead {
                        every,
                        path: path.clone(),
                        named_by_each_of: each,
                        whose: None,
                    },
                    j2,
                ));
            }
        }
        out
    }

    pub(crate) fn read_from_line(&self, i: usize) -> Reads<FromRead> {
        let mut out = Vec::new();
        if let Some(j) = self.lead(i, "every") {
            out.extend(self.read_from_core(j, true));
        }
        out.extend(self.read_from_core(i, false));
        out
    }

    pub(crate) fn is_whole_string(&self) -> bool {
        let end = match self.at(0) {
            Some('"') => self.dq(0).map(|(_, j)| j),
            Some('\'') => self.sq(0).map(|(_, j)| j),
            _ => None,
        };
        end == Some(self.len())
    }

    pub(crate) fn whole<T>(&self, reads: Reads<T>) -> Option<T> {
        reads
            .into_iter()
            .find(|(_, end)| *end == self.len())
            .map(|(value, _)| value)
    }
}

pub(crate) fn trim(line: &str) -> &str {
    line.trim()
}
