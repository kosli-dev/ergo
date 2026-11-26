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

_said_of(sentence, subj, cause, params) := said if {
	said := ergo._message_said(ergo._s_written_check(sentence), subj, cause) with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as params
}

_message_of(sentence, subj, cause, params) := m if {
	m := ergo._message(ergo._s_written_check(sentence), subj, cause) with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as params
}

test_a_message_is_its_pieces_joined_with_and if {
	_said_of("v is w", {"v": 3, "w": 4}, "value", {}) == [["v is 3", "w is 4"]]
	_message_of("v is w", {"v": 3, "w": 4}, "value", {}) == "v is 3, and w is 4"
}

test_a_message_keeps_what_a_count_says_as_its_clauses if {
	subj := {"es": [{}, {}]}
	[[counted]] := _said_of("count of es whose v is at least $params.min is 0", subj, "unusable", {"min": "s"})
	[c.kind | some c in counted] == ["root", "item", "item"]
	text := `$params.min is "s", which isn't a number; item 1 of es: v is missing; item 2 of es: v is missing`
	ergo._m_clauses_text(ergo._m_clauses_shown(counted)) == text
	_message_of("count of es whose v is at least $params.min is 0", subj, "unusable", {"min": "s"}) == text
}

test_a_key_that_cant_be_read_and_the_value_before_it_are_two_groups_of_the_message if {
	_said_of("m named by $params.k is 1", {"m": 3}, "unusable", {}) == [["$params.k is missing"], ["m is 3, which isn't an object"]]
	_message_of("m named by $params.k is 1", {"m": 3}, "unusable", {}) == "$params.k is missing; m is 3, which isn't an object"
}

test_a_row_says_what_else_it_cant_read_beside_a_key_it_cant_read if {
	check := {"op": "compare", "cmp": "eq", "left": ["k"], "right": ["m", {"ref": ["$$params", "k"]}], "expression": "k is m named by $params.k"}
	row := object.union(check, {"ergo/row": true})
	_piece_strings(ergo._m_unkeyed_said({}, row, "absent")) == ["k is missing"] with data.ergo_params as {}
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

test_a_list_walked_from_the_input_after_is_in_ignoring_case_is_said_beside_a_field_that_cant_be_read_whatever_its_cause if {
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case", "ergo/row": true}
	ergo._message(ref, {}, "absent") == "x is missing, and item 2 of $input.cs: name is null" with data.ergo_document as {"cs": [{"name": "a"}, {"name": null}]}
	ergo._message(ref, {"x": 3}, "unusable") == "x is 3, which isn't text, and item 2 of $input.cs: name is null" with data.ergo_document as {"cs": [{"name": "a"}, {"name": null}]}
	params := object.union(ref, {"path": ["$$params", "k"]})
	ergo._message(params, {}, "absent") == "$params.k is null, and item 2 of $input.cs: name is missing" with data.ergo_document as {"cs": [{"name": "a"}, {}]} with data.ergo_params as {"k": null}
}

test_a_list_after_is_in_ignoring_case_names_three_items_it_cant_use_and_counts_the_rest if {
	l := [1, 2, 3, 4, 5, 6, 7, null]
	said := "item 1 of $params.l is 1, which isn't text; item 2 of $params.l is 2, which isn't text; item 3 of $params.l is 3, which isn't text; and 5 more"
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._message(ref, {"x": "a"}, "unusable") == said with data.ergo_params as {"l": l}
	ergo._m_for_root_text({"x": "a"}, ref, ["$$params[]", "l"], "unusable") == said with data.ergo_params as {"l": l}
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._message(field, {"x": "a", "ys": [null, null, null, 3]}, "unusable") == "item 1 of ys is null; item 2 of ys is null; item 3 of ys is null; and 1 more"
	ergo._message(field, {"x": "a", "ys": [null, 2, null]}, "unusable") == "item 1 of ys is null; item 2 of ys is 2, which isn't text; item 3 of ys is null"
}

test_a_walked_part_list_after_is_in_ignoring_case_names_each_item_as_a_walk_does_after_what_the_field_cant_give if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	leaf := {"op": "compare", "cmp": "in", "left": ["v"], "right": part, "ignoring": "case"}
	three := {"v": 3, "p": [{"name": "a"}, {}]}
	_piece_strings(ergo._m_message_pieces(ergo._m_with_sides(ergo._m_walked(leaf, three)), three, "unusable")) == ["v is 3, which isn't text", "item 2 of pl: name is missing"] with input as {"ergo/names": {"ergo/subject": three}}
	broken := {"v": "a", "p": [{"name": 3}, {}]}
	_piece_strings(ergo._m_message_pieces(ergo._m_with_sides(ergo._m_walked(leaf, broken)), broken, "unusable")) == ["item 1 of pl: name is 3, which isn't text; item 2 of pl: name is missing"] with input as {"ergo/names": {"ergo/subject": broken}}
	five := {"v": 3, "p": [{"name": "a"}, {"name": 5}]}
	_piece_strings(ergo._m_message_pieces(ergo._m_with_sides(ergo._m_walked(leaf, five)), five, "unusable")) == ["v is 3, which isn't text", "item 2 of pl: name is 5, which isn't text"] with input as {"ergo/names": {"ergo/subject": five}}
	params := {"p": [{"name": "a"}, {}]}
	row := object.union(object.union(leaf, {"left": ["$$params", "k"]}), {"ergo/row": true})
	_piece_strings(ergo._m_message_pieces(ergo._m_with_sides(ergo._m_walked(row, params)), params, "absent")) == ["$params.k is null", "item 2 of pl: name is missing"] with input as {"ergo/names": {"ergo/subject": params}} with data.ergo_params as {"k": null}
}

