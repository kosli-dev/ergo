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

test_a_count_takes_the_cause_of_what_each_item_cant_read_on_its_own_beside_the_root_a_key_from_it_is_read_in if {
	side := ergo._m_tally_parts(ergo._s_written_check("count of xs whose v is not $input.d.m named by key is 0"))[0]
	ergo._tally({"xs": [{"v": 1}]}, side).states == {"null", "absent"} with data.ergo_document as {"d": null}
	ergo._tally({"xs": [{"key": "a", "v": null}]}, side).states == {"absent", "null"} with data.ergo_document as {}
	ergo._tally({"xs": [{"key": "a", "v": 1}]}, side).states == {"unusable"} with data.ergo_document as {"d": 3}
	ergo._tally({"xs": [{"key": "a"}]}, side).states == {"unusable", "absent"} with data.ergo_document as {"d": 3}
}

test_a_count_fails_on_the_root_a_key_from_the_item_is_read_in_even_when_the_list_is_empty if {
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"absent"} with data.ergo_params as {}
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"null"} with data.ergo_params as {"m": null}
	ergo._tally({"xs": []}, _count_keyed_by_item("$params.m")).states == {"unusable"} with data.ergo_params as {"m": 3}
	ergo._tally({"xs": []}, _count_keyed_by_item("$input.m")).states == {"absent"} with data.ergo_document as {}
}

test_a_count_fails_as_value_on_an_empty_list_on_the_right_of_its_whose_whatever_the_items if {
	every sentence in [
		"count of xs whose v is in $params.cs.name is 0",
		"count of xs whose v is not one of $params.cs.name is 0",
		"count of xs.v that is in $params.cs.name is 0",
	] {
		every xs in [[], [{"v": "a"}]] {
			[row[1] | some row in _tally_rows(sentence, [{"id": 1, "xs": xs}], {"cs": []})] == ["value"]
		}
		[row[1] | some row in _tally_rows(sentence, [{"id": 1, "xs": [{}]}], {"cs": []})] == ["absent"]
	}
}

_count_messages(sentence, xs) := [r.message | some r in ergo.report({"things": [{"id": 1, "xs": xs}]}, _sentence_policy({"c": sentence}), {"cs": []}).results; r.check == "c"]

test_a_count_says_an_empty_list_on_the_right_once_and_then_each_items_own_problem if {
	every sentence in [
		"count of xs whose v is in $params.cs.name is 0",
		"count of xs.v that is in $params.cs.name is 0",
	] {
		_count_messages(sentence, []) == ["$params.cs is []"]
		_count_messages(sentence, [{"v": "a"}, {"v": "b"}]) == ["$params.cs is []"]
		_count_messages(sentence, [{}]) == ["$params.cs is []; item 1 of xs: v is missing"]
	}
}

_rows_said(sentence, xs) := [[r.cause, r.message] | some r in ergo.report({"things": [{"id": 1, "xs": xs}]}, _sentence_policy({"c": sentence}), {"cs": []}).results; r.check == "c"]

test_an_every_or_a_some_says_an_empty_list_on_the_right_of_its_whose_once_and_fails if {
	every sentence in [
		"every xs whose v is in $params.cs.name exists",
		"every xs whose v is in $params.cs.name, if any, exists",
		"some xs whose v is in $params.cs.name exists",
	] {
		_rows_said(sentence, [{"v": "a"}]) == [["value", "$params.cs is []"]]
		_rows_said(sentence, [{}]) == [["absent", "$params.cs is []; item 1 of xs: v is missing"]]
	}
}

test_an_empty_list_after_contains_all_of_or_none_of_is_said_once_and_fails_the_row if {
	every sentence in [
		"count of xs whose tags contains all of $params.cs.name is 0",
		"count of xs whose tags contains none of $params.cs.name is 0",
		"every xs whose tags contains all of $params.cs.name exists",
		"every xs whose tags contains all of $params.cs.name, if any, exists",
		"some xs whose tags contains none of $params.cs.name exists",
	] {
		_rows_said(sentence, [{"tags": ["a"]}]) == [["value", "$params.cs is []"]]
		_rows_said(sentence, [{}]) == [["absent", "$params.cs is []; item 1 of xs: tags is missing"]]
	}
}

_said_beside_list(sentence, thing) := [[r.cause, r.message] | some r in ergo.report({"things": [object.union({"id": 1, "k": 0}, thing)]}, _sentence_policy({"c": sentence}), {"cs": []}).results; r.check == "c"]

test_a_count_or_a_sum_says_an_empty_list_on_the_right_before_its_own_list_that_cant_be_read if {
	every sentence in [
		"count of xs whose v is in $params.cs.name is 0",
		"count of xs whose v is not one of $params.cs.name is 0",
		"count of xs whose v matches $params.cs.name is 0",
		"count of xs.v that is in $params.cs.name is 0",
		"sum of xs.n that is in $params.cs.name is 0",
		"k plus count of xs whose v is in $params.cs.name is 0",
	] {
		_said_beside_list(sentence, {}) == [["absent", "$params.cs is []; xs is missing"]]
		_said_beside_list(sentence, {"xs": null}) == [["null", "$params.cs is []; xs is null"]]
	}
}

_count_keyed(sentence) := ergo._m_tally_parts(ergo._s_written_check(sentence))[0]

_phrases_keyed_by_item := [
	"count of xs whose v is not $input.m named by key is 0",
	"count of xs that is $input.m named by key is 0",
	"count of xs whose v is $input.m named by key and whose w equals 1 is 0",
	"count of xs whose tags contains $input.m named by key is 0",
	"count of xs whose v matches $input.m named by key is 0",
	"count of xs whose $input.m named by key is v is 0",
]

test_a_count_on_an_empty_list_fails_on_the_root_a_key_from_the_item_is_read_in_whatever_the_phrase if {
	every s in _phrases_keyed_by_item {
		side := _count_keyed(s)
		every pair in [[{}, "absent"], [{"m": null}, "null"], [{"m": 3}, "unusable"]] {
			t := ergo._tally({"xs": []}, side) with data.ergo_document as pair[0]
			t.states == {pair[1]}
			not "value" in object.keys(t)
		}
	}
}

test_a_count_on_an_empty_list_fails_on_a_root_further_back_than_the_key_that_isnt_an_object if {
	t := ergo._tally({"xs": []}, _count_keyed("count of xs whose v is $input.m.a named by key is 0")) with data.ergo_document as {"m": 3}
	t.states == {"unusable"}
	not "value" in object.keys(t)
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

_list_outcome(subj, sentence) := object.get(ergo._tally(subj, ergo._m_tally_parts(ergo._s_written_check(sentence))[0]), "ergo/outcome", "usable")

test_a_count_of_a_value_it_cannot_walk_is_unusable_but_one_that_stops_before_the_end_is_not if {
	_list_outcome({"y": [{"v": 1}]}, "count of y[0].v is 1") == "unusable"
	_list_outcome({"x": {"k": 5}, "zz": "k"}, "count of x named by zz is 1") == "unusable"
	_list_outcome({"ms": 3}, "count of ms is 1") == "unusable"
	_list_outcome({"costs": [1]}, "sum of member of costs is at most 3") == "unusable"
	_list_outcome({"p": 3}, "count of p.b is 1") == "usable"
	_list_outcome({"items": "x"}, "sum of items.usd is 30") == "usable"
}
