use super::*;

fn v(text: &str) -> Value {
    serde_json::from_str(text).unwrap()
}

fn key(k: &str) -> Step {
    Step::Key(k.to_string())
}

fn at(start: Start, steps: Vec<Step>) -> Path {
    Path { start, steps }
}

fn subject_path(steps: Vec<Step>) -> Path {
    at(Start::Subject, steps)
}

struct World {
    subject: Value,
    input: Value,
    params: Option<Value>,
}

impl World {
    fn new(subject: &str) -> World {
        World {
            subject: v(subject),
            input: v("{}"),
            params: None,
        }
    }

    fn with_input(mut self, input: &str) -> World {
        self.input = v(input);
        self
    }

    fn with_params(mut self, params: &str) -> World {
        self.params = Some(v(params));
        self
    }

    fn run(&self, path: &Path) -> (Outcome, Option<Value>, Option<String>) {
        self.run_with(path, false)
    }

    fn run_item_by_item(&self, path: &Path) -> (Outcome, Option<Value>, Option<String>) {
        self.run_with(path, true)
    }

    fn run_with(
        &self,
        path: &Path,
        item_by_item: bool,
    ) -> (Outcome, Option<Value>, Option<String>) {
        let ctx = Ctx {
            label: None,
            item_by_item,
            in_option: false,
            subject: Located {
                value: &self.subject,
                location: Location::input_root().key("s"),
            },
            input: &self.input,
            params: self.params.as_ref(),
            aliases: BTreeMap::new(),
        };
        let r = read(path, &ctx);
        (r.outcome, r.value.cloned(), r.location.map(|l| l.render()))
    }
}

fn loc(s: &str) -> Option<String> {
    Some(s.to_string())
}

