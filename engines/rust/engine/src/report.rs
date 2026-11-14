use crate::cause::Cause;
use crate::policy::{
    Check, Form, LISTED_LAST, OptionLines, Policy, Problems, Requirement, SPEC, SubjectName,
    field_name, merge_problems,
};
use crate::reading::{INVALID_FROM, Reading, Source};
use crate::value::{Decimal, json_text};
use serde_json::{Map, Value, json};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub requirement: String,
    pub subject_type: Value,
    pub subject_id: Value,
    pub subject_in: Option<Map<String, Value>>,
    pub check: String,
    pub cause: Cause,
    pub inputs: Vec<Value>,
    pub message: Option<String>,
    pub failed_items: Option<Value>,
    pub failed_assertions: Option<Value>,
}

impl Row {
    pub fn passed(&self) -> bool {
        self.cause == Cause::Satisfied
    }

    pub fn to_json(&self) -> Value {
        let mut subject = Map::new();
        subject.insert("type".to_string(), self.subject_type.clone());
        subject.insert("id".to_string(), self.subject_id.clone());
        if let Some(parents) = &self.subject_in {
            subject.insert("in".to_string(), Value::Object(parents.clone()));
        }
        let mut row = Map::new();
        row.insert("requirement".to_string(), json!(self.requirement));
        row.insert("subject".to_string(), Value::Object(subject));
        row.insert("check".to_string(), json!(self.check));
        row.insert("passed".to_string(), json!(self.passed()));
        row.insert("cause".to_string(), json!(self.cause.name()));
        row.insert("inputs".to_string(), Value::Array(self.inputs.clone()));
        if let Some(message) = &self.message {
            row.insert(
                "message".to_string(),
                json!(crate::ops::message::one_line(message)),
            );
        }
        if let Some(items) = &self.failed_items {
            row.insert("failed_items".to_string(), items.clone());
        }
        if let Some(assertions) = &self.failed_assertions {
            row.insert("failed_assertions".to_string(), assertions.clone());
        }
        Value::Object(row)
    }
}

pub fn input(name: &str, value: Value, locations: &[String]) -> Value {
    json!({"name": name, "value": value, "locations": locations})
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Evaluation {
    pub total: u64,
    pub matching: u64,
    pub min_subjects: Vec<Row>,
    pub unique_ids: Vec<Row>,
    pub unique_ancestor_ids: Vec<Row>,
    pub applies: Vec<Row>,
    pub subject_rows: Vec<Vec<Row>>,
}

fn subject_type(requirement: &Requirement) -> Value {
    match &requirement.subject {
        SubjectName::Missing => json!("subject"),
        SubjectName::Named(name) => json!(name),
        SubjectName::Invalid(raw) => raw.clone(),
    }
}

fn type_text(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        other => json_text(other),
    }
}

pub fn row_of(
    requirement_name: &str,
    requirement: &Requirement,
    check: &str,
    cause: Cause,
    inputs: Vec<Value>,
) -> Row {
    Row {
        requirement: requirement_name.to_string(),
        subject_type: subject_type(requirement),
        subject_id: Value::Null,
        subject_in: None,
        check: check.to_string(),
        cause,
        inputs,
        message: None,
        failed_items: None,
        failed_assertions: None,
    }
}

pub fn min_subjects_row(
    requirement_name: &str,
    requirement: &Requirement,
    count: u64,
    locations: &[String],
    read: Option<Cause>,
    extra_inputs: Vec<Value>,
) -> Row {
    let label = format!("in-scope {} count", type_text(&subject_type(requirement)));
    let cause = match read {
        Some(cause) => cause,
        None if count >= requirement.min_subjects_count => Cause::Satisfied,
        None => Cause::Value,
    };
    let mut inputs = vec![input(&label, json!(count), locations)];
    inputs.extend(extra_inputs);
    let mut row = row_of(
        requirement_name,
        requirement,
        "$min_subjects",
        cause,
        inputs,
    );
    if cause != Cause::Satisfied {
        row.message = Some(crate::ops::message::is(&label, &json!(count)));
    }
    row
}

