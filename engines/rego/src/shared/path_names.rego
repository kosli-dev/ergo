package ergo

import rego.v1

_ref_name(path) := "<invalid ref>" if not _builtin(path)

_written(x) := x.literal if _is_literal(x)

_written(x) := x if {
	not _is_ref(x)
	not _is_literal(x)
}

_field_path_name(path) := concat(".", [_segment_name(path[i]) | some i in _names(path)])

_path_name([]) := "the subject"

_path_name(path) := _visible_path_name(_visible(path), "the subject") if path != []

_input_path_name([]) := "$input"

_input_path_name(path) := _visible_path_name(_visible(path), "$input") if path != []

_visible_path_name(path, root) := concat("", ["item ", _literal_text(path[count(path) - 1] + 1), " of ", _rooted_steps_name(array.slice(path, 0, count(path) - 1), root)]) if {
	is_array(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := concat("", ["item ", _literal_text(path[0] + 1), " of ", root]) if {
	is_array(path)
	count(path) == 1
	_index_step(path[0])
} else := _rooted_steps_name(path, root)

_ref_name(path) := concat("", ["item ", _literal_text(path[count(path) - 1] + 1), " of ", _plain_steps_name(array.slice(path, 0, count(path) - 1))]) if {
	_builtin(path)
	count(path) > 1
	_index_step(path[count(path) - 1])
} else := _plain_steps_name(path) if _builtin(path)

_index_step(s) if {
	is_number(s)
	_is_key(s)
}

_steps_name(path) := _rooted_steps_name(path, "the subject")

_rooted_steps_name(path, root) := concat("", array.concat(_it_root(visible, root), [_step_name(i, visible[i]) | some i in _names(visible)])) if visible := _visible(path)

_it_root(visible, root) := [root] if _index_step(visible[0])

_it_root(visible, _) := [] if not _index_step(visible[0])

_plain_steps_name(path) := concat("", [_plain_step_name(i, path[i]) | some i in _names(path)])

_step_name(i, p) := _plain_step_name(i, p) if _nameable_step(p)

_step_name(i, p) := concat("", [" named by ", _ref_name(p.ref)]) if {
	i > 0
	_named_by(p)
}

_step_name(i, p) := concat("", [" named by ", _s_key_text(p.named_by)]) if {
	i > 0
	_name_step(p)
}

_step_name(i, p) := concat("", [" named by ", _fk_text(p)]) if {
	i > 0
	_field_step(p)
}

_step_name(i, p) := concat("", [_step_dot(i), _segment_name(p)]) if {
	not _nameable_step(p)
	not _is_ref(p)
	not _name_step_after(i, p)
}

_name_step_after(i, p) if {
	i > 0
	_name_step(p)
}

_name_step_after(i, p) if {
	i > 0
	_field_step(p)
}

_nameable_step(p) if is_string(p)

_nameable_step(p) if _index_step(p)

_nameable_step(p) if _parent_step_form(p)

_nameable_step(p) if _plain_step_form(p)

_nameable_step(p) if {
	_is_literal(p)
	is_string(p.literal)
}

_plain_step_name(0, "$$input") := "$input"

_plain_step_name(0, "$$input[]") := "$input"

_plain_step_name(0, "$$params") := "$params"

_plain_step_name(0, "$$params[]") := "$params"

_plain_step_name(0, step) := step if {
	is_string(step)
	startswith(step, "$")
	not step in {"$$input", "$$input[]", "$$params", "$$params[]", "$input", "$params"}
	not _parent_name(step)
	not _for_alias_step(step)
}

_plain_step_name(0, step) := concat("", ["\u0002", substring(step, 1, -1)]) if {
	is_string(step)
	_for_alias_step(step)
	not _parent_name(step)
}

_for_alias_step(step) if {
	startswith(step, "$")
	input["ergo/names"]["$at"].names[substring(step, 1, -1)]
}

_plain_step_name(0, step) := _s_parent_key(substring(step, 1, -1)) if _parent_name(step)

_plain_step_name(0, step) := step.plain if _plain_step_form(step)

_plain_step_form(p) if {
	is_object(p)
	object.keys(p) == {"plain"}
	is_string(p.plain)
}

_s_parent_key(key) := _json_text(key) if key in _s_words

else := _s_key_text(key)

_parent_name(step) if {
	is_string(step)
	startswith(step, "$")
	some p, _ in _parent_names
	step == concat("", ["$", p])
}

_plain_step_name(0, step) := concat("", [_s_dot(step, "left"), _s_key_text(step)]) if {
	is_string(step)
	not startswith(step, "$")
}

_plain_step_name(i, step) := concat("", [".", _s_key_text(step)]) if {
	i > 0
	is_string(step)
}

_plain_step_name(0, step) := concat("", [_literal_dot(step.literal), _s_key_text(step.literal)]) if _string_literal(step)

_literal_dot(key) := "." if not startswith(key, "$")

_literal_dot(key) := _s_dot(key, "left") if startswith(key, "$")

_plain_step_name(0, step) := _s_parent_key(step.parent) if _parent_step_form(step)

_parent_step_form(p) if {
	is_object(p)
	object.keys(p) == {"parent"}
	is_string(p.parent)
}

_plain_step_name(i, step) := concat("", [".", _s_key_text(step.literal)]) if {
	i > 0
	_string_literal(step)
}

_plain_step_name(_, step) := concat("", ["[", _literal_text(step), "]"]) if _index_step(step)

_step_dot(i) := "." if i > 0

_string_literal(p) if {
	_is_literal(p)
	is_string(p.literal)
}

_named_by(p) if {
	_is_ref(p)
	_builtin(p.ref)
	count(p.ref) == 2
	is_string(p.ref[1])
}

_segment_name(p) := _key_name(p) if not is_object(p)

_segment_name(p) := _key_name(p.literal) if _is_literal(p)

_segment_name(p) := concat("", ["[", concat(" and ", sort([concat("", [_key_name(k), "==", _value_text(v)]) | some k, v in p.where])), "]"]) if {
	is_object(p)
	not _is_literal(p)
	not _is_ref(p)
}

_first_dollar_key(0, k) if {
	is_string(k)
	startswith(k, "$")
}

_key_name(k) := k if _plain_key(k)

_key_name(k) := _json_text(k) if {
	is_string(k)
	not _plain_key(k)
}

_key_name(k) := _literal_text(k) if {
	is_number(k)
	_is_key(k)
}

_key_name(k) := "<invalid step>" if {
	not is_string(k)
	not _is_key(k)
}

_plain_key(k) if {
	is_string(k)
	regex.match(`^[A-Za-z_$][A-Za-z0-9_$-]*$`, k)
}

_plain_numbers(v) := _plain_json(v, json.marshal(v))

_plain_json(v, text) := v if not regex.match(`[:,\[]\s*(?:-?[0-9]+(?:\.[0-9]+)?[eE]|-?[0-9]+\.[0-9]*0\s*[,\]}]|-0\s*[,\]}])`, text)

else := json.unmarshal(concat("", [_plain_part(m) | some m in regex.find_all_string_submatch_n(`(-?[0-9][0-9.eE+-]*)|(?:"(?:[^"\\]|\\.)*"|[^"0-9-])+`, text, -1)]))

_plain_part(m) := m[0] if m[1] == ""

_plain_part(m) := _plain_number(m[1]) if m[1] != ""

_plain_number(t) := t if regex.match(`^(?:0|-?[1-9][0-9]*|-?(?:0|[1-9][0-9]*)\.[0-9]*[1-9])$`, t)

else := t if not _fits_a_float(json.unmarshal(t))

else := _number_text(t)
