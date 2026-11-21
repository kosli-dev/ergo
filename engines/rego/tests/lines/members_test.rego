package ergo_test

import data.ergo
import rego.v1

_fm_ats(w) := [s.at | some s in w.subjects]

_fm_keys(w) := [s.key | some s in w.subjects]

_fm_said(w) := [[f.path, f.cause] | some f in w.fails]

test_each_member_of_the_object_at_the_end_is_an_item_in_key_order_with_its_key if {
	w := ergo._fm_walk({"records": [{"id": "r1", "evidence": {"sign-off": {"kind": "approval"}, "build-7": {"kind": "scan"}}}]}, ["records", "evidence"])
	_fm_ats(w) == ["/records/0/evidence/build-7", "/records/0/evidence/sign-off"]
	_fm_keys(w) == ["build-7", "sign-off"]
	w.fails == []
	w.notes == []
}

test_members_sort_by_code_point_and_their_location_escapes_the_key if {
	w := ergo._fm_walk({"o": {"b": 1, "B": 2, "a": 3, "é": 4, "x/y": 5}}, ["o"])
	_fm_ats(w) == ["/o/B", "/o/a", "/o/b", "/o/x~1y", "/o/é"]
}

test_an_end_that_is_there_but_is_not_an_object_fails_unusable_and_other_ends_still_give_members if {
	w := ergo._fm_walk({"records": [{"evidence": {"a": 1}}, {"evidence": [1]}, {"evidence": "x"}, {"evidence": 2}, {"evidence": true}]}, ["records", "evidence"])
	_fm_ats(w) == ["/records/0/evidence/a"]
	_fm_said(w) == [[["records", 1, "evidence"], "unusable"], [["records", 2, "evidence"], "unusable"], [["records", 3, "evidence"], "unusable"], [["records", 4, "evidence"], "unusable"]]
	w.fails[0].why == {"path": ["records", 1, "evidence"], "value": [1], "kind": "an object"}
	w.fails[0].at == "/records/1/evidence"
	w.fails[0].value == [1]
}

test_a_list_at_the_end_is_not_walked_into if {
	w := ergo._fm_walk({"evidence": [{"a": 1}]}, ["evidence"])
	w.subjects == []
	_fm_said(w) == [[["evidence"], "unusable"]]
	w.fails[0].why == {"path": ["evidence"], "value": [{"a": 1}], "kind": "an object"}
}

test_a_missing_or_null_end_keeps_absent_or_null if {
	w := ergo._fm_walk({"records": [{}, {"evidence": null}, {"evidence": {"a": 1}}]}, ["records", "evidence"])
	_fm_ats(w) == ["/records/2/evidence/a"]
	_fm_said(w) == [[["records", 0, "evidence"], "absent"], [["records", 1, "evidence"], "null"]]
}

test_an_empty_object_gives_no_member_and_fails_nothing if {
	w := ergo._fm_walk({"records": [{"evidence": {}}]}, ["records", "evidence"])
	w.subjects == []
	w.fails == []
}

test_a_null_member_is_still_an_item if {
	w := ergo._fm_walk({"records": [{"evidence": {"a": null}}]}, ["records", "evidence"])
	_fm_ats(w) == ["/records/0/evidence/a"]
	w.subjects[0].subject == null
	w.fails == []
}

test_no_list_along_the_path_still_gives_the_members if {
	_fm_ats(ergo._fm_walk({"o": {"b": 1, "a": 2}}, ["o"])) == ["/o/a", "/o/b"]
	w := ergo._fm_walk({"b": 1, "a": 2}, [])
	_fm_ats(w) == ["/a", "/b"]
	_fm_keys(w) == ["a", "b"]
}

test_no_list_along_the_path_and_a_read_that_stops_before_the_end_fails_as_every_does if {
	w := ergo._fm_walk({"p": null}, ["p", "q"])
	w.subjects == []
	w.fails == ergo._every_walk({"p": null}, ["p", "q"]).fails
}

test_members_of_mixed_types_name_the_first_member_of_each_type if {
	w := ergo._fm_walk({"records": [{"evidence": {"a": {}, "b": "x", "c": "y"}}]}, ["records", "evidence"])
	count(w.subjects) == 3
	[n.types | some n in w.notes] == [[["an object", ["records", 0, "evidence", "a"], {}], ["text", ["records", 0, "evidence", "b"], "x"]]]
}

test_a_list_in_the_middle_is_walked_as_every_walks_it if {
	_fm_ats(ergo._fm_walk({"records": [{"evidence": {"a": 1}}, {"evidence": {"b": 2}}]}, ["records", "evidence"])) == ["/records/0/evidence/a", "/records/1/evidence/b"]
}
