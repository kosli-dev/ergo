package ergo

import rego.v1

default _check_passed(_, _, _) := false

_check_passed(check, subj, "") if _op_passed(check, subj)

_read_paths(check) := [side | some side in [check.left, check.right]; is_array(side)] if _two_sided(check)

_read_paths(check) := [check.path] if {
	not _two_sided(check)
	check.path
}

_read_state(subj, path) := _plain_read_state(subj, path, object.get(subj, _plain_keys(path), _absent)) if {
	is_object(subj)
	_plain_path(path)
} else := _any_read_state(subj, path)

_plain_read_state(subj, path, v) := "value" if {
	v != _absent
	v != null
}

else := "null" if v == null

else := "null" if {
	count(path) > 1
	keys := _plain_keys(path)
	some j, _ in keys
	j > 0
	object.get(subj, array.slice(keys, 0, j), _absent) == null
}

else := "unusable" if _blocked(subj, path)

else := "absent"

default _path_read_state(_, _) := "absent"

_path_read_state(subj, path) := "not_an_object" if _starts_at_non_object(subj, path)

_starts_at_non_object(subj, path) if {
	start := _start_of(subj, path)
	not is_object(start)
	not _reads_itself(path)
	not _position_first(path)
	not _params_not_given(path)
	not _field_unusable_after_read(subj, path)
}

_field_unusable_after_read(subj, path) if {
	is_object(subj)
	some i, seg in path
	_field_step(seg)
	_read_before_field(_resolved(subj, array.slice(path, 0, i)))
	not is_string(object.get(_fb(subj, seg), _fk(seg), null))
}

_reads_itself(path) if _keys_of(path) == []

_reads_subject(path) if path == []

_reads_subject(path) if {
	_subject_part(path)
	_part_of(path).n == 0
	array.slice(path, 1, count(path)) == []
}

_reads_subject(path) if {
	_subject_part(path)
	_part_of(path).n == 0
	_index_step(path[1])
}

_position_first(path) if _index_step(_keys_of(path)[0])

_position_first(path) if {
	not _builtin(path)
	_has_field_step(path)
	_index_step(_step_key(_path_steps(path)[0]))
}

_any_read_state(subj, path) := s if {
	s := _name_step_state(path)
} else := s if {
	s := _path_read_state(subj, path)
	s != "absent"
} else := _null_or_absent(subj, path)

_null_or_absent(subj, path) := "null" if {
	_null_stops(subj, path)
	not _starts_at_non_object(subj, path)
} else := "null" if {
	some step in path
	is_number(step)
	_position_first(path)
	not path[0] in _params_starts
	_start_of(subj, path) == null
	not _ref_step_flawed(path)
} else := "absent"

_null_stops(subj, path) if {
	j := _null_stop_at(subj, path)
	_field_step_key(subj, path[j])
	not _ref_step_flawed(path)
}

_null_stop_at(subj, path) := min({i | some i, _ in path; i > k; _resolved(subj, array.slice(path, 0, i)) == null}) if k := _first_key_at(path)

_ref_step_flawed(path) if {
	some seg in path
	_ref_step_flaw(seg)
}

_path_read_state(subj, path) := _field_step_state(subj, path)

_field_step_state(subj, path) := "not_an_object" if {
	_has_field_step(path)
	not is_object(_fb(subj, path[_first_field_step(path)]))
} else := s if {
	prefix := array.slice(path, 0, _first_field_step(path))
	not _read_before_field(_resolved(subj, prefix))
	not _starts_at_non_object(subj, path)
	s := _state_before_field(subj, prefix)
} else := "null" if {
	some i, seg in path
	_field_step(seg)
	_read_before_field(_resolved(subj, array.slice(path, 0, i)))
	_fb(subj, seg)[_fk(seg)] == null
} else := "unusable" if {
	some i, seg in path
	_field_step(seg)
	_read_before_field(_resolved(subj, array.slice(path, 0, i)))
	v := _fb(subj, seg)[_fk(seg)]
	not is_string(v)
}

