package ergo_test

import data.ergo
import rego.v1

test_an_input_outcome_of_missing_is_the_cause_absent if {
	ergo._cause_of_outcome("missing") == "absent"
	ergo._cause_of_outcome("null") == "null"
}

test_a_tally_word_that_is_neither_missing_nor_null_turns_absent_and_null_into_unusable if {
	ergo._tally_word_cause("xs is text", "absent") == "unusable"
	ergo._tally_word_cause("xs is text", "null") == "unusable"
	ergo._tally_word_cause("xs is text", "not_an_object") == "not_an_object"
	ergo._tally_word_cause("xs is missing", "absent") == "absent"
}

test_a_check_without_a_checks_list_in_its_where_is_its_own_text if {
	ergo._sub_mcheck({"check": {"checks": []}}, "c", {}) == "c"
}

test_a_walked_name_that_is_not_a_path_is_empty if {
	ergo._walked_name("xs") == ""
	ergo._walked_name(["xs"]) != ""
}

test_a_tally_with_no_lists_has_no_list_entries if {
	ergo._tally_list_entries({}, [], set(), []) == []
}

test_an_intermediate_join_with_no_own_entries_takes_the_name_and_value_of_the_item if {
	ergo._ms_join2([], [{"name": "xs", "value": 1, "locations": ["/xs"]}], []).name == "xs"
}

test_an_item_input_named_like_a_parent_keeps_its_dot_and_any_other_name_stays_plain if {
	ergo._item_input_name(["cov", 0]) == ".cov[0]" with data.ergo_parent as {"cov": {"from": "covs"}}
	ergo._item_input_name(["xs", 0]) == "xs[0]" with data.ergo_parent as {"cov": {"from": "covs"}}
}

test_a_counted_field_named_by_a_key_the_subject_lacks_is_found_by_the_whole_path_rule_first if {
	c := ergo._s_written_check("count of xs named by k is 1")
	ergo._tally_unkeyed_list_names(c, {}) == {"xs named by k"}
	ergo._tally_list_paths(c, "xs named by k") == [["xs", {"named_by_field": "k"}]]
}

test_a_from_without_a_path_gives_no_key_reads if {
	ergo._ms_key_reads({}) == []
}

test_a_list_named_in_a_message_but_found_in_no_path_keeps_the_input_it_was_read_from if {
	ergo._tally_list_read("xs", "absent", {}, [{"name": "xs", "value": 1}, {"name": "ys", "value": 2}], []) == [{"name": "xs", "value": 1, "outcome": "absent"}]
}

test_an_item_two_conditions_of_a_count_cant_decide_is_one_entry_that_says_both if {
	check := {
		"op": "compare", "cmp": "eq", "expression": "count of es whose v is 1 and whose w is 1 is 0",
		"left": {"count_of": ["es"], "text": "count of es whose v is 1 and whose w is 1", "whose": [
			{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
			{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
		]},
		"right": {"literal": 0},
	}
	parts := ergo._tally_item_parts(check, {"es": [{}]}, "absent", "/things/0", "item 1 of es: v is missing; item 1 of es: w is missing")
	[[p.name, p.cause, p.message] | some p in parts] == [["item 1 of es", "absent", "v is missing; w is missing"]]
}

test_a_counted_list_named_by_a_key_is_never_an_input_of_the_assertion_even_with_no_failed_items if {
	field := ergo._s_written_check("count of m named by p is at least 3")
	ergo._tally_own_read({"name": "m named by p[]", "value": [1, 2]}, field, set(), [])
	param := ergo._s_written_check("q is sum of m named by $params.k")
	ergo._tally_own_read({"name": "m named by $params.k[]", "value": [1, 2]}, param, set(), [])
}
