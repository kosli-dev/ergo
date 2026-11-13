package ergo

import rego.v1

_root_read_flaw(subj, c) := _worst_of(states) if {
	states := _root_states(subj, c)
	count(states) > 0
} else := ""

_plain_root_flaw(subj, c) := _worst_of(states) if {
	states := _plain_root_states(subj, c)
	count(states) > 0
} else := ""

_plain_root_states(subj, c) := {st |
	lists := {y[_basic_form(y)] | walk(c, [_, y]); _basic_form(y) in {"count_of", "sum_of"}}
	some p in _root_reads(c)
	st := _root_state(subj, c, p, lists)
	st in {"absent", "null", "unusable", "not_an_object"}
}

_root_states(subj, c) := _named_root_states(subj, c) | _walked_root_states(c) if _walk_roots_on

else := _named_root_states(subj, c)

_walk_roots_on if data.ergo_walk_roots == true

_named_root_states(subj, c) := _plain_root_states(subj, c) | {st |
	some y in _walked_tallies(c)
	some st in _walked_tally_states(subj, y)
	st in {"absent", "null", "unusable", "not_an_object"}
}

_walked_root_states(c) := {st |
	walk(c, [_, x])
	is_object(x)
	some p in _m_walked_roots(x)
	st := _walked_root_state(x, _rwalk_run(object.get(input, ["ergo/names", "ergo/subject"], null), _dotted_root_part(p)))
	st in {"absent", "null", "unusable", "not_an_object"}
}

_dotted_root_part(p) := rest if {
	p[0] == _root_marker
	rest := array.slice(p, 1, count(p))
	_literal_walk_path(rest)
} else := _as_subject_part(p)

_walked_root_shown(p) := _dotted_root_part(p) if _walk_roots_on

else := _as_subject_part(p)

_walked_root_state(x, w) := _walked_state_of(x, w, _rwalk_states(w))

_walked_state_of(_, _, states) := _worst_of(states) if count(states) > 0

_walked_state_of(x, w, states) := "unusable" if {
	count(states) == 0
	_m_leaf_needs(x, [_walk_value(e.v, e, w) | some e in w.items])
}

_walked_tally_walk(subj, y) := _walk(_walk_start({"path": p}, subj), _walk_keys({"path": p}, subj), true) if p := y[_basic_form(y)]

_walked_tally_states(subj, y) := (({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {st | some e in w.items; some st in _tally_mark(true, e)}) | _tally_number_states(f, _tally_distinct(y, [e.v | some e in w.items], subj, "read")) if {
	f := _basic_form(y)
	w := _walked_tally_walk(subj, y)
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
	_worst_of(_walked_tally_states(subj, y) & {"absent", "null", "unusable", "not_an_object"}) == st
	f := _basic_form(y)
	w := _walked_tally_walk(subj, y)
	roots := _dotted_roots([y[f]])
	some x in array.concat([[z.cause, _m_fail(z, roots)] | some z in array.concat(w.fails, _walk_stop(w))], [z | some e in w.items; some z in _m_tally_item(f, e, roots)])
	x[0] == st
]

_m_cond_root_texts(subj, c) := _once([m |
	ys := _walked_tallies(c)
	some st in _cause_precedence
	some m in array.concat(
		[m | some p in sort(_root_reads(c)); _root_state(subj, c, p, set()) == st; m := _m_for_root_text(subj, c, p, st)],
		_m_walked_tally_texts(subj, ys, st),
	)
]) if object.get(c, "ergo/for", false) == true

else := _m_root_texts_all(subj, c)

_m_root_texts_all(subj, c) := _once([m |
	states := _named_root_states(subj, c)
	ys := _walked_tallies(c)
	some st in _cause_precedence
	st in states
	some m in array.concat(_m_root_texts(subj, c, st), _m_walked_tally_texts(subj, ys, st))
])

_m_for_root_text(subj, c, p, st) := f.msg if {
	f := _tally_root_fault(subj, c, p)
} else := _m_isnt(_root_label(p), _root_value(subj, p), k) if k := _root_kind(subj, c, p)

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
	some f in ["count_of", "sum_of"]
	object.get(y, f, null) == p
	_walks_list_start(p)
}

_root_walk_node(y, p) if {
	some f in ["count_of", "sum_of"]
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
} else := _any_read_state(subj, _as_subject_part(p)) if {
	object.get(c, "ergo/for", false) == true
	not _builtin(p)
} else := _any_read_state(subj, p) if {
	object.get(c, "ergo/for", false) == true
	_has_field_step(p)
} else := _root_list_state(subj, p, lists)

_root_kind(subj, c, p) := _m_right_kind(cmp, v) if {
	some f in ["values", "patterns"]
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
	c.op in {"compare", "compare_time"}
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
	c.cmp in {"eq", "ne"}
	"within" in object.keys(c)
	c.left == p
	not is_number(_root_value(subj, p))
} else := _m_kind(w) if {
	object.get(c, "ergo/for", false) == true
	c.op == "compare"
	c.cmp in {"eq", "ne"}
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

_side_root(c, p) if c.right == p

_side_root(c, p) if c.right == {"ref": p}

_side_root(c, p) if c.left == p

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
	i := min({j | some j in numbers.range(1, count(shown)); _any_read_state(subj, array.slice(shown, 0, j)) in {"absent", "null", "unusable", "not_an_object"}})
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
	states := {fl | some c in _walk_root_conds(check); fl := _root_read_flaw(subj, c); fl != ""}
	count(states) > 0
} else := ""

_walk_root_conds(check) := array.concat(_walk_whose_conds(check), _for_sentence_conds(check))

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
	r := object.union(x, object.union(object.union({"ergo/for": true}, {f: _for_rooted_part(x[f]) | some f in ["left", "right", "path"]; f in object.keys(x)}), {f: {"ref": _root_fields(x[f].ref)} | some f in ["values", "patterns"]; _is_ref(object.get(x, f, null))}))
}

