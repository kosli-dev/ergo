package ergo

import rego.v1

_keys_of(path) := ks if {
	is_array(path)
	not _named(path)
	ks := [_step_key(seg) | some seg in path]
	count(ks) == count(path)
}

_keys_of(path) := ks if {
	_named(path)
	rest := array.slice(path, 1, count(path))
	ks := [_step_key(seg) | some seg in rest]
	count(ks) == count(rest)
}

_step_key(seg) := _key(seg.literal) if _is_literal(seg)

_step_key(seg) := _key(v) if {
	_is_ref(seg)
	v := _ref_read(seg.ref)
	is_string(v)
}

_step_key(seg) := _key(seg) if {
	not _is_literal(seg)
	not _is_ref(seg)
	not _name_step(seg)
	not _field_step(seg)
}

_step_key(seg) := v if {
	_name_step(seg)
	v := input["ergo/names"][seg.named_by]
	is_string(v)
}

_name_step(seg) if {
	is_object(seg)
	object.keys(seg) == {"named_by"}
	is_string(seg.named_by)
}

_field_step(seg) if {
	is_object(seg)
	object.keys(seg) == {"named_by_field"}
	is_string(seg.named_by_field)
}

_has_field_step(path) if {
	is_array(path)
	some seg in path
	_field_step(seg)
}

_keys_in(_, path) := _keys_of(path) if not _has_field_step(path)

_keys_in(subj, path) := ks if {
	_has_field_step(path)
	steps := _path_steps(path)
	ks := [k | some seg in steps; k := _field_step_key(subj, seg)]
	count(ks) == count(steps)
}

_root_key := "\u0002"

_subject_key := "\u0003"

_fk(seg) := substring(seg.named_by_field, count(_root_key), -1) if startswith(seg.named_by_field, _root_key)

else := split(seg.named_by_field, _subject_key)[2] if startswith(seg.named_by_field, _subject_key)

else := seg.named_by_field

_fk_text(seg) := concat(".", [_s_key_text(split(seg.named_by_field, _subject_key)[1]), _s_key_text(_fk(seg))]) if startswith(seg.named_by_field, _subject_key)

else := _s_key_text(_fk(seg))

_from_root(seg) if startswith(seg.named_by_field, _root_key)

_from_root(seg) if startswith(seg.named_by_field, _subject_key)

_fb(_, seg) := input["ergo/names"]["ergo/subject"] if _from_root(seg)

_fb(subj, seg) := subj if not _from_root(seg)

_path_steps(path) := array.slice(path, 1, count(path)) if _named(path)

_path_steps(path) := path if not _named(path)

_field_step_key(subj, seg) := v if {
	_field_step(seg)
	is_object(_fb(subj, seg))
	v := _fb(subj, seg)[_fk(seg)]
	is_string(v)
}

_field_step_key(_, seg) := _step_key(seg) if not _field_step(seg)

_is_key(v) if is_string(v)

_is_key(v) if {
	is_number(v)
	not _out_of_range(v)
	v >= 0
	v <= 9007199254740991
	v == floor(v)
}

_key(v) := floor(v) if {
	is_number(v)
	_is_key(v)
} else := v

default _is_ref(_) := false

_is_ref(x) if {
	is_object(x)
	object.keys(x) == {"ref"}
}

default _is_literal(_) := false

_is_literal(x) if {
	is_object(x)
	object.keys(x) == {"literal"}
}

_arg(x) := v if {
	_is_ref(x)
	v := _ref_read(x.ref)
	v != _absent
	v != null
}

_arg(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
}
