package ergo

import rego.v1

_messaged(raw, _, _, _) := raw if raw.passed == true

_messaged(raw, check, req, subj) := _keyed_rooted(object.union(raw, said), check, subj) if {
	raw.passed == false
	not "message" in object.keys(raw)
	not _m_marked_cause(raw.cause)
	said := _row_said(_labelled_for(check, req, subj), subj, raw)
}

_messaged(raw, check, req, subj) := _keyed_rooted(object.union(object.union(raw, _row_said(c, subj, raw)), _m_marks(c, subj, raw)), check, subj) if {
	raw.passed == false
	not "message" in object.keys(raw)
	_m_marked_cause(raw.cause)
	c := _labelled_for(check, req, subj)
}

_m_marked_cause("unusable")

_m_marked_cause("not_an_object")

_m_marked_cause("ambiguous")

_row_said(check, subj, raw) := {"message": _row_message(check, subj, raw)} if {
	not _all_of_run(check)
	not _any_of_run(check)
}

_m_marks(check, subj, raw) := _m_all_of_marks(check, subj, raw) if _all_of_run(check)

else := _m_any_of_marks(check, subj, raw) if _any_of_run(check)

else := _m_unusable_marks(check, subj, raw)

_m_unusable_marks(check, subj, raw) := {"inputs": _m_marked(raw.inputs, names)} if {
	names := _m_unusable_names_of(check, subj, raw.cause)
	count(names) > 0
} else := {}

_m_unusable_names_of(check, subj, "unusable") := _m_unusable_names(_m_with_sides(_m_walked(check, subj)), subj) if not _walk_run(check)

else := set()

_m_unusable_names_of(_, _, cause) := set() if cause != "unusable"

_m_all_of_marks(check, subj, raw) := _m_parts_marks(raw, "failed_assertions", [_m_unusable_names_of(check.checks[fa.at], subj, fa.cause) | some fa in raw.failed_assertions]) if {
	some fa in raw.failed_assertions
	fa.cause == "unusable"
} else := {}

_m_any_of_marks(check, subj, raw) := _m_parts_marks(raw, "ergo/outs", [_m_unusable_names_of(check.checks[i], subj, o.cause) | some i, o in raw["ergo/outs"]]) if {
	some o in raw["ergo/outs"]
	o.cause == "unusable"
} else := {}

_m_parts_marks(raw, key, ns) := {key: [object.union(o, {"inputs": _m_marked(o.inputs, ns[k])}) | some k, o in raw[key]], "inputs": _m_marked(raw.inputs, names)} if {
	names := union({n | some n in ns})
	count(names) > 0
} else := {}

_m_unusable_names(check, subj) := {s.name |
	some f in _m_fault(subj, check)
	s := _m_shown(subj, f[0])
	s.state == "value"
} | _m_text_walked_names(check, subj)

_m_text_walked_names(check, subj) := {s.name |
	check.ignoring
	check.cmp in _membership_ops
	_walked_side(check.right)
	_text_walk_state(subj, _rpath(check.right))
	s := _m_shown(subj, check.right)
}

_m_marked(inputs, names) := [_m_marked_input(i, names) | some i in inputs]

_m_marked_input(i, names) := object.union(i, {"ergo/outcome": "unusable"}) if {
	i.name in names
	not i["ergo/worked"]
} else := i

_row_said(check, subj, raw) := {"message": concat("; ", ms), "ergo/texts": ts} if {
	_all_of_run(check)
	ts := [_m_joined(_m_line_sorted(check.checks[i], subj, fa.cause)) |
		some fa in raw.failed_assertions
		i := min({j | some j, a in check.assertions; a == fa.assertion})
	]
	ms := _m_said_new(ts)
	ms != []
} else := {"message": _m_fallback(check)} if _all_of_run(check)

_row_said(check, subj, _) := {"message": concat("; ", ms), "ergo/texts": [_or_blank(t) | some t in said]} if {
	_any_of_run(check)
	causes := [_m_undecided(_option_line_cause(c, _assertion_cause(c, subj, ""), subj)) | some c in check.checks]
	said := [_option_said(c, subj, causes[i]) | some i, c in check.checks]
	texts := [_option_first(check.option_of, said, i) | some i, _ in said]
	ms := [concat("", [nm, ": ", concat(", and ", _m_said_new(lines))]) |
		some k, nm in check.option_of
		not nm in array.slice(check.option_of, 0, k)
		lines := [t | some i, t in texts; check.option_of[i] == nm; t != null]
		lines != []
	]
	ms != []
} else := {"message": _m_fallback(check)} if _any_of_run(check)

_option_said(_, _, "satisfied") := null

_option_said(c, subj, cause) := _m_joined(_m_line_sorted(c, subj, cause)) if cause != "satisfied"

_option_first(option_of, said, i) := null if said[i] == null

else := null if {
	some j, _ in array.slice(said, 0, i)
	option_of[j] == option_of[i]
	said[j] == said[i]
}

else := said[i]

_or_blank(null) := ""

_or_blank(t) := t if t != null

_messaged(raw, check, _, subj) := _for_once_said(_keyed_rooted(_for_said(raw), check, subj), check) if {
	raw.passed == false
	"message" in object.keys(raw)
}

_for_once_said(o, check) := object.union(o, {"message": _for_deduped(o.message)}) if {
	check.op == "for"
	is_string(o.message)
} else := o

_row_message(check, subj, raw) := _m_row_text(check, subj, raw.cause) if {
	not _all_of_run(check)
	not _any_of_run(check)
	not _walk_run(check)
}

_m_row_text(check, subj, cause) := concat("; ", _roots_then_lists(ps, _m_list_names(check))) if {
	cause in _value_fault_causes
	ps := [_m_piece_string(x) | some x in _m_null_key_parts(subj, check)]
	ps != []
} else := _m_top_sorted(_m_message(object.union(_m_with_sides(_m_walked(check, subj)), {"ergo/row": true}), subj, cause), _m_list_names(check)) if cause != "value"

