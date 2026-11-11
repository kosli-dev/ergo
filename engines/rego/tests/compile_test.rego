package ergo_test

import data.ergo
import rego.v1

test_a_compiled_policy_gives_the_same_ergo_and_engine if {
	rep := ergo.report(_engine_doc, ergo.compile(_engine_policy), {})
	rep.ergo == ergo._spec
	rep.engine == {"name": "ergo-rego", "version": ergo.version}
}

test_a_compiled_policy_without_ergo_spec_fails_like_the_policy_it_came_from if {
	policy := object.remove(two_reqs_policy({}), ["ergo_spec"])
	ergo.report({"items": [{"id": 1}]}, ergo.compile(policy), {}) == ergo.report({"items": [{"id": 1}]}, policy, {})
	ergo.report({"items": [{"id": 1}]}, ergo.compile(policy), {}).compliant == false
}

_saved(form) := json.unmarshal(json.marshal(form))

_compile_policies := [
	_sentence_policy({"c": "x is in $params.l and y exists and y is 2", "d": "y is $params.y"}),
	{"ergo_spec": ergo._spec, "subjects": _three_subjects, "requirements": {"r": {"subject": "commit", "checks": {"c": "verified is true"}}, "p": {"subject": "pull request", "checks": {"c": "url exists"}}}},
	{"ergo_spec": ergo._spec, "subjects": {"deployment": {"from": "every $input named by $params.list whose environment is $params.env", "identified_by": "id"}}, "requirements": {"a": approved_req("deployment")}},
	_sentence_policy({"c": "x is", "d": "y is 2"}),
	{"description": 1, "requirements": {"s": {"subject": "nowhere", "checks": {"c": "x exists"}}}},
	{},
	null,
	"policy",
]

_compile_runs := [
	[0, {"things": [{"id": "a", "x": "p", "y": 1}, {"id": "b", "x": "q", "y": 2}]}, {"l": ["p"], "y": 2}],
	[0, {"things": [{"id": "a", "x": "p", "y": 1}]}, {"l": "text"}],
	[0, {"things": [{"id": "a", "x": {"p"}, "y": 2}]}, {}],
	[1, _three_doc, {}],
	[1, null, {}],
	[2, deployments_doc, {"list": "deployments", "env": "staging"}],
	[2, deployments_doc, "params"],
	[3, {"things": [{"id": "a", "y": 2}]}, {}],
	[4, {"things": []}, {}],
	[5, {}, {}],
	[6, {}, {}],
	[7, {}, {}],
]

test_a_report_from_a_saved_compiled_policy_is_the_report_from_its_policy if {
	every run in _compile_runs {
		ergo.report(run[1], _saved(ergo.compile(_compile_policies[run[0]])), run[2]) == ergo.report(run[1], _compile_policies[run[0]], run[2])
	}
}

test_a_compiled_policy_holds_no_set_so_json_can_hold_it if {
	every policy in _compile_policies {
		ergo.compile(policy) == _saved(ergo.compile(policy))
	}
}

test_any_policy_compiles if {
	every policy in _compile_policies {
		object.keys(ergo.compile(policy)) == {"ergo/compiled"}
	}
}

test_compiling_a_compiled_policy_gives_it_back if {
	every policy in _compile_policies {
		ergo.compile(ergo.compile(policy)) == ergo.compile(policy)
	}
}

test_a_compiled_policy_reads_the_params_and_input_of_each_run_not_the_ones_it_was_compiled_with if {
	form := _saved(ergo.compile(_sentence_policy({"c": "x is in $params.l"})))
	doc := {"things": [{"id": "a", "x": "p"}]}
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": ["p"]}).results; r.check == "c"] == [[true, "satisfied"]]
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": ["q"]}).results; r.check == "c"] == [[false, "value"]]
	[[r.passed, r.cause] | some r in ergo.report(doc, form, {"l": "text"}).results; r.check == "c"] == [[false, "unusable"]]
	[[r.passed, r.cause] | some r in ergo.report({"things": [{"id": "a", "x": {"p"}}]}, form, {"l": ["p"]}).results; r.check == "c"] == [[false, "unusable"]]
	ergo.report(doc, form, {"l": ["p"]}).requirements.s.checks.c["$refs"] == [{"name": "$params.l", "value": ["p"], "locations": ["$params:/l"]}]
	ergo.report(doc, form, {"l": ["q"]}).requirements.s.checks.c["$refs"] == [{"name": "$params.l", "value": ["q"], "locations": ["$params:/l"]}]
}

