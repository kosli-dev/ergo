use crate::lower::{self, PartDef, Scope};
use crate::name;
use crate::ops::Check;
use crate::path::{self, Start, Step};
use crate::policy::{
    Has, LISTED_LAST, Policy, Problems, Requirement, SubjectDef, SubjectName, Subjects, Text,
    add_problem, field_name, merge_problems,
};
use ergo_policy_sentences as s;
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, BTreeSet};

pub const INVALID_FROM: &str = "<invalid from>";
pub const NARROWING_A_CHILD_PROBLEM: &str =
    "can't build on a subject read from another subject yet";

pub const INVALID_IDENTIFIED_BY: &str = "<invalid identified_by>";
pub const KEYED_ID_PROBLEM: &str = "not allowed with named by each of: the key is the id";
pub const EACH_START_PROBLEM: &str = "named by each of takes a list from $params or $input, so it can't start at a field or a subject";
const MAX_WALK_STEPS: usize = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Relation {
    Root,
    Narrows(String),
    Child(String),
}

#[derive(Debug, Clone)]
pub struct PartRead {
    pub from_text: String,
    pub id_text: Option<String>,
    pub def: Option<PartDef>,
}

#[derive(Debug, Clone)]
pub struct Filter {
    pub text: String,
    pub check: Check,
}

#[derive(Debug, Clone)]
pub enum Source {
    Root {
        path: path::Path,
        every: bool,
        distinct: bool,
        each_of: Option<path::Path>,
        names: usize,
        every_text: String,
    },
    Child {
        path: path::Path,
        every: bool,
        distinct: bool,
        each_of: Option<path::Path>,
        names: usize,
        every_text: String,
    },
}

#[derive(Debug, Clone)]
pub struct Lowered {
    pub source: Source,
    pub filters: Vec<Filter>,
    pub id: Option<Vec<Step>>,
    pub from_text: String,
}

impl Info {
    fn only_narrows_a_child(&self, name: &str) -> bool {
        !self.unsupported
            && self
                .problems
                .get(&field_name(&["subjects", name, "from"]))
                .is_some_and(|texts| texts.iter().all(|t| t == NARROWING_A_CHILD_PROBLEM))
    }
}

#[derive(Debug, Clone)]
pub struct Info {
    pub relation: Relation,
    pub problems: Problems,
    pub lowered: Option<Lowered>,
    pub from_text: Option<String>,
    pub scope: Scope,
    pub declarers: BTreeMap<String, BTreeSet<String>>,
    pub own_part_names: BTreeSet<String>,
    pub unsupported: bool,
    pub from_read: bool,
    pub own_filters: Vec<String>,
    pub filters_known: bool,
    pub entry: Value,
}

#[derive(Debug, Clone)]
pub struct Reading {
    pub infos: BTreeMap<String, Info>,
    pub names: BTreeSet<String>,
}

enum FromState {
    Parsed(s::FromLine),
    Errors(Vec<String>),
    NotText,
}

struct Raw<'a> {
    def: &'a SubjectDef,
    from: FromState,
    own: BTreeMap<String, PartRead>,
    own_problems: Problems,
    relation: Relation,
}

struct Own {
    source: Option<Source>,
    filters: Vec<Filter>,
    id: Option<Vec<Step>>,
    id_text: Option<String>,
    from_text: String,
}

fn looks_like_part_alias(alias: &str) -> bool {
    let mut bytes = alias.bytes();
    match bytes.next() {
        Some(b) if b.is_ascii_alphabetic() || b == b'_' => {}
        _ => return false,
    }
    bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn bad_alias(alias: &str) -> bool {
    !looks_like_part_alias(alias) || name::is_word(alias) || alias == "params" || alias == "input"
}

fn read_keyed(text: &str, what: &str) -> Result<(Vec<Step>, String), Vec<String>> {
    match s::parse_from(text) {
        Err(errors) => Err(errors.into_iter().map(|e| e.message).collect()),
        Ok(line) => {
            let mut problems = Vec::new();
            if line.every || line.named_by_each_of.is_some() || !line.whose.is_empty() {
                problems.push(
                    "a part is a path: whose and named by each of can't go in it".to_string(),
                );
            }
            match lower::part_steps(&line.path) {
                Ok(steps) if problems.is_empty() => {
                    let text = name::name(&path::Path {
                        start: Start::Subject,
                        steps: steps.clone(),
                    });
                    Ok((steps, text))
                }
                Ok(_) => Err(problems),
                Err(found) => {
                    problems.extend(found);
                    Err(problems)
                }
            }
        }
    }
    .map_err(|problems| {
        let mut sorted: Vec<String> = problems
            .into_iter()
            .map(|p| format!("{what}: {p}"))
            .collect();
        sorted.sort();
        sorted.dedup();
        sorted
    })
}

fn read_part(
    subject: &str,
    alias: &str,
    part: &crate::policy::Part,
    problems: &mut Problems,
) -> PartRead {
    let at = field_name(&["subjects", subject, "has", alias]);
    let mut bad = false;
    let name_problems = crate::policy::written_name_problems(alias);
    if !name_problems.is_empty() {
        for problem in name_problems {
            add_problem(problems, at.clone(), problem);
        }
        bad = true;
    } else if bad_alias(alias) {
        add_problem(problems, at.clone(), "invalid alias");
        bad = true;
    }
    let (from_text, steps) = match &part.from {
        Text::Written(text) => match read_keyed(text, "from") {
            Ok((steps, text)) => (text, Some(steps)),
            Err(found) => {
                for problem in found {
                    add_problem(problems, at.clone(), problem);
                }
                bad = true;
                (INVALID_FROM.to_string(), None)
            }
        },
        Text::Missing | Text::Invalid => {
            bad = true;
            (INVALID_FROM.to_string(), None)
        }
    };
    let (id_text, id_steps, id_bad) = match &part.identified_by {
        Text::Missing => (None, None, false),
        Text::Invalid => (Some(INVALID_IDENTIFIED_BY.to_string()), None, true),
        Text::Written(text) => match read_keyed(text, "identified_by") {
            Ok((steps, text)) => (Some(text), Some(steps), false),
            Err(found) => {
                for problem in found {
                    add_problem(problems, at.clone(), problem);
                }
                (Some(INVALID_IDENTIFIED_BY.to_string()), None, true)
            }
        },
    };
    let def = match (bad || id_bad, steps) {
        (false, Some(steps)) => Some(PartDef {
            steps,
            id: id_steps,
        }),
        _ => None,
    };
    PartRead {
        from_text,
        id_text,
        def,
    }
}

fn reach(links: &BTreeMap<String, Vec<String>>, start: &[String]) -> BTreeSet<String> {
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let mut todo: Vec<String> = start.to_vec();
    while let Some(next) = todo.pop() {
        if seen.insert(next.clone())
            && let Some(more) = links.get(&next)
        {
            todo.extend(more.iter().cloned());
        }
    }
    seen
}

fn names_a_subject<'a>(
    line: &'a s::FromLine,
    own_name: &str,
    names: &BTreeSet<String>,
) -> Option<&'a str> {
    match &line.path.start {
        s::Start::Field { key, dot: false } | s::Start::Quoted(key)
            if key != own_name && names.contains(key) =>
        {
            Some(key.as_str())
        }
        _ => None,
    }
}

