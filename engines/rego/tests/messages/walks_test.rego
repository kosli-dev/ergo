package ergo_test

import data.ergo
import rego.v1

test_message_of_a_passed_walk_has_no_parts if {
	ergo._m_fail_parts("satisfied", [], set()) == []
}

test_a_walk_says_its_items_in_list_order_in_the_order_of_its_failed_items_even_when_a_later_item_failed_on_a_read_outside_it if {
	check := ergo._s_written_check({"assert": "every xs whose tags contains $input.m named by key exists"})
	subj := {"xs": [null, {"key": "a", "tags": ["x"]}, {"tags": ["x"]}]}
	r := ergo._walk_row(check, subj) with data.ergo_document as {"m": {"a": "x"}}
	parts := ergo._walk_parts(check, subj, r, r) with data.ergo_document as {"m": {"a": "x"}}
	[p.text | some p in parts] == ["item 1 of xs is null, which isn't an object", "item 3 of xs: key is missing"]
	[f.item | some f in r.failed] == ["item 1 of xs", "item 3 of xs"]
}

test_a_clause_an_earlier_sentence_gave_is_left_out_but_a_quoted_value_is_one_clause if {
	ergo._m_said_new(["x is missing", "x is missing, and y is missing", "y is missing"]) == ["x is missing", "y is missing"]
	ergo._m_said_new(["x is \"a, and b\"", "x is \"a, and b\", and z is 1"]) == ["x is \"a, and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\", and b\"", "x is \"a\\\", and b\"; z is 1"]) == ["x is \"a\\\", and b\"", "z is 1"]
	ergo._m_said_new(["x is \"a\\\\\", and b is 1", "b is 1"]) == ["x is \"a\\\\\", and b is 1"]
	ergo._m_said_new(["item 1 of xs: a; item 2 of xs: b", "item 2 of xs: b; c"]) == ["item 1 of xs: a; item 2 of xs: b", "c"]
	ergo._m_quote_split("x is \"a, and b", ", and ") == ["x is \"a, and b"]
}

test_message_a_for_alias_loses_its_marker_and_a_value_that_spells_the_alias_stays if {
	ergo._m_aliased("x is \u0002c, and \"$c: y\"") == "x is c, and \"$c: y\""
	ergo._m_aliased("x is 1") == "x is 1"
}

test_message_a_key_named_by_another_name_is_another_name if {
	ergo._m_other_name({"named_by": "z"}, "c")
	ergo._m_other_name({"named_by_field": "z"}, "c")
	not ergo._m_other_name({"named_by": "c"}, "c")
}

test_message_of_a_walk_whose_path_is_not_a_path_names_no_blocked_parent if {
	ergo._m_walk_blocked({}, {"path": "x"}) == []
}

test_message_of_a_walk_that_failed_without_a_list_to_show_repeats_its_expression if {
	check := {"path": ["xs"], "expression": "every xs.ok is true"}
	ergo._walk_parts(check, {}, {"cause": "value"}, {"failed": []}) == [ergo._m_clause("root", "every xs.ok", "value", "every xs.ok is true is false")]
}

test_a_walk_part_is_a_clause_that_keeps_the_path_of_its_item_and_the_cause_of_its_failure if {
	check := ergo._s_written_check("every xs.ok is true")
	subj := {"xs": [{"ok": false}, {}, 3]}
	r := ergo._walk_row(check, subj) with input as {"ergo/names": {"ergo/subject": subj}}
	ergo._walk_parts(check, subj, r, r) == [
		ergo._m_clause("item", ["xs", 0], "value", "item 1 of xs: ok is false"),
		ergo._m_clause("item", ["xs", 1], "absent", "item 2 of xs: ok is missing"),
		ergo._m_clause("item", ["xs", 2], "not_an_object", "item 3 of xs is 3, which isn't an object"),
	] with input as {"ergo/names": {"ergo/subject": subj}}
	keyed := ergo._s_written_check("every xs whose v is m named by $params.k exists")
	k := ergo._walk_row(keyed, {"xs": [{"v": 1}]}) with input as {"ergo/names": {"ergo/subject": {"xs": [{"v": 1}]}}} with data.ergo_params as {"k": 3}
	k.other_roots == [ergo._m_clause("root", "$params.k", "unusable", "$params.k is 3, which isn't text")]
}

test_message_names_an_item_by_the_part_of_the_subject_it_goes_through if {
	marker := ergo._p_marker("cov", 0, null, false)
	ergo._m_item_name(["xs", marker, "z"], set()) == "cov.z"
	ergo._m_off_item_path(["xs", marker])
	not ergo._m_off_item_path(["xs", "z"])
}

_count_of_es(whose) := {"count_of": ["es"], "text": "count of es", "whose": whose}

test_an_item_names_every_condition_of_its_whose_it_cant_decide_and_not_only_the_first if {
	plain := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally_items({"es": [{}]}, plain)] == ["item 1 of es: v is missing", "item 1 of es: w is missing"]
	keyed := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["zz"], "right": ["m", {"ref": ["$$params", "k"]}]},
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": ["m", {"ref": ["$$params", "j"]}]},
	])
	said := [x[1] | some x in ergo._m_tally_items({"es": [{"zz": 2, "v": 2}]}, keyed)] with data.ergo_params as {"k": "a", "j": 3}
	"item 1 of es: $params.j is 3, which isn't text" in said
}

