package ergo

import rego.v1

_out_of_range(x) if {
	walk(x, [_, n])
	is_number(n)
	not _fits_a_float(n)
}

_number_flaws(x) := {p | walk(x, [_, n]); is_number(n); p := _number_flaw(n, json.marshal(n))}

_number_flaw(n, _) := "number out of range" if not _fits_a_float(n)

_number_flaw(n, t) := _too_long_problem if {
	_fits_a_float(n)
	count(_decimal_parts(t).digits) > 15
}

_too_long_problem := "number with more than 15 significant digits"

_fits_a_float(0)

_fits_a_float(n) if {
	abs(n) >= 2.2250738585072014e-308
	abs(n) <= 1.7976931348623157e308
}

default _leaf_passed(_, _) := false

_leaf_passed(check, subj) if _leaf_op_passed(check.op, check, subj)

_leaf_op_passed("range", check, subj) if {
	v := _value_at(subj, check.path)
	is_number(v)
	lo := _arg(check.min)
	hi := _arg(check.max)
	is_number(lo)
	is_number(hi)
	_cmp("gte", v, lo, check, subj)
	_cmp("lte", v, hi, check, subj)
}

_leaf_op_passed("outside_range", check, subj) if {
	v := _value_at(subj, check.path)
	is_number(v)
	lo := _arg(check.min)
	hi := _arg(check.max)
	is_number(lo)
	is_number(hi)
	_cmp("lt", v, lo, check, subj)
}

_leaf_op_passed("outside_range", check, subj) if {
	v := _value_at(subj, check.path)
	is_number(v)
	lo := _arg(check.min)
	hi := _arg(check.max)
	is_number(lo)
	is_number(hi)
	_cmp("gt", v, hi, check, subj)
}

_leaf_op_passed("includes_some", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	some want in wants
	_member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
}

_leaf_op_passed("not_includes_all", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	some want in wants
	not _member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
}

_leaf_op_passed("excludes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	want := _arg(check.value)
	_items_fit(v, [want])
	not _member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
}

_leaf_op_passed("includes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	want := _arg(check.value)
	_items_fit(v, [want])
	_member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
}

_leaf_op_passed("excludes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	every want in wants {
		not _member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
	}
}

_leaf_op_passed("includes", check, subj) if {
	v := _value_at(subj, check.path)
	is_array(v)
	wants := _wants(check.values)
	_wanted(wants)
	_items_fit(v, wants)
	every want in wants {
		_member(v, want, [[json.marshal(y), json.marshal(want)] | some y in v; y == want; is_number(y)])
	}
}

_leaf_op_passed("in", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	_fits_list(v, vals)
	_member(vals, v, [[json.marshal(y), json.marshal(v)] | some y in vals; y == v; is_number(y)])
}

_leaf_op_passed("has_type", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	type_name(v) == _json_types[check.type]
}

_leaf_op_passed("lacks_type", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	type_name(v) != _json_types[check.type]
}

_json_types := {"list": "array", "string": "string", "number": "number", "boolean": "boolean", "object": "object"}

_leaf_op_passed("not_in", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	vals := _wants(check.values)
	_value_list(vals)
	_fits_list(v, vals)
	not _member(vals, v, [[json.marshal(y), json.marshal(v)] | some y in vals; y == v; is_number(y)])
}

_leaf_op_passed("equals", check, subj) if {
	_cmp("eq", _field(subj, check.path), _arg(check.value), check, subj)
}

_leaf_op_passed("present", check, subj) if {
	_value_at(subj, check.path) != null
}

_leaf_op_passed("non_empty_string", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	v != ""
}

_leaf_op_passed("not_non_empty_string", check, subj) if {
	v := _value_at(subj, check.path)
	v != null
	not _non_empty_text(v)
}

_non_empty_text(v) if {
	is_string(v)
	v != ""
}

_leaf_op_passed("missing", check, subj) if {
	_missing_at(subj, check.path)
	not _params_not_given(check.path)
}

_leaf_op_passed("empty_string_or_list", check, subj) if {
	_value_at(subj, check.path) in {[], ""}
}

_leaf_op_passed("not_empty_string_or_list", check, subj) if {
	v := _value_at(subj, check.path)
	_string_or_list(v)
	count(v) > 0
}

_string_or_list(v) if is_string(v)

_string_or_list(v) if is_array(v)

_missing_at(x, path) if {
	_keys_in(x, path)
	_ := _start_of(x, path)
	_read_state(x, path) in {"absent", "null"}
}

_blocked(start, [k]) if not _can_hold(start, k)

_blocked(start, keys) if {
	count(keys) > 1
	_blocked_under(start, keys, _parent_read(start, keys))
}

