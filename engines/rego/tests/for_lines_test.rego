package ergo_test

import data.ergo
import rego.v1

test_a_bare_word_after_named_by_that_no_for_line_gives_is_an_unknown_alias if {
	_sentence_problems({"for": "every xs named by x as x", "assert": "x is 1"}) == ["for: unknown alias x"]
}

test_a_part_on_a_for_line_item_counts_the_parts_path if {
	doc := {"things": [object.union({"id": "a"}, _k9({"z": [1]})), object.union({"id": "b"}, _k9({"z": [2]}))]}
	_part_walk_rows({"x": _nine}, {"c": {"for": "every x.z as y", "assert": "y is 1"}}, doc) == [["a", "c", "satisfied"], ["b", "c", "value"]]
	_part_walk_problems({"x": _ten}, {"for": "every x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "some x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "first of x.z as y", "assert": "y is 1"}) == [_for_too_long]
	_part_walk_problems({"x": _ten}, {"for": "every xs as y", "assert": "y.n is count of x.z"}) == _too_long
}

test_a_for_line_lists_each_first_item_that_failed_with_the_lines_it_failed if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	[[row[0], row[1]] | some row in rows] == [["peer", "satisfied"], ["fails", "value"], ["nostate", "absent"]]
	rows[1][2] == [_assertion("approver.username does not equal author", "value", ["$policy:/requirements/s/checks/c/assert/0"], [_seen("author", "ann", ["/things/1/author"], "usable")], "", [_item("item 2 of approvers", "value", {"state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z", "username": "ann"}, ["/things/1/approvers/1"], [_seen("approver.username", "ann", ["/things/1/approvers/1/username"], "usable")], "approver.username is \"ann\", and author is \"ann\"", [])]), _assertion("approver.timestamp is after commit.timestamp", "value", ["$policy:/requirements/s/checks/c/assert/1"], [], "", [_item("item 1 of approvers", "value", {"state": "APPROVED", "timestamp": "2026-10-01T10:00:00Z", "username": "bob"}, ["/things/1/approvers/0"], [], "", [_item("item 2 of commits", "value", {"timestamp": "2026-10-01T11:00:00Z"}, ["/things/1/commits/1"], [_seen("approver.timestamp", "2026-10-01T10:00:00Z", ["/things/1/approvers/0/timestamp"], "usable"), _seen("commit.timestamp", "2026-10-01T11:00:00Z", ["/things/1/commits/1/timestamp"], "usable")], "approver.timestamp is \"2026-10-01T10:00:00Z\", and commit.timestamp is \"2026-10-01T11:00:00Z\"", [])])])]
	rows[2][2] == [_item("item 1 of approvers", "absent", {"timestamp": "2026-10-01T12:00:00Z", "username": "carl"}, ["/things/2/approvers/0"], [_seen("approvers[0].state", null, ["/things/2/approvers/0"], "absent")], "state is missing", [])]
	rows[0][2] == []
}

test_a_for_line_shows_each_list_it_walked_once_and_the_subject_fields_it_read if {
	rows := _for_rows(_peer_approval, _peer_things, {})
	rows[1][3] == [_seen("approvers[]", [{"state": "APPROVED", "timestamp": "2026-10-01T10:00:00Z", "username": "bob"}, {"state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z", "username": "ann"}, {"state": "COMMENTED", "timestamp": "2026-10-01T12:00:00Z", "username": "cat"}], ["/things/1/approvers/0", "/things/1/approvers/1", "/things/1/approvers/2"], "usable"), _seen("author", "ann", ["/things/1/author"], "usable"), _seen("commits[]", [{"timestamp": "2026-10-01T09:00:00Z"}, {"timestamp": "2026-10-01T11:00:00Z"}], ["/things/1/commits/0", "/things/1/commits/1"], "usable")]
}

test_a_for_list_fails_closed_as_a_walk_does if {
	check := {"for": "every xs as x", "assert": "x is 1"}
	rows := _for_rows(check, [{"id": 1, "xs": []}, {"id": 2}, {"id": 3, "xs": null}, {"id": 4, "xs": {"a": 1}}], {})
	[[row[0], row[1], row[2]] | some row in rows] == [[1, "value", [_list("xs", "value", [_seen("xs", [], ["/things/0/xs"], "usable")], "xs is []")]], [2, "absent", [_list("xs", "absent", [_seen("xs", null, ["/things/1"], "absent")], "xs is missing")]], [3, "null", [_list("xs", "null", [_seen("xs", null, ["/things/2/xs"], "null")], "xs is null")]], [4, "unusable", [_list("xs", "unusable", [_seen("xs", {"a": 1}, ["/things/3/xs"], "unusable")], "xs is {\"a\": 1}, which isn't a list")]]]
	[row[1] | some row in _for_rows({"for": "every xs, if any, as x", "assert": "x is 1"}, [{"id": 1, "xs": []}, {"id": 2}], {})] == ["satisfied", "absent"]
}

