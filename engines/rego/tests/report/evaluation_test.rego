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
