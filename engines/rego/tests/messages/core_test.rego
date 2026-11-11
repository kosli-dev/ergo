package ergo_test

import data.ergo
import rego.v1

test_message_of_an_object_whose_keys_are_long_counts_its_keys if {
	long := {"aaaaaaaaaaaa": 1, "bbbbbbbbbbbb": 2, "cccccccccccc": 3, "dddddddddddd": 4, "eeeeeeeeeeee": 5}
	ergo._m_object_item(long) == "an object with 5 keys"
}

test_message_prints_null_inside_a_flat_object if {
	ergo._m_flat_value(null)
	ergo._m_flat(null) == "null"
	ergo._m_object_item({"a": null}) == "{\"a\": null}"
}

test_message_names_the_kind_of_null if {
	ergo._m_kind(null) == "null"
}

test_message_a_check_whose_path_is_not_a_path_has_only_its_refs_as_sides if {
	ergo._m_found_sides({"op": "for", "path": "x"}) == []
}

test_a_null_before_an_unreadable_key_is_read_from_the_sides_a_check_already_carries if {
	check := {"$sides": [["s", {"named_by_field": "p"}]], "op": "present", "path": ["other"]}
	ergo._m_null_key_parts({"s": null, "p": null}, check) == ["s is null", "p is null"]
}

test_message_of_an_unusable_check_with_nothing_to_blame_repeats_its_expression if {
	check := {"$sides": [], "op": "present", "path": ["x"], "expression": "x exists"}
	ergo._m_message(check, {"x": 1}, "unusable") == "x exists is false"
}

test_message_of_a_check_with_no_value_to_show_repeats_its_expression if {
	check := {"$sides": [], "op": "present", "path": ["x"], "expression": "x exists"}
	ergo._m_message(check, {"x": 1}, "value") == "x exists is false"
}

test_message_of_a_missing_check_that_finds_nothing_missing_repeats_its_expression if {
	check := {"$sides": [], "op": "present", "path": ["x"], "expression": "x exists"}
	ergo._m_message(check, {"x": 1}, "absent") == "x exists is false"
	ergo._m_message(check, {"x": 1}, "null") == "x exists is false"
}

test_message_of_exists_on_a_null_field_says_it_is_null_whatever_cause_the_line_has if {
	check := {"$sides": [["x"]], "op": "present", "path": ["x"], "expression": "x exists"}
	ergo._m_message(check, {"x": null}, "absent") == "x is null"
}