fn relation_of(line: &s::FromLine, own_name: &str, names: &BTreeSet<String>) -> Relation {
    match names_a_subject(line, own_name, names) {
        Some(parent) if line.named_by_each_of.is_some() => Relation::Child(parent.to_string()),
        Some(parent) => {
            if line.path.steps.is_empty() && line.path.position.is_none() {
                Relation::Narrows(parent.to_string())
            } else {
                Relation::Child(parent.to_string())
            }
        }
        _ => Relation::Root,
    }
}

fn keeps_dot(line: &s::FromLine, own_name: &str, names: &BTreeSet<String>) -> bool {
    matches!(
        &line.path.start,
        s::Start::Field { key, dot: true } if key != own_name && names.contains(key)
    )
}

fn with_kept_dot(text: String, every: bool) -> String {
    let mut at = if every { "every ".len() } else { 0 };
    let rest = &text[at..];
    let positioned = rest.starts_with("first of ")
        || rest.starts_with("last of ")
        || (rest.starts_with("item ") && rest.contains(" of "));
    if positioned && let Some(of) = rest.find(" of ") {
        at += of + " of ".len();
    }
    if text[at..].starts_with('.') {
        text
    } else {
        format!("{}.{}", &text[..at], &text[at..])
    }
}

fn synthesized(name: &str) -> s::FromLine {
    s::FromLine {
        every: false,
        distinct: false,
        path: s::Path {
            position: None,
            start: s::Start::Field {
                key: name.to_string(),
                dot: name::is_word(name),
            },
            steps: Vec::new(),
        },
        named_by_each_of: None,
        whose: Vec::new(),
    }
}

fn members_of(name: &str, raw: &BTreeMap<String, Raw>) -> BTreeSet<String> {
    let mut seen = BTreeSet::new();
    let mut todo = vec![name.to_string()];
    while let Some(next) = todo.pop() {
        if seen.insert(next.clone())
            && let Some(Raw {
                relation: Relation::Narrows(parent),
                ..
            }) = raw.get(&next)
        {
            todo.push(parent.clone());
        }
    }
    seen
}

fn child_parent(name: &str, raw: &BTreeMap<String, Raw>) -> Option<String> {
    match raw.get(name).map(|r| &r.relation) {
        Some(Relation::Child(parent)) => Some(parent.clone()),
        _ => None,
    }
}

fn parent_is_self_compared(name: &str, raw: &BTreeMap<String, Raw>) -> bool {
    let Some(parent) = child_parent(name, raw) else {
        return false;
    };
    let above = ancestors_of(&parent, raw);
    let above: Vec<&str> = above.iter().map(String::as_str).collect();
    matches!(
        raw.get(&parent).map(|r| &r.from),
        Some(FromState::Parsed(line))
            if s::from_problems(line).is_empty() && !s::from_self_problems(line, &above).is_empty()
    )
}

fn blocked_ancestors(name: &str, raw: &BTreeMap<String, Raw>) -> Vec<String> {
    let Some(parent) = child_parent(name, raw) else {
        return Vec::new();
    };
    let broken = match raw.get(&parent).map(|r| &r.from) {
        Some(FromState::Parsed(line)) if s::from_problems(line).is_empty() => {
            let above = ancestors_of(&parent, raw);
            let above: Vec<&str> = above.iter().map(String::as_str).collect();
            !s::from_self_problems(line, &above).is_empty()
                || lower::keyed_steps(&line.path).is_err()
                || line
                    .named_by_each_of
                    .as_ref()
                    .is_some_and(|each| lower::keyed_steps(each).is_err())
        }
        _ => false,
    };
    if broken {
        ancestors_of(&parent, raw)
    } else {
        Vec::new()
    }
}

