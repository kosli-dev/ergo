#![cfg(feature = "serde")]

mod support;

use ergo_sentences::*;
use support::*;

#[test]
fn a_from_line_survives_a_trip_through_json() {
    let line = from(
        "every a1.b named by each of $params.l whose some c1, if any, matches \"x\" and count of d1 is at least 2",
    );
    let json = serde_json::to_string(&line).unwrap();
    let back: FromLine = serde_json::from_str(&json).unwrap();
    assert_eq!(back, line);
}

#[test]
fn a_syntax_error_survives_a_trip_through_json() {
    let errors = parse_from("x whose y is \"a").unwrap_err();
    let json = serde_json::to_string(&errors).unwrap();
    let back: Vec<SyntaxError> = serde_json::from_str(&json).unwrap();
    assert_eq!(back, errors);
}

fn trip<T>(value: &T)
where
    T: serde::Serialize + serde::de::DeserializeOwned + PartialEq + std::fmt::Debug,
{
    let json = serde_json::to_string(value).unwrap();
    let back: T = serde_json::from_str(&json).unwrap();
    assert_eq!(&back, value, "{json}");
}

const PHRASES: [&str; 31] = [
    "exists",
    "does not exist",
    "is empty",
    "is not empty",
    "is a non-empty string",
    "is a list",
    "is a string",
    "is a number",
    "is a boolean",
    "is an object",
    "contains 1",
    "does not contain k",
    "contains all of 1, 2",
    "contains none of l",
    "matches \"a\"",
    "does not match l",
    "starts with \"a\"",
    "ends with k",
    "is alphabetically before \"a\"",
    "is alphabetically after k",
    "is at least 1",
    "is at most 1",
    "is more than 1",
    "is less than 1",
    "is between 1 and 2",
    "is before k",
    "is after k",
    "is on or after k",
    "is on or before k",
    "is 1 within 2",
    "is not one of true, false, null, 'a', \"b\", -1.5e3",
];

#[test]
fn every_phrase_survives_a_trip_through_json() {
    for line in PHRASES {
        trip(&phrase(line));
    }
    trip(&phrase("is in $params.l"));
    trip(&phrase("is y plus 1"));
}

#[test]
fn every_small_enum_survives_a_trip_through_json() {
    trip(&Quantifier::Every);
    trip(&Quantifier::Some);
    trip(&DerivedKind::Count);
    trip(&DerivedKind::Sum);
    for unit in [
        Unit::Seconds,
        Unit::Minutes,
        Unit::Hours,
        Unit::Days,
        Unit::Weeks,
    ] {
        trip(&unit);
    }
    for order in [
        Order::AtLeast,
        Order::AtMost,
        Order::MoreThan,
        Order::LessThan,
    ] {
        trip(&order);
    }
    for time in [
        TimeOrder::Before,
        TimeOrder::After,
        TimeOrder::OnOrAfter,
        TimeOrder::OnOrBefore,
    ] {
        trip(&time);
    }
    for kind in [
        Type::List,
        Type::String,
        Type::Number,
        Type::Boolean,
        Type::Object,
    ] {
        trip(&kind);
    }
    trip(&Side::Left);
    trip(&Side::Right);
}

#[test]
fn every_kind_of_value_survives_a_trip_through_json() {
    for value in [
        Value::String("a".into()),
        Value::Number("-1.5e3".into()),
        Value::True,
        Value::False,
        Value::Null,
    ] {
        trip(&value);
    }
    trip(&List::Values(vec![Value::True, Value::Null]));
    trip(&List::Path(path("$params.l")));
    trip(&Operand::Value(Value::Null));
    trip(&Operand::Field(vec![Term::Number("1".into())]));
}

#[test]
fn every_kind_of_path_survives_a_trip_through_json() {
    for line in [
        "$params.k",
        "$input.k",
        ".empty",
        "first of p.q",
        "last of p",
        "item 2 of p",
        "item 3 from last of p",
        "p[k]",
        "p[$params.k]",
        "p[$input.k]",
        "p[\"b c\"]",
        "p[2]",
        "p named by k",
    ] {
        let read = match parse_path(line) {
            Ok(read) => read,
            Err(_) => from(&format!("{line} whose x exists")).path,
        };
        trip(&read);
        trip(&read.start);
        trip(&read.steps);
        trip(&read.position);
    }
    trip(&Reference::Params("k".into()));
    trip(&Reference::Input("k".into()));
    trip(&Reference::Name("k".into()));
}

#[test]
fn every_part_of_a_check_survives_a_trip_through_json() {
    let read = check(
        "every xs whose y is 1 exists and every xs, if any, is empty and it is 1 and some ys is empty and count of ys whose z is 1 is 2 and hours elapsed from p to q is 1 plus sum of c",
    );
    trip(&read);
    for assertion in &read.assertions {
        trip(assertion);
        match assertion {
            Assertion::Quantified {
                quantifier, whose, ..
            } => {
                trip(quantifier);
                trip(whose);
            }
            Assertion::Derived { terms, .. } => {
                for term in terms {
                    trip(term);
                    match term {
                        Term::Derived(derived) => trip(derived),
                        Term::Elapsed(elapsed) => trip(elapsed),
                        _ => {}
                    }
                }
            }
            Assertion::Plain { .. } => {}
        }
    }
}

#[test]
fn every_part_of_a_from_line_survives_a_trip_through_json() {
    let line = from(
        "every p named by each of q whose y is 1 and every c, if any, exists and count of d is 2 and days elapsed from e to f is 1",
    );
    trip(&line);
    for condition in &line.whose {
        trip(condition);
        if let FromCondition::Condition(condition) = condition {
            trip(&condition.left);
            trip(&condition.phrase);
            match &condition.left {
                Left::Derived(derived) => trip(derived),
                Left::Elapsed(elapsed) => trip(elapsed),
                Left::Path(path) => trip(path),
            }
        }
    }
}

#[test]
fn every_part_of_a_for_line_survives_a_trip_through_json() {
    let line = for_line("every xs whose p is 1 as x, last of ys sorted by d alphabetically as y");
    trip(&line);
    for item in &line.items {
        trip(item);
    }
    for item in &for_line("every xs, if any, as x").items {
        trip(item);
    }
    for item in &for_line("first of xs sorted by d as x").items {
        if let ForItem::Pick {
            sorted_by: Some(sorted),
            ..
        } = item
        {
            trip(sorted);
        }
    }
}
