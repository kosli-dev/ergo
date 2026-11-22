package ergo_test

import data.ergo
import rego.v1

test_keyed_side_checks_a_path_side_is_an_object_before_reading_its_whose if {
	not ergo._keyed_side(["approvals"], {"literal": 1})
	not ergo._keyed_list({"op": "compare", "cmp": "gte", "left": ["approvals"], "right": {"literal": 1}})
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
