package ergo_test

import data.ergo
import rego.v1

test_ergos_absent_marker_is_something_only_an_input_that_fails_closed_can_hold if {
	req := lookalike_req("items", {"m": "o does not exist"})
	rep := report({"items": [{"id": 1, "o": ergo._absent}]}, req)
	[[r.check, r.passed, r.cause] | some r in rep.results; r.check in {"$min_subjects", "m"}] == [["$min_subjects", false, "unusable"], ["m", false, "unusable"]]
	from_params := report({"items": [{"id": 1}]}, req) with data.params as {"x": ergo._absent}
	[[r.check, r.passed, r.cause] | some r in from_params.results; r.check in {"$min_subjects", "m"}] == [["$min_subjects", false, "unusable"], ["m", false, "unusable"]]
}

test_a_pointer_reads_into_a_list_a_name_holds_and_stops_where_the_read_stopped if {
	ergo._pointer("/x", [10, 20], [1]) == "/x/1"
	ergo._pointer("/x", [10], [3]) == "/x"
	ergo._pointer("/x", 5, ["a"]) == "/x"
	ergo._pointer("/x", 5, []) == "/x"
	ergo._pointer("", {"a": [{"b": 1}]}, ["a", 0, "c"]) == "/a/0"
}

test_a_read_that_starts_at_a_name_nothing_holds_has_no_location_and_never_leaves_the_report if {
	ergo._path_input({}, ["$nope", "a"]) == {"name": "$nope.a", "value": null, "locations": []}
	ergo._locations_of({}, ["$nope", "a"]) == []
	ergo._unread_at({}, {"path": ["$nope", "a"]}, {}) == {}
	ergo._fail_locations({"path": ["$nope", "a"]}) == []
}
