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

test_a_from_without_a_path_gives_no_key_reads if {
	ergo._ms_key_reads({}) == []
}
