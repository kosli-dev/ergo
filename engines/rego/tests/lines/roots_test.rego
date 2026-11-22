package ergo_test

import data.ergo
import rego.v1

test_an_every_leaf_compared_with_a_plain_value_reads_no_root if {
	check := {"op": "every", "path": ["xs"], "check": {"op": "compare", "left": ["v"], "cmp": "eq", "right": 1}}
	ergo._leaf_without_roots(check.check)
	ergo._leaf_root_flaw(check, {"xs": [{"v": 1}]}) == ""
}

test_a_right_side_that_is_a_ref_is_the_root_it_reads if {
	ergo._side_root({"right": {"ref": ["$$params", "q"]}}, ["$$params", "q"])
	ergo._side_root({"right": ["$$params", "q"]}, ["$$params", "q"])
}

test_a_left_side_is_a_root_as_much_as_a_right_side if {
	ergo._side_root({"left": ["$$params", "q"], "right": 1}, ["$$params", "q"])
	not ergo._side_root({"left": ["v"], "right": 1}, ["$$params", "q"])
}

test_a_root_a_whose_cant_read_stands_in_for_a_value_so_each_item_is_still_read if {
	same := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["$$params", "p"]}
	ergo._root_stand_in(same) == {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["v"]}
	order := {"op": "compare", "cmp": "gte", "left": ["v"], "right": ["$$params", "min"]}
	ergo._root_stand_in(order) == {"op": "compare", "cmp": "gte", "left": ["v"], "right": {"literal": 0}}
	timed := {"op": "compare_time", "cmp": "gt", "left": ["at"], "right": ["$$params", "t"]}
	ergo._root_stand_in(timed) == {"op": "compare_time", "cmp": "gt", "left": ["at"], "right": {"literal": "1970-01-01T00:00:00Z"}}
	listed := {"op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}}
	ergo._root_stand_in(listed) == {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["v"]}
}

test_a_root_list_after_is_in_ignoring_case_stands_in_for_text_so_an_item_whose_own_value_isnt_text_is_still_named if {
	listed := {"op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._root_stand_in(listed) == {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["v"], "ignoring": "case"}
	ergo._leaf_cause(ergo._root_stand_in(listed), {"v": 5}) == "unusable"
	field := {"op": "compare", "cmp": "in", "left": ["v"], "right": [`${"alias":"thing","n":0,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._leaf_cause(ergo._root_stand_in(field), {"v": 5}) == "unusable"
	ergo._root_stand_in(object.union(listed, {"op": "not_in"})) == {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["v"], "ignoring": "case"}
	ergo._leaf_cause(ergo._root_stand_in(object.union(field, {"cmp": "not_in"})), {"v": 5}) == "unusable"
	ergo._root_stand_in(object.union(field, {"cmp": "not_in"})).cmp == "eq"
}

test_a_list_after_is_in_ignoring_case_in_a_one_line_every_is_a_root_read_before_any_item if {
	field := {"op": "compare", "cmp": "in", "left": ["x"], "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	every_field := {"op": "every", "path": ["xs", "x"], "check": field, "whose": [], "if_any": true}
	ergo._walk_root_flaw(every_field, {"xs": [], "ys": ["a", null]}) == "null"
	ergo._walk_root_flaw(every_field, {"xs": [], "ys": [1, "a"]}) == "unusable"
	ergo._walk_root_flaw(every_field, {"xs": [], "ys": ["a"]}) == ""
	ergo._walk_root_flaw(every_field, {"xs": [], "ys": 3}) == ""
	ergo._walk_root_flaw(every_field, {"xs": []}) == ""
	not ergo._items_judged_alone({"xs": [{"x": 2}], "ys": 3}, every_field)
	not ergo._items_judged_alone({"xs": [{"x": 2}]}, every_field)
	ergo._walk_root_flaw(object.union(object.remove(every_field, ["check"]), {"check": object.remove(field, ["ignoring"])}), {"xs": [], "ys": ["a", null]}) == ""
	ergo._walk_root_msgs(every_field, {"xs": [], "ys": ["a", null]}) == ["item 2 of ys is null"]
	ergo._walk_root_msgs(every_field, {"xs": [], "ys": [1, "a"]}) == ["item 1 of ys is 1, which isn't text"]
	ergo._items_judged_alone({"xs": [], "ys": [3]}, every_field)
	not ergo._items_judged_alone({"xs": [], "ys": ["a"]}, every_field)
	ergo._whose_alone({"xs": [], "ys": [3]}, every_field).check == {"op": "in", "path": ["x"], "values": [""], "ignoring": "case"}
	ergo._whose_alone({"xs": [], "ys": [3]}, object.union(every_field, {"check": {"cmp": "not_in"}})).check == {"op": "in", "path": ["x"], "values": [""], "ignoring": "case"}
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	every_ref := {"op": "every", "path": ["xs", "x"], "check": ref, "whose": [], "if_any": true}
	ergo._walk_root_flaw(every_ref, {"xs": []}) == "null" with data.ergo_params as {"l": [null]}
	ergo._walk_root_msgs(every_ref, {"xs": []}) == ["item 1 of $params.l is null"] with data.ergo_params as {"l": [null]}
}

test_a_root_a_whose_cant_read_has_no_stand_in_after_a_key_or_a_phrase_b9_leaves_out if {
	keyed := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["$$params", "m", {"ref": ["$$params", "k"]}]}
	ergo._root_stand_in(keyed) == keyed
	starts := {"op": "compare", "cmp": "starts_with", "left": ["v"], "right": ["$$params", "p"]}
	ergo._root_stand_in(starts) == starts
	includes := {"op": "includes", "path": ["tags"], "value": {"ref": ["$$params", "t"]}}
	ergo._root_stand_in(includes) == includes
}

test_a_root_list_after_is_in_ignoring_case_fails_with_the_worst_cause_of_its_items_and_names_each if {
	ref := {"op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	p := ["$$params[]", "l"]
	ergo._root_state({"v": "a"}, ref, p, set()) == "unusable" with data.ergo_params as {"l": ["a", 3]}
	ergo._root_state({"v": "a"}, ref, p, set()) == "null" with data.ergo_params as {"l": ["a", null]}
	ergo._root_state({"v": "a"}, ref, p, set()) == "value" with data.ergo_params as {"l": ["a"]}
	ergo._m_for_root_text({"v": "a"}, ref, p, "unusable") == "item 2 of $params.l is 3, which isn't text" with data.ergo_params as {"l": ["a", 3]}
	ergo._m_for_root_text({"v": "a"}, ref, p, "null") == "item 2 of $params.l is null" with data.ergo_params as {"l": ["a", null]}
}

test_a_row_whose_items_fail_only_on_a_root_beside_a_list_after_is_in_ignoring_case_says_the_roots_and_no_item if {
	c := {"op": "in", "path": ["$$params", "k"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	check := {"op": "every", "path": ["xs"], "whose": [c], "check": {"op": "present", "path": ["x"]}, "if_any": true}
	r := ergo._walk_row(check, {"xs": [{"v": "a"}]}) with data.ergo_params as {"l": ["a", null]} with input as {}
	r.cause == "absent"
	r.root_msgs == ["$params.k is missing", "item 2 of $params.l is null"]
	not "other_roots" in object.keys(r)
	ok := ergo._walk_row(check, {"xs": [{"v": "a"}]}) with data.ergo_params as {"l": ["a"]} with input as {}
	ok.root_msgs == ["$params.k is missing"]
}
