package ergo

import rego.v1

_messaged(raw, _, _, _) := raw if raw.passed == true

_messaged(raw, check, req, subj) := object.union(raw, {"message": m}) if {
	raw.passed == false
	not "message" in object.keys(raw)
	m := _row_message(_labelled_for(check, req, subj), subj, raw)
}

_messaged(raw, _, _, _) := raw if {
	raw.passed == false
	"message" in object.keys(raw)
}

_row_message(check, subj, raw) := _m_row_text(check, subj, raw.cause) if {
	not _all_of_run(check)
	not _any_of_run(check)
	not _walk_run(check)
}

_m_row_text(check, subj, cause) := concat("; ", ps) if {
	cause in {"absent", "null", "unusable"}
	ps := _m_null_key_parts(subj, check)
	ps != []
} else := _m_message(object.union(_m_with_sides(_m_walked(check, subj)), {"ergo/row": true}), subj, cause)

_walk_message(check, subj, raw, r) := _m_joined(_walk_parts(check, subj, raw, r))

_walk_parts(check, _, _, r) := ms if {
	r.failed != []
	ms := _m_fail_parts(r.cause, object.get(r, "fails", []), _dotted_roots([check.path]))
	ms != []
} else := [_m_named_fail(f) | some f in r.failed] if r.failed != []

_walk_parts(check, subj, raw, r) := [_m_not_object(check, subj)] if {
	r.failed == []
	raw.cause == "not_an_object"
}

_walk_parts(check, _, raw, r) := _once(array.concat([concat("", [_path_name(check.path), " is ", _m_state_word(raw.cause)])], _walk_phrase_roots(check))) if {
	r.failed == []
	raw.cause in {"absent", "null"}
}

_walk_phrase_roots(check) := [m |
	is_object(object.get(check, "check", null))
	some cause in ["absent", "null", "unusable"]
	m := _m_root_alone(check.check, cause)
]

_walk_parts(check, subj, raw, r) := fs if {
	r.failed == []
	raw.cause == "unusable"
	fs := _m_walk_faults(subj, check)
	fs != []
}

_walk_parts(check, subj, raw, r) := [_m_fallback(check)] if {
	r.failed == []
	raw.cause == "unusable"
	_m_walk_faults(subj, check) == []
}

_m_walk_faults(subj, check) := _once(array.concat(array.concat(array.concat(_m_key_faults(subj, check), _m_walk_blocked(subj, check)), [f | some c in object.get(check, "whose", []); some f in _m_ref_faults_text(c)]), [f | is_object(object.get(check, "check", null)); some f in _m_ref_faults_text(check.check)]))

_m_walk_blocked(subj, check) := [c |
	some c in _m_blocked(subj, {"op": "present", "path": check.path})
	not _m_walk_through_list(subj, check.path)
] if is_array(check.path)

else := []

_m_walk_through_list(subj, path) if {
	some i in numbers.range(1, count(path))
	is_array(_m_resolved_prefix(subj, array.slice(path, 0, i)))
}

_walk_parts(check, subj, raw, r) := fs if {
	r.failed == []
	not raw.cause in {"absent", "null", "not_an_object", "unusable"}
	fs := _m_list_found(subj, check.path)
	fs != []
}

_walk_parts(check, subj, raw, r) := [_m_fallback(check)] if {
	r.failed == []
	not raw.cause in {"absent", "null", "not_an_object", "unusable"}
	_m_list_found(subj, check.path) == []
}

_m_not_object(check, subj) := _m_message(check, subj, "not_an_object")

_m_named_fail(f) := _m_is(f.path, f.value) if f.cause == "value"

_m_named_fail(f) := concat("", [f.path, " is ", _m_state_word(f.cause)]) if f.cause in {"absent", "null"}

_m_named_fail(f) := _m_isnt(f.path, f.value, _m_walk_kind(f.value)) if f.cause == "unusable"

_m_named_fail(f) := _m_isnt(f.path, f.value, "an object") if f.cause == "not_an_object"

_for_rest(e) := e.r if is_object(e.iv)