test_a_count_shows_every_item_it_cant_read_whatever_its_cause_but_not_a_root_or_a_params_item_of_another_cause if {
	item := {"item": {"i": ["xs", 0]}}
	ergo._m_record_shown(["absent", "item 1 of xs: v is missing", item], "unusable")
	ergo._m_record_shown(["not_an_object", "item 1 of xs is 3, which isn't an object", item], "absent")
	ergo._m_record_shown(["unusable", "item 1 of xs: v is \"a\", which isn't a number", item], "unusable")
	not ergo._m_record_shown(["value", "item 1 of xs: v is 2", item], "absent")
	not ergo._m_record_shown(["absent", "x is missing"], "unusable")
	not ergo._m_record_shown(["absent", "item 1 of $params.l: v is missing", {"item": {"i": ["$$params", "l", 0]}}], "unusable")
}

_keyed_count_side(sentence) := ergo._m_tally_parts(ergo._s_written_check(sentence))[0]

test_a_count_on_an_empty_list_says_only_the_root_a_key_from_the_item_is_read_in_whatever_the_phrase if {
	every s in [
		"count of xs whose v is $input.m named by key is 0",
		"count of xs whose v is not $input.m named by key is 0",
		"count of xs that is $input.m named by key is 0",
		"count of xs whose v is $input.m named by key and whose w equals 1 is 0",
		"count of xs whose tags contains $input.m named by key is 0",
		"count of xs whose v matches $input.m named by key is 0",
		"count of xs whose $input.m named by key is v is 0",
	] {
		side := _keyed_count_side(s)
		said := [x[1] | some x in ergo._m_tally({"xs": []}, side)] with data.ergo_document as {"m": null}
		said == ["$input.m is null"]
	}
}

test_a_count_on_an_empty_list_says_a_root_further_back_than_the_key_that_isnt_an_object if {
	side := _keyed_count_side("count of xs whose v is $input.m.a named by key is 0")
	said := [x[1] | some x in ergo._m_tally({"xs": []}, side)] with data.ergo_document as {"m": 3}
	said == ["$input.m is 3, which isn't an object"]
}

test_an_item_whose_field_is_of_the_wrong_kind_for_contains_or_matches_gets_its_own_item_entry_beside_the_root_a_key_from_it_is_read_in if {
	every c in [
		["count of xs whose tags contains $input.m named by key is 1", "x", "item 1 of xs: tags is \"x\", which isn't a list"],
		["count of xs whose tags matches $input.m named by key is 1", 3, "item 1 of xs: tags is 3, which isn't text"],
	] {
		side := _keyed_count_side(c[0])
		ts := ergo._m_tally({"xs": [{"key": "a", "tags": c[1]}]}, side) with data.ergo_document as {"m": 3}
		[x[1] | some x in ts] == ["$input.m is 3, which isn't an object", c[2]]
		[x | some x in ts; count(x) == 3] != []
	}
}

test_an_item_doesnt_say_again_the_root_a_key_from_it_is_read_in if {
	every s in [
		"count of xs whose v is not $input.m named by key is 0",
		"count of xs that is $input.m named by key is 0",
		"count of xs whose v is $input.m named by key and whose w equals 1 is 0",
		"count of xs whose $input.m named by key is v is 0",
	] {
		side := _keyed_count_side(s)
		said := [x[1] | some x in ergo._m_tally({"xs": [{"key": "a", "v": 1, "w": 1}]}, side)] with data.ergo_document as {"m": null}
		said == ["$input.m is null"]
	}
}

test_an_item_doesnt_say_again_a_missing_root_a_key_from_it_is_read_in if {
	side := _keyed_count_side("count of xs whose tags contains $input.m named by key and whose v is $params.zz is 1")
	said := [x[1] | some x in ergo._m_tally({"xs": [{"key": "a", "tags": ["x"], "v": "x"}]}, side)] with data.ergo_document as {}
		with data.ergo_params as {}
	said == ["$input.m is missing", "$params.zz is missing"]
}

test_an_item_still_says_its_own_key_beside_the_root_a_key_from_it_is_read_in if {
	side := _keyed_count_side("count of xs whose v is not $input.m named by key is 0")
	said := [x[1] | some x in ergo._m_tally({"xs": [{"v": 1}]}, side)] with data.ergo_document as {"m": 3}
	said == ["$input.m is 3, which isn't an object", "item 1 of xs: key is missing"]
}

test_an_item_without_its_key_says_only_its_key_after_a_null_root_a_key_from_it_is_read_in if {
	every s in [
		"count of xs whose v is not $input.m named by key is 0",
		"count of xs whose $input.m named by key is not v is 0",
		"count of xs whose v is at least $input.m named by key is 0",
		"count of xs whose v is not $input.m named by key and whose w is 1 is 0",
	] {
		side := _keyed_count_side(s)
		said := [x[1] | some x in ergo._m_tally({"xs": [{"v": 1, "w": 1}]}, side)] with data.ergo_document as {"m": null}
		said == ["$input.m is null", "item 1 of xs: key is missing"]
	}
}