fn reads_alias(text: &str, ancestor: &str) -> bool {
    text.match_indices(ancestor).any(|(at, _)| {
        let before = text[..at].chars().next_back();
        let after = text[at + ancestor.len()..].chars().next();
        before.is_none_or(|c| !(c.is_alphanumeric() || c == '_' || c == '.' || c == '$'))
            && after.is_none_or(|c| c == '.' || c.is_whitespace())
    })
}

fn right_side_text(condition: &s::FromCondition, scope: &Scope, wide: bool) -> String {
    let s::FromCondition::Condition(condition) = condition else {
        return String::new();
    };
    match lower::lower_condition(condition, scope) {
        Ok(Check::Compare(check)) => format!("{:?}", check.right),
        Ok(Check::CompareTime(check)) => format!("{:?}", check.right),
        Ok(Check::In(check)) => format!("{:?}", check.values),
        Ok(Check::Contains(check)) if wide => format!("{:?}", check.wanted),
        other => format!("{:?}", other.map(|_| ())),
    }
}

fn ancestors_of(name: &str, raw: &BTreeMap<String, Raw>) -> Vec<String> {
    let mut out = Vec::new();
    let mut at = name.to_string();
    while let Some(parent) = child_parent(&at, raw) {
        if out.contains(&parent) || parent == name {
            break;
        }
        out.push(parent.clone());
        at = parent;
    }
    out
}

fn effective_of(
    name: &str,
    raw: &BTreeMap<String, Raw>,
    clashing: &BTreeMap<String, BTreeSet<String>>,
) -> BTreeMap<String, PartRead> {
    let mut members: Vec<String> = members_of(name, raw).into_iter().collect();
    members.sort();
    let mut out: BTreeMap<String, PartRead> = BTreeMap::new();
    for member in members {
        if let Some(found) = raw.get(&member) {
            for (alias, part) in &found.own {
                let mut part = part.clone();
                if clashing
                    .get(&member)
                    .is_some_and(|aliases| aliases.contains(alias))
                {
                    part.def = None;
                }
                out.entry(alias.clone()).or_insert(part);
            }
        }
    }
    out
}

fn subject_defs(policy: &Policy) -> BTreeMap<String, Option<&SubjectDef>> {
    match &policy.subjects {
        Subjects::Map(map) => map
            .iter()
            .map(|(name, subject)| (name.clone(), subject.def.as_ref()))
            .collect(),
        Subjects::NotAnObject => BTreeMap::new(),
    }
}

fn own_part_names(name: &str, raw: &BTreeMap<String, Raw>) -> BTreeSet<String> {
    members_of(name, raw)
        .iter()
        .filter_map(|member| raw.get(member))
        .flat_map(|found| found.own.keys().cloned())
        .collect()
}

fn declarers_of(name: &str, raw: &BTreeMap<String, Raw>) -> BTreeMap<String, BTreeSet<String>> {
    let mut owners: BTreeSet<String> = members_of(name, raw);
    if let Some(parent) = child_parent(name, raw) {
        owners.insert(parent.clone());
        if let Some(grand) = child_parent(&parent, raw) {
            owners.insert(grand);
        }
    }
    let mut declarers = BTreeSet::new();
    for owner in &owners {
        declarers.extend(members_of(owner, raw));
    }
    let mut out: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for declarer in declarers {
        if let Some(found) = raw.get(&declarer) {
            for alias in found.own.keys() {
                out.entry(alias.clone())
                    .or_default()
                    .insert(declarer.clone());
            }
        }
    }
    out
}

fn scope_of(
    name: &str,
    raw: &BTreeMap<String, Raw>,
    effective: &BTreeMap<String, BTreeMap<String, PartRead>>,
) -> Scope {
    let mut scope = Scope::new();
    for (alias, part) in effective.get(name).into_iter().flatten() {
        if let Some(def) = &part.def {
            scope = scope.with_part(alias, def.clone());
        }
    }
    for ancestor in ancestors_of(name, raw) {
        let parts: BTreeMap<String, PartDef> = effective
            .get(&ancestor)
            .into_iter()
            .flatten()
            .filter_map(|(alias, part)| part.def.clone().map(|def| (alias.clone(), def)))
            .collect();
        scope = scope.with_parent(&ancestor, parts);
    }
    scope
}

const DISTINCT_ON_FROM: &str =
    r#"on a from line, distinct goes after every, like "every distinct sbom.components""#;