pub fn unique_ancestor_ids_row(
    requirement_name: &str,
    requirement: &Requirement,
    ancestor: &str,
    repeated: Vec<Value>,
    locations: &[String],
) -> Row {
    let label = format!("repeated {ancestor} ids");
    let mut row = unique_ids_row(requirement_name, requirement, repeated, locations);
    row.check = "$unique_ancestor_ids".to_string();
    row.subject_type = json!(ancestor);
    row.inputs[0]["name"] = json!(label);
    if let Some(message) = row.message.as_mut() {
        *message = crate::ops::message::is(&label, &row.inputs[0]["value"]);
    }
    row
}

pub fn unique_ids_row(
    requirement_name: &str,
    requirement: &Requirement,
    repeated: Vec<Value>,
    locations: &[String],
) -> Row {
    let label = format!("repeated {} ids", type_text(&subject_type(requirement)));
    let cause = if repeated.is_empty() {
        Cause::Satisfied
    } else {
        Cause::Value
    };
    let shown = Value::Array(repeated);
    let mut row = row_of(
        requirement_name,
        requirement,
        "$unique_ids",
        cause,
        vec![input(&label, shown.clone(), locations)],
    );
    if cause != Cause::Satisfied {
        row.message = Some(crate::ops::message::is(&label, &shown));
    }
    row
}

pub fn unreadable_params(params: &Value) -> Vec<Value> {
    match params {
        Value::Null | Value::Object(_) => Vec::new(),
        _ => vec![input("$params", json!(["not an object"]), &[])],
    }
}

pub fn no_subjects(
    requirement_name: &str,
    requirement: &Requirement,
    params: &Value,
) -> Evaluation {
    let unreadable = unreadable_params(params);
    let read = (!unreadable.is_empty()).then_some(Cause::Unusable);
    Evaluation {
        total: 0,
        matching: 0,
        min_subjects: vec![min_subjects_row(
            requirement_name,
            requirement,
            0,
            &[],
            read,
            unreadable,
        )],
        unique_ids: vec![unique_ids_row(
            requirement_name,
            requirement,
            Vec::new(),
            &[],
        )],
        unique_ancestor_ids: Vec::new(),
        applies: Vec::new(),
        subject_rows: Vec::new(),
    }
}

fn written_line(line: &Option<String>) -> String {
    match line {
        Some(text) => text.trim().to_string(),
        None => "<invalid assert>".to_string(),
    }
}

pub fn written_expression(check: &Check) -> String {
    match &check.form {
        Form::Line(text) => text.trim().to_string(),
        Form::Assert { lines, for_line } => {
            let body = lines
                .iter()
                .map(written_line)
                .collect::<Vec<_>>()
                .join(" and ");
            match for_line {
                Some(text) => format!("for {}: {body}", text.trim()),
                None => body,
            }
        }
        Form::MissingAssert => "<missing assert>".to_string(),
        Form::Invalid => "<invalid check>".to_string(),
        Form::AnyOf(None) => "<invalid any_of>".to_string(),
        Form::AnyOf(Some(options)) if options.is_empty() => "one of: <empty options>".to_string(),
        Form::AnyOf(Some(options)) => {
            let parts: Vec<String> = options
                .iter()
                .map(|(name, option)| {
                    let body = match option {
                        OptionLines::Invalid => "<invalid option>".to_string(),
                        OptionLines::Lines(lines) if lines.is_empty() => {
                            "<empty option>".to_string()
                        }
                        OptionLines::Lines(lines) => lines
                            .iter()
                            .map(written_line)
                            .collect::<Vec<_>>()
                            .join(" and "),
                    };
                    format!("{name}({body})")
                })
                .collect();
            format!("one of: {}", parts.join(" | "))
        }
    }
}

