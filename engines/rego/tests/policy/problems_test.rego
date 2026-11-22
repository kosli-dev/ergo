package ergo_test

import data.ergo
import rego.v1

test_the_paths_of_an_inputs_list_are_the_paths_a_model_check_reads_for_its_names if {
	ergo._own_paths({"op": "present", "path": ["x"], "inputs": [["y"], ["$zz", "c"], {"z": 1}]}, "inputs") == [["y"], ["$zz", "c"]]
}

test_a_list_after_the_words_that_holds_text_and_other_values_names_each_item_and_does_not_break_the_check if {
	words := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	not ergo._node_param_broken(words) with data.ergo_document as {"cs": [{"name": "a"}, {"name": 3}]}
	ergo._node_param_broken(object.remove(words, ["ignoring"])) with data.ergo_document as {"cs": [{"name": "a"}, {"name": 3}]}
}
