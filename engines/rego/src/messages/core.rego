package ergo

import rego.v1

_m_print(v) := _m_text(v) if is_string(v)

_m_print(v) := _m_item(v) if {
	not is_string(v)
	not is_array(v)
}

_m_print_at(v, at, row) := _m_print(v) if {
	not is_number(v)
	not is_array(v)
	_ = at
	_ = row
}

_m_print_at(v, _, _) := _m_number_text(v, json.marshal(v)) if is_number(v)

_m_print_at(v, _, _) := concat("", ["[", concat(", ", [_m_item_of(x, [json.marshal(x) | is_number(x)]) | some x in array.slice(v, 0, 3)]), ", and ", _literal_text(count(v) - 3), " more]"]) if {
	is_array(v)
	count(v) > 3
}

_m_print_at(v, _, _) := concat("", ["[", concat(", ", [_m_item_of(x, [json.marshal(x) | is_number(x)]) | some x in v]), "]"]) if {
	is_array(v)
	count(v) <= 3
}

_m_item_of(x, [t]) := _m_number_text(x, t)

_m_item_of(x, []) := _m_item(x)

_m_number_text(v, _) := "<number out of range>" if _out_of_range(v)

_m_number_text(v, t) := _number_text(t) if not _out_of_range(v)

_m_item(v) := _m_text(v) if is_string(v)

_m_item(true) := "true"

_m_item(false) := "false"

_m_item(null) := "null"

_m_item(v) := _literal_text(v) if is_number(v)

_m_item(v) := _literal_text(v) if is_array(v)

_m_item(v) := _m_object_item(v) if is_object(v)

_m_object_item(v) := _m_keys_text(v) if _m_long_object(v)

else := _m_short_object(v, _m_object_text(v))

_m_long_object(v) if sum([n | some k, _ in v; is_string(k); n := count(k) + 5]) > 80

_m_short_object(_, t) := t if count(t) <= 80

_m_short_object(v, t) := _m_keys_text(v) if count(t) > 80

_m_keys_text(v) := concat("", ["an object with ", _literal_text(count(v)), " ", _m_keys_word(count(v))])

_m_keys_word(1) := "key"

_m_keys_word(n) := "keys" if n != 1

_m_object_text(v) := concat("", ["{", concat(", ", [concat("", [_m_quoted(k), ": ", _m_flat(v[k])]) | some k in sort(object.keys(v))]), "}"]) if _m_flat_object(v)

else := _literal_text(v)

_m_flat_object(v) if {
	every k, x in v {
		is_string(k)
		_m_flat_value(x)
	}
}

_m_flat_value(x) if is_string(x)

_m_flat_value(x) if is_boolean(x)

_m_flat_value(null)

_m_flat(x) := _m_quoted(x) if is_string(x)

_m_flat(true) := "true"

_m_flat(false) := "false"

_m_flat(null) := "null"

_m_text(s) := _m_quoted(s) if count(s) <= 60

_m_text(s) := concat("", [trim_suffix(_m_quoted(substring(s, 0, 60)), `"`), `…"`]) if count(s) > 60

_m_quoted(s) := _m_one_line(concat("", [`"`, s, `"`])) if not regex.match(`["\\\x00-\x1f\x7f]`, s)

_m_quoted(s) := _m_one_line(_json_text(s)) if regex.match(`["\\\x00-\x1f\x7f]`, s)

_m_one_line(t) := strings.replace_n({"\u2028": "\\u2028", "\u2029": "\\u2029", "\u0085": "\\u0085"}, t)

_m_kind(v) := "text" if is_string(v)

_m_kind(v) := "a number" if is_number(v)

_m_kind(v) := "true or false" if is_boolean(v)

_m_kind(v) := "a list" if is_array(v)

_m_kind(v) := "an object" if is_object(v)

_m_kind(null) := "null"

_m_kinds(vs) := concat(" or ", sort({_m_kind(v) | some v in vs; v != null}))

_m_list_of(vs) := concat("", ["a list of ", concat(" or ", sort({_m_plural(v) | some v in vs; v != null}))])

_m_plural(v) := "text" if is_string(v)

_m_plural(v) := "numbers" if is_number(v)

_m_plural(v) := "true or false values" if is_boolean(v)

_m_plural(v) := "lists" if is_array(v)

_m_plural(v) := "objects" if is_object(v)

_m_is(name, v) := concat("", [name, " is ", _m_print_at(v, name, null)])

_m_isnt(name, v, kind) := concat("", [name, " is ", _m_print_at(v, name, null), ", which isn't ", kind])

_m_state_word("absent") := "missing"

