use crate::lower::{self, PartDef, Scope};
use crate::name;
use crate::ops::Check;
use crate::path::{self, Start, Step};
use crate::policy::{
    Has, Policy, Problems, Requirement, SubjectDef, SubjectName, Subjects, Text, add_problem,
    field_name, merge_problems,
};
use ergo_sentences as s;
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, BTreeSet};

pub const INVALID_FROM: &str = "<invalid from>";
pub const NARROWING_A_CHILD_PROBLEM: &str =
    "can't build on a subject read from another subject yet";

pub const INVALID_IDENTIFIED_BY: &str = "<invalid identified_by>";
pub const KEYED_ID_PROBLEM: &str = "not allowed with named by each of: the key is the id";
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
        each_of: Option<path::Path>,
    },
    Child {
        path: path::Path,
        each_of: Option<path::Path>,
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
    if bad_alias(alias) {
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
        if line.every {
            problems.push(
                "every can't go with a from line that starts at another subject yet".to_string(),
            );
        }
    }
    if line.every && line.named_by_each_of.is_some() {
        problems.push("every can't go with named by each of: start the from line at a subject to read its names one subject at a time".to_string());
    }
    if line.path.start == s::Start::Params {
        problems.push("a from reads the input, so it can't start at $params".to_string());
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
    if line.every || line.named_by_each_of.is_some() || !line.whose.is_empty() {
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
                Some(each) if each.start == s::Start::It => {
                    return Err(vec![format!("{name}: it can't name keys")]);
                }
                Some(each) => Some(scope.path(each)?),
            };
            Ok(Source::Child { path, each_of })
        }
        _ => {
            if let s::Start::Field { key, .. } | s::Start::Quoted(key) = &line.path.start {
                steps.insert(0, Step::Key(key.clone()));
            }
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
                        s::Start::It => {
                            return Err(vec![format!("{name}: it can't name keys")]);
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
                each_of,
            })
        }
    }
}