_first_field_step(path) := min({i | some i, seg in path; _field_step(seg)})

_state_before_field(subj, prefix) := "unusable" if {
	start := _start_of(subj, prefix)
	is_object(start)
	_blocked(start, _keys_in(subj, prefix))
}

else := "unusable" if {
	not _builtin(prefix)
	_position_first(prefix)
	start := _start_of(subj, prefix)
	is_array(start)
	_blocked(start, _keys_in(subj, prefix))
}

else := "absent"

_read_before_field(v) if v != _absent

_walk_read_state(subj, path) := _worst_of(flaws) if {
	flaws := {f | some seg in path; f := _ref_step_flaw(seg)}
	flaws != set()
} else := _key_state(object.get(_fb(subj, path[i]), _fk(path[i]), _absent)) if {
	i := _bad_field_at(subj, path)
	is_object(_fb(subj, path[i]))
	_walks_before_field(subj, array.slice(path, 0, i))
} else := "null" if {
	i := _bad_field_at(subj, path)
	is_object(_fb(subj, path[i]))
	_null_before_field(subj, array.slice(path, 0, i))
} else := _read_state(subj, path)

_ref_step_flaw(seg) := "unusable" if {
	_is_ref(seg)
	_ref_state(seg.ref) == "value"
	not is_string(_ref_read(seg.ref))
} else := s if {
	_is_ref(seg)
	s := _ref_state(seg.ref)
	s != "value"
}

_bad_field_at(subj, path) := min({j | some j, seg in path; _field_step(seg); not is_string(object.get(_fb(subj, seg), _fk(seg), null))})

_null_prefix_fails(item, subj) := array.concat(w.fails, _walk_stop(w)) if {
	is_object(subj)
	prefix := array.slice(item.path, 0, _bad_field_at(subj, item.path))
	_null_before_field(subj, prefix)
	p := object.union(item, {"path": prefix})
	w := _walk(_walk_start(p, subj), _walk_keys(p, subj), false)
} else := []

_for_null_fails(item, subj, names) := fails if {
	fails := _null_prefix_fails(item, subj) with input as {"ergo/names": names}
}

_null_before_field(subj, prefix) if {
	some j, _ in prefix
	j > _first_key_at(prefix)
	_resolved(subj, array.slice(prefix, 0, j)) == null
}

_first_key_at(path) := 1 if _named(path)

else := 0

_walks_before_field(subj, prefix) if {
	some i, seg in prefix
	is_string(seg)
	is_array(_resolved(subj, array.slice(prefix, 0, i)))
}

_key_state(v) := "absent" if v == _absent

else := "null" if v == null

else := "unusable"

_name_step_state(path) := "null" if {
	_has_name_step(path)
	some step in path
	_name_step(step)
	input["ergo/names"][step.named_by] == null
} else := "unusable" if {
	_has_name_step(path)
	some step in path
	_name_step(step)
	not is_string(input["ergo/names"][step.named_by])
}

_path_read_state(subj, path) := "null" if {
	_resolved(subj, path) == null
	not _params_null(path)
}

_path_read_state(subj, path) := "unusable" if {
	start := _start_of(subj, path)
	is_object(start)
	_blocked(start, _keys_in(subj, path))
}

_path_read_state(subj, path) := "unusable" if {
	not _builtin(path)
	_position_first(path)
	start := _start_of(subj, path)
	is_array(start)
	_blocked(start, _keys_in(subj, path))
}

_path_read_state(_, path) := "unusable" if {
	path[0] == "$$input"
	_position_first(path)
	is_array(data.ergo_document)
	_blocked(data.ergo_document, _keys_of(path))
}

_path_read_state(subj, path) := "unusable" if {
	_position_first(path)
	start := _start_of(subj, path)
	start != null
	not is_array(start)
	not is_object(start)
}

_path_read_state(subj, path) := "value" if {
	v := _resolved(subj, path)
	v != _absent
	v != null
}

_is_collection(v) if is_array(v)

_is_collection(v) if is_object(v)

_cause_precedence := ["not_an_object", "ambiguous", "unusable", "absent", "null"]

