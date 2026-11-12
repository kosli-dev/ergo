package ergo

import rego.v1

_entry_ref(entry, req) := object.union(_entry_ref_of(entry, req), _row_in)

_entry_ref_of(entry, req) := {"type": _subject_type_of(req), "id": entry.key} if "key" in object.keys(entry)

_entry_ref_of(entry, req) := _subject_ref(entry.subject, req) if {
	not "key" in object.keys(entry)
	not _scoped(req)
}

_entry_ref_of(entry, req) := r if {
	not "key" in object.keys(entry)
	_scoped(req)
	s := _scope_of(req, entry.subject)
	r := _subject_ref(entry.subject, req) with input as s
}

_subject_ref(subj, req) := {
	"type": _subject_type_of(req),
	"id": _subject_id(subj, req),
}

_subject_id(subj, req) := _value_at(subj, _id_of(req)) if {
	is_object(subj)
	is_array(_id_of(req))
}

_subject_id(subj, _) := subj if not is_object(subj)

_absent := {"ergo/absent": set()}

default _value_at(_, _) := null

_value_at(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, _plain_keys(path), null)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_field(subj, path) := v if {
	is_object(subj)
	_plain_path(path)
	v := object.get(subj, _plain_keys(path), _absent)
	not is_object(v)
} else := v if {
	v := _resolved(subj, path)
	v != _absent
}

_resolved(subj, path) := object.get(subj, _plain_keys(path), _absent) if {
	is_object(subj)
	_plain_path(path)
} else := _read_from(_start_of(subj, path), _keys_in(subj, path))

_plain_keys(path) := [_key(seg) | some seg in path]

_plain_path(path) if {
	is_array(path)
	not _named(path)
	every seg in path {
		not is_object(seg)
	}
}

_read_from(start, keys) := _read_at(start, keys, [i | some i, seg in keys; is_object(seg)]) if is_object(start)

_read_from(start, []) := start

_read_from(start, keys) := object.get({"start": start}, array.concat(["start"], keys), _absent) if {
	is_array(start)
	count(keys) > 0
	every seg in keys {
		not is_object(seg)
	}
}

_read_at(start, keys, []) := object.get(start, keys, _absent)

default _named(_) := false

_named(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "$")
}

default _builtin(_) := false

_builtin(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "$$")
	not _parent_name(path[0])
}

_start_of(subj, path) := subj if not _named(path)

_start_of(_, path) := data.ergo_document if path[0] == "$$input"

_start_of(_, path) := data.ergo_document if path[0] == "$$input[]"

_start_of(_, path) := data.ergo_params if path[0] in _params_starts

_start_of(_, path) := input["ergo/names"][substring(path[0], 1, -1)] if {
	_named(path)
	not _builtin(path)
	not _part_start(path)
}

_start_of(subj, path) := subj if {
	_subject_part(path)
	_part_of(path).old == false
}

_start_of(_, path) := input["ergo/names"]["ergo/subject"] if {
	_subject_part(path)
	_part_of(path).old == true
}

_start_of(_, path) := input["ergo/names"][_part_of(path).of] if {
	_part_start(path)
	not _subject_part(path)
}

default _part_start(_) := false

_part_start(path) if {
	is_array(path)
	is_string(path[0])
	startswith(path[0], "${\"alias\":")
	json.is_valid(substring(path[0], 1, -1))
	m := json.unmarshal(substring(path[0], 1, -1))
	is_object(m)
	object.keys(m) == {"alias", "n", "of", "old"}
}

_part_of(path) := json.unmarshal(substring(path[0], 1, -1))

default _subject_part(_) := false

_subject_part(path) if {
	_part_start(path)
	_part_of(path).of == null
}

default _old_subject_part(_) := false

_old_subject_part(path) if {
	_subject_part(path)
	_part_of(path).old == true
}

default _at_ctx := {}

_at_ctx := input["ergo/names"]["$at"] if is_object(input["ergo/names"]["$at"])

default _doc_at := ""

_doc_at := _at_ctx.doc if is_string(_at_ctx.doc)

default _subject_at := "~~"

_subject_at := _at_ctx.subject if is_string(_at_ctx.subject)

default _parent_ats := {}

_parent_ats := _at_ctx.names if is_object(_at_ctx.names)

_name_at(name) := _parent_ats[name]

_row_input(at) := {"ergo/names": {"$at": {"names": _parent_ats, "subject": at}}}

_start_at(path) := _subject_at if not _named(path)

_start_at(path) := "" if path[0] == "$$input"

_start_at(path) := "" if path[0] == "$$input[]"

_start_at(path) := "$params:" if path[0] in _params_starts

_start_at(path) := _name_at(substring(path[0], 1, -1)) if {
	_named(path)
	not _builtin(path)
	not _part_start(path)
}

