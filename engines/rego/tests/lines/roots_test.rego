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

test_a_part_root_after_any_list_phrase_stands_in_for_a_value_so_each_item_is_still_read if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	every cmp in ["in", "not_in", "includes", "excludes"] {
		ergo._root_stand_in({"op": "compare", "cmp": cmp, "left": ["v"], "right": part}) == {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["v"]}
	}
	every cmp in ["matches_any", "not_matches_any", "includes_all", "excludes_all", "includes_some", "not_includes_all"] {
		c := {"op": "compare", "cmp": cmp, "left": ["v"], "right": part}
		ergo._root_stand_in(c) != c
	}
}

test_a_root_stand_in_after_a_phrase_that_needs_a_list_still_fails_an_item_that_isnt_one if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	ref := {"ref": ["$$params[]", "cs", "name"]}
	conds := array.concat(
		[{"op": op, "path": ["tags"], "values": ref} | some op in ["includes", "excludes", "includes_some", "not_includes_all"]],
		[{"op": "compare", "cmp": cmp, "left": ["tags"], "right": part} | some cmp in ["includes_all", "excludes_all", "includes_some", "not_includes_all"]],
	)
	every c in conds {
		[ergo._row_cause(ergo._root_stand_in(c), item, "") | some item in [{"tags": "a"}, {"tags": 3}, {"tags": {}}, {}, {"tags": null}]] == ["unusable", "unusable", "unusable", "absent", "null"]
		every tags in [[], ["a"], [1, "a"], [null]] {
			ergo._row_cause(ergo._root_stand_in(c), {"tags": tags}, "") in {"satisfied", "value"}
		}
	}
}

test_a_root_stand_in_after_a_pattern_phrase_still_fails_an_item_that_isnt_text if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	ref := {"ref": ["$$params[]", "cs", "name"]}
	conds := array.concat(
		[{"op": op, "path": ["v"], "patterns": ref} | some op in ["matches_any", "not_matches_any"]],
		[{"op": "compare", "cmp": cmp, "left": ["v"], "right": part} | some cmp in ["matches_any", "not_matches_any"]],
	)
	every c in conds {
		[ergo._row_cause(ergo._root_stand_in(c), item, "") | some item in [{"v": 3}, {"v": [1]}, {"v": {}}, {}, {"v": null}]] == ["unusable", "unusable", "unusable", "absent", "null"]
		ergo._row_cause(ergo._root_stand_in(c), {"v": "s"}, "") in {"satisfied", "value"}
	}
}

test_a_root_on_the_left_of_a_list_phrase_has_no_stand_in_so_the_item_is_still_read_as_a_list if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	every cmp in ["not_in", "matches_any", "not_matches_any", "includes_all", "excludes_all", "includes_some", "not_includes_all"] {
		c := {"op": "compare", "cmp": cmp, "left": part, "right": ["f"]}
		ergo._root_stand_in(c) == c
	}
}

test_a_root_a_whose_cant_read_has_no_stand_in_after_a_key_or_a_phrase_b9_leaves_out if {
	keyed := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["$$params", "m", {"ref": ["$$params", "k"]}]}
	ergo._root_stand_in(keyed) == keyed
	starts := {"op": "compare", "cmp": "starts_with", "left": ["v"], "right": ["$$params", "p"]}
	ergo._root_stand_in(starts) == starts
	includes := {"op": "includes", "path": ["tags"], "value": {"ref": ["$$params", "t"]}}
	ergo._root_stand_in(includes) == includes
}
