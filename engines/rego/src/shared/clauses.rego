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
	rest := _item_parts(c)[1]
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

_m_clause_name(c) := _cut_before(c, " is ")

_cut_before(c, sep) := substring(c, 0, indexof(c, sep)) if {
	contains(c, sep)
	not contains(c, "\"")
} else := concat(sep, array.slice(parts, 0, min(js))) if {
	contains(c, "\"")
	parts := split(c, sep)
	js := [j | some j in numbers.range(1, count(parts) - 1); _clause_quotes_shut(concat(sep, array.slice(parts, 0, j)))]
	count(js) > 0
} else := c

_clause_quotes_shut(s) if count(split(replace(replace(s, "\\\\", ""), "\\\"", ""), "\"")) % 2 == 1

_clause_last_cut(ends, n) := ends if ends[count(ends) - 1] == n

else := array.concat(ends, [n])

_m_clause(kind, name, cause, text) := {"kind": kind, "name": name, "cause": cause, "text": text, "said": []}

_m_root_in(name, cause, text, group) := {"kind": "root", "name": name, "cause": cause, "text": text, "said": [], "group": group}

_m_item_clause(name, cause, said) := {"kind": "item", "name": name, "cause": cause, "text": "", "said": said}

_m_clause_more(n) := {"kind": "more", "count": n, "name": "", "cause": "value", "text": "", "said": []}

_m_said_clauses(said) := [_m_clause("root", _m_clause_name(x[1]), x[0], x[1]) | some x in said]

_m_said_sorted(said) := [x[3] | some i, x in ys; not x[2] in {y[2] | some y in array.slice(ys, 0, i)}] if {
	ys := sort([[_m_clause_rank(x[1]), _m_clause_name(x[1]), x[1], x] | some x in said])
}

_clause_text(x) := x.text if is_object(x)

else := x

_m_row_texts(rr) := object.union(rr, {k: [_clause_text(c) | some c in rr[k]] | some k in ["root_msgs", "other_roots"]; is_array(object.get(rr, k, null))}) if {
	some k in ["root_msgs", "other_roots"]
	k in object.keys(rr)
} else := rr

_m_clause_texts(clauses) := [t | some c in clauses; some t in _m_clause_lines(c)]

_m_clauses_shown(clauses) := _m_clauses_cut(_m_clauses_order(clauses))

_m_clauses_order(clauses) := [c | some i, c in sorted; not _m_said_before(c, array.slice(sorted, 0, i))] if {
	sorted := [x[5] | some x in sort([_m_clause_place(i, c) | some i, c in clauses; _m_clause_first(c, array.slice(clauses, 0, i))])]
}

_m_clause_first(c, _) if c.kind == "more"

_m_clause_first(c, earlier) if {
	c.kind != "more"
	not c in earlier
}

_m_clause_place(i, c) := [object.get(c, "group", 0), 0, object.get(_m_clause_ranks, c.cause, 6), c.name, c.text, c] if {
	c.kind == "root"
	_ = i
}

else := [object.get(c, "group", 0), object.get(_m_clause_kind_ranks, c.kind, 3), 0, "", i, c]

_m_clause_kind_ranks := {"list": 1, "item": 2, "more": 2}

_m_said_before(c, earlier) if {
	c.kind in {"root", "list"}
	some e in earlier
	e.kind in {"root", "list"}
	e.text == c.text
}

_m_said_before(c, earlier) if {
	c.kind == "item"
	c.said == []
	c.text != ""
	some e in earlier
	e.kind == "item"
	e.said == []
	e.text == c.text
}

_m_walk_said(clauses, items) := {
	"message": concat("; ", ts),
	"ergo/own": [t | some t in ts; not t in said],
	"ergo/texts": items,
	"ergo/heads": [],
} if {
	count(clauses) <= 3
	every c in clauses {
		c.kind == "item"
		c.said == []
	}
	ts := _once([c.text | some c in clauses])
	said := {c.text | some c in items}
} else := {
	"message": _m_clauses_text(_m_clauses_cut(ordered)),
	"ergo/own": [t | some t in _m_clause_texts(ordered); not t in said],
	"ergo/texts": items,
	"ergo/heads": [c | some c in ordered; c.kind != "item"],
} if {
	ordered := _m_clauses_order(clauses)
	said := {c.text | some c in items}
}

