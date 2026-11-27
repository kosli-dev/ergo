package ergo

import rego.v1

_root_read_flaw(subj, c) := _worst_of(states) if {
	states := _root_states(subj, c)
	count(states) > 0
} else := "value" if {
	"value" in _walked_root_states(c)
} else := ""

_plain_root_flaw(subj, c) := _worst_of(states) if {
	states := _plain_root_states(subj, c)
	count(states) > 0
} else := ""

_plain_root_states(subj, c) := {st |
	lists := _root_tally_lists(c)
	some p in _root_reads(c)
	st := _root_state(subj, c, p, lists)
	st in _failed_read_states
}

_root_tally_lists(c) := {y[_basic_form(y)] | walk(c, [_, y]); _basic_form(y) in _tally_forms}

_root_states(subj, c) := _named_root_states(subj, c) | (_walked_root_states(c) & _failed_read_states) if _walk_roots_on

else := _named_root_states(subj, c)

_walk_roots_on := false

_named_root_states(subj, c) := _plain_root_states(subj, c) | {st |
	some y in _walked_tallies(c)
	some st in _walked_tally_states(subj, y)
	st in _failed_read_states
}

_walked_root_states(c) := {st |
	walk(c, [_, x])
	is_object(x)
	some p in _m_walked_roots(x)
	some st in _walked_root_states_at(x, p)
}

_walked_root_states_at(x, p) := ({st | st := _walked_root_state(x, _rwalk_run(object.get(input, ["ergo/names", "ergo/subject"], null), _dotted_root_part(p)))} | {st |
	_text_walked_ref(x, p)
	st := _text_ref_state(p)
	st in _failed_read_states
}) | {st |
	_text_list_root(x, p)
	st := _text_walk_state(object.get(input, ["ergo/names", "ergo/subject"], null), _dotted_root_part(p))
	st in _failed_read_states
}

_dotted_root_part(p) := rest if {
	p[0] == _root_marker
	rest := array.slice(p, 1, count(p))
	_literal_walk_path(rest)
} else := _as_subject_part(p)

_walked_root_shown(p) := _dotted_root_part(p) if _walk_roots_on

else := _as_subject_part(p)

_walked_root_state(x, w) := _walked_state_of(x, w, _rwalk_states(w))

_walked_state_of(_, _, states) := _worst_or_value(states) if count(states) > 0

_walked_state_of(x, w, states) := "unusable" if {
	count(states) == 0
	_m_leaf_needs(x, [_walk_value(e.v, e, w) | some e in w.items])
}