else := _m_message(object.union(_m_with_sides(_m_walked(check, subj)), {"ergo/row": true}), subj, cause)

_walk_message(check, subj, raw, r) := _with_roots(_m_clauses_shown(_walk_parts(check, subj, raw, r)), roots) if {
	walked := _m_for_said_pairs(check)
	roots := _walk_flawed_roots(check, subj, walked)
	some m in roots
	not m.text in {x[1] | some x in walked}
} else := roots if {
	roots := _walk_flawed_roots(check, subj, _m_for_said_pairs(check))
	roots != []
} else := []

_walk_flawed_roots(check, subj, walked) := _m_said_clauses(_once(array.concat(_walk_root_said(check, subj), [[y[1], y[0]] | some y in sort([[x[1], x[0]] | some x in walked])])))

_walk_parts(check, subj, raw, r) := _m_said_clauses(_once([x |
	some c in _key_item_conds(check)
	some [p, _] in _key_base_reads(c)
	some x in _m_key_said(p)
])) if {
	raw["ergo/key_texts"] == true
	_ = [subj, r]
} else := [_m_clause("item", name, f.cause, _m_leaf_named(name, _key_focus_text(f.path, f.item, f["ergo/base"].prefix, _m_key_list_text(_input_name(f["ergo/base"].prefix), f["ergo/base"])))) |
	some p in sort({f.path | some f in r.fails})
	some f in r.fails
	f.path == p
	name := _m_item_name(f.item, roots)
] if {
	r["ergo/key_items"] == true
	roots := _dotted_roots([check.path])
} else := array.concat(_m_said_clauses(_once(array.concat(_m_key_said(check.path), _walk_phrase_said(check)))), ls) if {
	r.failed == []
	ls := [_m_clause("list", n, f.cause, _m_key_list_text(n, f)) | some f in _key_list_flaws(subj, check.path, object.get(check, "if_any", false) == true); n := _input_name(f.prefix)]
	ls != []
} else := _walk_parts_of(check, subj, raw, r)

_m_part_clause(name, cause, text, check) := _m_clause("item", name, cause, text) if _walk_kind(text) == "item"

else := _m_clause("list", _m_clause_name(text), cause, text) if _m_clause_name(text) in _walk_list_names(check)

else := _m_clause("root", _m_clause_name(text), cause, text)

_m_fail_clause(f, roots, check) := _m_part_clause(f.item, f.cause, _m_fail(f, roots), check)

_m_key_texts(path) := [x[1] | some x in _m_key_said(path)]

_m_key_said(path) := array.concat(
	[[f, concat("", [_ref_label(seg.ref), " is ", _key_ref_word[f]])] | some seg in path; f := _ref_step_flaw(seg); f in _no_value_states],
	[["unusable", _m_isnt(_ref_label(seg.ref), _ref_read(seg.ref), "text")] | some seg in path; _ref_step_flaw(seg) == "unusable"],
)

_m_key_list_texts(subj, path, if_any) := [_m_key_list_text(_input_name(f.prefix), f) | some f in _key_list_flaws(subj, path, if_any)]

_m_key_list_text(name, f) := concat("", [name, " is ", _m_state_word(f.cause)]) if f.cause in _no_value_states

_m_key_list_text(name, f) := concat("", [name, " is []"]) if f.cause == "value"

_m_key_list_text(name, f) := _m_isnt(name, f.value, f.kind) if f.cause == "unusable"

_walk_parts_of(check, _, _, r) := ms if {
	r.failed != []
	r.cause != "satisfied"
	fails := object.get(r, "fails", [])
	roots := _dotted_roots([check.path])
	ms := [_m_fail_clause(f, roots, check) | some p in sort({[f.item, f.path] | some f in fails}); some f in fails; [f.item, f.path] == p]
	ms != []
} else := [_m_part_clause(object.get(f, "item", f.path), f.cause, _m_named_fail(f), check) | some f in r.failed] if r.failed != []

_walk_parts_of(check, subj, raw, r) := [_m_clause("root", _m_clause_name(t), "not_an_object", t)] if {
	r.failed == []
	raw.cause == "not_an_object"
	t := _m_not_object(check, subj)
}

_walk_parts_of(check, _, raw, r) := _m_said_clauses(_once(array.concat(ks, _walk_phrase_said(check)))) if {
	r.failed == []
	raw.cause in _no_value_states
	ks := [x | some x in _m_key_said(check.path); x[0] in _no_value_states]
	ks != []
}

_walk_parts_of(check, _, raw, r) := array.concat(_m_said_clauses(_once(_walk_phrase_said(check))), [_m_clause("list", n, raw.cause, concat("", [n, " is ", _m_state_word(raw.cause)]))]) if {
	r.failed == []
	raw.cause in _no_value_states
	_walk_key_ref_texts(check.path) == []
	n := _path_name(check.path)
}

_walk_phrase_said(check) := [[cause, m] |
	is_object(object.get(check, "check", null))
	some cause in _value_fault_cause_list
	m := _m_root_alone(check.check, cause)
]

_walk_parts_of(check, subj, raw, r) := fs if {
	r.failed == []
	raw.cause == "unusable"
	fs := _m_walk_faults(subj, check)
	fs != []
}

_walk_parts_of(check, subj, raw, r) := ms if {
	r.failed == []
	raw.cause == "unusable"
	_m_walk_faults(subj, check) == []
	ms := _m_empty_walk_roots(check, subj, r)
	ms != []
}

_walk_parts_of(check, subj, raw, r) := [_m_clause("root", _m_clause_name(t), "unusable", t)] if {
	r.failed == []
	raw.cause == "unusable"
	_m_walk_faults(subj, check) == []
	_m_empty_walk_roots(check, subj, r) == []
	t := _m_fallback(check)
}

