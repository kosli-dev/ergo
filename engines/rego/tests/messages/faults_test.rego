package ergo_test

import data.ergo
import rego.v1

test_message_a_number_fits_the_kind_a_number if {
	ergo._m_fits_kind(5, "a number")
	not ergo._m_fits_kind("5", "a number")
}

test_message_kind_of_a_side_read_against_a_written_value_on_the_left if {
	check := {"op": "compare", "cmp": "eq", "left": {"literal": "a"}, "right": ["x"]}
	ergo._m_side_kind({}, check, ["x"]) == "text"
}

test_message_kind_of_a_side_is_ignoring_case_compares_is_text if {
	check := {"op": "compare", "cmp": "eq", "left": ["x"], "right": ["y"], "ignoring": "case"}
	ergo._m_side_kind({"x": 3, "y": "a"}, check, ["x"]) == "text"
	ergo._m_side_kind({"x": "a", "y": 3}, check, ["y"]) == "text"
}