test_a_walked_part_list_after_is_in_ignoring_case_is_said_after_the_field_so_its_part_is_one_of_the_lists_a_message_names_last if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	leaf := {"op": "compare", "cmp": "in", "left": ["v"], "right": part, "ignoring": "case"}
	"pl" in ergo._m_list_names(leaf)
	"pl.name" in ergo._m_list_names(leaf)
	ergo._m_list_names(object.union(leaf, {"right": ["ys"]})) == {"ys"}
	ergo._m_list_names(object.remove(leaf, ["ignoring"])) == set()
}

test_a_row_says_the_items_of_a_list_after_is_in_ignoring_case_read_from_each_item_of_a_subject_that_is_a_list_after_the_field_and_in_list_order if {
	c := {"op": "compare", "cmp": "in", "left": ["$$params", "v"], "right": [`${"alias":"thing","n":0,"of":null,"old":false}`, "states"], "ignoring": "case"}
	subj := [{"states": ["A"]}, {"states": [null, 4]}]
	ergo._m_row_text(c, subj, "unusable") == "$params.v is 3, which isn't text, and item 2 of thing: item 1 of states is null; item 2 of thing: item 2 of states is 4, which isn't text" with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as {"v": 3}
	ergo._m_row_text(c, subj, "unusable") == "item 2 of thing: item 1 of states is null; item 2 of thing: item 2 of states is 4, which isn't text" with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as {"v": "a"}
	ergo._m_row_text(c, [{"states": ["a", 3]}], "unusable") == "$params.v is null, and item 1 of thing: item 2 of states is 3, which isn't text" with input as {"ergo/names": {"ergo/subject": [{"states": ["a", 3]}]}} with data.ergo_params as {"v": null}
}

test_a_piece_that_is_a_clause_prints_as_its_text if {
	c := ergo._m_clause("root", "a", "absent", "a is missing")
	ergo._m_piece_text(c) == "a is missing"
	ergo._m_pieces_text([c, "x is null"]) == "a is missing, and x is null"
	ergo._m_pieces_once([c, "a is missing", "x is null"]) == [c, "x is null"]
}

test_a_state_piece_is_a_root_clause_with_the_state_as_its_cause if {
	ergo._m_state_piece({"name": "a", "state": "absent"}) == ergo._m_clause("root", "a", "absent", "a is missing")
	ergo._m_state_piece({"name": "a", "state": "null"}) == ergo._m_clause("root", "a", "null", "a is null")
}

test_a_state_piece_with_a_text_keeps_that_text if {
	ergo._m_state_piece({"name": "xs", "state": "absent", "text": "xs can't be read: x"}).text == "xs can't be read: x"
	ergo._m_state_piece({"name": "xs", "state": "absent", "text": "xs can't be read: x"}).cause == "absent"
}

_piece_strings(ps) := [ergo._m_piece_string(p) | some p in ps]

test_the_items_of_a_list_that_arent_text_are_one_list_clause if {
	subj := {"v": "a"}
	c := ergo._m_with_sides(ergo._s_written_check("v is in $params.l ignoring case"))
	said := ergo._m_text_list_said(subj, c, "unusable") with data.ergo_params as {"l": ["a", 3]} with input as {"ergo/names": {"ergo/subject": subj}}
	said == [ergo._m_clause("list", "$params.l", "unusable", "item 2 of $params.l is 3, which isn't text")]
}

test_a_sum_that_needs_more_than_15_digits_is_a_clause if {
	subj := {"ns": [123456789012345678, 1]}
	c := ergo._m_with_sides(ergo._s_written_check("sum of ns is 3"))
	ergo._m_message_pieces(c, subj, "unusable") == [ergo._m_clause("root", "sum of ns", "unusable", "sum of ns needs more than 15 digits")] with input as {"ergo/names": {"ergo/subject": subj}}
}

test_a_key_piece_is_a_root_clause_named_by_the_key_and_its_state if {
	check := {"op": "compare", "cmp": "eq", "left": ["k"], "right": ["m", {"ref": ["$$params", "k"]}], "expression": "k is m named by $params.k"}
	ergo._m_key_pieces({}, check, "absent") == [ergo._m_clause("root", "$params.k", "absent", "$params.k is missing")] with data.ergo_params as {}
	ergo._m_key_states({}, check, "absent") == ["$params.k is missing"] with data.ergo_params as {}
}