else := []

_m_rest_named(name, f) := concat("", [name, ": ", _plain_steps_name(f.rest)]) if count(object.get(f, "rest", [])) > 0

else := name

_m_undecided("missing") := "absent"

_m_undecided(c) := c if c != "missing"

_m_leaf(item, m) := _m_leaf_in(item, m, set())

_m_leaf_in(item, m, roots) := concat("", [_m_item_name(item, roots), substring(m, 11, -1)]) if startswith(m, "the subject ")

_m_leaf_in(item, m, roots) := concat("", [_m_item_name(item, roots), ": ", m]) if not startswith(m, "the subject ")

_m_item_name(path, _) := _input_name(_as_subject_part(array.slice(path, k, count(path)))) if {
	k := min({k | some k, step in path; _subject_part([step])})
	k > 0
}

_m_item_name(path, roots) := _m_unreached_or(path, roots) if {
	count([j | some j, step in path; is_number(step)]) == 0
	not _m_off_item_path(path)
}

_m_unreached_or(path, roots) := _m_part_name(path) if _m_part_unreached(path)

else := _failed_name(path, roots)

_m_item_name(path, roots) := concat(": ", array.concat(
	array.concat([_failed_name(array.slice(path, 0, idx[0] + 1), roots)], [concat("", ["item ", _literal_text(path[idx[k]] + 1), " of ", _m_inner_name(array.slice(path, idx[k - 1] + 1, idx[k]))]) | some k in numbers.range(1, count(idx) - 1)]),
	[_plain_steps_name(tail) | tail := array.slice(path, idx[count(idx) - 1] + 1, count(path)); tail != []],
)) if {
	idx := [j | some j, step in path; is_number(step)]
	count(idx) > 0
	not _m_off_item_path(path)
}

_m_inner_name([]) := "it"

_m_inner_name(steps) := _plain_steps_name(steps) if steps != []

_m_off_item_path(path) if {
	some k, step in path
	k > 0
	_subject_part([step])
}

_m_fail(f, _) := f.msg if {
	f.msg != ""
	not f.msg in {"a list", "a list or an object"}
}

_m_fail(f, roots) := _m_is(_m_item_name(f.path, roots), f.value) if {
	f.cause == "value"
	object.get(f, "msg", "") in {"", "a list", "a list or an object"}
}

_m_fail(f, roots) := concat("", [_m_item_name(f.path, roots), " is ", _m_state_word(f.cause)]) if {
	f.cause in {"absent", "null"}
	object.get(f, "msg", "") in {"", "a list", "a list or an object"}
}

_m_fail(f, roots) := _m_isnt(_m_item_name(f.path, roots), object.get(f, "raw", f.value), object.get(f, "msg", _m_walk_kind(object.get(f, "raw", f.value)))) if {
	f.cause == "unusable"
	object.get(f, "msg", "") in {"a list", "a list or an object"}
}

_m_fail_parts("satisfied", _, _) := []

_m_fail_parts(cause, fails, roots) := [_m_fail(f, roots) |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_m_joined(parts) := _m_joined_once(_once(parts))

_m_joined_once(ms) := concat("; ", ms) if count(ms) <= 3

_m_joined_once(ms) := concat("; ", array.concat(array.slice(ms, 0, 3), [concat("", ["and ", _literal_text(count(ms) - 3), " more"])])) if count(ms) > 3

_m_tally_shown(state, cause) if state == cause

_m_tally_shown("root", _)

_m_tally_shown(state, _) if startswith(state, "focus ")

_m_tallies(subj, check, cause) := [c |
	some side in _m_tally_parts(check)
	cs := [x[1] | some x in _m_tally(subj, side); _m_tally_shown(x[0], cause); not _m_tally_dropped(subj, side, cause, x)]
	count(cs) > 0
	c := _m_joined(cs)
]

_m_tally_dropped(subj, side, cause, x) if {
	roots := {m | some c in object.get(side, "whose", []); _root_read_flaw(subj, c) == cause; some m in array.concat(_m_root_texts(subj, c, cause), _m_walked_tally_texts(subj, _walked_tallies(c), cause))}
	roots != set()
	not x[1] in roots
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
	s in {"absent", "null"}
}

_m_tally(subj, side) := [["unusable", c] | some c in _m_parent_clause(subj, {"op": "present", "path": path}, _input_name(path)); not _m_walk_through_list(subj, path)] if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
	_walk_read_state(subj, path) == "unusable"
}

