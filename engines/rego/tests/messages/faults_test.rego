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

test_the_faults_of_a_message_are_clauses_that_say_what_a_value_isnt if {
	c := ergo._m_with_sides(ergo._s_written_check("v is at least 3"))
	ergo._m_faults({"v": "a"}, c) == [ergo._m_clause("root", "v", "unusable", `v is "a", which isn't a number`)]
	t := ergo._m_with_sides(ergo._s_written_check("v is in xs ignoring case"))
	ergo._m_faults({"v": "a", "xs": [3]}, t) == [ergo._m_clause("list", "xs", "unusable", "item 1 of xs is 3, which isn't text")]
}

test_the_parents_a_message_blames_are_clauses_that_say_which_cant_hold_the_next_key if {
	c := ergo._m_with_sides(ergo._s_written_check("m.x is 1"))
	m := ergo._m_clause("root", "m", "unusable", "m is 3, which isn't an object")
	ergo._m_blocked({"m": 3}, c) == [m]
	ergo._m_blocked_early({"m": 3}, c) == [m]
	ergo._m_parent_clause({"m": 3}, c, "m.x") == ["m is 3, which isn't an object"]
	p := ergo._m_clause("root", "$params.p", "unusable", "$params.p is 3, which isn't an object")
	early := ergo._m_with_sides(ergo._s_written_check("v is $params.p.q"))
	ergo._m_params_faults_early({"v": 1}, early) == [p] with data.ergo_params as {"p": 3}
	late := ergo._m_with_sides(ergo._s_written_check("v is in $params.p named by k"))
	ergo._m_blocked_late({"v": 1, "k": "a"}, late) == [p] with data.ergo_params as {"p": 3}
}
