package ergo_test

import data.ergo
import rego.v1

test_a_path_with_a_ref_step_that_cant_be_read_is_flawed if {
	path := ["x", {"ref": ["$$params", "k"]}]
	ergo._ref_step_flawed(path) with data.ergo_params as {}
	ergo._ref_step_flawed(path) with data.ergo_params as {"k": 3}
	not ergo._ref_step_flawed(path) with data.ergo_params as {"k": "a"}
}

test_a_ref_that_is_not_a_path_in_the_input_or_the_params_has_no_location if {
	ergo._ref_entries({["x"]}) == [{"name": "<invalid ref>", "value": null, "locations": []}]
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

test_a_null_on_the_path_stops_the_read_at_the_step_after_the_first_key if {
	ergo._null_stop_at({"c": null}, ["c", "z"]) == 1
}
