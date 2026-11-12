package ergo

import rego.v1

default _cmp(_, _, _, _, _) := false

_cmp("eq", l, r, _, _) if {
	l == r
	not _holds_numbers(l)
}

_cmp("eq", l, r, check, subj) if {
	l == r
	_holds_numbers(l)
	_same_texts(json.marshal(l), json.marshal(r))
	_ = check
	_ = subj
}

_cmp("ne", l, r, _, _) if l != r

_cmp("ne", l, r, _, _) if {
	l == r
	_holds_numbers(l)
	not _same_texts(json.marshal(l), json.marshal(r))
}

_holds_numbers(x) if is_number(x)

_holds_numbers(x) if is_object(x)

_holds_numbers(x) if is_array(x)

_same_texts(a, b) if a == b

_same_texts(a, b) if {
	a != b
	x := json.unmarshal(a)
	y := json.unmarshal(b)
	x == y
	xs := {p: json.marshal(n) | walk(x, [p, n]); is_number(n)}
	ys := {p: json.marshal(n) | walk(y, [p, n]); is_number(n)}
	every p, t in xs {
		_text_order(t, ys[p]) == 0
	}
}

_has_number(x) if is_number(x)

_has_number(x) if {
	_holds_numbers(x)
	not is_number(x)
	walk(x, [_, n])
	is_number(n)
}

_exact_key(x, []) := x

_exact_key(_, [t]) := [v, {p: _decimal_parts(json.marshal(n)) | walk(v, [p, n]); is_number(n)}] if v := json.unmarshal(t)

default _long_text(_) := false

_long_text(t) if contains(strings.replace_n(_digit_marks, t), "0000000000000000")

_digit_marks := {"1": "0", "2": "0", "3": "0", "4": "0", "5": "0", "6": "0", "7": "0", "8": "0", "9": "0", ".": "0"}

_exact_keys(vs, t) := vs if not _long_text(t)

else := [_exact_key(v, [json.marshal(v) | _holds_numbers(v)]) | some v in vs]

_cmp("gt", l, r, _, _) if l > r

_cmp("gt", l, r, _, _) if {
	l == r
	is_number(l)
	_text_order(json.marshal(l), json.marshal(r)) == 1
}

_cmp("gte", l, r, _, _) if l > r

_cmp("gte", l, r, _, _) if {
	l == r
	not is_number(l)
}

_cmp("gte", l, r, _, _) if {
	l == r
	is_number(l)
	_text_order(json.marshal(l), json.marshal(r)) >= 0
}

_cmp("lt", l, r, _, _) if l < r

_cmp("lt", l, r, _, _) if {
	l == r
	is_number(l)
	_text_order(json.marshal(l), json.marshal(r)) == -1
}

_cmp("lte", l, r, _, _) if l < r

_cmp("lte", l, r, _, _) if {
	l == r
	not is_number(l)
}

_cmp("lte", l, r, _, _) if {
	l == r
	is_number(l)
	_text_order(json.marshal(l), json.marshal(r)) <= 0
}

_text_order(a_text, b_text) := 0 if a_text == b_text

_text_order(a_text, b_text) := _signed_order(a.negative, b.negative, _magnitude_order(a, b)) if {
	a_text != b_text
	a := _decimal_parts(a_text)
	b := _decimal_parts(b_text)
}

_signed_order(false, false, m) := m

_signed_order(true, true, m) := 0 - m

_signed_order(true, false, _) := -1

_signed_order(false, true, _) := 1

_magnitude_order(a, b) := _ordered(a.digits != "0", b.digits != "0") if "0" in {a.digits, b.digits}

_magnitude_order(a, b) := _ordered(count(a.digits) + a.exponent, count(b.digits) + b.exponent) if {
	not "0" in {a.digits, b.digits}
	count(a.digits) + a.exponent != count(b.digits) + b.exponent
}

_magnitude_order(a, b) := _ordered(_padded(a.digits, n), _padded(b.digits, n)) if {
	not "0" in {a.digits, b.digits}
	count(a.digits) + a.exponent == count(b.digits) + b.exponent
	n := max([count(a.digits), count(b.digits)])
}

_padded(digits, n) := concat("", [digits, _zeros(n - count(digits))])

_ordered(x, y) := -1 if x < y

_ordered(x, y) := 1 if x > y

_ordered(x, y) := 0 if x == y

_member(list, x, _) if {
	not _holds_numbers(x)
	x in list
}

_member(_, _, pairs) if {
	some p in pairs
	_same_texts(p[0], p[1])
}

