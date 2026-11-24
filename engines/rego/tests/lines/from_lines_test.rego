package ergo_test

import data.ergo
import rego.v1

test_a_check_on_an_item_that_isnt_an_object_keeps_its_words_when_the_requirement_names_no_subject if {
	ergo._named_check({"op": "exists"}, {}, 3) == {"op": "exists"}
	ergo._named_check({"op": "exists"}, {"subject": "t"}, 3) == {"op": "exists", "label": "t"}
}

test_a_requirement_that_reads_parts_only_by_name_runs_without_a_scope_because_a_scope_makes_opa_work_out_every_row_again if {
	parts := {"parts": {"s": {"cov": {}}}}
	not ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, false), "b", "x"]}}}) with data.ergo_subject_sentences as parts
	ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, true), "b", "x"]}}}) with data.ergo_subject_sentences as parts
}

test_a_check_with_a_for_key_and_no_op_is_a_for_check if {
	ergo._for_check({"for": "every xs as m", "assert": "m.v is 1"})
	ergo._for_check({"op": "for"})
	not ergo._for_check({"op": "all_of"})
}

test_a_from_line_note_about_mixed_types_says_one_clause_per_item_so_each_item_entry_gets_its_own if {
	req := {"subject": "s", "from": ["things"]}
	mixed := {"types": [["text", ["things", 0], "a"], ["a number", ["things", 1], 1]], "plain": true}
	ergo._fl_note_clauses(req, mixed) == ["item 1 of things is text", "item 2 of things is a number"]
	beside := {"list": {"c": ["things", 0, "xs"]}, "other": {"c": ["things", 1, "xs"], "v": 3}}
	ergo._fl_note_clauses(req, beside) == ["item 1 of things: xs is a list", "item 2 of things: xs is a number"]
}

test_a_failing_row_over_an_empty_list_is_read_again_with_a_list_after_is_in_ignoring_case_that_walks_a_subject_or_input_that_is_a_list if {
	field := {"op": "compare", "cmp": "in", "left": ["x"], "right": [`${"alias":"thing","n":0,"of":null,"old":true}`, "states"], "ignoring": "case"}
	every_field := {"op": "every", "path": [`${"alias":"thing","n":0,"of":null,"old":false}`, "xs", "v"], "check": field, "whose": [], "if_any": false, "label": "thing"}
	raw := {"passed": false, "inputs": [{"value": []}]}
	subj := [{"xs": [], "states": ["A"]}, {"xs": [], "states": ["b", 3]}]
	ergo._walk_read_again(raw, every_field) with input as {"ergo/names": {"ergo/subject": subj}}
	not ergo._walk_read_again(raw, object.union(object.remove(every_field, ["check"]), {"check": object.remove(field, ["ignoring"])})) with input as {"ergo/names": {"ergo/subject": subj}}
	not ergo._walk_read_again(object.union(raw, {"inputs": [{"value": [1]}]}), every_field) with input as {"ergo/names": {"ergo/subject": subj}}
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$input[]", "ok"]}, "ignoring": "case"}
	every_ref := {"op": "every", "path": ["xs", "v"], "check": ref, "whose": [], "if_any": false}
	ergo._walk_read_again(raw, every_ref) with input as {"ergo/names": {"ergo/subject": subj[1]}} with data.ergo_document as [{"ok": ["b", 3]}]
	not ergo._walk_read_again(raw, every_ref) with input as {"ergo/names": {"ergo/subject": subj[1]}} with data.ergo_document as {"ok": ["b", 3]}
}

test_a_failing_row_whose_check_compares_ignoring_case_with_a_walked_list_is_read_again_with_its_walked_roots if {
	part := [`${"alias":"pl","n":1,"of":null,"old":true}`, "p", "name"]
	whose := {"op": "every", "path": ["xs"], "check": {"op": "present", "path": ["x"]}, "whose": [{"op": "compare", "cmp": "in", "left": ["v"], "right": part, "ignoring": "case"}], "if_any": false}
	subj := {"xs": [], "p": [{"name": 3}]}
	ergo._text_walk_rooted(whose) with input as {"ergo/names": {"ergo/subject": subj}}
	not ergo._text_walk_rooted(object.union(whose, {"whose": [object.remove(whose.whose[0], ["ignoring"])]})) with input as {"ergo/names": {"ergo/subject": subj}}
	ref := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._text_walk_rooted(object.union(whose, {"whose": [ref]})) with input as {"ergo/names": {"ergo/subject": {"xs": []}}} with data.ergo_document as {"cs": [{"name": 3}]}
	params := {"op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	not ergo._text_walk_rooted(object.union(whose, {"whose": [params]})) with input as {"ergo/names": {"ergo/subject": {"xs": []}}} with data.ergo_params as {"l": [3]}
}

test_a_failing_for_row_over_an_empty_list_is_read_again_with_a_part_after_is_in_ignoring_case_that_walks_a_list if {
	right := [`${"alias":"pl","n":2,"of":null,"old":false}`, "items", "allowed"]
	assertion := {"cmp": "in", "ignoring": "case", "left": ["$e", "v"], "op": "compare", "right": right}
	for_c := {"op": "for", "checks": [assertion], "items": [{"as": "e", "if_any": false, "path": ["xs"], "q": "every", "whose": []}]}
	raw := {"passed": false, "inputs": [{"value": []}]}
	subj := {"xs": [], "items": [{"allowed": ["a"]}, {"allowed": ["b", 3]}]}
	ergo._walk_read_again(raw, for_c) with input as {"ergo/names": {"ergo/subject": subj}}
	not ergo._walk_read_again(raw, object.union(object.remove(for_c, ["checks"]), {"checks": [object.remove(assertion, ["ignoring"])]})) with input as {"ergo/names": {"ergo/subject": subj}}
}

test_a_failing_for_row_is_read_again_only_when_one_of_its_own_assertions_has_the_words_to_keep_the_wasm_memory_of_for_rows_near_main if {
	right := [`${"alias":"pl","n":2,"of":null,"old":false}`, "items", "allowed"]
	assertion := {"cmp": "in", "ignoring": "case", "left": ["$e", "v"], "op": "compare", "right": right}
	for_c := {"op": "for", "checks": [assertion], "items": [{"as": "e", "if_any": false, "path": ["xs"], "q": "every", "whose": []}]}
	subj := {"xs": [{"v": "a"}], "items": [{"allowed": ["a"]}, {"allowed": ["b", 3]}]}
	ergo._walk_read_again({"passed": false, "inputs": [{"value": [{"v": "a"}]}]}, for_c) with input as {"ergo/names": {"ergo/subject": subj}}
	nested := {"op": "compare", "cmp": "eq", "left": {"count_of": ["$e", "ys"], "whose": [object.union(assertion, {"left": ["v"]})]}, "right": {"literal": 1}}
	if_any := {"op": "for", "checks": [nested], "items": [{"as": "e", "if_any": true, "path": ["xs"], "q": "every", "whose": []}]}
	not ergo._walk_read_again({"passed": false, "inputs": []}, if_any) with input as {"ergo/names": {"ergo/subject": subj}}
}
