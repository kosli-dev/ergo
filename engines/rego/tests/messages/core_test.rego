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

test_a_list_after_is_in_ignoring_case_names_each_item_that_isnt_text_in_list_order if {
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._message(field, {"x": "a", "ys": ["A", 3]}, "unusable") == "item 2 of ys is 3, which isn't text"
	ergo._message(field, {"x": 3, "ys": ["a", null, {"a": 1}]}, "unusable") == `x is 3, which isn't text, and item 2 of ys is null; item 3 of ys is {"a": 1}, which isn't text`
	ergo._message(object.union(field, {"cmp": "not_in"}), {"x": "a", "ys": [null]}, "null") == "item 1 of ys is null"
	ergo._message(object.union(field, {"ergo/row": true}), {"ys": [null]}, "null") == "x is missing, and item 1 of ys is null"
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._message(ref, {"x": "a"}, "unusable") == "item 1 of $params.l is 1, which isn't text" with data.ergo_params as {"l": [1, "a"]}
	ergo._message(ref, {"x": "a"}, "null") == "item 1 of $params.l is null" with data.ergo_params as {"l": [null]}
	ergo._message(object.union(ref, {"ergo/row": true}), {}, "null") == "x is missing, and item 1 of $params.l is null" with data.ergo_params as {"l": [null]}
	ergo._message(ref, {"x": "a"}, "unusable") == `$params.l is "s", which isn't a list` with data.ergo_params as {"l": "s"}
}

test_a_list_walked_from_the_input_after_is_in_ignoring_case_names_each_item_it_cant_use_as_the_walk_names_it if {
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._message(ref, {"x": "a"}, "unusable") == "item 1 of $input.cs: name is null; item 3 of $input.cs: name is true, which isn't text" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}, {"name": true}]}
	ergo._message(ref, {"x": "a"}, "unusable") == "item 2 of $input.cs: name is 3, which isn't text" with data.ergo_document as {"cs": [{"name": "a"}, {"name": 3}]}
	ergo._message(ref, {"x": "a"}, "unusable") == "item 1 of $input.cs: name is missing; item 2 of $input.cs: name is 3, which isn't text" with data.ergo_document as {"cs": [{}, {"name": 3}]}
	ergo._message(ref, {"x": "a"}, "unusable") == "item 1 of $input.cs is 3, which isn't an object; item 2 of $input.cs: name is 5, which isn't text" with data.ergo_document as {"cs": [3, {"name": 5}]}
}

test_a_list_after_is_in_ignoring_case_that_cant_be_used_is_said_beside_a_field_that_cant_be_read_whatever_its_cause if {
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case", "ergo/row": true}
	ergo._message(field, {"ys": ["a", null]}, "absent") == "x is missing, and item 2 of ys is null"
	ergo._message(field, {"ys": [3]}, "unusable") == "x is missing, and item 1 of ys is 3, which isn't text"
	ergo._message(field, {"x": null, "ys": [3]}, "unusable") == "x is null, and item 1 of ys is 3, which isn't text"
	ergo._message(field, {"x": 3, "ys": ["a", null]}, "unusable") == "x is 3, which isn't text, and item 2 of ys is null"
	ref := {"op": "in", "path": ["$$params", "k"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case", "ergo/row": true}
	ergo._message(ref, {}, "absent") == "$params.k is missing, and item 2 of $params.l is null" with data.ergo_params as {"l": ["a", null]}
	ergo._message(ref, {}, "unusable") == "$params.k is 3, which isn't text, and item 2 of $params.l is null" with data.ergo_params as {"k": 3, "l": ["a", null]}
	ergo._message(ref, {}, "unusable") == "$params.k is missing, and item 1 of $params.l is 3, which isn't text" with data.ergo_params as {"l": [3]}
}