fn is_zero(value: &Value) -> bool {
    match value {
        Value::Number(number) => Decimal::parse(&number.to_string()).is_some_and(|d| d.is_zero()),
        _ => false,
    }
}

fn from_readable(reading: &Reading, subject_name: &str, extra: &Problems) -> bool {
    let at = field_name(&["subjects", subject_name, "from"]);
    reading
        .infos
        .get(subject_name)
        .is_some_and(|info| !info.problems.contains_key(&at) && info.from_text.is_some())
        && !extra.contains_key(&at)
}

fn from_text(
    reading: &Reading,
    policy: &Policy,
    requirement: &Requirement,
    extra: &Problems,
) -> String {
    let Some((name, _)) = policy.subject_of(requirement) else {
        return INVALID_FROM.to_string();
    };
    if !from_readable(reading, name, extra) {
        return INVALID_FROM.to_string();
    }
    reading.infos[name].from_text.clone().unwrap_or_default()
}

fn filters_text(
    reading: &Reading,
    policy: &Policy,
    requirement: &Requirement,
    extra: &Problems,
) -> Option<String> {
    let (name, _) = policy.subject_of(requirement)?;
    let blocked = extra
        .get(&field_name(&["subjects", name, "from"]))
        .is_some_and(|texts| {
            texts
                .iter()
                .any(|text| text != crate::reading::NARROWING_A_CHILD_PROBLEM)
        });
    if blocked {
        return None;
    }
    reading.filters_text(name)
}

#[derive(Debug, Clone, PartialEq)]
pub struct CheckDef {
    pub description: String,
    pub meta: Value,
    pub expression: String,
    pub refs: Vec<Value>,
}

impl CheckDef {
    fn added(description: String, expression: String) -> CheckDef {
        CheckDef {
            description,
            meta: json!({}),
            expression,
            refs: Vec::new(),
        }
    }

    fn to_json(&self) -> Value {
        let mut def = Map::new();
        def.insert("description".to_string(), json!(self.description));
        def.insert("expression".to_string(), json!(self.expression));
        def.insert("meta".to_string(), self.meta.clone());
        if !self.refs.is_empty() {
            def.insert("$refs".to_string(), Value::Array(self.refs.clone()));
        }
        Value::Object(def)
    }
}

fn ancestor_def(
    reading: &Reading,
    policy: &Policy,
    requirement: &Requirement,
    extra: &Problems,
    input: &Value,
    params: &Value,
) -> Option<CheckDef> {
    let (name, _) = policy.subject_of(requirement)?;
    let mut levels: Vec<String> = Vec::new();
    let mut at = name.to_string();
    while levels.len() < 2 && from_readable(reading, &at, extra) {
        let Some(crate::reading::Relation::Child(parent)) = reading
            .infos
            .get(at.as_str())
            .map(|info| info.relation.clone())
        else {
            break;
        };
        levels.insert(0, parent.clone());
        at = parent;
    }
    if levels.is_empty() {
        return None;
    }
    let mut descriptions = Vec::new();
    let mut expressions = Vec::new();
    let mut refs: Vec<Value> = Vec::new();
    for (at, level) in levels.iter().enumerate() {
        let every = if at == 0 { "Every" } else { "every" };
        descriptions.push(format!("{every} {level} id is unique"));
        let from = if from_readable(reading, level, extra) {
            refs.extend(crate::checks::refs_read(
                &reading.source_refs(level),
                input,
                params.as_object().map(|_| params),
            ));
            reading.infos[level].from_text.clone().unwrap_or_default()
        } else {
            INVALID_FROM.to_string()
        };
        expressions.push(format!("count(repeated(ids({from}))) == 0"));
    }
    refs.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    refs.dedup();
    let mut def = CheckDef::added(descriptions.join(" and "), expressions.join(" and "));
    def.refs = refs;
    Some(def)
}