_m_empty_walk_roots(check, subj, r) := _walk_key_root_clauses(check, subj, r) if {
	_m_params_only_flaw(check, r)
	_walk_key_texts(check, r) != []
	_key_beats_roots(check, subj)
} else := ms if {
	_m_params_only_flaw(check, r)
	ms := _walk_root_clauses(check, subj)
	ms != []
} else := ms if {
	_m_params_only_flaw(check, r)
	ms := _m_said_clauses([["unusable", t] | some t in _walk_key_texts(check, r)])
	ms != []
} else := _m_said_clauses(_walk_phrase_said(check)) if _m_params_only_flaw(check, r)

else := []

_m_params_only_flaw(check, r) if {
	r.empty == true
	_params_shape_only_unreadable(check)
}

_m_walk_faults(subj, check) := array.concat(
	_m_said_clauses([["unusable", t] | some t in _once(array.concat(array.concat(_m_key_faults(subj, check), _m_whose_ref_faults(check)), _m_assertion_ref_faults(check)))]),
	[_m_clause("list", _m_clause_name(t), "unusable", t) | some t in _once(_m_walk_blocked(subj, check))],
)

_m_whose_ref_faults(check) := [f | some c in object.get(check, "whose", []); some f in _m_ref_faults_text(c)]

_m_assertion_ref_faults(check) := [f | is_object(object.get(check, "check", null)); some f in _m_ref_faults_text(check.check)]

_m_walk_blocked(subj, check) := [c.text |
	some c in _m_blocked(subj, {"op": "present", "path": check.path})
	not _m_walk_through_list(subj, check.path)
] if is_array(check.path)

else := []

_m_walk_through_list(subj, path) if {
	some i in numbers.range(1, count(path))
	is_array(_m_resolved_prefix(subj, array.slice(path, 0, i)))
}

_walk_parts_of(check, subj, raw, r) := [_m_clause("list", _m_clause_name(t), raw.cause, t) | some t in fs] if {
	r.failed == []
	not raw.cause in _failed_read_states
	fs := _m_list_found(subj, check.path)
	fs != []
}

_walk_parts_of(check, subj, raw, r) := [_m_clause("root", _m_clause_name(t), raw.cause, t)] if {
	r.failed == []
	not raw.cause in _failed_read_states
	_m_list_found(subj, check.path) == []
	t := _m_fallback(check)
}

_m_not_object(check, subj) := _m_message(check, subj, "not_an_object")

_m_named_fail(f) := _m_is(f.path, f.value) if f.cause == "value"

_m_named_fail(f) := concat("", [f.path, " is ", _m_state_word(f.cause)]) if f.cause in _no_value_states

_m_named_fail(f) := _m_isnt(f.path, f.value, object.get(f, "wants", _m_walk_kind(f.value))) if f.cause == "unusable"

_m_named_fail(f) := _m_isnt(f.path, f.value, "an object") if f.cause == "not_an_object"

_for_rest(e) := e.r if is_object(e.iv)

else := []

_m_rest_named(name, f) := concat("", [name, ": ", _plain_steps_name(f.rest)]) if count(object.get(f, "rest", [])) > 0

else := name

_m_undecided("missing") := "absent"

_m_undecided(c) := c if c != "missing"

_m_leaf(item, m) := _m_leaf_in(item, m, set())

_m_leaf_in(item, m, roots) := _m_leaf_named(_m_item_name(item, roots), m)

_m_leaf_named(name, m) := concat("", [name, substring(m, 11, -1)]) if startswith(m, "the subject ")

_m_leaf_named(name, m) := concat("", [name, ": ", m]) if not startswith(m, "the subject ")

_m_item_name(path, _) := _input_name(_as_subject_part(array.slice(path, k, count(path)))) if {
	k := min({k | some k, step in path; _subject_part([step])})
	k > 0
}

_m_item_name(path, roots) := _m_unreached_or(path, roots) if {
	count([j | some j, step in path; _item_step(step)]) == 0
	not _m_off_item_path(path)
}

_m_unreached_or(path, roots) := _m_part_name(path) if _m_part_unreached(path)

else := _failed_name(path, roots)

_m_item_name(path, roots) := concat(": ", array.concat(
	array.concat([_failed_name(array.slice(path, 0, idx[0] + 1), roots)], [_m_position_name(path[idx[k]], _m_inner_name(array.slice(path, idx[k - 1] + 1, idx[k]))) | some k in numbers.range(1, count(idx) - 1)]),
	[_plain_steps_name(tail) | tail := array.slice(path, idx[count(idx) - 1] + 1, count(path)); tail != []],
)) if {
	idx := [j | some j, step in path; _item_step(step)]
	count(idx) > 0
	not _m_off_item_path(path)
}

_m_position_name(step, list) := concat("", ["member ", _s_key_text(step.member), " of ", list]) if _member_step(step)

else := concat("", ["item ", _literal_text(step + 1), " of ", list])

_m_inner_name([]) := "it"

_m_inner_name(steps) := _plain_steps_name(steps) if steps != []

_m_off_item_path(path) if {
	some k, step in path
	k > 0
	_subject_part([step])
}

_m_fail(f, _) := f.msg if {
	f.msg != ""
	not f.msg in _list_expected_msgs
}

_m_fail(f, roots) := _m_is(_m_item_name(f.path, roots), f.value) if {
	f.cause == "value"
	object.get(f, "msg", "") in _blank_or_list_expected_msgs
}

_m_fail(f, roots) := concat("", [_m_item_name(f.path, roots), " is ", _m_state_word(f.cause)]) if {
	f.cause in _no_value_states
	object.get(f, "msg", "") in _blank_or_list_expected_msgs
}