_cmp("starts_with", l, r, _, _) if {
	is_string(l)
	is_string(r)
	startswith(l, r)
}

_cmp("ends_with", l, r, _, _) if {
	is_string(l)
	is_string(r)
	endswith(l, r)
}

_cmp("not_starts_with", l, r, _, _) if {
	is_string(l)
	is_string(r)
	not startswith(l, r)
}

_cmp("not_ends_with", l, r, _, _) if {
	is_string(l)
	is_string(r)
	not endswith(l, r)
}

_cmp("alphabetically_lte", l, r, _, _) if {
	is_string(l)
	is_string(r)
	l <= r
}

_cmp("alphabetically_gte", l, r, _, _) if {
	is_string(l)
	is_string(r)
	l >= r
}

_cmp("alphabetically_before", l, r, _, _) if {
	is_string(l)
	is_string(r)
	l < r
}

_cmp("alphabetically_after", l, r, _, _) if {
	is_string(l)
	is_string(r)
	l > r
}

_cmp("in", l, r, _, _) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	_member(r, l, [[json.marshal(y), json.marshal(l)] | some y in r; y == l; _holds_numbers(y)])
}

_cmp("not_in", l, r, _, _) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	not _member(r, l, [[json.marshal(y), json.marshal(l)] | some y in r; y == l; _holds_numbers(y)])
}

_cmp("includes", l, r, _, _) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	_member(l, r, [[json.marshal(y), json.marshal(r)] | some y in l; y == r; _holds_numbers(y)])
}

_cmp("excludes", l, r, _, _) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	not _member(l, r, [[json.marshal(y), json.marshal(r)] | some y in l; y == r; _holds_numbers(y)])
}

_cmp("includes_all", l, r, _, _) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		_member(l, want, [[json.marshal(y), json.marshal(want)] | some y in l; y == want; _holds_numbers(y)])
	}
}

_cmp("excludes_all", l, r, _, _) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		not _member(l, want, [[json.marshal(y), json.marshal(want)] | some y in l; y == want; _holds_numbers(y)])
	}
}

_cmp("includes_some", l, r, _, _) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	some want in r
	_member(l, want, [[json.marshal(y), json.marshal(want)] | some y in l; y == want; _holds_numbers(y)])
}

_cmp("not_includes_all", l, r, _, _) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	some want in r
	not _member(l, want, [[json.marshal(y), json.marshal(want)] | some y in l; y == want; _holds_numbers(y)])
}

_cmp("matches_any", l, r, _, _) if {
	is_string(l)
	_valid_patterns(r)
	some pattern in r
	regex.match(pattern, l)
}

_cmp("not_matches_any", l, r, _, _) if {
	is_string(l)
	_valid_patterns(r)
	every pattern in r {
		not regex.match(pattern, l)
	}
}

_all_cmps := {"includes_all", "excludes_all", "includes_some", "not_includes_all"}

_list_cmps := {"in", "not_in", "includes", "excludes", "matches_any", "not_matches_any"} | _all_cmps

_list_cmp(leaf) if {
	leaf.op == "compare"
	leaf.cmp in _list_cmps
	is_array(leaf.right)
}

_list_cmp(leaf) if {
	leaf.op == "compare"
	leaf.cmp in _list_cmps
	_walked_side(leaf.right)
}

default _list_flaw(_, _) := set()

_list_flaw(leaf, x) := {_lstate(leaf, x)} if {
	_list_cmp(leaf)
	_lstate(leaf, x) != "value"
}

_list_flaw(leaf, x) := {"value"} if {
	_list_cmp(leaf)
	_lfailed(leaf, x)
	_lstate(leaf, x) == "value"
}

_list_flaw(leaf, x) := {"unusable"} if {
	_list_cmp(leaf)
	_lstate(leaf, x) == "value"
	not _lfailed(leaf, x)
	not _list_right_usable(leaf.cmp, _lvalue(leaf, x))
}

_list_flawed(leaf, x) if count(_list_flaw(leaf, x)) > 0

_list_right_usable(cmp, r) if {
	cmp in {"in", "not_in"}
	is_array(r)
	not _mixed_types(r)
}

_list_right_usable(cmp, _) if cmp in {"includes", "excludes"}

_list_right_usable(cmp, r) if {
	cmp in _all_cmps
	_wanted(r)
	not _mixed_types(r)
}

_list_right_usable(cmp, r) if {
	cmp in {"matches_any", "not_matches_any"}
	_valid_patterns(r)
}

_leaf_ops := {"range", "excludes", "includes", "in", "equals", "present", "missing", "non_empty_string", "matches_any", "not_matches_any", "compare", "compare_time"}