fn from_problems(
    name: &str,
    line: &s::FromLine,
    raw: &BTreeMap<String, Raw>,
    names: &BTreeSet<String>,
    links: &BTreeMap<String, Vec<String>>,
) -> Vec<String> {
    let mut problems = Vec::new();
    let starts = names_a_subject(line, name, names).map(str::to_string);
    let relation = &raw[name].relation;
    if let Some(parent) = &starts {
        let on_loop = matches!(relation, Relation::Child(_) | Relation::Narrows(_)) && {
            let reached = reach(links, std::slice::from_ref(parent));
            reached.iter().any(|m| {
                let onward = links.get(m).cloned().unwrap_or_default();
                reach(links, &onward).contains(m)
            })
        };
        if on_loop {
            problems.push("leads to a loop".to_string());
        } else if let Relation::Child(parent) = relation
            && let Some(grand) = child_parent(parent, raw)
            && child_parent(&grand, raw).is_some()
        {
            problems.push("a chain of more than three subjects isn't supported yet".to_string());
        }
        if parent.trim().is_empty() {
            problems.push(format!("\"{parent}\" isn't a subject name"));
        }
        if line.every && matches!(relation, Relation::Narrows(_)) {
            let shown = s::print_path(
                &s::Path {
                    position: None,
                    start: line.path.start.clone(),
                    steps: Vec::new(),
                },
                s::Side::Left,
                &[],
            );
            problems.push(format!(
                "{shown} is a subject: write {shown} whose \u{2026} to narrow it, without every"
            ));
        }
    }
    if line.every && line.named_by_each_of.is_some() {
        problems.push("every can't go with named by each of: start the from line at a subject to read its names one subject at a time".to_string());
    }
    if line.distinct && !line.every {
        problems.push(DISTINCT_ON_FROM.to_string());
    }
    if line.path.start == s::Start::Params {
        problems.push("a from reads the input, so it can't start at $params".to_string());
    }
    if let Some(each) = &line.named_by_each_of
        && matches!(each.start, s::Start::Field { .. } | s::Start::Quoted(_))
    {
        problems.push(EACH_START_PROBLEM.to_string());
    }
    match lower::keyed_steps(&line.path) {
        Ok(steps) => {
            let counted =
                steps.len() + usize::from(matches!(line.path.start, s::Start::Field { .. }));
            if line.every && counted > MAX_WALK_STEPS {
                problems.push("every over more than ten steps isn't supported yet".to_string());
            }
        }
        Err(found) => problems.extend(found),
    }
    if let Some(each) = &line.named_by_each_of
        && let Err(found) = lower::keyed_steps(each)
    {
        problems.extend(found);
    }
    problems
}

fn plain_text(steps: &[Step]) -> String {
    if steps.is_empty() {
        "$input".to_string()
    } else {
        name::name(&path::Path {
            start: Start::Subject,
            steps: steps.to_vec(),
        })
    }
}

fn read_id(text: &str) -> Option<(Vec<Step>, String)> {
    let line = s::parse_from(text).ok()?;
    if line.every || line.distinct || line.named_by_each_of.is_some() || !line.whose.is_empty() {
        return None;
    }
    let steps = lower::part_steps(&line.path).ok()?;
    let text = name::name(&path::Path {
        start: Start::Subject,
        steps: steps.clone(),
    });
    Some((steps, text))
}

fn source_of(
    name: &str,
    line: &s::FromLine,
    relation: &Relation,
    scope: &Scope,
) -> Result<Source, Vec<String>> {
    let mut steps = lower::keyed_steps(&line.path)?;
    match relation {
        Relation::Child(parent) => {
            let sentence_path = s::Path {
                position: line.path.position.clone(),
                start: s::Start::Field {
                    key: parent.clone(),
                    dot: false,
                },
                steps: line.path.steps.clone(),
            };
            let path = scope.path(&sentence_path)?;
            let each_of = match &line.named_by_each_of {
                None => None,
                Some(each) => Some(scope.path(each)?),
            };
            let names = 1 + named_steps(&steps);
            Ok(Source::Child {
                path,
                every: line.every,
                distinct: line.every && line.distinct,
                each_of,
                names,
                every_text: every_text(line),
            })
        }
        _ => {
            if let s::Start::Field { key, .. } | s::Start::Quoted(key) = &line.path.start {
                steps.insert(0, Step::Key(key.clone()));
            }
            let names = named_steps(&steps) + usize::from(line.path.start == s::Start::Input);
            let each_of = match &line.named_by_each_of {
                None => None,
                Some(each) => {
                    let mut each_steps = lower::keyed_steps(each)?;
                    let start = match &each.start {
                        s::Start::Params => Start::Params,
                        s::Start::Input => Start::Input,
                        s::Start::Field { key, .. } | s::Start::Quoted(key) => {
                            each_steps.insert(0, Step::Key(key.clone()));
                            Start::Subject
                        }
                        s::Start::That => {
                            return Err(vec![format!("{name}: that can't name keys")]);
                        }
                        s::Start::Unknown(unknown) => {
                            return Err(vec![format!("{}{unknown}", lower::UNKNOWN_NAME)]);
                        }
                    };
                    Some(path::Path {
                        start,
                        steps: each_steps,
                    })
                }
            };
            Ok(Source::Root {
                path: path::Path {
                    start: Start::Input,
                    steps,
                },
                every: line.every,
                distinct: line.every && line.distinct,
                each_of,
                names,
                every_text: every_text(line),
            })
        }
    }
}

fn named_steps(steps: &[Step]) -> usize {
    steps
        .iter()
        .filter(|step| !matches!(step, Step::Index(_)))
        .count()
}

fn every_text(line: &s::FromLine) -> String {
    s::print_from(
        &s::FromLine {
            every: true,
            distinct: false,
            path: line.path.clone(),
            named_by_each_of: None,
            whose: Vec::new(),
        },
        &[],
        &[],
    )
}

