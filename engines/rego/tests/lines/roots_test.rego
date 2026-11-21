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
	field := {"op": "compare", "left": ["v"], "cmp": "in", "right": ["$$ergo/root", "ys"], "ignoring": "case"}
	q := ["$$ergo/root", "ys"]
	ergo._root_state({"v": "a"}, field, q, set()) == "unusable" with input as {"ergo/names": {"ergo/subject": {"ys": [3]}}}
	ergo._root_state({"v": "a"}, field, q, set()) == "null" with input as {"ergo/names": {"ergo/subject": {"ys": ["a", null]}}}
	ergo._m_for_root_text({"v": "a"}, field, q, "unusable") == "item 1 of ys is 3, which isn't text" with input as {"ergo/names": {"ergo/subject": {"ys": [3]}}}
}