pub fn check_defs(
    reading: &Reading,
    policy: &Policy,
    requirement: &Requirement,
    extra: &Problems,
    input: &Value,
    params: &Value,
) -> BTreeMap<String, CheckDef> {
    let expressions = crate::checks::read_checks(reading, requirement);
    let mut defs: BTreeMap<String, CheckDef> = requirement
        .checks
        .iter()
        .filter(|(name, _)| !name.starts_with('$'))
        .map(|(name, check)| {
            (
                name.clone(),
                CheckDef {
                    description: check.description.clone(),
                    meta: check.meta.clone(),
                    expression: expressions
                        .get(name)
                        .map_or_else(|| written_expression(check), |read| read.expression.clone()),
                    refs: expressions
                        .get(name)
                        .and_then(|read| read.plan.as_ref())
                        .map(|plan| crate::checks::refs_of(plan, input, Some(params)))
                        .unwrap_or_default(),
                },
            )
        })
        .collect();
    let kind = type_text(&subject_type(requirement));
    let from = from_text(reading, policy, requirement, extra);
    let min = crate::value::literal_text(&requirement.min_subjects);
    let keyed = policy.subject_of(requirement).is_some_and(|(name, _)| {
        matches!(
            reading.lowered(name).map(|lowered| &lowered.source),
            Some(
                Source::Root {
                    each_of: Some(_),
                    ..
                } | Source::Child {
                    each_of: Some(_),
                    ..
                }
            )
        )
    });
    let (min_description, min_expression) = if is_zero(&requirement.min_subjects) && !keyed {
        (
            format!("The {kind} list can be read"),
            format!("{from} can be read"),
        )
    } else {
        (
            format!("The in-scope {kind} count is at least {min}"),
            format!("count(matching({from})) >= {min}"),
        )
    };
    let from_refs = match policy.subject_of(requirement) {
        Some((name, _)) if from_readable(reading, name, extra) => crate::checks::refs_read(
            &reading.source_refs(name),
            input,
            params.as_object().map(|_| params),
        ),
        _ => Vec::new(),
    };
    let mut min_def = CheckDef::added(min_description, min_expression);
    min_def.refs.clone_from(&from_refs);
    defs.insert("$min_subjects".to_string(), min_def);
    let mut unique_def = CheckDef::added(
        format!("Every {kind} id is unique"),
        format!("count(repeated(ids({from}))) == 0"),
    );
    unique_def.refs = from_refs;
    defs.insert("$unique_ids".to_string(), unique_def);
    if let Some(def) = ancestor_def(reading, policy, requirement, extra, input, params) {
        defs.insert("$unique_ancestor_ids".to_string(), def);
    }
    defs.insert(
        "$well_formed".to_string(),
        CheckDef::added(
            "The requirement is written correctly".to_string(),
            "count(problems) == 0".to_string(),
        ),
    );
    match filters_text(reading, policy, requirement, extra) {
        Some(filters) => {
            let mut applies_def = CheckDef::added(format!("The {kind} is in scope"), filters);
            if let Some((name, _)) = policy.subject_of(requirement)
                && let Some(lowered) = reading.lowered(name)
            {
                let checks: Vec<&crate::ops::Check> =
                    lowered.filters.iter().map(|f| &f.check).collect();
                applies_def.refs = crate::checks::refs_of_checks(
                    &checks,
                    input,
                    params.as_object().map(|_| params),
                );
            }
            defs.insert("$applies".to_string(), applies_def);
        }
        None => {
            defs.remove("$applies");
        }
    }
    defs
}

pub fn requirement_problems(requirement: &Requirement, extra: Option<&Problems>) -> Problems {
    let mut problems = requirement.problems.clone();
    if let Some(extra) = extra {
        merge_problems(&mut problems, extra);
    }
    problems
}

