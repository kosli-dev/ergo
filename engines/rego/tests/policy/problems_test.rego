package ergo_test

import data.ergo
import rego.v1

test_the_paths_of_an_inputs_list_are_the_paths_a_model_check_reads_for_its_names if {
	ergo._own_paths({"op": "present", "path": ["x"], "inputs": [["y"], ["$zz", "c"], {"z": 1}]}, "inputs") == [["y"], ["$zz", "c"]]
}

test_a_list_of_params_with_an_item_that_isnt_text_breaks_is_in_ignoring_case_and_a_null_item_doesnt if {
	check := {"op": "in", "path": ["v"], "values": {"ref": ["$$params", "l"]}, "ignoring": "case"}
	ergo._node_param_broken(check) with data.ergo_params as {"l": ["a", 3]}
	not ergo._node_param_broken(check) with data.ergo_params as {"l": ["a", null]}
	not ergo._node_param_broken(check) with data.ergo_params as {"l": ["a", "b"]}
}