test_an_item_of_a_list_reached_through_a_list_doesnt_say_again_the_root_a_key_from_it_is_read_in if {
	side := _keyed_count_side("count of xs.v whose v is not $input.m named by key is 0")
	subj := {"xs": [{"v": {"key": "a", "v": 1}}, {"v": {"key": "b", "v": 2}}]}
	every pair in [[{}, "$input.m is missing"], [{"m": null}, "$input.m is null"], [{"m": 3}, "$input.m is 3, which isn't an object"]] {
		said := [x[1] | some x in ergo._m_tally(subj, side)] with data.ergo_document as pair[0]
		said == [pair[1]]
	}
}

_roots_that_cant_be_read := [
	[{}, "$input.m is missing"],
	[{"m": null}, "$input.m is null"],
	[{"m": 3}, "$input.m is 3, which isn't an object"],
]

test_a_count_says_the_root_a_key_from_the_item_is_read_in_once_and_then_each_item_whose_own_value_it_cant_read if {
	every s in [
		"count of xs whose v is not $input.m named by key is 0",
		"count of xs whose v is $input.m named by key is 0",
		"count of xs whose v is at least $input.m named by key is 0",
		"count of xs whose v is in $input.m named by key is 0",
		"count of xs whose $input.m named by key is v is 0",
	] {
		side := _keyed_count_side(s)
		every pair in _roots_that_cant_be_read {
			said := [x[1] | some x in ergo._m_tally({"xs": [{"key": "a"}, {"key": "b", "v": null}]}, side)] with data.ergo_document as pair[0]
			said == [pair[1], "item 1 of xs: v is missing", "item 2 of xs: v is null"]
		}
	}
}

test_an_item_without_its_key_says_its_own_value_and_its_key_after_the_root_a_key_from_it_is_read_in if {
	every pair in [
		["count of xs whose v is not $input.m named by key is 0", "item 1 of xs: v is missing, and key is missing"],
		["count of xs whose v is at least $input.m named by key is 0", "item 1 of xs: v is missing, and key is missing"],
		["count of xs whose v is in $input.m named by key is 0", "item 1 of xs: v is missing, and key is missing"],
		["count of xs whose $input.m named by key is v is 0", "item 1 of xs: key is missing, and v is missing"],
	] {
		side := _keyed_count_side(pair[0])
		every root in _roots_that_cant_be_read {
			said := [x[1] | some x in ergo._m_tally({"xs": [{"tags": ["x"]}]}, side)] with data.ergo_document as root[0]
			said == [root[1], pair[1]]
		}
	}
}

_items_said_beside_the_keyed_root(sentence, xs, field) if {
	side := _keyed_count_side(sentence)
	every root in _roots_that_cant_be_read {
		said := [x[1] | some x in ergo._m_tally({"xs": xs}, side)] with data.ergo_document as root[0]
		said == [
			root[1],
			concat("", ["item 1 of xs: ", field, " is missing"]),
			concat("", ["item 2 of xs: ", field, " is ", json.marshal(xs[1][field]), ", which isn't ", _kind_wanted[field]]),
			concat("", ["item 3 of xs: ", field, " is null"]),
		]
	}
}

_kind_wanted := {"s": "text", "tags": "a list", "v": "a number"}

test_a_count_says_the_root_a_key_from_the_item_is_read_in_once_and_then_what_each_item_cant_read_whatever_the_phrase if {
	every s in [
		"count of xs whose s starts with $input.m named by key is 0",
		"count of xs whose s ends with $input.m named by key is 0",
		"count of xs whose s does not start with $input.m named by key is 0",
		"count of xs whose s does not end with $input.m named by key is 0",
		"count of xs whose s is alphabetically before $input.m named by key is 0",
		"count of xs whose s is alphabetically on or after $input.m named by key is 0",
		"count of xs whose s matches $input.m named by key is 0",
		"count of xs whose s does not match $input.m named by key is 0",
		"count of xs whose $input.m named by key starts with s is 0",
	] {
		_items_said_beside_the_keyed_root(s, [{"key": "a"}, {"key": "b", "s": 3}, {"key": "c", "s": null}], "s")
	}
	every s in [
		"count of xs whose tags contains $input.m named by key is 0",
		"count of xs whose tags does not contain $input.m named by key is 0",
		"count of xs whose tags contains all of $input.m named by key is 0",
		"count of xs whose tags does not contain all of $input.m named by key is 0",
		"count of xs whose tags contains some of $input.m named by key is 0",
		"count of xs whose tags contains none of $input.m named by key is 0",
		"count of xs whose $input.m named by key contains all of tags is 0",
	] {
		_items_said_beside_the_keyed_root(s, [{"key": "a"}, {"key": "b", "tags": "x"}, {"key": "c", "tags": null}], "tags")
	}
	every s in [
		"count of xs whose v is $input.m named by key within 1 is 0",
		"count of xs whose v is more than $input.m named by key is 0",
	] {
		_items_said_beside_the_keyed_root(s, [{"key": "a"}, {"key": "b", "v": "x"}, {"key": "c", "v": null}], "v")
	}
}