fn source_text(source: &Source) -> String {
    match source {
        Source::Root { path, every, .. } => {
            let words = if *every { "every " } else { "" };
            let from_input = matches!(path.steps.first(), Some(Step::Index(_)));
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
        Source::Child { path, .. } => name::name(path),
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
                    let aliases = scope.aliases();
                    let alias_refs: Vec<&str> = aliases.iter().map(String::as_str).collect();
                    let parent_names = scope.parent_names();
                    let parent_refs: Vec<&str> = parent_names.iter().map(String::as_str).collect();
                    let syntax_problems = s::from_problems(line);
                    let reads = syntax_problems.is_empty();
                    found_problems.extend(syntax_problems);
                    let mut filters = Vec::new();
                    for condition in line.whose.iter().filter(|_| reads) {
                        let text = s::print_from_condition(condition, &alias_refs, &parent_refs);
                        match condition {
                            s::FromCondition::Condition(condition) => {
                                found_problems.extend(lower::condition_elapsed_problems(condition));
                                match lower::lower_condition(condition, &scope) {
                                    Ok(check) => filters.push(Filter { text, check }),
                                    Err(found) => {
                                        found_problems.extend(lower::in_from_line(found));
                                    }
                                }
                            }
                            s::FromCondition::Quantified {
                                quantifier,
                                path,
                                if_any,
                                phrase,
                            } => match lower::lower_quantified(
                                *quantifier,
                                path,
                                &[],
                                *if_any,
                                phrase,
                                &scope,
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
            let problems = problems_by_subject.get(name).cloned().unwrap_or_default();
            let ok = !problems.contains_key(&field_name(&["subjects", name, "from"]));
            let lowered = if ok {
                flatten(name, &raw, &owns, &mut Vec::new())
            } else {
                None
            };
            let from_text = lowered.as_ref().map(|l: &Lowered| l.from_text.clone());
            let entry = entry_of(name, found, &problems_by_subject, &raw, &effective, &names);
            infos.insert(
                name.clone(),
                Info {
                    relation: found.relation.clone(),
                    problems,
                    lowered,
                    from_text,
                    scope: scope_of(name, &raw, &effective),
                    declarers: declarers_of(name, &raw),
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
            Some(Source::Child { path, each_of }) => {
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
) -> Value {
    let from_at = field_name(&["subjects", name, "from"]);
    let invalid = problems.get(name).is_some_and(|p| p.contains_key(&from_at));
    let from = if invalid || found.def.says_how || matches!(found.from, FromState::NotText) {
        INVALID_FROM.to_string()
    } else {
        match &found.from {
            FromState::Parsed(line) if matches!(found.def.from, Text::Written(_)) => {
                let scope = scope_of(name, raw, effective);
                let aliases = scope.aliases();
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
mod tests {
    use super::*;
    use serde_json::json;

    fn reading(subjects: Value) -> (Policy, Reading) {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.3-dev",
            "subjects": subjects,
            "requirements": {}
        }));
        let reading = Reading::of(&policy);
        (policy, reading)
    }

    fn problem_names(reading: &Reading, subject: &str) -> Vec<String> {
        reading.infos[subject].problems.keys().cloned().collect()
    }

    fn texts(reading: &Reading, subject: &str, at: &str) -> Vec<String> {
        reading.infos[subject].problems[at]
            .iter()
            .cloned()
            .collect()
    }

    #[test]
    fn a_plain_from_is_a_root_read_from_the_input() {
        let (_, r) = reading(json!({"d": {"from": "data.deployments"}}));
        let lowered = r.lowered("d").unwrap();
        assert_eq!(lowered.from_text, "data.deployments");
        assert!(matches!(lowered.source, Source::Root { every: false, .. }));
    }

    #[test]
    fn a_subject_with_no_from_reads_the_input_field_of_its_own_name() {
        let (_, r) = reading(json!({"artifact": null, "pull request": {}}));
        assert_eq!(r.lowered("artifact").unwrap().from_text, "artifact");
        assert_eq!(
            r.lowered("pull request").unwrap().from_text,
            "\"pull request\""
        );
    }

    #[test]
    fn a_from_that_is_the_input_alone_reads_the_whole_input() {
        let (_, r) = reading(json!({"art": {"from": "$input"}}));
        assert_eq!(r.lowered("art").unwrap().from_text, "$input");
    }

    #[test]
    fn a_line_that_does_not_parse_is_listed_under_from() {
        let (_, r) = reading(json!({"d": {"from": "deployments whose environment is \"prod"}}));
        assert_eq!(
            texts(&r, "d", "subjects.d.from"),
            ["unclosed quote at column 34"]
        );
        assert!(r.lowered("d").is_none());
        assert_eq!(r.infos["d"].entry["from"], json!("<invalid from>"));
    }

    #[test]
    fn a_path_in_identified_by_that_does_not_parse_is_listed_under_identified_by() {
        let (_, r) = reading(json!({"d": {"from": "ds", "identified_by": "environment is"}}));
        assert_eq!(
            texts(&r, "d", "subjects.d.identified_by"),
            ["identified_by is a path, like \"id\" or \"build.number\""]
        );
    }

    #[test]
    fn a_path_alone_names_the_subject_it_starts_at_as_a_child() {
        let (_, r) = reading(json!({"art": {"from": "arts"}, "p": {"from": "art.pulls"}}));
        assert_eq!(r.infos["p"].relation, Relation::Child("art".into()));
        assert_eq!(r.lowered("p").unwrap().from_text, "art.pulls");
    }

    #[test]
    fn a_path_through_a_part_of_a_dollar_subject_quotes_the_subject_name() {
        let (_, r) = reading(json!({
            "$x": {"from": "things", "has": {"pa": "meta"}},
            "kid": {"from": "\"$x\".pa.items"}
        }));
        assert_eq!(r.lowered("kid").unwrap().from_text, "\"$x\".pa.items");
    }

    #[test]
    fn a_subject_name_with_named_by_each_of_is_a_child_that_keeps_its_keys_inside_its_parent() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"},
            "k": {"from": "art named by each of $params.k"},
            "j": {"from": "first of art named by each of $params.k"},
        }));
        assert_eq!(r.infos["k"].relation, Relation::Child("art".into()));
        assert_eq!(r.infos["j"].relation, Relation::Child("art".into()));
        assert!(matches!(
            r.lowered("k").unwrap().source,
            Source::Child {
                each_of: Some(_),
                ..
            }
        ));
    }

    #[test]
    fn a_dotted_first_key_named_like_another_subject_keeps_its_dot_in_every_printed_from() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"},
            "k": {"from": ".art named by each of $params.k"},
            "p": {"from": ".art.p"},
            "q": {"from": ".other.p"},
        }));
        assert_eq!(r.lowered("k").unwrap().from_text, ".art");
        assert_eq!(r.lowered("p").unwrap().from_text, ".art.p");
        assert_eq!(r.lowered("q").unwrap().from_text, "other.p");
        assert_eq!(
            r.infos["k"].entry["from"],
            json!(".art named by each of $params.k")
        );
        assert_eq!(r.infos["p"].entry["from"], json!(".art.p"));
        assert_eq!(r.infos["q"].entry["from"], json!("other.p"));
    }

    #[test]
    fn a_kept_dot_goes_after_the_position_of_a_printed_from() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"},
            "p": {"from": ".art.p[0]"},
            "q": {"from": "first of .art.p"},
        }));
        assert_eq!(r.infos["p"].entry["from"], json!("item 1 of .art.p"));
        assert_eq!(r.infos["q"].entry["from"], json!("first of .art.p"));
    }

    #[test]
    fn a_subject_name_and_nothing_more_narrows_that_subject() {
        let (_, r) = reading(
            json!({"art": {"from": "arts", "identified_by": "id"}, "b": {"from": "art whose x exists"}}),
        );
        assert_eq!(r.infos["b"].relation, Relation::Narrows("art".into()));
        assert_eq!(r.lowered("b").unwrap().filters.len(), 1);
        assert_eq!(r.infos["b"].entry["identified_by"], json!("id"));
    }

    #[test]
    fn a_position_after_a_subjects_name_is_a_child_that_reads_the_position_and_does_not_narrow() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"},
            "a": {"from": "art[1]"},
            "b": {"from": "first of art"},
            "c": {"from": "item 2 of art"},
        }));
        for name in ["a", "b", "c"] {
            assert_eq!(r.infos[name].relation, Relation::Child("art".into()));
        }
    }

    #[test]
    fn a_subject_called_like_its_own_from_reads_the_input_field() {
        let (_, r) = reading(json!({"lockfile": {"from": "lockfile whose status exists"}}));
        assert_eq!(r.infos["lockfile"].relation, Relation::Root);
        assert_eq!(r.lowered("lockfile").unwrap().from_text, "lockfile");
    }

    #[test]
    fn a_dot_reads_the_field_and_not_the_subject() {
        let (_, r) = reading(json!({"art": {"from": "arts"}, "b": {"from": ".a.x"}}));
        assert_eq!(r.infos["b"].relation, Relation::Root);
    }

    #[test]
    fn a_subject_that_narrows_a_blank_name_reports_no_id_of_its_own_nor_its_parents() {
        let (_, r) = reading(json!({
            " ": {"from": "things", "identified_by": "id"},
            "b": {"from": "\" \" whose id is \"a\""}
        }));
        assert_eq!(r.infos["b"].entry["identified_by"], Value::Null);
        assert_eq!(r.infos[" "].entry["identified_by"], json!("id"));
    }

    #[test]
    fn a_subject_in_a_loop_lists_the_whole_loop_but_only_reads_itself() {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.3-dev",
            "subjects": {"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}},
            "requirements": {}
        }));
        let r = Reading::of(&policy);
        assert_eq!(r.listed("x"), ["x", "y"]);
        assert_eq!(r.used("x"), ["x"]);
    }

    #[test]
    fn subjects_that_narrow_each_other_lead_to_a_loop() {
        let (_, r) = reading(
            json!({"x": {"from": "y whose id exists"}, "y": {"from": "x whose id exists"}}),
        );
        assert_eq!(texts(&r, "x", "subjects.x.from"), ["leads to a loop"]);
        assert_eq!(texts(&r, "y", "subjects.y.from"), ["leads to a loop"]);
        assert!(r.lowered("x").is_none());
    }

    #[test]
    fn a_subject_that_reaches_a_loop_leads_to_a_loop_too() {
        let (_, r) =
            reading(json!({"pa": {"from": "pb"}, "pb": {"from": "pa"}, "pc": {"from": "pa"}}));
        assert_eq!(texts(&r, "pc", "subjects.pc.from"), ["leads to a loop"]);
    }

    #[test]
    fn a_chain_of_four_subjects_is_written_wrong() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"}, "b": {"from": "art.bs"}, "c": {"from": "b.cs"}, "d": {"from": "c.ds"}
        }));
        assert_eq!(
            texts(&r, "d", "subjects.d.from"),
            ["a chain of more than three subjects isn't supported yet"]
        );
        assert!(problem_names(&r, "c").is_empty());
    }

    #[test]
    fn a_blank_subject_name_cannot_start_a_chain() {
        let (_, r) =
            reading(json!({" ": {"from": "things"}, "b": {"from": "\" \" whose id exists"}}));
        assert_eq!(
            texts(&r, "b", "subjects.b.from"),
            ["\" \" isn't a subject name"]
        );
    }

    #[test]
    fn every_cannot_go_with_a_from_line_that_starts_at_a_subject() {
        let (_, r) = reading(json!({"art": {"from": "arts"}, "p": {"from": "every art.prs"}}));
        assert_eq!(
            texts(&r, "p", "subjects.p.from"),
            ["every can't go with a from line that starts at another subject yet"]
        );
    }

    #[test]
    fn every_cannot_go_with_named_by_each_of() {
        let (_, r) = reading(json!({"s": {"from": "every art.b named by each of $params.l"}}));
        assert_eq!(
            texts(&r, "s", "subjects.s.from"),
            [
                "every can't go with named by each of: start the from line at a subject to read its names one subject at a time"
            ]
        );
    }

    #[test]
    fn every_takes_ten_steps_and_an_eleventh_is_written_wrong() {
        let (_, ok) = reading(json!({"s": {"from": "every art.b.c.d.e.f.g.h.i.j"}}));
        assert!(ok.lowered("s").is_some());
        let (_, over) = reading(json!({"s": {"from": "every art.b.c.d.e.f.g.h.i.j.k"}}));
        assert_eq!(
            texts(&over, "s", "subjects.s.from"),
            ["every over more than ten steps isn't supported yet"]
        );
        let (_, input) = reading(json!({"s": {"from": "every $input.art.b.c.d.e.f.g.h.i.j"}}));
        assert!(input.lowered("s").is_some());
    }

    #[test]
    fn a_from_cannot_start_at_params() {
        let (_, r) = reading(json!({"s": {"from": "$params.x"}}));
        assert_eq!(
            texts(&r, "s", "subjects.s.from"),
            ["a from reads the input, so it can't start at $params"]
        );
    }

    #[test]
    fn a_bare_name_after_named_by_is_an_unknown_alias() {
        let (_, r) = reading(json!({"s": {"from": "art named by foo"}}));
        assert_eq!(texts(&r, "s", "subjects.s.from"), ["unknown alias foo"]);
    }

    #[test]
    fn a_condition_with_a_count_on_the_right_is_read_and_not_marked_unsupported() {
        let (_, r) = reading(json!({"s": {"from": "art whose x is at least count of ys"}}));
        assert!(!r.infos["s"].unsupported);
        assert!(r.infos["s"].problems.is_empty());
        assert!(r.lowered("s").is_some());
    }

    #[test]
    fn a_narrowing_subject_cannot_have_its_own_identified_by() {
        let (_, r) = reading(
            json!({"art": {"from": "arts", "identified_by": "id"}, "b": {"from": "art whose x exists", "identified_by": "team"}}),
        );
        assert_eq!(
            texts(&r, "b", "subjects.b.identified_by"),
            ["not allowed on a subject that narrows another"]
        );
    }

    #[test]
    fn identified_by_on_a_subject_listed_by_named_by_each_of_is_written_wrong() {
        for from in [
            "suites named by each of $params.names",
            "artifact.suites named by each of $params.names",
            "top[$params.g].suites named by each of $params.names",
            "suites named by each of $params.names whose id exists",
            "top named by $params.g named by each of $params.names",
        ] {
            let (_, r) = reading(json!({"s": {"from": from, "identified_by": "id"}}));
            assert_eq!(
                texts(&r, "s", "subjects.s.identified_by"),
                [KEYED_ID_PROBLEM],
                "{from}"
            );
            assert_eq!(r.infos["s"].entry["identified_by"], json!("id"), "{from}");
        }
    }

    #[test]
    fn identified_by_on_a_child_listed_by_named_by_each_of_is_written_wrong() {
        for from in [
            "art.suites named by each of $params.names",
            "art.suites named by each of $params.names whose id exists and id is 1",
        ] {
            let (_, r) = reading(
                json!({"art": {"from": "arts"}, "c": {"from": from, "identified_by": "id"}}),
            );
            assert_eq!(
                texts(&r, "c", "subjects.c.identified_by"),
                [KEYED_ID_PROBLEM],
                "{from}"
            );
        }
    }

    #[test]
    fn the_keyed_id_problem_sorts_with_a_problem_of_the_path() {
        let (_, r) = reading(
            json!({"s": {"from": "suites named by each of $params.names", "identified_by": "id is"}}),
        );
        assert_eq!(
            texts(&r, "s", "subjects.s.identified_by"),
            [
                "identified_by is a path, like \"id\" or \"build.number\"".to_string(),
                KEYED_ID_PROBLEM.to_string()
            ]
        );
    }

    #[test]
    fn identified_by_is_allowed_with_named_by_and_under_a_keyed_parent() {
        let (_, r) = reading(json!({
            "a": {"from": "suites named by $params.g", "identified_by": "id"},
            "k": {"from": "suites named by each of $params.names"},
            "c": {"from": "k.runs", "identified_by": "id"}
        }));
        assert!(
            !r.infos["a"]
                .problems
                .contains_key("subjects.a.identified_by")
        );
        assert!(
            !r.infos["c"]
                .problems
                .contains_key("subjects.c.identified_by")
        );
    }

    #[test]
    fn a_subject_that_narrows_a_child_subject_is_written_wrong() {
        let (_, r) = reading(
            json!({"art": {"from": "arts"}, "k": {"from": "art.ks"}, "n": {"from": "k whose x exists"}}),
        );
        assert!(r.infos["n"].problems.contains_key("subjects.n.from"));
    }

    #[test]
    fn parts_are_listed_with_their_paths_written_as_a_sentence_writes_them() {
        let (_, r) = reading(json!({"r": {"from": "rs", "has": {
            "dd": "  dd.b ", "x": "x[$params.k]", "c": {"from": "c.d", "identified_by": "id"}
        }}}));
        assert_eq!(
            r.infos["r"].entry["parts"],
            json!({
                "dd": {"from": "dd.b", "identified_by": null},
                "x": {"from": "x named by $params.k", "identified_by": null},
                "c": {"from": "c.d", "identified_by": "id"}
            })
        );
    }

    #[test]
    fn a_part_written_wrong_is_listed_as_best_it_can_be() {
        let (_, r) = reading(json!({"r": {"from": "rs", "has": {
            "bad": {"from": "art whose x exists", "identified_by": "x y z"},
            "num": 3
        }}}));
        assert_eq!(
            r.infos["r"].entry["parts"]["bad"],
            json!({"from": "<invalid from>", "identified_by": "<invalid identified_by>"})
        );
        assert_eq!(
            r.infos["r"].entry["parts"]["num"]["from"],
            json!("<invalid from>")
        );
    }

    #[test]
    fn part_problems_are_listed_under_the_alias() {
        let (_, r) = reading(json!({"r": {"from": "rs", "has": {
            "who": "art whose x exists", "in_params": "$params.x", "blank": " ",
            "every": "art", "with space": "art", "bare_by": "art named by foo", "$dollar": "art"
        }}}));
        let problems = &r.infos["r"].problems;
        assert_eq!(
            problems["subjects.r.has.who"].iter().collect::<Vec<_>>(),
            ["from: a part is a path: whose and named by each of can't go in it"]
        );
        assert!(problems["subjects.r.has.in_params"].contains(
            "from: a part reads inside its subject, so it can't start at $params or $input"
        ));
        assert!(problems["subjects.r.has.blank"].contains("from: doesn't parse"));
        assert!(problems["subjects.r.has.every"].contains("invalid alias"));
        assert!(problems["subjects.r.has.\"with space\""].contains("invalid alias"));
        assert!(problems["subjects.r.has.$dollar"].contains("invalid alias"));
        assert!(problems["subjects.r.has.bare_by"].contains("from: unknown alias foo"));
    }

    #[test]
    fn an_alias_named_like_a_subject_or_a_part_of_one_it_narrows_is_written_wrong() {
        let (_, r) = reading(json!({
            "base": {"from": "bs", "has": {"x": "x"}},
            "n": {"from": "base whose x exists", "has": {"x": "x", "base": "b"}},
        }));
        let problems = &r.infos["n"].problems["subjects.n.has.x"];
        assert_eq!(
            problems.iter().collect::<Vec<_>>(),
            ["x can't be an alias: it's a part of base"]
        );
        assert_eq!(
            r.infos["n"].problems["subjects.n.has.base"]
                .iter()
                .collect::<Vec<_>>(),
            ["base can't be an alias: it's a subject's name"]
        );
    }

    #[test]
    fn an_alias_named_like_a_part_of_a_parent_is_written_wrong() {
        let (_, r) = reading(json!({
            "gp": {"from": "g", "has": {"cap": "c"}},
            "p": {"from": "gp.ps"},
            "leaf": {"from": "p.ls", "has": {"cap": "d"}},
        }));
        assert_eq!(
            r.infos["leaf"].problems["subjects.leaf.has.cap"]
                .iter()
                .collect::<Vec<_>>(),
            ["cap can't be an alias: it's a part of gp"]
        );
    }

    #[test]
    fn a_narrowing_subject_keeps_the_parts_of_the_subject_it_narrows() {
        let (_, r) = reading(json!({
            "base": {"from": "bs", "has": {"x": {"from": "x", "identified_by": "id"}}},
            "n": {"from": "base whose x.y exists", "has": {"z": "z"}},
        }));
        let parts = r.infos["n"].entry["parts"].as_object().unwrap();
        assert_eq!(parts.keys().collect::<Vec<_>>(), ["x", "z"]);
        assert_eq!(r.lowered("n").unwrap().filters.len(), 1);
    }

    #[test]
    fn the_subjects_a_requirement_uses_are_the_subject_and_everything_it_reads_from() {
        let (_, r) = reading(json!({
            "art": {"from": "arts"}, "b": {"from": "art.bs"}, "c": {"from": "cs"},
            "n": {"from": "c whose x exists"},
        }));
        assert_eq!(r.used("b"), ["art", "b"]);
        assert_eq!(r.used("n"), ["c", "n"]);
        assert_eq!(r.used("c"), ["c"]);
        assert!(r.used("nope").is_empty());
        assert!(r.listed("nope").is_empty());
    }

    #[test]
    fn the_problems_of_a_parent_belong_to_the_requirement_of_its_child() {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.3-dev",
            "subjects": {"art": {"from": "arts whose"}, "b": {"from": "art.bs"}},
            "requirements": {"r": {"subject": "b", "checks": {"c": "x"}}}
        }));
        let reading = Reading::of(&policy);
        let problems = reading.problems_of(&policy, &policy.requirements["r"]);
        assert!(problems.contains_key("subjects.art.from"));
    }

    #[test]
    fn the_condition_texts_of_a_chain_start_with_the_outermost() {
        let (_, r) = reading(json!({
            "art": {"from": "arts whose x exists"}, "n": {"from": "art whose y exists"},
        }));
        assert_eq!(r.filters_text("n").unwrap(), "x exists and y exists");
        assert!(r.filters_text("nope").is_none());
    }

    fn requirement_problems(subjects: Value) -> Problems {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.3-dev",
            "subjects": subjects,
            "requirements": {"r": {"subject": "kid", "checks": {"c": "n exists"}}}
        }));
        Reading::of(&policy).problems_of(&policy, &policy.requirements["r"])
    }

    #[test]
    fn a_narrowed_child_with_an_unknown_name_lists_its_own_problem_for_the_requirement() {
        let problems = requirement_problems(json!({
            "parent": {"from": "things", "identified_by": "id"},
            "mid": {"from": "parent.items whose zz is $foo", "identified_by": "n"},
            "kid": {"from": "mid whose n is 1"}
        }));
        assert!(problems.contains_key("subjects.mid.from"));
        assert!(problems["subjects.kid.from"].contains(NARROWING_A_CHILD_PROBLEM));
    }

    #[test]
    fn a_narrowed_child_with_mixed_types_lists_its_own_problem_for_the_requirement() {
        let problems = requirement_problems(json!({
            "parent": {"from": "things", "identified_by": "id"},
            "mid": {"from": "parent.items whose n is one of 1, \"a\"", "identified_by": "n"},
            "kid": {"from": "mid whose n is 1"}
        }));
        assert!(problems.contains_key("subjects.mid.from"));
        assert!(problems.contains_key("subjects.kid.from"));
    }

    #[test]
    fn subjects_in_a_loop_each_with_an_identified_by_show_it_as_invalid() {
        let (_, r) = reading(json!({
            "pp": {"from": "kid whose n is 1", "identified_by": "x"},
            "kid": {"from": "pp whose n is 1", "identified_by": "y"}
        }));
        assert_eq!(
            r.infos["pp"].entry["identified_by"],
            "<invalid identified_by>"
        );
        assert_eq!(
            r.infos["kid"].entry["identified_by"],
            "<invalid identified_by>"
        );
        assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["leads to a loop"]);
        assert!(
            !r.infos["kid"]
                .problems
                .contains_key("subjects.kid.identified_by")
        );
    }

    #[test]
    fn subjects_in_a_loop_without_an_identified_by_show_none() {
        let (_, r) = reading(json!({
            "pp": {"from": "kid whose n is 1"},
            "kid": {"from": "pp whose n is 1"}
        }));
        assert_eq!(r.infos["pp"].entry["identified_by"], Value::Null);
        assert_eq!(r.infos["kid"].entry["identified_by"], Value::Null);
    }

    #[test]
    fn a_from_with_an_unknown_name_still_starts_at_its_subject() {
        for from in [
            "parent.items whose zz is $foo",
            "parent.items named by $foo",
            "parent[$foo] whose n is 1",
            "parent.items whose zz is $foo.k",
        ] {
            let (_, r) = reading(json!({
                "parent": {"from": "things"}, "kid": {"from": from}
            }));
            assert_eq!(
                r.infos["kid"].relation,
                Relation::Child("parent".to_string()),
                "{from}"
            );
            assert_eq!(r.listed("kid"), ["kid", "parent"], "{from}");
            assert_eq!(
                texts(&r, "kid", "subjects.kid.from"),
                ["unknown name $foo"],
                "{from}"
            );
            assert_eq!(r.infos["kid"].entry["from"], INVALID_FROM, "{from}");
        }
    }

    #[test]
    fn a_from_with_an_unknown_name_and_a_quoted_parent_with_whose_in_it_starts_at_that_parent() {
        let (_, r) = reading(json!({
            "par whose ent": {"from": "things"},
            "kid": {"from": "\"par whose ent\".items whose zz is $foo"}
        }));
        assert_eq!(
            r.infos["kid"].relation,
            Relation::Child("par whose ent".to_string())
        );
        assert_eq!(r.listed("kid"), ["kid", "par whose ent"]);
    }

    #[test]
    fn a_narrowing_subject_with_an_unknown_name_takes_the_id_and_parts_of_its_parent() {
        let (_, r) = reading(json!({
            "parent": {"from": "things", "identified_by": "id", "has": {"owner": "owner.name"}},
            "kid": {"from": "parent whose n is $foo"}
        }));
        assert_eq!(
            r.infos["kid"].relation,
            Relation::Narrows("parent".to_string())
        );
        assert_eq!(r.infos["kid"].entry["identified_by"], "id");
        assert_eq!(
            r.infos["kid"].entry["parts"]["owner"]["from"],
            r.infos["parent"].entry["parts"]["owner"]["from"]
        );
        assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["unknown name $foo"]);
    }

    #[test]
    fn the_unknown_name_of_a_whose_adds_no_second_problem() {
        let (_, r) = reading(json!({
            "parent": {"from": "things"}, "kid": {"from": "parent.items whose zz is $foo"}
        }));
        assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["unknown name $foo"]);
    }

    #[test]
    fn a_from_with_an_unknown_name_and_a_syntax_error_lists_no_other_subject() {
        let (_, r) = reading(json!({
            "parent": {"from": "things"}, "kid": {"from": "parent.items whose zz is $foo foo bar"}
        }));
        assert_eq!(r.infos["kid"].relation, Relation::Root);
        assert_eq!(r.listed("kid"), ["kid"]);
        assert_eq!(texts(&r, "kid", "subjects.kid.from"), ["doesn't parse"]);
    }
}