fn source_text(source: &Source) -> String {
    match source {
        Source::Root {
            path,
            every,
            distinct,
            ..
        } => {
            let words = match (*every, *distinct) {
                (true, true) => "every distinct ",
                (true, false) => "every ",
                _ => "",
            };
            let from_input = matches!(path.steps.first(), Some(Step::Index(_) | Step::Ref(_)));
            let text = if from_input {
                name::name(&path::Path {
                    start: Start::Input,
                    steps: path.steps.clone(),
                })
            } else {
                plain_text(&path.steps)
            };
            format!("{words}{text}")
        }
        Source::Child {
            path,
            every,
            distinct,
            ..
        } => {
            let words = match (*every, *distinct) {
                (true, true) => "every distinct ",
                (true, false) => "every ",
                _ => "",
            };
            format!("{words}{}", name::name(path))
        }
    }
}

impl Reading {
    pub fn of(policy: &Policy) -> Reading {
        let defs = subject_defs(policy);
        let names: BTreeSet<String> = defs.keys().cloned().collect();
        let mut raw: BTreeMap<String, Raw> = BTreeMap::new();
        for (name, def) in &defs {
            let Some(def) = def else { continue };
            let from = match &def.from {
                Text::Written(text) => match s::parse_from(text) {
                    Ok(line) => FromState::Parsed(line),
                    Err(errors) => {
                        FromState::Errors(errors.into_iter().map(|e| e.message).collect())
                    }
                },
                Text::Missing => FromState::Parsed(synthesized(name)),
                Text::Invalid => FromState::NotText,
            };
            let relation = match &from {
                FromState::Parsed(line) => relation_of(line, name, &names),
                _ => Relation::Root,
            };
            let mut own_problems = Problems::new();
            let mut own = BTreeMap::new();
            if let Has::Parts(parts) = &def.has {
                for (alias, part) in parts {
                    own.insert(
                        alias.clone(),
                        read_part(name, alias, part, &mut own_problems),
                    );
                }
            }
            raw.insert(
                name.clone(),
                Raw {
                    def,
                    from,
                    own,
                    own_problems,
                    relation,
                },
            );
        }
        let mut clashing: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        let mut clash_problems: BTreeMap<String, Problems> = BTreeMap::new();
        for (name, found) in &raw {
            let mut owners: BTreeSet<String> = members_of(name, &raw)
                .into_iter()
                .filter(|m| m != name)
                .collect();
            if let Some(parent) = child_parent(name, &raw) {
                owners.insert(parent.clone());
                if let Some(grand) = child_parent(&parent, &raw) {
                    owners.insert(grand);
                }
            }
            let at = |alias: &str| field_name(&["subjects", name, "has", alias]);
            let mut extra = Problems::new();
            for alias in found.own.keys() {
                if names.contains(alias) {
                    add_problem(
                        &mut extra,
                        at(alias),
                        format!("{alias} can't be an alias: it's a subject's name"),
                    );
                    clashing
                        .entry(name.clone())
                        .or_default()
                        .insert(alias.clone());
                }
                let mut declarers = BTreeSet::new();
                for owner in &owners {
                    declarers.extend(members_of(owner, &raw));
                }
                for declarer in declarers {
                    if raw
                        .get(&declarer)
                        .is_some_and(|r| r.own.contains_key(alias))
                    {
                        add_problem(
                            &mut extra,
                            at(alias),
                            format!(
                                "{alias} can't be an alias: it's a part of {}",
                                name::key_text(&declarer)
                            ),
                        );
                        clashing
                            .entry(name.clone())
                            .or_default()
                            .insert(alias.clone());
                    }
                }
            }
            clash_problems.insert(name.clone(), extra);
        }
        for (name, extra) in &clash_problems {
            if let Some(entry) = raw.get_mut(name) {
                merge_problems(&mut entry.own_problems, extra);
            }
        }
        let effective: BTreeMap<String, BTreeMap<String, PartRead>> = raw
            .keys()
            .map(|name| (name.clone(), effective_of(name, &raw, &clashing)))
            .collect();
        let mut links: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for (name, found) in &raw {
            let mut out = Vec::new();
            match &found.relation {
                Relation::Narrows(parent) | Relation::Child(parent) => out.push(parent.clone()),
                Relation::Root => {}
            }
            links.insert(name.clone(), out);
        }
        let mut owns: BTreeMap<String, Own> = BTreeMap::new();
        let mut unsupported: BTreeSet<String> = BTreeSet::new();
        let mut narrowing_a_child: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut chain_problems: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut problems_by_subject: BTreeMap<String, Problems> = BTreeMap::new();
        for (name, found) in &raw {
            let mut problems = found.own_problems.clone();
            let from_at = field_name(&["subjects", name, "from"]);
            let id_at = field_name(&["subjects", name, "identified_by"]);
            let mut own = None;
            match &found.from {
                FromState::Errors(errors) => {
                    for error in errors {
                        add_problem(&mut problems, from_at.clone(), error.clone());
                    }
                }
                FromState::NotText => {}
                FromState::Parsed(line) => {
                    let mut found_problems = from_problems(name, line, &raw, &names, &links);
                    let scope = scope_of(name, &raw, &effective);
                    let mut aliases = scope.aliases();
                    aliases.extend(own_part_names(name, &raw));
                    let alias_refs: Vec<&str> = aliases.iter().map(String::as_str).collect();
                    let mut printed_aliases = alias_refs.clone();
                    printed_aliases.push(name.as_str());
                    let parent_names = scope.parent_names();
                    let parent_refs: Vec<&str> = parent_names.iter().map(String::as_str).collect();
                    let syntax_problems = s::from_problems(line);
                    let reads = syntax_problems.is_empty();
                    found_problems.retain(|found| {
                        found.strip_prefix("unknown alias ").is_none_or(|name| {
                            !syntax_problems.contains(&format!("{name} can't be an alias"))
                        })
                    });
                    found_problems.extend(syntax_problems);
                    if reads {
                        found_problems.extend(s::from_self_problems(line, &alias_refs));
                    }
                    let mut filters = Vec::new();
                    let blocked = blocked_ancestors(name, &raw);
                    for condition in line.whose.iter().filter(|_| reads) {
                        for ancestor in &blocked {
                            let reduced = scope.clone().without_parent(ancestor);
                            let wide = parent_is_self_compared(name, &raw);
                            if reads_alias(
                                &s::print_from_condition(condition, &printed_aliases, &parent_refs),
                                ancestor,
                            ) && right_side_text(condition, &reduced, wide)
                                != right_side_text(condition, &scope, wide)
                            {
                                chain_problems
                                    .entry(name.clone())
                                    .or_default()
                                    .push(format!("unknown alias ${ancestor}"));
                            }
                        }
                        let mut text = s::print_from_condition(
                            &lower::quoted_name_dotted_condition(condition, name),
                            &printed_aliases,
                            &parent_refs,
                        );
                        match condition {
                            s::FromCondition::Condition(condition) => {
                                found_problems.extend(lower::condition_elapsed_problems(condition));
                                let lowered = if condition.that {
                                    let named = s::Condition {
                                        left: s::Left::Path(s::Path {
                                            position: None,
                                            start: s::Start::Field {
                                                key: name.clone(),
                                                dot: false,
                                            },
                                            steps: Vec::new(),
                                        }),
                                        ..condition.clone()
                                    };
                                    text = format!("{} {text}", crate::name::parent_key_text(name));
                                    lower::lower_condition(
                                        &named,
                                        &scope.clone().with_part(
                                            name,
                                            lower::PartDef {
                                                steps: Vec::new(),
                                                id: None,
                                            },
                                        ),
                                    )
                                } else {
                                    lower::lower_condition(
                                        condition,
                                        &scope.clone().with_subject(name).for_from_line(),
                                    )
                                };
                                match lowered {
                                    Ok(check) => filters.push(Filter { text, check }),
                                    Err(found) => {
                                        found_problems.extend(lower::in_from_line(found));
                                    }
                                }
                            }
                            s::FromCondition::Quantified {
                                quantifier,
                                path,
                                distinct,
                                if_any,
                                phrase,
                            } => match lower::lower_quantified(
                                *quantifier,
                                &lower::name_dotted(path, name),
                                *distinct,
                                &[],
                                *if_any,
                                phrase,
                                &scope.clone().with_subject(name).for_from_line(),
                            ) {
                                Ok(check) => filters.push(Filter { text, check }),
                                Err(found) => found_problems.extend(lower::in_from_line(found)),
                            },
                        }
                    }
                    if let Relation::Narrows(parent) = &found.relation
                        && matches!(
                            raw.get(parent).map(|r| &r.relation),
                            Some(Relation::Child(_))
                        )
                    {
                        if found_problems.is_empty() {
                            narrowing_a_child.insert(
                                name.clone(),
                                filters.iter().map(|f| f.text.clone()).collect(),
                            );
                        }
                        found_problems.push(NARROWING_A_CHILD_PROBLEM.to_string());
                    }
                    found_problems.sort();
                    found_problems.dedup();
                    let before = found_problems.len();
                    found_problems.retain(|p| !p.ends_with(lower::UNSUPPORTED_SUFFIX));
                    if found_problems.len() != before {
                        unsupported.insert(name.clone());
                    }
                    if found_problems.is_empty() && !unsupported.contains(name) {
                        if matches!(found.relation, Relation::Narrows(_)) {
                            own = Some(Own {
                                from_text: String::new(),
                                source: None,
                                filters,
                                id: None,
                                id_text: None,
                            });
                        } else {
                            match source_of(name, line, &found.relation, &scope) {
                                Ok(source) => {
                                    let mut from_text = source_text(&source);
                                    if keeps_dot(line, name, &names) {
                                        from_text = with_kept_dot(from_text, line.every);
                                    }
                                    own = Some(Own {
                                        from_text,
                                        source: Some(source),
                                        filters,
                                        id: None,
                                        id_text: None,
                                    });
                                }
                                Err(found) => found_problems.extend(found),
                            }
                        }
                    }
                    for problem in found_problems {
                        add_problem(&mut problems, from_at.clone(), problem);
                    }
                }
            }
            let mut id_steps = None;
            let mut id_text = None;
            match &found.def.identified_by {
                Text::Written(text) => match read_id(text) {
                    Some((steps, text)) => {
                        id_steps = Some(steps);
                        id_text = Some(text);
                    }
                    None => add_problem(
                        &mut problems,
                        id_at.clone(),
                        "identified_by is a path, like \"id\" or \"build.number\"",
                    ),
                },
                Text::Missing | Text::Invalid => {}
            }
            if matches!(&found.from, FromState::Parsed(line) if line.named_by_each_of.is_some())
                && !matches!(found.def.identified_by, Text::Missing)
            {
                add_problem(&mut problems, id_at.clone(), KEYED_ID_PROBLEM);
            }
            let in_a_loop = problems
                .get(&from_at)
                .is_some_and(|texts| texts.contains("leads to a loop"));
            if matches!(found.relation, Relation::Narrows(_))
                && matches!(&found.from, FromState::Parsed(line) if !line.every)
                && !matches!(found.def.identified_by, Text::Missing)
                && !in_a_loop
            {
                add_problem(
                    &mut problems,
                    id_at.clone(),
                    "not allowed on a subject that narrows another",
                );
            }
            if let Some(own) = own.as_mut() {
                own.id = id_steps;
                own.id_text = id_text;
            }
            if let Some(own) = own {
                owns.insert(name.clone(), own);
            }
            problems_by_subject.insert(name.clone(), problems);
        }
        let mut infos = BTreeMap::new();
        for (name, found) in &raw {
            let mut problems = problems_by_subject.get(name).cloned().unwrap_or_default();
            let ok = !problems.contains_key(&field_name(&["subjects", name, "from"]));
            for text in chain_problems.get(name).into_iter().flatten() {
                let at = field_name(&["subjects", name, "from"]);
                add_problem(&mut problems, format!("{LISTED_LAST}{at}"), text);
            }
            let lowered = if ok && !chain_problems.contains_key(name) {
                flatten(name, &raw, &owns, &mut Vec::new())
            } else {
                None
            };
            let from_text = lowered.as_ref().map(|l: &Lowered| l.from_text.clone());
            let entry = entry_of(
                name,
                found,
                &problems_by_subject,
                &raw,
                &effective,
                &names,
                chain_problems.contains_key(name),
            );
            infos.insert(
                name.clone(),
                Info {
                    relation: found.relation.clone(),
                    problems,
                    lowered,
                    from_text,
                    scope: scope_of(name, &raw, &effective),
                    declarers: declarers_of(name, &raw),
                    own_part_names: own_part_names(name, &raw),
                    unsupported: unsupported.contains(name),
                    from_read: ok && !unsupported.contains(name),
                    own_filters: owns
                        .get(name)
                        .map(|own| own.filters.iter().map(|f| f.text.clone()).collect())
                        .or_else(|| narrowing_a_child.get(name).cloned())
                        .unwrap_or_default(),
                    filters_known: owns.contains_key(name) || narrowing_a_child.contains_key(name),
                    entry,
                },
            );
        }
        Reading { infos, names }
    }

