package ergo_test

import data.ergo
import rego.v1

test_a_row_whose_list_after_the_words_holds_text_and_a_number_says_the_list_and_the_root_and_not_that_the_sentence_is_false if {
	c := {"ignoring": "case", "op": "in", "path": ["$$params", "k"], "values": {"ref": ["$$input[]", "cs", "name"]}}
	check := {"check": {"op": "present", "path": ["x"]}, "expression": "every xs whose $params.k is in $input.cs.name ignoring case, if any, exists", "if_any": true, "op": "every", "path": ["xs"], "whose": [c]}
	r := ergo._walk_row(check, {"xs": [{}]}) with data.ergo_document as {"cs": [{"name": "a"}, {"name": 3}]} with data.ergo_params as {} with input as {"ergo/names": {}}
	[m.text | some m in r.other_roots] == ["item 2 of $input.cs: name is 3, which isn't text", "$params.k is missing"]
	not "root_msgs" in object.keys(r)
	[f.item | some f in r.failed] == ["item 1 of xs"]
}

test_a_walk_that_starts_at_a_name_with_no_location_still_walks_its_items if {
	start := ergo._walk_start({"path": ["$x", "a"]}, {}) with input as {"ergo/names": {"x": {"a": [1]}}}
	start.v == {"a": [1]}
	start.a == ""
}

_member_walk(subj, path, if_any) := ergo._walk(ergo._walk_start({"path": path}, subj), ergo._walk_keys({"path": path, "member": true}, subj), if_any)

_member_list_outcome(subj) := object.get(ergo._walk_inputs({"path": ["xs", "ys"], "member": true}, _member_walk(subj, ["xs", "ys"], false))[0], "ergo/outcome", "usable")

test_a_member_walk_whose_every_end_stops_reads_the_list_as_its_worst_stop_in_any_order if {
	_member_list_outcome({"xs": [{"ys": 3}]}) == "unusable"
	_member_list_outcome({"xs": [{"ys": null}, {"ys": 3}]}) == "unusable"
	_member_list_outcome({"xs": [{"ys": 3}, {"ys": null}]}) == "unusable"
	_member_list_outcome({"xs": [{"ys": null}, {}]}) == "absent"
	_member_list_outcome({"xs": [{}, {"ys": null}]}) == "absent"
	_member_list_outcome({"xs": [{"ys": {"a": 1}}, {"ys": 3}]}) == "usable"
	_member_list_outcome({"xs": [{"ys": {}}, {"ys": null}]}) == "usable"
}

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

test_a_broken_text_list_after_is_in_ignoring_case_hides_an_empty_list_as_any_root_after_every_does if {
	field := {"op": "compare", "cmp": "in", "left": ["x"], "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	every_field := {"op": "every", "path": ["xs", "x"], "check": field, "whose": [], "if_any": false}
	row := ergo._walk_row(every_field, {"xs": [], "ys": [3]})
	row.cause == "unusable"
	row.failed == []
	[m.text | some m in row.root_msgs] == ["item 1 of ys is 3, which isn't text"]
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	mixed := ergo._walk_row({"op": "every", "path": ["xs", "x"], "check": ref, "whose": [], "if_any": false}, {"xs": []}) with data.ergo_params as {"l": ["A", 3]}
	mixed.cause == "unusable"
	[m.text | some m in mixed.root_msgs] == ["item 2 of $params.l is 3, which isn't text"]
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

test_a_walk_lists_its_failed_items_in_list_order_even_when_a_later_item_failed_on_a_read_outside_it if {
	fails := [
		{"path": ["$$input", "m"], "item": ["xs", 2], "cause": "absent", "value": null, "at": "~~/m"},
		{"path": ["xs", 0, "tags"], "item": ["xs", 0], "cause": "not_an_object", "value": null, "at": "~~/xs/0"},
	]
	[f.item | some f in ergo._walk_failed("not_an_object", fails, ["xs"])] == ["item 1 of xs", "item 3 of xs"]
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

test_an_item_whose_walked_field_is_missing_reads_as_absent_even_when_the_check_fails_it_with_value if {
	r := ergo._walk_row(ergo._s_written_check("every xs.v exists"), {"xs": [{"v": 1}, {}, {"v": null}]})
	[[f.cause, object.get(f, "read_outcome", "")] | some f in r.fails] == [["value", "absent"], ["value", ""]]
}