_walked_tally_states(subj, y) := (({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {st | some e in w.items; some st in _tally_mark(true, e)}) | _tally_number_states(f, _tally_distinct(y, [e.v | some e in w.items], subj, "read")) if {
	f := _basic_form(y)
	w := _tally_walk(subj, y)
}

_walked_tallies(c) := {y |
	some side in _derived_sides(c)
	some y in _tally_parts(side)
	p := y[_basic_form(y)]
	is_array(p)
	_m_off_path(p)
	not _m_key_ref_failed(p)
	not _unbound_alias(p)
	not _unbound_name_step(p)
	_root_walk_node(y, p)
}

_m_walked_tally_texts(subj, ys, st) := [x[1] |
	some y in sort(ys)
	_worst_of(_walked_tally_states(subj, y) & _failed_read_states) == st
	f := _basic_form(y)
	w := _tally_walk(subj, y)
	roots := _dotted_roots([y[f]])
	some x in array.concat([[z.cause, _m_fail(z, roots)] | some z in array.concat(w.fails, _walk_stop(w))], [z | some e in w.items; some z in _m_tally_item(f, e, roots)])
	x[0] == st
]

_m_cond_root_texts(subj, c) := _once([x[1] | some x in _m_cond_root_said(subj, c)])

_m_cond_root_said(subj, c) := _once([[st, m] |
	ys := _walked_tallies(c)
	reads := [[p, _root_state(subj, c, p, set())] | some p in sort(_root_reads(c))]
	some st in _cause_precedence
	some m in array.concat(
		[m | some [p, s] in reads; s == st; m := _m_for_root_text(subj, c, p, st)],
		_m_walked_tally_texts(subj, ys, st),
	)
]) if object.get(c, "ergo/for", false) == true

else := _m_root_said_all(subj, c)

_m_root_said_all(subj, c) := [[st, m] |
	states := _named_root_states(subj, c)
	ys := _walked_tallies(c)
	some st in _cause_precedence
	st in states
	some m in array.concat(_m_root_texts(subj, c, st), _m_walked_tally_texts(subj, ys, st))
]

_m_for_root_text(subj, c, p, st) := f.msg if {
	f := _tally_root_fault(subj, c, p)
} else := _m_isnt(_root_label(p), _root_value(subj, p), k) if k := _root_kind(subj, c, p)

else := _m_isnt(_root_label(p), v, _text_items_kind) if {
	_text_list_root(c, p)
	v := _root_value(subj, p)
	_text_items_state(v) == st
}

else := _message({"op": "present", "path": _as_subject_part(p)}, subj, st)

_root_reads(c) := {x |
	walk(c, [_, x])
	_m_off_path(x)
	not _presence_path(c, x)
	not _m_key_ref_failed(x)
	not _unbound_alias(x)
	not _walking_root(c, x)
	not _unbound_name_step(x)
}

_unbound_name_step(p) if {
	some step in p
	_name_step(step)
	not step.named_by in object.keys(object.get(input, "ergo/names", {}))
}

_walking_root(_, p) if {
	_builtin(p)
	_ref_walks(p)
}

_walking_root(c, p) if {
	object.get(c, "ergo/for", false) == true
	_list_cmp(c)
	not _one_right(c)
	_rpath(c.right) == p
	p[0] == _root_marker
	_rwalks(object.get(input, ["ergo/names", "ergo/subject"], null), array.slice(p, 1, count(p)))
}

_walking_root(c, p) if {
	walk(c, [_, y])
	is_object(y)
	_root_walk_node(y, p)
}

_root_walk_node(y, p) if {
	_rpath(object.get(y, "right", null)) == p
	_list_cmp(y)
	not _one_right(y)
	_root_walks(p)
}

_root_walk_node(y, p) if {
	some f in _tally_forms
	object.get(y, f, null) == p
	_walks_list_start(p)
}

_root_walk_node(y, p) if {
	some f in _tally_forms
	object.get(y, f, null) == p
	_root_walks(p)
	not is_array(object.get(input, ["ergo/names", "ergo/subject"], null))
}

_root_walks(p) if _rwalks(null, p)

_root_walks(p) if {
	_part_start(p)
	_part_of(p).old == false
	_rwalks(object.get(input, ["ergo/names", "ergo/subject"], null), p)
}

_walks_list_start(p) if {
	_list_start(p, null)
	count(p) > 1
	not _index_step(p[1])
}

_unbound_alias(p) if {
	_alias_start(p)
	not substring(p[0], 1, -1) in object.keys(object.get(input, "ergo/names", {}))
}

_presence_path(c, x) if {
	object.get(c, "op", "") in {"present", "missing"}
	c.path == x
}

_root_state(subj, c, p, lists) := "not_an_object" if {
	_input_one_root(c, p)
	is_array(data.ergo_document)
} else := f.state if {
	f := _tally_root_fault(subj, c, p)
} else := "unusable" if {
	_root_kind(subj, c, p)
} else := "null" if {
	_text_list_root(c, p)
	_text_items_state(_root_value(subj, p)) == "null"
} else := _any_read_state(subj, _as_subject_part(p)) if {
	object.get(c, "ergo/for", false) == true
	not _builtin(p)
} else := _any_read_state(subj, p) if {
	object.get(c, "ergo/for", false) == true
	_has_field_step(p)
} else := _root_list_state(subj, p, lists)

_root_kind(subj, c, p) := _text_list_kind(_root_value(subj, p)) if {
	_text_list_root(c, p)
} else := "text" if {
	c.ignoring
	not _text_list_root(c, p)
	_side_root(c, p)
	not is_string(_root_value(subj, p))
} else := _m_right_kind(cmp, v) if {
	some f in _list_argument_keys
	object.get(c, f, null) == {"ref": p}
	not _ref_walks(p)
	_ref_state(p) == "value"
	v := _ref_read(p)
	cmp := _m_ref_cmp(c.op, f)
	not _list_right_usable(cmp, v)
} else := _m_right_kind(c.cmp, v) if {
	_list_cmp(c)
	not _one_right(c)
	_rpath(c.right) == p
	not _rwalking(subj, c.right)
	shown := _as_subject_part(p)
	_read_state(subj, shown) == "value"
	v := _value_at(subj, shown)
	not _list_right_usable(c.cmp, v)
} else := k if {
	c.op in _two_sided_ops
	not _list_cmp(c)
	_side_root(c, p)
	k := _m_right_needs(c, _root_value(subj, p))
} else := "text" if {
	object.get(c, "ergo/for", false) == true
	_builtin(p)
	_keys_by(c, p)
	_ref_state(p) == "value"
	not is_string(_ref_read(p))
} else := "text" if {
	p in object.get(c, "ergo/keys", [])
	not is_string(_root_value(subj, p))
} else := _m_kind(w) if {
	object.get(c, "ergo/for", false) == true
	c.op == "equals"
	c.path == p
	w := _arg(c.value)
	w != null
	type_name(_root_value(subj, p)) != type_name(w)
} else := "a number" if {
	object.get(c, "ergo/for", false) == true
	c.op == "compare"
	c.cmp in _equality_cmps
	"within" in object.keys(c)
	c.left == p
	not is_number(_root_value(subj, p))
} else := _m_kind(w) if {
	object.get(c, "ergo/for", false) == true
	c.op == "compare"
	c.cmp in _equality_cmps
	not "within" in object.keys(c)
	c.left == p
	w := c.right.literal
	w != null
	type_name(_root_value(subj, p)) != type_name(w)
}

_keys_by(c, p) if {
	walk(c, [_, x])
	is_array(x)
	some step in x
	step == {"ref": p}
}

_key_root_texts(c) := array.concat(
	[_m_isnt(named[0], v, "text") |
		some named in sort({[_ref_name(step.ref), step.ref] |
			walk(c, [_, x])
			is_array(x)
			some step in x
			_is_ref(step)
			_builtin(step.ref)
		})
		p := named[1]
		not _ref_walks(p)
		_ref_state(p) == "value"
		v := _ref_read(p)
		not is_string(v)
	],
	[_m_isnt(x[0], x[1], "text") | some x in _alias_keys_unread(c); x[1] != null],
)

_key_root_said(c) := array.concat(
	[["unusable", t] | some t in _key_root_texts(c)],
	[["null", concat("", [x[0], " is null"])] | some x in _alias_keys_unread(c); x[1] == null],
)

_walk_key_texts(check, r) := _once([m |
	some c in _key_conds(check, r)
	some m in _key_root_texts(c)
])

_walk_key_said(check, r) := _once([x |
	some c in _key_conds(check, r)
	some x in _key_root_said(c)
])

_walk_key_msgs(check, subj, r) := _m_root_sorted(_once(array.concat(_walk_key_texts(check, r), _walk_root_msgs(check, subj))))

_walk_key_root_clauses(check, subj, r) := _m_said_clauses(_m_said_sorted(array.concat(_walk_key_said(check, r), _walk_root_said(check, subj))))

_key_beats_roots(check, subj) if {
	not _walk_root_flaw(check, subj) in _root_read_flaws
	not _leaf_root_flaw(check, subj) in _root_read_flaws
}

_key_conds(check, r) := array.concat(object.get(check, "whose", []), [x | x := object.get(check, "check", null); is_object(x)]) if {
	r.empty == true
} else := [c | some item in object.get(check, "items", []); some c in object.get(item, "whose", [])] if {
	not "empty" in object.keys(r)
} else := []

_text_leaf_flawed(check, subj) := [c | some c in _text_leaf_conds(check); _text_leaf_broken(subj, c)]

_text_leaf_broken(subj, c) if {
	some p in _root_reads(c)
	_text_list_root(c, p)
	v := _root_value(subj, p)
	is_array(v)
	_text_items_state(v)
}

_text_leaf_broken(_, c) if {
	_walk_roots_on
	some p in _text_walked_paths(c)
	_walked_root_states_at(c, p) & _failed_read_states != set()
}

_text_list_root(c, p) if {
	c.ignoring
	c.op in _membership_ops
	c.values == {"ref": p}
	not _ref_walks(p)
}

_text_list_root(c, p) if {
	c.ignoring
	_list_cmp(c)
	c.cmp in _membership_ops
	_rpath(c.right) == p
}

_text_walked_root(x, p) if _text_walked_ref(x, p)

_text_walked_paths(c) := {p |
	c.ignoring
	some p in array.concat([c.values.ref | _is_ref(object.get(c, "values", null))], [_rpath(c.right) | c.op == "compare"; c.cmp in _membership_ops; _rpath(c.right)])
	_walk_outside(p)
	_walking_root(c, p)
	_text_walked_root(c, p)
}

_side_root(c, p) if c.right == p

_side_root(c, p) if c.right == {"ref": p}

_side_root(c, p) if c.left == p

_side_root(c, p) if {
	c.op in _membership_ops
	c.path == p
}

_root_value(subj, p) := _ref_read(p) if {
	_builtin(p)
	_ref_state(p) == "value"
} else := _value_at(subj, shown) if {
	not _builtin(p)
	shown := _as_subject_part(p)
	_read_state(subj, shown) == "value"
}

_root_label(p) := _ref_name(p) if _builtin(p)

else := _input_name(_as_subject_part(p))

_root_list_state(subj, p, lists) := _any_read_state(subj, array.slice(shown, 0, i)) if {
	p in lists
	not _builtin(p)
	shown := _as_subject_part(p)
	i := min({j | some j in numbers.range(1, count(shown)); _any_read_state(subj, array.slice(shown, 0, j)) in _failed_read_states})
} else := _root_read_state(subj, p)

_root_read_state(subj, p) := _key_state(v) if {
	some step in p
	_field_step(step)
	_from_root(step)
	v := object.get(_fb({}, step), _fk(step), _absent)
	not is_string(v)
} else := "" if {
	some step in p
	_field_step(step)
	_from_root(step)
} else := _ref_state([_ref_key_seg(seg) | some seg in p]) if {
	_builtin(p)
	some seg in p
	_is_ref(seg)
} else := _ref_state(p) if _builtin(p)

else := _any_read_state(subj, _as_subject_part(p))

_ref_key_seg(seg) := _ref_read(seg.ref) if _is_ref(seg)

else := seg

_walk_root_flaw(check, subj) := _worst_of(states) if {
	states := {fl | some c in array.concat(_walk_root_conds(check), _text_leaf_flawed(check, subj)); fl := _root_read_flaw(subj, c); fl != ""}
	count(states) > 0
} else := "value" if {
	some c in _walk_whose_conds(check)
	_root_read_flaw(subj, c) == "value"
} else := "value" if {
	_walk_roots_on
	some c in _for_sentence_conds(check)
	_root_read_flaw(subj, c) == "value"
} else := ""

_walk_root_conds(check) := array.concat(_walk_whose_conds(check), _for_sentence_conds(check))

_text_leaf_conds(check) := [c] if {
	c := object.get(check, "check", null)
	is_object(c)
	c.ignoring
	some p in _root_reads(c)
	_text_list_root(c, p)
} else := [c] if {
	_walk_roots_on
	c := object.get(check, "check", null)
	is_object(c)
	c.ignoring
	_text_walked_paths(c) != set()
} else := []

_walk_whose_conds(check) := array.concat(array.concat(object.get(check, "whose", []), [c | check.op == "for"; some item in check.items; some c in object.get(item, "whose", [])]), _for_nested_conds(check))

_for_nested_conds(check) := [c |
	check.op == "for"
	some sentence in check.checks
	walk(sentence, [path, cs])
	count(path) > 0
	path[count(path) - 1] == "whose"
	some c in cs
]

_for_sentence_conds(check) := [_for_root_form(x, path) |
	check.op == "for"
	some sentence in check.checks
	walk(sentence, [path, x])
	is_object(x)
	is_string(object.get(x, "op", null))
	not "whose" in path
	_for_read_once(x, path)
]

_for_read_once(x, path) if {
	not x.op in {"every", "some", "all_of", "sentence_any_of"}
	not "check" in path
}

_for_read_once(_, path) if {
	count(path) > 0
	path[count(path) - 1] == "check"
	not "check" in array.slice(path, 0, count(path) - 1)
}

_for_root_form(x, path) := object.union(x, {"ergo/for": true}) if "check" in path

else := object.union(r, {"ergo/keys": _for_root_keys(r)}) if {
	r := object.union(x, object.union(object.union({"ergo/for": true}, {f: _for_rooted_part(x[f]) | some f in _ref_fields; f in object.keys(x)}), {f: {"ref": _root_fields(x[f].ref)} | some f in _list_argument_keys; _is_ref(object.get(x, f, null))}))
}

_for_rooted_part(p) := _rooted_side(p) if is_array(p)

else := object.union(object.remove(p, ["whose"]), {f: _rooted_side(p[f]) | some f in _tally_forms; is_array(object.get(p, f, null))}) if is_object(p)

else := p

_for_root_keys(x) := sort({k |
	walk(x, [at, p])
	not "whose" in at
	is_array(p)
	_for_keyed_path(at, p)
	some step in p
	k := _for_root_key(step)
})

_for_keyed_path(_, p) if _alias_start(p)

_for_keyed_path(at, _) if at[count(at) - 1] in _tally_forms

_for_root_key(step) := [_root_marker, _fk(step)] if {
	_field_step(step)
	step.root == true
}

_for_root_key(step) := [concat("", ["$", step.named_by])] if {
	_name_step(step)
	not startswith(step.named_by, "$")
}

_tally_root(c, p) if {
	object.get(c, "ergo/for", false) == true
	some f in _compare_sides
	y := object.get(c, f, null)
	is_object(y)
	some g in _tally_forms
	object.get(y, g, null) == p
}

_tally_root_fault(subj, c, p) := [x | some x in _tally_steps(subj, _as_subject_part(p)); not x.go][0] if {
	_tally_root(c, p)
	p[0] == _root_marker
} else := {"state": "unusable", "msg": _m_isnt(_root_label(p), v, k)} if {
	_tally_root(c, p)
	v := _root_value(subj, p)
	k := _tally_kind(v, true)
}

_tally_steps(subj, shown) := [_tally_step(subj, array.slice(shown, 0, j), j == count(shown)) | some j in numbers.range(2, count(shown))]

_tally_step(subj, pre, last) := {"state": "", "go": false} if {
	not type_name(pre[count(pre) - 1]) in {"string", "number"}
} else := {"state": st, "msg": concat("", [_input_name(pre), " is ", _m_state_word(st)]), "go": false} if {
	st := _any_read_state(subj, pre)
	st in _no_value_states
} else := {"state": "", "go": false} if {
	is_array(_value_at(subj, pre))
} else := {"state": "unusable", "msg": _m_isnt(_input_name(pre), v, k), "go": false} if {
	v := _value_at(subj, pre)
	k := _tally_kind(v, last)
} else := {"state": "", "go": false} if last

else := {"state": "", "go": true}

_tally_kind(v, last) := "a list or an object" if not type_name(v) in _list_or_object_types

else := "a list" if {
	is_object(v)
	last == true
}

_walk_count_conds(check) := [c |
	check.op == "for"
	some sentence in check.checks
	walk(sentence, [_, x])
	is_object(x)
	_m_tally_side(x)
	some c in object.get(x, "whose", [])
]

_walk_root_msgs(check, subj) := _m_root_sorted(_once([x[1] | some x in _walk_root_said(check, subj)]))

_walk_root_clauses(check, subj) := _m_said_clauses(_m_said_sorted(_walk_root_said(check, subj)))

_walk_root_said(check, subj) := _once(array.concat(
	[[y[1], y[0]] | some y in sort([[x[1], x[0]] | some c in _walk_count_conds(check); some x in array.concat(_m_root_said_all(subj, c), _m_cond_walked_said(c)); x[0] in _no_value_states; startswith(x[1], "$")])],
	array.concat(
		[x |
			some c in array.concat(_walk_whose_conds(check), _text_leaf_flawed(check, subj))
			some x in array.concat(_m_cond_root_said(subj, c), _m_cond_walked_said(c))
		],
		[x |
			some c in _for_sentence_conds(check)
			some x in array.concat(_m_cond_root_said(subj, c), _m_walked_root_said(c))
		],
	),
))

_m_cond_walked_texts(c) := [x[1] | some x in _m_cond_walked_said(c)]

_m_cond_walked_said(c) := [[cause, t] |
	walk(c, [_, x])
	is_object(x)
	_list_phrase(x)
	some cause in array.concat(_value_fault_cause_list, ["value"])
	t := _m_walked_root_text(x, cause)
]

_m_walked_root_texts(c) := _m_cond_walked_texts(c) if _walk_roots_on

else := []

_m_walked_root_said(c) := _m_cond_walked_said(c) if _walk_roots_on

else := []

_leaf_root_flaw(check, subj) := fl if {
	check.op in _walk_ops
	is_object(object.get(check, "check", null))
	paths := [p | some p in _m_root_paths(check.check); not _walking_root(check.check, p)]
	count(paths) > 0
	fl := _root_read_flaw(subj, {"paths": paths})
	fl != ""
} else := "unusable" if {
	check.op in _walk_ops
	is_object(object.get(check, "check", null))
	check.check.op in {"compare", "compare_time", "in", "not_in", "includes", "excludes", "matches_any", "not_matches_any"}
	_leaf_may_root(check.check)
	some p in _root_reads(check.check)
	_root_kind(subj, check.check, p)
} else := _worst_or_value(states) if {
	_walk_roots_on
	check.op in _walk_ops
	is_object(object.get(check, "check", null))
	states := _walked_root_states(check.check)
	count(states) > 0
} else := ""

_leaf_may_root(c) if not _leaf_without_roots(c)

_leaf_without_roots(c) if {
	not _list_cmp(c)
	every f in ["right", "values", "patterns"] {
		not type_name(object.get(c, f, null)) in _list_or_object_types
	}
	object.get(c, "ergo/for", false) != true
}

_leaf_root_clauses(check, flaw) := _m_said_clauses([[flaw, m] | some m in _leaf_root_msgs(check, flaw)])

_leaf_root_msgs(check, flaw) := [m] if {
	m := _m_root_alone(check.check, flaw)
	is_string(m)
}

_rooted_row(check, subj, r) := object.union(object.remove(a, ["other_roots"]), {"cause": _worst_or_value({flaw, a.cause}), "inputs": r.inputs, "failed": a.failed, "root_msgs": _with_roots(ps, ms), "ergo/alone_items": [p | some p in ps; not p.text in {m.text | some m in ms}]}) if {
	check.op != "for"
	not _walk_keyed(check)
	_items_judged_alone(subj, check)
	not _walk_list_fails(r)
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
	ms := _walk_root_clauses(check, subj)
	ms != []
	a := _alone_read(check, subj)
	ps := _walk_parts(check, subj, a, a)
} else := object.union(object.remove(_rooted_main(check, subj, r), ["other_roots"]), {"cause": _worst_or_value({flaw, r.cause}), "root_msgs": _with_roots(_walk_parts(check, subj, r, r), ms)}) if {
	check.op != "for"
	_walk_list_fails(r)
	not _empty_beside_text_leaf(check, subj, r)
	not _walk_keyed(check)
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
	ms := _walk_root_clauses(check, subj)
	ms != []
} else := object.union(r, {"cause": _worst_or_value({flaw, r.cause}), "root_msgs": _with_roots(ps, ms), "ergo/alone_items": [_unrooted_text(t, ms) | some t in _walk_item_texts(ps, r)]}) if {
	r.cause in _value_fault_causes
	check.op != "for"
	not _walk_keyed(check)
	r.fails != []
	every f in r.fails {
		_path_through_item(f.item)
	}
	_walk_root_flaw(check, subj) == ""
	_step_refs(check.check) == set()
	not _walks_for_alias(check)
	flaw := _leaf_root_flaw(check, subj)
	flaw == "unusable"
	ms := _leaf_root_clauses(check, flaw)
	ms != []
	ps := _walk_parts(check, subj, r, r)
} else := _rooted_main(check, subj, r)

_walks_for_alias(check) if {
	is_string(check.path[0])
	_for_alias_step(check.path[0])
}

_unrooted_text(c, ms) := object.union(c, {"text": ""}) if c.text in {m.text | some m in ms}

else := c

_rooted_main(check, subj, r) := object.union(r, {"cause": _worst_of({x[0] | some x in said}), "failed": [], "root_msgs": _walk_key_root_clauses(check, subj, r)}) if {
	r.cause in _not_failing_causes
	said := _walk_key_said(check, r)
	said != []
	_key_beats_roots(check, subj)
} else := object.union(r, object.union(object.union({"cause": flaw, "failed": _rooted_kept(check, subj, r)}, {"root_msgs": ms | ms := _m_said_clauses(_m_said_sorted(said.all)); ms != []}), said.kept)) if {
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
	_rooted_cause_said(check, subj, r, flaw)
	said := _root_said_kept(check, subj)
} else := object.union(r, object.union({"cause": flaw, "failed": []}, {"root_msgs": ms | ms := _leaf_root_clauses(check, flaw); ms != []})) if {
	r.cause in _not_failing_causes
	flaw := _leaf_root_flaw(check, subj)
	flaw != ""
} else := object.union(r, object.union({"other_roots": ms | ms := _m_said_clauses(_m_said_sorted(said.all)); ms != []}, said.kept)) if {
	not r.cause in _not_failing_causes
	said := _root_said_kept(check, subj)
} else := r

_rooted_cause_said(_, _, r, flaw) if r.cause in {"satisfied", "value", flaw}

_rooted_cause_said(check, subj, r, flaw) if {
	_worst_of({flaw, r.cause}) == flaw
	r.fails != []
	some c in array.concat(_walk_root_conds(check), [object.get(check, "check", {})])
	c.ignoring
	ms := _walk_root_msgs(check, subj)
	every f in r.fails {
		f.msg in ms
	}
}

_root_said_kept(check, subj) := {"all": parts.all, "kept": {"ergo/root_said": parts.said}} if {
	check.op == "for"
	parts := _for_said_parts(check, subj)
} else := {"all": _walk_root_said(check, subj), "kept": {}}

_parts_ahead(parts, r) := _with_roots(parts, r.other_roots) if "other_roots" in object.keys(r)

else := parts

_walk_list_fails(r) if {
	r.cause != "satisfied"
	r.failed != []
	r.fails != []
	every f in r.fails {
		not _path_through_item(f.item)
	}
}

_path_through_item(path) if {
	some step in path
	is_number(step)
}

_walk_keyed(check) if {
	some c in _walk_whose_conds(check)
	walk(c, [_, x])
	is_array(x)
	some step in x
	_key_step(step)
}

_key_step(step) if _is_ref(step)

_key_step(step) if _name_step(step)

_key_step(step) if _field_step(step)

_rooted_failed(r) := [] if r.cause in _not_failing_causes

else := r.failed

_rooted_kept(check, subj, r) := [] if {
	_text_leaf_flawed(check, subj) != []
	_ = r
}

else := _rooted_failed(r)

_empty_beside_text_leaf(check, subj, r) if {
	_text_leaf_flawed(check, subj) != []
	every f in r.fails {
		f.cause == "value"
	}
}

_item_keyed(p) if {
	some step in p
	_field_step(step)
	not _from_root(step)
}

_items_judged_alone(subj, side) if {
	some c in object.get(side, "whose", [])
	flaw := _root_read_flaw(subj, c)
	flaw != ""
	_root_stand_in(c) != c
	not _root_said_alone(c, flaw)
}

_root_said_alone(c, flaw) if {
	flaw in _root_read_flaws
	not c.op in {"in", "compare", "compare_time"}
}

_items_judged_alone(subj, side) if _text_leaf_flawed(side, subj) != []

_whose_alone(subj, side) := object.union(side, {"whose": [_root_stand_in(c) | some c in side.whose]}) if {
	_items_judged_alone(subj, side)
	_text_leaf_flawed(side, subj) == []
} else := object.union(object.remove(side, ["check"]), {"whose": [_root_stand_in(c) | some c in side.whose], "check": _text_stand_in(side.check)}) if _items_judged_alone(subj, side)

else := side

_root_stand_in(c) := _typed_stand_in(c.cmp, c.left) if {
	c.op == "compare"
	c.cmp in (_all_cmps | _pattern_ops)
	is_array(c.right)
	_walk_outside(c.right)
	not _stand_in_keyed(c.right)
	is_array(c.left)
	not _walk_outside(c.left)
} else := object.union(c, {"cmp": "eq", f: c[g]}) if {
	c.op == "compare"
	some f in _compare_side_list
	_stand_in_side(c.cmp, f)
	is_array(c[f])
	_walk_outside(c[f])
	not _stand_in_keyed(c[f])
	some g in _compare_side_list
	g != f
	is_array(c[g])
	not _walk_outside(c[g])
} else := object.union(c, {f: {"literal": _stand_in_value[c.op]}}) if {
	c.op in {"compare", "compare_time"}
	c.cmp in {"gt", "gte", "lt", "lte"}
	some f in _compare_side_list
	is_array(c[f])
	_walk_outside(c[f])
	some g in _compare_side_list
	g != f
	is_array(c[g])
	not _walk_outside(c[g])
} else := _typed_stand_in(c.op, c.path) if {
	some f in ["values", "patterns"]
	_is_ref(object.get(c, f, null))
	c.op in (_contain_ops | _pattern_ops)
	is_array(c.path)
	not _walk_outside(c.path)
} else := object.union({"op": "compare", "cmp": "eq", "left": c.path, "right": c.path}, object.filter(c, {"ignoring"})) if {
	some f in ["values", "patterns"]
	_is_ref(object.get(c, f, null))
	c.op in (_list_phrase_ops | _single_contain_ops)
	is_array(c.path)
	not _walk_outside(c.path)
} else := c

_text_stand_in(c) := {"op": "in", "path": c.left, "values": [""], "ignoring": c.ignoring} if c.op == "compare"

else := {"op": "in", "path": c.path, "values": [""], "ignoring": c.ignoring}

_stand_in_side(cmp, _) if cmp in {"eq", "ne", "in", "includes"}

_stand_in_side(cmp, "right") if cmp in _list_cmps

_stand_in_keyed(p) if {
	some step in p
	_key_step(step)
}

_alone_read(check, subj) := object.union(a, {
	"cause": _worst_of({f.cause | some f in failed}),
	"failed": failed,
	"fails": [f | some f in object.get(a, "fails", []); f.cause in _failed_read_states],
	"empty": false,
}) if {
	a := _walk_read_row(object.union(_whose_alone(subj, check), {"op": "every"}), subj)
	failed := [f | some f in a.failed; f.cause in _failed_read_states]
	failed != []
}
