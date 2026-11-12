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