pub fn well_formed_row(
    policy: &Policy,
    requirement_name: &str,
    requirement: &Requirement,
    extra: Option<&Problems>,
) -> Row {
    let problems = requirement_problems(requirement, extra);
    let name_problems = crate::policy::written_name_problems(requirement_name);
    let reserved = !name_problems.is_empty();
    let mut inputs = Vec::new();
    if reserved {
        inputs.push(input("requirement name", json!(name_problems), &[]));
    }
    inputs.push(input("count(checks)", json!(requirement.checks_count), &[]));
    let require_wrong = problems.contains_key("require");
    inputs.push(if require_wrong {
        input("require", json!(["neither every nor some"]), &[])
    } else {
        input("require", requirement.require.clone(), &[])
    });
    if let Some(raw) = &requirement.not_an_object {
        inputs.push(input("requirement", raw.clone(), &[]));
    }
    let mut listed: Vec<(&String, &std::collections::BTreeSet<String>)> = problems.iter().collect();
    listed.sort_by_key(|(name, _)| {
        let group = if name.starts_with(LISTED_LAST) {
            3
        } else if name.starts_with("checks.") {
            2
        } else {
            u8::from(name.starts_with("subjects."))
        };
        (group, name.as_str())
    });
    for (name, texts) in listed {
        if name == "require" {
            continue;
        }
        inputs.push(input(
            name.trim_start_matches(LISTED_LAST),
            json!(texts),
            &[],
        ));
    }
    for (name, texts) in &policy.problems {
        inputs.push(input(name, json!(texts), &[]));
    }
    let failed = reserved
        || !problems.is_empty()
        || !policy.problems.is_empty()
        || requirement.not_an_object.is_some();
    let cause = if failed {
        Cause::Value
    } else {
        Cause::Satisfied
    };
    let mut row = row_of(requirement_name, requirement, "$well_formed", cause, inputs);
    if failed {
        row.message = Some(problems_message(&row.inputs));
    }
    row
}

fn problems_message(inputs: &[Value]) -> String {
    let lines: Vec<String> = inputs
        .iter()
        .flat_map(|entry| {
            let name = entry["name"].as_str().unwrap_or_default().to_string();
            entry["value"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .map(|text| format!("{name}: {text}"))
                .collect::<Vec<String>>()
        })
        .collect();
    if lines.is_empty() {
        "the policy isn't written correctly".to_string()
    } else {
        lines.join("; ")
    }
}

pub fn status(
    requirement: &Requirement,
    well_formed: &Row,
    evaluation: &Evaluation,
) -> &'static str {
    if !well_formed.passed() {
        return "not_met";
    }
    let scope_unreadable = evaluation
        .applies
        .iter()
        .any(|row| !row.passed() && row.cause != Cause::Value);
    let counts_failed = evaluation
        .min_subjects
        .iter()
        .chain(&evaluation.unique_ids)
        .chain(&evaluation.unique_ancestor_ids)
        .any(|row| !row.passed());
    if scope_unreadable || counts_failed {
        return "not_met";
    }
    let checks_hold = match requirement.require.as_str() {
        Some("some") => {
            let keys: BTreeSet<String> = evaluation
                .subject_rows
                .iter()
                .filter(|rows| !rows.is_empty())
                .map(|rows| parent_key(&rows[0]))
                .collect();
            keys.is_subset(&passing_parents(requirement, evaluation))
        }
        _ => evaluation
            .subject_rows
            .iter()
            .all(|rows| rows.iter().all(Row::passed)),
    };
    if !checks_hold {
        "not_met"
    } else if evaluation.matching == 0 {
        "not_applicable"
    } else {
        "met"
    }
}

fn parent_key(row: &Row) -> String {
    match &row.subject_in {
        Some(parents) if !parents.is_empty() => {
            crate::value::plain(&Value::Object(parents.clone())).to_string()
        }
        _ => String::new(),
    }
}

