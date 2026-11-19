package ergo_test

import data.ergo
import rego.v1

two_checks_req := {"subject": "s", "require": "some", "checks": {
	"a": ".a exists",
	"b": "b exists",
}}

passing_row := {"passed": true, "cause": "satisfied"}

evaluation_with(rows, matching, scope_readable) := {
	"well_formed": passing_row,
	"unique_ids": [passing_row],
	"unique_ancestor_ids": [],
	"min_subjects": [passing_row],
	"scope_readable": scope_readable,
	"rows_complete": ergo._rows_complete(rows, matching, two_checks_req),
	"subject_rows": rows,
	"matching": count(matching),
}

test_a_subject_missing_a_check_row_does_not_count_as_passing if {
	ergo._holds(two_checks_req, evaluation_with([[passing_row, passing_row]], [{"subject": {}}], true))
	not ergo._holds(two_checks_req, evaluation_with([[passing_row]], [{"subject": {}}], true))
}

test_a_subject_in_scope_without_rows_does_not_let_some_pass_on_nothing if {
	ergo._holds(two_checks_req, evaluation_with([], [], true))
	not ergo._holds(two_checks_req, evaluation_with([], [{"subject": {}}], true))
}

test_a_subject_without_an_applies_row_leaves_the_scope_unknown if {
	subjects := {"s": {"from": ["items"], "applies_to": {"f": {"op": "present", "path": ["a"]}}}}
	resolved := ergo._resolved_subjects with data.ergo_subjects as subjects
	ergo._scope_readable([{"subject": {}}, {"subject": {}}], [passing_row, passing_row], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
	not ergo._scope_readable([{"subject": {}}, {"subject": {}}], [passing_row], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
	not ergo._scope_readable([{"subject": {}}], [{"passed": false, "cause": "absent"}], two_checks_req) with data.ergo_subjects as subjects with data.ergo_resolved as resolved
}

test_message_of_a_row_writes_every_line_separator_of_a_name_as_an_escape if {
	every sep, esc in {"\u2028": "\\u2028", "\u2029": "\\u2029", "\u0085": "\\u0085"} {
		ergo._m_row_one_line({"message": concat("", ["a", sep, "b"])}).message == concat("", ["a", esc, "b"])
	}
}

test_message_of_a_row_without_a_line_separator_is_the_same_row if {
	row := {"message": "a is 1", "passed": false}
	ergo._m_row_one_line(row) == row
	ergo._m_row_one_line({"passed": true}) == {"passed": true}
}

test_a_model_check_with_an_inputs_list_echoes_each_path_in_its_row_inputs if {
	check := {"op": "present", "path": ["x"], "inputs": [["y"], ["x"]]}
	[i.name | some i in ergo._check_inputs({"x": 1, "y": 2}, check)] == ["y", "x"]
}

test_a_model_check_with_an_inputs_list_does_not_echo_an_entry_that_is_not_a_path if {
	check := {"op": "present", "path": ["x"], "inputs": [{"z": 1}, ["x"]]}
	[i.name | some i in ergo._check_inputs({"x": 1}, check)] == ["x"]
}

test_a_ref_that_is_not_a_path_in_the_input_or_the_params_has_no_location if {
	ergo._ref_entries_in({["x"]}, {}) == [{"name": "<invalid ref>", "value": null, "locations": [], "outcome": "absent"}]
}

test_message_of_a_row_writes_line_separators_as_escapes_at_every_level_of_its_failures if {
	leaf := {"message": "c d"}
	inner := {"message": "b c", "failures": [leaf]}
	entry := {"message": "a b", "failures": [inner]}
	row := ergo._m_row_one_line({"message": "x y", "failures": [entry]})
	row.message == "x\\u2028y"
	row.failures[0].message == "a\\u2028b"
	row.failures[0].failures[0].message == "b\\u2028c"
	row.failures[0].failures[0].failures[0].message == "c\\u2028d"
}

test_a_list_compare_whose_right_side_is_the_ref_itself_finds_a_ref_of_the_wrong_kind_unusable if {
	node := {"op": "compare", "cmp": "in", "left": ["s"], "right": ["$$params", "l"]}
	ergo._ref_node_unfit(node, ["$$params", "l"], "a")
	ergo._ref_node_unfit(node, ["$$params", "l"], null)
	not ergo._ref_node_unfit(node, ["$$params", "l"], ["a"])
	not ergo._ref_node_unfit(node, ["$$params", "m"], "a")
}

test_a_row_that_fails_as_ambiguous_gets_its_unusable_inputs_marked_like_one_that_fails_as_unusable if {
	every cause in ["unusable", "not_an_object", "ambiguous"] {
		ergo._m_marked_cause(cause)
	}
	not ergo._m_marked_cause("absent")
	not ergo._m_marked_cause("null")
}

test_a_check_with_no_written_policy_to_read_has_no_written_form if {
	ergo._written_check({"req": "r", "name": "c"}) == null
}
