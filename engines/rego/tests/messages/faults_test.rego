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

test_a_key_fault_piece_is_a_clause_that_says_the_key_isnt_text if {
	check := {"op": "compare", "cmp": "eq", "left": ["k"], "right": ["m", {"ref": ["$$params", "k"]}], "expression": "k is m named by $params.k"}
	ergo._m_key_fault_pieces({}, check) == [ergo._m_clause("root", "$params.k", "unusable", "$params.k is 3, which isn't text")] with data.ergo_params as {"k": 3}
	ergo._m_key_faults({}, check) == ["$params.k is 3, which isn't text"] with data.ergo_params as {"k": 3}
	field := {"op": "present", "path": ["m", {"named_by_field": "p"}]}
	ergo._m_key_fault_pieces({"p": 4}, field) == [ergo._m_clause("root", "p", "unusable", "p is 4, which isn't text")]
	named := {"op": "present", "path": ["m", {"named_by": "e"}]}
	ergo._m_key_fault_pieces({}, named) == [ergo._m_clause("root", "e", "unusable", "e is 5, which isn't text")] with input as {"ergo/names": {"e": 5}}
}
