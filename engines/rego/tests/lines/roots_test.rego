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