_m_fail(f, roots) := _m_isnt(_m_item_name(f.path, roots), object.get(f, "raw", f.value), object.get(f, "msg", _m_walk_kind(object.get(f, "raw", f.value)))) if {
	f.cause == "unusable"
	object.get(f, "msg", "") in _list_expected_msgs
}

_m_fail_parts("satisfied", _, _) := []

_m_fail_parts(cause, fails, roots) := [_m_fail(f, roots) |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_m_joined(parts) := _m_joined_once(_once(parts))

_m_said_new(texts) := [t |
	some k, x in texts
	before := {c | some j, y in texts; j < k; some p in _m_text_parts(y); some c in p}
	t := concat("; ", [concat(", and ", cs) | some p in _m_text_parts(x); cs := [c | some c in p; not c in before]; cs != []])
	t != ""
]

_m_text_parts(x) := [_m_quote_split(p, ", and ") | some p in _m_quote_split(x, "; ")]

_m_quote_split(t, sep) := [concat(sep, array.slice(ps, cuts[g], cuts[g + 1])) | some g in numbers.range(0, count(cuts) - 2)] if {
	ps := split(t, sep)
	ends := [e | some i, _ in ps; e := i + 1; _m_shut(concat(sep, array.slice(ps, 0, e)))]
	cuts := array.concat([0], _m_last_cut(ends, count(ps)))
}

_m_last_cut(ends, n) := ends if ends[count(ends) - 1] == n

else := array.concat(ends, [n])

_m_shut(s) if count(split(replace(replace(s, "\\\\", ""), "\\\"", ""), "\"")) % 2 == 1

_m_joined_once(ms) := concat("; ", ms) if count(ms) <= 3

_m_joined_once(ms) := concat("; ", ms) if {
	count(ms) > 3
	count(_m_item_leads(ms)) <= 3
}

_m_joined_once(ms) := concat("; ", array.concat([m | some m in ms; _m_shown_clause(m, shown)], [concat("", ["and ", _literal_text(count(leads) - 3), " more"])])) if {
	count(ms) > 3
	leads := _m_item_leads(ms)
	count(leads) > 3
	shown := array.slice(leads, 0, 3)
}

_m_item_leads(ms) := _once([_m_item_lead(m) | some m in ms; _walk_kind(m) == "item"])

_m_shown_clause(m, _) if _walk_kind(m) == "list"

_m_shown_clause(m, shown) if _m_item_lead(m) in shown

_m_tally_shown(state, cause) if state == cause

_m_tally_shown(state, _) if startswith(state, "root ")

_m_tally_shown(state, _) if startswith(state, "list ")

_m_tally_shown(state, _) if startswith(state, "focus ")

_m_tally_lists(subj, check, cause) := [cs |
	some side in _m_tally_parts(check)
	cs := _m_tally_said(subj, side, cause)
	count(cs) > 0
]

_m_tally_said(subj, side, cause) := [_m_record_clause(x, side) | some x in _m_tally_records(subj, side, cause)]

_m_tally_records(subj, side, cause) := [x | some x in _m_tally(subj, side); _m_record_shown(x, cause); not _m_tally_dropped(subj, side, cause, x)]

_m_record_clause([state, text], _) := _m_clause("root", _m_clause_name(text), substring(state, 5, -1), text) if startswith(state, "root ")

_m_record_clause([state, text], _) := _m_clause("list", _m_clause_name(text), substring(state, 5, -1), text) if startswith(state, "list ")

_m_record_clause([state, text], _) := _m_clause("list", _m_clause_name(text), state, text) if state in _failed_read_states

_m_record_clause([state, text, src], side) := _m_item_text_clause(_m_item_name(_m_src_path(src), _dotted_roots([side[_basic_form(side)]])), _m_src_cause(state), text)

_m_src_path(src) := src.item.i

_m_src_path(src) := src.fail.path

_m_src_path(src) := src.key.i

_m_src_cause(state) := substring(state, 5, -1) if startswith(state, "root ")

else := substring(state, 6, -1) if startswith(state, "focus ")

else := state

_m_item_text_clause(name, cause, text) := _m_item_clause(name, cause, [_m_clause("root", _m_clause_name(rest), cause, rest)]) if {
	lead := concat("", [name, ": "])
	startswith(text, lead)
	rest := substring(text, count(lead), -1)
} else := _m_clause("item", name, cause, text) if startswith(text, concat("", [name, " "]))

else := _m_clause("root", _m_clause_name(text), cause, text)

_m_key_flawed(c) if {
	some r in _step_refs(c)
	_ref_state(r) != "value"
}

_m_record_shown(x, cause) if _m_tally_shown(x[0], cause)

_m_record_shown(x, _) if {
	count(x) == 3
	x[0] in _failed_read_states
	not _m_params_item(x[2])
}

_m_params_item(src) if src.item.i[0] in _params_starts

_m_tally_dropped(subj, side, cause, x) if {
	roots := {m | some c in object.get(side, "whose", []); _root_read_flaw(subj, c) == cause; not _m_key_flawed(c); some m in array.concat(_m_root_texts(subj, c, cause), _m_walked_tally_texts(subj, _walked_tallies(c), cause))}
	roots != set()
	not x[1] in roots
	not _items_judged_alone(subj, side)
	x in _m_tally_items(subj, side)
}

_m_tally_parts(check) := [p | some side in _m_sides(check); some p in _m_side_tallies(side)]

_m_side_tallies(side) := [side] if _m_tally_side(side)

else := [p | some p in side.add; _m_tally_side(p)] if _side_form(side) == "add"

else := []

_m_plain_paths(side) := [p | some operand in side.add; not _m_tally_side(operand); some p in _basic_paths(operand)] if _side_form(side) == "add"

else := _side_paths(side)

_m_tally(subj, side) := [[s, concat("", [_path_name(path), " is ", _m_state_word(s)])]] if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
	s := _walk_read_state(subj, path)
	s in _no_value_states
}