test_an_item_says_its_missing_key_once_when_both_sides_are_roots_read_through_it if {
	side := _keyed_count_side("count of xs whose $input.m named by key is $input.n named by key is 0")
	subj := {"xs": [{"key": "a"}, {"v": 1}]}
	[x[1] | some x in ergo._m_tally(subj, side)] == ["$input.m is null", "item 2 of xs: key is missing"] with data.ergo_document as {"m": null, "n": {"a": 1}}
	[x[1] | some x in ergo._m_tally(subj, side)] == ["$input.m is null", "$input.n is null", "item 2 of xs: key is missing"] with data.ergo_document as {"m": null, "n": null}
}

test_a_count_says_the_root_a_key_from_the_item_is_read_in_once_and_then_the_items_without_their_own_value_with_a_phrase_that_takes_any_kind if {
	every s in [
		"count of xs whose v is not one of $input.m named by key is 0",
		"count of xs whose v is one of $input.m named by key is 0",
		"count of xs whose $input.m named by key contains v is 0",
	] {
		side := _keyed_count_side(s)
		every root in _roots_that_cant_be_read {
			said := [x[1] | some x in ergo._m_tally({"xs": [{"key": "a"}, {"key": "b", "v": "x"}, {"key": "c", "v": null}]}, side)] with data.ergo_document as root[0]
			said == [root[1], "item 1 of xs: v is missing", "item 3 of xs: v is null"]
		}
	}
}

test_an_item_says_each_condition_that_reads_the_root_a_key_from_it_is_read_in if {
	side := _keyed_count_side("count of xs whose v is not $input.m named by key and whose w is $input.m named by key is 0")
	every root in _roots_that_cant_be_read {
		said := [x[1] | some x in ergo._m_tally({"xs": [{"tags": ["x"]}, {"key": "a"}]}, side)] with data.ergo_document as root[0]
		said == [
			root[1],
			"item 1 of xs: v is missing, and key is missing",
			"item 1 of xs: w is missing, and key is missing",
			"item 2 of xs: v is missing",
			"item 2 of xs: w is missing",
		]
	}
}

test_a_count_says_a_root_further_back_once_and_then_each_item_it_cant_read_on_its_own if {
	side := _keyed_count_side("count of xs whose v is not $input.d.m named by key is 0")
	subj := {"xs": [null, {"key": "a", "tags": ["x"]}, {"tags": ["x"]}]}
	every pair in [
		[{"d": 3}, "$input.d is 3, which isn't an object"],
		[{"d": "s"}, "$input.d is \"s\", which isn't an object"],
		[{"d": null}, "$input.d is null"],
	] {
		said := [x[1] | some x in ergo._m_tally(subj, side)] with data.ergo_document as pair[0]
		said == [
			pair[1],
			"item 1 of xs is null, which isn't an object",
			"item 2 of xs: v is missing",
			"item 3 of xs: v is missing, and key is missing",
		]
	}
}

test_an_item_of_a_list_reached_through_a_list_says_what_it_cant_read_on_its_own_after_the_root if {
	side := _keyed_count_side("count of xs.v whose v is not $input.m named by key is 0")
	subj := {"xs": [{"v": {"key": "a"}}, {"v": {"key": "b", "v": null}}]}
	every pair in _roots_that_cant_be_read {
		said := [x[1] | some x in ergo._m_tally(subj, side)] with data.ergo_document as pair[0]
		said == [pair[1], "item 1 of xs: v: v is missing", "item 2 of xs: v: v is null"]
	}
}

test_a_count_says_the_root_a_key_from_the_item_is_read_in_once_before_the_items_with_a_phrase_that_orders_times if {
	side := _keyed_count_side("count of xs whose v is after $input.m named by key is 0")
	every pair in _roots_that_cant_be_read {
		said := [x[1] | some x in ergo._m_tally({"xs": [{"key": "a"}, {"key": "b", "v": "2020-01-01T00:00:00Z"}]}, side)] with data.ergo_document as pair[0]
		said == [pair[1], "item 1 of xs: v is missing"]
	}
}

test_an_item_whose_focus_is_missing_says_only_that_after_the_root_a_key_from_it_is_read_in if {
	side := _keyed_count_side("count of xs.v that is $input.m named by key is 0")
	every pair in _roots_that_cant_be_read {
		said := [x[1] | some x in ergo._m_tally({"xs": [{}]}, side)] with data.ergo_document as pair[0]
		said == [pair[1], "item 1 of xs: v is missing"]
	}
}

test_a_count_on_an_empty_list_doesnt_add_its_root_again_after_the_root_it_already_says if {
	check := ergo._s_written_check("count of xs whose tags contains $input.m named by key is 1")
	o := {"passed": false, "cause": "null", "message": "$input.m is null"}
	ergo._keyed_rooted(o, check, {"xs": []}) == o with data.ergo_document as {"m": null}
}

test_an_item_names_the_conditions_it_cant_decide_in_the_order_the_sentence_reads_them if {
	side := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally({"es": [{}]}, side)] == ["item 1 of es: w is missing", "item 1 of es: v is missing"]
}

test_an_item_two_conditions_cant_read_for_the_same_reason_is_named_once if {
	side := _count_of_es([
		{"op": "compare", "cmp": "eq", "left": ["v"], "right": {"literal": 1}},
		{"op": "compare", "cmp": "eq", "left": ["w"], "right": {"literal": 1}},
	])
	[x[1] | some x in ergo._m_tally_items({"es": [null]}, side)] == ["item 1 of es is null, which isn't an object"]
}