_parent_read(start, keys) := v if {
	v := _read_from(start, array.slice(keys, 0, count(keys) - 1))
} else := _absent

_blocked_under(_, keys, parent) if {
	parent != _absent
	not _can_hold(parent, keys[count(keys) - 1])
}

_blocked_under(start, keys, parent) if {
	parent == _absent
	some i, k in keys
	v := _read_from(start, array.slice(keys, 0, i))
	not _can_hold(v, k)
}

_can_hold(v, _) if v == _absent

_can_hold(v, _) if v == null

_can_hold(v, k) if {
	is_object(v)
	is_string(k)
}

_can_hold(v, k) if {
	is_array(v)
	is_number(k)
}

_leaf_op_passed("matches_any", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, v)
}

_leaf_op_passed("not_matches_any", check, subj) if {
	v := _value_at(subj, check.path)
	is_string(v)
	patterns := _wants(check.patterns)
	every pattern in patterns {
		is_string(pattern)
		not regex.match(pattern, v)
	}
}

_leaf_op_passed("compare", check, subj) if {
	l := _simple_value(subj, check.left)
	r := _right_value(subj, check)
	_compared(check, l, r, subj)
}

_right_value(subj, check) := _lvalue(check, subj) if {
	_list_cmp(check)
	not _lfailed(check, subj)
}

_right_value(subj, check) := _simple_value(subj, check.right) if not _list_cmp(check)

_compared(check, l, r, subj) if {
	not "within" in object.keys(check)
	not check.cmp in _list_cmps
	check.cmp != "outside"
	_comparable(l, r)
	_orderable(check.cmp, l)
	_cmp(check.cmp, l, r, check, subj)
	_at_most_max(check, l, subj)
}

default _at_most_max(_, _, _) := false

_at_most_max(check, _, _) if not "max" in object.keys(check)

_at_most_max(check, l, subj) if {
	is_number(l)
	is_number(check.max)
	_cmp("lte", l, check.max, check, subj)
}

_compared(check, l, r, subj) if {
	not "within" in object.keys(check)
	check.cmp in _list_cmps
	not "max" in object.keys(check)
	_cmp(check.cmp, l, r, check, subj)
}

_compared(check, l, r, _) if {
	"within" in object.keys(check)
	check.cmp == "eq"
	is_number(l)
	is_number(r)
	not "max" in object.keys(check)
	_within_gap(json.marshal(l), json.marshal(r), json.marshal(check.within))
}

_compared(check, l, r, subj) if {
	"within" in object.keys(check)
	check.cmp == "ne"
	_within_usable(check, l, r, subj)
	not "max" in object.keys(check)
	not _within_gap(json.marshal(l), json.marshal(r), json.marshal(check.within))
}

_compared(check, l, r, subj) if {
	not "within" in object.keys(check)
	check.cmp == "outside"
	_comparable(l, r)
	_orderable(check.cmp, l)
	is_number(check.max)
	_cmp("lt", l, r, check, subj)
}

_compared(check, l, r, subj) if {
	not "within" in object.keys(check)
	check.cmp == "outside"
	_comparable(l, r)
	_orderable(check.cmp, l)
	is_number(check.max)
	_cmp("gt", l, check.max, check, subj)
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
	ln := time.parse_rfc3339_ns(l)
	rn := time.parse_rfc3339_ns(r)
	_cmp(check.cmp, ln, rn, check, subj)
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	is_number(l)
	is_number(r)
	_cmp(check.cmp, l, r, check, subj)
}

_leaf_op_passed("compare_time", check, subj) if {
	l := _value_at(subj, check.left)
	r := _simple_value(subj, check.right)
	_date_shaped(l)
	_date_shaped(r)
	_cmp(check.cmp, l, r, check, subj)
}

_wants(values) := _arg(values) if not _value_list(values)

_wants(values) := [_arg(x) | some x in values] if {
	_value_list(values)
	every x in values {
		_readable(x)
	}
}

_readable(x) if _ = _arg(x)

_wanted(v) if {
	_value_list(v)
	count(v) > 0
}

_value_list(v) if is_array(v)

_comparable(l, r) if {
	l != null
	type_name(l) == type_name(r)
}

_orderable(c, _) if c in {"eq", "ne"}

_orderable(c, v) if {
	is_number(v)
	not c in _text_cmps
}

_orderable(c, v) if {
	is_string(v)
	c in _text_cmps
}

_unusable_states(leaf, x) := {"unusable" | _unusable(leaf, x)}

_unusable(leaf, x) if {
	leaf.op in {"range", "outside_range"}
	v := _found(x, leaf.path)
	not is_number(v)
}

_unusable(leaf, x) if {
	leaf.op in {"matches_any", "not_matches_any"}
	v := _found(x, leaf.path)
	not is_string(v)
}