_m_tally(subj, side) := [["unusable", c] | some c in _m_parent_clause(subj, {"op": "present", "path": path}, _input_name(path)); not _m_walk_through_list(subj, path)] if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
	_walk_read_state(subj, path) == "unusable"
}

_m_tally(subj, side) := ts if {
	ts := _m_tally_key_items(subj, side)
} else := array.concat(_m_tally_keyed_root(subj, side), _m_tally_walked_side(subj, side))

_m_tally_keyed_root(subj, side) := [[concat("", ["root ", f.cause]), f.text] | some f in b.faults] if {
	b := _m_tally_keyed_base(subj, side)
} else := []

_m_tally_keyed_base(subj, side) := {"faults": fs, "paths": _m_keyed_fault_paths(subj, whose)} if {
	not _unreadable_input
	whose := object.get(side, "whose", null)
	is_array(whose)
	_whose_reads_keyed_root(whose)
	fs := _once([x[2] | some x in sort([[i, f.text, f] |
		some c in whose
		object.get(c, "op", null) in {"compare", "compare_time"}
		some p in [object.get(c, "left", null), object.get(c, "right", null)]
		_keyed_root_path(p)
		f := _keyed_root_fault(subj, p)
		some i, st in _cause_precedence
		st == f.cause
	])])
	fs != []
}

_m_keyed_fault_paths(subj, whose) := {p |
	some c in whose
	object.get(c, "op", null) in {"compare", "compare_time"}
	some p in [object.get(c, "left", null), object.get(c, "right", null)]
	_keyed_root_path(p)
	_keyed_root_fault(subj, p)
}

_whose_reads_keyed_root(whose) if {
	some c in whose
	some p in [object.get(c, "left", null), object.get(c, "right", null)]
	is_array(p)
	count(p) > 2
	last := p[count(p) - 1]
	is_object(last)
	"named_by_field" in object.keys(last)
	_keyed_root_path(p)
}

_m_tally_fail_state(side, x) := concat("", ["root ", x.cause]) if {
	count(_key_item_flaws(side)) > 0
	not _path_through_item(x.item)
} else := x.cause

_m_tally_key_items(subj, side) := array.concat(
	[[concat("", ["root ", x[0]]), x[1]] | some x in _once([x | some c in side.whose; some [p, _] in _key_base_reads(c); some x in _m_key_said(p)])],
	[[concat("", ["root ", f.cause]), _m_leaf_in(e.i, _key_focus_text(array.concat(e.c, f.prefix), e.i, f.prefix, _m_key_list_text(_input_name(f.prefix), f)), roots), {"key": e, "flaw": f, "steps": p}] |
		some e in w.items
		some c in side.whose
		some [p, mode] in _key_base_reads(c)
		not p[0] in _params_starts
		p[0] != "$$input"
		some f in _key_base_flaws(_key_focus(e), p, mode)
	],
) if {
	f := _basic_form(side)
	count(_key_item_flaws(side)) > 0
	not _unreadable_input
	w := _tally_walk(subj, side)
	w.items != []
	w.fails == []
	_key_items_clean(w, side.whose)
	roots := _dotted_roots([side[f]])
}

_m_tally_walked_side(subj, side) := array.concat(
	array.concat(
		_m_tally_heads(said, side, w),
		[[concat("", ["list ", x.cause]), _m_fail(x, roots)] | some x in fs; _m_tally_list_said(side, said, x)],
	),
	[x[2] | some x in sort(array.concat(
		[[_m_positions(x.path), 0, [_m_tally_fail_state(side, x), _m_fail(x, roots), {"fail": x}]] | some x in fs; not _m_tally_list_said(side, said, x)],
		_m_tally_items_at(subj, side),
	))],
) if {
	f := _basic_form(side)
	w := _tally_walk(subj, side)
	roots := _dotted_roots([side[f]])
	fs := array.concat(w.fails, _walk_stop(w))
	said := _m_said_once([[concat("", ["root ", x[0]]), x[1]] | some c in side.whose; some x in array.concat(_m_root_said_all(subj, c), _m_tally_walked(c, w))])
}

_m_said_once(xs) := [x | some i, x in xs; not x[1] in {y[1] | some y in array.slice(xs, 0, i)}]

_m_tally_heads(said, side, w) := said if {
	w.items != []
} else := said if {
	[t | some c in side.whose; some t in _key_root_texts(c)] == []
} else := _m_said_once(array.concat(said, [["root unusable", t] | some c in side.whose; some t in _key_root_texts(c)]))

_m_tally_list_said(side, said, x) if {
	said != []
	not _unreadable_input
	not _m_tally_keyed(side)
	not _path_through_item(x.path)
}

_m_tally_keyed(side) if {
	some c in side.whose
	walk(c, [_, y])
	is_array(y)
	some step in y
	_key_step(step)
}

_m_tally_walked(c, w) := _m_cond_walked_said(c) if array.concat(w.fails, _walk_stop(w)) == []

else := array.concat([x | some x in _m_cond_walked_said(c); x[0] == "value"], _m_text_walked_said(c))

_m_text_walked_said(c) := [[cause, t] |
	walk(c, [_, x])
	is_object(x)
	x.ignoring
	some p in _m_walked_roots(x)
	_text_walked_root(x, p)
	some cause in _value_fault_cause_list
	t := _m_walked_root_text(x, cause)
]

_m_positions(path) := [_m_position(x) | some x in path; _item_step(x)]

_m_position(x) := x.member if _member_step(x)

else := x

_m_tally_items(subj, side) := [x[2] | some x in _m_tally_items_at(subj, side)]