_tally_records(sentence, subj, cause) := ergo._m_tally_said(subj, ergo._m_tally_parts(ergo._s_written_check(sentence))[0], cause)

test_a_count_gives_its_roots_then_its_items_as_clauses if {
	_tally_records("count of ms whose v is at least $params.r is 0", {"ms": [{"v": "s"}, {}, "x"]}, "not_an_object") == [
		ergo._m_clause("root", "$params.r", "absent", "$params.r is missing"),
		ergo._m_item_clause("item 1 of ms", "unusable", [ergo._m_clause("root", "v", "unusable", `v is "s", which isn't a number`)]),
		ergo._m_item_clause("item 2 of ms", "absent", [ergo._m_clause("root", "v", "absent", "v is missing")]),
		ergo._m_clause("item", "item 3 of ms", "not_an_object", `item 3 of ms is "x", which isn't an object`),
	] with data.ergo_params as {}
	ergo._m_clauses_text(ergo._m_clauses_shown(_tally_records("count of ms whose v is at least $params.r is 0", {"ms": [{}, {}, {}, {}]}, "absent"))) == "$params.r is missing; item 1 of ms: v is missing; item 2 of ms: v is missing; item 3 of ms: v is missing; and 1 more" with data.ergo_params as {}
}

test_a_count_says_a_root_before_a_key_from_the_item_once_and_each_item_only_its_own_paths if {
	_tally_records("count of xs whose v is $params.m named by key is 1", {"xs": [{"key": "a", "v": 1}, {}]}, "absent") == [
		ergo._m_clause("root", "$params.m", "null", "$params.m is null"),
		ergo._m_item_clause("item 2 of xs", "absent", [ergo._m_clause("root", "v", "absent", "v is missing, and key is missing")]),
	] with data.ergo_params as {"m": null}
}

test_a_count_on_an_empty_list_says_the_root_a_key_from_the_item_is_read_in if {
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "absent") == [ergo._m_clause("root", "$params.m", "absent", "$params.m is missing")] with data.ergo_params as {}
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "null") == [ergo._m_clause("root", "$params.m", "null", "$params.m is null")] with data.ergo_params as {"m": null}
	_tally_records("count of xs whose v is $params.m named by key is 0", {"xs": []}, "unusable") == [ergo._m_clause("root", "$params.m", "unusable", "$params.m is 3, which isn't an object")] with data.ergo_params as {"m": 3}
}

test_a_count_says_the_root_a_key_from_the_item_is_read_in_before_a_list_it_cant_read if {
	missing := _tally_records("count of xs whose v is $params.m named by key is 0", {}, "unusable") with data.ergo_params as {"m": 3}
	[[c.name, c.cause, c.text] | some c in missing] == [["$params.m", "unusable", "$params.m is 3, which isn't an object"], ["xs", "absent", "xs is missing"]]
	null_list := _tally_records("count of xs whose v is $params.m named by key is 0", {"xs": null}, "absent") with data.ergo_params as {}
	[[c.name, c.cause, c.text] | some c in null_list] == [["$params.m", "absent", "$params.m is missing"], ["xs", "null", "xs is null"]]
}

test_an_items_cause_comes_from_its_record_not_its_last_words if {
	side := ergo._m_tally_parts(ergo._s_written_check("count of xs whose v is 1 is 0"))[0]
	e := {"i": ["xs", 0], "c": ["xs", 0], "iv": {}, "r": [], "v": {}}
	ergo._m_record_clause(["focus unusable", "item 1 of xs: v is missing", {"item": e}], side) == ergo._m_item_clause("item 1 of xs", "unusable", [ergo._m_clause("root", "v", "unusable", "v is missing")])
	ergo._m_record_clause(["absent", `item 1 of xs: v is "a", which isn't text`, {"item": e}], side) == ergo._m_item_clause("item 1 of xs", "absent", [ergo._m_clause("root", "v", "absent", `v is "a", which isn't text`)])
	ergo._m_record_clause(["root unusable", `$params.k is 3, which isn't text`], side) == ergo._m_clause("root", "$params.k", "unusable", `$params.k is 3, which isn't text`)
	ergo._m_record_clause(["absent", "xs is missing"], side) == ergo._m_clause("list", "xs", "absent", "xs is missing")
}

test_a_member_is_named_like_an_item_with_its_key_in_place_of_its_position if {
	ergo._m_item_name(["statuses", {"member": "sign-off"}], set()) == "member sign-off of statuses"
	ergo._m_item_name(["rs", 0, "statuses", {"member": "b"}], set()) == "item 1 of rs: member b of statuses"
	ergo._m_item_name(["evidence", {"member": "y"}, "kind"], set()) == "member y of evidence: kind"
	ergo._m_item_name(["evidence", {"member": "a.b"}], set()) == `member "a.b" of evidence`
}

test_a_member_walk_that_finds_no_object_says_what_is_there if {
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "absent", "value": null, "msg": "an object"}, set()) == "statuses is missing"
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "null", "value": null, "msg": "an object"}, set()) == "statuses is null"
	ergo._m_fail({"path": ["statuses"], "item": ["statuses"], "cause": "unusable", "value": ["DONE"], "msg": "an object"}, set()) == `statuses is ["DONE"], which isn't an object`
}