_m_state_word("null") := "null"

_m_sides(check) := check["$sides"] if _m_has_sides(check)

_m_sides(check) := _m_found_sides(check) if not _m_has_sides(check)

_m_has_sides(check) if is_array(check["$sides"])

_m_with_sides(check) := object.union(check, {"$sides": sides}) if {
	is_object(check)
	sides := _m_found_sides(check)
}

_message(check, subj, cause) := concat("; ", ps) if {
	cause in {"absent", "null", "unusable"}
	ps := _m_null_key_parts(subj, check)
	ps != []
} else := _m_message(_m_with_sides(_m_walked(check, subj)), subj, cause)

_m_null_key_parts(subj, check) := _once([x |
	some side in _m_key_sides(check)
	some p in _m_side_paths(side)
	is_array(p)
	_key_step_later(p)
	some x in _m_null_key_pair(subj, p)
])

_m_key_sides(check) := check["$sides"] if _m_has_sides(check)

_m_key_sides(check) := [check.left, check.right] if {
	not _m_has_sides(check)
	_two_sided(check)
}

_m_key_sides(check) := [check.path] if {
	not _m_has_sides(check)
	not _two_sided(check)
	is_array(check.path)
}

_key_step_later(p) if {
	some k, step in p
	k > 0
	is_object(step)
}

_m_null_key_pair(subj, p) := _m_said_once(concat("", [_input_name(array.slice(p, 0, j)), " is null"]), _m_key_text(subj, p[i])) if {
	i := min({k | some k, step in p; _m_key_text(subj, step)})
	i > 0
	j := min({m | some m in numbers.range(1, i); _resolved(subj, array.slice(p, 0, m)) == null})
	_input_name(array.slice(p, 0, j)) != "$params"
}

_m_said_once(first, second) := [second] if _m_aliased(first) == second

else := [first, second]

_m_key_text(subj, step) := t if {
	t := _m_key_fault(subj, step)
} else := concat("", [_m_key_name(step), " is ", _m_state_word(st)]) if {
	st := _m_key_state(subj, step)
	st in {"absent", "null"}
}

_m_walked(check, subj) := object.union(check, {"right": {"walked": check.right}}) if {
	_right_walks(check, subj)
} else := check

_m_found_sides(check) := [check.left, check.right] if _two_sided(check)

_m_found_sides(check) := array.concat([check.path], [{"ref": r} | some r in sort(_check_refs(check))]) if {
	not _two_sided(check)
	is_array(check.path)
}

_m_found_sides(check) := [{"ref": r} | some r in sort(_check_refs(check))] if {
	not _two_sided(check)
	not is_array(check.path)
}

_m_shown(subj, side) := {"name": w.name, "state": w.state, "value": w.value} if {
	_walked_side(side)
	w := _rwalk(subj, side.walked)
	not w.failed
}

_m_shown(subj, side) := {"name": w.name, "state": w.state, "value": w.value, "text": _rwalk_text(subj, side.walked)} if {
	_walked_side(side)
	w := _rwalk(subj, side.walked)
	w.failed
}

_m_shown(_, side) := {"name": _m_ref_null_name(side.ref), "state": _ref_state(side.ref), "value": _ref_shown(side.ref)} if {
	_is_ref(side)
	not _ref_failed_walk(side.ref)
}

_m_ref_null_name(r) := _ref_name(array.slice(r, 0, j)) if {
	_ref_state(r) == "null"
	j := min({i | some i, _ in r; i > 1; _ref_read(array.slice(r, 0, i)) == null})
} else := _ref_label(r)

_m_shown(_, side) := {"name": _ref_label(side.ref), "state": _ref_state(side.ref), "value": _ref_shown(side.ref), "text": _ref_walk_text(side.ref)} if {
	_is_ref(side)
	_ref_failed_walk(side.ref)
}

default _ref_failed_walk(_) := false

_ref_failed_walk(r) if {
	_ref_walks(r)
	_ref_walk(r).failed
}

_m_state_clause(s) := s.text if "text" in object.keys(s)

_m_state_clause(s) := concat("", [s.name, " is ", _m_state_word(s.state)]) if not "text" in object.keys(s)

_m_shown(subj, side) := {"name": _m_null_name(subj, side, state), "state": state, "value": object.get({"v": _value_at(subj, side)}, "v", null), "side": side} if {
	is_array(side)
	state := _read_state(subj, side)
}

_m_side_said(s, cause, _) if s.state == cause

_m_side_said(s, "absent", check) if {
	object.get(check, "op", null) == "present"
	s.state == "null"
}