fn passing_parents(requirement: &Requirement, evaluation: &Evaluation) -> BTreeSet<String> {
    if requirement.require.as_str() != Some("some") {
        return BTreeSet::new();
    }
    evaluation
        .subject_rows
        .iter()
        .filter(|rows| !rows.is_empty() && rows.iter().all(Row::passed))
        .map(|rows| parent_key(&rows[0]))
        .collect()
}

fn causes(
    status: &str,
    requirement: &Requirement,
    well_formed: &Row,
    evaluation: &Evaluation,
) -> Value {
    if status != "not_met" {
        return json!([]);
    }
    let mut shadowing = passing_parents(requirement, evaluation);
    shadowing.remove("");
    let rows = std::iter::once(well_formed)
        .chain(&evaluation.min_subjects)
        .chain(&evaluation.unique_ids)
        .chain(&evaluation.unique_ancestor_ids)
        .chain(&evaluation.applies)
        .chain(evaluation.subject_rows.iter().flatten());
    let mut counts: BTreeMap<Cause, u64> = BTreeMap::new();
    for row in rows {
        if row.passed() || (row.check == "$applies" && row.cause == Cause::Value) {
            continue;
        }
        if !row.check.starts_with('$') && shadowing.contains(&parent_key(row)) {
            continue;
        }
        *counts.entry(row.cause).or_default() += 1;
    }
    Value::Array(
        counts
            .into_iter()
            .map(|(cause, rows)| json!({"cause": cause.name(), "rows": rows}))
            .collect(),
    )
}

fn subject_entry(reading: &Reading, name: &str, extra: &Problems) -> Value {
    let Some(info) = reading.infos.get(name) else {
        return json!({
            "description": "",
            "from": INVALID_FROM,
            "identified_by": null,
            "parts": {},
        });
    };
    let mut entry = info.entry.clone();
    if extra.contains_key(&field_name(&["subjects", name, "from"])) {
        entry["from"] = json!(INVALID_FROM);
    }
    let follows_parent = matches!(
        &info.relation,
        crate::reading::Relation::Narrows(parent) if !parent.trim().is_empty()
    );
    let id_unreadable = extra
        .get(&field_name(&["subjects", name, "identified_by"]))
        .is_some_and(|texts| {
            texts
                .iter()
                .any(|text| text != crate::reading::KEYED_ID_PROBLEM)
        });
    if id_unreadable && !follows_parent {
        entry["identified_by"] = json!(crate::reading::INVALID_IDENTIFIED_BY);
    }
    entry
}

fn engine() -> Value {
    json!({"name": "ergo-rust", "version": env!("CARGO_PKG_VERSION")})
}

#[cfg(test)]
pub fn assemble(
    policy: &Policy,
    extra: &BTreeMap<String, Problems>,
    evaluations: &BTreeMap<String, Evaluation>,
    params: &Value,
) -> Value {
    assemble_with(
        policy,
        &Reading::of(policy),
        extra,
        evaluations,
        &Value::Null,
        params,
    )
}