_start_at(path) := _subject_at if _subject_part(path)

_start_at(path) := _name_at(_part_of(path).of) if {
	_part_start(path)
	not _subject_part(path)
}

_escaped(k) := replace(replace(k, "~", "~0"), "/", "~1") if is_string(k)

_escaped(k) := format_int(k, 10) if is_number(k)

_probe(start, keys) := object.get(start, keys, _absent) if is_object(start)

_probe(start, keys) := object.get({"v": start}, array.concat(["v"], keys), _absent) if not is_object(start)

_reached(start, keys) := max({0} | {i |
	count(keys) > 0
	some i in numbers.range(1, count(keys))
	_probe(start, array.slice(keys, 0, i)) != _absent
})

_pointer(base, start, keys) := _joined(base, keys) if _probe(start, keys) != _absent

else := _joined(base, array.slice(keys, 0, _reached(start, keys)))

_resolved_prefix(subj, steps) := ks if {
	read := {i: k | some i, seg in steps; k := _field_step_key(subj, seg)}
	missing := {i | some i, _ in steps; not i in object.keys(read)}
	n := min(missing | {count(steps)})
	ks := [read[i] | some i in numbers.range(0, n - 1); n > 0]
}

_leading_keys(subj, path) := _resolved_prefix(subj, _path_steps(path))

_starts_group(_, 0)

_starts_group(sorted, j) if {
	j > 0
	sorted[j][0] != sorted[j - 1][0]
}

_number_input(name, value, inputs) := {"name": name, "value": value, "locations": _first_seen([l | some i in inputs; some l in i.locations])}

_locations_of(subj, path) := [at] if at := _at(subj, path)

else := []

_at(subj, path) := _joined(_subject_at, keys) if {
	is_object(subj)
	_plain_path(path)
	keys := _plain_keys(path)
	object.get(subj, keys, _absent) != _absent
} else := _pointer(_subject_at, subj, _plain_keys(path)) if {
	is_object(subj)
	_plain_path(path)
} else := _pointer(_start_at(path), start, _leading_keys(subj, path)) if {
	start := _start_of(subj, path)
}

_path_input(subj, path) := {"name": _input_name(path), "value": _value_at(subj, path), "locations": [at]} if at := _at(subj, path)

else := {"name": _input_name(path), "value": _value_at(subj, path), "locations": []}

_input_name(path) := _path_name(path) if not _has_parents

_input_name(path) := _with_dot(_path_name(path), _dot_kept(path)) if _has_parents

default _has_parents := false

_has_parents if count(_parent_names) > 0

_with_dot(name, false) := name

_with_dot(name, true) := concat("", [at, ".", trim_prefix(substring(name, count(at), -1), ".")]) if at := regex.find_all_string_submatch_n(`^(?:item [1-9][0-9]* of )?`, name, 1)[0][0]

default _dot_kept(_) := false

_dot_kept(path) if {
	is_string(path[0])
	_ := _parent_names[path[0]]
}

_dot_kept(path) if {
	_string_literal(path[0])
	_ := _parent_names[path[0].literal]
}

_merged_inputs(inputs) := [object.union(_with_part({"name": t[0], "value": t[1]}, t[2]), {"locations": t[3]}) | some t in sort({[i.name, i.value, object.get(i, "part", null), i.locations] | some i in inputs})]

_with_part(entry, null) := entry

_with_part(entry, part) := object.union(entry, {"part": part}) if part != null

default _off_subject(_) := false

_off_subject(path) if {
	_named(path)
	not _subject_part(path)
}

_visible(path) := array.concat(_visible_root(_part_of(path)), array.slice(path, 1 + max([_part_of(path).n, 0]), count(path))) if _part_start(path)

_visible(path) := path if not _part_start(path)

_visible_root(m) := [m.alias] if {
	m.of == null
	m.n > 0
}

_visible_root(m) := [{"plain": m.alias}] if {
	m.of == null
	m.n == 0
}

_visible_root(m) := [] if {
	m.of == null
	m.n < 0
}

_visible_root(m) := [concat("", ["$", m.of]), m.alias] if {
	m.of != null
	m.n >= 0
}

_visible_root(m) := [concat("", ["$", m.of])] if {
	m.of != null
	m.n < 0
}

_unusable_mark := {"ergo/unusable": set()}

_walk_stop(w) := [] if w.walked != set()

_walk_stop(w) := [{"path": e.c, "item": e.c, "cause": _walk_stop_state(e.v), "value": _walk_value(e.v, e, w), "at": _walk_at(w, e), "msg": _m_walk_kind(e.v)} | e := _walk_stopped_at(w.trail)] if w.walked == set()
