package ergo_test

import data.ergo
import rego.v1

unique_of(subjects, doc) := r if {
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": "thing", "min_subjects": 0, "checks": {"c": "x exists"}}}}, {})
	some r in rep.results
	r.check == "$unique_ids"
}

test_a_subject_whose_id_is_missing_or_null_fails_unique_ids_named_by_its_place if {
	r := unique_of({"thing": {"from": "ds", "identified_by": "id"}}, {"ds": [{"id": "a"}, {"ok": 1}, {"id": null}, {"id": "a"}]})
	r.cause == "absent"
	r.message == "repeated thing ids is [\"a\"]; item 2 of ds: id is missing; item 3 of ds: id is null"
	[[f.name, f.message, f.locations] | some f in r.failures] == [["item 2 of ds", "id is missing", ["/ds/1"]], ["item 3 of ds", "id is null", ["/ds/2"]]]
}

test_a_null_item_is_its_own_id_so_it_fails_unique_ids_with_or_without_identified_by if {
	every subject in [{"from": "ds"}, {"from": "ds", "identified_by": "id"}] {
		r := unique_of({"thing": subject}, {"ds": ["a", null]})
		r.cause == "null"
		r.message == "item 2 of ds is null"
		r.failures[0].inputs == [{"name": "ds[1]", "value": null, "locations": ["/ds/1"], "outcome": "null"}]
	}
}

test_an_id_read_through_a_field_says_what_stopped_it_as_a_check_would if {
	r := unique_of({"thing": {"from": "ds", "identified_by": "meta.id"}}, {"ds": [{"meta": 3}, {"meta": null}, {"meta": {}}]})
	r.cause == "unusable"
	r.message == "item 1 of ds: meta is 3, which isn't an object; item 2 of ds: meta is null; item 3 of ds: meta.id is missing"
}

test_a_subject_without_an_id_in_a_list_of_lists_sits_under_the_outer_item if {
	r := unique_of({"thing": {"from": "every xs.bs", "identified_by": "id"}}, {"xs": [{"bs": [{"id": 1}, {"x": 1}]}]})
	r.message == "item 1 of xs: item 2 of bs: id is missing"
	r.failures[0].name == "item 1 of xs"
	r.failures[0].locations == ["/xs/0"]
	r.failures[0].failures[0].name == "item 2 of bs"
	r.failures[0].failures[0].inputs[0].name == "xs[0].bs[1].id"
}

test_a_subject_outside_a_list_without_an_id_puts_the_read_on_the_row if {
	r := unique_of({"thing": {"identified_by": "id"}}, {"thing": {"x": 1}})
	r.message == "thing.id is missing"
	r.failures == []
	r.inputs[1] == {"name": "thing.id", "value": null, "locations": ["/thing"], "outcome": "absent"}
}

test_a_subject_out_of_scope_without_an_id_still_fails_unique_ids if {
	r := unique_of({"thing": {"from": "ds whose keep exists", "identified_by": "id"}}, {"ds": [{"id": 1, "keep": 1}, {}]})
	r.message == "item 2 of ds: id is missing"
}

test_copies_of_a_subject_without_an_id_list_every_copy if {
	r := unique_of({"thing": {"from": "every distinct ds"}}, {"ds": [null, "a", null]})
	r.message == "item 1 of ds is null"
	r.failures[0].locations == ["/ds/0", "/ds/2"]
}

test_ids_of_any_other_value_are_ids if {
	r := unique_of({"thing": {"from": "ds", "identified_by": "id"}}, {"ds": [{"id": ""}, {"id": 0}, {"id": false}, {"id": {}}, {"id": []}]})
	r.passed == true
}

test_a_child_and_a_parent_without_an_id_are_named_from_where_they_were_read if {
	subjects := {"art": {"from": "arts whose live exists", "identified_by": "id"}, "thing": {"from": "every art.prs", "identified_by": "id"}}
	rep := ergo.report({"arts": [{"id": "a1", "live": 1, "prs": [{"id": 1}, {}]}, {"prs": [{"id": 2}]}]}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": "thing", "checks": {"c": "x exists"}}}}, {})
	[[r.check, r.message, r.failures[0].locations] | some r in rep.results; r.check in {"$unique_ids", "$unique_ancestor_ids"}] == [
		["$unique_ids", "item 2 of prs: id is missing", ["/arts/0/prs/1"]],
		["$unique_ancestor_ids", "item 2 of arts: id is missing", ["/arts/1"]],
	]
}

test_the_whole_input_without_an_id_is_named_from_the_input if {
	r := unique_of({"thing": {"from": "$input", "identified_by": "id"}}, {"x": 1})
	[r.cause, r.message, r.failures] == ["absent", "$input.id is missing", []]
	r.inputs[1] == {"name": "$input.id", "value": null, "locations": [""], "outcome": "absent"}
}

test_a_subject_read_through_a_field_of_each_item_is_named_by_its_item if {
	r := unique_of({"thing": {"from": "every xs.meta", "identified_by": "id"}}, {"xs": [{"meta": {}}, {"meta": {"id": 1}}, {"meta": {}}, {"meta": {"id": null}}, {"meta": {}}]})
	r.message == "item 1 of xs: meta.id is missing; item 3 of xs: meta.id is missing; item 4 of xs: meta.id is null; and 1 more"
	count(r.inputs) == 1
	count(r.failures) == 4
	r.failures[0] == {"kind": "item", "name": "item 1 of xs", "cause": "absent", "message": "meta.id is missing", "failures": [], "inputs": [{"name": "xs[0].meta.id", "value": null, "locations": ["/xs/0/meta"], "outcome": "absent"}], "value": {"meta": {}}, "locations": ["/xs/0"]}
}

test_an_id_read_through_a_null_field_fails_as_null if {
	r := unique_of({"thing": {"from": "ds", "identified_by": "meta.id"}}, {"ds": [{"meta": null}]})
	r.cause == "null"
}

test_a_subject_picked_by_position_without_an_id_is_an_item if {
	r := unique_of({"thing": {"from": "first of ds", "identified_by": "id"}}, {"ds": [{}]})
	[r.failures[0].kind, r.failures[0].name, r.failures[0].message] == ["item", "item 1 of ds", "id is missing"]
}