pub fn assemble_with(
    policy: &Policy,
    reading: &Reading,
    extra: &BTreeMap<String, Problems>,
    evaluations: &BTreeMap<String, Evaluation>,
    input: &Value,
    params: &Value,
) -> Value {
    let mut requirements = Map::new();
    let mut well_formed_rows = Vec::new();
    let mut min_rows = Vec::new();
    let mut unique_rows = Vec::new();
    let mut ancestor_rows = Vec::new();
    let mut applies_rows = Vec::new();
    let mut check_rows = Vec::new();
    let mut subjects = Map::new();
    let mut compliant = !policy.requirements.is_empty();
    for (name, requirement) in &policy.requirements {
        let mut combined = reading.problems_of(policy, requirement);
        if let Some(given) = extra.get(name) {
            merge_problems(&mut combined, given);
        }
        let extra_problems = &combined;
        let well_formed = well_formed_row(policy, name, requirement, Some(extra_problems));
        let evaluation = if well_formed.passed() {
            evaluations
                .get(name)
                .cloned()
                .unwrap_or_else(|| no_subjects(name, requirement, params))
        } else {
            Evaluation::default()
        };
        let status = status(requirement, &well_formed, &evaluation);
        if status == "not_met" {
            compliant = false;
        }
        let defs = check_defs(reading, policy, requirement, extra_problems, input, params);
        let reported_subject = policy.subject_of(requirement).map(|(n, _)| n);
        requirements.insert(
            name.clone(),
            json!({
                "description": requirement.description,
                "meta": requirement.meta,
                "require": requirement.require,
                "subject": reported_subject,
                "status": status,
                "causes": causes(status, requirement, &well_formed, &evaluation),
                "subjects": {"total": evaluation.total, "matching": evaluation.matching},
                "checks": defs
                    .iter()
                    .map(|(n, def)| (n.clone(), def.to_json()))
                    .collect::<Map<String, Value>>(),
            }),
        );
        if let SubjectName::Named(subject_name) = &requirement.subject
            && policy.subject_of(requirement).is_some()
        {
            for used in reading.listed(subject_name) {
                subjects.insert(used.clone(), subject_entry(reading, &used, extra_problems));
            }
            subjects
                .entry(subject_name.clone())
                .or_insert_with(|| subject_entry(reading, subject_name, extra_problems));
        }
        well_formed_rows.push(well_formed);
        min_rows.extend(evaluation.min_subjects);
        unique_rows.extend(evaluation.unique_ids);
        ancestor_rows.extend(evaluation.unique_ancestor_ids);
        applies_rows.extend(evaluation.applies);
        check_rows.extend(evaluation.subject_rows.into_iter().flatten());
    }
    if policy.requirements.is_empty() {
        requirements.insert("$policy".to_string(), policy_requirement());
        well_formed_rows.push(policy_row(policy));
    }
    let results: Vec<Value> = well_formed_rows
        .iter()
        .chain(&min_rows)
        .chain(&unique_rows)
        .chain(&ancestor_rows)
        .chain(&applies_rows)
        .chain(&check_rows)
        .map(Row::to_json)
        .collect();
    json!({
        "ergo": SPEC,
        "engine": engine(),
        "compliant": compliant,
        "description": policy.description,
        "meta": policy.meta,
        "requirements": requirements,
        "results": results,
        "subjects": subjects,
    })
}

pub const POLICY: &str = "$policy";

fn policy_requirement() -> Value {
    json!({
        "description": "",
        "meta": {},
        "require": "every",
        "subject": POLICY,
        "status": "not_met",
        "causes": [{"cause": "value", "rows": 1}],
        "subjects": {"total": 0, "matching": 0},
        "checks": {"$well_formed": {
            "description": "The policy is written correctly",
            "expression": "count(problems) == 0",
            "meta": {},
        }},
    })
}

fn policy_row(policy: &Policy) -> Row {
    let mut named: Vec<(String, Value)> = policy
        .problems
        .iter()
        .map(|(name, texts)| (name.clone(), json!(texts)))
        .collect();
    if !policy.requirements_problem.is_empty() {
        named.push((
            "requirements".to_string(),
            json!([policy.requirements_problem]),
        ));
    }
    named.sort_by(|a, b| a.0.cmp(&b.0));
    let inputs: Vec<Value> = named
        .into_iter()
        .map(|(name, value)| input(&name, value, &[]))
        .collect();
    let message = Some(problems_message(&inputs));
    Row {
        requirement: POLICY.to_string(),
        subject_type: json!(POLICY),
        subject_id: json!(POLICY),
        subject_in: None,
        check: "$well_formed".to_string(),
        cause: Cause::Value,
        inputs,
        message,
        failed_items: None,
        failed_assertions: None,
    }
}

