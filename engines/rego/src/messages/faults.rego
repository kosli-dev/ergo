package ergo

import rego.v1

_m_reads_params(check) if {
	walk(check, [_, v])
	is_array(v)
	v[0] in _params_starts
}

_m_params_break(path) := [c |
	is_array(path)
	count(path) > 1
	path[0] in _params_starts
	i := min({j |
		some j in numbers.range(1, count(path) - 1)
		not _m_params_holds(path, j)
	})
	c := _m_params_isnt(path, i)
]

_m_params_holds(path, j) if {
	keys := [_m_step_key(null, step) | some step in array.slice(path, 1, j)]
	count(keys) == j - 1
	v := _read_from(data.ergo_params, keys)
	k := _m_step_key(null, path[j])
	_can_hold(v, k)
}

_m_params_isnt(path, i) := _m_isnt(_ref_name(array.slice(path, 0, i)), v, _m_holder(k)) if {
	keys := [_m_step_key(null, step) | some step in array.slice(path, 1, i)]
	count(keys) == i - 1
	v := _read_from(data.ergo_params, keys)
	v != _absent
	v != null
	k := _m_step_key(null, path[i])
}

_m_params_unread(check) if {
	_m_reads_params(check)
	not is_object(data.ergo_params)
	data.ergo_params != null
}

_m_list_items(check, subj) if {
	is_array(subj)
	not _m_list_read_plain(check, subj)
	count(_m_tallies(subj, check, "not_an_object")) > 0
}

_m_list_read_plain(check, subj) if {
	some side in _m_sides(check)
	_basic_form(side) == "path"
	_read_state(subj, side) == "not_an_object"
}

_m_list_read_plain(check, subj) if {
	some side in _m_tally_parts(check)
	some c in side.whose
	_root_read_flaw(subj, c) == "not_an_object"
}

_m_input_one_refs(check) := [_m_isnt("$input", data.ergo_document, "an object") |
	_reads_input_one(check)
	is_array(data.ergo_document)
]

_reads_input_one(check) if {
	some r in _check_refs(check)
	_one_input_ref(check, r)
}

_reads_input_one(check) if {
	_one_right(check)
	is_array(check.right)
	check.right[0] == "$$input"
	is_string(check.right[1])
}

_reads_input_one(check) if {
	some p in _m_sides(check)
	is_array(p)
	count(p) > 1
	p[0] == "$$input"
	not _index_step(p[1])
}

_m_label(check) := check.label if {
	is_object(check)
	is_string(object.get(check, "label", null))
} else := "the subject"

_m_fallback(check) := concat(", and ", cs) if {
	_m_params_unread(check)
	cs := sort({c | walk(check, [_, v]); some c in _m_params_break(v)})
	cs != []
} else := _m_isnt("$params", data.ergo_params, "an object") if _m_params_unread(check)

else := concat("", [check.expression, " is false"]) if _written_expression(check)

else := "the check is false"

_m_key_faults(subj, check) := [c |
	some side in _m_sides(check)
	some p in _m_side_paths(side)
	is_array(p)
	some step in p
	c := _m_key_fault(subj, step)
]

_m_key_states(subj, check, cause) := _once([c |
	some side in _m_sides(check)
	some p in _m_side_paths(side)
	is_array(p)
	some i, step in p
	not _null_stop_before(subj, p, i)
	_m_key_state(subj, step) == cause
	c := concat("", [_m_key_name(step), " is ", _m_state_word(cause)])
])

_null_stop_before(subj, p, i) if {
	_null_stops(subj, p)
	_null_stop_at(subj, p) < i
}

_m_key_state(_, step) := _ref_state(step.ref) if _is_ref(step)

_m_key_state(_, step) := "null" if {
	is_object(step)
	object.keys(step) == {"named_by"}
	input["ergo/names"][step.named_by] == null
}

_m_key_state(subj, step) := "null" if {
	is_object(step)
	is_object(subj)
	_fb(subj, step)[_fk(step)] == null
}

_m_key_state(subj, step) := "absent" if {
	is_object(step)
	is_string(_fk(step))
	is_object(subj)
	not _fk(step) in object.keys(_fb(subj, step))
}

_m_key_name(step) := _ref_name(step.ref) if _is_ref(step)

_m_key_name(step) := step.named_by if object.keys(step) == {"named_by"}

_m_key_name(step) := _fk_text(step) if object.keys(step) == {"named_by_field"}

