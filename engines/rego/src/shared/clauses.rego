package ergo

import rego.v1

_m_root_sorted(clauses) := _roots_then_lists(clauses, set())

_roots_then_lists(clauses, lists) := _roots_then_lists_of([[_m_root_clause(c, lists), c] | some c in clauses], lists)

_roots_then_lists_of(tagged, lists) := array.concat(
	array.concat(
		[x[2] | some x in sort([[_m_clause_rank(t[1]), _m_clause_name(t[1]), t[1]] | some t in tagged; t[0]; not _m_clause_name(t[1]) in lists])],
		[t[1] | some t in tagged; t[0]; _m_clause_name(t[1]) in lists],
	),
	[t[1] | some t in tagged; not t[0]],
)

_m_root_clause(c, lists) := false if {
	_m_more_clause(c)
	_ = lists
}

else := false if _m_list_item_clause(c, lists)

else := true

_m_more_clause(c) if {
	startswith(c, "and ")
	endswith(c, " more")
	not contains(c, " is ")
}

_m_list_item_clause(c, lists) if {
	startswith(c, "item ")
	rest := substring(c, indexof(c, " of ") + 4, -1)
	some l in lists
	_m_names_list(rest, l)
}

_m_names_list(rest, l) if startswith(rest, concat("", [l, ":"]))

_m_names_list(rest, l) if startswith(rest, concat("", [l, " "]))

_m_top_sorted(m, lists) := m if {
	not contains(m, "; ")
	not contains(m, ", and ")
	_ = lists
} else := concat("; ", _roots_then_lists(ps, lists)) if {
	ps := _m_top_split(m, "; ")
	count(ps) > 1
} else := concat(", and ", _roots_then_lists(_m_top_split(m, ", and "), lists))

_m_top_split(t, sep) := [concat(sep, array.slice(ps, cuts[g], cuts[g + 1])) | some g in numbers.range(0, count(cuts) - 2)] if {
	ps := split(t, sep)
	ends := [e | some i, _ in ps; e := i + 1; _m_top_shut(concat(sep, array.slice(ps, 0, e)))]
	cuts := array.concat([0], _clause_last_cut(ends, count(ps)))
}

_m_top_shut(s) if {
	_clause_quotes_shut(s)
	count(split(s, "[")) == count(split(s, "]"))
	count(split(s, "{")) == count(split(s, "}"))
}

_m_clause_rank(c) := 4 if endswith(c, " is missing")

else := 5 if endswith(c, " is null")

else := 3 if contains(c, ", which isn't ")

else := 3 if endswith(c, " needs more than 15 digits")

else := 6

_m_clause_name(c) := substring(c, 0, indexof(c, " is ")) if contains(c, " is ")

else := c

_clause_quotes_shut(s) if count(split(replace(replace(s, "\\\\", ""), "\\\"", ""), "\"")) % 2 == 1

_clause_last_cut(ends, n) := ends if ends[count(ends) - 1] == n

else := array.concat(ends, [n])
