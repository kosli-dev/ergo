package ergo_test

import data.ergo
import rego.v1

test_the_id_check_says_every_subject_has_a_unique_id if {
	ergo._unique_ancestor_description(0, "repo") == "Every repo has a unique id"
	ergo._unique_ancestor_description(1, "pull request") == "every pull request has a unique id"
}

test_the_id_expression_counts_missing_and_repeated_ids if {
	ergo._ids_expression("repos") == "count(missing(ids(repos))) + count(repeated(ids(repos))) == 0"
}

test_a_null_id_is_not_an_id_so_it_never_repeats if {
	refs := {0: {"id": null}, 1: {"id": null}, 2: {"id": "a"}, 3: {"id": "a"}}
	[p[1] | some p in ergo._repeated_ids(refs)] == ["a"]
}

ds_keys(req) := ["ds"] if is_object(req)

place_at(entry, req) := {"c": entry.c} if is_object(req)

test_subjects_without_an_id_are_named_in_the_order_of_the_subjects_whatever_order_their_ids_are_kept_in if {
	raw := [{"subject": {}, "at": concat("", ["/ds/", format_int(i, 10)]), "c": ["ds", i]} | some i in numbers.range(0, 11)]
	refs := {i: {"id": id} | some i, _ in raw; id := _id_or_null(i)}
	places := ergo._id_fault_places(raw, refs, {"subject": "d"}) with ergo._id_fault_place as place_at
	[p.c[1] | some p in places] == [1, 9, 10, 11]
}

_id_or_null(i) := null if i in {1, 9, 10, 11}

else := i

id_fault_place(c, at, cause, text) := {"c": c, "at": at, "cause": cause, "value": null, "text": text, "note": false, "plain": false, "listed": true}

test_ids_that_are_missing_or_null_fail_the_row_after_the_repeated_ids_with_the_worst_cause if {
	row := {"check": "$unique_ids", "inputs": [{"name": "repeated d ids", "value": ["a"], "locations": []}], "passed": false, "cause": "value"}
	places := [
		id_fault_place(["ds", 1, "id"], "/ds/1", "absent", "item 2 of ds: id is missing"),
		id_fault_place(["ds", 2, "id"], "/ds/2/id", "null", "item 3 of ds: id is null"),
	]
	doc := {"ds": [{"id": "a"}, {"ok": true}, {"id": null}, {"id": "a"}]}
	r := ergo._with_id_faults(row, places, doc, {"subject": "d"}) with ergo._id_keys as ds_keys
	r.cause == "absent"
	r.message == "repeated d ids is [\"a\"]; item 2 of ds: id is missing; item 3 of ds: id is null"
	r.failures == [
		{"kind": "item", "name": "item 2 of ds", "cause": "absent", "message": "id is missing", "failures": [], "inputs": [{"name": "ds[1].id", "value": null, "locations": ["/ds/1"], "outcome": "absent"}], "value": {"ok": true}, "locations": ["/ds/1"]},
		{"kind": "item", "name": "item 3 of ds", "cause": "null", "message": "id is null", "failures": [], "inputs": [{"name": "ds[2].id", "value": null, "locations": ["/ds/2/id"], "outcome": "null"}], "value": {"id": null}, "locations": ["/ds/2"]},
	]
}

test_a_unique_ids_row_that_fails_on_a_repeated_id_alone_has_no_failures_to_list if {
	row := {"check": "$unique_ids", "inputs": [{"name": "repeated d ids", "value": ["a"], "locations": []}], "passed": false, "cause": "value"}
	ergo._with_id_faults(row, [], {}, {"subject": "d"}) == object.union(row, {"failures": []})
	passed := object.union(row, {"passed": true, "cause": "satisfied"})
	ergo._with_id_faults(passed, [], {}, {"subject": "d"}) == passed
}

test_a_subject_outside_any_list_puts_its_id_read_on_the_row_and_has_no_entry if {
	row := {"check": "$unique_ids", "inputs": [{"name": "repeated d ids", "value": [], "locations": []}], "passed": true, "cause": "satisfied"}
	place := object.union(id_fault_place(["thing", "id"], "/thing", "absent", "thing.id is missing"), {"listed": false})
	r := ergo._with_id_faults(row, [place], {"thing": {}}, {"subject": "d"})
	r.cause == "absent"
	r.message == "thing.id is missing"
	r.failures == []
	r.inputs[1] == {"name": "thing.id", "value": null, "locations": ["/thing"], "outcome": "absent"}
}

test_the_message_names_three_subjects_without_an_id_and_counts_the_rest if {
	row := {"check": "$unique_ids", "inputs": [{"name": "repeated d ids", "value": [], "locations": []}], "passed": true, "cause": "satisfied"}
	places := [id_fault_place(["ds", i, "id"], concat("", ["/ds/", format_int(i, 10)]), "absent", concat("", ["item ", format_int(i + 1, 10), " of ds: id is missing"])) | some i in numbers.range(0, 4)]
	r := ergo._with_id_faults(row, places, {"ds": [{}, {}, {}, {}, {}]}, {"subject": "d"})
	r.message == "item 1 of ds: id is missing; item 2 of ds: id is missing; item 3 of ds: id is missing; and 2 more"
	count(r.failures) == 5
}