_m_key_fault(_, step) := _m_isnt(_ref_name(step.ref), v, "text") if {
	_is_ref(step)
	_ref_state(step.ref) == "value"
	v := _ref_shown(step.ref)
	not is_string(v)
}

_m_key_fault(_, step) := _m_isnt(step.named_by, v, "text") if {
	is_object(step)
	object.keys(step) == {"named_by"}
	is_string(step.named_by)
	v := input["ergo/names"][step.named_by]
	v != null
	not is_string(v)
}

_m_key_fault(subj, step) := _m_isnt(_fk_text(step), v, "text") if {
	is_object(step)
	is_string(_fk(step))
	is_object(subj)
	v := _fb(subj, step)[_fk(step)]
	v != null
	not is_string(v)
}

_m_blocked(subj, check) := [c |
	some s in _m_sources(subj, check)
	s.state == "unusable"
	some c in _m_parent_clause(subj, check, s.name)
]

_m_params_faults(subj, check) := [_m_isnt(_ref_name(prefix), v, _m_holder(k)) |
	some side in _m_sides(check)
	is_array(side)
	side[0] in _params_starts
	some i in numbers.range(count(side) - 1, 1)
	prefix := array.slice(side, 0, i)
	v := _m_resolved_prefix(subj, prefix)
	v != _absent
	v != null
	k := _m_step_key(subj, side[i])
	not _can_hold(v, k)
]

_m_parent_clause(subj, check, name) := [c |
	some side in _m_paths_named(check, name)
	is_array(side)
	some i in numbers.range(count(side) - 1, 1)
	v := _m_resolved_prefix(subj, array.slice(side, 0, i))
	v != _absent
	v != null
	k := _m_step_key(subj, side[i])
	not _can_hold(v, k)
	c := _m_isnt(_m_part_name(array.slice(side, 0, i)), v, _m_holder(k))
]

_m_resolved_prefix(subj, prefix) := _resolved(subj, prefix) if not _params_prefix(prefix)

_m_resolved_prefix(subj, prefix) := _read_from(_start_of(subj, prefix), _keys_in(subj, prefix)) if _params_prefix(prefix)

_params_prefix(prefix) if prefix[0] in _params_starts

default _m_part_unreached(_) := false

_m_part_unreached(p) if {
	_part_start(p)
	count(p) > 1
	count(p) - 1 < _part_of(p).n
}

_m_part_name(p) := concat("", [_m_part_prefix(_part_of(p)), _part_of(p).alias, " can't be read: ", _m_part_prefix(_part_of(p)), _input_name(array.slice(p, 1, count(p)))]) if _m_part_unreached(p)

else := _input_name(p)

_m_part_prefix(m) := "" if m.of == null

_m_part_prefix(m) := concat("", [_s_parent_key(m.of), "."]) if m.of != null

_m_paths_named(check, name) := [p | some side in _m_sides(check); some p in _m_side_paths(side); is_array(p); _input_name(p) == name]

_m_side_paths(side) := [side] if is_array(side)

_m_side_paths(side) := _side_paths(side) if not is_array(side)

_m_step_key(_, step) := step if is_string(step)

_m_step_key(_, step) := step if is_number(step)

_m_step_key(_, step) := k if {
	_is_ref(step)
	k := _ref_shown(step.ref)
	is_string(k)
}

_m_step_key(_, step) := k if {
	is_object(step)
	object.keys(step) == {"named_by"}
	is_string(step.named_by)
	k := input["ergo/names"][step.named_by]
	is_string(k)
}

_m_step_key(subj, step) := k if {
	is_object(step)
	is_object(subj)
	k := _fb(subj, step)[_fk(step)]
	is_string(k)
}

_m_holder(step) := "a list" if is_number(step)

_m_holder(step) := "an object" if not is_number(step)

_m_faults(subj, check) := [_m_isnt(s.name, s.value, kind) |
	some f in _m_fault(subj, check)
	s := _m_shown(subj, f[0])
	s.state == "value"
	kind := f[1]
]

_m_ref_blocked(check) := [m |
	some r in sort(_check_refs(check))
	_ref_state(r) == "unusable"
	not _ref_walks(r)
	some m in _m_ref_breaks(r)
]

_m_ref_breaks(r) := [_m_isnt(_ref_name(prefix), v, _m_holder(k)) |
	some i in numbers.range(count(r) - 1, 1)
	prefix := array.slice(r, 0, i)
	v := _m_prefix_read(prefix)
	v != _absent
	v != null
	k := _key(r[i])
	not _can_hold(v, k)
]