#[test]
fn a_present_value_is_found_at_its_own_location() {
    let w = World::new(r#"{"a": {"b": 1}}"#);
    let (o, value, l) = w.run(&subject_path(vec![key("a"), key("b")]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("1")));
    assert_eq!(l, loc("/s/a/b"));
}

#[test]
fn false_and_empty_values_are_found_not_null() {
    let w = World::new(r#"{"a": false, "b": "", "c": []}"#);
    for k in ["a", "b", "c"] {
        assert_eq!(w.run(&subject_path(vec![key(k)])).0, Outcome::Found);
    }
}

#[test]
fn a_path_without_steps_reads_the_subject_whatever_it_is() {
    for text in ["1", "\"s\"", "[1]", "{}", "false"] {
        let (o, value, l) = World::new(text).run(&subject_path(vec![]));
        assert_eq!(o, Outcome::Found, "{text}");
        assert_eq!(value, Some(v(text)));
        assert_eq!(l, loc("/s"));
    }
}

#[test]
fn a_path_from_a_list_input_is_not_an_object_whatever_its_key_holds_but_item_by_item() {
    let params_key = Step::Ref(Box::new(at(Start::Params, vec![key("k")])));
    let input_key = Step::Ref(Box::new(at(Start::Input, vec![key("k")])));
    for params in ["{}", r#"{"k": null}"#, r#"{"k": 3}"#, r#"{"k": "a"}"#] {
        let w = World::new(r#"{"m": {"a": 1}}"#)
            .with_input(r#"[{"m": {"a": 1}}]"#)
            .with_params(params);
        let from_input = at(Start::Input, vec![key("m"), params_key.clone()]);
        let whole = at(Start::Input, vec![params_key.clone()]);
        let keyed = subject_path(vec![key("m"), input_key.clone()]);
        for path in [&from_input, &whole, &keyed] {
            assert_eq!(w.run(path).0, Outcome::NotAnObject, "{params} {path:?}");
        }
        let walked = (
            w.run_item_by_item(&from_input).0,
            w.run_item_by_item(&keyed).0,
        );
        let key_outcome = match params {
            "{}" => Outcome::Absent,
            r#"{"k": null}"# => Outcome::Null,
            r#"{"k": 3}"# => Outcome::Unusable,
            _ => Outcome::NotAnObject,
        };
        assert_eq!(walked, (key_outcome, Outcome::Unusable), "{params}");
    }
}

#[test]
fn a_null_subject_without_steps_is_null_not_not_an_object() {
    let (o, value, l) = World::new("null").run(&subject_path(vec![]));
    assert_eq!(o, Outcome::Null);
    assert_eq!(value, Some(Value::Null));
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_key_on_a_subject_that_is_not_an_object_is_not_an_object() {
    for text in ["null", "1", "\"s\"", "[1]", "true"] {
        let (o, value, l) = World::new(text).run(&subject_path(vec![key("a")]));
        assert_eq!(o, Outcome::NotAnObject, "{text}");
        assert_eq!(value, None);
        assert_eq!(l, loc("/s"));
    }
}

#[test]
fn a_key_on_an_alias_that_is_not_an_object_is_not_an_object() {
    let w = World::new("{}");
    let alias_value = v("[1]");
    let mut aliases = BTreeMap::new();
    aliases.insert(
        "pr".to_string(),
        Located {
            value: &alias_value,
            location: Location::input_root().key("prs").index(0),
        },
    );
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases,
    };
    let r = read(&at(Start::Alias("pr".into()), vec![key("a")]), &ctx);
    assert_eq!(r.outcome, Outcome::NotAnObject);
    assert_eq!(r.location.unwrap().render(), "/prs/0");
    let r = read(&at(Start::Alias("pr".into()), vec![]), &ctx);
    assert_eq!(r.outcome, Outcome::Found);
}

#[test]
fn a_number_an_alias_holds_is_unusable_as_a_key_not_a_position() {
    let w = World::new(r#"{"m": [5, 1]}"#);
    for (held, outcome) in [
        ("1", Outcome::Unusable),
        ("[1]", Outcome::Unusable),
        ("{\"a\": 1}", Outcome::Unusable),
        ("null", Outcome::Null),
    ] {
        let alias_value = v(held);
        let mut aliases = BTreeMap::new();
        aliases.insert(
            "k".to_string(),
            Located {
                value: &alias_value,
                location: Location::input_root().key("ks").index(0),
            },
        );
        let ctx = Ctx {
            label: None,
            item_by_item: false,
            in_option: false,
            subject: Located {
                value: &w.subject,
                location: Location::input_root(),
            },
            input: &w.input,
            params: None,
            aliases,
        };
        let step = Step::Ref(Box::new(at(Start::Alias("k".into()), vec![])));
        assert!(
            matches!(resolve(&step, &ctx), Err(found) if found == outcome),
            "{held}"
        );
    }
}

#[test]
fn an_alias_nothing_holds_is_absent_with_no_location() {
    let w = World::new("{}");
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let r = read(&at(Start::Alias("nope".into()), vec![key("a")]), &ctx);
    assert_eq!(r.outcome, Outcome::Absent);
    assert!(r.location.is_none());
}

#[test]
fn a_position_on_a_null_subject_is_null_and_on_an_empty_list_absent() {
    let p = subject_path(vec![Step::Index(0)]);
    assert_eq!(World::new("null").run(&p).0, Outcome::Null);
    assert_eq!(World::new("[]").run(&p).0, Outcome::Absent);
}

#[test]
fn a_position_on_a_string_subject_is_unusable() {
    let p = subject_path(vec![Step::Index(0)]);
    let (o, _, l) = World::new("\"s\"").run(&p);
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_position_on_an_object_subject_is_unusable() {
    let (o, _, _) = World::new("{\"0\": 1}").run(&subject_path(vec![Step::Index(0)]));
    assert_eq!(o, Outcome::Unusable);
}

#[test]
fn a_position_on_a_list_subject_reads_the_item() {
    let (o, value, l) = World::new("[5, 6]").run(&subject_path(vec![Step::Index(1)]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("6")));
    assert_eq!(l, loc("/s/1"));
}

#[test]
fn a_missing_key_is_absent_and_points_at_the_object() {
    let (o, value, l) =
        World::new(r#"{"a": {"b": 1}}"#).run(&subject_path(vec![key("a"), key("c")]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(value, None);
    assert_eq!(l, loc("/s/a"));
}

#[test]
fn an_index_past_the_end_is_absent_and_points_at_the_short_list() {
    let (o, _, l) =
        World::new(r#"{"xs": [1, 2]}"#).run(&subject_path(vec![key("xs"), Step::Index(2)]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("/s/xs"));
}

#[test]
fn steps_after_a_missing_value_stay_absent() {
    let (o, _, l) =
        World::new(r#"{"a": {}}"#).run(&subject_path(vec![key("a"), key("b"), key("c"), key("d")]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("/s/a"));
}

#[test]
fn steps_after_null_are_null_and_point_at_the_null() {
    let (o, _, l) = World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a"), key("b")]));
    assert_eq!(o, Outcome::Null);
    assert_eq!(l, loc("/s/a"));
    let (o, _, _) = World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a"), Step::Index(0)]));
    assert_eq!(o, Outcome::Null);
}

#[test]
fn a_last_step_that_reads_null_is_null() {
    let (o, value, l) = World::new(r#"{"a": null}"#).run(&subject_path(vec![key("a")]));
    assert_eq!(o, Outcome::Null);
    assert_eq!(value, Some(Value::Null));
    assert_eq!(l, loc("/s/a"));
}

#[test]
fn a_key_on_a_string_is_unusable() {
    let (o, _, l) = World::new(r#"{"x": "a"}"#).run(&subject_path(vec![key("x"), key("y")]));
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(l, loc("/s/x"));
}

#[test]
fn a_key_on_a_list_is_unusable() {
    let (o, _, l) = World::new(r#"{"x": [{"y": 1}]}"#).run(&subject_path(vec![key("x"), key("y")]));
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(l, loc("/s/x"));
}

#[test]
fn an_index_on_an_object_is_unusable() {
    let (o, _, l) =
        World::new(r#"{"x": {"1": "a"}}"#).run(&subject_path(vec![key("x"), Step::Index(1)]));
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(l, loc("/s/x"));
}

#[test]
fn any_step_after_a_scalar_is_unusable() {
    for text in [r#"{"x": 1}"#, r#"{"x": true}"#, r#"{"x": "s"}"#] {
        for step in [key("y"), Step::Index(0)] {
            let (o, _, _) = World::new(text).run(&subject_path(vec![key("x"), step]));
            assert_eq!(o, Outcome::Unusable, "{text}");
        }
    }
}

#[test]
fn input_paths_start_at_the_input_root() {
    let w = World::new("{}").with_input(r#"{"a": [{"b": 2}]}"#);
    let p = at(Start::Input, vec![key("a"), Step::Index(0), key("b")]);
    let (o, value, l) = w.run(&p);
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("2")));
    assert_eq!(l, loc("/a/0/b"));
}

#[test]
fn a_key_on_an_input_that_is_not_an_object_gives_not_an_object_and_a_position_reads_it() {
    let w = World::new("{}").with_input("[1]");
    let (o, _, l) = w.run(&at(Start::Input, vec![key("a")]));
    assert_eq!(o, Outcome::NotAnObject);
    assert_eq!(l, loc(""));
    let (o, _, l) = w.run(&at(Start::Input, vec![Step::Index(0), key("a")]));
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(l, loc("/0"));
}

#[test]
fn the_input_root_is_found_with_an_empty_pointer() {
    let w = World::new("{}").with_input("{}");
    assert_eq!(w.run(&at(Start::Input, vec![])).2, loc(""));
}

#[test]
fn params_paths_point_into_the_params() {
    let w = World::new("{}").with_params(r#"{"max": {"high": 3}}"#);
    let (o, value, l) = w.run(&at(Start::Params, vec![key("max"), key("high")]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("3")));
    assert_eq!(l, loc("$params:/max/high"));
}

#[test]
fn no_params_ends_absent_at_the_params_root() {
    let w = World::new("{}");
    for steps in [vec![], vec![key("a")], vec![key("a"), key("b")]] {
        let (o, value, l) = w.run(&at(Start::Params, steps));
        assert_eq!(o, Outcome::Absent);
        assert_eq!(value, None);
        assert_eq!(l, loc("$params:"));
    }
}

#[test]
fn a_missing_params_key_points_at_the_params_root() {
    let w = World::new("{}").with_params("{}");
    let (o, _, l) = w.run(&at(Start::Params, vec![key("a")]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("$params:"));
}

#[test]
fn keys_are_escaped_in_pointers() {
    let w = World::new(r#"{"a/b": {"c~d": 1}}"#);
    let (_, _, l) = w.run(&subject_path(vec![key("a/b"), key("c~d")]));
    assert_eq!(l, loc("/s/a~1b/c~0d"));
}

#[test]
fn a_tilde_is_escaped_before_a_slash() {
    assert_eq!(Location::input_root().key("~1").render(), "/~01");
}

#[test]
fn a_ref_step_reads_the_key_it_holds() {
    let w = World::new(r#"{"limits": {"high": 3, "low": 9}, "sev": "high"}"#)
        .with_params(r#"{"k": "low"}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, value, l) = w.run(&subject_path(vec![
        key("limits"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("9")));
    assert_eq!(l, loc("/s/limits/low"));
}

#[test]
fn a_ref_step_holding_a_whole_number_is_never_a_list_position() {
    for params in [r#"{"i": 2}"#, r#"{"i": 2.0}"#, r#"{"i": 0}"#] {
        let w = World::new(r#"{"xs": [10, 20, 30]}"#).with_params(params);
        let reference = at(Start::Params, vec![key("i")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("xs"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Unusable, "{params}");
        assert_eq!(value, None);
        assert_eq!(l, loc("/s/xs"));
    }
}

#[test]
fn a_ref_that_is_missing_ends_the_path_absent_before_the_step() {
    let w = World::new(r#"{"limits": {"high": 3}}"#).with_params("{}");
    let reference = at(Start::Params, vec![key("k")]);
    let (o, value, l) = w.run(&subject_path(vec![
        key("limits"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(value, None);
    assert_eq!(l, loc("/s/limits"));
}

#[test]
fn a_ref_with_no_params_ends_absent() {
    let w = World::new(r#"{"limits": {}}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, l) = w.run(&subject_path(vec![
        key("limits"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("/s/limits"));
}

#[test]
fn a_ref_that_reads_null_ends_the_path_null() {
    let w = World::new(r#"{"limits": {"null": 1}}"#).with_params(r#"{"k": null}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, value, _) = w.run(&subject_path(vec![
        key("limits"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Null);
    assert_eq!(value, None);
}

#[test]
fn a_ref_that_cannot_be_read_beats_a_subject_that_is_not_an_object() {
    let w = World::new("1").with_params("{}");
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, _) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
    assert_eq!(o, Outcome::Absent);
}

#[test]
fn a_ref_in_a_later_step_beats_a_field_that_is_missing_or_null() {
    for (params, want) in [
        ("{}", Outcome::Absent),
        (r#"{"k": null}"#, Outcome::Null),
        (r#"{"k": [1]}"#, Outcome::Unusable),
        (r#"{"k": true}"#, Outcome::Unusable),
    ] {
        for subject in [
            "{}",
            r#"{"x": null}"#,
            r#"{"x": 1}"#,
            "[1]",
            r#""s""#,
            "null",
        ] {
            let w = World::new(subject).with_params(params);
            let reference = at(Start::Params, vec![key("k")]);
            let (o, value, _) = w.run(&subject_path(vec![
                key("x"),
                Step::Ref(Box::new(reference)),
            ]));
            assert_eq!(o, want, "{params} on {subject}");
            assert_eq!(value, None);
        }
    }
}

#[test]
fn a_ref_in_a_later_step_that_can_be_read_leaves_the_earlier_cause() {
    let w = World::new("{}").with_params(r#"{"k": "y"}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, l) = w.run(&subject_path(vec![
        key("x"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_ref_step_on_a_subject_that_is_not_an_object_is_not_an_object() {
    let w = World::new("1").with_params(r#"{"k": "a"}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, l) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
    assert_eq!(o, Outcome::NotAnObject);
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_ref_holding_a_number_on_a_subject_list_is_unusable() {
    let w = World::new("[7, 8]").with_params(r#"{"k": 1}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, value, _) = w.run(&subject_path(vec![Step::Ref(Box::new(reference))]));
    assert_eq!(o, Outcome::Unusable);
    assert_eq!(value, None);
}

#[test]
fn a_ref_value_that_cannot_be_a_key_is_unusable() {
    for params in [
        r#"{"k": true}"#,
        r#"{"k": 0}"#,
        r#"{"k": 1}"#,
        r#"{"k": 1.0}"#,
        r#"{"k": 1.5}"#,
        r#"{"k": -1}"#,
        r#"{"k": [0]}"#,
        r#"{"k": {"a": 1}}"#,
        r#"{"k": 9007199254740992}"#,
        r#"{"k": 1e400}"#,
    ] {
        let w = World::new(r#"{"xs": [1], "o": {"a": 1}}"#).with_params(params);
        let reference = at(Start::Params, vec![key("k")]);
        let (o, value, l) = w.run(&subject_path(vec![
            key("xs"),
            Step::Ref(Box::new(reference)),
        ]));
        assert_eq!(o, Outcome::Unusable, "{params}");
        assert_eq!(value, None);
        assert_eq!(l, loc("/s/xs"));
    }
}

#[test]
fn a_string_ref_on_a_list_is_unusable() {
    let w = World::new(r#"{"xs": [1]}"#).with_params(r#"{"k": "0"}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, _) = w.run(&subject_path(vec![
        key("xs"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Unusable);
}

#[test]
fn a_number_ref_on_an_object_is_unusable() {
    let w = World::new(r#"{"o": {"1": 1}}"#).with_params(r#"{"k": 1}"#);
    let reference = at(Start::Params, vec![key("k")]);
    let (o, _, _) = w.run(&subject_path(vec![
        key("o"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Unusable);
}

#[test]
fn a_ref_can_read_the_input() {
    let w = World::new(r#"{"o": {"x": 1}}"#).with_input(r#"{"which": "x"}"#);
    let reference = at(Start::Input, vec![key("which")]);
    let (o, value, l) = w.run(&subject_path(vec![
        key("o"),
        Step::Ref(Box::new(reference)),
    ]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("1")));
    assert_eq!(l, loc("/s/o/x"));
}

#[test]
fn outcomes_give_their_causes() {
    assert_eq!(Outcome::Found.cause(), None);
    assert_eq!(Outcome::Null.cause(), Some(Cause::Null));
    assert_eq!(Outcome::Absent.cause(), Some(Cause::Absent));
    assert_eq!(Outcome::Unusable.cause(), Some(Cause::Unusable));
    assert_eq!(Outcome::NotAnObject.cause(), Some(Cause::NotAnObject));
}

fn part_start(name: &str, base: Start, steps: Vec<Step>, id: Option<Vec<Step>>) -> Start {
    Start::Part(Box::new(PartStart {
        name: name.to_string(),
        base,
        steps,
        id,
    }))
}

#[test]
fn a_field_step_reads_the_key_a_field_of_the_subject_holds() {
    let w = World::new(r#"{"limits": {"high": 3, "low": 9}, "sev": "low"}"#);
    let field = at(Start::Subject, vec![key("sev")]);
    let (o, value, l) = w.run(&subject_path(vec![
        key("limits"),
        Step::Field(Box::new(field)),
    ]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("9")));
    assert_eq!(l, loc("/s/limits/low"));
}

#[test]
fn a_field_step_whose_field_is_missing_null_or_not_a_string_ends_the_path_with_that_cause() {
    for (subject, want) in [
        (r#"{"limits": {}}"#, Outcome::Absent),
        (r#"{"limits": {}, "sev": null}"#, Outcome::Null),
        (r#"{"limits": {}, "sev": 1}"#, Outcome::Unusable),
        (r#"{"limits": {}, "sev": ["a"]}"#, Outcome::Unusable),
        (r#"{"limits": {}, "sev": true}"#, Outcome::Unusable),
    ] {
        let field = at(Start::Subject, vec![key("sev")]);
        let (o, value, l) = World::new(subject).run(&subject_path(vec![
            key("limits"),
            Step::Field(Box::new(field)),
        ]));
        assert_eq!(o, want, "{subject}");
        assert_eq!(value, None);
        assert_eq!(l, loc("/s/limits"));
    }
}

#[test]
fn a_field_step_on_a_subject_that_is_not_an_object_is_not_an_object() {
    let field = at(Start::Subject, vec![key("sev")]);
    let (o, _, l) = World::new("[1]").run(&subject_path(vec![Step::Field(Box::new(field))]));
    assert_eq!(o, Outcome::NotAnObject);
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_part_stands_for_its_steps_inside_the_subject() {
    let w = World::new(r#"{"d": {"b": {"x": 1}}}"#);
    let start = part_start("cov", Start::Subject, vec![key("d"), key("b")], None);
    let (o, value, l) = w.run(&at(start, vec![key("x")]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("1")));
    assert_eq!(l, loc("/s/d/b/x"));
}

#[test]
fn a_part_on_a_subject_that_is_not_an_object_ends_not_an_object_like_the_full_path() {
    let start = part_start("cov", Start::Subject, vec![key("d")], None);
    let (o, _, l) = World::new("3").run(&at(start, vec![]));
    assert_eq!(o, Outcome::NotAnObject);
    assert_eq!(l, loc("/s"));
}

#[test]
fn a_missing_part_ends_absent_where_the_full_path_would() {
    let w = World::new(r#"{"d": {}}"#);
    let start = part_start("cov", Start::Subject, vec![key("d"), key("b")], None);
    let (o, _, l) = w.run(&at(start, vec![key("x")]));
    assert_eq!(o, Outcome::Absent);
    assert_eq!(l, loc("/s/d"));
}

#[test]
fn a_part_with_a_named_by_in_its_path_reads_the_ref() {
    let w = World::new(r#"{"m": {"k": {"x": 1}}}"#).with_params(r#"{"p": "k"}"#);
    let reference = at(Start::Params, vec![key("p")]);
    let start = part_start(
        "cov",
        Start::Subject,
        vec![key("m"), Step::Ref(Box::new(reference))],
        None,
    );
    let (o, value, _) = w.run(&at(start, vec![key("x")]));
    assert_eq!(o, Outcome::Found);
    assert_eq!(value, Some(v("1")));
    let (o, _, _) = World::new(r#"{"m": {}}"#).run(&at(
        part_start(
            "cov",
            Start::Subject,
            vec![
                key("m"),
                Step::Ref(Box::new(at(Start::Params, vec![key("p")]))),
            ],
            None,
        ),
        vec![],
    ));
    assert_eq!(o, Outcome::Absent);
}

#[test]
fn a_part_of_an_alias_starts_at_the_alias_value() {
    let w = World::new("{}");
    let parent = v(r#"{"att": {"n": 5}}"#);
    let mut aliases = BTreeMap::new();
    aliases.insert(
        "art".to_string(),
        Located {
            value: &parent,
            location: Location::input_root().key("arts").index(0),
        },
    );
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases,
    };
    let start = part_start(
        "art.cov",
        Start::Alias("art".into()),
        vec![key("att")],
        None,
    );
    let r = read(&at(start, vec![key("n")]), &ctx);
    assert_eq!(r.outcome, Outcome::Found);
    assert_eq!(r.location.unwrap().render(), "/arts/0/att/n");
}

#[test]
fn a_part_tag_has_the_alias_and_the_id_read_inside_the_part() {
    let w = World::new(r#"{"d": {"id": "c1", "x": 1}}"#);
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases: BTreeMap::new(),
    };
    let start = part_start("cov", Start::Subject, vec![key("d")], Some(vec![key("id")]));
    let tag = part_tag(&at(start, vec![key("x")]), &ctx);
    assert_eq!(tag, Some(("cov".to_string(), v("\"c1\""))));
}

#[test]
fn a_part_tag_id_is_null_without_an_id_path_or_when_the_id_leads_nowhere() {
    let w = World::new(r#"{"d": {"id": null}}"#);
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases: BTreeMap::new(),
    };
    for id in [
        None,
        Some(vec![key("id")]),
        Some(vec![key("nope")]),
        Some(vec![key("id"), key("z")]),
    ] {
        let start = part_start("cov", Start::Subject, vec![key("d")], id);
        assert_eq!(
            part_tag(&at(start, vec![]), &ctx),
            Some(("cov".to_string(), Value::Null))
        );
    }
}

#[test]
fn a_path_that_does_not_start_at_a_part_has_no_tag() {
    let w = World::new("{}");
    let ctx = Ctx {
        label: None,
        item_by_item: false,
        in_option: false,
        subject: Located {
            value: &w.subject,
            location: Location::input_root(),
        },
        input: &w.input,
        params: None,
        aliases: BTreeMap::new(),
    };
    assert_eq!(part_tag(&subject_path(vec![key("a")]), &ctx), None);
}