_worst_read(subj, check) := _read_cause(subj, check, refs, {_used_ref_state(check, r) | some r in refs}) if refs := _check_refs(check)

_read_cause(_, _, _, states) := _worst_of(states) if {
	some state in states
	state != "value"
}

_read_cause(_, _, refs, states) := "value" if {
	states - {"value"} == set()
	some r in refs
	_ref_failed_walk(r)
}

_read_cause(subj, check, refs, states) := _worst_or_value(_check_states(check, subj)) if {
	states - {"value"} == set()
	not _any_failed_walk(refs)
}

_any_failed_walk(refs) if {
	some r in refs
	_ref_failed_walk(r)
}

_worst_or_value(states) := c if {
	c := _worst_of(states)
} else := "value"

_check_states(check, subj) := _answered(check, subj, {_state_at(check, subj, p) | some p in _read_paths(check)}) | _unusable_states(check, subj) if {
	not _list_flawed(check, subj)
}

_check_states(check, subj) := _list_flaw(check, subj) if {
	_list_flawed(check, subj)
}

_group_cause(causes) := "value" if {
	"missing" in causes
} else := _worst_or_value(causes)

_leaf_cause(leaf, x) := "satisfied" if {
	_leaf_passed(leaf, x)
} else := "missing" if {
	_asks_presence(leaf, x)
	_read_state(x, leaf.path) in {"absent", "null"}
} else := _worst_or_value(_list_flaw(leaf, x)) if {
	_list_flawed(leaf, x)
} else := _worst_or_value({_state_at(leaf, x, p) | some p in _leaf_paths(leaf)} | _unusable_states(leaf, x))

_answered(check, x, states) := {_presence_state(s) | some s in states} if _asks_presence(check, x)

_answered(check, x, states) := states if not _asks_presence(check, x)

default _asks_presence(_, _) := false

_asks_presence(check, x) if {
	check.op == "present"
	_keys_in(x, check.path)
	_ := _start_of(x, check.path)
	not _params_not_given(check.path)
}

_params_not_given(path) if {
	path[0] in _params_starts
	not is_object(data.ergo_params)
}

_presence_state(s) := "missing" if s in {"absent", "null"}

_presence_state(s) := s if not s in {"absent", "null"}

default _unreadable_ref(_) := false

_unreadable_ref(check) if {
	some r in _check_refs(check)
	_used_ref_state(check, r) != "value"
}

_worst_of(states) := _cause_precedence[i] if {
	i := min([j |
		some j, c in _cause_precedence
		c in states
	])
}

_row_cause(_, _, flaw) := flaw if flaw != ""

_row_cause(check, subj, "") := c if {
	_derived_once(check)
	c := _derived_eval(check, subj).cause
} else := _readable_cause(check, subj)

_readable_cause(check, subj) := "satisfied" if _op_passed(check, subj)

else := _worst_read(subj, check)

_check_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
}

_step_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
	count(p) >= 2
	is_number(p[count(p) - 1])
}

_used_ref_state(check, r) := "not_an_object" if {
	_key_of_list_input_path(check, r)
} else := "unusable" if {
	_wrong_step(check, r)
} else := "not_an_object" if {
	_one_input_ref(check, r)
	is_array(data.ergo_document)
} else := "not_an_object" if {
	_input_key_ref(r)
	r in _step_refs(check)
	_plain_check(check)
} else := _ref_state(r)

_key_of_list_input_path(check, r) if {
	is_array(data.ergo_document)
	_key_of_input_path(check, r)
}

_key_of_input_path(check, r) if {
	walk(check, [q, p])
	is_array(p)
	count(p) > 1
	p[0] == "$$input"
	not _index_step(p[1])
	{"ref": r} in p
	not _under_literal(check, q)
	_plain_check(check)
}

_plain_check(check) if {
	is_object(check)
	check["$plain"] == true
}

_input_one_root(c, p) if _one_input_ref(c, p)

_input_one_root(_, p) if {
	is_array(p)
	count(p) > 1
	p[0] == "$$input"
	not _index_step(p[1])
}