    pub fn used(&self, name: &str) -> Vec<String> {
        self.walk_back(name, true)
    }

    pub fn listed(&self, name: &str) -> Vec<String> {
        self.walk_back(name, false)
    }

    fn walk_back(&self, name: &str, only_read: bool) -> Vec<String> {
        let mut seen: Vec<String> = Vec::new();
        let mut todo = vec![name.to_string()];
        while let Some(next) = todo.pop() {
            if seen.contains(&next) || !self.infos.contains_key(&next) {
                continue;
            }
            seen.push(next.clone());
            let info = &self.infos[&next];
            if only_read && !info.from_read {
                continue;
            }
            match &info.relation {
                Relation::Narrows(parent) | Relation::Child(parent) => todo.push(parent.clone()),
                Relation::Root => {}
            }
        }
        seen.sort();
        seen
    }

    pub fn problems_of(&self, policy: &Policy, requirement: &Requirement) -> Problems {
        let mut problems = Problems::new();
        for (check, read) in crate::checks::read_checks(self, requirement) {
            for text in read.problems {
                add_problem(&mut problems, field_name(&["checks", &check]), text);
            }
        }
        if let SubjectName::Named(name) = &requirement.subject {
            let mut listed = self.used(name);
            for used in listed.clone() {
                if self.infos[&used].only_narrows_a_child(&used)
                    && let Relation::Narrows(child) = &self.infos[&used].relation
                    && self.infos.contains_key(child)
                {
                    listed.push(child.clone());
                }
            }
            listed.sort();
            listed.dedup();
            for used in listed {
                merge_problems(&mut problems, &self.infos[&used].problems);
                if let Some(subject) = policy.subject(&used) {
                    merge_problems(&mut problems, &subject.problems);
                }
            }
        }
        problems
    }