fn is_holding(report: &Value, requirement: &Value) -> bool {
    let status = report
        .get("requirements")
        .and_then(|requirements| requirements.get(requirement.as_str().unwrap_or("")))
        .and_then(|entry| entry.get("status"))
        .and_then(Value::as_str);
    matches!(status, Some("met") | Some("not_applicable"))
}

fn child_check_key(report: &Value, row: &Value) -> Option<(String, String, String)> {
    let check = row.get("check").and_then(Value::as_str)?;
    if check.starts_with('$') {
        return None;
    }
    let requirement = row.get("requirement").and_then(Value::as_str)?;
    let require = report
        .get("requirements")?
        .get(requirement)?
        .get("require")?
        .as_str()?;
    if require != "some" {
        return None;
    }
    let subject = row.get("subject")?;
    let parents = subject.get("in")?.as_object().filter(|m| !m.is_empty())?;
    Some((
        requirement.to_string(),
        Value::Object(parents.clone()).to_string(),
        subject.to_string(),
    ))
}

fn shadowing_parents(report: &Value, results: &[Value]) -> BTreeSet<(String, String)> {
    let mut subjects: BTreeMap<(String, String, String), bool> = BTreeMap::new();
    for row in results {
        if let Some(key) = child_check_key(report, row) {
            let passed = row.get("passed") != Some(&Value::Bool(false));
            let entry = subjects.entry(key).or_insert(true);
            *entry = *entry && passed;
        }
    }
    subjects
        .into_iter()
        .filter(|(_, passed)| *passed)
        .map(|((requirement, parents, _), _)| (requirement, parents))
        .collect()
}

pub fn violations(report: &Value) -> Value {
    let empty = Vec::new();
    let results = report
        .get("results")
        .and_then(Value::as_array)
        .unwrap_or(&empty);
    let shadowing = shadowing_parents(report, results);
    let mut out = Vec::new();
    for row in results {
        if row.get("passed") != Some(&Value::Bool(false)) {
            continue;
        }
        if let Some((requirement, parents, _)) = child_check_key(report, row)
            && shadowing.contains(&(requirement, parents))
        {
            continue;
        }
        let check = row.get("check").cloned().unwrap_or(Value::Null);
        if check == json!("$applies") && row.get("cause") == Some(&json!("value")) {
            continue;
        }
        let requirement = row.get("requirement").cloned().unwrap_or(Value::Null);
        if is_holding(report, &requirement) {
            continue;
        }
        let definition = report
            .get("requirements")
            .and_then(|requirements| requirements.get(requirement.as_str().unwrap_or("")))
            .and_then(|entry| entry.get("checks"))
            .and_then(|checks| checks.get(check.as_str().unwrap_or("")));
        let field = |key: &str| {
            definition
                .and_then(|def| def.get(key))
                .cloned()
                .unwrap_or_else(|| json!(""))
        };
        let mut inputs = row
            .get("inputs")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        if let Some(refs) = definition
            .and_then(|def| def.get("$refs"))
            .and_then(Value::as_array)
        {
            let listed = inputs.clone();
            inputs.extend(refs.iter().filter(|r| !listed.contains(r)).cloned());
        }
        let mut violation = Map::new();
        violation.insert("requirement".to_string(), requirement);
        violation.insert(
            "subject".to_string(),
            row.get("subject").cloned().unwrap_or(Value::Null),
        );
        violation.insert("check".to_string(), check);
        violation.insert("description".to_string(), field("description"));
        violation.insert("expression".to_string(), field("expression"));
        violation.insert("inputs".to_string(), Value::Array(inputs));
        violation.insert(
            "cause".to_string(),
            row.get("cause").cloned().unwrap_or(Value::Null),
        );
        for key in ["message", "failed_items", "failed_assertions"] {
            if let Some(value) = row.get(key) {
                violation.insert(key.to_string(), value.clone());
            }
        }
        out.push(Value::Object(violation));
    }
    Value::Array(out)
}

#[cfg(test)]
mod tests;