_m_side_said(s, cause, check) if {
	object.get(check, "ergo/row", false) == true
	s.state != cause
	s.state in {"absent", "null"}
	is_array(object.get(s, "side", null))
	not _m_off_path(s.side)
}

_m_null_name(subj, side, "null") := _input_name(array.slice(side, 0, j)) if {
	j := min({i | some i, _ in side; i > _first_key_at(side); _resolved(subj, array.slice(side, 0, i)) == null})
} else := _input_name(array.slice(side, 0, _first_key_at(side))) if {
	_position_first(side)
	_start_of(subj, side) == null
} else := _input_name(side)

_m_null_name(_, side, state) := _input_name(side) if state != "null"

_m_shown(subj, side) := {"name": side.text, "state": "value", "value": v} if {
	_side_form(side) in {"count_of", "sum_of", "elapsed", "add", "join"}
	[v] := _side_eval(subj, side).v
}

_m_value_clauses(subj, side) := [c] if {
	s := _m_shown(subj, side)
	c := _m_value_clause(s, subj)
} else := [c | some p in [side.elapsed_from, side.elapsed_to]; c := _m_value_clause(_m_shown(subj, p), subj)] if _side_form(side) == "elapsed"

else := [c | some e in sort({x | walk(side, [_, x]); _side_form(x) == "elapsed"}); some p in [e.elapsed_from, e.elapsed_to]; c := _m_value_clause(_m_shown(subj, p), subj)] if _side_form(side) == "add"

else := []

_m_value_clause(s, subj) := concat("", [s.name, " is ", _m_print_at(s.value, s, subj)]) if {
	s.state == "value"
	not "text" in object.keys(s)
}

_m_value_clause(s, _) := s.text if {
	s.state == "value"
	"text" in object.keys(s)
}

_m_value_clause(s, _) := _m_state_clause(s) if s.state in {"absent", "null"}

_m_sources(subj, check) := _once([x | some side in _m_sides(check); some x in _m_side_sources(subj, side)])

_m_side_sources(_, side) := [_m_shown(null, side)] if _is_ref(side)

_m_side_sources(subj, side) := [_m_shown(subj, side)] if is_array(side)

_m_side_sources(subj, side) := [_m_shown(subj, side)] if _walked_side(side)

_m_side_sources(subj, side) := [_m_shown(subj, p) | some p in _m_plain_paths(side)] if {
	not _is_ref(side)
	not is_array(side)
	not _walked_side(side)
	not _m_tally_side(side)
}

_m_side_sources(_, side) := [] if _m_tally_side(side)

_m_tally_side(side) if _basic_form(side) in {"count_of", "sum_of"}

_m_message(check, subj, "value") := m if {
	clauses := _once([c | some side in _m_sides(check); some c in _m_value_clauses(subj, side)])
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := _m_fallback(check)

_m_message(check, subj, cause) := m if {
	cause in {"absent", "null"}
	clauses := _m_key_states(subj, check, cause)
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := m if {
	cause in {"absent", "null"}
	clauses := _once(array.concat([_m_state_clause(s) | some s in _m_sources(subj, check); _m_side_said(s, cause, check)], _m_tallies(subj, check, cause)))
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := _m_fallback(check) if cause in {"absent", "null"}

_m_message(check, subj, "unusable") := m if {
	clauses := _once(array.concat(array.concat(array.concat(array.concat(array.concat(_m_key_faults(subj, check), _m_blocked(subj, check)), _m_params_faults(subj, check)), _m_faults(subj, check)), _m_walk_ref_faults(subj, check)), _m_tallies(subj, check, "unusable")))
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := m if {
	clauses := [concat("", [side.text, " needs more than 15 digits"]) |
		some side in _m_sides(check)
		_side_form(side) in {"add", "sum_of"}
		_side_eval(subj, side).v == []
		not _m_params_unread(check)
	]
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := _m_fallback(check)

_m_message(check, subj, "not_an_object") := _m_isnt(_m_label(check), subj, "an object") if {
	not is_object(subj)
	not _m_list_items(check, subj)
}

_m_message(check, subj, "not_an_object") := concat(", and ", _m_tallies(subj, check, "not_an_object")) if {
	_m_list_items(check, subj)
}

_m_message(check, subj, "not_an_object") := m if {
	is_object(subj)
	clauses := _once(array.concat(array.concat(_m_aliases_blocked(check), _m_input_one_refs(check)), _m_tallies(subj, check, "not_an_object")))
	count(clauses) > 0
	m := concat(", and ", clauses)
} else := _m_fallback(check) if is_object(subj)
