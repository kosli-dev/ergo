package ergo_test

import data.ergo
import rego.v1

_parts_results(doc, checks, params) := [r | some r in ergo.report(doc, _sentence_policy({"c": checks}), params).results; r.check == "c"]

_flat(entry) := {
	"kind": entry.kind,
	"name": entry.name,
	"cause": entry.cause,
	"message": entry.message,
}

_shape(entry) := object.union(_flat(entry), {"failures": [_shape_one(f) | some f in entry.failures]})

_shape_one(entry) := object.union(_flat(entry), {"failures": [_flat(f) | some f in entry.failures]})

test_a_missing_field_is_read_as_absent_and_only_on_a_failed_row if {
	rows := _parts_results({"things": [{"id": "m"}, {"id": "f", "x": "ok"}]}, "x is \"ok\"", {})
	rows[0].inputs == [{"name": "x", "value": null, "locations": ["/things/0"], "outcome": "absent"}]
	rows[1].inputs == [{"name": "x", "value": "ok", "locations": ["/things/1/x"]}]
}

test_a_null_field_is_read_as_null_and_only_on_a_failed_row if {
	rows := _parts_results({"things": [{"id": "n", "x": null}, {"id": "f", "x": "ok"}]}, "x is \"ok\"", {})
	rows[0].inputs == [{"name": "x", "value": null, "locations": ["/things/0/x"], "outcome": "null"}]
	not "outcome" in object.keys(rows[1].inputs[0])
}

test_a_wrong_typed_field_is_found_and_the_row_fails_as_unusable if {
	rows := _parts_results({"things": [{"id": "w", "x": [1]}]}, "x is \"ok\"", {})
	rows[0].cause == "unusable"
	rows[0].inputs == [{"name": "x", "value": [1], "locations": ["/things/0/x"], "outcome": "found"}]
}

test_a_failed_row_gives_an_outcome_to_every_path_input_of_each_entry_under_it if {
	rows := _parts_results({"things": [{"id": "a", "x": 1, "y": 3}]}, "x is 1 and y is 2", {})
	every i in rows[0].inputs {
		i.outcome == "found"
	}
	every f in rows[0].failures {
		every i in f.inputs {
			i.outcome == "found"
		}
	}
}

test_a_passed_row_has_no_failures_no_message_and_no_outcome if {
	every check in ["x is 1", "x is 1 and y is 2", {"any_of": {"a": "x is 1", "b": "x is 2"}}, {"for": "every xs as x", "assert": "x.v is 1"}] {
		rows := _parts_results({"things": [{"id": "a", "x": 1, "y": 2, "xs": [{"v": 1}]}]}, check, {})
		count(rows) == 1
		rows[0].passed
		object.keys(rows[0]) == {"cause", "check", "inputs", "passed", "requirement", "subject"}
		every i in rows[0].inputs {
			not "outcome" in object.keys(i)
		}
	}
}

test_a_one_sentence_check_has_one_assertion_entry_with_the_policy_location_of_its_sentence if {
	rows := _parts_results({"things": [{"id": "a", "x": 2}]}, "x is 1", {})
	[[f.kind, f.name, f.locations, f.failures] | some f in rows[0].failures] == [["assertion", "x is 1", ["$policy:/requirements/s/checks/c"], []]]
}

test_each_sentence_of_a_check_with_and_has_its_own_location_numbered_in_the_string if {
	rows := _parts_results({"things": [{"id": "a", "x": 2, "y": 3}]}, "x is 1 and y is 2", {})
	[f.locations | some f in rows[0].failures] == [["$policy:/requirements/s/checks/c#1"], ["$policy:/requirements/s/checks/c#2"]]
}

test_a_failed_sentence_of_an_assert_list_names_its_own_policy_location if {
	rows := _parts_results({"things": [{"id": "a", "x": 1, "y": 3}]}, {"assert": ["x is 1", "y is 2"]}, {})
	[[f.name, f.locations] | some f in rows[0].failures] == [["y is 2", ["$policy:/requirements/s/checks/c/assert/1"]]]
}

