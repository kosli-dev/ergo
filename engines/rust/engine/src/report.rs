use crate::cause::Cause;
use crate::policy::{
    Check, Form, OptionLines, Policy, Problems, Requirement, SPEC, SubjectName, field_name,
    merge_problems,
};
use crate::reading::{INVALID_FROM, Reading, Source};
use crate::value::{Decimal, json_text};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub requirement: String,
    pub subject_type: Value,
    pub subject_id: Value,
    pub subject_in: Option<Map<String, Value>>,
    pub check: String,
    pub cause: Cause,
    pub inputs: Vec<Value>,
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
    row_of(
        requirement_name,
        requirement,
        "$min_subjects",
        cause,
        inputs,
    )
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
    row_of(
        requirement_name,
        requirement,
        "$unique_ids",
        cause,
        vec![input(&label, Value::Array(repeated), locations)],
    )
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
                        .map(|plan| {
                            crate::checks::refs_of(plan, input, params.as_object().map(|_| params))
                        })
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
    defs.insert(
        "$well_formed".to_string(),
        CheckDef::added(
            "The requirement is written correctly".to_string(),
            "count(problems) == 0".to_string(),
        ),
    );
    match filters_text(reading, policy, requirement, extra) {
        Some(filters) => {
            defs.insert(
                "$applies".to_string(),
                CheckDef::added(format!("The {kind} is in scope"), filters),
            );
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
    let mut inputs = vec![input("count(checks)", json!(requirement.checks_count), &[])];
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
    listed.sort_by_key(|(name, _)| (name.starts_with("checks."), name.replace('"', "")));
    for (name, texts) in listed {
        if name == "require" {
            continue;
        }
        inputs.push(input(name, json!(texts), &[]));
    }
    for (name, texts) in &policy.problems {
        inputs.push(input(name, json!(texts), &[]));
    }
    let failed =
        !problems.is_empty() || !policy.problems.is_empty() || requirement.not_an_object.is_some();
    let cause = if failed {
        Cause::Value
    } else {
        Cause::Satisfied
    };
    row_of(requirement_name, requirement, "$well_formed", cause, inputs)
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
        .any(|row| !row.passed());
    if scope_unreadable || counts_failed {
        return "not_met";
    }
    let checks_hold = match requirement.require.as_str() {
        Some("some") => {
            evaluation.subject_rows.is_empty()
                || evaluation
                    .subject_rows
                    .iter()
                    .any(|rows| rows.iter().all(Row::passed))
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

fn causes(status: &str, well_formed: &Row, evaluation: &Evaluation) -> Value {
    if status != "not_met" {
        return json!([]);
    }
    let rows = std::iter::once(well_formed)
        .chain(&evaluation.min_subjects)
        .chain(&evaluation.unique_ids)
        .chain(&evaluation.applies)
        .chain(evaluation.subject_rows.iter().flatten());
    let mut counts: BTreeMap<Cause, u64> = BTreeMap::new();
    for row in rows {
        if row.passed() || (row.check == "$applies" && row.cause == Cause::Value) {
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
    json!({"name": "ergo-policy-engine", "version": env!("CARGO_PKG_VERSION")})
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
                "causes": causes(status, &well_formed, &evaluation),
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
        applies_rows.extend(evaluation.applies);
        check_rows.extend(evaluation.subject_rows.into_iter().flatten());
    }
    let results: Vec<Value> = well_formed_rows
        .iter()
        .chain(&min_rows)
        .chain(&unique_rows)
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

fn is_holding(report: &Value, requirement: &Value) -> bool {
    let status = report
        .get("requirements")
        .and_then(|requirements| requirements.get(requirement.as_str().unwrap_or("")))
        .and_then(|entry| entry.get("status"))
        .and_then(Value::as_str);
    matches!(status, Some("met") | Some("not_applicable"))
}

pub fn violations(report: &Value) -> Value {
    let empty = Vec::new();
    let results = report
        .get("results")
        .and_then(Value::as_array)
        .unwrap_or(&empty);
    let mut out = Vec::new();
    for row in results {
        if row.get("passed") != Some(&Value::Bool(false)) {
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
            inputs.extend(refs.iter().cloned());
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
        for key in ["failed_items", "failed_assertions"] {
            if let Some(value) = row.get(key) {
                violation.insert(key.to_string(), value.clone());
            }
        }
        out.push(Value::Object(violation));
    }
    Value::Array(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy::Policy;

    fn policy(requirements: Value) -> Value {
        json!({
            "ergo_spec": "v0.3-dev",
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": requirements,
        })
    }

    fn report_of(policy: Value, params: Value) -> Value {
        let read = Policy::read(&policy);
        assemble(&read, &BTreeMap::new(), &BTreeMap::new(), &params)
    }

    fn row_of_check<'a>(report: &'a Value, requirement: &str, check: &str) -> &'a Value {
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["requirement"] == requirement && r["check"] == check)
            .unwrap()
    }

    fn row(requirement: &str, check: &str, cause: Cause) -> Row {
        Row {
            requirement: requirement.to_string(),
            subject_type: json!("thing"),
            subject_id: json!(1),
            subject_in: None,
            check: check.to_string(),
            cause,
            inputs: vec![input("x", json!(1), &["/t/0/x".to_string()])],
            failed_items: None,
            failed_assertions: None,
        }
    }

    fn requirement_of(value: Value) -> (Policy, Requirement) {
        let read = Policy::read(&policy(json!({"s": value})));
        let requirement = read.requirements["s"].clone();
        (read, requirement)
    }

    fn good() -> Value {
        json!({"subject": "thing", "checks": {"c": "x exists"}})
    }

    #[test]
    fn a_row_prints_as_the_schema_wants() {
        let mut r = row("s", "c", Cause::Value);
        r.subject_in = Some(Map::from_iter([("artifact".to_string(), json!("sha-1"))]));
        r.failed_items = Some(json!([]));
        r.failed_assertions = Some(json!([{"assertion": "a", "cause": "value"}]));
        assert_eq!(
            r.to_json(),
            json!({
                "requirement": "s",
                "subject": {"type": "thing", "id": 1, "in": {"artifact": "sha-1"}},
                "check": "c",
                "passed": false,
                "cause": "value",
                "inputs": [{"name": "x", "value": 1, "locations": ["/t/0/x"]}],
                "failed_items": [],
                "failed_assertions": [{"assertion": "a", "cause": "value"}],
            })
        );
    }

    #[test]
    fn a_row_passes_only_with_the_cause_satisfied() {
        assert!(row("s", "c", Cause::Satisfied).passed());
        for cause in [
            Cause::NotAnObject,
            Cause::Ambiguous,
            Cause::Unusable,
            Cause::Absent,
            Cause::Null,
            Cause::Value,
        ] {
            assert!(!row("s", "c", cause).passed());
        }
        assert_eq!(
            row("s", "c", Cause::Satisfied).to_json()["passed"],
            json!(true)
        );
    }

    #[test]
    fn a_row_without_a_parent_has_no_in() {
        assert!(
            row("s", "c", Cause::Value).to_json()["subject"]
                .get("in")
                .is_none()
        );
        assert!(
            row("s", "c", Cause::Value)
                .to_json()
                .get("failed_items")
                .is_none()
        );
    }

    #[test]
    fn a_requirement_written_right_has_a_satisfied_well_formed_row_of_count_and_require() {
        let (read, requirement) = requirement_of(good());
        let well_formed = well_formed_row(&read, "s", &requirement, None);
        assert_eq!(
            well_formed.to_json(),
            json!({
                "requirement": "s",
                "subject": {"type": "thing", "id": null},
                "check": "$well_formed",
                "passed": true,
                "cause": "satisfied",
                "inputs": [
                    {"name": "count(checks)", "value": 1, "locations": []},
                    {"name": "require", "value": "every", "locations": []}
                ],
            })
        );
    }

    #[test]
    fn well_formed_lists_count_and_require_then_field_problems_then_check_problems_sorted_by_name()
    {
        let (read, requirement) = requirement_of(json!({
            "subject": "thing",
            "checks": {"c": {"op": "x"}, "a": 5},
            "zz": 1,
            "aa": 2
        }));
        let row = well_formed_row(&read, "s", &requirement, None);
        let names: Vec<_> = row.inputs.iter().map(|i| i["name"].clone()).collect();
        assert_eq!(
            names,
            [
                "count(checks)",
                "require",
                "aa",
                "zz",
                "checks.a",
                "checks.c"
            ]
        );
        assert_eq!(row.cause, Cause::Value);
    }

    #[test]
    fn a_wrong_require_stays_second_whatever_the_other_problems_are() {
        let (read, requirement) = requirement_of(json!({
            "subject": "thing",
            "require": "most",
            "checks": {"c": "x exists"},
            "aa": 1
        }));
        let row = well_formed_row(&read, "s", &requirement, None);
        assert_eq!(
            row.inputs,
            [
                input("count(checks)", json!(1), &[]),
                input("require", json!(["neither every nor some"]), &[]),
                input("aa", json!(["unknown field"]), &[]),
            ]
        );
    }

    #[test]
    fn policy_problems_come_last_and_fail_every_requirement() {
        let mut p = policy(json!({"s": good(), "t": good()}));
        p["ergo_spec"] = json!(1);
        p["description"] = json!(5);
        p["meta"] = json!("m");
        p["requirements"]["t"]["zz"] = json!(1);
        let report = report_of(p, Value::Null);
        for name in ["s", "t"] {
            let row = row_of_check(&report, name, "$well_formed");
            assert_eq!(row["passed"], json!(false));
            let tail: Vec<_> = row["inputs"]
                .as_array()
                .unwrap()
                .iter()
                .rev()
                .take(3)
                .map(|i| i["name"].as_str().unwrap().to_string())
                .collect();
            assert_eq!(
                tail,
                ["policy meta", "policy ergo_spec", "policy description"]
            );
        }
        let inputs = row_of_check(&report, "t", "$well_formed")["inputs"].clone();
        assert_eq!(
            inputs[2],
            json!({"name": "zz", "value": ["unknown field"], "locations": []})
        );
        assert_eq!(report["description"], json!(""));
        assert_eq!(report["meta"], json!({}));
    }

    #[test]
    fn extra_problems_given_for_a_requirement_fail_its_well_formed_row_and_nothing_else() {
        let read = Policy::read(&policy(json!({"s": good(), "t": good()})));
        let mut extra = BTreeMap::new();
        let mut problems = Problems::new();
        crate::policy::add_problem(&mut problems, "checks.c".to_string(), "doesn't parse");
        extra.insert("s".to_string(), problems);
        let report = assemble(&read, &extra, &BTreeMap::new(), &Value::Null);
        let s = row_of_check(&report, "s", "$well_formed");
        assert_eq!(s["passed"], json!(false));
        assert_eq!(
            s["inputs"][2],
            json!({"name": "checks.c", "value": ["doesn't parse"], "locations": []})
        );
        assert_eq!(
            row_of_check(&report, "t", "$well_formed")["passed"],
            json!(true)
        );
        assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
    }

    #[test]
    fn a_requirement_that_is_not_an_object_lists_what_was_written() {
        let report = report_of(policy(json!({"s": "x"})), Value::Null);
        let row = row_of_check(&report, "s", "$well_formed");
        assert_eq!(row["passed"], json!(false));
        assert_eq!(
            row["inputs"],
            json!([
                {"name": "count(checks)", "value": 0, "locations": []},
                {"name": "require", "value": "every", "locations": []},
                {"name": "requirement", "value": "x", "locations": []}
            ])
        );
        assert_eq!(row["subject"], json!({"type": "subject", "id": null}));
        assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
    }

    #[test]
    fn a_requirement_written_wrong_gets_only_its_well_formed_row() {
        let report = report_of(
            policy(
                json!({"bad": {"subject": "thing", "require": "most", "checks": {"c": "x exists"}}}),
            ),
            Value::Null,
        );
        let results = report["results"].as_array().unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0]["check"], json!("$well_formed"));
        let entry = &report["requirements"]["bad"];
        assert_eq!(entry["status"], json!("not_met"));
        assert_eq!(entry["subjects"], json!({"total": 0, "matching": 0}));
        assert_eq!(entry["require"], json!("most"));
        assert_eq!(entry["causes"], json!([{"cause": "value", "rows": 1}]));
        assert_eq!(report["compliant"], json!(false));
    }

    #[test]
    fn a_written_wrong_requirement_still_lists_every_check_and_the_ones_ergo_adds() {
        let report = report_of(
            policy(json!({"s": {"subject": "thing", "checks": {"c": "x is \"a"}}})),
            Value::Null,
        );
        let checks = &report["requirements"]["s"]["checks"];
        let mut names: Vec<_> = checks.as_object().unwrap().keys().cloned().collect();
        names.sort();
        assert_eq!(names, ["$min_subjects", "$unique_ids", "$well_formed", "c"]);
        assert_eq!(checks["c"]["expression"], json!("x is \"a"));
        assert_eq!(
            checks["$well_formed"]["expression"],
            json!("count(problems) == 0")
        );
        assert_eq!(
            checks["$min_subjects"],
            json!({
                "description": "The in-scope thing count is at least 1",
                "expression": "count(matching(things)) >= 1",
                "meta": {}
            })
        );
        assert_eq!(
            checks["$unique_ids"],
            json!({
                "description": "Every thing id is unique",
                "expression": "count(repeated(ids(things))) == 0",
                "meta": {}
            })
        );
    }

    #[test]
    fn reserved_names_list_only_ergos_own_check() {
        let report = report_of(
            policy(json!({"s": {"subject": "thing", "checks": {
                "$well_formed": "x is 2", "$min_subjects": "x is 2", "$unique_ids": "x is 2", "$applies": "x is 2"
            }}})),
            Value::Null,
        );
        let checks = report["requirements"]["s"]["checks"].as_object().unwrap();
        let mut names: Vec<_> = checks.keys().cloned().collect();
        names.sort();
        assert_eq!(names, ["$min_subjects", "$unique_ids", "$well_formed"]);
        assert_eq!(
            checks["$well_formed"]["expression"],
            json!("count(problems) == 0")
        );
        let row = row_of_check(&report, "s", "$well_formed");
        assert_eq!(row["inputs"][0]["value"], json!(4));
    }

    #[test]
    fn a_requirement_with_no_checks_says_empty() {
        let report = report_of(
            policy(json!({"s": {"subject": "thing", "checks": {}}})),
            Value::Null,
        );
        let row = row_of_check(&report, "s", "$well_formed");
        assert_eq!(
            row["inputs"],
            json!([
                {"name": "count(checks)", "value": 0, "locations": []},
                {"name": "require", "value": "every", "locations": []},
                {"name": "checks", "value": ["empty"], "locations": []}
            ])
        );
    }

    #[test]
    fn a_requirement_with_no_subject_names_none_and_types_its_rows_subject() {
        let report = report_of(
            policy(json!({"s": {"checks": {"c": "x exists"}}})),
            Value::Null,
        );
        let row = row_of_check(&report, "s", "$well_formed");
        assert_eq!(row["subject"], json!({"type": "subject", "id": null}));
        assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
        assert_eq!(
            report["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
            json!("count(matching(<invalid from>)) >= 1")
        );
        assert_eq!(report["subjects"], json!({}));
    }

    #[test]
    fn a_subject_that_is_not_in_subjects_is_typed_as_written_and_named_null() {
        let report = report_of(
            policy(json!({"s": {"subject": "nope", "checks": {"c": "x exists"}}})),
            Value::Null,
        );
        assert_eq!(
            row_of_check(&report, "s", "$well_formed")["subject"]["type"],
            json!("nope")
        );
        assert_eq!(report["requirements"]["s"]["subject"], Value::Null);
        assert_eq!(
            row_of_check(&report, "s", "$well_formed")["inputs"][2],
            json!({"name": "subject", "value": ["not in subjects"], "locations": []})
        );
    }

    #[test]
    fn requirements_come_in_name_order_in_each_group_of_rows() {
        let report = report_of(
            policy(json!({"b": good(), "a": good(), "B": good()})),
            Value::Null,
        );
        let order: Vec<_> = report["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| {
                format!(
                    "{}:{}",
                    r["requirement"].as_str().unwrap(),
                    r["check"].as_str().unwrap()
                )
            })
            .collect();
        assert_eq!(
            order,
            [
                "B:$well_formed",
                "a:$well_formed",
                "b:$well_formed",
                "B:$min_subjects",
                "a:$min_subjects",
                "b:$min_subjects",
                "B:$unique_ids",
                "a:$unique_ids",
                "b:$unique_ids",
            ]
        );
    }

    #[test]
    fn a_requirement_the_stub_finds_nothing_for_fails_min_subjects_as_value() {
        let report = report_of(policy(json!({"s": good()})), Value::Null);
        let row = row_of_check(&report, "s", "$min_subjects");
        assert_eq!(row["cause"], json!("value"));
        assert_eq!(
            row["inputs"],
            json!([{"name": "in-scope thing count", "value": 0, "locations": []}])
        );
        assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
        assert_eq!(report["compliant"], json!(false));
    }

    #[test]
    fn min_subjects_zero_with_nothing_found_is_not_applicable_and_describes_reading_the_list() {
        let report = report_of(
            policy(
                json!({"s": {"subject": "thing", "min_subjects": 0, "checks": {"c": "x exists"}}}),
            ),
            Value::Null,
        );
        assert_eq!(
            report["requirements"]["s"]["status"],
            json!("not_applicable")
        );
        assert_eq!(report["compliant"], json!(true));
        assert_eq!(
            report["requirements"]["s"]["checks"]["$min_subjects"],
            json!({"description": "The thing list can be read", "expression": "things can be read", "meta": {}})
        );
    }

    #[test]
    fn params_that_are_not_an_object_fail_min_subjects_as_unusable_and_say_why() {
        for params in [json!("p"), json!([]), json!(1), json!(true)] {
            let report = report_of(
                policy(
                    json!({"s": {"subject": "thing", "min_subjects": 0, "checks": {"c": "x exists"}}}),
                ),
                params,
            );
            let row = row_of_check(&report, "s", "$min_subjects");
            assert_eq!(row["cause"], json!("unusable"));
            assert_eq!(
                row["inputs"][1],
                json!({"name": "$params", "value": ["not an object"], "locations": []})
            );
            assert_eq!(report["requirements"]["s"]["status"], json!("not_met"));
        }
        for params in [Value::Null, json!({})] {
            assert!(unreadable_params(&params).is_empty());
        }
    }

    #[test]
    fn a_policy_with_no_requirements_is_never_compliant() {
        let report = report_of(
            json!({"ergo_spec": "v0.3-dev", "subjects": {}, "requirements": {}}),
            Value::Null,
        );
        assert_eq!(report["compliant"], json!(false));
        assert_eq!(report["results"], json!([]));
        assert_eq!(report["requirements"], json!({}));
        let report = report_of(json!(null), Value::Null);
        assert_eq!(report["compliant"], json!(false));
    }

    #[test]
    fn the_report_names_the_spec_version_and_the_engine() {
        let report = report_of(policy(json!({"s": good()})), Value::Null);
        assert_eq!(report["ergo"], json!("v0.3-dev"));
        assert_eq!(
            report["engine"],
            json!({"name": "ergo-policy-engine", "version": env!("CARGO_PKG_VERSION")})
        );
        assert_eq!(report["engine"].as_object().unwrap().len(), 2);
    }

    #[test]
    fn requirement_description_and_meta_are_copied_or_default() {
        let report = report_of(
            policy(json!({
                "s": {"subject": "thing", "description": "Every thing is approved", "meta": {"control": "C-1", "v": 1.5},
                      "checks": {"c": {"assert": "x exists", "description": "Approved", "meta": {"k": 1}}}},
                "t": good()
            })),
            Value::Null,
        );
        assert_eq!(
            report["requirements"]["s"]["description"],
            json!("Every thing is approved")
        );
        assert_eq!(
            report["requirements"]["s"]["meta"],
            json!({"control": "C-1", "v": 1.5})
        );
        assert_eq!(
            report["requirements"]["s"]["checks"]["c"],
            json!({"description": "Approved", "expression": "x exists", "meta": {"k": 1}})
        );
        assert_eq!(report["requirements"]["t"]["description"], json!(""));
        assert_eq!(report["requirements"]["t"]["meta"], json!({}));
        assert_eq!(
            report["requirements"]["t"]["checks"]["c"]["meta"],
            json!({})
        );
    }

    #[test]
    fn a_subject_with_a_filter_gets_an_applies_check_and_a_subject_with_none_does_not() {
        let mut p = policy(json!({"s": good()}));
        p["subjects"]["thing"]["from"] = json!("things whose e exists");
        let report = report_of(p, Value::Null);
        let checks = &report["requirements"]["s"]["checks"];
        assert_eq!(
            checks["$applies"],
            json!({"description": "The thing is in scope", "expression": "e exists", "meta": {}})
        );
        assert_eq!(
            checks["$min_subjects"]["expression"],
            json!("count(matching(things)) >= 1")
        );
        let plain = report_of(policy(json!({"s": good()})), Value::Null);
        assert!(
            plain["requirements"]["s"]["checks"]
                .get("$applies")
                .is_none()
        );
    }

    #[test]
    fn a_subject_without_from_reads_the_field_named_like_it() {
        let mut p = policy(json!({"s": {"subject": "pull request", "checks": {"c": "x exists"}}}));
        p["subjects"] = json!({"pull request": null});
        let report = report_of(p, Value::Null);
        assert_eq!(
            report["requirements"]["s"]["checks"]["$min_subjects"]["expression"],
            json!("count(matching(\"pull request\")) >= 1")
        );
        assert_eq!(
            report["requirements"]["s"]["checks"]["$min_subjects"]["description"],
            json!("The in-scope pull request count is at least 1")
        );
        assert_eq!(
            report["subjects"]["pull request"],
            json!({"description": "", "from": "\"pull request\"", "identified_by": null, "parts": {}})
        );
    }

    #[test]
    fn a_from_that_is_not_a_string_prints_as_invalid() {
        let mut p = policy(json!({"s": good()}));
        p["subjects"]["thing"] = json!({"from": ["a"], "identified_by": ["id"]});
        let report = report_of(p, Value::Null);
        assert_eq!(report["subjects"]["thing"]["from"], json!("<invalid from>"));
        assert_eq!(
            report["subjects"]["thing"]["identified_by"],
            json!("<invalid identified_by>")
        );
        assert_eq!(
            report["requirements"]["s"]["checks"]["$unique_ids"]["expression"],
            json!("count(repeated(ids(<invalid from>))) == 0")
        );
    }

    fn subjects_of(subjects: Value, subject: &str) -> Value {
        let mut p = policy(json!({"s": {"subject": subject, "checks": {"c": "n exists"}}}));
        p["subjects"] = subjects;
        report_of(p, Value::Null)["subjects"].clone()
    }

    fn entry(from: &str, id: Option<&str>) -> Value {
        json!({"description": "", "from": from, "identified_by": id, "parts": {}})
    }

    #[test]
    fn a_subject_with_applies_to_or_of_has_an_invalid_from() {
        let applies = subjects_of(
            json!({"d": {"from": "ds", "identified_by": "id", "applies_to": {"f": {"op": "present", "path": ["x"]}}}}),
            "d",
        );
        assert_eq!(applies["d"], entry("<invalid from>", Some("id")));
        let of = subjects_of(
            json!({"d": {"from": "ds", "identified_by": "id", "of": "ds"}}),
            "d",
        );
        assert_eq!(of["d"], entry("<invalid from>", Some("id")));
    }

    #[test]
    fn a_subject_that_narrows_another_keeps_its_id_when_its_from_is_written_wrong() {
        for line in [
            "parent whose n is one of 1, \"a\"",
            "parent whose n is $foo",
            "every parent",
        ] {
            let found = subjects_of(
                json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": line}}),
                "kid",
            );
            assert_eq!(found["kid"], entry("<invalid from>", Some("id")), "{line}");
            assert_eq!(found["parent"], entry("things", Some("id")), "{line}");
        }
    }

    #[test]
    fn a_subject_that_narrows_another_has_its_id_when_its_from_is_written_wrong_even_with_an_id_of_its_own()
     {
        for line in [
            "every parent",
            "parent whose n is 1",
            "parent whose n is one of 1, \"a\"",
        ] {
            let found = subjects_of(
                json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": line, "identified_by": "n"}}),
                "kid",
            );
            let from = if line == "parent whose n is 1" {
                line
            } else {
                "<invalid from>"
            };
            assert_eq!(found["kid"], entry(from, Some("id")), "{line}");
        }
    }

    #[test]
    fn a_child_whose_from_has_an_unknown_name_lists_the_subject_it_starts_at() {
        let found = subjects_of(
            json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": "parent.items whose zz is $foo", "identified_by": "n"}}),
            "kid",
        );
        assert_eq!(found["kid"], entry("<invalid from>", Some("n")));
        assert_eq!(found["parent"], entry("things", Some("id")));
    }

    #[test]
    fn every_on_a_subject_start_is_one_problem_under_from_and_none_under_identified_by() {
        let mut p = policy(json!({"r": {"subject": "kid", "checks": {"c": "n exists"}}}));
        p["subjects"] = json!({"parent": {"from": "things", "identified_by": "id"}, "kid": {"from": "every parent", "identified_by": "n"}});
        let reading = Reading::of(&Policy::read(&p));
        let problems = &reading.infos["kid"].problems;
        assert_eq!(problems.len(), 1);
        assert!(problems.contains_key("subjects.kid.from"));
    }

    #[test]
    fn a_subject_entry_has_its_description_from_id_and_parts() {
        let mut p = policy(json!({"s": good()}));
        p["subjects"]["thing"] = json!({
            "description": "A thing",
            "from": "  things ",
            "identified_by": " id ",
            "has": {
                "a": "x.y",
                "b": {"from": " x ", "identified_by": "id"},
                "c": {"from": 5, "identified_by": 5},
                "d": 5,
                "e": {"identified_by": "id"}
            }
        });
        let report = report_of(p, Value::Null);
        assert_eq!(
            report["subjects"]["thing"],
            json!({
                "description": "A thing",
                "from": "things",
                "identified_by": "id",
                "parts": {
                    "a": {"from": "x.y", "identified_by": null},
                    "b": {"from": "x", "identified_by": "id"},
                    "c": {"from": "<invalid from>", "identified_by": "<invalid identified_by>"},
                    "d": {"from": "<invalid from>", "identified_by": null},
                    "e": {"from": "<invalid from>", "identified_by": "id"}
                }
            })
        );
    }

    #[test]
    fn a_subject_that_is_written_wrong_still_has_its_entry_and_one_no_requirement_uses_has_none() {
        let mut p = policy(json!({"s": good()}));
        p["subjects"] = json!({"thing": "x", "other": {"from": "t"}});
        let report = report_of(p, Value::Null);
        assert_eq!(
            report["subjects"],
            json!({"thing": {"description": "", "from": "<invalid from>", "identified_by": null, "parts": {}}})
        );
    }

    fn status_of(require: &str, groups: Vec<Vec<Cause>>, matching: u64) -> &'static str {
        let (_, requirement) = requirement_of(
            json!({"subject": "thing", "require": require, "checks": {"c": "x exists"}}),
        );
        let (read, _) = requirement_of(good());
        let well_formed = well_formed_row(&read, "s", &requirement, None);
        let evaluation = Evaluation {
            total: matching,
            matching,
            min_subjects: vec![row("s", "$min_subjects", Cause::Satisfied)],
            unique_ids: vec![row("s", "$unique_ids", Cause::Satisfied)],
            applies: Vec::new(),
            subject_rows: groups
                .into_iter()
                .map(|g| g.into_iter().map(|c| row("s", "c", c)).collect())
                .collect(),
        };
        status(&requirement, &well_formed, &evaluation)
    }

    #[test]
    fn every_needs_every_subject_to_pass_every_check() {
        use Cause::*;
        assert_eq!(
            status_of(
                "every",
                vec![vec![Satisfied, Satisfied], vec![Satisfied]],
                2
            ),
            "met"
        );
        assert_eq!(
            status_of("every", vec![vec![Satisfied, Value], vec![Satisfied]], 2),
            "not_met"
        );
        assert_eq!(status_of("every", vec![vec![Absent]], 1), "not_met");
    }

    #[test]
    fn some_needs_one_subject_to_pass_every_check_by_itself() {
        use Cause::*;
        assert_eq!(
            status_of(
                "some",
                vec![vec![Satisfied, Value], vec![Value, Satisfied]],
                2
            ),
            "not_met"
        );
        assert_eq!(
            status_of(
                "some",
                vec![vec![Satisfied, Value], vec![Satisfied, Satisfied]],
                2
            ),
            "met"
        );
    }

    #[test]
    fn a_requirement_that_would_be_met_with_no_subject_in_scope_is_not_applicable() {
        assert_eq!(status_of("every", vec![], 0), "not_applicable");
        assert_eq!(status_of("some", vec![], 0), "not_applicable");
    }

    fn status_with(min: Cause, unique: Cause, applies: &[Cause]) -> &'static str {
        let (read, requirement) = requirement_of(good());
        let well_formed = well_formed_row(&read, "s", &requirement, None);
        let evaluation = Evaluation {
            total: 1,
            matching: 1,
            min_subjects: vec![row("s", "$min_subjects", min)],
            unique_ids: vec![row("s", "$unique_ids", unique)],
            applies: applies.iter().map(|c| row("s", "$applies", *c)).collect(),
            subject_rows: vec![vec![row("s", "c", Cause::Satisfied)]],
        };
        status(&requirement, &well_formed, &evaluation)
    }

    #[test]
    fn min_subjects_unique_ids_and_unreadable_filters_make_a_requirement_not_met() {
        use Cause::*;
        assert_eq!(
            status_with(Satisfied, Satisfied, &[Satisfied, Value]),
            "met"
        );
        assert_eq!(status_with(Value, Satisfied, &[]), "not_met");
        assert_eq!(status_with(Satisfied, Value, &[]), "not_met");
        for cause in [Absent, Null, Unusable, NotAnObject, Ambiguous] {
            assert_eq!(status_with(Satisfied, Satisfied, &[cause]), "not_met");
        }
    }

    #[test]
    fn a_requirement_that_is_written_wrong_is_not_met_whatever_it_evaluated_to() {
        let (read, requirement) = requirement_of(
            json!({"subject": "thing", "require": "x", "checks": {"c": "x exists"}}),
        );
        let well_formed = well_formed_row(&read, "s", &requirement, None);
        let evaluation = Evaluation {
            total: 1,
            matching: 1,
            ..Evaluation::default()
        };
        assert_eq!(status(&requirement, &well_formed, &evaluation), "not_met");
    }

    #[test]
    fn causes_count_the_rows_that_would_be_violations_worst_first() {
        let (read, requirement) = requirement_of(good());
        let well_formed = well_formed_row(&read, "s", &requirement, None);
        let evaluation = Evaluation {
            total: 3,
            matching: 2,
            min_subjects: vec![row("s", "$min_subjects", Cause::Satisfied)],
            unique_ids: vec![row("s", "$unique_ids", Cause::Satisfied)],
            applies: vec![
                row("s", "$applies", Cause::Value),
                row("s", "$applies", Cause::Absent),
            ],
            subject_rows: vec![
                vec![row("s", "c", Cause::Value), row("s", "d", Cause::Satisfied)],
                vec![row("s", "c", Cause::Value), row("s", "d", Cause::Absent)],
            ],
        };
        assert_eq!(
            causes("not_met", &well_formed, &evaluation),
            json!([{"cause": "absent", "rows": 2}, {"cause": "value", "rows": 2}])
        );
        assert_eq!(causes("met", &well_formed, &evaluation), json!([]));
        assert_eq!(
            causes("not_applicable", &well_formed, &evaluation),
            json!([])
        );
    }

    fn full_report() -> Value {
        let (read, requirement) = requirement_of(json!({
            "subject": "thing",
            "checks": {"c": "every cs.v is in $params.ok", "d": "x exists"}
        }));
        let mut defs = json!({});
        let report_defs = check_defs(
            &Reading::of(&read),
            &read,
            &requirement,
            &Problems::new(),
            &Value::Null,
            &Value::Null,
        );
        for (name, def) in report_defs {
            defs[name] = def.to_json();
        }
        defs["c"]["$refs"] = json!([input(
            "$params.ok",
            json!(["a"]),
            &["$params:/ok".to_string()]
        )]);
        let failed = |name: &str, passed: bool| {
            let cause = if passed { "satisfied" } else { "value" };
            json!({
                "requirement": name,
                "subject": {"type": "thing", "id": 1},
                "check": "c",
                "passed": passed,
                "cause": cause,
                "inputs": [input("cs[].v", json!(["z"]), &["/t/0/cs/0/v".to_string()])],
                "failed_items": [{"path": "cs[0].v", "item": "item 1 of cs", "cause": "value", "value": "z", "locations": ["/t/0/cs/0/v"]}],
            })
        };
        json!({
            "requirements": {
                "s": {"status": "not_met", "checks": defs},
                "holds": {"status": "met", "checks": defs},
                "na": {"status": "not_applicable", "checks": defs},
            },
            "results": [
                failed("s", false),
                failed("s", true),
                failed("holds", false),
                failed("na", false),
                {"requirement": "s", "subject": {"type": "thing", "id": 2}, "check": "$applies", "passed": false, "cause": "value", "inputs": []},
                {"requirement": "s", "subject": {"type": "thing", "id": 3}, "check": "$applies", "passed": false, "cause": "absent", "inputs": []},
            ],
        })
    }

    #[test]
    fn violations_are_the_failed_rows_of_requirements_that_are_not_met() {
        let violations = violations(&full_report());
        let list = violations.as_array().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0]["requirement"], json!("s"));
        assert_eq!(list[0]["check"], json!("c"));
        assert_eq!(list[1]["check"], json!("$applies"));
        assert_eq!(list[1]["cause"], json!("absent"));
    }

    #[test]
    fn a_violation_adds_description_expression_and_refs_at_the_end_of_its_inputs() {
        let violations = violations(&full_report());
        let first = &violations[0];
        assert_eq!(first["description"], json!(""));
        assert_eq!(first["expression"], json!("every cs.v is in $params.ok"));
        assert_eq!(
            first["inputs"],
            json!([
                {"name": "cs[].v", "value": ["z"], "locations": ["/t/0/cs/0/v"]},
                {"name": "$params.ok", "value": ["a"], "locations": ["$params:/ok"]}
            ])
        );
        assert_eq!(first["failed_items"][0]["path"], json!("cs[0].v"));
        assert!(first.get("passed").is_none());
        assert!(first.get("failed_assertions").is_none());
        assert_eq!(first["subject"], json!({"type": "thing", "id": 1}));
    }

    #[test]
    fn a_violation_of_an_added_check_has_the_description_ergo_gave_it() {
        let report = report_of(policy(json!({"s": good()})), Value::Null);
        let list = violations(&report);
        assert_eq!(list.as_array().unwrap().len(), 1);
        assert_eq!(list[0]["check"], json!("$min_subjects"));
        assert_eq!(
            list[0]["description"],
            json!("The in-scope thing count is at least 1")
        );
        assert_eq!(list[0]["expression"], json!("count(matching(things)) >= 1"));
        assert_eq!(list[0]["cause"], json!("value"));
    }

    #[test]
    fn violations_of_a_requirement_written_wrong_are_its_well_formed_row() {
        let report = report_of(
            policy(json!({"s": {"subject": "thing", "checks": {"c": "x is \"a"}, "zz": 1}})),
            Value::Null,
        );
        let list = violations(&report);
        assert_eq!(list.as_array().unwrap().len(), 1);
        assert_eq!(list[0]["check"], json!("$well_formed"));
        assert_eq!(list[0]["expression"], json!("count(problems) == 0"));
        assert_eq!(list[0]["inputs"][2]["name"], json!("zz"));
    }

    #[test]
    fn violations_fail_closed_on_a_report_that_lacks_a_requirement_entry() {
        let report = json!({"results": [
            {"requirement": "s", "subject": {"type": "t", "id": null}, "check": "c", "passed": false, "cause": "value", "inputs": []},
            {"requirement": "s", "subject": {"type": "t", "id": null}, "check": "c", "passed": true, "cause": "satisfied", "inputs": []},
        ]});
        let list = violations(&report);
        assert_eq!(list.as_array().unwrap().len(), 1);
        assert_eq!(list[0]["description"], json!(""));
        assert_eq!(list[0]["expression"], json!(""));
        assert_eq!(violations(&json!({})), json!([]));
        assert_eq!(violations(&json!(null)), json!([]));
    }

    #[test]
    fn a_violation_keeps_failed_assertions() {
        let report = json!({
            "requirements": {"s": {"status": "not_met", "checks": {"c": {"description": "d", "expression": "e"}}}},
            "results": [{"requirement": "s", "subject": {"type": "t", "id": 1}, "check": "c", "passed": false, "cause": "value", "inputs": [],
                         "failed_assertions": [{"assertion": "a", "cause": "value"}]}],
        });
        assert_eq!(
            violations(&report)[0]["failed_assertions"],
            json!([{"assertion": "a", "cause": "value"}])
        );
    }

    #[test]
    fn the_unique_ids_row_lists_the_repeated_ids() {
        let (_, requirement) = requirement_of(good());
        let ok = unique_ids_row("s", &requirement, vec![], &[]);
        assert_eq!(ok.cause, Cause::Satisfied);
        let bad = unique_ids_row(
            "s",
            &requirement,
            vec![json!("b"), json!(10)],
            &["/t/0/id".to_string()],
        );
        assert_eq!(bad.cause, Cause::Value);
        assert_eq!(
            bad.inputs,
            [input(
                "repeated thing ids",
                json!(["b", 10]),
                &["/t/0/id".to_string()]
            )]
        );
    }

    #[test]
    fn the_min_subjects_row_passes_at_the_minimum_and_fails_with_the_cause_it_is_given() {
        let (_, requirement) = requirement_of(
            json!({"subject": "thing", "min_subjects": 2, "checks": {"c": "x exists"}}),
        );
        assert_eq!(
            min_subjects_row("s", &requirement, 2, &[], None, vec![]).cause,
            Cause::Satisfied
        );
        assert_eq!(
            min_subjects_row("s", &requirement, 1, &[], None, vec![]).cause,
            Cause::Value
        );
        assert_eq!(
            min_subjects_row("s", &requirement, 5, &[], Some(Cause::Absent), vec![]).cause,
            Cause::Absent
        );
    }

    #[test]
    fn written_expressions_follow_what_was_written() {
        let expression = |check: Value| {
            written_expression(
                &crate::policy::Policy::read(&policy(
                    json!({"s": {"subject": "thing", "checks": {"c": check}}}),
                ))
                .requirements["s"]
                    .checks["c"],
            )
        };
        assert_eq!(expression(json!("  x exists ")), "x exists");
        assert_eq!(expression(json!({"assert": ["a ", " b"]})), "a and b");
        assert_eq!(expression(json!({"assert": []})), "");
        assert_eq!(expression(json!({"assert": 5})), "<invalid assert>");
        assert_eq!(
            expression(json!({"assert": ["a", 5]})),
            "a and <invalid assert>"
        );
        assert_eq!(expression(json!({"op": "present"})), "<missing assert>");
        assert_eq!(expression(json!(5)), "<invalid check>");
        assert_eq!(expression(json!({"any_of": 5})), "<invalid any_of>");
        assert_eq!(expression(json!({"any_of": {}})), "one of: <empty options>");
        assert_eq!(
            expression(json!({"any_of": {"b": ["y", "z"], "a": "x", "c": [], "d": 5}})),
            "one of: a(x) | b(y and z) | c(<empty option>) | d(<invalid option>)"
        );
    }

    #[test]
    fn field_name_keys_are_what_the_well_formed_row_names() {
        let (read, requirement) = requirement_of(json!({"subject": "thing", "checks": {"a b": 5}}));
        let row = well_formed_row(&read, "s", &requirement, None);
        assert_eq!(row.inputs[2]["name"], json!("checks.\"a b\""));
    }

    #[test]
    fn engine_and_spec_are_the_ones_this_engine_follows() {
        assert_eq!(SPEC, "v0.3-dev");
        assert_eq!(engine()["name"], json!("ergo-policy-engine"));
    }
}
