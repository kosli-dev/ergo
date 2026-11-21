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

test_a_count_or_sum_of_member_of_walks_each_member_of_the_object_as_an_item if {
	side := {"sum_of": ["costs"], "whose": [], "text": "sum of member of costs", "member": true}
	w := ergo._tally_walk({"costs": {"b": 5, "a": 1}}, side)
	[e.v | some e in w.items] == [1, 5]
	[e.i | some e in w.items] == [["costs", {"member": "a"}], ["costs", {"member": "b"}]]
	t := ergo._tally({"costs": {"b": 5, "a": 1, "c": "x"}}, side)
	t.values == [1, 5, "x"]
	t.list == "costs"
	t.states == {"unusable"}
	count := {"count_of": ["evidence"], "whose": [{"op": "equals", "path": ["kind"], "value": "approval"}], "text": "count of member of evidence", "member": true}
	ergo._tally({"evidence": {"x": {"kind": "scan"}, "y": {"kind": "approval"}}}, count).value == 1
}