_m_tally_items_at(subj, side) := [[_m_positions(e.i), [1, k], array.concat(x, [{"item": e}])] | some e in w.items; some k, x in array.concat(_m_whose_undecided(subj, alone, e, flaws, roots, paths), [y | _tally_judge(side, e, flaws, w, long).read; some y in _m_tally_item(f, e, roots)])] if {
	f := _basic_form(side)
	w := _tally_walk(subj, side)
	alone := _whose_alone(subj, side)
	flaws := [_cond_flaw(c) | some c in alone.whose]
	roots := _dotted_roots([side[f]])
	long := _long_text(json.marshal([e.iv | some e in w.items]))
	paths := _m_keyed_paths(subj, side)
}

_m_keyed_paths(subj, side) := b.paths if {
	b := _m_tally_keyed_base(subj, side)
} else := set()

_m_whose_undecided(subj, side, e, flaws, roots, paths) := _once([x |
	some i, c in side.whose
	some x in _m_undecided_said(subj, c, e, flaws[i], roots, paths)
])

_m_undecided_said(subj, c, e, flaw, roots, paths) := _m_keyed_said_item(c, e, o, roots) if {
	o := _keyed_own(c, e, paths)
	is_object(_keyed_focus_value(e))
} else := [[_m_focus_state(e, c, cause), _m_focus_text(subj, c, e, cause, roots)]] if {
	cause := _tally_focus_cause(c, e, flaw)
	not cause in _tally_decided_causes
} else := []

_m_keyed_said_item(c, e, o, roots) := [[_m_focus_state(e, c, _worst_of({t[0] | some t in ts})), _m_leaf_in(_focus_of(e, c).i, concat(", and ", [t[1] | some t in ts]), roots)]] if {
	ts := _m_keyed_own_parts(c, o, _keyed_focus_value(e))
	ts != []
} else := []

_m_keyed_own_parts(c, o, item) := _once(array.concat(array.concat(_m_keyed_key_part(c, o, item, "left"), _m_keyed_operand_part(o, item)), _m_keyed_key_part(c, o, item, "right")))

_m_keyed_operand_part(o, item) := [[o.operand, _m_cond_message(o.stand, item, o.operand)]] if not o.operand in _tally_decided_causes

else := []

_m_keyed_key_part(c, o, item, f) := [_keyed_key(item, c[f][count(c[f]) - 1])] if {
	some i, g in o.sides
	g == f
	o.keys[i] != "satisfied"
}

else := []

_m_focus_state(e, c, cause) := concat("", ["focus ", cause]) if {
	e.r != []
	_reads_focus(c)
} else := cause

_m_focus_text(_, c, e, _, roots) := _m_tally_item("count_of", e, roots)[0][1] if _focus_lost(e, c)

_m_focus_text(subj, c, e, cause, roots) := _m_undecided_text(subj, c, _focus_of(e, c), cause, roots) if not _focus_lost(e, c)

_m_undecided_text(subj, c, e, cause, roots) := _m_isnt(_m_item_name(e.i, roots), e.iv, "an object") if {
	cause == "not_an_object"
	not is_object(e.iv)
	not _reads_input_key(c)
} else := t if {
	t := _m_walked_root_text(c, cause)
} else := _m_leaf_in(e.i, concat(", and ", own), roots) if {
	cause in _no_value_states
	not _m_list_read_first(c)
	_m_keyed_off(subj, c, cause) != []
	own := _m_own_clauses(c, e.iv, cause)
	own != []
} else := concat(", and ", off) if {
	off := _m_keyed_off(subj, c, cause)
	off != []
} else := concat(", and ", off) if {
	cause == "not_an_object"
	off := [x.text | some x in _m_input_one_refs(c)]
	off != []
} else := _m_leaf_in(e.i, _m_cond_message(c, e.iv, cause), roots)

_m_own_clauses(c, item, cause) := _once([_m_state_clause(s) |
	some s in _m_sources(item, c)
	s.state == cause
	not _reads_unreadable_ref(c, s.side)
	not _m_keyed_from_root(s.side)
])

_m_keyed_from_root(p) if {
	is_array(p)
	some step in p
	_field_step(step)
	_from_root(step)
}

_m_list_read_first(c) if {
	_list_cmp(c)
	_reads_unreadable_ref(c, c.right)
}

_m_off_path(p) if {
	_part_start(p)
	not _item_keyed(p)
}

_m_off_path(p) if {
	_starts_at_name(p)
	not _part_start(p)
	not _item_keyed(p)
}

_m_off_path(p) if {
	is_array(p)
	_builtin(p)
	not _item_keyed(p)
}

_m_said_in(m, parts) if {
	some p in parts
	contains(p, m)
}

_m_root_texts(subj, c, cause) := [_m_isnt("$input", data.ergo_document, "an object")] if {
	cause == "not_an_object"
	some p in _root_reads(c)
	_input_one_root(c, p)
	is_array(data.ergo_document)
} else := _m_keyed_off(subj, c, cause) if count(_m_keyed_off(subj, c, cause)) > 0

else := [concat("", [_input_name(_as_subject_part(p)), " is ", _m_state_word(cause)]) | some p in sort(_root_reads(c)); _root_state(subj, c, p, _root_tally_lists(c)) == cause]

_m_key_ref_failed(p) if {
	some seg in p
	_ref_step_flaw(seg)
}

_m_keyed_off(subj, c, cause) := ks if {
	ks := _once([_m_root_key_text(step, cause) |
		some side in _m_sides(c)
		some p in _m_side_paths(side)
		is_array(p)
		some step in p
		_field_step(step)
		_from_root(step)
		_m_root_key_text(step, cause)
	])
	ks != []
} else := _m_off_item(subj, c, cause)

_m_root_key_text(step, cause) := concat("", [_fk_text(step), " is ", _m_state_word(cause)]) if {
	cause in _no_value_states
	_key_state(object.get(_fb({}, step), _fk(step), _absent)) == cause
} else := _m_isnt(_fk_text(step), v, "text") if {
	cause == "unusable"
	v := _fb({}, step)[_fk(step)]
	v != null
	not is_string(v)
}