test_an_any_of_row_lists_its_options_sorted_by_name_with_their_assertions_under_them if {
	rows := _parts_results({"things": [{"id": "a", "x": 1, "y": 3}]}, {"any_of": {"b": "x is 2", "a": ["x is 1 and y is 2", "y exists"]}}, {})
	[_shape(f) | some f in rows[0].failures] == [
		{"kind": "option", "name": "a", "cause": "value", "message": "y is 3", "failures": [{"kind": "assertion", "name": "y is 2", "cause": "value", "message": "y is 3", "failures": []}]},
		{"kind": "option", "name": "b", "cause": "value", "message": "x is 1", "failures": [{"kind": "assertion", "name": "x is 2", "cause": "value", "message": "x is 1", "failures": []}]},
	]
}

test_an_option_and_its_assertions_have_locations_in_the_policy_and_an_option_reads_nothing_itself if {
	rows := _parts_results({"things": [{"id": "a", "x": 1, "y": 3}]}, {"any_of": {"b": "x is 2", "a": ["x is 1 and y is 2", "y exists"]}}, {})
	[[f.locations, f.inputs, [g.locations | some g in f.failures]] | some f in rows[0].failures] == [
		[["$policy:/requirements/s/checks/c/any_of/a"], [], [["$policy:/requirements/s/checks/c/any_of/a/0#2"]]],
		[["$policy:/requirements/s/checks/c/any_of/b"], [], [["$policy:/requirements/s/checks/c/any_of/b"]]],
	]
}

test_a_for_line_sentence_that_does_not_read_the_alias_is_its_own_assertion_with_its_own_message if {
	things := [{"id": "a", "z": 2, "w": 5, "xs": [{"v": 2}, {"v": 1}]}]
	rows := _parts_results({"things": things}, {"for": "every xs as x", "assert": ["x.v is 1", "z is 3", "w is 4"]}, {})
	rows[0].message == "z is 2; w is 5; item 1 of xs: x.v is 2"
	[_shape(f) | some f in rows[0].failures] == [
		{"kind": "assertion", "name": "x.v is 1", "cause": "value", "message": "", "failures": [{"kind": "item", "name": "item 1 of xs", "cause": "value", "message": "x.v is 2", "failures": []}]},
		{"kind": "assertion", "name": "z is 3", "cause": "value", "message": "z is 2", "failures": []},
		{"kind": "assertion", "name": "w is 4", "cause": "value", "message": "w is 5", "failures": []},
	]
}

test_a_for_line_whose_list_is_missing_has_the_list_on_the_row_and_no_assertion_that_passed if {
	rows := _parts_results({"things": [{"id": "c", "z": 3, "w": 4}]}, {"for": "every xs as x", "assert": ["x.v is 1", "z is 3", "w is 4"]}, {})
	[_shape(f) | some f in rows[0].failures] == [{"kind": "list", "name": "xs", "cause": "absent", "message": "xs is missing", "failures": []}]
}

test_a_for_line_second_list_that_breaks_sits_on_the_row_after_the_assertions_and_not_under_each_one if {
	rows := _parts_results({"things": [{"id": "a", "ws": [{"ys": [{"n": 1}]}, {"ys": null}, {}]}]}, {"for": "every ws as w2, every w2.ys as y", "assert": ["y.n is 1", "y.n exists"]}, {})
	rows[0].message == "item 2 of ws: w2.ys is null; item 3 of ws: w2.ys is missing"
	[_shape(f) | some f in rows[0].failures] == [
		{"kind": "item", "name": "item 2 of ws", "cause": "null", "message": "", "failures": [{"kind": "list", "name": "w2.ys", "cause": "null", "message": "w2.ys is null", "failures": []}]},
		{"kind": "item", "name": "item 3 of ws", "cause": "absent", "message": "", "failures": [{"kind": "list", "name": "w2.ys", "cause": "absent", "message": "w2.ys is missing", "failures": []}]},
	]
}

test_an_item_that_failed_two_sentences_of_a_for_line_sits_under_each_of_them if {
	rows := _parts_results({"things": [{"id": "a", "xs": [{"v": 2, "k": 2}]}]}, {"for": "every xs as x", "assert": ["x.v is 1", "x.k is 1"]}, {})
	[[f.name, [g.name | some g in f.failures]] | some f in rows[0].failures] == [["x.v is 1", ["item 1 of xs"]], ["x.k is 1", ["item 1 of xs"]]]
}