    pub fn printed_aliases(&self, subject: Option<&str>, scope: &Scope) -> Vec<String> {
        let mut names: BTreeSet<String> = scope.aliases().into_iter().collect();
        if let Some(info) = subject.and_then(|name| self.infos.get(name)) {
            names.extend(info.own_part_names.iter().cloned());
        }
        names.into_iter().collect()
    }

    pub fn alias_clashes(&self, subject: Option<&str>, alias: &str) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        if self.names.contains(alias) {
            out.insert(format!("{alias} can't be an alias: it's a subject's name"));
        }
        if let Some(info) = subject.and_then(|name| self.infos.get(name)) {
            for declarer in info.declarers.get(alias).into_iter().flatten() {
                out.insert(format!(
                    "{alias} can't be an alias: it's a part of {}",
                    name::key_text(declarer)
                ));
            }
        }
        out
    }

    pub fn unsupported(&self, name: &str) -> bool {
        self.used(name)
            .iter()
            .any(|used| self.infos[used].unsupported)
    }

    pub fn lowered(&self, name: &str) -> Option<&Lowered> {
        self.infos.get(name).and_then(|info| info.lowered.as_ref())
    }

    pub fn source_refs(&self, name: &str) -> Vec<path::Path> {
        match self.lowered(name).map(|lowered| &lowered.source) {
            Some(Source::Root { path, each_of, .. }) => {
                let mut refs = path::step_refs(path);
                refs.extend(each_of.iter().filter(|each| path::is_ref(each)).cloned());
                refs
            }
            Some(Source::Child { path, each_of, .. }) => {
                let mut refs = path::step_refs(path);
                refs.extend(each_of.iter().filter(|each| path::is_ref(each)).cloned());
                refs
            }
            None => Vec::new(),
        }
    }

    pub fn filters_text(&self, name: &str) -> Option<String> {
        let texts = match self.lowered(name) {
            Some(lowered) => lowered.filters.iter().map(|f| f.text.clone()).collect(),
            None => self.readable_filters(name),
        };
        if texts.is_empty() {
            return None;
        }
        Some(texts.join(" and "))
    }

    fn readable_filters(&self, name: &str) -> Vec<String> {
        let mut layers: Vec<&Info> = Vec::new();
        let mut seen: Vec<&str> = Vec::new();
        let mut at = name;
        while let Some(info) = self.infos.get(at) {
            if !info.filters_known || seen.contains(&at) {
                break;
            }
            seen.push(at);
            layers.push(info);
            match &info.relation {
                Relation::Narrows(parent) => at = parent,
                Relation::Child(_) | Relation::Root => break,
            }
        }
        layers
            .iter()
            .rev()
            .flat_map(|info| info.own_filters.iter().cloned())
            .collect()
    }
}