_m_off_item(subj, c, "unusable") := _once(array.concat(
	array.concat(
		[_m_isnt(_input_name(shown), v, "a list") |
			some side in _m_tally_sides(c)
			_m_off_path(side[_basic_form(side)])
			shown := _as_subject_part(side[_basic_form(side)])
			v := _value_at(subj, shown)
			not is_array(v)
			v != null
		],
		_m_off_right(subj, c),
	),
	[m |
		some p in sort({x | walk(c, [_, x]); _m_off_path(x)})
		not _walking_root(c, p)
		shown := _as_subject_part(p)
		some m in _m_parent_clause(subj, {"op": "present", "path": shown}, _input_name(shown))
	],
))

_m_walked_root_text(c, cause) := ts[0] if {
	ts := [t |
		some p in _m_walked_roots(c)
		t := _m_walked_root_fault(c, _walked_root_shown(p), object.get(input, ["ergo/names", "ergo/subject"], null), cause)
	]
	count(ts) > 0
}

_m_walked_roots(c) := [p |
	_list_phrase(c)
	not _one_right(c)
	some p in _m_root_paths(c)
	_walk_outside(p)
	_walking_root(c, p)
]

_m_walked_root_fault(c, shown, x, cause) := _m_text_walk_text(null, shown) if {
	_text_walked_ref(c, shown)
	_text_ref_state(shown) == cause
} else := _m_text_walk_text(x, shown) if {
	_text_walked_side(c, shown)
	_text_walk_state(x, shown) == cause
} else := _rwalk_text(x, shown) if {
	not _text_walk_flawed(c, shown, x)
	w := _rwalk(x, shown)
	w.failed
	w.state == cause
} else := _m_isnt(w.name, w.value, k) if {
	cause == "unusable"
	w := _rwalk(x, shown)
	not w.failed
	k := _m_leaf_needs(c, w.value)
}

_text_walk_flawed(c, shown, _) if {
	_text_walked_ref(c, shown)
	_text_ref_state(shown)
}

_text_walk_flawed(c, shown, x) if {
	_text_walked_side(c, shown)
	_text_walk_state(x, shown)
}

_text_walked_side(c, shown) if {
	p := _rpath(c.right)
	_text_list_root(c, p)
	_walked_root_shown(p) == shown
}

_m_off_right(subj, c) := [_m_isnt(_root_label(p), _root_value(subj, p), k) |
	some p in _root_reads(c)
	k := _root_kind(subj, c, p)
]

_m_off_item(subj, c, cause) := _once([m |
	some p in sort({x | walk(c, [_, x]); _m_off_path(x)})
	not _m_key_ref_failed(p)
	some m in _m_off_item_texts(subj, c, p, cause)
]) if cause in _no_value_states

_m_off_item_texts(subj, c, p, cause) := [_m_text_items(_root_label(p), v)] if {
	_text_list_root(c, p)
	v := _root_value(subj, p)
	_text_items_state(v) == cause
} else := [concat("", [_input_name(_m_shown_at(shown, i, cause)), " is ", _m_state_word(cause)])] if {
	shown := _as_subject_part(p)
	i := min({j | some j in numbers.range(1, count(shown)); _read_state(subj, array.slice(shown, 0, j)) == cause})
} else := []

_m_off_item(_, c, "not_an_object") := [_m_isnt("$input", data.ergo_document, "an object")] if {
	some r in _step_refs(c)
	_input_key_ref(r)
}

_m_shown_at(shown, _, "absent") := shown

_m_shown_at(shown, i, "null") := array.slice(shown, 0, i)

_m_cond_message(c, item, cause) := concat("; ", array.concat(_m_null_before_key(item, c), [concat(", and ", cs)])) if {
	cause in _no_value_states
	cs := _m_key_states(item, c, cause)
	cs != []
} else := concat(", and ", cs) if {
	cause in _no_value_states
	cs := _once(array.concat([_m_state_clause(s) | some s in _m_sources(item, c); s.state == cause], _m_item_tallies(item, c, cause)))
	cs != []
} else := concat(", and ", cs) if {
	cause == "unusable"
	wc := _m_walked(c, item)
	cs := _once([_m_piece_string(x) | some x in array.concat(array.concat(array.concat(array.concat(array.concat(_m_key_faults(item, wc), _m_blocked_early(item, wc)), _m_faults(item, wc)), _m_blocked_late(item, wc)), _m_walk_ref_faults(item, c)), _m_item_tallies(item, c, cause))])
	cs != []
} else := _m_fallback(c)

_m_cond_base_texts(item, c) := [x[1] | some x in _m_cond_base_said(item, c)]

_m_cond_base_said(item, c) := _once([[f.cause, _m_key_list_text(_input_name(f.prefix), f)] |
	some [p, mode] in _key_base_reads(c)
	not p[0] in _params_starts
	not p[0] == "$$input"
	some f in _key_base_flaws(item, p, mode)
])

_m_item_tallies(item, c, "unusable") := [_m_isnt(_input_name(p), v, _m_tally_wants(side)) |
	some side in _m_tally_sides(c)
	p := side[_basic_form(side)]
	not _m_off_path(p)
	v := _value_at(item, p)
	not _m_tally_fits(side, v)
	v != null
]

_m_tally_wants(side) := "an object" if side.member == true

else := "a list"

_m_tally_fits(side, v) if {
	side.member == true
	is_object(v)
}

_m_tally_fits(side, v) if {
	not side.member
	is_array(v)
}

_m_item_tallies(item, c, cause) := [concat("", [_input_name(array.slice(p, 0, i)), " is ", _m_state_word(cause)]) |
	some side in _m_tally_sides(c)
	p := side[_basic_form(side)]
	not _m_off_path(p)
	i := min({j | some j in numbers.range(1, count(p)); _read_state(item, array.slice(p, 0, j)) == cause})
] if cause in _no_value_states

