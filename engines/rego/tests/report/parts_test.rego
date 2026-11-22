package ergo_test

import data.ergo
import rego.v1

test_an_input_outcome_of_missing_is_the_cause_absent if {
	ergo._cause_of_outcome("missing") == "absent"
	ergo._cause_of_outcome("null") == "null"
}

test_a_tally_word_that_is_neither_missing_nor_null_turns_absent_and_null_into_unusable if {
	ergo._tally_word_cause("xs is text", "absent") == "unusable"
	ergo._tally_word_cause("xs is text", "null") == "unusable"
	ergo._tally_word_cause("xs is text", "not_an_object") == "not_an_object"
	ergo._tally_word_cause("xs is missing", "absent") == "absent"
}

test_a_clause_kept_from_a_record_takes_its_cause_from_the_record_state_without_its_focus_or_root_mark if {
	ergo._tally_clause_cause("v is missing", "focus unusable") == "absent"
	ergo._tally_clause_cause(`v is "a", which isn't text`, "focus absent") == "unusable"
	ergo._tally_clause_cause(`v is "a", which isn't text`, "focus not_an_object") == "not_an_object"
	ergo._tally_clause_cause(`v is "a", which isn't text`, "root absent") == "unusable"
	ergo._tally_clause_cause(`v is "a", which isn't text`, "root not_an_object") == "not_an_object"
	ergo._tally_clause_cause(`v is "a", which isn't text`, "not_an_object") == "not_an_object"
}

test_a_check_without_a_checks_list_in_its_where_is_its_own_text if {
	ergo._sub_mcheck({"check": {"checks": []}}, "c", {}) == "c"
}

test_a_walked_name_that_is_not_a_path_is_empty if {
	ergo._walked_name("xs") == ""
	ergo._walked_name(["xs"]) != ""
}

test_a_tally_with_no_lists_has_no_list_entries if {
	ergo._tally_list_entries({}, [], set(), []) == []
}

test_an_intermediate_join_with_no_own_entries_takes_the_name_and_value_of_the_item if {
	ergo._ms_join2([], [{"name": "xs", "value": 1, "locations": ["/xs"]}], []).name == "xs"
}

test_an_item_input_named_like_a_parent_keeps_its_dot_and_any_other_name_stays_plain if {
	ergo._item_input_name(["cov", 0]) == ".cov[0]" with data.ergo_parent as {"cov": {"from": "covs"}}
	ergo._item_input_name(["xs", 0]) == "xs[0]" with data.ergo_parent as {"cov": {"from": "covs"}}
}

test_a_counted_field_named_by_a_key_the_subject_lacks_is_found_by_the_whole_path_rule_first if {
	c := ergo._s_written_check("count of xs named by k is 1")
	ergo._tally_unkeyed_list_names(c, {}) == {"xs named by k"}
	ergo._tally_list_paths(c, "xs named by k") == [["xs", {"named_by_field": "k"}]]
}

test_a_from_without_a_path_gives_no_key_reads if {
	ergo._ms_key_reads({}) == []
}

test_a_list_named_in_a_message_but_found_in_no_path_keeps_the_input_it_was_read_from if {
	ergo._tally_list_read("xs", "absent", {}, [{"name": "xs", "value": 1}, {"name": "ys", "value": 2}], []) == [{"name": "xs", "value": 1, "outcome": "absent"}]
}