_m_prefix_read(prefix) := _ref_read(prefix) if not _params_prefix(prefix)

_m_prefix_read(prefix) := _m_resolved_prefix(null, prefix) if _params_prefix(prefix)

_m_walk_ref_faults(subj, check) := [] if {
	count(_m_tally_parts(check)) > 0
} else := _m_walk_ref_faults_of(subj, check)

_m_walk_ref_faults_of(subj, check) := array.concat(array.concat(_m_ref_blocked(check), [_ref_walk_text(r) | some r in sort(_check_refs(check)); _ref_failed_walk(r); _ref_state(r) == "unusable"]), [t | some side in _m_sides(check); _walked_side(side); s := _m_shown(subj, side); s.state == "unusable"; t := s.text])

_m_ref_list_fault(check) := [[check[f], _m_right_kind(cmp, v)]] if {
	some f in ["values", "patterns"]
	_is_ref(check[f])
	cmp := _m_ref_cmp(check.op, f)
	_ref_state(check[f].ref) == "value"
	v := _ref_shown(check[f].ref)
	not _list_right_usable(cmp, v)
} else := []

_m_ref_cmp(op, "values") := "includes_all" if op == "includes"

_m_ref_cmp(op, "values") := "excludes_all" if op == "excludes"

_m_ref_cmp(op, f) := op if {
	not op in {"includes", "excludes"}
	f in {"values", "patterns"}
}

_m_fault(subj, check) := [f | some g in [_m_fault_1(subj, check), _m_fault_2(subj, check), _m_fault_3(subj, check), _m_fault_4(subj, check), _m_fault_5(subj, check), _m_fault_6(subj, check), _m_fault_7(subj, check), _m_fault_8(subj, check), _m_fault_9(subj, check), _m_fault_10(subj, check), _m_fault_11(subj, check), _m_ref_list_fault(check)]; some f in g]

_m_fault_1(subj, check) := [[check.path, "a number"]] if {
	check.op in {"range", "outside_range"}
	not is_number(_found(subj, check.path))
} else := []

_m_fault_2(subj, check) := [[check.path, "text"]] if {
	check.op in {"matches_any", "not_matches_any"}
	not is_string(_found(subj, check.path))
} else := []

_m_fault_3(subj, check) := [[check.path, "text or a list"]] if {
	check.op in {"empty_string_or_list", "not_empty_string_or_list"}
	not _string_or_list(_found(subj, check.path))
} else := []

_m_fault_4(subj, check) := [[check.path, "a list"]] if {
	check.op in _contain_ops
	not is_array(_found(subj, check.path))
} else := []

_m_fault_5(subj, check) := [[check.path, _m_list_of(_leaf_wants(check))]] if {
	check.op in _contain_ops
	v := _found(subj, check.path)
	is_array(v)
	not _items_fit(v, _leaf_wants(check))
} else := []

_m_fault_6(subj, check) := [[check.path, _m_kind(w)]] if {
	check.op == "equals"
	v := _found(subj, check.path)
	w := _arg(check.value)
	w != null
	type_name(v) != type_name(w)
} else := []

_m_fault_7(subj, check) := [[check.path, _m_kinds(vals)]] if {
	check.op in {"in", "not_in"}
	v := _found(subj, check.path)
	vals := _wants(check.values)
	_value_list(vals)
	not _fits_list(v, vals)
} else := []

_m_fault_8(subj, check) := [f | some s in [check.left, check.right]; some f in _m_side_fault(subj, check, s)] if {
	check.op == "compare"
	not _list_cmp(check)
} else := []

_m_fault_9(subj, check) := fs if {
	_list_cmp(check)
	fs := array.concat(_m_list_left(subj, check), _m_list_right(subj, check))
	fs != []
} else := []

_m_list_right(subj, check) := [[check.right, _m_right_kind(check.cmp, r)]] if {
	_lstate(check, subj) == "value"
	not _lfailed(check, subj)
	r := _lvalue(check, subj)
	not _list_right_usable(check.cmp, r)
} else := []

_m_right_kind(_, r) := "a list" if not is_array(r)

_m_right_kind(cmp, r) := "a list of patterns" if {
	is_array(r)
	cmp in {"matches_any", "not_matches_any"}
}

_m_right_kind(cmp, r) := "a list with at least one value" if {
	r == []
	cmp in _all_cmps
}

