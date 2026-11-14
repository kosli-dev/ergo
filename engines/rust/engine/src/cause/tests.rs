use super::*;

#[test]
fn names_are_the_spec_words() {
    let all = [
        Cause::Satisfied,
        Cause::NotAnObject,
        Cause::Ambiguous,
        Cause::Unusable,
        Cause::Absent,
        Cause::Null,
        Cause::Value,
    ];
    let names: Vec<_> = all.iter().map(|c| c.name()).collect();
    assert_eq!(
        names,
        [
            "satisfied",
            "not_an_object",
            "ambiguous",
            "unusable",
            "absent",
            "null",
            "value"
        ]
    );
}

#[test]
fn causes_are_in_the_spec_order() {
    assert!(Cause::Satisfied < Cause::NotAnObject);
    assert!(Cause::NotAnObject < Cause::Ambiguous);
    assert!(Cause::Ambiguous < Cause::Unusable);
    assert!(Cause::Unusable < Cause::Absent);
    assert!(Cause::Absent < Cause::Null);
    assert!(Cause::Null < Cause::Value);
}

#[test]
fn worst_takes_the_first_failing_cause_in_spec_order() {
    assert_eq!(
        Cause::worst([Cause::Value, Cause::Null, Cause::Absent]),
        Some(Cause::Absent)
    );
    assert_eq!(
        Cause::worst([Cause::Value, Cause::NotAnObject, Cause::Unusable]),
        Some(Cause::NotAnObject)
    );
}

#[test]
fn worst_ignores_satisfied() {
    assert_eq!(
        Cause::worst([Cause::Satisfied, Cause::Value]),
        Some(Cause::Value)
    );
}

#[test]
fn worst_of_nothing_or_only_satisfied_is_none() {
    assert_eq!(Cause::worst([]), None);
    assert_eq!(Cause::worst([Cause::Satisfied, Cause::Satisfied]), None);
}
