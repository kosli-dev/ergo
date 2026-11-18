package ergo_test

import data.ergo
import rego.v1

test_message_of_a_passed_walk_has_no_parts if {
	ergo._m_fail_parts("satisfied", [], set()) == []
}

test_a_clause_an_earlier_sentence_gave_is_left_out_but_a_quoted_value_is_one_clause if {
	ergo._m_said_new(["x is missing", "x is missing, and y is missing", "y is missing"]) == ["x is missing", "y is missing"]
	ergo._m_said_new(["x is \"a, and b\"", "x is \"a, and b\", and z is 1"]) == ["x is \"a, and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\", and b\"", "x is \"a\\\", and b\"; z is 1"]) == ["x is \"a\\\", and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\\\", and b is 1", "b is 1"]) == ["x is \"a\\\\\", and b is 1"]
	ergo._m_said_new(["item 1 of xs: a; item 2 of xs: b", "item 2 of xs: b; c"]) == ["item 1 of xs: a; item 2 of xs: b", "c"]
	ergo._m_quote_split("x is \"a, and b", ", and ") == ["x is \"a, and b"]
}

test_message_a_for_alias_loses_its_marker_and_a_value_that_spells_the_alias_stays if {
	ergo._m_aliased("x is \u0002c, and \"$c: y\"") == "x is c, and \"$c: y\""
	ergo._m_aliased("x is 1") == "x is 1"
}

test_message_a_key_named_by_another_name_is_another_name if {
	ergo._m_other_name({"named_by": "z"}, "c")
	ergo._m_other_name({"named_by_field": "z"}, "c")
	not ergo._m_other_name({"named_by": "c"}, "c")
}

test_message_of_a_walk_whose_path_is_not_a_path_names_no_blocked_parent if {
	ergo._m_walk_blocked({}, {"path": "x"}) == []
}

test_message_of_a_walk_that_failed_without_a_list_to_show_repeats_its_expression if {
	check := {"path": ["xs"], "expression": "every xs.ok is true"}
	ergo._walk_parts(check, {}, {"cause": "value"}, {"failed": []}) == ["every xs.ok is true is false"]
}

test_message_names_an_item_by_the_part_of_the_subject_it_goes_through if {
	marker := ergo._p_marker("cov", 0, null, false)
	ergo._m_item_name(["xs", marker, "z"], set()) == "cov.z"
	ergo._m_off_item_path(["xs", marker])
	not ergo._m_off_item_path(["xs", "z"])
}