_for_rooted_part(p) := _rooted_side(p) if is_array(p)

else := object.union(object.remove(p, ["whose"]), {f: _rooted_side(p[f]) | some f in ["count_of", "sum_of"]; is_array(object.get(p, f, null))}) if is_object(p)

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

_for_keyed_path(at, _) if at[count(at) - 1] in {"count_of", "sum_of"}

_for_root_key(step) := [_root_marker, _fk(step)] if {
	_field_step(step)
	startswith(step.named_by_field, _root_key)
}

_for_root_key(step) := [concat("", ["$", step.named_by])] if {
	_name_step(step)
	not startswith(step.named_by, "$")
}

_tally_root(c, p) if {
	object.get(c, "ergo/for", false) == true
	some f in ["left", "right"]
	y := object.get(c, f, null)
	is_object(y)
	some g in ["count_of", "sum_of"]
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
	st in {"absent", "null"}
} else := {"state": "", "go": false} if {
	is_array(_value_at(subj, pre))
} else := {"state": "unusable", "msg": _m_isnt(_input_name(pre), v, k), "go": false} if {
	v := _value_at(subj, pre)
	k := _tally_kind(v, last)
} else := {"state": "", "go": false} if last

else := {"state": "", "go": true}

_tally_kind(v, last) := "a list or an object" if not type_name(v) in {"array", "object"}

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

_walk_root_msgs(check, subj) := _once(array.concat(
	sort([m | some c in _walk_count_conds(check); some m in array.concat(_m_root_texts_all(subj, c), _m_cond_walked_texts(c)); _m_ref_first(m)]),
	array.concat(
		[m |
			some c in _walk_whose_conds(check)
			some m in array.concat(_m_cond_root_texts(subj, c), _m_cond_walked_texts(c))
		],
		[m |
			some c in _for_sentence_conds(check)
			some m in array.concat(_m_cond_root_texts(subj, c), _m_walked_root_texts(c))
		],
	),
))

_m_cond_walked_texts(c) := [t |
	walk(c, [_, x])
	is_object(x)
	_list_phrase(x)
	some cause in ["absent", "null", "unusable"]
	t := _m_walked_root_text(x, cause)
]

_m_walked_root_texts(c) := _m_cond_walked_texts(c) if _walk_roots_on

else := []

_leaf_root_flaw(check, subj) := fl if {
	check.op in {"every", "some"}
	is_object(object.get(check, "check", null))
	paths := [p | some p in _m_root_paths(check.check); not _walking_root(check.check, p)]
	count(paths) > 0
	fl := _root_read_flaw(subj, {"paths": paths})
	fl != ""
} else := "unusable" if {
	check.op in {"every", "some"}
	is_object(object.get(check, "check", null))
	check.check.op in {"compare", "compare_time", "in", "not_in", "includes", "excludes", "matches_any", "not_matches_any"}
	_leaf_may_root(check.check)
	some p in _root_reads(check.check)
	_root_kind(subj, check.check, p)
} else := _worst_of(states) if {
	_walk_roots_on
	check.op in {"every", "some"}
	is_object(object.get(check, "check", null))
	states := _walked_root_states(check.check)
	count(states) > 0
} else := ""

_leaf_may_root(c) if not _leaf_without_roots(c)

_leaf_without_roots(c) if {
	not _list_cmp(c)
	every f in ["right", "values", "patterns"] {
		not type_name(object.get(c, f, null)) in {"array", "object"}
	}
	object.get(c, "ergo/for", false) != true
}

_leaf_root_msgs(check, flaw) := [m] if {
	m := _m_root_alone(check.check, flaw)
	is_string(m)
}

_rooted_row(check, subj, r) := object.union(r, object.union({"cause": flaw, "failed": _rooted_failed(r)}, {"root_msgs": ms | ms := _walk_root_msgs(check, subj); ms != []})) if {
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
	r.cause in {"satisfied", "value", flaw}
} else := object.union(r, object.union({"cause": flaw, "failed": []}, {"root_msgs": ms | ms := _leaf_root_msgs(check, flaw); ms != []})) if {
	r.cause in {"satisfied", "value"}
	flaw := _leaf_root_flaw(check, subj)
	flaw != ""
} else := object.union(r, {"other_roots": ms}) if {
	not r.cause in {"satisfied", "value"}
	ms := _walk_root_msgs(check, subj)
	ms != []
} else := r

_parts_ahead(parts, r) := _with_roots(parts, r.other_roots) if "other_roots" in object.keys(r)

else := parts

_rooted_failed(r) := [] if r.cause in {"satisfied", "value"}

else := r.failed

_item_keyed(p) if {
	some step in p
	_field_step(step)
	not _from_root(step)
}
