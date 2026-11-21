package ergo_test

import data.ergo
import rego.v1

test_a_path_with_a_ref_step_that_cant_be_read_is_flawed if {
	path := ["x", {"ref": ["$$params", "k"]}]
	ergo._ref_step_flawed(path) with data.ergo_params as {}
	ergo._ref_step_flawed(path) with data.ergo_params as {"k": 3}
	not ergo._ref_step_flawed(path) with data.ergo_params as {"k": "a"}
}

test_listed_refs_skip_meta_and_description_but_not_an_option_named_meta if {
	ergo._listed_refs({"op": "present", "path": ["v"], "meta": {"ref": ["$$params", "a"]}, "description": ["$$params", "b"]}) == set()
	ergo._listed_refs({"any_of": {"meta": {"op": "present", "path": ["$$params", "a"]}}}) == {["$$params", "a"]}
	ergo._listed_refs(["$$params", "a"]) == {["$$params", "a"]}
}

test_listed_refs_name_a_walked_path_as_is_in_does if {
	ergo._listed_refs({"op": "every", "path": ["$$params", "o", "x"], "check": {"op": "present", "path": []}, "whose": []}) == {["$$params[]", "o", "x"]}
	ergo._listed_refs({"op": "for", "items": [{"as": "o", "path": ["$$input", "o"], "q": "some"}], "checks": []}) == {["$$input[]", "o"]}
	ergo._listed_refs({"op": "compare", "left": {"count_of": ["$$params", "o"]}, "right": ["$$params", "n"]}) == {["$$params[]", "o"], ["$$params", "n"]}
}

test_listed_refs_name_the_path_before_named_by_and_not_a_walk_of_it if {
	ergo._listed_refs({"op": "present", "path": ["$$params", "m", {"named_by_field": "k"}]}) == {["$$params", "m"]}
	ergo._listed_refs({"op": "every", "path": ["$$params", "o", {"named_by_field": "k"}], "check": {"op": "present", "path": []}, "whose": []}) == {["$$params", "o"]}
	ergo._listed_refs({"op": "compare", "left": ["v"], "right": ["$$input", "m", 0, {"named_by": "it"}, "k"]}) == {["$$input", "m", 0]}
	ergo._listed_refs({"op": "compare", "left": ["v"], "right": ["$$input", "m", {"ref": ["$$params", "a"]}]}) == {["$$input", "m"], ["$$params", "a"]}
	ergo._listed_refs({"op": "compare", "left": ["v"], "right": ["m", {"named_by_field": "k"}]}) == set()
}

test_a_null_on_the_path_stops_the_read_at_the_step_after_the_first_key if {
	ergo._null_stop_at({"c": null}, ["c", "z"]) == 1
}

test_is_in_ignoring_case_fails_on_a_list_item_that_isnt_text_whatever_the_field_holds if {
	cases := [
		[["A", 3], "unusable"],
		[[1, "a"], "unusable"],
		[[null], "null"],
		[["a", null], "null"],
		[["a", null, 3], "unusable"],
		[["a", ["a"]], "unusable"],
		[["a", {"a": 1}], "unusable"],
		[[true], "unusable"],
	]
	every c in cases {
		every cmp in ["in", "not_in"] {
			field := {"op": "compare", "left": ["x"], "cmp": cmp, "right": ["ys"], "ignoring": "case"}
			every subj in [{"x": "a", "ys": c[0]}, {"x": 3, "ys": c[0]}, {"x": null, "ys": c[0]}, {"ys": c[0]}] {
				ergo._leaf_cause(field, subj) == c[1]
			}
			ref := {"op": cmp, "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
			every subj in [{"x": "a"}, {"x": 3}, {"x": null}, {}] {
				ergo._leaf_cause(ref, subj) == c[1] with data.ergo_params as {"l": c[0]}
			}
		}
	}
}

test_is_in_ignoring_case_compares_with_a_list_from_the_input_once_both_sides_are_prepared if {
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case and surrounding spaces"}
	ergo._leaf_cause(field, {"x": " Bug ", "ys": ["incident", "BUG"]}) == "satisfied"
	ergo._leaf_cause(object.union(field, {"cmp": "not_in"}), {"x": " Bug ", "ys": ["incident", "BUG"]}) == "value"
	ergo._leaf_cause(field, {"x": "bug", "ys": []}) == "value"
	ergo._leaf_cause(object.union(field, {"cmp": "not_in"}), {"x": "bug", "ys": []}) == "satisfied"
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._leaf_cause(ref, {"x": "BUG"}) == "satisfied" with data.ergo_params as {"l": ["bug"]}
	ergo._leaf_cause(ref, {"x": 3}) == "unusable" with data.ergo_params as {"l": ["bug"]}
}

test_is_in_ignoring_case_with_a_list_walked_from_the_input_fails_with_the_worst_cause_of_its_reads_and_its_values if {
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._leaf_cause(ref, {"x": "a"}) == "unusable" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}, {"name": true}]}
	ergo._leaf_cause(ref, {"x": "a"}) == "unusable" with data.ergo_document as {"cs": [{"name": "a"}, {"name": 3}]}
	ergo._leaf_cause(ref, {"x": "a"}) == "unusable" with data.ergo_document as {"cs": [{}, {"name": 3}]}
	ergo._leaf_cause(ref, {"x": "a"}) == "null" with data.ergo_document as {"cs": [{"name": null}]}
	ergo._leaf_cause(ref, {"x": "a"}) == "absent" with data.ergo_document as {"cs": [{"name": "a"}, {}]}
	ergo._leaf_cause(ref, {"x": "A"}) == "satisfied" with data.ergo_document as {"cs": [{"name": "a"}]}
}

test_a_list_walked_from_the_input_after_is_in_ignoring_case_is_a_ref_used_with_the_worst_cause_of_its_reads_and_its_values if {
	r := ["$$input[]", "cs", "name"]
	ref := {"op": "in", "path": ["x"], "values": {"ref": r}, "ignoring": "case"}
	ergo._used_ref_state(ref, r) == "unusable" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}, {"name": true}]}
	ergo._used_ref_state(ref, r) == "null" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}]}
	ergo._used_ref_state(object.remove(ref, ["ignoring"]), r) == "null" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}, {"name": true}]}
}