_m_tally_sides(c) := sort({y | walk(c, [_, y]); _basic_form(y) in _tally_forms})

_m_tally_item(_, e, roots) := [["not_an_object", _m_isnt(_m_item_name(e.i, roots), e.iv, "an object")]] if {
	e.v == _absent
	not is_object(e.iv)
}

_m_tally_item(_, e, roots) := [["absent", concat("", [_m_item_name(e.c, roots), " is missing"])]] if {
	e.v == _absent
	is_object(e.iv)
	not _tally_null_step(e)
}

_m_tally_item(_, e, roots) := [["null", concat("", [_m_item_name(array.slice(e.c, 0, (count(e.c) - count(e.r)) + j), roots), " is null"])]] if {
	e.v == _absent
	is_object(e.iv)
	j := _tally_null_step(e)
}

_m_tally_item(_, e, roots) := [["unusable", _m_leaf_in(e.i, c, roots)] | some c in _m_parent_clause(e.iv, {"op": "present", "path": e.r}, _input_name(e.r))] if {
	e.v == _unusable_mark
	_read_state(e.iv, e.r) != "not_an_object"
}

_m_tally_item(_, e, roots) := [["not_an_object", _m_isnt(_m_item_name(e.i, roots), e.iv, "an object")]] if {
	e.v == _unusable_mark
	_read_state(e.iv, e.r) == "not_an_object"
}

_m_tally_item("sum_of", e, roots) := [["null", concat("", [_m_item_name(e.c, roots), " is null"])]] if e.v == null

_m_tally_item("sum_of", e, roots) := [["unusable", _m_isnt(_m_item_name(e.c, roots), e.v, "a number")]] if {
	not _walk_marked(e.v)
	e.v != null
	not is_number(e.v)
}

_m_sentence(c, subj, cause) := [_message(c, subj, cause)] if not _walks(c)

_m_line_sorted(c, subj, cause) := [_m_top_sorted(_message(object.union(c, {"ergo/line": true}), subj, cause), _m_list_names(c))] if {
	not _walks(c)
	cause != "value"
} else := _m_line(c, subj, cause)

_m_sentence(c, subj, cause) := _m_walk_sentence(c, subj, cause, _walk_row(c, subj)) if _walks(c)

_m_walk_sentence(c, subj, cause, r) := _m_clause_texts(_m_walk_clauses(c, subj, cause, r))

_m_walk_clauses(c, subj, cause, r) := _m_clauses_order(r.root_msgs) if "root_msgs" in object.keys(r)

else := _m_clauses_order(_parts_ahead(_walk_parts(c, subj, {"cause": cause}, r), r))

_m_own_msg(check, c, m, [read, subj, cause]) := object.union(_m_own_part(check, c, m, count(read) == 1), {"read": _m_marked(read, _m_unusable_names_of(c, subj, cause))})

_m_own_part(check, c, m, one) := {"own_msg": [_m_aliased(_m_unalias(a, one, x)) | some x in m]} if {
	a := check.items[count(check.items) - 1].as
	_reads_name(c, a)
	not _m_reads_other(c, a)
} else := {}

_m_reads_other(c, a) if {
	walk(c, [at, x])
	not _under_data(at)
	not _under_literal(c, at)
	_m_other_name(x, a)
}

_m_reads_other(c, a) if {
	walk(c, [at, x])
	not _under_data(at)
	not _under_literal(c, at)
	not _m_relative(at)
	_m_other_path(x, a)
}

_m_reads_other(c, a) if {
	some r in _check_refs(c)
	not r[0] in {concat("", ["$", a]), concat("", ["$$", a])}
}

_m_relative(at) if {
	some k in at
	k in {"check", "whose"}
}

_m_other_path(x, a) if {
	is_array(x)
	count(x) > 0
	is_string(x[0])
	x[0] != concat("", ["$", a])
}

_m_other_path(x, _) if {
	is_array(x)
	count(x) > 0
	_string_literal(x[0])
}

_m_other_name(x, _) if {
	is_object(x)
	"text" in object.keys(x)
}

_m_other_name(x, _) if {
	is_object(x)
	"named_by_field" in object.keys(x)
}

_m_other_name(x, a) if {
	is_object(x)
	"named_by" in object.keys(x)
	x.named_by != a
}

_m_unalias(a, one, x) := _m_lead_alias(a, one, x)

_m_lead_alias(a, one, y) := concat("", ["\u0001", a, "\u0001", substring(y, count(a) + 1, -1)]) if {
	one == true
	startswith(y, concat("", ["\u0002", a, " is "]))
}

else := y

_m_under(name, x) := concat("", [name, substring(substring(x, 1, -1), indexof(substring(x, 1, -1), "\u0001") + 1, -1)]) if startswith(x, "\u0001")

else := concat("", [name, ": ", x])

_m_first_marked(xs) := array.concat([xs[0]], [_m_unmarked(x) | some x in array.slice(xs, 1, count(xs))])

_m_unmarked(x) := strings.replace_n({"\u0001": ""}, x)

_m_aliased(m) := strings.replace_n({"\u0002": ""}, m)

_m_null_before_key(item, c) := _once([concat("", [_input_name(prefix), " is null"]) |
	some side in _m_sides(c)
	some p in _m_side_paths(side)
	is_array(p)
	_m_rooted_path(p)
	some i, step in p
	i > 0
	_m_key_state(item, step) in _no_value_states
	prefix := array.slice(p, 0, i)
	_m_resolved_prefix(item, prefix) == null
])

_m_rooted_path(p) if _part_start(p)

_m_rooted_path(p) if _starts_at_name(p)

_m_rooted_path(p) if _builtin(p)
