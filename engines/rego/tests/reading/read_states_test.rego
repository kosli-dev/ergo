package ergo_test

import data.ergo
import rego.v1

test_a_path_with_a_ref_step_that_cant_be_read_is_flawed if {
	path := ["x", {"ref": ["$$params", "k"]}]
	ergo._ref_step_flawed(path) with data.ergo_params as {}
	ergo._ref_step_flawed(path) with data.ergo_params as {"k": 3}
	not ergo._ref_step_flawed(path) with data.ergo_params as {"k": "a"}
}

test_a_null_on_the_path_stops_the_read_at_the_step_after_the_first_key if {
	ergo._null_stop_at({"c": null}, ["c", "z"]) == 1
}