_one_input_ref(check, r) if {
	check.op in {"includes", "excludes"}
	_is_ref(object.get(check, "value", null))
	check.value.ref == r
	r[0] == "$$input"
	is_string(r[1])
}

_wrong_step(check, r) if {
	r in _step_refs(check)
	_ref_state(r) == "value"
	not is_string(_ref_read(r))
}

_under_literal(check, p) if {
	some i, seg in p
	seg == "literal"
	walk(check, [q, w])
	q == array.slice(p, 0, i)
	_is_literal(w)
}

default _ref_state(_) := "absent"

_ref_state(r) := _ref_state_read(r) if not _params_null(r)

_input_key_ref(r) if {
	r[0] == "$$input"
	is_array(data.ergo_document)
	count(r) > 1
	is_string(r[1])
}

_params_null(r) if {
	r[0] in _params_starts
	data.ergo_params == null
}

_ref_state_read(r) := "null" if _ref_read(r) == null

_ref_state_read(r) := "null" if {
	_ref_read(r) == _absent
	not _ref_walks(r)
	_ref_null_partway(r)
}

_ref_null_partway(r) if {
	some j, _ in r
	j > 1
	_ref_read(array.slice(r, 0, j)) == null
}

_ref_state_read(r) := "unusable" if {
	_ref_read(r) == _absent
	not _ref_walks(r)
	_blocked(_start_of(null, r), [seg | some seg in array.slice(r, 1, count(r))])
}

_ref_state_read(r) := _ref_walk(r).state if {
	_ref_walks(r)
	_ref_walk(r).failed
}

_ref_state_read(r) := "value" if {
	v := _ref_read(r)
	v != _absent
	v != null
}

default _ref_shown(_) := null

_ref_shown(r) := v if {
	v := _ref_read(r)
	v != _absent
}

_ref_shown(r) := _ref_walk(r).value if {
	_ref_walks(r)
	_ref_walk(r).failed
}

_ref_label(r) := _ref_walk(r).name if _ref_walks(r)

_ref_label(r) := _ref_name(r) if not _ref_walks(r)

_ref_inputs(check) := _ref_entries(_check_refs(check))

_ref_entries(refs) := [{"name": pair[0], "value": pair[1], "locations": pair[2]} | some pair in sort({[_ref_label(r), _ref_shown(r), _ref_locations(r)] | some r in refs})]

_input_ref_inputs(conds) := _ref_entries({r |
	some c in conds
	c.op in _right_ref_ops
	some r in _check_refs(object.remove(c, ["path"]))
	r[0] in {"$$input", "$$input[]"}
})

_ref_locations(r) := [_ref_at(r)] if {
	_builtin(r)
	not _ref_walks(r)
}

_ref_locations(r) := _ref_walk(r).locations if _ref_walks(r)

_ref_locations(r) := [] if not _builtin(r)

_ref_at(r) := _pointer(_start_at(r), start, [_key(seg) | some seg in array.slice(r, 1, count(r))]) if {
	start := _start_of(null, r)
}

_verdict_cause(passed) := "satisfied" if passed

_verdict_cause(passed) := "value" if not passed

_applies_cause(_, true) := "satisfied"

_applies_cause(evals, false) := _scope_cause({e.cause | some e in evals; not e.passed})

_scope_cause(causes) := "value" if {
	"missing" in causes
} else := "value" if {
	causes == {"value"}
} else := _worst_of(causes)

_filter_cause(check, subj, flaw) := "missing" if _answers_presence(check, subj, flaw)

_filter_cause(check, subj, flaw) := _row_cause(check, subj, flaw) if not _answers_presence(check, subj, flaw)

default _answers_presence(_, _, _) := false

_answers_presence(check, subj, "") if {
	check.op == "present"
	_keys_in(subj, check.path)
	_ := _start_of(subj, check.path)
	not _unreadable_ref(check)
	not _params_not_given(check.path)
	_read_state(subj, check.path) in {"absent", "null"}
}