_m_tally(subj, side) := array.concat(
	array.concat(
		[[x.cause, _m_fail(x, roots)] | some x in array.concat(w.fails, _walk_stop(w))],
		array.concat(
			[["root", m] | some m in sort([m | some c in side.whose; some m in _m_root_texts_all(subj, c); _m_ref_first(m)])],
			[["root", m] | some c in side.whose; some m in _m_root_texts_all(subj, c)],
		),
	),
	_m_tally_items(subj, side),
) if {
	f := _basic_form(side)
	w := _walk(_walk_start({"path": side[f]}, subj), _walk_keys({"path": side[f]}, subj), true)
	roots := _dotted_roots([side[f]])
}

_m_tally_items(subj, side) := [x | some e in w.items; some x in array.concat(_m_whose_undecided(subj, side, e, flaws, roots), [y | _tally_judge(side, e, flaws, w, long).read; some y in _m_tally_item(f, e, roots)])] if {
	f := _basic_form(side)
	w := _walk(_walk_start({"path": side[f]}, subj), _walk_keys({"path": side[f]}, subj), true)
	flaws := [_cond_flaw(c) | some c in side.whose]
	roots := _dotted_roots([side[f]])
	long := _long_text(json.marshal([e.iv | some e in w.items]))
}

_m_whose_undecided(subj, side, e, flaws, roots) := [[_m_focus_state(e, c, cause), _m_focus_text(subj, c, e, cause, roots)] |
	some i, c in side.whose
	cause := _tally_focus_cause(c, e, flaws[i])
	not cause in {"satisfied", "value", "missing"}
]

_m_focus_state(e, c, cause) := concat("", ["focus ", cause]) if {
	e.r != []
	_reads_focus(c)
} else := cause

_m_focus_text(_, c, e, _, roots) := _m_tally_item("count_of", e, roots)[0][1] if _focus_lost(e, c)

_m_focus_text(subj, c, e, cause, roots) := _m_undecided_text(subj, c, _focus_of(e, c), cause, roots) if not _focus_lost(e, c)

_m_undecided_text(subj, c, e, cause, roots) := _m_isnt(_m_item_name(e.i, roots), e.iv, "an object") if {
	cause == "not_an_object"
	not is_object(e.iv)
} else := t if {
	t := _m_walked_root_text(c, cause)
} else := concat(", and ", off) if {
	off := _m_keyed_off(subj, c, cause)
	off != []
} else := concat(", and ", off) if {
	cause == "not_an_object"
	off := _m_input_one_refs(c)
	off != []
} else := _m_leaf_in(e.i, _m_cond_message(c, e.iv, cause), roots)

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

