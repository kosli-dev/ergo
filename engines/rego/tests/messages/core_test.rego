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
	ergo._m_null_key_parts({"s": null, "p": null}, check) == ["p is null", "s is null"]
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

test_a_row_says_what_else_it_cant_read_beside_a_key_it_cant_read if {
	check := {"op": "compare", "cmp": "eq", "left": ["k"], "right": ["m", {"ref": ["$$params", "k"]}], "expression": "k is m named by $params.k"}
	row := object.union(check, {"ergo/row": true})
	ergo._m_unkeyed_said({}, row, "absent") == ["k is missing"] with data.ergo_params as {}
	ergo._m_message(row, {}, "absent") == "$params.k is missing, and k is missing" with data.ergo_params as {}
	ergo._m_unkeyed_said({}, check, "absent") == [] with data.ergo_params as {}
}

test_a_count_whose_ignoring_case_keeps_the_items_of_its_list_from_the_params_in_list_order if {
	whose := {"ignoring": "case", "op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}}
	check := {"op": "compare", "cmp": "eq", "left": {"count_of": ["xs"], "text": "count of xs whose v is in $params.l ignoring case", "whose": [whose]}, "right": {"literal": 1}}
	"$params.l" in ergo._m_list_names(check)
	ergo._m_top_sorted("item 2 of $params.l is null, and item 3 of $params.l is 3, which isn't text", ergo._m_list_names(check)) == "item 2 of $params.l is null, and item 3 of $params.l is 3, which isn't text"
}