test_an_item_two_conditions_of_a_count_cant_decide_is_one_entry_that_says_both if {
	check := {
		"op": "compare", "cmp": "eq", "expression": "count of es whose v is 1 and whose w is 1 is 0",
		"left": {"count_of": ["es"], "text": "count of es whose v is 1 and whose w is 1", "whose": [
			{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
			{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
		]},
		"right": {"literal": 0},
	}
	parts := ergo._tally_item_parts(check, {"es": [{}]}, "absent", "/things/0", "item 1 of es: v is missing; item 1 of es: w is missing")
	[[p.name, p.cause, p.message] | some p in parts] == [["item 1 of es", "absent", "v is missing; w is missing"]]
}

test_a_counted_list_named_by_a_key_is_never_an_input_of_the_assertion_even_with_no_failed_items if {
	field := ergo._s_written_check("count of m named by p is at least 3")
	ergo._tally_own_read({"name": "m named by p[]", "value": [1, 2]}, field, set(), [])
	param := ergo._s_written_check("q is sum of m named by $params.k")
	ergo._tally_own_read({"name": "m named by $params.k[]", "value": [1, 2]}, param, set(), [])
}

test_a_summed_field_of_each_item_is_never_an_input_of_the_assertion if {
	c := ergo._s_written_check("sum of xs.n is 1")
	ergo._tally_own_read({"name": "xs[].n", "value": [1, 2]}, c, set(), [])
}

test_a_counted_list_that_failed_under_an_item_is_never_an_input_of_the_assertion if {
	c := ergo._s_written_check("count of y[0].v is 1")
	ergo._tally_own_read({"name": "y[0].v", "value": 1}, c, set(), [{"kind": "item", "name": "item 1 of y"}])
}

test_a_counted_list_that_failed_with_no_entry_of_its_own_stays_on_the_assertion if {
	c := ergo._s_written_check("count of xs.n is 1")
	not ergo._tally_own_read({"name": "xs.n", "value": null}, c, set(), [])
}

test_a_root_an_option_cant_use_is_unusable_on_the_row_as_on_the_assertion if {
	z := {"name": "art.cov.z", "value": "s", "locations": ["/arts/0/c/z"]}
	x := {"name": "x", "value": null, "locations": ["/arts/0/xs/0"], "outcome": "absent"}
	assertion := {"kind": "assertion", "name": "every ys whose n is at least art.cov.z, if any, exists", "cause": "unusable", "inputs": [object.union(z, {"outcome": "unusable"})], "failures": [], "message": "art.cov.z is \"s\", which isn't a number"}
	option := {"kind": "option", "name": "a", "cause": "unusable", "inputs": [], "failures": [assertion], "message": ""}
	row := {"passed": false, "cause": "unusable", "message": "a: art.cov.z is \"s\", which isn't a number; b: x is missing", "inputs": [object.union(z, {"outcome": "usable"}), x], "failures": [option]}
	[[i.name, i.outcome] | some i in ergo._said_outcomes(row).inputs] == [["art.cov.z", "unusable"], ["x", "absent"]]
}

test_a_root_read_fine_by_every_assertion_stays_usable_on_the_row if {
	z := {"name": "z", "value": 1, "locations": ["/z"], "outcome": "usable"}
	assertion := {"kind": "assertion", "name": "z is 2", "cause": "value", "inputs": [z], "failures": [], "message": "z is 1"}
	other := {"kind": "assertion", "name": "y is at least 1", "cause": "unusable", "inputs": [{"name": "y", "value": "s", "locations": ["/y"], "outcome": "unusable"}], "failures": [], "message": "y is \"s\", which isn't a number"}
	row := {"passed": false, "cause": "unusable", "message": "z is 1; y is \"s\", which isn't a number", "inputs": [z, {"name": "y", "value": "s", "locations": ["/y"], "outcome": "usable"}], "failures": [assertion, other]}
	[[i.name, i.outcome] | some i in ergo._said_outcomes(row).inputs] == [["z", "usable"], ["y", "unusable"]]
}

_tag_each(inputs, check, req, subj) := [object.union(i, {"part": {"id": null, "name": "lock"}}) | some i in inputs] if {
	is_object(check)
	is_object(req)
	is_object(subj)
}

test_a_walk_in_an_option_or_among_several_assertions_tags_the_parts_it_reads_and_a_for_line_is_left_as_it_was if {
	c := ergo._s_written_check("every xs.k is 1")
	subj := {"id": "t1", "xs": [{"k": 5}]}
	scope := {"ergo/names": {"$at": {"names": {}}}}
	option := ergo._scoped_walk_outcome(c, {}, subj, "sentence_any_of") with ergo._scoped as true with ergo._scope_of as scope with ergo._tagged as _tag_each
	[[i.name, i.part] | some i in option.inputs] == [["xs[].k", {"id": null, "name": "lock"}]]
	line := ergo._scoped_walk_outcome(c, {}, subj, "for") with ergo._scoped as true with ergo._scope_of as scope with ergo._tagged as _tag_each
	[i.name | some i in line.inputs; not i.part] == ["xs[].k"]
}

test_a_counted_list_written_with_a_dot_is_never_an_input_of_an_assertion_in_an_option_or_among_several if {
	c := {"cmp": "eq", "left": {"count_of": [{"literal": "lock"}, "pkgs"], "text": "count of .lock.pkgs", "whose": []}, "op": "compare", "right": {"literal": 1}}
	e := {"kind": "assertion", "name": "count of .lock.pkgs is 1", "cause": "value", "inputs": [{"name": "count of .lock.pkgs", "value": 2}, {"name": ".lock.pkgs[]", "outcome": "usable", "value": [{"n": 1}, {"n": 2}]}], "failures": [], "message": "count of .lock.pkgs is 2"}
	row := {"ergo/subj": {"id": "t1", "lock": {"pkgs": [{"n": 1}, {"n": 2}]}}, "ergo/req": {}}
	[i.name | some i in ergo._tallied_entry(e, c, {"cause": "value"}, "/repos/0", {"check": {"op": "sentence_any_of"}}, row).inputs] == ["count of .lock.pkgs"]
}

test_a_count_gives_an_item_entry_for_each_item_beside_a_key_it_cant_read if {
	check := ergo._s_written_check("count of es whose zz is m named by $params.k is 0")
	m := "$params.k is missing; item 1 of es: m is missing; item 2 of es: m is missing; item 3 of es: m is missing; and 1 more"
	parts := ergo._tally_item_parts(check, {"es": [{"zz": 1}, {"zz": 1}, {"zz": 1}, {"zz": 1}]}, "absent", "/things/0", m) with data.ergo_params as {}
	[[p.name, p.cause, p.message] | some p in parts] == [["item 1 of es", "absent", "m is missing"], ["item 2 of es", "absent", "m is missing"], ["item 3 of es", "absent", "m is missing"], ["item 4 of es", "absent", "m is missing"]]
	ergo._tally_rest_of(m, set(), ergo._tally_item_texts(check, {"es": [{"zz": 1}, {"zz": 1}, {"zz": 1}, {"zz": 1}]}, "absent", m)) == "$params.k is missing" with data.ergo_params as {}
}

test_a_count_item_beside_a_key_it_cant_read_reads_the_value_before_the_key_as_an_every_item_does if {
	check := ergo._s_written_check("count of es whose zz is m named by $params.k is 0")
	m := "$params.k is missing; item 1 of es: m is missing; item 2 of es: m is null; item 3 of es: m is 3, which isn't an object"
	parts := ergo._tally_item_parts(check, {"es": [{"zz": 1}, {"zz": 1, "m": null}, {"zz": 1, "m": 3}]}, "unusable", "/things/0", m) with data.ergo_params as {}
	[[p.name, p.cause, p.inputs] | some p in parts] == [
		["item 1 of es", "absent", [{"name": "es[0].m", "value": null, "locations": ["/things/0/es/0"], "outcome": "absent"}]],
		["item 2 of es", "null", [{"name": "es[1].m", "value": null, "locations": ["/things/0/es/1/m"], "outcome": "absent"}]],
		["item 3 of es", "unusable", [{"name": "es[2].m", "value": 3, "locations": ["/things/0/es/2/m"], "outcome": "unusable"}]],
	]
}

test_a_member_nests_under_the_items_of_the_lists_before_it_like_an_item if {
	ergo._level_names("member b of rs[0].statuses", 1) == ["item 1 of rs", "member b of statuses"]
	ergo._level_names(`member "a; b" of rs[1].statuses`, 1) == ["item 2 of rs", `member "a; b" of statuses`]
	ergo._level_names("item 2 of rs[0].statuses", 1) == ["item 1 of rs", "item 2 of statuses"]
}

test_a_tally_entry_keeps_a_member_name_whole_when_its_key_holds_a_colon if {
	e := {"kind": "item", "name": `member "a: b" of statuses`, "cause": "unusable", "inputs": [], "locations": ["~~/statuses/a: b"], "message": `member "a: b" of statuses is "x", which isn't a number`}
	x := ergo._tally_leveled(e, ["statuses", {"member": "a: b"}], {"trail": []}, "/things/0")
	[x.name, x.message] == [`member "a: b" of statuses`, `member "a: b" of statuses is "x", which isn't a number`]
	not x["ergo/levels"]
	y := ergo._tally_leveled(object.union(e, {"name": `member "a; b: c" of statuses`, "message": "kind is missing"}), ["statuses", {"member": "a; b: c"}], {"trail": []}, "/things/0")
	[y.name, y.message] == [`member "a; b: c" of statuses`, "kind is missing"]
}

test_the_list_of_a_member_is_what_follows_its_key if {
	ergo._list_base("member b of statuses") == "statuses"
	ergo._list_base(`member "x of y" of r.evidence`) == "r.evidence"
	ergo._list_base("item 2 of xs[0].ys") == "xs"
	ergo._list_base("xs") == "xs"
}

test_a_text_beside_a_member_that_names_no_item_is_a_root_text if {
	row := {"failed_items": [{"item": "member b of xs"}, {"item": "member c of xs"}, {"item": "member d of xs"}]}
	clauses := [
		ergo._m_clause("root", "$params.k", "absent", "$params.k is missing"),
		ergo._m_clause("item", ["xs", "c"], "value", "member c of xs is 1"),
		ergo._m_clause("root", "", "value", ""),
	]
	ergo._walk_root_texts(row, clauses) == ["$params.k is missing"]
	ergo._walk_owned_texts(row, clauses) == ["", "member c of xs is 1", ""]
}

test_a_list_entry_of_a_walk_with_no_items_takes_its_name_and_cause_from_its_clause if {
	row := {"ergo/subj": {"xs": "s", "ys": null}, "ergo/heads": [
		ergo._m_clause("list", "xs", "absent", "xs is gone"),
		ergo._m_clause("root", "$params.k", "unusable", "$params.k is 3, which isn't text"),
	]}
	[[e.kind, e.name, e.cause, e.message] | some e in ergo._walk_flaw_lists(row, "s", {"path": ["xs"]}, [])] == [["list", "xs", "absent", "xs is gone"]]
	ergo._walk_flaw_lists(row, "s", {"path": ["xs"]}, [{"kind": "item"}]) == []
}

test_an_item_clause_is_the_items_own_text_whatever_its_words_say if {
	row := {"failed_items": [{"item": "item 1 of xs"}, {"item": "xs"}]}
	clauses := [ergo._m_clause("item", ["xs", 0], "absent", "cov.z is missing"), ergo._m_clause("list", "xs", "absent", "xs is missing")]
	ergo._walk_root_texts(row, clauses) == []
	ergo._walk_owned_texts(row, clauses) == ["cov.z is missing", "xs is missing"]
}

test_a_member_read_by_its_key_is_its_list_and_its_key if {
	ergo._whose_item_name({"item": "member b of xs"}) == "xs.b"
	ergo._whose_item_name({"item": `member "a b" of r.evidence`}) == `r.evidence."a b"`
	ergo._whose_item_name({"item": "item 2 of xs"}) == "xs[1]"
}

test_the_object_a_count_of_member_of_reads_is_its_own_read_as_a_walked_list_is if {
	members := ergo._s_written_check("sum of member of costs is at most 3")
	ergo._tally_own_read({"name": "costs", "value": [1, 5]}, members, set(), [{"kind": "item"}])
	ergo._tally_own_read({"name": "costs", "value": []}, members, set(), [])
	not ergo._tally_own_read({"name": "costs", "value": 5}, members, set(), [])
	not ergo._tally_own_read({"name": "costs.x", "value": [1]}, members, set(), [])
	ergo._tally_own_read({"name": "costs[]", "value": [1]}, members, set(), [{"kind": "item"}])
	items := ergo._s_written_check("sum of costs is at most 3")
	ergo._tally_own_read({"name": "costs[]"}, items, set(), [{"kind": "item"}])
	ergo._tally_own_read({"name": "costs"}, items, set(), [{"kind": "item"}])
}

test_a_list_after_is_in_ignoring_case_that_holds_an_item_that_isnt_text_is_an_unusable_input_even_when_the_row_fails_as_null if {
	ergo._with_outcome({"name": "ys", "value": ["a", null]}) == {"name": "ys", "value": ["a", null], "outcome": "unusable"} with data.ergo_text_lists as {"ys"}
	ergo._with_outcome({"name": "ys", "value": [3]}).outcome == "unusable" with data.ergo_text_lists as {"ys"}
	ergo._with_outcome({"name": "ys", "value": ["a"]}).outcome == "usable" with data.ergo_text_lists as {"ys"}
	ergo._with_outcome({"name": "zs", "value": [null]}).outcome == "usable" with data.ergo_text_lists as {"ys"}
	ergo._with_outcome({"name": "ys", "value": null}) == {"name": "ys", "value": null} with data.ergo_text_lists as {"ys"}
}

test_the_lists_a_check_compares_ignoring_case_are_named_as_its_inputs_name_them if {
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._text_list_names(field) == {"ys"}
	ergo._text_list_names(object.remove(field, ["ignoring"])) == set()
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._text_list_names({"op": "every", "path": ["xs"], "check": {"op": "present", "path": ["x"]}, "whose": [ref]}) == {"$params.l"}
	parent := {"op": "compare", "left": ["v"], "cmp": "in", "right": [`${"alias":"thing","n":0,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._text_list_names({"op": "compare", "cmp": "eq", "left": {"count_of": ["xs"], "whose": [parent]}, "right": {"literal": 0}}) == {"thing.ys"}
	root := {"op": "compare", "left": ["x"], "cmp": "not_in", "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._text_list_names({"op": "every", "path": ["xs", "v"], "check": root}) == {"ys"}
}