test_an_empty_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it if {
	approvers := [{"u": "ada", "subs": []}, {"u": "g", "state": "REJECTED"}]
	things := [{"id": 1, "approvers": approvers, "commits": []}]
	[[row[1], row[2]] | some row in _for_rows({"for": "some approvers as ap, every commits, if any, as c", "assert": "ap.state is \"APPROVED\""}, things, {})] == [["absent", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert"], [], "item 1 of approvers: ap.state is missing", [_item("item 1 of approvers", "absent", {"subs": [], "u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
	[[row[1], row[2]] | some row in _for_rows({"for": "every approvers as ap, every commits, if any, as c", "assert": "ap.state is \"APPROVED\""}, things, {})] == [["absent", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert"], [], "item 1 of approvers: ap.state is missing", [_item("item 1 of approvers", "absent", {"subs": [], "u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
	[[row[1], row[2]] | some row in _for_rows({"for": "every approvers as ap, every commits whose author is ap.u, if any, as c", "assert": "ap.state is \"APPROVED\""}, [{"id": 1, "approvers": approvers, "commits": [{"author": "bob"}]}], {})] == [["absent", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert"], [], "item 1 of approvers: ap.state is missing", [_item("item 1 of approvers", "absent", {"subs": [], "u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
}

test_a_sentence_that_reads_the_alias_of_an_empty_list_a_for_line_tolerates_has_nothing_to_check if {
	check := {"for": "some approvers as ap, every commits, if any, as c", "assert": ["ap.state is \"APPROVED\"", "c.author does not equal ap.u"]}
	things := [
		{"id": 1, "approvers": [{"u": "ada", "state": "APPROVED"}], "commits": []},
		{"id": 2, "approvers": [{"u": "ada", "state": "APPROVED"}], "commits": [{"author": "ada"}]},
		{"id": 3, "approvers": [{"u": "ada", "state": "REJECTED"}], "commits": []},
	]
	[[row[0], row[1]] | some row in _for_rows(check, things, {})] == [[1, "satisfied"], [2, "value"], [3, "value"]]
	[row[1] | some row in _for_rows({"for": "some approvers as ap, every commits, if any, as c", "assert": "c.author does not equal ap.u"}, [things[2]], {})] == ["satisfied"]
}

test_a_list_a_for_line_tolerates_still_fails_when_it_is_missing_null_or_not_a_list if {
	check := {"for": "some approvers as ap, every commits, if any, as c", "assert": "ap.state is \"APPROVED\""}
	approvers := [{"u": "ada", "state": "APPROVED"}]
	things := [{"id": 1, "approvers": approvers}, {"id": 2, "approvers": approvers, "commits": null}, {"id": 3, "approvers": approvers, "commits": "s"}, {"id": 4, "approvers": approvers, "commits": []}]
	[[row[0], row[1]] | some row in _for_rows(check, things, {})] == [[1, "absent"], [2, "null"], [3, "unusable"], [4, "satisfied"]]
}

_said_rows(check, things) := [[r.subject.id, r.cause, object.get(r, "message", null), object.get(r, "failures", [])] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), {}).results; r.check == "c"]

test_an_empty_first_list_a_for_line_tolerates_still_runs_the_sentences_that_dont_read_it if {
	approvers := [{"u": "ada"}, {"u": "g", "state": "REJECTED"}]
	every line in ["every commits, if any, as c, some approvers as ap", "every commits, if any, as c, every approvers as ap"] {
		_said_rows({"for": line, "assert": ["ap.state is \"APPROVED\"", "c.author is ap.u"]}, [{"id": 1, "approvers": approvers, "commits": []}]) == [[1, "absent", "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\"", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert/0"], [], "", [_item("item 1 of approvers", "absent", {"u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
		_said_rows({"for": line, "assert": ["c.author is ap.u", "ap.state is \"APPROVED\""]}, [{"id": 1, "approvers": approvers, "commits": []}]) == [[1, "absent", "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\"", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert/1"], [], "", [_item("item 1 of approvers", "absent", {"u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
	}
	_said_rows({"for": "every commits whose n is 1, if any, as c, some approvers as ap", "assert": "ap.state is \"APPROVED\""}, [{"id": 1, "approvers": approvers, "commits": [{"n": 2}]}]) == [[1, "absent", "item 1 of approvers: ap.state is missing; item 2 of approvers: ap.state is \"REJECTED\"", [_assertion("ap.state is \"APPROVED\"", "absent", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 1 of approvers", "absent", {"u": "ada"}, ["/things/0/approvers/0"], [_seen("ap.state", null, ["/things/0/approvers/0"], "absent")], "ap.state is missing", []), _item("item 2 of approvers", "value", {"state": "REJECTED", "u": "g"}, ["/things/0/approvers/1"], [_seen("ap.state", "REJECTED", ["/things/0/approvers/1/state"], "usable")], "ap.state is \"REJECTED\"", [])])]]]
}

test_an_empty_first_list_a_for_line_tolerates_skips_only_the_sentences_that_read_it if {
	line := "every commits, if any, as c, some approvers as ap"
	approved := [{"u": "ada", "state": "APPROVED"}]
	[row[1] | some row in _for_rows({"for": line, "assert": "c.author is ap.u"}, [{"id": 1, "approvers": [{"u": "ada"}], "commits": []}, {"id": 2, "commits": []}, {"id": 3, "approvers": [], "commits": []}], {})] == ["satisfied", "satisfied", "satisfied"]
	[[row[0], row[1]] | some row in _for_rows({"for": line, "assert": ["ap.state is \"APPROVED\"", "c.author is ap.u"]}, [{"id": 1, "approvers": approved, "commits": []}, {"id": 2, "approvers": approved}, {"id": 3, "approvers": approved, "commits": null}, {"id": 4, "approvers": approved, "commits": "s"}, {"id": 5, "commits": []}], {})] == [[1, "satisfied"], [2, "absent"], [3, "null"], [4, "unusable"], [5, "absent"]]
	_said_rows({"for": "every commits, if any, as c, every c.files as f", "assert": ["f.n is 1", "z is 1"]}, [{"id": 1, "commits": [], "z": 3}]) == [[1, "value", "z is 3", [_assertion("z is 1", "value", ["$policy:/requirements/s/checks/c/assert/1"], [_seen("z", 3, ["/things/0/z"], "usable")], "z is 3", [])]]]
}

test_an_empty_list_a_one_item_for_line_tolerates_still_runs_the_sentences_that_dont_read_it if {
	things := [{"id": 1, "xs": [], "z": 3}, {"id": 2, "xs": [], "z": 1}, {"id": 3, "z": 3}]
	every line in ["every xs, if any, as m", "every xs whose k is 1, if any, as m"] {
		_said_rows({"for": line, "assert": ["m.v is 1", "z is 1"]}, things) == [[1, "value", "z is 3", [_assertion("z is 1", "value", ["$policy:/requirements/s/checks/c/assert/1"], [_seen("z", 3, ["/things/0/z"], "usable")], "z is 3", [])]], [2, "satisfied", null, []], [3, "absent", "z is 3; xs is missing", [_assertion("z is 1", "value", ["$policy:/requirements/s/checks/c/assert/1"], [_seen("z", 3, ["/things/2/z"], "usable")], "z is 3", []), _list("xs", "absent", [_seen("xs", null, ["/things/2"], "absent")], "xs is missing")]]]
	}
	_said_rows({"for": "every xs whose k is 1, if any, as m", "assert": ["m.v is 1", "z is 1"]}, [{"id": 1, "xs": [{"k": 2}], "z": 3}]) == [[1, "value", "z is 3", [_assertion("z is 1", "value", ["$policy:/requirements/s/checks/c/assert/1"], [_seen("z", 3, ["/things/0/z"], "usable")], "z is 3", [])]]]
	[row[1] | some row in _for_rows({"for": "every xs, if any, as m", "assert": "m.v is 1"}, [things[0]], {})] == ["satisfied"]
	_said_rows({"for": "every xs, if any, as m", "assert": ["w exists", "y is at least 1", "z is 1"]}, [{"id": 1, "xs": [], "z": 3, "y": "s"}]) == [[1, "unusable", "y is \"s\", which isn't a number; w is missing; z is 3", [_assertion("w exists", "value", ["$policy:/requirements/s/checks/c/assert/0"], [_seen("w", null, ["/things/0"], "absent")], "w is missing", []), _assertion("y is at least 1", "unusable", ["$policy:/requirements/s/checks/c/assert/1"], [_seen("y", "s", ["/things/0/y"], "unusable")], "y is \"s\", which isn't a number", []), _assertion("z is 1", "value", ["$policy:/requirements/s/checks/c/assert/2"], [_seen("z", 3, ["/things/0/z"], "usable")], "z is 3", [])]]]
}

test_a_for_line_can_walk_a_param if {
	check := {"for": "some $params.allowed as ok", "assert": "k equals ok"}
	rows := _for_rows(check, [{"id": 1, "k": "a"}, {"id": 2, "k": "z"}], {"allowed": ["a", "b"]})
	[row[1] | some row in rows] == ["satisfied", "value"]
	rows[1][3] == [_seen("$params.allowed[]", ["a", "b"], ["$params:/allowed/0", "$params:/allowed/1"], "usable"), _seen("k", "z", ["/things/1/k"], "usable")]
	[row[1] | some row in _for_rows(check, [{"id": 1, "k": "a"}], {})] == ["absent"]
}

test_a_for_line_on_a_subject_that_isnt_an_object_fails_like_any_path_does if {
	[[row[1], row[2], row[3]] | some row in _for_rows({"for": "every xs as x", "assert": "x is 1"}, ["s"], {})] == [["not_an_object", [_list("xs", "not_an_object", [], "thing is \"s\", which isn't an object")], []]]
}

test_a_for_list_whose_named_by_cant_be_read_fails_with_its_cause_and_puts_the_key_on_the_row if {
	check := {"for": "every m named by $params.k as x", "assert": "x is 1"}
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {}) == [[1, "absent", [], [_seen("m named by $params.k", [], [], "absent"), _seen("$params.k", null, ["$params:"], "absent")]]]
	_for_rows(check, [{"id": 1, "m": {"a": [1]}}], {"k": "a"}) == [[1, "satisfied", [], [{"name": "m named by $params.k[]", "value": [1], "locations": ["/things/0/m/a/0"]}]]]
	inner := {"for": "every xs as x, every m named by $params.k as y", "assert": "y is 1"}
	_for_rows(inner, [{"id": 1, "xs": [1], "m": {"a": [1]}}], {}) == [[1, "absent", [], [_seen("m named by $params.k", [], [], "absent"), _seen("xs[]", [1], ["/things/0/xs/0"], "usable"), _seen("$params.k", null, ["$params:"], "absent")]]]
}

test_a_for_line_whose_param_cant_be_used_fails_as_unusable_and_keeps_its_inputs if {
	rows := _for_rows({"for": "every xs as x", "assert": "x is one of $params.l"}, [{"id": 1, "xs": [1]}, "s"], {"l": "text"})
	rows == [[1, "unusable", [_assertion("x is in $params.l", "unusable", ["$policy:/requirements/s/checks/c/assert"], [_seen("$params.l", "text", ["$params:/l"], "unusable")], "$params.l is \"text\", which isn't a list", [])], [_seen("$params.l", "text", ["$params:/l"], "unusable"), _seen("xs[]", [1], ["/things/0/xs/0"], "usable")]], ["s", "unusable", [_assertion("x is in $params.l", "unusable", ["$policy:/requirements/s/checks/c/assert"], [_seen("$params.l", "text", ["$params:/l"], "unusable")], "$params.l is \"text\", which isn't a list", [])], [_seen("$params.l", "text", ["$params:/l"], "unusable"), _seen("xs", [], [], "unusable")]]]
	[row[1] | some row in _for_rows({"for": "every xs whose x is one of $params.l as x", "assert": "x is 1"}, [{"id": 1, "xs": [{"x": 1}]}], {"l": "text"})] == ["unusable"]
	[row[1] | some row in _for_rows({"for": "every xs whose x is one of $params.l as x", "assert": "x is 1"}, [{"id": 1, "xs": [1]}], {"l": "text"})] == ["unusable"]
}

test_an_every_under_a_for_line_shows_its_list_as_a_one_line_every_does if {
	rows := _for_rows({"for": "every prs as pr", "assert": "every cs.s is true"}, [{"id": 1, "prs": [{"n": 1}], "cs": [{"s": true}, {"s": false}]}], {})
	rows[0][3] == [_seen("cs[].s", [true, false], ["/things/0/cs/0/s", "/things/0/cs/1/s"], "usable"), _seen("prs[]", [{"n": 1}], ["/things/0/prs/0"], "usable")]
}

test_a_for_line_on_a_subject_that_isnt_an_object_fails_when_either_path_starts_at_the_subject if {
	[[row[1], row[3]] | some row in _for_rows({"for": "every $params.l as l, some xs as x", "assert": "x is l"}, ["s"], {"l": [1]})] == [["not_an_object", []]]
}

test_counts_work_in_and_lists_and_under_a_for_line_with_its_names if {
	[row[1] | some row in _tally_rows({"assert": ["count of findings is 3", "sum of stages.usd is 0.75"]}, [_review], {})] == ["satisfied"]
	things := [{"id": 1, "ps": ["a"], "prs": [{"r": [1, 2]}, {"r": [1]}]}, {"id": 2, "ps": ["a"], "prs": [{"r": [1, 2]}]}]
	rows := _tally_rows({"for": "every prs as pr", "assert": ["count of ps is 1", "count of pr.r is at least 2"]}, things, {})
	[[row[0], row[1]] | some row in rows] == [[1, "value"], [2, "satisfied"]]
	rows[1][2] == [{"name": "count of ps", "value": 1, "locations": ["/things/1/ps/0"]}, {"name": "prs[]", "value": [{"r": [1, 2]}], "locations": ["/things/1/prs/0"]}, {"name": "ps[]", "value": ["a"], "locations": ["/things/1/ps/0"]}]
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "count of pr.r whose u does not equal pr.a is 2"}, [{"id": 1, "prs": [{"a": "x", "r": [{"u": "x"}, {"u": "y"}, {"u": "z"}]}]}], {})] == ["satisfied"]
}

test_plus_under_a_for_line_reads_the_names if {
	[row[1] | some row in _tally_rows({"for": "every prs as pr", "assert": "pr.a plus count of pr.r is 3"}, [{"id": 1, "prs": [{"a": 1, "r": [1, 2]}]}, {"id": 2, "prs": [{"a": 2, "r": [1, 2]}]}], {})] == ["satisfied", "value"]
}

test_a_count_under_a_for_line_lists_its_list_when_its_whose_reads_the_alias if {
	doc := object.union(_owner_doc, {"artifact": {"people": [{"r": "ann"}, {"r": "bob"}]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of artifact.people whose r is c.author is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.people[]", "commits[]"]]
}

test_a_count_under_a_for_line_lists_its_list_and_its_number_when_they_dont_change_per_item if {
	doc := object.union(_owner_doc, {"artifact": {"tags": ["t"]}})
	checks := {"c": {"for": "every commits as c", "assert": "count of artifact.tags is at least 1"}}
	rep := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {})
	[[i.name | some i in r.inputs] | some r in rep.results; r.check == "c"] == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

_add_rows(assert) := [[i.name | some i in r.inputs] |
	some r in ergo.report(
		{"artifacts": [{"name": "a1", "tags": [{"x": "bob"}], "pull_requests": [{"id": 1, "commits": [{"author": "bob", "revs": [1]}]}]}]},
		{"ergo_spec": ergo._spec, "subjects": {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.pull_requests", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": "every commits as c", "assert": assert}}}}},
		{},
	).results
	r.check == "c"
]

test_an_add_under_a_for_line_lists_the_number_of_the_operand_that_doesnt_read_the_alias if {
	_add_rows("count of artifact.tags plus count of artifact.tags whose x is c.author is at least 1") == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

test_an_add_under_a_for_line_lists_the_number_of_the_second_operand_when_the_first_reads_the_alias_in_its_path if {
	_add_rows("count of c.revs plus count of artifact.tags is at least 1") == [["artifact.tags[]", "commits[]", "count of artifact.tags"]]
}

test_a_for_line_walk_named_by_the_subject_lists_the_key_and_named_by_the_alias_lists_the_part_before_the_name if {
	checks := {
		"item": {"for": "every files as f", "assert": "some commits.author is artifact.atts named by k.owner"},
		"alias": {"for": "every files as f", "assert": "some commits.author is artifact.atts named by f.k.owner"},
	}
	_atts_rows(checks, {}) == {"item": ["artifact.atts named by k.owner", "commits[].author", "files[]", "k"], "alias": ["artifact.atts", "commits[].author", "files[]"]}
}

test_named_by_a_name_from_the_for_line_reads_the_key_each_item_names if {
	check := {"for": "every dispatched as persona", "assert": `shas named by persona matches "^[0-9a-f]{40}$"`}
	rows := _for_rows(check, _persona_doc.things, {})
	rows[0] == [1, "satisfied", [], [_in("dispatched[]", ["security", "style"], ["/things/0/dispatched/0", "/things/0/dispatched/1"]), _in("shas", {"security": "3f2a000000000000000000000000000000000000", "style": "9c1b000000000000000000000000000000000000"}, ["/things/0/shas"])]]
	rows[1] == [2, "unusable", [_assertion("shas named by persona matches \"^[0-9a-f]{40}$\"", "unusable", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 1 of dispatched", "value", "security", ["/things/1/dispatched/0"], [_seen("shas named by persona", "x", ["/things/1/shas/security"], "usable")], "shas named by persona is \"x\"", []), _item("item 2 of dispatched", "absent", "perf", ["/things/1/dispatched/1"], [_seen("shas named by persona", null, ["/things/1/shas"], "absent")], "shas named by persona is missing", []), _item("item 3 of dispatched", "unusable", 5, ["/things/1/dispatched/2"], [_seen("shas named by persona", null, ["/things/1/shas"], "unusable")], "persona is 5, which isn't text", [])])], [_seen("dispatched[]", ["security", "perf", 5], ["/things/1/dispatched/0", "/things/1/dispatched/1", "/things/1/dispatched/2"], "usable"), _seen("shas", {"security": "x"}, ["/things/1/shas"], "usable")]]
}

test_named_by_a_field_on_a_for_line_reads_the_subject_and_a_for_name_hides_a_field_with_the_same_name if {
	things := [{"id": 1, "k": "a", "xs": {"a": [1], "b": [2]}, "items": [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}]}]
	_for_rows({"for": "every xs named by k as x", "assert": "x is 1"}, things, {}) == [[1, "satisfied", [], [_in("k", "a", ["/things/0/k"]), _in("xs named by k[]", [1], ["/things/0/xs/a/0"])]]]
	_for_rows({"for": "every items as i", "assert": "i.n is at least $params.min named by k"}, things, {"min": {"a": 2, "b": 2}})[0][3] == [_seen("$params.min named by k", 2, ["$params:/min/a"], "usable"), _seen("items[]", [{"kind": "a", "n": 3}, {"kind": "b", "n": 1}], ["/things/0/items/0", "/things/0/items/1"], "usable"), _seen("k", "a", ["/things/0/k"], "usable")]
	_for_rows({"for": "every items as k", "assert": "$params.min named by k exists"}, [{"id": 1, "k": "b", "items": ["a"]}], {"min": {"a": 1}})[0][1] == "satisfied"
	_for_rows({"for": "every xs whose v named by k is 1 as x", "assert": "x exists"}, [{"id": 1, "xs": [{"k": "a", "v": {"a": 1}}]}], {})[0][1] == "satisfied"
}

