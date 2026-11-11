package ergo

import rego.v1

_json_text(v) := concat("", [_json_token(t) | some m in regex.find_all_string_submatch_n(`"(?:[^"\\]|\\.)*"|-?[0-9][0-9.eE+-]*|[^"0-9-]+`, _sorted_json(v), -1); t := m[0]])

_sorted_json(v) := concat("", [_node_json(paths, index, i) | some i, _ in paths]) if {
	index := {p: x | walk(v, [p, x])}
	paths := [pair[1] | some pair in sort([[_written_path(index, p), p] | some p, _ in index])]
}

_written_path(index, p) := [_written_step(index, p, i) | some i, _ in p]

_written_step(index, p, i) := _key_text(p[i]) if is_object(index[array.slice(p, 0, i)])

_written_step(index, p, i) := p[i] if not is_object(index[array.slice(p, 0, i)])

_key_text(k) := k if is_string(k)

_node_json(paths, index, i) := concat("", [
	_node_separator(paths, i),
	_node_key(index, paths[i]),
	_node_body(index[paths[i]]),
	_node_closers(paths, index, i),
])

_node_separator(_, 0) := ""

_node_separator(paths, i) := "" if {
	i > 0
	paths[i - 1] == _parent(paths[i])
}

_node_separator(paths, i) := "," if {
	i > 0
	paths[i - 1] != _parent(paths[i])
}

_parent(p) := array.slice(p, 0, count(p) - 1)

_node_key(index, p) := concat("", [_key_json(p[count(p) - 1]), ":"]) if {
	count(p) > 0
	is_object(index[_parent(p)])
}

_node_key(_, p) := "" if count(p) == 0

_node_key(index, p) := "" if {
	count(p) > 0
	not is_object(index[_parent(p)])
}

_key_json(k) := json.marshal(_key_text(k))

_node_body(x) := "{" if {
	_opens(x)
	is_object(x)
}

_node_body(x) := "[" if {
	_opens(x)
	not is_object(x)
}

_node_body(x) := "{}" if {
	is_object(x)
	count(x) == 0
}

_node_body(x) := "[]" if {
	type_name(x) in {"array", "set"}
	count(x) == 0
}

_node_body(x) := json.marshal(x) if not type_name(x) in {"object", "array", "set"}

_opens(x) if {
	type_name(x) in {"object", "array", "set"}
	count(x) > 0
}

_node_closers(paths, index, i) := "" if _opens(index[paths[i]])

_node_closers(paths, index, i) := concat("", [_closer(index[array.slice(paths[i], 0, k)]) | some k in _closed_depths(paths, i)]) if not _opens(index[paths[i]])

_closed_depths(paths, i) := numbers.range(count(paths[i]) - 1, _next_depth(paths, i)) if count(paths[i]) > _next_depth(paths, i)

_closed_depths(paths, i) := [] if count(paths[i]) <= _next_depth(paths, i)

_next_depth(paths, i) := count(paths[i + 1]) if i + 1 < count(paths)

_next_depth(paths, i) := 0 if i + 1 == count(paths)

_closer(x) := "}" if is_object(x)

_closer(x) := "]" if not is_object(x)

_json_token(t) := concat("", [object.get(_standard_escapes, e, e) | some m in regex.find_all_string_submatch_n(`\\u[0-9a-f]{4}|\\.|[^\\]+`, t, -1); e := m[0]]) if startswith(t, `"`)

_json_token(t) := _number_text(t) if regex.match(`^-?[0-9]`, t)

_json_token(t) := strings.replace_n({",": ", ", ":": ": "}, t) if {
	not startswith(t, `"`)
	not regex.match(`^-?[0-9]`, t)
}

_standard_escapes := {`\u003c`: "<", `\u003e`: ">", `\u0026`: "&", `\u2028`: "\u2028", `\u2029`: "\u2029", `\u0008`: `\b`, `\u000c`: `\f`}

_number_text(t) := _signed(m[1], _decimal(concat("", [m[2], m[3]]), count(m[2]) + _exponent(m[4]))) if {
	m := regex.find_all_string_submatch_n(`^(-?)([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$`, t, 1)[0]
}

_exponent("") := 0

_exponent(e) := to_number(trim_prefix(e, "+")) if e != ""

_decimal(digits, point) := _decimal_text(whole, frac) if {
	left := max([0, 1 - point])
	padded := concat("", [_zeros(left), digits, _zeros(point - count(digits))])
	whole := trim_left(substring(padded, 0, point + left), "0")
	frac := trim_right(substring(padded, point + left, -1), "0")
}

_decimal_text("", "") := "0"

_decimal_text(whole, "") := whole if whole != ""

_decimal_text("", frac) := concat("", ["0.", frac]) if frac != ""

_decimal_text(whole, frac) := concat(".", [whole, frac]) if {
	whole != ""
	frac != ""
}

_signed(_, "0") := "0"

_signed(sign, n) := concat("", [sign, n]) if n != "0"

_zeros(n) := concat("", ["0" | some _ in numbers.range(1, n)]) if n > 0

_zeros(n) := "" if n <= 0

_value_text(x) := _ref_name(x.ref) if _is_ref(x)

_value_text(x) := _literal_text(_written(x)) if {
	not _is_ref(x)
}

_literal_text(v) := "<number out of range>" if _out_of_range(v)

_literal_text(v) := _json_text(v) if not _out_of_range(v)

_text(x) := x if is_string(x)

_text(x) := _literal_text(x) if not is_string(x)
