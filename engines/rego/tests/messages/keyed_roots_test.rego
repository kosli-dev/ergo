package ergo_test

import data.ergo
import rego.v1

test_keyed_list_leaves_a_count_to_say_its_own_root if {
	not ergo._keyed_list({"op": "compare", "cmp": "gte", "left": ["approvals"], "right": {"literal": 1}})
	not ergo._keyed_list(ergo._s_written_check("count of xs whose tags contains $input.m named by key is 1"))
}

test_an_item_under_a_root_said_once_takes_the_cause_of_its_own_missing_key_not_the_roots_null if {
	check := ergo._s_written_check({"assert": "every xs whose tags contains $input.m named by key exists"})
	subj := {"xs": [null, {"key": "a", "tags": ["x"]}, {"tags": ["x"]}]}
	o := {"passed": false, "cause": "not_an_object", "message": "", "failed_items": [{"item": "item 1 of xs", "cause": "not_an_object"}, {"item": "item 3 of xs", "cause": "null"}]}
	r := ergo._keyed_said(o, ergo._keyed_list(check), {"cause": "null", "text": "$input.m is null"}, subj)
	[[f.item, f.cause] | some f in r.failed_items] == [["item 1 of xs", "not_an_object"], ["item 3 of xs", "absent"]]
}

test_an_item_the_keyed_root_finds_nothing_wrong_with_keeps_the_cause_the_walk_gave_it_so_it_still_fails if {
	ergo._keyed_failed({"item": "item 2 of xs", "cause": "value"}, [{"text": "", "causes": set()}, {"text": "item 3 of xs: key is missing", "causes": {"absent"}}]) == {"item": "item 2 of xs", "cause": "value"}
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
