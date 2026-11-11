package ergo_test

import data.ergo
import rego.v1

test_the_paths_of_an_inputs_list_are_the_paths_a_model_check_reads_for_its_names if {
	ergo._own_paths({"op": "present", "path": ["x"], "inputs": [["y"], ["$zz", "c"], {"z": 1}]}, "inputs") == [["y"], ["$zz", "c"]]
}
