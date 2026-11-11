package ergo

import rego.v1

default _cmp(_, _, _) := false

_cmp("eq", l, r) if l == r

_cmp("ne", l, r) if l != r

_cmp("gt", l, r) if l > r

_cmp("gte", l, r) if l >= r

_cmp("lt", l, r) if l < r

_cmp("lte", l, r) if l <= r

_cmp("starts_with", l, r) if {
	is_string(l)
	is_string(r)
	startswith(l, r)
}

_cmp("ends_with", l, r) if {
	is_string(l)
	is_string(r)
	endswith(l, r)
}

_cmp("not_starts_with", l, r) if {
	is_string(l)
	is_string(r)
	not startswith(l, r)
}

_cmp("not_ends_with", l, r) if {
	is_string(l)
	is_string(r)
	not endswith(l, r)
}

_cmp("alphabetically_lte", l, r) if {
	is_string(l)
	is_string(r)
	l <= r
}

_cmp("alphabetically_gte", l, r) if {
	is_string(l)
	is_string(r)
	l >= r
}

_cmp("alphabetically_before", l, r) if {
	is_string(l)
	is_string(r)
	l < r
}

_cmp("alphabetically_after", l, r) if {
	is_string(l)
	is_string(r)
	l > r
}

_cmp("in", l, r) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	l in r
}

_cmp("not_in", l, r) if {
	l != null
	is_array(r)
	_fits_list(l, r)
	not l in r
}

_cmp("includes", l, r) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	r in l
}

_cmp("excludes", l, r) if {
	is_array(l)
	r != null
	_items_fit(l, [r])
	not r in l
}

_cmp("includes_all", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		want in l
	}
}

_cmp("excludes_all", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	every want in r {
		not want in l
	}
}

_cmp("includes_some", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	some want in r
	want in l
}

_cmp("not_includes_all", l, r) if {
	is_array(l)
	_wanted(r)
	_items_fit(l, r)
	some want in r
	not want in l
}

_cmp("matches_any", l, r) if {
	is_string(l)
	_valid_patterns(r)
	some pattern in r
	regex.match(pattern, l)
}

_cmp("not_matches_any", l, r) if {
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