test_a_compiled_policy_with_a_field_missing_or_of_a_type_ergo_cant_use_fails_like_a_policy_ergo_cant_read if {
	form := ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"]
	doc := {"things": [{"id": "a", "x": 1}]}
	ergo.report(doc, {"ergo/compiled": form}, {}).compliant
	every broken in array.concat(
		[{"ergo/compiled": null}, {"ergo/compiled": {}}, {"ergo/compiled": form, "x": 1}],
		array.concat(
			array.concat(
				[{"ergo/compiled": object.remove(form, [f])} | some f, _ in form; f != "engine"],
				[{"ergo/compiled": object.union(form, {f: "x"})} | some f in ["resolved", "subject_sentences", "ahead", "sentences"]],
			),
			array.concat(
				[{"ergo/compiled": object.union(object.remove(form, ["ahead"]), {"ahead": object.remove(form.ahead, [f])})} | some f, _ in form.ahead],
				[{"ergo/compiled": object.union(form, {"ahead": object.union(form.ahead, {f: "x"})})} | some f, _ in form.ahead],
			),
		),
	) {
		ergo.report(doc, broken, {}) == ergo.report(doc, {"x": 1}, {})
	}
}

test_a_compiled_policy_says_which_engine_compiled_it if {
	ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"].engine == {"name": "ergo-rego", "version": ergo.version}
}

_stale_rows(form) := [[r.requirement, r.check, r.passed, problem_inputs_of(r)] | some r in ergo.report({"things": [{"id": "a", "x": 1}]}, {"ergo/compiled": form}, {}).results]

test_a_compiled_policy_without_an_engine_fails_its_well_formed_rows if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])
	_stale_rows(form) == [["s", "$well_formed", false, [{"name": "ergo/compiled engine", "value": ["missing"], "locations": []}]]]
}

test_a_compiled_policy_from_another_engine_fails_its_well_formed_rows if {
	want := [["s", "$well_formed", false, [{"name": "ergo/compiled engine", "value": [concat("", ["compiled by another engine, expected ergo-rego ", ergo.version])], "locations": []}]]]
	form := ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"]
	every engine in [{"name": "ergo-rego", "version": "0.0.9"}, {"name": "other", "version": ergo.version}, {"name": "ergo-rego"}, "ergo-rego", 1, {}] {
		_stale_rows(object.union(object.remove(form, ["engine"]), {"engine": engine})) == want
	}
}

test_a_compiled_policy_that_names_its_engine_ergo_dot_rego_is_refused_because_engines_are_now_named_ergo_rego if {
	want := [["s", "$well_formed", false, [{"name": "ergo/compiled engine", "value": [concat("", ["compiled by another engine, expected ergo-rego ", ergo.version])], "locations": []}]]]
	form := ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"]
	_stale_rows(object.union(object.remove(form, ["engine"]), {"engine": {"name": "ergo.rego", "version": ergo.version}})) == want
}

test_a_compiled_policy_from_another_engine_is_read_from_its_policy_because_its_other_fields_may_mean_something_else_now if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])
	stale := object.union(form, {"requirements": {}, "sentences": [], "resolved": {}, "ahead": {}})
	_stale_rows(stale) == _stale_rows(form)
	_stale_rows(object.union(form, {"policy": _sentence_policy({"c": {"op": "empty", "path": ["xs"]}})})) == [["s", "$well_formed", false, [
		{"name": "checks.c", "value": ["missing assert", "unknown field op", "unknown field path"], "locations": []},
		{"name": "ergo/compiled engine", "value": ["missing"], "locations": []},
	]]]
}

test_a_compiled_policy_from_another_engine_lists_its_engine_before_the_policys_own_problems if {
	form := object.remove(ergo.compile(object.remove(_sentence_policy({"c": "x is 1"}), ["ergo_spec"]))["ergo/compiled"], ["engine"])
	_stale_rows(form) == [["s", "$well_formed", false, [
		{"name": "ergo/compiled engine", "value": ["missing"], "locations": []},
		{"name": "policy ergo_spec", "value": ["missing"], "locations": []},
	]]]
}

test_compiling_a_policy_compiled_by_another_engine_gives_it_back_so_the_report_still_says_so if {
	stale := {"ergo/compiled": object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine"])}
	ergo.compile(stale) == stale
}

test_a_compiled_policy_from_another_engine_without_its_policy_fails_like_a_policy_ergo_cant_read if {
	form := object.remove(ergo.compile(_sentence_policy({"c": "x is 1"}))["ergo/compiled"], ["engine", "policy"])
	ergo.report({"things": [{"id": "a", "x": 1}]}, {"ergo/compiled": form}, {}) == ergo.report({"things": [{"id": "a", "x": 1}]}, {"x": 1}, {})
}

test_data_named_like_ergos_compile_flag_changes_no_report if {
	policy := _sentence_policy({"c": "x is 1"})
	doc := {"things": [{"id": "a", "x": 2}]}
	want := ergo.report(doc, policy, {})
	every form in [policy, ergo.compile(policy)] {
		ergo.report(doc, form, {}) == want with data.ergo_reading as true
	}
}