test_a_root_on_the_for_line_comes_before_an_empty_list_unless_if_any if {
	checks := {"c": {"for": "every xs whose v is in thing.z as m", "assert": "m.v is 1"}, "any": {"for": "every xs whose v is in thing.z, if any, as m", "assert": "m.v is 1"}}
	_for_sentence_root_rows(checks, {"xs": []}) == {"c": ["absent", "thing.z is missing; xs is []"], "any": ["absent", "thing.z is missing"]}
	_for_sentence_root_rows(checks, {"xs": [], "z": null}) == {"c": ["null", "thing.z is null; xs is []"], "any": ["null", "thing.z is null"]}
	_for_sentence_root_rows(checks, {"xs": [], "z": "s"}) == {"c": ["unusable", "thing.z is \"s\", which isn't a list; xs is []"], "any": ["unusable", "thing.z is \"s\", which isn't a list"]}
}

test_elapsed_works_in_each_line_of_a_list_and_under_a_for_line if {
	_elapsed_first({"assert": ["days elapsed from p to q is 1", "hours elapsed from p to q is 24"]}, [{"id": 1, "p": 0, "q": 86400}], {}) == [true, "satisfied"]
	fors := _elapsed_rows({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is less than $params.max"}, [{"id": 1, "ps": [{"p": 0, "q": 86400}, {"p": 0, "q": 86400}]}, {"id": 2, "ps": [{"p": 0, "q": 864000}]}], {"max": 2})
	[[r[0], r[1]] | some r in fors] == [[1, true], [2, false]]
	_elapsed_cause({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is 1"}, {"id": 1, "ps": [{"p": 0}]}, {}) == "absent"
	_elapsed_cause({"for": "every ps as entry", "assert": "days elapsed from entry.p to entry.q is 1"}, {"id": 1, "ps": [{"p": 1, "q": 0}]}, {}) == "value"
}

test_an_elapsed_time_in_a_whose_goes_on_a_for_line_too if {
	doc := [{"id": 1, "xs": [{"n": 1, "p": 0, "q": 86400}, {"n": 2, "p": 0, "q": 172800}]}]
	_elapsed_first({"for": "every xs whose days elapsed from p to q is 1 as x", "assert": "x.n is 1"}, doc, {}) == [true, "satisfied"]
	_elapsed_first({"for": "every xs whose days elapsed from p to q is 2 as x", "assert": "x.n is 1"}, doc, {}) == [false, "value"]
}

test_the_nested_failed_items_of_a_second_for_line_keep_the_dot_of_an_own_field if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"round": {"from": "rounds", "identified_by": "id"}},
		"requirements": {"r": {"subject": "round", "checks": {"c": {"for": "every items as y, every .y.zs as z", "assert": "z is at least 1"}}}},
	}
	rep := ergo.report({"rounds": [{"id": "r1", "y": {"zs": [5, 0]}, "items": [{"id": "i1"}]}]}, policy, {})
	[r.failures | some r in rep.results; r.check == "c"] == [[_assertion("z is at least 1", "value", ["$policy:/requirements/r/checks/c/assert"], [], "", [_item("item 1 of items", "value", {"id": "i1"}, ["/rounds/0/items/0"], [], "", [_item("item 2 of .y.zs", "value", 0, ["/rounds/0/y/zs/1"], [_seen("z", 0, ["/rounds/0/y/zs/1"], "usable")], "item 2 of .y.zs is 0", [])])])]]
}

test_an_alias_works_on_the_subject_in_a_for_line_and_not_on_its_items if {
	has := {"cov": "dd.b", "lst": "dd.items"}
	checks := {
		"c": {"for": "every lst as entry", "assert": ["entry.x is cov.x", "cov.s exists"]},
		"d": {"for": "some lst whose y is 2 as entry", "assert": "entry.x is 1"},
		"e": {"for": "every lst as entry, every entry.sub as s", "assert": "s is cov.x"},
	}
	d := {"b": {"x": 1, "s": "a"}, "items": [{"x": 1, "y": 2, "sub": [1]}, {"x": 1, "y": 3, "sub": [1, 1]}]}
	rep := _parts_report(has, checks, d)
	every c in ["c", "d", "e"] {
		_parts_row(rep, c).passed
	}
	rep.requirements.r.checks.c.expression == "for every lst as entry: entry.x equals cov.x and cov.s exists"
	_untagged(_parts_row(rep, "c").inputs) == [{"name": "cov.s", "value": "a", "locations": ["/trail/dd/b/s"]}, {"name": "cov.x", "value": 1, "locations": ["/trail/dd/b/x"]}, {"name": "lst[]", "value": [{"sub": [1], "x": 1, "y": 2}, {"sub": [1, 1], "x": 1, "y": 3}], "locations": ["/trail/dd/items/0", "/trail/dd/items/1"]}]
}

test_a_part_gives_the_rows_of_its_full_path_in_every_scenario_in_the_for_line_checks if _swap_differences("fors") == set()

test_a_walk_and_a_count_and_a_for_line_tag_the_lists_they_read_through_a_part if {
	checks := {
		"every": "every lst.x is at least 1",
		"count": "count of lst is 2",
		"for": {"for": "every lst as entry", "assert": "entry.x is at least 1"},
	}
	rep := _parts_report(_tag_has, checks, _tag_doc)
	every c in ["every", "count", "for"] {
		every i in _parts_row(rep, c).inputs {
			i.part == {"id": null, "name": "lst"}
		}
	}
}

test_a_for_item_that_picks_with_brackets_still_lists_the_line_s_other_problems if {
	_sentence_problems({"assert": "x exists", "for": "every t as x, t as x"}) == [
		`for: an item starts with "every", "some" or a position, like "last of"`,
		"for: x is given twice",
	]
	_sentence_problems({"assert": "x exists", "for": "every t as x, t[0] as x"}) == [
		`for: an item starts with "every", "some" or a position, like "last of"`,
		"for: x is given twice",
	]
}

test_a_for_line_picks_an_item_by_its_position_sorted_by_a_field if {
	_picked_author("first of commits sorted by timestamp", [3, 1, 2]) == "grace"
	_picked_author("item 2 of commits sorted by timestamp", [3, 1, 2]) == "linus"
	_picked_author("last of commits sorted by timestamp", [3, 1, 2]) == "ada"
	_picked_author("item 2 from last of commits sorted by timestamp", [3, 1, 2]) == "linus"
}

test_a_picked_item_and_a_walk_share_a_for_line if {
	check := {
		"for": "some approvers as approver, last of commits sorted by timestamp as last_commit",
		"assert": "approver.username does not equal last_commit.author_username",
	}
	commits := [{"author_username": "ada", "timestamp": 2}, {"author_username": "grace", "timestamp": 1}]
	[row[1] | some row in _for_rows(
		check, [
			{"id": 1, "approvers": [{"username": "grace"}], "commits": commits},
			{"id": 2, "approvers": [{"username": "ada"}], "commits": commits},
		],
		{},
	)] == ["satisfied", "value"]
	reverse := {
		"for": "last of commits sorted by timestamp as last_commit, some approvers as approver",
		"assert": "approver.username does not equal last_commit.author_username",
	}
	[row[1] | some row in _for_rows(
		reverse, [
			{"id": 1, "approvers": [{"username": "grace"}], "commits": commits},
			{"id": 2, "approvers": [{"username": "ada"}], "commits": commits},
		],
		{},
	)] == ["satisfied", "value"]
}

test_a_for_item_that_failed_shows_the_item_as_its_value if {
	rows := _for_rows({"for": "every xs as x", "assert": "x.k is 1"}, [{"id": 1, "xs": [{"k": 1}, {"k": 2}]}], {})
	rows[0][2] == [_assertion("x.k is 1", "value", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 2 of xs", "value", {"k": 2}, ["/things/0/xs/1"], [_seen("x.k", 2, ["/things/0/xs/1/k"], "usable")], "x.k is 2", [])])]
}

test_a_for_item_whose_path_ends_at_a_field_shows_what_its_alias_stands_for_as_its_value if {
	check := {"for": "every prs.author as who", "assert": `who is "ann"`}
	rows := _for_rows(check, [{"id": 1, "prs": [{"author": "ann"}, {"author": "bob"}]}], {})
	rows[0][2] == [_assertion("who is \"ann\"", "value", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 2 of prs", "value", "bob", ["/things/0/prs/1/author"], [_seen("who", "bob", ["/things/0/prs/1/author"], "usable")], "item 2 of prs is \"bob\"", [])])]
}

test_a_plus_under_a_for_line_whose_term_is_missing_still_shows_the_sum_and_the_term_as_null if {
	check := {"for": "every xs as x", "assert": ["x.a is 1", "n plus 2 is 3"]}
	rows := [r | some r in ergo.report({"things": [{"id": 1, "xs": [{"a": 1}]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"]
	[rows[0].cause, rows[0].inputs, rows[0].failures] == ["absent", [_seen("n", null, ["/things/0"], "absent"), _in("n plus 2", null, ["/things/0"]), _seen("xs[]", [{"a": 1}], ["/things/0/xs/0"], "usable")], [_assertion("n plus 2 is 3", "absent", ["$policy:/requirements/s/checks/c/assert/1"], [_in("n plus 2", null, ["/things/0"]), _seen("n", null, ["/things/0"], "absent")], "n is missing", [])]]
}

test_a_plus_under_a_for_line_shows_the_sum_and_each_term if {
	check := {"for": "every xs as x", "assert": ["x.a is 1", "n plus 2 is 3"]}
	[[r.cause, r.inputs] | some r in ergo.report({"things": [{"id": 1, "n": 1, "xs": [{"a": 1}]}]}, _sentence_policy({"c": check}), {}).results; r.check == "c"] == [["satisfied", [
		{"name": "n", "value": 1, "locations": ["/things/0/n"]},
		{"name": "n plus 2", "value": 3, "locations": ["/things/0/n"]},
		{"name": "xs[]", "value": [{"a": 1}], "locations": ["/things/0/xs/0"]},
	]]]
}

test_a_for_line_row_gives_the_location_of_each_item_and_of_the_item_that_failed if {
	rows := [r | some r in ergo.report({"things": [{"id": "t1", "prs": [{"a": 1}, {"a": 2}]}]}, _sentence_policy({"c": {"for": "every prs as pr", "assert": "pr.a is 1"}}), {}).results; r.check == "c"]
	count(rows) == 1
	rows[0].inputs == [_seen("prs[]", [{"a": 1}, {"a": 2}], ["/things/0/prs/0", "/things/0/prs/1"], "usable")]
	rows[0].failures == [_assertion("pr.a is 1", "value", ["$policy:/requirements/s/checks/c/assert"], [], "", [_item("item 2 of prs", "value", {"a": 2}, ["/things/0/prs/1"], [_seen("pr.a", 2, ["/things/0/prs/1/a"], "usable")], "pr.a is 2", [])])]
}

test_a_failed_item_of_a_nested_for_line_points_at_the_value_it_read if {
	check := {"for": "every prs.meta as m, every m.commits as c", "assert": "c.signed is true"}
	rows := _for_rows(check, [{"id": 1, "prs": [{"meta": {"commits": "zz"}, "commits": [{"signed": true}]}]}], {})
	rows[0][2] == [_item("item 1 of prs", "unusable", {"commits": "zz"}, ["/things/0/prs/0/meta"], [], "", [_list("m.commits", "unusable", [_seen("m.commits", "zz", ["/things/0/prs/0/meta/commits"], "unusable")], "m.commits is \"zz\", which isn't a list or an object")])]
	absent := _for_rows(check, [{"id": 1, "prs": [{"meta": {"n": 1}, "commits": [{"signed": true}]}, {"meta": {"commits": []}}]}], {})
	absent[0][2] == [_item("item 1 of prs", "absent", {"n": 1}, ["/things/0/prs/0/meta"], [], "", [_list("m.commits", "absent", [_seen("m.commits", null, ["/things/0/prs/0/meta"], "absent")], "m.commits is missing")]), _item("item 2 of prs", "value", {"commits": []}, ["/things/0/prs/1/meta"], [], "", [_list("m.commits", "value", [_seen("m.commits", [], ["/things/0/prs/1/meta/commits"], "usable")], "m.commits is []")])]
}

test_the_subjects_name_after_a_for_line_is_still_the_subject_and_not_the_item if {
	doc := {"xs": [{"id": "a", "l": [1, 2]}]}
	rows := _subject_rows(doc, "every xs", {"for": "every l as e", "assert": ["s is an object", "e is 1"]}, {})
	rows[0][1] == false
	_seen("s", {"id": "a", "l": [1, 2]}, ["/xs/0"], "usable") in rows[0][3]
	_subject_report(doc, "every xs", {"c": {"for": "every l as e", "assert": ["s is an object", "e is 1"]}}, {}).requirements.r.checks.c.expression == "for every l as e: s is an object and e is 1"
}

test_a_for_alias_cannot_be_called_like_the_subject if {
	_subject_problems("every xs", {"c": {"for": "every xs as s", "assert": "s is 1"}}) == ["s can't be an alias: it's a subject's name"]
}

test_a_position_on_the_subjects_name_works_on_the_right_and_fails_in_a_for_line_over_a_list_subject if {
	rows := _subject_rows({"xs": [[1, 2]]}, "every xs", "x is first of s", {})
	rows[0][1] == false
	_subject_rows({"xs": [[1, 2]]}, "every xs", {"for": "last of s as e", "assert": "e is 2"}, {})[0][2] == "not_an_object"
}

test_a_for_alias_that_clashes_with_nothing_reads_the_item if {
	has := {"x": "k1.k2.k3"}
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.x.z is 7"}) == [["satisfied", true]]
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.v is 1"}) == [["value", false]]
	_clash_rows(has, {}, {"for": "every xs as entry", "assert": "entry.b.x.z is 1"}) == [["value", false]]
}

_clash_narrowed := {
	"b": {"from": "bs", "identified_by": "id", "has": {"part": "k1"}},
	"b2": {"from": "b whose id exists"},
	"kid2": {"from": "every b2.kids", "identified_by": "id"},
}

_clash_narrowed_problems(subject, check) := [i.value | some r in ergo.report(_clash_doc, {"ergo_spec": ergo._spec, "subjects": _clash_narrowed, "requirements": {"r": {"subject": subject, "checks": {"c": check}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

test_a_for_alias_named_like_a_part_kept_from_a_narrowed_subject_names_the_subject_that_declares_it if {
	_clash_narrowed_problems("b2", {"for": "every kids as part", "assert": "part.id exists"}) == [["part can't be an alias: it's a part of b"]]
	_clash_narrowed_problems("kid2", {"for": "every xs as part", "assert": "part.v is 1"}) == [["part can't be an alias: it's a part of b"]]
}

test_a_for_alias_named_like_a_part_of_a_subject_with_a_space_in_its_name_quotes_the_name if {
	subjects := {"pull request": {"from": "bs", "identified_by": "id", "has": {"pull": "k1"}}, "kid": {"from": `every "pull request".kids`, "identified_by": "id"}}
	rep := ergo.report(_clash_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "kid", "checks": {"c": {"for": "every xs as pull", "assert": "pull.v is 1"}}}}}, {})
	[i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"] == [["pull can't be an alias: it's a part of \"pull request\""]]
}

test_a_for_line_item_keeps_its_alias_when_the_right_side_reads_a_field_called_like_it if {
	rows := _dot_plain_rows({"for": "every items as p", "assert": "p.name is in .p.name"}, {"repos": [{"id": "r", "p": [], "items": [{"name": "a"}]}]})
	rows[0].message == "item 1 of items: p.name is \"a\", and .p is []"
	rows[0].names == [".p[].name", "items[]"]
}

test_a_for_line_keeps_the_dot_of_a_right_side_when_an_item_of_the_field_is_not_an_object if {
	rows := _dot_plain_rows({"for": "every items as p", "assert": "p.name is in .p.name"}, {"repos": [{"id": "r", "p": ["t"], "items": [{"name": "a"}]}]})
	rows[0].message == "item 1 of items: item 1 of .p is \"t\", which isn't an object"
}

test_a_for_line_that_reads_params_that_are_not_an_object_names_them if {
	every case in [[3, "3"], ["s", "\"s\""], [true, "true"], [false, "false"]] {
		object.filter(params_for_line_messages, ["c", "d", "e"]) == {
			"c": concat("", ["$params is ", case[1], ", which isn't an object"]),
			"d": concat("", ["$params is ", case[1], ", which isn't an object"]),
			"e": concat("", ["$params is ", case[1], ", which isn't an object"]),
		} with data.params as case[0]
	}
}

test_a_for_line_that_picks_from_a_list_subject_fails_as_not_an_object_and_one_that_walks_it_reads_each_item if {
	doc := {"xs": [[1, 2], [3]]}
	walked := _subject_rows(doc, "every xs", {"for": "some s as e", "assert": "e is 1"}, {})
	[[r[1], r[2]] | some r in walked] == [[true, "satisfied"], [false, "value"]]
	every line in ["last of s as e", "first of s as e"] {
		rows := _subject_rows(doc, "every xs", {"for": line, "assert": "e is 1"}, {})
		[[r[1], r[2]] | some r in rows] == [[false, "not_an_object"], [false, "not_an_object"]]
	}
	rep := _subject_report(doc, "every xs", {"c": {"for": "last of s as e", "assert": "e is 1"}}, {})
	[r.message | some r in rep.results; r.check == "c"] == ["s is [1, 2], which isn't an object", "s is [3], which isn't an object"]
	object_rows := _subject_rows({"xs": [{"id": "a"}]}, "every xs", {"for": "last of s as e", "assert": "e is 1"}, {})
	[[r[1], r[2]] | some r in object_rows] == [[false, "unusable"]]
}

test_a_for_line_reads_a_bare_params_once_before_any_item_whatever_the_list_holds if {
	least := {"c": {"for": "every xs as m", "assert": "m.v is at least $params"}}
	_root_rows(least, {"id": "p", "xs": []}, null).c == ["absent", "$params is missing; xs is []"]
	_root_rows(least, {"id": "p"}, null).c == ["absent", "$params is missing; xs is missing"]
	_root_rows(least, {"id": "p", "xs": [{"v": 1}, {"v": 2}]}, null).c == ["absent", "$params is missing"]
	_root_rows(least, {"id": "p", "xs": []}, {}).c == ["unusable", "$params is {}, which isn't a number; xs is []"]
	_root_rows(least, {"id": "p", "xs": [{"v": 1}, {"v": 2}]}, {}).c == ["unusable", "$params is {}, which isn't a number"]
	_root_rows(least, {"id": "p", "xs": []}, "s").c == ["unusable", "$params is \"s\", which isn't an object"]
}

test_a_for_line_compares_a_bare_params_before_any_item_and_names_the_empty_list_after_it if {
	is_3 := {"c": {"for": "every xs as m", "assert": "$params is 3"}}
	_root_rows(is_3, {"id": "p", "xs": []}, null).c == ["absent", "$params is missing; xs is []"]
	_root_rows(is_3, {"id": "p", "xs": [{"v": 1}]}, null).c == ["absent", "$params is missing"]
	_root_rows(is_3, {"id": "p", "xs": []}, {}).c == ["unusable", "$params is {}, which isn't a number; xs is []"]
	_root_rows(is_3, {"id": "p", "xs": []}, 3).c == ["unusable", "$params is 3, which isn't an object"]
}

test_a_for_line_reads_a_bare_input_before_any_item_and_names_the_empty_list_after_it if {
	least := {"c": {"for": "every xs as m", "assert": "m.v is at least $input"}}
	_root_rows(least, {"id": "p", "xs": []}, {}).c == ["unusable", "$input is {\"prs\": [{\"id\": \"p\", \"xs\": []}]}, which isn't a number; xs is []"]
	_root_rows(least, {"id": "p", "xs": [{"v": 1}]}, {}).c == ["unusable", "$input is {\"prs\": [{\"id\": \"p\", \"xs\": [{\"v\": 1}]}]}, which isn't a number"]
}

test_a_for_check_that_does_not_read_params_but_passes_is_unusable_with_its_expression_when_params_is_not_an_object if {
	doc := {"prs": [{"id": "p0", "z": 1, "xs": [{"v": 1}]}]}
	every params in [3, "s", []] {
		_params_not_object_rows(doc, params).plain == ["unusable", "for every xs as m: z is 1 is false", [_assertion("z is 1", "unusable", ["$policy:/requirements/r/checks/plain/assert"], [_seen("z", 1, ["/prs/0/z"], "usable")], "for every xs as m: z is 1 is false", [])]]
	}
}

test_a_for_check_with_params_missing_or_null_reads_it_as_missing_and_names_the_problem_once_on_the_assertion if {
	every params in [null, {}] {
		rows := _params_not_object_rows(_params_not_object_doc, params)
		rows.least_z == ["unusable", "z is \"s\", which isn't a number", [_assertion("m.v is at least z", "unusable", ["$policy:/requirements/r/checks/least_z/assert"], [_seen("z", "s", ["/prs/0/z"], "unusable")], "z is \"s\", which isn't a number", [])]]
		rows.least_q == ["absent", "$params.q is missing", [_assertion("m.v is at least $params.q", "absent", ["$policy:/requirements/r/checks/least_q/assert"], [_seen("$params.q", null, ["$params:"], "absent")], "$params.q is missing", [])]]
		rows.in_q == ["absent", "$params.q is missing", [_assertion("m.v is in $params.q", "absent", ["$policy:/requirements/r/checks/in_q/assert"], [_seen("$params.q", null, ["$params:"], "absent")], "$params.q is missing", [])]]
	}
}

test_params_that_arent_an_object_make_a_for_line_unusable_even_when_its_items_arent_objects if {
	every params in [[], 3, "s", true] {
		rows := _item_rows(_params_cause_policy, {"prs": [{"id": "p0", "xs": ["s", {"v": "x"}]}]}, params)
		rows.plain == ["unusable", "item 1 of xs is \"s\", which isn't an object; item 2 of xs: m.v is \"x\", which isn't a number"]
		rows.some[0] == "unusable"
		rows.reads[0] == "unusable"
		rows.whose[0] == "unusable"
		nulls := _item_rows(_params_cause_policy, {"prs": [{"id": "p0", "xs": [null]}]}, params)
		nulls.plain == ["unusable", "item 1 of xs is null, which isn't an object"]
		nulls.reads[0] == "unusable"
	}
}

test_params_that_arent_an_object_name_themselves_in_a_for_line_that_reads_them_whatever_its_items_are if {
	rows := _item_rows(_params_cause_policy, {"prs": [{"id": "p0", "xs": [null, "s"]}]}, 3)
	rows.reads == ["unusable", "$params is 3, which isn't an object"]
	rows.whose == ["unusable", "$params is 3, which isn't an object"]
}

test_a_part_that_holds_a_list_is_walked_by_a_count_of_whose_under_a_for_line if {
	xs := [{"v": 1, "ys": [{"v": 1}]}]
	empty := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": [], "xs": xs}]}, {})
	empty == {"xs": ["value", "pl is []"], "ys": ["value", "pl is []"], "at_least": ["value", "pl is []"]}
	no_item := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": [], "xs": []}]}, {})
	no_item.ys == ["value", "pl is []; xs is []"]
	objects := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": [{"z": 1}], "xs": xs}]}, {})
	objects.xs == ["value", "count of xs whose v is in pl.z is 1"]
	objects.ys == ["value", "item 1 of xs: count of m.ys whose v is in pl.z is 1"]
	objects.at_least[0] == "satisfied"
}

test_a_part_that_is_an_object_with_a_list_still_works_in_a_count_of_whose_under_a_for_line if {
	rows := _item_rows(_count_part_policy, {"prs": [{"id": "p0", "c": {"z": [2]}, "xs": [{"v": 1, "ys": [{"v": 1}]}]}]}, {})
	rows.xs == ["satisfied", null]
	rows.at_least == ["satisfied", null]
}

test_host_data_cannot_turn_on_reading_walked_roots if {
	policy := {
		"ergo_spec": ergo._spec,
		"subjects": {"c": {"from": "cs", "identified_by": "id"}},
		"requirements": {"r": {"subject": "c", "checks": {"c": {"for": "every rows, if any, as r", "assert": "r.tags contains all of $params.os.name"}}}},
	}
	doc := {"cs": [{"id": "c1", "rows": [{"tags": ["bob"]}]}]}
	params := {"os": [{"name": "bob"}, {}]}
	plain := ergo.report(doc, policy, params)
	[[r.cause, r.message] | some r in plain.results; r.check == "c"] == [["absent", "item 2 of $params.os: name is missing"]]
	hosted := ergo.report(doc, policy, params) with data.ergo_walk_roots as true
	hosted == plain
}

_null_key_whose_row(check) := [[r.cause, r.message] |
	some r in ergo.report({"things": [{"id": "t", "m": {"a": "a"}, "rs": [{"v": "a"}, {"v": 4}]}], "k": null}, _sentence_policy({"c": check}), {}).results
	r.check == "c"
]

test_a_whose_key_from_the_input_that_is_null_is_named_once_and_the_worse_cause_of_an_item_wins if {
	_null_key_whose_row({"for": "every rs whose v is m named by $input.k as r", "assert": "r.v is 1"}) == [["absent", "$input.k is null; item 1 of rs: m is missing; item 2 of rs: m is missing"]]
	_null_key_whose_row({"for": "every rs whose zz is m named by $input.k as r", "assert": "r.v is 1"}) == [["absent", "$input.k is null; item 1 of rs: zz is missing; item 2 of rs: zz is missing"]]
}

test_a_second_list_item_that_fails_on_its_own_field_keeps_a_whose_key_that_isnt_text_in_each_item if {
	policy := _sentence_policy({"c": {"for": "every ws as w, every w.rs whose zz is m named by $params.k as r", "assert": "r.v exists"}})
	doc := {"things": [{"id": "t", "ws": [{"rs": [{"v": 1}, {"v": 2}]}]}]}
	[[r.cause, r.message] | some r in ergo.report(doc, policy, {"k": 3}).results; r.check == "c"] == [["unusable", "item 1 of ws: item 1 of w.rs: $params.k is 3, which isn't text; item 1 of ws: item 2 of w.rs: $params.k is 3, which isn't text"]]
	nulls := {"things": [{"id": "t", "ws": [{"rs": [{"v": 1}, {"zz": 2, "m": null}]}]}]}
	[[r.cause, r.message] | some r in ergo.report(nulls, policy, {"k": null}).results; r.check == "c"] == [["absent", "$params.k is null; item 1 of ws: item 1 of w.rs: zz is missing; item 1 of ws: item 2 of w.rs: m is null"]]
}

test_a_for_line_shows_three_items_after_a_sentence_that_doesnt_read_the_alias_and_never_counts_that_sentence if {
	checks := {"c": {"for": "every xs as x", "assert": ["x.v is 1", "z is 3"]}}
	_for_sentence_root_rows(checks, {"z": 2, "xs": [{"v": 2}, {"v": 2}, {"v": 2}, {"v": 2}, {"v": 2}]}) == {"c": ["value", "z is 2; item 1 of xs: x.v is 2; item 2 of xs: x.v is 2; item 3 of xs: x.v is 2; and 2 more"]}
	two := {"c": {"for": "every ws as w, every w.ys as y", "assert": ["y is 1", "w.n is 1", "z is 3"]}}
	_for_sentence_root_rows(two, {"z": 2, "ws": [{"n": 2, "ys": [1]}, {"n": 2, "ys": null}, {"n": 1}, {"n": 2}, {"n": 2}]}) == {"c": ["absent", "z is 2; item 1 of ws: w.n is 2; item 2 of ws: w.n is 2; item 2 of ws: w.ys is null; item 3 of ws: w.ys is missing; and 2 more"]}
}

test_a_second_whose_that_reads_a_list_input_key_through_an_alias_never_says_an_object_item_isnt_an_object if {
	doc := [{"id": "t", "k": "a", "rs": [{"m": {"a": "a"}}], "xs": [{"v": "a"}]}]
	policy := object.union(_sentence_policy({"c": {"for": "every rs as r, every xs whose v is r.m named by $input.k as x", "assert": "x.v is \"a\""}}), {"subjects": {"thing": {"from": "$input"}}})
	listed := `$input is [{"id": "t", "k": "a", "rs": [{"m": {"a": "a"}}], "xs": [{"v": "a"}]}], which isn't an object`
	[[r.cause, r.message] | some r in ergo.report(doc, policy, {}).results; r.check == "c"] == [["not_an_object", concat("", [listed, "; item 1 of rs: ", listed])]]
}

_for_said_beside_empty(line, xs) := [[r.cause, r.message] | some r in ergo.report({"things": [{"id": 1, "xs": xs}]}, _sentence_policy({"c": {"for": line, "assert": "m.v exists"}}), {"cs": []}).results; r.check == "c"]

test_a_for_line_whose_says_an_empty_list_on_the_right_then_the_list_or_each_item_as_a_null_list_does if {
	every line in ["every xs whose v is in $params.cs.name as m", "some xs whose v is in $params.cs.name as m"] {
		_for_said_beside_empty(line, []) == [["value", "$params.cs is []; xs is []"]]
		_for_said_beside_empty(line, [{"v": "a"}, {}]) == [["value", "$params.cs is []; item 2 of xs: v is missing"]]
		_for_said_beside_empty(line, [null]) == [["value", "$params.cs is []; item 1 of xs is null, which isn't an object"]]
	}
	_for_said_beside_empty("every xs whose v is in $params.cs.name, if any, as m", []) == [["value", "$params.cs is []"]]
	_for_said_beside_empty("every xs whose v is in $params.cs.name, if any, as m", [{"v": "a"}, {}]) == [["value", "$params.cs is []; item 2 of xs: v is missing"]]
}

test_a_for_lines_whose_leaves_an_empty_part_out_of_the_rows_inputs_as_a_null_part if {
	policy := _item_policy({"has": {"pl": "c"}}, {"every": {"for": "every xs whose v is in pl.z as m", "assert": "m.v is 1"}})
	every part in [[], null] {
		rows := [r | some r in ergo.report({"prs": [{"id": "p0", "c": part, "xs": [{"v": 1}]}]}, policy, {}).results; r.check == "every"]
		[i.name | some i in rows[0].inputs] == ["xs[]"]
	}
}

test_a_sentence_under_a_for_line_over_an_empty_list_lists_no_input_on_its_assertion_entry_for_an_empty_part_as_for_a_null_one if {
	policy := _item_policy({"has": {"pl": "c"}}, {"c": {"for": "every xs as m", "assert": "count of m.ys whose v is in pl.z is 0"}})
	every part in [[], null] {
		rows := [r | some r in ergo.report({"prs": [{"id": "p0", "c": part, "xs": []}]}, policy, {}).results; r.check == "c"]
		[[e.kind, [i.name | some i in e.inputs]] | some e in rows[0].failures] == [["assertion", []], ["list", ["xs"]]]
	}
}