_m_ref_first(m) if {
	startswith(m, "$")
	some word in [" is missing", " is null"]
	endswith(m, word)
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

else := [concat("", [_input_name(_as_subject_part(p)), " is ", _m_state_word(cause)]) | some p in sort(_root_reads(c))]

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
	cause in {"absent", "null"}
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

_m_walked_root_text(c, cause) := _rwalk_text(null, p) if {
	_list_cmp(c)
	not _one_right(c)
	p := _rpath(c.right)
	_walking_root(c, p)
	_rwalk(null, p).state == cause
}

_m_off_right(subj, c) := [_m_isnt(_root_label(p), _root_value(subj, p), k) |
	some p in _root_reads(c)
	k := _root_kind(subj, c, p)
]

_m_off_item(subj, c, cause) := _once([concat("", [_input_name(shown_at), " is ", _m_state_word(cause)]) |
	some p in sort({x | walk(c, [_, x]); _m_off_path(x)})
	not _m_key_ref_failed(p)
	shown := _as_subject_part(p)
	i := min({j | some j in numbers.range(1, count(shown)); _read_state(subj, array.slice(shown, 0, j)) == cause})
	shown_at := _m_shown_at(shown, i, cause)
]) if cause in {"absent", "null"}

_m_shown_at(shown, _, "absent") := shown

_m_shown_at(shown, i, "null") := array.slice(shown, 0, i)

_m_cond_message(c, item, cause) := concat(", and ", cs) if {
	cause in {"absent", "null"}
	cs := _m_key_states(item, c, cause)
	cs != []
} else := concat(", and ", cs) if {
	cause in {"absent", "null"}
	cs := _once(array.concat([_m_state_clause(s) | some s in _m_sources(item, c); s.state == cause], _m_item_tallies(item, c, cause)))
	cs != []
} else := concat(", and ", cs) if {
	cause == "unusable"
	cs := _once(array.concat(array.concat(array.concat(array.concat(_m_key_faults(item, c), _m_blocked(item, c)), _m_faults(item, c)), _m_walk_ref_faults(item, c)), _m_item_tallies(item, c, cause)))
	cs != []
} else := _m_fallback(c)

_m_item_tallies(item, c, "unusable") := [_m_isnt(_input_name(p), v, "a list") |
	some side in _m_tally_sides(c)
	p := side[_basic_form(side)]
	not _m_off_path(p)
	v := _value_at(item, p)
	not is_array(v)
	v != null
]

_m_item_tallies(item, c, cause) := [concat("", [_input_name(array.slice(p, 0, i)), " is ", _m_state_word(cause)]) |
	some side in _m_tally_sides(c)
	p := side[_basic_form(side)]
	not _m_off_path(p)
	i := min({j | some j in numbers.range(1, count(p)); _read_state(item, array.slice(p, 0, j)) == cause})
] if cause in {"absent", "null"}

_m_tally_sides(c) := sort({y | walk(c, [_, y]); _basic_form(y) in {"count_of", "sum_of"}})

_m_tally_item(_, e, roots) := [["not_an_object", _m_isnt(_m_item_name(e.i, roots), e.iv, "an object")]] if {
	e.v == _absent
	not is_object(e.iv)
}

_m_tally_item(_, e, roots) := [["absent", concat("", [_m_item_name(e.c, roots), " is missing"])]] if {
	e.v == _absent
	is_object(e.iv)
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

_m_sentence(c, subj, cause) := _m_walk_sentence(c, subj, cause, _walk_row(c, subj)) if _walks(c)

_m_walk_sentence(c, subj, cause, r) := r.root_msgs if "root_msgs" in object.keys(r)

else := _walk_parts(c, subj, {"cause": cause}, r)

_m_own_msg(check, c, m, one) := {"own_msg": [_m_aliased(_m_unalias(a, one, x)) | some x in m]} if {
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

_m_unalias(a, one, x) := _m_lead_alias(a, one, strings.replace_n({concat("", ["\u0002", a, "."]): ""}, x))

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

_row_message(check, subj, raw) := concat("; ", ms) if {
	_all_of_run(check)
	ms := _once([_m_joined(_m_line(check.checks[i], subj, fa.cause)) |
		some fa in raw.failed_assertions
		i := min({j | some j, a in check.assertions; a == fa.assertion})
	])
	ms != []
} else := _m_fallback(check) if _all_of_run(check)

_row_message(check, subj, _) := concat("; ", ms) if {
	_any_of_run(check)
	causes := [_m_undecided(_option_line_cause(c, _assertion_cause(c, subj, ""), subj)) | some c in check.checks]
	ms := [concat("", [nm, ": ", concat(", and ", lines)]) |
		some k, nm in check.option_of
		not nm in array.slice(check.option_of, 0, k)
		lines := _once([_m_joined(_m_line(c, subj, causes[i])) |
			some i, c in check.checks
			check.option_of[i] == nm
			causes[i] != "satisfied"
		])
		lines != []
	]
	ms != []
} else := _m_fallback(check) if _any_of_run(check)
