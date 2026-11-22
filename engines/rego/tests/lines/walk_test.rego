package ergo_test

import data.ergo
import rego.v1

test_a_walk_that_starts_at_a_name_with_no_location_still_walks_its_items if {
	start := ergo._walk_start({"path": ["$x", "a"]}, {}) with input as {"ergo/names": {"x": {"a": [1]}}}
	start.v == {"a": [1]}
	start.a == ""
}

_member_walk(subj, path, if_any) := ergo._walk(ergo._walk_start({"path": path}, subj), ergo._walk_keys({"path": path, "member": true}, subj), if_any)

test_a_walk_that_ends_with_member_of_reads_each_member_of_the_object_in_key_order if {
	w := _member_walk({"statuses": {"sign-off": "FAILED", "build": "DONE"}}, ["statuses"], false)
	[e.c | some e in w.items] == [["statuses", {"member": "build"}], ["statuses", {"member": "sign-off"}]]
	[e.i | some e in w.items] == [["statuses", {"member": "build"}], ["statuses", {"member": "sign-off"}]]
	[e.v | some e in w.items] == ["DONE", "FAILED"]
	[e.iv | some e in w.items] == ["DONE", "FAILED"]
	w.fails == []
	ergo._walk_stop(w) == []
	ergo._walk_name(["statuses"], w.walked) == "statuses"
	ergo._walk_locations(w) == ["~~/statuses/build", "~~/statuses/sign-off"]
	[ergo._item_at(w, e) | some e in w.items] == ["~~/statuses/build", "~~/statuses/sign-off"]
}

test_a_walk_with_member_of_walks_the_lists_along_its_path_and_marks_only_them if {
	w := _member_walk({"rs": [{"statuses": {"b": 1, "a": "DONE"}}]}, ["rs", "statuses"], false)
	[e.c | some e in w.items] == [["rs", 0, "statuses", {"member": "a"}], ["rs", 0, "statuses", {"member": "b"}]]
	ergo._walk_name(["rs", "statuses"], w.walked) == "rs[].statuses"
	ergo._walk_locations(w) == ["~~/rs/0/statuses/a", "~~/rs/0/statuses/b"]
}

test_a_member_walk_fails_each_end_that_is_not_an_object_or_has_no_members if {
	w := _member_walk({"rs": [{"statuses": ["x"]}, {"statuses": {}}, {}, {"statuses": null}]}, ["rs", "statuses"], false)
	w.items == []
	[[f.path, f.cause, f.value, f.msg] | some f in w.fails] == [
		[["rs", 0, "statuses"], "unusable", ["x"], "an object"],
		[["rs", 1, "statuses"], "value", {}, ""],
		[["rs", 2, "statuses"], "absent", null, "an object"],
		[["rs", 3, "statuses"], "null", null, "an object"],
	]
	_member_walk({"rs": [{"statuses": {}}]}, ["rs", "statuses"], true).fails == []
}

test_a_member_walk_with_no_list_on_its_path_stops_where_the_object_should_be if {
	w := _member_walk({"statuses": ["DONE"]}, ["statuses"], false)
	w.walked == set()
	w.fails == []
	[[f.cause, f.msg] | some f in ergo._walk_stop(w)] == [["unusable", "an object"]]
	[[f.cause, f.msg] | some f in ergo._walk_stop(_member_walk({}, ["statuses"], false))] == [["absent", "an object"]]
	[[f.cause, f.msg] | some f in ergo._walk_stop(_member_walk({"a": 5}, ["a", "statuses"], false))] == [["unusable", "a list or an object"]]
	w2 := _member_walk({"statuses": {}}, ["statuses"], false)
	[[f.path, f.cause, f.value] | some f in w2.fails] == [[["statuses"], "value", {}]]
}

test_a_walk_reads_member_of_only_when_the_check_says_member if {
	ergo._walk_keys({"path": ["a", "b"]}, {}) == ["a", "b"]
	ergo._walk_keys({"path": ["a", "b"], "member": false}, {}) == ["a", "b"]
	ergo._walk_keys({"path": ["a", "b"], "member": true}, {}) == ["a", "b", ergo._fm_mark]
}

test_a_tally_of_member_of_walks_each_member_of_the_object_as_an_item if {
	side := {"sum_of": ["costs"], "whose": [], "text": "sum of member of costs", "member": true}
	w := ergo._tally_walk({"costs": {"b": 5, "a": 1}}, side)
	[e.v | some e in w.items] == [1, 5]
	[e.i | some e in w.items] == [["costs", {"member": "a"}], ["costs", {"member": "b"}]]
}

_min_said(sentence, subj) := {"cause": r.cause, "message": ergo._m_walk_outcome(check, subj, r).message} if {
	check := ergo._s_written_check(sentence)
	r := ergo._walk_row(check, subj)
}

test_a_root_after_the_phrase_is_said_first_beside_items_that_fail_on_their_own_and_the_row_takes_the_worst_cause if {
	five := {"xs": [{}, {}, {}, {}, {}]}
	_min_said("every xs.v is at least $params.min", five) == {"cause": "unusable", "message": "$params.min is \"s\", which isn't a number; item 1 of xs: v is missing; item 2 of xs: v is missing; item 3 of xs: v is missing; and 2 more"} with input as {"ergo/names": {"ergo/subject": five}} with data.ergo_params as {"min": "s"}
	two := {"xs": [{}, {}]}
	_min_said("some xs.v is at least $params.min", two) == {"cause": "unusable", "message": "$params.min is \"s\", which isn't a number; item 1 of xs: v is missing; item 2 of xs: v is missing"} with input as {"ergo/names": {"ergo/subject": two}} with data.ergo_params as {"min": "s"}
	mixed := {"xs": [{"v": null}, {"v": 1}]}
	_min_said("every xs.v is at least $params.min", mixed) == {"cause": "unusable", "message": "$params.min is \"s\", which isn't a number; item 1 of xs: v is null"} with input as {"ergo/names": {"ergo/subject": mixed}} with data.ergo_params as {"min": "s"}
}

test_a_named_by_key_after_the_phrase_that_cant_be_read_leaves_the_items_to_say_their_own_problems_as_path_ref_step_says if {
	check := ergo._s_written_check("every rs.zz is m named by $input.k")
	rs := {"m": {"a": "a"}, "rs": [{"v": 1}, {"v": 2}]}
	r := ergo._walk_row(check, rs) with input as {"ergo/names": {"ergo/subject": rs}} with data.ergo_document as {"k": null}
	ergo._leaf_root_flaw(check, rs) != "" with input as {"ergo/names": {"ergo/subject": rs}} with data.ergo_document as {"k": null}
	r.cause == "absent"
	not "root_msgs" in object.keys(r)
}

test_a_walk_through_a_for_alias_leaves_a_root_after_the_phrase_to_the_for_line_so_each_item_keeps_its_own_cause_as_for_roots_says if {
	check := ergo._s_written_check({"for": "every ws as w", "assert": "every w.xs.v is at least $params.min"}).checks[0]
	w := {"xs": [{}, {}]}
	subj := {"ws": [w]}
	names := {"ergo/subject": subj, "w": w, "$at": {"names": {"w": "/ws/0"}}}
	ergo._leaf_root_flaw(check, subj) == "unusable" with input as {"ergo/names": names} with data.ergo_params as {"min": "s"}
	r := ergo._walk_row(check, subj) with input as {"ergo/names": names} with data.ergo_params as {"min": "s"}
	r.cause == "absent"
	not "root_msgs" in object.keys(r)
}