_unusable(leaf, x) if {
	leaf.op in _contain_ops
	v := _found(x, leaf.path)
	not is_array(v)
}

_unusable(leaf, x) if {
	leaf.op in _contain_ops
	v := _found(x, leaf.path)
	is_array(v)
	not _items_fit(v, _leaf_wants(leaf))
}

_contain_ops := {"includes", "excludes", "includes_some", "not_includes_all"}

_leaf_wants(leaf) := [_arg(leaf.value)] if "value" in object.keys(leaf)

_leaf_wants(leaf) := vals if {
	vals := _wants(leaf.values)
	_value_list(vals)
}

_items_fit(items, wants) if not _mixed_types(array.concat(items, wants))

_unusable(leaf, x) if {
	leaf.op in {"empty_string_or_list", "not_empty_string_or_list"}
	v := _found(x, leaf.path)
	not _string_or_list(v)
}

_unusable(leaf, x) if {
	leaf.op == "compare"
	not "within" in object.keys(leaf)
	not leaf.cmp in _list_cmps
	l := _simple_found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _usable_pair(leaf.cmp, l, r)
}

_unusable(leaf, x) if {
	leaf.op == "equals"
	v := _found(x, leaf.path)
	w := _arg(leaf.value)
	w != null
	type_name(v) != type_name(w)
}

_unusable(leaf, x) if {
	leaf.op in {"in", "not_in"}
	v := _found(x, leaf.path)
	vals := _wants(leaf.values)
	_value_list(vals)
	not _fits_list(v, vals)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"in", "not_in"}
	l := _found(x, leaf.left)
	r := _rfound(x, leaf.right)
	is_array(r)
	not _fits_list(l, r)
}

_fits_list(v, vals) if {
	every w in vals {
		_fits(v, w)
	}
}

_fits(_, w) if w == null

_fits(v, w) if type_name(v) == type_name(w)

_mixed_types(vals) if count({type_name(w) | some w in vals; w != null}) > 1

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"matches_any", "not_matches_any"}
	v := _found(x, leaf.left)
	not is_string(v)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in ({"includes", "excludes"} | _all_cmps)
	v := _found(x, leaf.left)
	not is_array(v)
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in {"includes", "excludes"}
	l := _found(x, leaf.left)
	r := _found(x, leaf.right)
	is_array(l)
	not _items_fit(l, [r])
}

_unusable(leaf, x) if {
	_list_cmp(leaf)
	leaf.cmp in _all_cmps
	l := _found(x, leaf.left)
	r := _rfound(x, leaf.right)
	is_array(l)
	is_array(r)
	not _items_fit(l, r)
}

_unusable(leaf, x) if {
	leaf.op == "compare"
	"within" in object.keys(leaf)
	l := _simple_found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _within_usable(leaf, l, r, x)
}

_numbers(l, r) if {
	is_number(l)
	is_number(r)
}

_simple_found(x, side) := _found(x, side) if is_array(side)

_simple_found(_, side) := v if {
	_basic_form(side) == "literal"
	v := _written(side)
	v != null
}

_unusable(leaf, x) if {
	leaf.op == "compare_time"
	l := _found(x, leaf.left)
	r := _simple_found(x, leaf.right)
	not _timestamps(l, r)
}

_usable_pair(cmp, l, r) if {
	_comparable(l, r)
	_orderable(cmp, l)
}

_timestamps(l, r) if {
	_rfc3339_shaped(l)
	_rfc3339_shaped(r)
}

_timestamps(l, r) if {
	is_number(l)
	is_number(r)
}

_timestamps(l, r) if {
	_date_shaped(l)
	_date_shaped(r)
}

_found(x, path) := v if {
	v := _field(x, path)
	v != null
}

_rfc3339_shaped(v) if {
	is_string(v)
	m := regex.find_all_string_submatch_n(`^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$`, v, 1)[0]
	_real_date(m)
}

_date_shaped(v) if {
	is_string(v)
	m := regex.find_all_string_submatch_n(`^(1[6-9][0-9]{2}|2[0-2][0-9]{2})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$`, v, 1)[0]
	_real_date(m)
}

_real_date(m) if {
	year := to_number(m[1])
	year >= 1678
	year <= 2261
	to_number(trim_left(m[3], "0")) <= _days_in(year, to_number(trim_left(m[2], "0")))
}

_days_in(_, month) := 31 if month in {1, 3, 5, 7, 8, 10, 12}

_days_in(_, month) := 30 if month in {4, 6, 9, 11}

_days_in(year, 2) := 29 if _leap_year(year)

_days_in(year, 2) := 28 if not _leap_year(year)

_leap_year(year) if {
	year % 4 == 0
	year % 100 != 0
}

_leap_year(year) if year % 400 == 0
