package ergo_test

import data.ergo
import rego.v1

test_keyed_list_leaves_a_count_to_say_its_own_root if {
	not ergo._keyed_list({"op": "compare", "cmp": "gte", "left": ["approvals"], "right": {"literal": 1}})
	not ergo._keyed_list(ergo._s_written_check("count of xs whose tags contains $input.m named by key is 1"))
}

test_keyed_list_takes_only_a_one_step_list if {
	whose := [{"op": "compare", "cmp": "includes", "left": ["tags"], "right": ["$$input", "m", {"named_by_field": "key"}]}]
	ergo._keyed_clause(["xs"], whose) == whose[0]
	not ergo._keyed_clause(["xs", "v"], whose)
}

test_keyed_root_fault_names_a_step_before_the_last_that_isnt_an_object if {
	p := ["$$input", "m", "a", {"named_by_field": "key"}]
	ergo._keyed_root_fault({}, p) == {"cause": "unusable", "text": "$input.m is 3, which isn't an object"} with data.ergo_document as {"m": 3}
	ergo._keyed_root_fault({}, p) == {"cause": "unusable", "text": "$input.m.a is 3, which isn't an object"} with data.ergo_document as {"m": {"a": 3}}
	ergo._keyed_root_fault({}, p) == {"cause": "absent", "text": "$input.m.a is missing"} with data.ergo_document as {"m": {}}
	not ergo._keyed_root_fault({}, p) with data.ergo_document as {"m": {"a": {}}}
}