test_members_count_toward_and_n_more_like_items if {
	ms := ["member a of xs is 1", "member b of xs is 1", "member c of xs is 1", `member "d e" of xs is 1`]
	ergo._m_joined_once(ms) == "member a of xs is 1; member b of xs is 1; member c of xs is 1; and 1 more"
	ergo._m_item_leads(ms) == ["member a of xs", "member b of xs", "member c of xs", `member "d e" of xs`]
	not ergo._m_shown_clause(`member "d e" of xs is 1`, ["member a of xs"])
}

test_members_whose_keys_hold_a_colon_count_toward_and_n_more_one_each if {
	ms := [`member "a: b" of statuses is 1, which isn't text`, `member "a; b: c" of statuses is 1, which isn't text`, "member p of statuses is 1, which isn't text", "member q of statuses is 1, which isn't text"]
	ergo._m_joined_once(ms) == `member "a: b" of statuses is 1, which isn't text; member "a; b: c" of statuses is 1, which isn't text; member p of statuses is 1, which isn't text; and 1 more`
}

test_a_member_is_placed_among_the_items_of_a_tally_by_its_key if {
	ergo._m_positions(["costs", {"member": "c"}]) == ["c"]
	ergo._m_positions(["rs", 0, "statuses", {"member": "b"}]) == [0, "b"]
	ergo._m_positions(["xs", 2, "v"]) == [2]
}

test_an_item_whose_count_of_member_of_ends_at_no_object_says_it_isnt_one if {
	c := {"op": "compare", "cmp": "eq", "left": {"count_of": ["s"], "whose": [], "text": "count of member of s", "member": true}, "right": {"literal": 1}}
	ergo._m_item_tallies({"s": [1]}, c, "unusable") == ["s is [1], which isn't an object"]
	ergo._m_item_tallies({"s": {"x": 1}}, c, "unusable") == []
	l := {"op": "compare", "cmp": "eq", "left": {"count_of": ["s"], "whose": [], "text": "count of s"}, "right": {"literal": 1}}
	ergo._m_item_tallies({"s": {"x": 1}}, l, "unusable") == [`s is {"x": 1}, which isn't a list`]
	ergo._m_item_tallies({"s": [1]}, l, "unusable") == []
}

test_a_named_failure_a_member_walk_wanted_as_an_object_says_it_isnt_one if {
	ergo._m_named_fail({"path": "r.s", "cause": "unusable", "value": [1], "wants": "an object"}) == "r.s is [1], which isn't an object"
	ergo._m_named_fail({"path": "r.s", "cause": "unusable", "value": [1]}) == "r.s is [1], which isn't a list or an object"
}

test_a_failed_row_carries_the_clauses_its_message_is_printed_from if {
	c := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["w"]}
	ergo._m_row_said(c, {}, "absent") == {
		"message": "v is missing, and w is missing",
		"ergo/clauses": [ergo._m_clause("root", "v", "absent", "v is missing"), ergo._m_clause("root", "w", "absent", "w is missing")],
	}
	k := ergo._s_written_check("count of xs whose v is at least 2 is 0")
	tally := ergo._m_row_said(k, {"xs": [{"v": 3}, {}, null]}, "unusable")
	tally.message == "item 2 of xs: v is missing; item 3 of xs is null, which isn't an object"
	tally["ergo/clauses"] == [
		ergo._m_item_clause("item 2 of xs", "absent", [ergo._m_clause("root", "v", "absent", "v is missing")]),
		ergo._m_clause("item", "item 3 of xs", "not_an_object", "item 3 of xs is null, which isn't an object"),
	]
	keyed := {"$sides": [["s", {"named_by_field": "p"}]], "op": "present", "path": ["other"]}
	ergo._m_row_said(keyed, {"s": null, "p": null}, "null") == {
		"message": "p is null; s is null",
		"ergo/clauses": [ergo._m_clause("root", "p", "null", "p is null"), ergo._m_clause("root", "s", "null", "s is null")],
	}
	ergo._m_row_said(c, {"v": 1, "w": 2}, "value")["ergo/clauses"] == [ergo._m_clause("root", "v", "value", "v is 1"), ergo._m_clause("root", "w", "value", "w is 2")]
}

test_a_root_before_several_items_of_a_count_is_cut_from_them_like_the_items if {
	c := ergo._s_written_check("count of xs whose v is 1 is $params.n")
	ergo._m_row_text(c, {"xs": [{}, {}]}, "absent") == "$params.n is missing; item 1 of xs: v is missing; item 2 of xs: v is missing" with data.ergo_params as {}
	ergo._m_row_text(c, {"xs": [{}]}, "absent") == "$params.n is missing, and item 1 of xs: v is missing" with data.ergo_params as {}
}

test_the_roots_of_a_count_and_of_its_whose_are_sorted_together_by_name if {
	c := ergo._s_written_check("count of es whose zz is m named by $params.k is $params.n")
	ergo._m_row_text(c, {"es": [{"zz": 2}, {"zz": 2}]}, "absent") == "$params.k is missing; $params.n is missing; item 1 of es: m is missing; item 2 of es: m is missing" with data.ergo_params as {}
}

test_a_list_after_is_in_ignoring_case_that_isnt_a_list_is_a_root_sorted_by_its_cause if {
	c := ergo._s_written_check("x is in ls ignoring case")
	ergo._m_row_text(c, {"x": null, "ls": "a"}, "unusable") == `ls is "a", which isn't a list, and x is null`
}

