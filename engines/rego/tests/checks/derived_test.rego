package ergo_test

import data.ergo
import rego.v1

test_sum_of_and_plus_add_numbers_as_decimals if {
	_tally_rows("sum of xs.n is 1.6", [{"id": 1, "xs": [{"n": 0.7}, {"n": 0.9}]}], {})[0][2][0] == {"name": "sum of xs.n", "value": 1.6, "locations": ["/things/0/xs/0/n", "/things/0/xs/1/n"]}
	[row[1] | some row in _tally_rows("x is p plus q plus 0.1", [{"id": 1, "p": 0.7, "q": 0.9, "x": 1.7}], {})] == ["satisfied"]
	ergo._decimal_sum([1e-7, 2e-7]) == 3e-7
	ergo._decimal_sum([1.5e3, 0.25]) == 1500.25
	ergo._decimal_sum([-0.7, 0.9]) == 0.2
	ergo._decimal_sum([]) == 0
	not ergo._decimal_sum([1e-20, 1])
	not ergo._decimal_sum([1e15])
	ergo._decimal_sum([0.123456789012345]) == 0.123456789012345
	ergo._decimal_sum([0.1, 0.2, 100]) == 100.3
}

_count_of_ms(cmp) := {"count_of": ["ms"], "text": "count of ms", "whose": [{"op": "compare", "cmp": cmp, "left": ["v"], "right": ["$$params", "r"]}]}

test_a_count_takes_the_worst_cause_of_a_root_it_cant_read_and_of_its_items if {
	ergo._tally({"ms": [{"v": "s"}, {}]}, _count_of_ms("gte")).states == {"absent", "unusable"} with data.ergo_params as {}
	ergo._tally({"ms": [{"v": "s"}, {}]}, _count_of_ms("gte")).states == {"null", "absent", "unusable"} with data.ergo_params as {"r": null}
	ergo._tally({"ms": [{"v": 1}]}, _count_of_ms("gte")).states == {"absent"} with data.ergo_params as {}
	ergo._tally({"ms": [{}, {"v": 1}]}, _count_of_ms("in")).states == {"null", "absent"} with data.ergo_params as {"r": null}
}

_count_keyed_by_item(root) := ergo._m_tally_parts(ergo._s_written_check(concat("", ["count of xs whose v is ", root, " named by key is 1"])))[0]

test_a_count_takes_the_cause_of_the_root_a_key_from_the_item_is_read_in if {
	ergo._tally({"xs": [{}]}, _count_keyed_by_item("$params.m")).states == {"absent", "unusable"} with data.ergo_params as {"m": 3}
	ergo._tally({"xs": [{"v": 1}]}, _count_keyed_by_item("$params.m")).states == {"absent", "unusable"} with data.ergo_params as {"m": "s"}
	ergo._tally({"xs": [{}]}, _count_keyed_by_item("$input.m")).states == {"absent", "unusable"} with data.ergo_document as {"m": true}
}

test_a_count_fails_on_the_root_a_key_from_the_item_is_read_in_even_when_the_list_is_empty if {
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"absent"} with data.ergo_params as {}
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"null"} with data.ergo_params as {"m": null}
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"unusable"} with data.ergo_params as {"m": 3}
	ergo._tally({"xs": []}, _count_keyed_by_item("$input.m")).states == {"absent"} with data.ergo_document as {}
}

test_a_count_or_sum_of_member_of_walks_each_member_of_the_object_as_an_item if {
	side := {"sum_of": ["costs"], "whose": [], "text": "sum of member of costs", "member": true}
	t := ergo._tally({"costs": {"b": 5, "a": 1, "c": "x"}}, side)
	t.values == [1, 5, "x"]
	t.list == "costs"
	t.states == {"unusable"}
	approvals := {"count_of": ["evidence"], "whose": [{"op": "equals", "path": ["kind"], "value": "approval"}], "text": "count of member of evidence", "member": true}
	ergo._tally({"evidence": {"x": {"kind": "scan"}, "y": {"kind": "approval"}}}, approvals).value == 1
}
