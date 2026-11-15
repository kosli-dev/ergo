package ergo_test

import data.ergo
import rego.v1

test_keyed_side_checks_a_path_side_is_an_object_before_reading_its_whose if {
	not ergo._keyed_side(["approvals"], {"literal": 1})
	not ergo._keyed_list({"op": "compare", "cmp": "gte", "left": ["approvals"], "right": {"literal": 1}})
}

test_keyed_list_takes_only_a_one_step_list if {
	whose := [{"op": "compare", "cmp": "includes", "left": ["tags"], "right": ["$$input", "m", {"named_by_field": "key"}]}]
	ergo._keyed_clause(["xs"], whose) == whose[0]
	not ergo._keyed_clause(["xs", "v"], whose)
}