test_an_item_of_the_input_read_on_the_right_is_a_root_sorted_by_the_name_of_its_path if {
	c := ergo._s_written_check("id is in $input.id")
	ergo._m_row_text(c, {}, "absent") == "item 2 of $input: id is missing, and id is missing" with data.ergo_document as [{"id": "a"}, {}]
}

test_a_list_on_the_right_that_cant_be_walked_is_a_root_sorted_by_its_name if {
	ref := ergo._s_written_check("x contains all of $input.sbom.components.name")
	ergo._m_row_text(ref, {"x": "click"}, "unusable") == `item 1 of $input.sbom.components is "click", which isn't an object, and x is "click", which isn't a list` with data.ergo_document as {"sbom": {"components": ["click"]}}
	field := ergo._s_written_check("z contains all of ys.v")
	ergo._m_row_text(field, {"z": "click", "ys": ["a"]}, "unusable") == `item 1 of ys is "a", which isn't an object, and z is "click", which isn't a list`
}

test_a_row_keeps_the_items_of_a_list_after_is_in_ignoring_case_in_list_order if {
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._m_row_text(ref, {"x": "a"}, "unusable") == "item 2 of $params.l is null; item 3 of $params.l is 3, which isn't text" with data.ergo_params as {"l": ["a", null, 3]}
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._m_row_text(field, {"x": "a", "ys": [null, 3]}, "unusable") == "item 1 of ys is null; item 2 of ys is 3, which isn't text"
}

