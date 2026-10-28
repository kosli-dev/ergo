use crate::policy::{Policy, Requirement};
use crate::report::{Evaluation, no_subjects};
use serde_json::Value;

pub fn find_subjects(
    _policy: &Policy,
    requirement_name: &str,
    requirement: &Requirement,
    _input: &Value,
    params: &Value,
) -> Evaluation {
    no_subjects(requirement_name, requirement, params)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn until_subjects_are_read_none_are_found_and_min_subjects_fails_as_value() {
        let policy = Policy::read(&json!({
            "ergo_spec": "v0.2",
            "subjects": {"thing": {"from": "things"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": "x"}}}
        }));
        let requirement = &policy.requirements["s"];
        let found = find_subjects(
            &policy,
            "s",
            requirement,
            &json!({"things": [1]}),
            &Value::Null,
        );
        assert_eq!((found.total, found.matching), (0, 0));
        assert_eq!(found.min_subjects.len(), 1);
        assert!(!found.min_subjects[0].passed());
        assert!(found.subject_rows.is_empty());
    }
}