_m_right_kind(cmp, r) := "a list of one kind of value" if {
	is_array(r)
	_mixed_types(r)
	cmp in ({"in", "not_in"} | _all_cmps)
}

_m_list_left(subj, check) := [[check.left, "text"]] if {
	check.cmp in {"matches_any", "not_matches_any"}
	not is_string(_found(subj, check.left))
} else := [[check.left, "a list"]] if {
	check.cmp in ({"includes", "excludes"} | _all_cmps)
	not is_array(_found(subj, check.left))
} else := [[check.left, _m_kinds(r)]] if {
	check.cmp in {"in", "not_in"}
	r := _rfound(subj, check.right)
	is_array(r)
	not _mixed_types(r)
	not _fits_list(_found(subj, check.left), r)
} else := [[check.left, _m_list_of(r)]] if {
	check.cmp in _all_cmps
	l := _found(subj, check.left)
	r := _rfound(subj, check.right)
	is_array(l)
	_list_right_usable(check.cmp, r)
	not _items_fit(l, r)
} else := [[check.left, _m_list_of([r])]] if {
	check.cmp in {"includes", "excludes"}
	l := _found(subj, check.left)
	r := _found(subj, check.right)
	is_array(l)
	not _items_fit(l, [r])
} else := []

_m_fault_10(subj, check) := fs if {
	check.op == "compare_time"
	fs := [[s, "a time"] | some s in [check.left, check.right]; v := _m_side_value(subj, s); not _m_time(v)]
	fs != []
} else := []

_m_fault_11(subj, check) := [[check.left, concat("", ["a time written like ", _m_print(r)])]] if {
	check.op == "compare_time"
	l := _m_side_value(subj, check.left)
	r := _m_side_value(subj, check.right)
	_m_time(l)
	_m_time(r)
	not _timestamps(l, r)
} else := []

_m_time(v) if _rfc3339_shaped(v)

_m_time(v) if is_number(v)

_m_time(v) if _date_shaped(v)

_m_side_value(subj, side) := _found(subj, side) if is_array(side)

_m_side_value(_, side) := v if {
	_basic_form(side) == "literal"
	v := _written(side)
}

_m_side_value(subj, side) := v if {
	_side_form(side) in {"count_of", "sum_of", "elapsed", "add", "join"}
	[v] := _side_eval(subj, side).v
}

_m_side_fault(subj, check, side) := f if {
	f := _m_parts_fault(subj, side)
	f != []
} else := [[side, k]] if {
	k := _m_side_kind(subj, check, side)
	v := _m_side_value(subj, side)
	not _m_fits_kind(v, k)
}

_m_parts_fault(subj, side) := fs if {
	_side_form(side) == "elapsed"
	fs := [[p, "a time"] | some p in [side.elapsed_from, side.elapsed_to]; v := _found(subj, p); not _m_time(v)]
	fs != []
} else := [[side.elapsed_from, concat("", ["a time written like ", _m_print(r)])]] if {
	_side_form(side) == "elapsed"
	l := _found(subj, side.elapsed_from)
	r := _found(subj, side.elapsed_to)
	not _elapsed_times(l, r)
}

_m_parts_fault(subj, side) := [[p, "a number"] | some p in side.add; v := _found(subj, p); not is_number(v)] if _side_form(side) == "add"

_m_parts_fault(subj, side) := [[p, "text"] | some p in side.join; v := _found(subj, p); not is_string(v)] if _side_form(side) == "join"

_m_side_kind(_, check, _) := "a number" if "within" in object.keys(check)

_m_side_kind(_, check, _) := "text" if {
	not "within" in object.keys(check)
	check.cmp in _text_cmps
}

_m_side_kind(_, check, _) := "a number" if {
	not "within" in object.keys(check)
	not check.cmp in _text_cmps
	not check.cmp in {"eq", "ne"}
}

_m_side_kind(subj, check, side) := _m_kind(o) if {
	not "within" in object.keys(check)
	check.cmp in {"eq", "ne"}
	side == check.left
	_basic_form(check.left) != "literal"
	o := _m_side_value(subj, check.right)
}

_m_side_kind(subj, check, side) := _m_kind(o) if {
	not "within" in object.keys(check)
	check.cmp in {"eq", "ne"}
	side == check.right
	_basic_form(check.left) == "literal"
	o := _m_side_value(subj, check.left)
}

_m_fits_kind(v, k) if _m_kind(v) == k