test_a_for_line_item_names_what_it_read_through_the_alias_and_has_a_value_and_a_location if {
	rows := _parts_results({"things": [{"id": "a", "xs": [{"v": 2}, {"v": 1}]}]}, {"for": "every xs as x", "assert": "x.v is 1"}, {})
	item := rows[0].failures[0].failures[0]
	item.inputs == [{"name": "x.v", "value": 2, "locations": ["/things/0/xs/0/v"], "outcome": "found"}]
	item.value == {"v": 2}
	item.locations == ["/things/0/xs/0"]
}

test_a_walk_that_reads_no_list_has_a_list_entry_under_its_assertion if {
	rows := _parts_results({"things": [{"id": "b"}]}, "every x.y is 1", {})
	[_shape(f) | some f in rows[0].failures] == [{"kind": "assertion", "name": "every x.y is 1", "cause": "absent", "message": "", "failures": [{"kind": "list", "name": "x", "cause": "absent", "message": "x is missing", "failures": []}]}]
	rows[0].failures[0].failures[0].inputs == [{"name": "x", "value": null, "locations": ["/things/0"], "outcome": "absent"}]
}

test_a_list_failing_deep_down_sits_under_the_items_it_belongs_to if {
	doc := {"things": [{"id": 1, "groups": [{"teams": [{"units": [{"n": 1}, {"n": 2}]}, {"units": null}]}]}]}
	rows := _walk_rows({"c": "every groups.teams.units.n is 1"}, doc, {})
	rows[0][3] == [_assertion("every groups.teams.units.n is 1", "null", ["$policy:/requirements/s/checks/c"], [], "", [_item("item 1 of groups", "null", {"teams": [{"units": [{"n": 1}, {"n": 2}]}, {"units": null}]}, ["/things/0/groups/0"], [], "", [_item("item 1 of teams", "value", {"units": [{"n": 1}, {"n": 2}]}, ["/things/0/groups/0/teams/0"], [], "", [_item("item 2 of units", "value", {"n": 2}, ["/things/0/groups/0/teams/0/units/1"], [_seen("groups[0].teams[0].units[1].n", 2, ["/things/0/groups/0/teams/0/units/1/n"], "found")], "n is 2", [])]), _item("item 2 of teams", "null", {"units": null}, ["/things/0/groups/0/teams/1"], [], "", [_list("units", "null", [_seen("groups[0].teams[1].units", null, ["/things/0/groups/0/teams/1/units"], "null")], "units is null")])])])]
}

test_a_for_lines_second_list_through_a_deep_path_sits_under_the_items_it_belongs_to if {
	rows := _for_rows({"for": "every prs as pr, every pr.meta.commits as c", "assert": "c.signed is true"}, [{"id": 1, "prs": [{"meta": {"commits": [{"signed": true}, {"signed": false}]}}, {"meta": {"commits": null}}]}], {})
	rows[0][2] == [_assertion("c.signed is true", "value", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 1 of prs", "value", {"meta": {"commits": [{"signed": true}, {"signed": false}]}}, ["/things/0/prs/0"], [], "", [_item("item 2 of pr.meta.commits", "value", {"signed": false}, ["/things/0/prs/0/meta/commits/1"], [_seen("c.signed", false, ["/things/0/prs/0/meta/commits/1/signed"], "found")], "c.signed is false", [])])]), _item("item 2 of prs", "null", {"meta": {"commits": null}}, ["/things/0/prs/1"], [], "", [_list("pr.meta.commits", "null", [_seen("pr.meta.commits", null, ["/things/0/prs/1/meta/commits"], "null")], "pr.meta.commits is null")])]
}

test_two_sentences_that_say_the_same_text_each_keep_it_and_the_row_says_it_once if {
	policy := _sentence_policy({"c": {"description": "d", "assert": ["x is 1", "x is 2"]}})
	rows := [r | some r in ergo.report({"things": [{"id": 1, "x": 5}]}, policy, {}).results; r.check == "c"]
	rows[0].message == "x is 5"
	[f.message | some f in rows[0].failures] == ["x is 5", "x is 5"]
}