fn flatten(
    name: &str,
    raw: &BTreeMap<String, Raw>,
    owns: &BTreeMap<String, Own>,
    visiting: &mut Vec<String>,
) -> Option<Lowered> {
    if visiting.iter().any(|seen| seen == name) {
        return None;
    }
    let own = owns.get(name)?;
    match &raw.get(name)?.relation {
        Relation::Narrows(parent) => {
            visiting.push(name.to_string());
            let base = flatten(parent, raw, owns, visiting);
            visiting.pop();
            let mut base = base?;
            if matches!(base.source, Source::Child { .. }) {
                return None;
            }
            base.filters.extend(own.filters.iter().cloned());
            Some(base)
        }
        _ => Some(Lowered {
            source: own.source.clone()?,
            filters: own.filters.clone(),
            id: own.id.clone(),
            from_text: own.from_text.clone(),
        }),
    }
}

fn resolved_id_text(
    name: &str,
    raw: &BTreeMap<String, Raw>,
    problems: &BTreeMap<String, Problems>,
) -> Option<String> {
    let mut at = name.to_string();
    let mut seen = BTreeSet::new();
    while let Some(Raw {
        relation: Relation::Narrows(parent),
        ..
    }) = raw.get(&at)
        && !parent.trim().is_empty()
    {
        if !seen.insert(at.clone()) {
            return match raw.get(name)?.def.identified_by {
                Text::Missing => None,
                _ => Some(INVALID_IDENTIFIED_BY.to_string()),
            };
        }
        at = parent.clone();
    }
    let found = raw.get(&at)?;
    let id_at = field_name(&["subjects", &at, "identified_by"]);
    match &found.def.identified_by {
        Text::Missing => None,
        Text::Invalid => Some(INVALID_IDENTIFIED_BY.to_string()),
        Text::Written(text) => {
            let other_problem = problems
                .get(&at)
                .and_then(|p| p.get(&id_at))
                .is_some_and(|texts| texts.iter().any(|text| text != KEYED_ID_PROBLEM));
            if other_problem {
                Some(INVALID_IDENTIFIED_BY.to_string())
            } else {
                Some(read_id(text).map_or(INVALID_IDENTIFIED_BY.to_string(), |r| r.1))
            }
        }
    }
}

fn entry_of(
    name: &str,
    found: &Raw,
    problems: &BTreeMap<String, Problems>,
    raw: &BTreeMap<String, Raw>,
    effective: &BTreeMap<String, BTreeMap<String, PartRead>>,
    names: &BTreeSet<String>,
    blocked: bool,
) -> Value {
    let from_at = field_name(&["subjects", name, "from"]);
    let invalid = blocked || problems.get(name).is_some_and(|p| p.contains_key(&from_at));
    let from = if invalid || found.def.says_how || matches!(found.from, FromState::NotText) {
        INVALID_FROM.to_string()
    } else {
        match &found.from {
            FromState::Parsed(line) if matches!(found.def.from, Text::Written(_)) => {
                let scope = scope_of(name, raw, effective);
                let mut aliases = scope.aliases();
                aliases.extend(own_part_names(name, raw));
                let refs: Vec<&str> = aliases.iter().map(String::as_str).collect();
                let printed = s::print_from(line, &refs, &[]);
                if keeps_dot(line, name, names) {
                    with_kept_dot(printed, line.every)
                } else {
                    printed
                }
            }
            _ => name::name(&path::Path {
                start: Start::Subject,
                steps: vec![Step::Key(name.to_string())],
            }),
        }
    };
    let identified_by = resolved_id_text(name, raw, problems);
    let mut parts = Map::new();
    for (alias, part) in effective.get(name).into_iter().flatten() {
        parts.insert(
            alias.clone(),
            json!({"from": part.from_text, "identified_by": part.id_text}),
        );
    }
    json!({
        "description": found.def.description,
        "from": from,
        "identified_by": identified_by,
        "parts": Value::Object(parts),
    })
}

#[cfg(test)]
mod tests;