test_a_root_list_after_is_in_ignoring_case_that_holds_null_names_each_null_item_and_not_the_list if {
	ref := {"op": "in", "path": ["v"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._m_root_texts({}, ref, "null") == ["item 2 of $params.l is null"] with data.ergo_params as {"l": ["a", null]}
	ergo._m_root_texts({}, ref, "null") == ["item 1 of $params.l is null"] with data.ergo_params as {"l": [null]}
	ergo._m_root_texts({}, ref, "absent") == ["$params.l is missing"] with data.ergo_params as {}
	field := {"op": "compare", "cmp": "in", "left": ["v"], "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._m_root_texts({"ys": ["a", null]}, field, "null") == ["item 2 of ys is null"]
}

test_a_row_keeps_the_items_of_a_list_walked_from_the_input_after_is_in_ignoring_case_in_list_order if {
	ref := {"op": "in", "path": ["x"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._m_row_text(ref, {"x": "a"}, "unusable") == "item 1 of $input.cs: name is null; item 3 of $input.cs: name is true, which isn't text" with data.ergo_document as {"cs": [{"name": null}, {"name": "a"}, {"name": true}]}
}

test_a_root_beside_a_list_after_is_in_ignoring_case_says_its_own_state_and_not_the_lists if {
	c := {"op": "compare", "cmp": "in", "left": ["$$params", "k"], "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._m_root_texts({"ys": ["a", null]}, c, "null") == ["item 2 of ys is null"] with data.ergo_params as {}
	ergo._m_root_texts({"ys": ["a", null]}, c, "absent") == ["$params.k is missing"] with data.ergo_params as {}
	ergo._m_root_texts({"ys": ["a", null]}, c, "null") == ["$params.k is null", "item 2 of ys is null"] with data.ergo_params as {"k": null}
}

test_a_walked_root_after_is_in_ignoring_case_names_each_item_that_isnt_text if {
	c := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._m_walked_root_text(c, "unusable") == "item 1 of $input.cs: name is 3, which isn't text" with data.ergo_document as {"cs": [{"name": 3}]} with input as {}
	ergo._m_walked_root_text(c, "unusable") == "item 1 of $input.cs: name is 3, which isn't text; item 2 of $input.cs: name is null" with data.ergo_document as {"cs": [{"name": 3}, {"name": null}]} with input as {}
	not ergo._m_walked_root_text(c, "unusable") with data.ergo_document as {"cs": [{"name": "a"}]} with input as {}
	not ergo._m_walked_root_text(object.remove(c, ["ignoring"]), "unusable") with data.ergo_document as {"cs": [{"name": 3}]} with input as {}
}

test_a_walked_root_after_is_in_ignoring_case_is_said_once_with_its_worst_cause if {
	c := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	not ergo._m_walked_root_text(c, "null") with data.ergo_document as {"cs": [{"name": 3}, {"name": null}]} with input as {}
	ergo._m_walked_root_text(c, "null") == "item 2 of $input.cs: name is null" with data.ergo_document as {"cs": [{"name": "a"}, {"name": null}]} with input as {}
}

test_a_list_after_is_in_ignoring_case_that_holds_null_is_said_with_the_roots_that_are_null_and_no_item_is_named_for_it if {
	c := {"op": "compare", "cmp": "in", "left": ["$$params", "k"], "right": [`${"alias":"","n":-1,"of":null,"old":true}`, "ys"], "ignoring": "case"}
	ergo._m_keyed_off({"ys": ["a", null]}, c, "null") == ["item 2 of ys is null"] with data.ergo_params as {}
	ergo._m_keyed_off({"ys": ["a", null]}, c, "null") == ["$params.k is null", "item 2 of ys is null"] with data.ergo_params as {"k": null}
	ergo._m_keyed_off({"ys": ["a", null]}, c, "absent") == ["$params.k is missing"] with data.ergo_params as {}
	ergo._m_keyed_off({"ys": ["a", 3]}, c, "null") == [] with data.ergo_params as {}
}

test_an_empty_list_after_is_in_ignoring_case_is_said_as_a_walked_root_as_without_the_words if {
	c := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	ergo._m_walked_root_text(object.remove(c, ["ignoring"]), "value") == "$input.cs is []" with data.ergo_document as {"cs": []} with input as {}
	ergo._m_walked_root_text(c, "value") == "$input.cs is []" with data.ergo_document as {"cs": []} with input as {}
}

test_a_null_params_before_a_key_from_the_item_is_named_as_the_part_before_the_key if {
	c := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["$$params", {"named_by_field": "key"}]}
	ergo._m_null_before_key({"v": 1}, c) == ["$params is null"] with data.ergo_params as null
	ergo._m_null_before_key({"v": 1, "key": "a"}, c) == [] with data.ergo_params as null
}

test_a_null_alias_before_a_key_from_the_item_is_named_as_the_part_before_the_key if {
	c := {"op": "compare", "cmp": "eq", "left": ["v"], "right": ["$w", {"named_by_field": "key"}]}
	ergo._m_null_before_key({"v": 1}, c) == ["$w is null"] with input as {"ergo/names": {"w": null}}
	ergo._m_null_before_key({"v": 1, "key": "a"}, c) == [] with input as {"ergo/names": {"w": null}}
}

test_a_walked_list_after_is_in_ignoring_case_in_a_count_whose_is_said_as_a_root_beside_a_list_that_cant_be_walked if {
	ref := {"op": "in", "path": ["v"], "values": {"ref": ["$$input[]", "cs", "name"]}, "ignoring": "case"}
	stopped := {"fails": [{"cause": "absent"}], "walked": {1}, "trail": []}
	ergo._m_tally_walked(ref, stopped) == [["unusable", "item 1 of $input.cs: name is 3, which isn't text"]] with input as {"ergo/names": {"ergo/subject": {}}} with data.ergo_document as {"cs": [{"name": 3}]}
	ergo._m_tally_walked(object.remove(ref, ["ignoring"]), stopped) == [] with input as {"ergo/names": {"ergo/subject": {}}} with data.ergo_document as {"cs": [{}]}
}

test_a_list_after_is_in_ignoring_case_read_from_each_item_of_a_subject_that_is_a_list_names_its_null_items_in_list_order if {
	c := {"op": "compare", "cmp": "in", "left": ["$$params", "v"], "right": [`${"alias":"thing","n":0,"of":null,"old":true}`, "states"], "ignoring": "case"}
	ergo._m_walked_root_text(c, "null") == "item 2 of thing: item 2 of states is null" with input as {"ergo/names": {"ergo/subject": [{"states": ["A"]}, {"states": ["b", null]}]}}
	ergo._m_walked_root_text(c, "null") == "item 1 of thing: item 1 of states is null; item 2 of thing: item 1 of states is null" with input as {"ergo/names": {"ergo/subject": [{"states": [null]}, {"states": [null]}]}}
	ergo._m_walked_root_text(c, "unusable") == "item 1 of thing: item 1 of states is null; item 1 of thing: item 2 of states is 4, which isn't text" with input as {"ergo/names": {"ergo/subject": [{"states": [null, 4]}]}}
}

test_an_option_or_a_filter_says_the_items_of_a_list_after_is_in_ignoring_case_after_what_the_field_cant_give if {
	c := {"op": "in", "path": ["t"], "values": {"ref": ["$$params[]", "l"]}, "ignoring": "case"}
	ergo._m_line_sorted(c, {}, "absent") == ["t is missing, and item 2 of $params.l is null"] with data.ergo_params as {"l": ["a", null]}
	ergo._m_line_sorted(c, {"t": 3}, "unusable") == ["t is 3, which isn't text, and item 2 of $params.l is null"] with data.ergo_params as {"l": ["a", null]}
	ergo._m_line_sorted(c, {}, "absent") == ["t is missing"] with data.ergo_params as {"l": ["a"]}
	ergo._m_line_sorted(object.remove(c, ["ignoring"]), {}, "absent") == ["t is missing"] with data.ergo_params as {"l": ["a", null]}
}

test_a_list_after_is_in_ignoring_case_read_from_each_item_of_a_subject_that_is_a_list_is_marked_unusable_when_an_item_isnt_text if {
	c := {"op": "compare", "cmp": "in", "left": ["$$params", "v"], "right": [`${"alias":"thing","n":0,"of":null,"old":false}`, "states"], "ignoring": "case"}
	subj := [{"states": ["A"]}, {"states": ["b", 3]}]
	"thing[].states[]" in ergo._m_unusable_names_of(c, subj, "unusable") with input as {"ergo/names": {"ergo/subject": subj}} with data.ergo_params as {"v": "a"}
	text := [{"states": ["A"]}, {"states": ["b"]}]
	not "thing[].states[]" in ergo._m_unusable_names_of(c, text, "unusable") with input as {"ergo/names": {"ergo/subject": text}} with data.ergo_params as {"v": 3}
}