_m_clauses_cut(ordered) := ordered if count(_m_clause_counted_names(_m_clause_units_in(ordered))) <= 3

_m_clauses_cut(ordered) := array.concat([x[1] | some x in sort(array.concat([[[i], c] | some i, c in ordered; c.kind != "item"], [[u.key, u.clause] | some u in pieces; _m_clause_kept(u, pieces, kept)]))], [_m_clause_more(count(names) - 3)]) if {
	pieces := _m_clause_units_in(ordered)
	names := _m_clause_counted_names(pieces)
	count(names) > 3
	kept := {n | some n in array.slice(names, 0, 3)}
}

_m_clause_units_in(ordered) := [x[1] | some x in sort([[u.key, u] | some t, c in ordered; c.kind == "item"; some u in _m_clause_item_units(t, c)])]

_m_clause_counted_names(pieces) := _once([u.clause.name | some u in pieces; u.counted])

_m_clause_kept(u, _, kept) if {
	u.counted
	u.clause.name in kept
}

_m_clause_kept(u, pieces, kept) if {
	not u.counted
	under := array.slice(u.key, 0, count(u.key) - 1)
	some p in pieces
	p.counted
	p.clause.name in kept
	array.slice(p.key, 0, count(under)) == under
}

_m_clause_ranks := {"not_an_object": 1, "ambiguous": 2, "unusable": 3, "absent": 4, "null": 5}

_m_clauses_text(clauses) := concat("; ", _m_clause_texts(clauses))

_m_clause_lines(c) := [c.text] if {
	c.kind != "more"
	c.said == []
	c.text != ""
}

_m_clause_lines(c) := [concat("", ["and ", _literal_text(c.count), " more"])] if c.kind == "more"

_m_clause_lines(c) := [_m_clause_unit_text(u.clause) | some u in _m_clause_units([c])] if {
	c.kind == "item"
	c.said != []
}

_m_clause_unit_text(c) := c.text if c.said == []

_m_clause_unit_text(c) := concat(": ", [c.name, concat(", and ", [s.text | some s in c.said])]) if c.said != []

_m_clause_units(items) := [x[1] | some x in sort([[u.key, u] | some t, c in items; some u in _m_clause_item_units(t, c)])]

_m_clause_item_units(t, c) := {{"key": [t], "counted": true, "clause": c} | c.text != ""} if c.said == []

else := {u |
	nodes := {p: v | walk(c, [p, v]); _m_clause_item_node(v)}
	some p, n in nodes
	some u in _m_clause_node_units(array.concat([t], p), [nodes[q].name | some k in numbers.range(0, count(p)); k < count(p); k % 2 == 0; q := array.slice(p, 0, k)], n)
}

_m_clause_item_node(v) if {
	is_object(v)
	v.kind == "item"
}

_m_clause_node_units(key, lead, n) := array.concat(
	[{"key": key, "counted": true, "clause": _m_clause("item", name, n.cause, concat(": ", array.concat(lead, [n.text])))} | n.text != ""],
	[{"key": array.concat(key, ["said", i]), "counted": _m_clause_leaf(n), "clause": _m_item_clause(name, n.cause, run)} | some [i, run] in _m_clause_runs(n.said)],
) if name := _m_clause_unit_name(lead, n.name)

_m_clause_unit_name(lead, name) := concat(": ", array.concat(lead, [name])) if is_string(name)

else := array.concat(lead, [name])

_m_clause_leaf(n) := false if {
	some c in n.said
	c.kind == "item"
} else := true

_m_clause_runs(said) := [[i, array.slice(said, i, _m_clause_run_end(said, i))] | some i, c in said; c.kind != "item"; _m_clause_run_start(said, i)]

_m_clause_run_start(_, 0)

_m_clause_run_start(said, i) if said[i - 1].kind == "item"

_m_clause_run_end(said, i) := min({j | some j, c in said; j > i; c.kind == "item"} | {count(said)})
