package ergo

import rego.v1

_for_is_free(item, names) if _for_free(item, names)

else := false

_for_free(item, names) if {
	aliases := {concat("", ["$", a]) | some a, _ in names; not startswith(a, "ergo/"); not a in object.keys(_for_names)}
	not _for_reads_alias(item, aliases)
}

_for_reads_alias(item, aliases) if {
	some c in item.whose
	walk(c, [_, x])
	is_array(x)
	count(x) > 0
	x[0] in aliases
}

_m_free_text(f, x, t) := t if object.get(x, "free", false) == true

else := concat("", [object.get(f, "said", f.item), ": ", t])

_m_root_why(f) := f.why if object.get(f, "root_why", false) == true

else := _m_unread_text(f)

_for_why(_, _, _, _, _, null) := null

_for_why(_, _, _, _, wh, failure) := failure if {
	failure != null
	wh.undecided == []
}

_for_counts_a_root(c) if {
	walk(c, [_, y])
	is_object(y)
	some f in _tally_forms
	p := object.get(y, f, null)
	is_array(p)
	_m_off_path(p)
}

_for_own_read_fails(c, e) if {
	fe := _focus_of(e, c)
	some x in _walk_sides_paths(c)
	is_array(x[0])
	not _walk_outside(x[0])
	_read_state(fe.iv, x[0]) in _failed_read_states
}

_for_root_why(c, cause, subj) := [t] if {
	t := _m_walked_root_text(c, cause)
} else := ts if {
	_for_counts_a_root(c)
	_root_read_flaw(subj, c) == cause
	ts := _m_cond_root_texts(subj, c)
	ts != []
} else := []

_for_why(first, item, e, names, wh, failure) := object.union(failure, {"why": []}) if {
	failure != null
	wh.undecided != []
	some c in item.whose
	_reads_input_key(c)
	_for_is_free({"whose": [c]}, names)
} else := object.union(failure, _for_own_why_of(first, e, own)) if {
	failure != null
	wh.undecided != []
	_for_root_fails(item, e, names)
	own := _for_own_texts(item, e, names)
	own != []
} else := object.union(failure, {"why": [ts[0]], "root_why": true, "free": true}) if {
	failure != null
	wh.undecided != []
	ts := [t |
		some c in item.whose
		cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
		_for_cause_undecided(cause, c) with input as {"ergo/names": names}
		not _for_own_read_fails(c, e)
		said := _for_root_why(c, _m_undecided(cause), object.get(names, "ergo/subject", null)) with input as {"ergo/names": names}
		some t in said
	]
	count(ts) > 0
} else := object.union(failure, {"why": [_m_tally_item("count_of", e, set())[0][1]]}) if {
	failure != null
	wh.undecided != []
	some c in item.whose
	_focus_lost(e, c)
} else := object.union(failure, {"why": [ms[0][0]], "root_why": true, "free": ms[0][1]}) if {
	failure != null
	wh.undecided != []
	ms := [[m, _for_is_free({"whose": [c]}, names)] |
		some c in item.whose
		cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
		_for_cause_undecided(cause, c) with input as {"ergo/names": names}
		off := [_m_aliased(t) | some t in _m_keyed_off(object.get(names, "ergo/subject", null), c, cause)] with input as {"ergo/names": names}
		some m in off
	]
	count(ms) > 0
	not _for_own_why(first, item, e, names)
} else := object.union(failure, {"why": [ms[0]]}) if {
	failure != null
	wh.undecided != []
	pairs := [[_m_why_text(_m_item_name(fe.i, set()), _m_aliased(said)), _m_own_said(said, roots)] |
		some c in item.whose
		fe := _focus_of(e, c)
		cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
		_for_cause_undecided(cause, c) with input as {"ergo/names": names}
		said := _m_whose_said_in(item, names, c, fe.iv, cause)
		roots := _m_keyed_roots(object.get(names, "ergo/subject", null), c, cause)
	] with input as {"ergo/names": names}
	ms := _for_own_first(first, pairs)
	count(ms) > 0
} else := failure

_for_whose_item_clause(item, e, names, wh) := clause if {
	wh.undecided != []
	clause := _for_whose_own(item, e) with input as {"ergo/names": names}
}

_for_whose_own(_, e) := _m_clause("item", name, "not_an_object", _m_isnt(name, e.iv, "an object")) if {
	not is_object(e.iv)
	name := _m_item_name(e.i, set())
}

_for_whose_own(item, e) := clauses[0] if {
	is_object(e.iv)
	clauses := [x |
		some c in item.whose
		_for_focus_cause(c, e) != "satisfied"
		x := _for_cond_clause(c, e)
	]
}

_for_cond_clause(c, e) := _m_item_clause(_m_item_name(e.i, set()), cause, [_m_clause("root", m, cause, m)]) if {
	_focus_lost(e, c)
	p := {"op": "present", "path": e.r}
	cause := _row_cause(p, e.iv, "")
	m := _message(p, e.iv, cause)
} else := _m_clause("item", name, "not_an_object", _m_isnt(name, fe.iv, "an object")) if {
	e.r != []
	fe := _focus_of(e, c)
	fe.r == []
	not is_object(fe.iv)
	some p in _condition_paths(c)
	p != []
	not _walk_outside(p)
	name := _m_item_name(fe.i, set())
} else := _m_item_clause(_m_item_name(fe.i, set()), cause, said) if {
	fe := _focus_of(e, c)
	said := _once(_for_cond_own(c, fe, object.get(_for_names, "ergo/subject", null)))
	cause := _for_said_cause(said)
	cause != "satisfied"
}

_for_said_cause(said) := _worst_or_value({x.cause | some x in said}) if said != []

else := "satisfied"

_for_cond_own(c, fe, subj) := array.concat(bases, _for_own_said(c, fe, subj)) if {
	bases := [_m_clause("root", x[1], x[0], x[1]) | some x in _m_cond_base_said(fe.iv, c)]
	_for_base_first(c, subj)
} else := array.concat(_for_own_said(c, fe, subj), [_m_clause("root", x[1], x[0], x[1]) | some x in _m_cond_base_said(fe.iv, c)])

_for_base_first(c, subj) if {
	ps := _condition_paths(c)
	some i, p in ps
	_ref_step_flawed(p)
	every q in array.slice(ps, 0, i) {
		_for_blocked(c, q, subj)
	}
}

_for_own_said(c, fe, subj) := [_m_clause("root", m, cause, m) |
	s := _for_own_check(c, subj)
	cause := _focus_cause(s, fe)
	not cause in _not_failing_causes
	m := _message(s, fe.iv, cause)
]

_for_own_check(c, subj) := c if {
	not _for_blocks(c, subj)
} else := object.union(c, {"right": {"literal": []}}) if {
	c.op == "compare"
	c.cmp in {"in", "not_in"}
	not _for_side_blocked(c, c.left, subj)
	_for_side_blocked(c, c.right, subj)
} else := object.union(c, {"left": c[f], "right": c[f]}) if {
	c.op == "compare"
	some f in _compare_side_list
	not _for_side_blocked(c, c[f], subj)
	some g in _compare_side_list
	g != f
	_for_side_blocked(c, c[g], subj)
} else := object.union(c, {"left": c[f], "right": {"literal": "1970-01-01T00:00:00Z"}}) if {
	c.op == "compare_time"
	some f in _compare_side_list
	not _for_side_blocked(c, c[f], subj)
	some g in _compare_side_list
	g != f
	_for_side_blocked(c, c[g], subj)
} else := object.union(c, {f: stand_ins[f]}) if {
	stand_ins := _for_stand_ins[c.op]
	some f, _ in stand_ins
	_for_blocked(c, c[f].ref, subj)
	not _for_blocked(c, c.path, subj)
}

_for_stand_ins := {
	"includes": {"value": null, "values": [null]},
	"excludes": {"value": null, "values": [null]},
	"includes_some": {"values": [null]},
	"not_includes_all": {"values": [null]},
	"in": {"values": []},
	"not_in": {"values": []},
	"matches_any": {"patterns": ["x"]},
	"not_matches_any": {"patterns": ["x"]},
}

_for_blocks(c, subj) if {
	some p in array.concat(_condition_paths(c), [c[f].ref | some f in ["value", "values", "patterns"]; _is_ref(object.get(c, f, null))])
	_for_blocked(c, p, subj)
}

_for_side_blocked(c, side, subj) if {
	some p in _side_paths(side)
	_for_blocked(c, p, subj)
}

_for_blocked(_, p, _) if _ref_step_flawed(p)

_for_blocked(c, p, subj) if {
	_walk_outside(p)
	_root_read_flaw(subj, c) != ""
}

_for_own_first(true, pairs) := array.concat([m | some [m, true] in pairs], [m | some [m, false] in pairs])

_for_own_first(false, pairs) := [m | some [m, _] in pairs]

_for_own_why(true, item, e, names) if {
	some c in item.whose
	fe := _focus_of(e, c) with input as {"ergo/names": names}
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	_for_cause_undecided(cause, c) with input as {"ergo/names": names}
	roots := _m_keyed_roots(object.get(names, "ergo/subject", null), c, cause) with input as {"ergo/names": names}
	_m_own_said(_m_whose_said_in(item, names, c, fe.iv, cause), roots) with input as {"ergo/names": names}
}

_for_own_why_of(true, e, own) := {"why": [_m_why_text(_m_item_name(e.i, set()), own[0])]}

_for_own_why_of(false, _, own) := {"own": own}

_for_root_fails(item, e, names) if {
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	_for_cause_undecided(cause, c) with input as {"ergo/names": names}
	subj := object.get(names, "ergo/subject", null)
	count(array.concat(_for_root_why(c, _m_undecided(cause), subj), _m_keyed_off(subj, c, cause))) > 0 with input as {"ergo/names": names}
}

_for_root_fails(item, e, names) if {
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	_for_cause_undecided(cause, c) with input as {"ergo/names": names}
	not _root_read_flaw(object.get(names, "ergo/subject", null), c) in _tolerated_root_flaws with input as {"ergo/names": names}
}

_for_own_texts(item, e, names) := [t |
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	_for_cause_undecided(cause, c) with input as {"ergo/names": names}
	fe := _focus_of(e, c)
	some x in _walk_sides_paths(c)
	is_array(x[0])
	not _walk_outside(x[0])
	read := _for_own_read(c, fe.iv, x[0])
	own := read[0]
	own in _failed_read_states
	subj := object.get(names, "ergo/subject", null)
	roots := {piece | some r in array.concat(array.concat(_for_root_why(c, _m_undecided(own), subj), _m_keyed_off(subj, c, own)), _m_cond_root_texts(subj, c)); some piece in split(r, "; ")} with input as {"ergo/names": names}
	said := _m_whose_said_in(item, names, read[1], fe.iv, own) with input as {"ergo/names": names}
	parts := [y | some z in split(said, "; "); some y in split(z, ", and "); not y in roots; not regex.match(`^and [0-9]+ more$`, y)]
	parts != []
	t := _m_aliased(concat(", and ", parts))
]

_for_own_read(c, iv, p) := [s, st] if {
	st := _root_stand_in(c)
	st.op in (_contain_ops | _pattern_ops)
	st.path == p
	s := _row_cause(st, iv, "")
	s in _failed_read_states
} else := [_side_state(iv, p), c]

_m_whose_why(first, f) := _for_why(first, wo[0], wo[1], wo[2], wo[3], f) if {
	wo := f.whose_of
	_for_root_fails(wo[0], wo[1], wo[2])
} else := _for_why(first, wo[0], wo[1], wo[2], wo[3], f) if {
	wo := f.whose_of
	_for_own_texts(wo[0], wo[1], wo[2]) != []
} else := f

_m_inner_text(check, f) := _m_inner_text_of(check, _m_whose_why(false, f))

_m_inner_text_of(check, f) := [_m_why_text(_m_for_item_name(check, f.path), f.own[0])] if count(object.get(f, "own", [])) > 0

else := ts if {
	ts := _m_root_why(f)
	ts != []
} else := [concat("", [_m_for_item_name(check, f.path), ": ", substring(w, indexof(w, ": ") + 2, -1)]) |
	count(object.get(f, "rest", [])) == 0
	some w in object.get(f, "why", [])
	contains(w, ": ")
]

_m_inner_free(f) := _m_inner_free_of(_m_whose_why(false, f))

_m_inner_free_of(f) := false if count(object.get(f, "own", [])) > 0

else := object.get(f, "free", false)

_m_with_why(f) := object.union(f, {"msg": w.why}) if {
	w := _m_whose_why(true, f)
	"why" in object.keys(w)
} else := f

_m_own_said(said, roots) if {
	some x in split(said, "; ")
	some y in split(x, ", and ")
	not y in roots
}

default _m_own_said(_, _) := false

_m_keyed_roots(subj, c, cause) := ms if ms := _m_keyed_off(subj, c, cause)

else := []

_m_why_text(name, m) := concat("", [name, " ", trim_prefix(m, "the subject ")]) if startswith(m, "the subject ")

else := concat("", [name, ": ", m])

_m_strip(f) := object.union(object.remove(f, _failed_internal_keys), object.union({"failed_assertions": [_m_strip_line(l) | some l in f.failed_assertions]}, _m_strip_items(f))) if "failed_assertions" in object.keys(f)

else := object.remove(f, _failed_internal_keys)

_m_strip_items(f) := {"failed_items": [object.remove(x, ["msg", "text", "free"]) | some x in f.failed_items]} if "failed_items" in object.keys(f)

else := {}

_m_strip_line(l) := object.union(object.remove(l, _line_internal_keys), {"items": [object.remove(x, ["msg", "own"]) | some x in l.items]}) if "items" in object.keys(l)

else := object.remove(l, _line_internal_keys)

_for_message(check, subj, r) := _m_joined(_for_empty_texts(check, subj, r)) if r.failed == []

_m_for_empty(check, subj, cause) := cs if {
	ls := [t | some item in check.items; some t in _m_key_list_texts(subj, item.path, object.get(item, "if_any", false) == true)]
	ls != []
	cs := _once(array.concat([t | some item in check.items; some t in _m_key_texts(item.path)], ls))
} else := cs if {
	cause in _no_value_states
	cs := _once([c | some item in check.items; some c in _m_key_states(subj, _m_for_item(item), cause)])
	cs != []
} else := cs if {
	cause in _no_value_states
	cs := _once([concat("", [_m_unbound_name(check, s), " is ", _m_state_word(cause)]) | some item in check.items; some s in _m_sources(subj, _m_for_item(item)); s.state == cause])
	cs != []
} else := cs if {
	cause == "unusable"
	faults := _once([c | some item in check.items; some c in array.concat(_m_key_faults(subj, _m_for_item(item)), _m_whose_ref_faults(item))])
	faults != []
	cs := _once(array.concat(faults, [c | some item in check.items; _m_picked_none(subj, item); some c in _m_list_found(subj, item.path)]))
} else := cs if {
	cs := _once([c | some item in check.items; _m_narrows(subj, item); some c in _m_list_found(subj, item.path)])
	cs != []
} else := cs if {
	cs := _once([c | some item in check.items; some c in _m_list_found(subj, item.path)])
	cs != []
} else := [_m_fallback_text(check)]

_m_unbound_name(check, s) := _input_name(array.concat([{"plain": substring(s.side[0], 1, -1)}], array.slice(s.side, 1, count(s.side)))) if {
	s.state == "absent"
	s.side[0] in {concat("", ["$", item.as]) | some item in check.items}
} else := s.name

_m_narrows(_, item) if count(object.get(item, "whose", [])) > 0

_m_narrows(_, item) if "pick" in object.keys(item)

_m_narrows(subj, item) if _value_at(subj, item.path) == []

_m_picked_none(subj, item) if {
	"pick" in object.keys(item)
	_value_at(subj, item.path) == []
}

_m_whose_ref_faults(item) := [_m_isnt(_ref_label(f[0].ref), _ref_shown(f[0].ref), f[1]) |
	some c in object.get(item, "whose", [])
	some f in _m_ref_list_fault(c)
]

_m_ref_faults_text(check) := [_m_isnt(_ref_label(f[0].ref), _ref_shown(f[0].ref), f[1]) | some f in _m_ref_list_fault(check)]

_m_for_item(item) := {"op": "present", "path": item.path, "whose": object.get(item, "whose", [])}

_m_list_found(subj, path) := [_m_is(_input_name(p), _value_at(subj, p))] if {
	i := min({j | some j in numbers.range(1, count(path)); is_array(_value_at(subj, array.slice(path, 0, j)))})
	p := array.slice(path, 0, i)
} else := []

_for_message(check, _, r) := _m_for_joined(_for_ents(check, r)) if r.failed != []

_for_key_in_items(ks, ents) if {
	some e in ents
	some k in ks
	contains(e.t, concat("", [": ", k]))
}

_for_whose_key_faults(check) := _m_root_sorted(_once([_m_isnt(_ref_label(seg.ref), _ref_read(seg.ref), "text") |
	some item in check.items
	some c in object.get(item, "whose", [])
	some [p, _] in _key_base_reads(c)
	some seg in p
	_ref_step_flaw(seg) == "unusable"
]))

_for_message_parts(check, subj, r) := _once([e.t | some e in _for_ents(check, r)]) if r.failed != []

else := split(_for_message(check, subj, r), "; ")

_for_key_once(check, r) := [k | some k in ks; not _m_said_in(k, object.get(r, "root_msgs", object.get(r, "other_roots", [])))] if {
	r.failed != []
	ks := _for_whose_key_faults(check)
	ks != []
	not _for_key_in_items(ks, _for_ents(check, r))
} else := []

_for_ents(check, r) := array.concat(
	[{"i": i, "t": t, "x": _m_extra_part(f, j)} | some i, f in r.failed; object.get(f, "hoisted", false) == true; some j, p in _m_for_part(check, r.failed, i, f); some t in _m_for_unled(said, p)],
	[{"i": i, "t": t, "x": _m_extra_part(f, j)} | some i, f in r.failed; object.get(f, "hoisted", false) != true; some j, p in _m_for_part(check, r.failed, i, f); some t in _m_for_unled(said, p)],
) if said := _m_for_said(check) | _m_for_tally_said(check)

_m_for_tally_said(check) := {_m_joined(xs) | some xs in _m_for_tally_lists(check)}

_m_for_tally_lists(check) := {xs |
	subj := object.get(input, ["ergo/names", "ergo/subject"], null)
	walk(check, [_, c])
	is_object(c)
	ys := _walked_tallies(c)
	some cause in _value_fault_causes
	xs := _m_walked_tally_texts(subj, ys, cause)
	xs != []
}

_m_tally_grouped(check, once) := [t |
	lists := [xs | some xs in _m_for_tally_lists(check); count(xs) > 3; every x in xs { x in once }]
	some m in once
	not _m_later_piece(lists, m)
	t := _m_tally_unit(lists, m)
]

_m_later_piece(lists, m) if {
	some xs in lists
	some j, x in xs
	j > 0
	x == m
}

_m_tally_unit(lists, m) := _m_joined(xs) if {
	some xs in lists
	xs[0] == m
} else := m

_m_for_said(check) := {x[1] | some x in _m_for_said_pairs(check)}

_m_for_said_pairs(check) := {[cause, t] |
	walk(check, [_, c])
	is_object(c)
	_list_phrase(c)
	some cause in _value_fault_causes
	t := _m_walked_root_text(c, cause)
}

_m_for_unled(said, p) := [t] if {
	_walk_kind(p) == "item"
	some t in said
	endswith(p, concat("", [": ", t]))
} else := [t, substring(p, 0, count(p) - count(tail))] if {
	_walk_kind(p) == "item"
	some t in said
	tail := concat("", [", and ", t])
	endswith(p, tail)
} else := [t, concat("", [substring(p, 0, i + 2), substring(p, (i + count(t)) + 8, -1)])] if {
	_walk_kind(p) == "item"
	some t in said
	i := indexof(p, concat("", [": ", t, ", and "]))
	i > 0
} else := [t, concat("", [substring(p, 0, i), substring(p, (i + count(t)) + 6, -1)])] if {
	_walk_kind(p) == "item"
	some t in said
	i := indexof(p, concat("", [", and ", t, ", and "]))
	i > 0
} else := [p]

_m_for_joined(ents) := concat("; ", _once([e.t | some e in ents])) if count(ents) <= 3

_m_for_joined(ents) := concat("; ", _once([e.t | some e in ents])) if {
	count(ents) > 3
	count(_m_for_counted(ents)) <= 3
}

_m_for_joined(ents) := concat("; ", array.concat(_once([e.t | some e in ents; _m_kept(e, shown, ents)]), [concat("", ["and ", _literal_text(count(counted) - 3), " more"])])) if {
	count(ents) > 3
	counted := _m_for_counted(ents)
	count(counted) > 3
	shown := array.slice(counted, 0, 3)
}

_m_for_counted(ents) := _once([_m_item_lead(e.t) | some e in ents; e.x == false; _walk_kind(e.t) == "item"])

_m_item_lead(t) := concat(": ", [_m_item_head(p) | some i, p in ps; i < n]) if {
	ps := _m_quote_split(t, ": ")
	n := count([i | some i, _ in ps; _m_items_up_to(ps, i)])
}

_m_items_up_to(ps, i) if {
	every j in numbers.range(0, i) {
		_walk_kind(ps[j]) == "item"
	}
}

_m_item_head(p) := concat("", [x[0], " of ", split(x[1], " ")[0]]) if x := _member_parts(p)

else := substring(p, 0, o + s) if {
	o := indexof(p, " of ") + 4
	s := indexof(substring(p, o, -1), " ")
	s >= 0
} else := p

_m_kept(e, shown, _) if {
	e.x == false
	_m_kept_text(e.t, shown)
}

_m_kept(e, shown, ents) if {
	e.x == true
	some o in ents
	o.i == e.i
	o.x == false
	_m_kept_text(o.t, shown)
}

_m_kept_text(t, shown) if not _m_cut_item(t, shown)

_m_cut_item(t, shown) if {
	_walk_kind(t) == "item"
	not _m_item_lead(t) in shown
}

_m_for_part(_, _, _, f) := _m_for_fail(_m_with_why(f)) if f.cause != "ambiguous"

_m_for_part(check, _, _, f) := [concat("", [object.get(f, "said", f.item), ": ", _m_tie(check, 1, f.failed_items)])] if {
	f.cause == "ambiguous"
	_m_nested_tie(f)
}

_m_for_part(check, failed, i, f) := [_m_tie(check, 0, failed)] if {
	f.cause == "ambiguous"
	not _m_nested_tie(f)
	not _m_earlier_tie(failed, i)
}

_m_for_part(_, failed, i, f) := [] if {
	f.cause == "ambiguous"
	not _m_nested_tie(f)
	_m_earlier_tie(failed, i)
}

_m_nested_tie(f) if {
	some x in object.get(f, "failed_items", [])
	x.cause == "ambiguous"
}

_m_earlier_tie(failed, i) if {
	some j, g in failed
	j < i
	g.cause == "ambiguous"
	not _m_nested_tie(g)
}

_m_for_fail(f) := [q | some p in f.msg; q := _m_unskipped(p, object.get(f, "skip", [])); q != ""] if "msg" in object.keys(f)

_m_for_fail(f) := [_m_isnt(object.get(f, "bare", object.get(f, "said", f.item)), object.get(f, "raw", f.value), "an object")] if {
	not "msg" in object.keys(f)
	f.cause == "not_an_object"
	not is_object(object.get(f, "raw", f.value))
}

_m_for_fail(f) := array.concat([_m_under(object.get(f, "said", f.item), q) | some g in _m_for_groups(f); some q in _m_second_tally_pieces(f, _m_group_text(g))], [_m_free_text(f, x, t) | some x in object.get(f, "failed_items", []); some t in _m_inner_fail(x)]) if {
	not "msg" in object.keys(f)
	not _m_bare_item(f)
	f.failed_assertions != []
}

_m_for_groups(f) := array.concat(_m_groups([q | some q in qs; not _m_more_clause(q)], _m_two_list(f)), [[q] | some q in qs; _m_more_clause(q)]) if {
	lines := [_m_tally_pieces(l, _m_line_msg(l, f)) | some l in f.failed_assertions]
	qs := _once([q | some ps in lines; some p in ps; q := _m_unskipped(p, object.get(f, "skip", [])); q != ""])
}

_m_tally_pieces(l, ps) := [q | some p in ps; some q in _m_top_split(p, "; ")] if {
	not "items" in object.keys(l)
	_m_tally_line(l.assertion)
} else := ps

_m_second_tally_pieces(f, t) := [_m_releaded(lead, q) | some q in _m_top_split(t, "; ")] if {
	_m_two_list(f)
	some l in f.failed_assertions
	"items" in object.keys(l)
	_m_tally_line(l.assertion)
	lead := _m_lead_of(t)
	lead != ""
} else := [t]

_m_releaded(lead, q) := concat("", [lead, ": ", q]) if {
	_walk_kind(q) == "item"
	not startswith(q, concat("", [lead, ": "]))
} else := q

_m_tally_line(a) if contains(a, "count of ")

_m_tally_line(a) if contains(a, "sum of ")

_m_unskipped(p, skip) := p if skip == []

else := concat("; ", [y |
	xs := split(p, "; ")
	some x in xs
	not _m_skipped(x, skip)
	not _m_more_of_skipped(x, xs, skip)
	y := concat(", and ", [z | some z in split(x, ", and "); not z in skip])
	y != ""
])

_m_skipped(x, skip) if x in skip

_m_skipped(x, skip) if _m_after_lead(_m_lead_of(x), x) in skip

_m_more_of_skipped(x, xs, skip) if {
	regex.match(`^and [0-9]+ more$`, x)
	some y in xs
	_m_skipped(y, skip)
}

default _m_extra_part(_, _) := false

_m_extra_part(f, j) if {
	f.cause != "ambiguous"
	not "msg" in object.keys(f)
	not _m_bare_item(f)
	f.failed_assertions != []
	not _m_two_list(f)
	gs := _m_for_groups(f)
	count(gs) > 1
	_m_lead_of(gs[j][0]) == ""
}

default _m_two_list(_) := false

_m_two_list(f) if {
	some l in f.failed_assertions
	"items" in object.keys(l)
}

_m_lead_of(t) := substring(t, 0, k) if {
	_walk_kind(t) == "item"
	cuts := [i | some i in array.concat(_m_cuts(t, ": "), _m_cuts(t, " is ")); i > 0; _m_outside_quotes(substring(t, 0, i))]
	count(cuts) > 0
	k := min(cuts)
	contains(substring(t, 0, k), " of ")
} else := ""

_m_cuts(t, sep) := [count(concat(sep, array.slice(ps, 0, k))) | some k in numbers.range(1, count(ps) - 1)] if ps := split(t, sep)

_m_outside_quotes(p) if count(split(replace(replace(p, "\\\\", ""), "\\\"", ""), "\"")) % 2 == 1

_m_groups(texts, two) := [texts] if count(texts) < 2

else := _m_grouped(texts, [_m_lead_of(t) | some t in texts], two)

_m_grouped(texts, ls, _) := [texts] if count(_m_leads(ls)) == 0

_m_grouped(texts, ls, true) := [[texts[j] | some j, l in ls; _m_in_group(l, lead, k, true)] | some k, lead in _m_pair_leads(ls)] if count(_m_leads(ls)) > 0

_m_grouped(texts, ls, false) := [[texts[j] | some j, l in ls; l == lead] | some lead in _m_list_leads(ls)] if count(_m_leads(ls)) > 0

_m_list_leads(ls) := [x[3] | some x in sort([[_m_list_at(ls, l), _m_lead_n(l), i, l] | some i, l in ls; not l in array.slice(ls, 0, i)])]

_m_list_at(ls, l) := min({i | some i, k in ls; _m_lead_list(k) == _m_lead_list(l)})

_m_lead_list(l) := p[1] if p := _item_parts(l)

else := l

_m_leads(ls) := [l | some i, l in ls; l != ""; not l in array.slice(ls, 0, i)]

_m_pair_leads(ls) := [x[2] | some x in sort([[_m_lead_n(l), i, l] | some i, l in ls; l != ""; not l in array.slice(ls, 0, i)])]

_m_lead_n(l) := to_number(tok) if {
	tok := split(substring(l, 5, -1), " ")[0]
	regex.match(`^[0-9]+$`, tok)
} else := 0

_m_in_group(l, lead, _, _) if l == lead

_m_in_group("", _, 0, true)

_m_after_lead(lead, x) := substring(x, count(prefix), -1) if {
	lead != ""
	prefix := concat("", [lead, ": "])
	startswith(x, prefix)
} else := x

_m_group_text(g) := g[0] if count(g) == 1

else := concat(", and ", _m_said_new(_m_first_marked(array.concat([g[0]], [_m_after_lead(_m_lead_of(g[0]), x) | some x in array.slice(g, 1, count(g))]))))

_m_for_fail(f) := [_m_free_text(f, x, t) | some x in f.failed_items; some t in _m_inner_fail(x)] if {
	not "msg" in object.keys(f)
	not _m_bare_item(f)
	f.failed_assertions == []
	count(object.get(f, "failed_items", [])) > 0
}

_m_for_fail(f) := [_m_named_item(f)] if {
	not "msg" in object.keys(f)
	not _m_bare_item(f)
	f.failed_assertions == []
	count(object.get(f, "failed_items", [])) == 0
}

_m_line_msg(l, f) := [p | some x in l.items; some p in _m_line_text(x, _m_pair_owns(f, x.item))] if "items" in object.keys(l)

_m_line_msg(l, f) := _m_pick_msg(l, _m_owns(f)) if not "items" in object.keys(l)

_m_pair_owns(f, item) if {
	every l in f.failed_assertions {
		_m_owned_for(l, item)
	}
}

else := false

_m_owned_for(l, item) if {
	"items" in object.keys(l)
	every x in l.items {
		_m_item_owned(x, item)
	}
}

_m_item_owned(x, item) if x.item != item

_m_item_owned(x, item) if {
	x.item == item
	is_array(x.own)
}

_m_line_text(x, false) := x.msg

_m_line_text(x, true) := x.own

_m_own_under(_, null) := null

_m_own_under(name, ms) := [_m_under(name, y) | some y in ms] if is_array(ms)

_m_pick_msg(l, false) := l.msg

_m_pick_msg(l, true) := l.own_msg

_m_all_owned(f) if {
	every l in f.failed_assertions {
		_m_owned(l)
	}
}

_m_owned(l) if {
	"items" in object.keys(l)
	every x in l.items {
		is_array(x.own)
	}
}

_m_owned(l) if {
	not "items" in object.keys(l)
	"own_msg" in object.keys(l)
}

_m_owns(f) if _m_all_owned(f)

else := false

_m_named_item(f) := _m_is(object.get(f, "said", f.item), f.value) if f.cause == "value"

_m_named_item(f) := concat("", [object.get(f, "bare", object.get(f, "said", f.item)), " is ", _m_state_word(f.cause)]) if f.cause in _no_value_states

_m_named_item(f) := _m_isnt(object.get(f, "bare", object.get(f, "said", f.item)), object.get(f, "raw", f.value), "an object") if f.cause == "not_an_object"

_m_named_item(f) := _m_isnt(object.get(f, "said", f.item), f.value, object.get(f, "wants", _m_walk_kind(f.value))) if f.cause == "unusable"

_m_tie(check, k, failed) := concat("", [_m_listed([f.item | some f in failed; f.cause == "ambiguous"]), " tie", _m_tie_on(check, k)])

_m_tie_on(check, k) := concat("", [" on ", _input_name(by)]) if {
	by := [item.pick.by | some j, item in check.items; j >= k; is_object(object.get(item, "pick", null)); "by" in object.keys(item.pick)][0]
	is_array(by)
} else := ""

_m_listed(names) := concat("", ["item ", concat(" and item ", [m[1] | some m in ms]), " of ", ms[0][2]]) if {
	ms := [m | some n in names; m := regex.find_all_string_submatch_n(`^item ([0-9]+) of (.+)$`, n, 1)[0]]
	count(ms) == count(names)
	count({m[2] | some m in ms}) == 1
} else := concat(" and ", names)

_m_walk_leaf(e, leaf, cause, roots) := t if {
	leaf != null
	t := _m_walked_root_text(leaf, cause)
} else := concat(", and ", off) if {
	leaf != null
	off := _m_keyed_off(object.get(input, ["ergo/names", "ergo/subject"], null), leaf, cause)
	off != []
} else := _m_leaf_in(e.i, concat("; ", bs), roots) if {
	leaf != null
	bs := _m_cond_base_texts(e.iv, leaf)
	bs != []
	not _key_item_unclean(e)
} else := _m_leaf_in(e.i, _m_unclean_said(leaf, e.iv, cause), roots) if {
	leaf != null
	_key_item_unclean(e)
} else := _m_leaf_in(e.i, _message(leaf, e.iv, cause), roots) if leaf != null

else := ""

_m_line(c, subj, cause) := _m_sentence(c, subj, cause)

_for_sentence_clauses(check, c, subj, cause) := _for_rooted_clauses(check, c, subj, cause, _for_sentence_roots(check, c, subj))

_for_rooted_clauses(_, _, _, "satisfied", _) := []

_for_rooted_clauses(_, c, _, cause, _) := [] if {
	cause != "satisfied"
	_m_params_unread(c)
}

_for_rooted_clauses(_, c, subj, cause, roots) := [x | some x in _m_walk_clauses(c, subj, cause, _walk_row(c, subj)); not _for_said_by_root(x, roots)] if {
	cause != "satisfied"
	not _m_params_unread(c)
	_walks(c)
}

_for_rooted_clauses(check, c, subj, cause, roots) := _once([x | some g in said; some x in _for_group_clauses(g, roots, cause, whole)]) if {
	cause != "satisfied"
	not _m_params_unread(c)
	not _walks(c)
	said := [[_m_piece_string(p) | some p in g] | some g in _message_said(c, subj, cause)]
	whole := _for_says_whole(check, c)
}

_for_says_whole(check, c) := false if _for_reads_an_alias(check, c)

else := true

_for_group_clauses(g, roots, cause, false) := [x | some p in g; some x in _for_piece_clauses(p, roots, cause)]

_for_group_clauses(g, roots, cause, true) := array.concat(
	[x | some p in g; not is_string(p); some x in _for_piece_clauses(p, roots, cause)],
	[_m_clause("root", t, cause, t) | ts := [p | some p in g; is_string(p); not p in roots]; ts != []; t := concat(", and ", ts)],
)

_for_piece_clauses(p, roots, cause) := [_m_clause("root", p, cause, p) | not p in roots] if is_string(p)

else := [x | some x in p; not _for_said_by_root(x, roots)]

_for_said_by_root(x, roots) if {
	x.kind != "item"
	x.text in roots
}

_for_item_clause(check, failed, k) := _for_item_clause_at(check, failed, k, _for_items_walked(check))

_for_item_clause_at(check, failed, k, walked) := _m_clause("item", t, "ambiguous", t) if {
	failed[k].cause == "ambiguous"
	not _m_nested_tie(failed[k])
	not _m_earlier_tie(failed, k)
	t := _m_tie(check, 0, failed)
	_ = walked
}

_for_item_clause_at(check, failed, k, walked) := _m_item_clause(f.said, "ambiguous", [_m_clause("item", t, "ambiguous", t)]) if {
	f := failed[k]
	f.cause == "ambiguous"
	_m_nested_tie(f)
	t := _m_tie(check, 1, f.failed_items)
	_ = walked
}

_for_item_clause_at(check, failed, k, walked) := c if {
	failed[k].cause != "ambiguous"
	c := _for_item_own(check, failed[k], walked)
}

_for_item_own(check, f, walked) := _for_whose_item_clause(check.items[0], e, _for_names, wh) if {
	e := walked.items[f.path]
	wh := _for_whose(check.items[0], e, _for_names)
	wh.undecided != []
	object.get(check.items[0], "whose", []) != []
}

_for_item_own(check, f, walked) := c if {
	not _for_whose_undecided(check, f, walked)
	c := _for_item_kept(check, f, walked)
}

_for_whose_undecided(check, f, walked) if {
	object.get(check.items[0], "whose", []) != []
	_for_whose(check.items[0], walked.items[f.path], _for_names).undecided != []
}

_for_item_kept(check, f, walked) := _m_clause("item", f.said, f.cause, concat("; ", array.slice(f.msg, count(roots), count(f.msg)))) if {
	roots := f["ergo/why_roots"]
	_ = [check, walked]
}

else := _m_clause("item", f.said, f.cause, concat("; ", _m_for_fail(_m_with_why(f)))) if {
	_for_said_why(f)
	_ = [check, walked]
}

else := _m_clause("item", f.said, "not_an_object", _m_isnt(object.get(f, "bare", f.said), object.get(f, "raw", f.value), "an object")) if {
	f.cause == "not_an_object"
	not is_object(object.get(f, "raw", f.value))
}

else := _m_clause("item", f.said, f.cause, _m_named_item(f)) if {
	object.get(f, "failed_assertions", []) == []
	object.get(f, "failed_items", []) == []
}

else := object.union(_m_item_clause(f.said, _worst_or_value({own[0]} | {x.cause | some x in said}), said), {"text": own[1]}) if {
	count(check.items) == 1
	own := _for_owned_text(f)
	rest := [l | some l in array.slice(f.failed_assertions, 1, count(f.failed_assertions)); object.get(l, "own_msg", []) != f.failed_assertions[0].own_msg]
	said := _for_item_sentences(check, object.union(f, {"failed_assertions": rest}), _for_item_bound(check, f, walked), walked.roots)
}

else := _m_item_clause(f.said, _for_said_cause(said), said) if {
	f.failed_assertions != []
	count(check.items) == 1
	said := _for_item_sentences(check, f, _for_item_bound(check, f, walked), walked.roots)
	said != []
}

else := _m_item_clause(f.said, _for_said_cause(said), said) if {
	count(check.items) == 2
	said := _for_pairs_said(check, f, _for_item_bound(check, f, walked))
	said != []
}

_for_owned_text(f) := [l.cause, _m_under(f.said, l.own_msg[0])] if {
	_m_all_owned(f)
	l := f.failed_assertions[0]
	count(l.own_msg) == 1
	startswith(l.own_msg[0], "\u0001")
}

_for_pairs_said(check, f, names) := array.concat([x | firsts == []; some p in riders; some x in p[1]], [x[3] | some x in sort(array.concat(pairs, dead))]) if {
	w := _for_walk(check.items[1], object.get(names, "ergo/subject", null), names)
	own := [[j, _for_pair_parts(check, f, names, w, e)] | some j, e in w.items]
	firsts := [j | some [j, ps] in own; ps != []]
	riders := _for_rider_parts(check, f, names)
	pairs := [[j, 0, 0, _for_pair_clause(f, _for_item_name(check, w.items[j].i), said)] |
		some [j, ps] in own
		said := [x | some p in sort(array.concat(ps, [r | j == firsts[0]; some r in riders])); some x in p[1]]
		said != []
	]
	dead := [[_for_inner_at(check, w, x), 1, k, _m_clause("item", x.item, x.cause, t)] |
		some k, x in object.get(f, "failed_items", [])
		object.get(x, "free", false) != true
		some t in _m_inner_fail(x)
	]
}

_for_pair_clause(f, name, said) := _m_clause("item", name, _for_said_cause(said), concat(", and ", owns)) if {
	_m_pair_owns(f, name)
	owns := _once([t | some l in f.failed_assertions; some x in l.items; x.item == name; some t in x.own])
	owns != []
	every t in owns {
		not startswith(t, concat("", [name, ": "]))
	}
} else := _m_item_clause(name, _for_said_cause(said), said)

_for_pair_parts(check, f, names, w, e) := [[i, cs] |
	name := _for_item_name(check, e.i)
	some i, c in check.checks
	some l in f.failed_assertions
	l.assertion == check.assertions[i]
	some x in object.get(l, "items", [])
	x.item == name
	cs := _for_sentence_clauses(check, c, object.get(names, "ergo/subject", null), x.cause) with input as {"ergo/names": _bound(names, check.items[1].as, e.v, _walk_at(w, e))}
	cs != []
]

_for_rider_parts(check, f, names) := [[i, cs] |
	some i, c in check.checks
	_for_reads_an_alias(check, c)
	some l in f.failed_assertions
	l.assertion == check.assertions[i]
	not "items" in object.keys(l)
	cs := _for_sentence_clauses(check, c, object.get(names, "ergo/subject", null), l.cause) with input as {"ergo/names": names}
	cs != []
]

_for_inner_at(check, w, x) := min({j | some j, e in w.items; _for_item_name(check, e.i) == x.path} | {count(w.items)})

_for_items_walked(check) := object.union(_for_walked_items(check), {"roots": [_for_sentence_roots(check, c, object.get(_for_names, "ergo/subject", null)) | some c in check.checks]})

_for_walked_items(check) := {"w": w, "items": {_failed_name(e.i, d): e | some e in w.items}} if {
	w := _for_walk(check.items[0], object.get(_for_names, "ergo/subject", null), _for_names)
	d := _for_dotted(check)
}

_for_item_bound(check, f, walked) := _bound(_for_names, check.items[0].as, e.v, _walk_at(walked.w, e)) if e := walked.items[f.path]

_for_item_sentences(check, f, names, roots) := _for_in_list_order([x | some i, x in said; not _for_said_earlier(x, array.slice(said, 0, i))]) if {
	said := _once([_for_whole_list(x) |
		some i, c in check.checks
		_for_reads_an_alias(check, c)
		some l in f.failed_assertions
		l.assertion == check.assertions[i]
		some x in _for_rooted_clauses(check, c, object.get(names, "ergo/subject", null), l.cause, roots[i]) with input as {"ergo/names": names}
	])
}

_for_whole_list(x) := object.union(x, {"kind": "list"}) if {
	x.kind == "item"
	x.said == []
	is_string(x.name)
	_walk_kind(x.name) == "list"
} else := x

_for_said_earlier(x, earlier) if {
	x.kind != "item"
	some e in earlier
	e.kind != "item"
	e.text == x.text
}

_for_in_list_order(said) := [_for_slot(said, sorted, i) | some i, _ in said] if {
	items := [c | some c in said; c.kind == "item"]
	lists := _once([_for_item_list(c) | some c in items])
	sorted := [x[3] | some x in sort([[_for_list_rank(lists, _for_item_list(c)), _for_item_number(c), j, c] | some j, c in items])]
}

_for_slot(said, sorted, i) := said[i] if {
	said[i].kind != "item"
	_ = sorted
}

else := sorted[count([j | some j, c in said; j < i; c.kind == "item"])]

_for_item_list(c) := array.slice(c.name, 0, count(c.name) - 1) if _for_numbered(c)

else := c.name

_for_item_number(c) := c.name[count(c.name) - 1] if _for_numbered(c)

else := 0

_for_numbered(c) if {
	is_array(c.name)
	is_number(c.name[count(c.name) - 1])
}

_for_list_rank(lists, l) := [i | some i, x in lists; x == l][0]

_for_row_clauses(check, subj, r) := array.concat(array.concat(array.concat(p.roots, p.free), p.items), p.lists) if p := _for_row_parts(check, subj, r)

_for_row_parts(check, subj, r) := {"roots": roots, "free": free, "items": items, "lists": array.concat(listed, line), "line": line, "said": ssaid, "own": {k: c.cause | some [k, c] in failed}} if {
	ssaid := _for_row_said(check, subj, r)
	roots := [_for_root_item(c) | some c in array.concat(_for_row_roots(check, subj, r, ssaid), _for_why_roots(check, r)); not _for_subject_root(c, subj, r)]
	rooted := {c.text | some c in roots}
	sroots := {i: {x[1] | some x in xs} | some i, xs in ssaid}
	free := [x | some c in _for_free_clauses(check, subj, r, sroots); x := _for_free_unrooted(c, rooted)]
	said := {t | some c in array.concat(roots, free); some t in _m_clause_lines(c)}
	name := _input_name(check.items[0].path)
	after := (3 * count(check.checks)) + 2
	failed := _for_failed_clauses(check, r, sroots)
	items := [object.union(x, {"group": after}) | some [k, c] in failed; r.failed[k].path != name; x := _for_unrooted(c, said)]
	listed := [object.union(c, {"kind": "list", "group": after}) | some [k, c] in failed; r.failed[k].path == name]
	line := [object.union(_m_clause("list", t, r.cause, t), {"group": after}) | some t in _for_list_texts(check, subj, r)]
}

_for_why_roots(check, r) := [c | some i, c in cs; not c.text in {d.text | some d in array.slice(cs, 0, i)}] if {
	cs := [_m_root_in(_m_clause_name(x[1]), x[0], x[1], count(check.checks)) | some f in r.failed; some x in object.get(f, "ergo/why_roots", [])]
}

_for_failed_clauses(check, r, roots) := [] if {
	r.failed == []
	_ = [check, roots]
} else := [[k, _for_item_clause_at(check, r.failed, k, walked)] | some k, _ in r.failed] if {
	walked := object.union(_for_walked_items(check), {"roots": roots})
}

_for_failed_sentences(check, r) := {i |
	some f in r.failed
	some l in object.get(f, "failed_assertions", [])
	some i, a in check.assertions
	l.assertion == a
} | {i |
	some l in object.get(r, "free_lines", [])
	some i, a in check.assertions
	l.assertion == a
}

_for_free_clauses(check, subj, r, roots) := [object.union(x, {"group": i}) |
	some i, c in check.checks
	not _for_reads_an_alias(check, c)
	ls := array.concat([l | some f in r.failed; some l in object.get(f, "failed_assertions", []); l.assertion == check.assertions[i]], [l | some l in object.get(r, "free_lines", []); l.assertion == check.assertions[i]])
	ls != []
	some x in _for_rooted_clauses(check, c, subj, ls[0].cause, roots[i])
]

_for_row_said(check, subj, r) := _for_said_of(check, subj, r, {i | some i, _ in check.checks}) if _for_row_rooted(r, subj)

else := _for_said_of(check, subj, r, _for_failed_sentences(check, r))

_for_said_of(check, subj, r, is) := {i: r["ergo/root_said"][i] | some i in is} if {
	"ergo/root_said" in object.keys(r)
	_ = [check, subj]
}

else := {i: _walk_root_said(_for_one_sentence(check, check.checks[i]), subj) | some i in is}

_for_row_roots(check, subj, r, said) := _for_roots_of(check, subj, said) if _for_row_rooted(r, subj)

else := []

_for_row_rooted(r, _) if {
	some k in ["root_msgs", "other_roots"]
	k in object.keys(r)
}

_for_row_rooted(r, subj) if {
	r.cause == "not_an_object"
	r.failed == []
	not is_object(subj)
}

_for_root_item(c) := object.union(c, {"kind": "item"}) if _walk_kind(c.text) == "item"

else := c

_for_subject_root(c, subj, r) if {
	r.cause == "not_an_object"
	r.failed == []
	not is_object(subj)
	c.name == "the subject"
}

_for_free_unrooted(c, rooted) := c if {
	c.kind != "item"
	_ = rooted
} else := _for_unrooted(c, rooted)

_for_unrooted(c, said) := object.union(c, {"said": kept}) if {
	kept := [x | some x in c.said; not _for_said_by_row(x, said)]
	not _for_says_nothing(c.text, kept, said)
}

_for_says_nothing(text, [], said) if text in ({""} | said)

_for_says_nothing(text, kept, said) if {
	text in ({""} | said)
	kept != []
	every x in kept {
		x.said == []
	}
	concat(", and ", [x.text | some x in kept]) in said
}

_for_said_by_row(x, said) if {
	x.said == []
	x.text in said
}

_for_list_texts(check, subj, r) := [] if {
	r.failed != []
	_ = [check, subj]
} else := [] if "root_msgs" in object.keys(r)

else := _for_empty_texts(check, subj, r.unfreed) if "unfreed" in object.keys(r)

else := [] if "free_lines" in object.keys(r)

else := _for_empty_texts(check, subj, r)

_for_empty_texts(check, subj, r) := [_m_not_object(check, subj)] if r.cause == "not_an_object"

else := _m_for_empty(object.union(check, {"items": object.get(r, "said_items", check.items)}), subj, r.cause)

_m_leaf_message(_, leaf, cause, _) := _m_root_alone(leaf, cause)

_m_leaf_message(e, leaf, cause, path) := _m_clash_named(_m_walk_leaf(e, leaf, cause, _dotted_roots([path])), e, leaf, path) if not _m_root_alone(leaf, cause)

_m_root_paths(leaf) := array.concat([leaf.right | is_array(object.get(leaf, "right", null))], [leaf[f].ref | some f in ["values", "value", "patterns"]; _is_ref(object.get(leaf, f, null))])

_m_root_alone(leaf, cause) := [m |
	some p in _m_root_paths(leaf)
	_walk_outside(p)
	shown := _as_subject_part(p)
	subj := object.get(input, ["ergo/names", "ergo/subject"], null)
	m := _m_root_problem(leaf, shown, subj, cause)
][0]

_m_root_problem(leaf, shown, subj, cause) := _rwalk_text(subj, shown) if {
	_list_phrase(leaf)
	not _text_walked_ref(leaf, shown)
	_rfailed(subj, shown)
} else := _m_walked_root_fault(leaf, shown, subj, cause) if {
	_list_phrase(leaf)
	not _one_right(leaf)
	_rwalking(subj, shown)
}

else := concat("", [_input_name(shown), " is missing"]) if {
	not _m_walks_root(leaf, shown, subj)
	cause == "absent"
	_m_ref_read_state(subj, shown) == cause
	i := min({j | some j in numbers.range(1, count(shown)); _any_read_state(subj, array.slice(shown, 0, j)) == cause})
	i < count(shown)
	not _has_field_step(array.slice(shown, 0, i))
} else := _message({"op": "present", "path": shown}, subj, cause) if {
	not _m_walks_root(leaf, shown, subj)
	cause in _value_fault_causes
	_m_ref_read_state(subj, shown) == cause
} else := _m_isnt(_input_name(shown), v, kind) if {
	not _m_walks_root(leaf, shown, subj)
	cause == "unusable"
	_m_ref_read_state(subj, shown) == "value"
	v := _value_at(subj, shown)
	kind := _m_leaf_needs(leaf, v)
}

_m_walks_root(leaf, shown, subj) if {
	_list_phrase(leaf)
	not _one_right(leaf)
	_rwalking(subj, shown)
}

_m_leaf_needs(leaf, v) := k if {
	k := _m_right_needs(leaf, v)
} else := _m_right_kind(leaf.cmp, v) if {
	_list_cmp(leaf)
	not _list_right_usable(leaf.cmp, v)
} else := _m_right_kind(cmp, v) if {
	some f in _list_argument_keys
	_is_ref(object.get(leaf, f, null))
	cmp := _m_ref_cmp(leaf.op, f)
	not _list_right_usable(cmp, v)
}

_list_phrase(leaf) if _list_cmp(leaf)

_list_phrase(leaf) if leaf.op in _list_phrase_ops

_list_phrase(leaf) if {
	_walk_roots_on
	leaf.op in _single_contain_ops
}

_list_phrase(leaf) if {
	leaf.op in _single_contain_ops
	_is_ref(object.get(leaf, "values", null))
}

_m_right_needs(leaf, v) := "a number" if {
	leaf.op == "compare"
	leaf.cmp in {"gt", "gte", "lt", "lte"}
	not is_number(v)
} else := "a time" if {
	leaf.op == "compare_time"
	not _s_time_value(v)
} else := "text" if {
	leaf.op == "compare"
	leaf.cmp in _text_cmps
	not is_string(v)
} else := "a list" if {
	leaf.op == "compare"
	leaf.cmp in {"in", "not_in", "includes_all", "excludes_all", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}
	not is_array(v)
} else := "a list" if {
	leaf.op in _list_phrase_ops
	not is_array(v)
}

_m_clash_named(m, e, leaf, path) := concat("", [substring(m, 0, at), ": ", _path_name(path), substring(m, (at + count(cut)) - 1, -1)]) if {
	rest := _path_name(e.r)
	e.r != []
	some p in _m_root_paths(leaf)
	_walk_outside(p)
	_input_name(_as_subject_part(p)) == rest
	cut := concat("", [": ", rest, " "])
	at := indexof(m, cut)
	at >= 0
} else := m

_m_aliases_blocked(check) := [_m_isnt_piece(_m_marked_alias(p[0]), v, _m_holder(p[1]), "not_an_object") |
	some side in _m_sides(check)
	some p in _m_side_paths(side)
	is_array(p)
	count(p) > 1
	is_string(p[0])
	startswith(p[0], "$")
	nm := substring(p[0], 1, -1)
	nm in object.keys(object.get(input, "ergo/names", {}))
	v := input["ergo/names"][nm]
	not _m_holds(v, p[1])
]

_m_marked_alias(step) := concat("", ["\u0002", substring(step, 1, -1)]) if _for_alias_step(step)

else := step

_m_holds(v, step) if {
	is_number(step)
	is_array(v)
}

_m_holds(v, step) if {
	not is_number(step)
	is_object(v)
}

_m_bare_item(f) if {
	f.cause == "not_an_object"
	not is_object(f.value)
}

_m_problems_row(row) := row if row.passed == true

else := object.union(row, {"message": concat("; ", ms)}) if {
	ms := [concat("", [i.name, ": ", p]) | some i in row.inputs; is_array(i.value); some p in i.value; is_string(p)]
	ms != []
}

else := object.union(row, {"message": "the policy isn't written correctly"})

_m_count_row(row) := row if row.passed == true

else := row if "message" in object.keys(row)

else := object.union(row, {"message": _m_joined([_m_named_fail(f) | some f in row.failed_items])}) if count(object.get(row, "failed_items", [])) > 0

else := object.union(row, {"message": _m_is(row.inputs[0].name, row.inputs[0].value)})

_m_from_message(_, _, true, _) := {}

_m_from_message(doc, req, false, cause) := {"message": m} if {
	_from_unreadable(req)
	ms := array.concat(_m_from_refs(req, cause), [_m_key_list_text(_m_from_item_name(req, f.prefix), f) | some f in _key_base_flaws(doc, _from_path(req), "list")])
	count(ms) > 0
	m := _m_joined(ms)
} else := {"message": m} if {
	m := _fl_plain_message(doc, req)
} else := {"message": _m_isnt(_m_from_root(req), doc, "an object")} if {
	cause == "not_an_object"
	_chained(req)
	not _walkable(doc)
	not _walk_gone(doc)
} else := {"message": _m_isnt(_m_from_root(req), doc, "an object")} if {
	cause == "not_an_object"
	_member_from(req)
	is_array(doc)
	_fl_parent_unread(doc, req)
} else := {"message": m} if {
	_every_from(req)
	w := _fl_broken(doc, _fl_keys(req))
	ms := array.concat([_fl_fail_text(req, f) | some p in sort({f.path | some f in w.fails}); some f in w.fails; f.path == p], _fl_notes_once([_fl_note_text(req, n) | some n in w.notes]))
	count(ms) > 0
	m := concat("; ", _once(ms))
} else := {"message": m} if {
	not _every_from(req)
	fails := _every_walk(doc, _from_keys(req)).fails
	count(fails) > 0
	m := _m_joined([_m_named_fail(object.union(f, {"path": _m_from_item_name(req, f.path)})) | some p in sort({f.path | some f in fails}); some f in fails; f.path == p])
} else := {}

_fl_notes_once(ts) := [t |
	some k, x in ts
	before := {c | some j, y in ts; j < k; some c in split(y, ", ")}
	t := concat(", ", [c | some c in split(x, ", "); not c in before])
	t != ""
]

_m_from_root(req) := data.ergo_subject_sentences.chains[req.subject] if _chained(req)

else := "$input"

_m_from_item_name(req, []) := _m_from_root(req)

_m_from_item_name(req, path) := concat(": ", [_visible_path_name([path[0]], _m_from_root(req)), _m_item_name(array.slice(path, 1, count(path)), set())]) if {
	is_number(path[0])
	count(path) > 1
} else := _visible_path_name(path, _m_from_root(req)) if {
	is_number(path[0])
} else := _m_item_name(path, set()) if path != []

_m_from_refs(req, cause) := _once([m | some r in _m_from_ref_list(req); m := _m_from_ref_said(r)]) if {
	some r in _m_from_ref_list(req)
	_m_from_params_unread(r.ref)
} else := ms if {
	ms := [m | some r in _m_from_ref_list(req); m := _m_from_ref_text(r, cause)]
	count(ms) > 0
} else := [m | some r in _m_from_ref_list(req); m := _m_from_ref_text(r, _m_from_ref_cause(r))]

_m_from_ref_said(r) := _m_from_params_text(r) if _m_from_params_unread(r.ref)

_m_from_ref_said(r) := _m_from_ref_text(r, _m_from_ref_cause(r)) if not _m_from_params_unread(r.ref)

_m_from_params_unread(ref) if {
	ref[0] in _params_starts
	not is_object(data.ergo_params)
	data.ergo_params != null
}

_m_from_params_text(r) := _m_isnt(_ref_name(r.ref), v, r.kind) if {
	_ref_state(r.ref) == "value"
	v := _ref_read(r.ref)
	not _m_from_ref_fits(v, r.kind)
} else := c if {
	some c in _m_params_break(r.ref)
} else := _m_isnt("$params", data.ergo_params, "an object")

_m_from_ref_list(req) := array.concat(
	[{"ref": r, "kind": "text"} | some r in sort({seg.ref | some seg in _from_path(req); _is_ref(seg)})],
	[{"ref": r, "kind": "a list of text"} | some r in sort({r | some r in _keys_refs(_each_step(req))})],
)

_m_from_ref_cause(r) := _ref_state(r.ref)

_m_from_ref_text(r, state) := concat("", [_ref_name(r.ref), " is ", _m_state_word(state)]) if {
	state in _no_value_states
	_ref_state(r.ref) == state
}

_m_from_ref_text(r, "unusable") := _m_isnt(_ref_name(r.ref), v, r.kind) if {
	_ref_state(r.ref) == "value"
	v := _ref_read(r.ref)
	not _m_from_ref_fits(v, r.kind)
}

_m_from_ref_text(r, "unusable") := _m_ref_breaks(r.ref)[0] if {
	_ref_state(r.ref) == "unusable"
	is_object(_start_of(null, r.ref))
	not _ref_walks(r.ref)
}

_m_from_ref_fits(v, "text") if is_string(v)

_m_from_ref_fits(v, "a list of text") if {
	is_array(v)
	every k in v {
		is_string(k)
	}
}

_m_filter(_, _, row) := row if row.passed == true

_m_filter(check, subj, row) := object.union(row, _m_line_said(check, subj, "value")) if {
	row.passed == false
	row.cause == "missing"
}

_m_filter(check, subj, row) := object.union(row, _m_line_said(check, subj, row.cause)) if {
	row.passed == false
	row.cause != "missing"
	row.cause != "unusable"
}

_m_filter(check, subj, row) := object.union(object.union(row, _m_line_said(check, subj, row.cause)), _m_unusable_marks(check, subj, row)) if {
	row.passed == false
	row.cause == "unusable"
}

_m_filter_walk(_, _, true, _, _) := {}

_m_filter_walk(_, _, false, _, w) := _m_walk_said(w.root_msgs, object.get(w, "ergo/alone_items", [])) if "root_msgs" in object.keys(w)

_m_filter_walk(check, subj, false, cause, w) := _m_walk_said(parts, _walk_item_texts(parts, w)) if {
	not "root_msgs" in object.keys(w)
	parts := _walk_parts(check, subj, {"cause": cause}, w)
}

_m_applies(_, _, true) := {}

_m_applies(evals, req, false) := {"message": concat("; ", ms)} if {
	ms := _once([evals[n].message | some n in _applies_to_names(req); not evals[n].passed])
	ms != []
} else := {"message": concat("", [_text(object.get(req, "subject", null)), " doesn't match"])}

_for_said(raw) := object.union(object.remove(raw, ["ergo/for_raw"]), {
	"message": _m_aliased(_m_clauses_text(_m_clauses_shown(tree))),
	"cause": cause,
	"ergo/for_texts": object.union(_for_said_texts(s.check, s.subj, s.r, _m_clause_texts(array.concat(p.roots, p.free)), _m_clause_texts(p.line), p.said, set(), own.texts), {"own": own.items}),
}) if {
	s := raw["ergo/for_raw"]
	s.tree == true
	count(_m_for_said(s.check) | _m_for_tally_said(s.check)) == 0
	p := _for_row_parts(s.check, s.subj, s.r)
	tree := array.concat(array.concat(array.concat(p.roots, p.free), p.items), p.lists)
	cause := _worst_or_value({raw.cause} | {v.cause | walk(tree, [_, v]); is_object(v); "cause" in object.keys(v)})
	own := _for_own_causes(s, p, raw.cause, cause)
} else := object.union(object.remove(raw, ["ergo/for_raw"]), {"message": said.message, "ergo/for_texts": _for_texts(s.check, s.subj, s.r, said.once, said.line)}) if {
	s := raw["ergo/for_raw"]
	s.tree == true
	said := _for_row_text(s.check, s.subj, s.r)
} else := object.union(object.remove(raw, ["ergo/for_raw"]), {"ergo/for_texts": _for_texts(s.check, s.subj, s.r, s.once, s.line)}) if s := raw["ergo/for_raw"]

else := raw

_for_texts(check, subj, r, once, line) := _for_said_texts(check, subj, r, once, line, {}, _m_for_said(check) | _m_for_tally_said(check), {})

_for_said_texts(check, subj, r, once, line, ssaid, said, causes) := {
	"items": items,
	"said": [concat("; ", array.concat(_for_flaw_said(check, i, flaw), _for_grouped(check, owned[i]))) | some i, _ in check.assertions],
	"said_causes": [_for_texts_cause(causes, array.concat(_for_flaw_said(check, i, flaw), owned[i])) | some i, _ in check.assertions],
	"walk": array.concat(array.concat([["list", _for_list_label(check, m), m, _for_texts_cause(causes, [m])] | flaw == []; some m in line], [["list", _for_list_label(check, ""), concat("; ", _for_grouped(check, unowned)), _for_texts_cause(causes, unowned)] | unowned != []]), seconds),
	"free": [object.remove(l, ["msg", "own_msg"]) | some l in object.get(r, "free_lines", [])],
	"flawed": flaw != [],
} if {
	flaw := _for_flaw_line(check, line)
	rs := object.get(r, "root_msgs", object.get(r, "other_roots", []))
	second := {m | once != []; some x in _for_second_roots(check, _for_names); some m in x.ms}
	skip := _for_once_skip(check, once)
	free_as := {a | some i, a in check.assertions; not _for_reads_an_alias(check, check.checks[i])}
	items := [_for_item_texts(check, r.failed, k, skip, said, once, free_as) | some k, _ in r.failed]
	roots := _once(array.concat([m | once != []; some m in rs; not m in second], [t | some x in items; some t in x.roots]))
	frees := _for_free_said(r, rs, once, free_as)
	frees0 := _for_free_said(r, [], once, free_as)
	owners := {m: _for_root_owner(check, subj, m, frees0, ssaid) | some m in roots}
	unowned := _uncovered([m | some m in roots; -1 in owners[m]])
	owned := [_uncovered(array.concat([m | some m in roots; i in owners[m]], object.get(frees, a, []))) | some i, a in check.assertions]
	seconds := [["item", _m_lead_of(m), _m_after_lead(_m_lead_of(m), m), null] | once != []; some m in rs; m in second]
}

_for_texts_cause(causes, ts) := _worst_or_value({causes[t] | some t in ts}) if {
	ts != []
	every t in ts {
		_ = causes[t]
	}
} else := null

_for_own_causes(s, p, was, now) := {"texts": {c.text: _worst_or_value({d.cause | some d in cs; d.text == c.text}) | some c in cs}, "items": p.own} if {
	now != was
	_for_row_rooted(s.r, s.subj)
	cs := array.concat(p.roots, p.line)
} else := {"texts": {}, "items": {}}

_for_flaw_line(check, line) := line if {
	line != []
	_unreadable_input
	not _m_reads_params(check.items)
} else := []

_for_flaw_said(_, _, []) := []

_for_flaw_said(check, i, flaw) := flaw if {
	flaw != []
	_m_reads_params(check.checks[i])
} else := flaw if {
	flaw != []
	not _m_reads_params(check.checks)
} else := []

_for_grouped(check, ts) := _m_tally_grouped(check, ts) if count(ts) > 3

else := ts

_uncovered([]) := []

_uncovered([t]) := [t]

_uncovered(ts) := [t | some k, t in ts; not _covered(t, array.slice(ts, 0, k))] if count(ts) > 1

_covered(t, earlier) if {
	seen := {z | some e in earlier; some x in split(e, "; "); some z in split(x, ", and ")}
	every x in split(t, "; ") {
		every z in split(x, ", and ") {
			z in seen
		}
	}
}

_for_once_skip(_, []) := []

_for_once_skip(check, once) := array.concat(once, [m | some x in _for_second_roots(check, _for_names); some m in x.raw]) if once != []

_for_list_label(check, m) := name if {
	count(check.items) == 2
	name := _input_name(check.items[1].path)
	startswith(m, concat("", [name, " "]))
} else := _input_name(check.items[0].path)

_for_root_owner(check, subj, m, frees, ssaid) := free | {i | some i, _ in check.assertions; not i in free; _for_root_of(check, subj, i, m, ssaid)} if {
	free := {i | some i, a in check.assertions; _for_free_root(m, frees[a])}
	count(free) > 0
} else := {-1} if {
	some it in check.items
	count(object.get(it, "whose", [])) > 0
	_for_root_of(object.union(check, {"checks": [], "assertions": []}), subj, -1, m, {})
} else := {0} if count(check.checks) == 1

else := owners if {
	owners := {i | some i, _ in check.checks; _for_root_of(check, subj, i, m, ssaid)}
	count(owners) > 0
} else := {-1}

_for_sentence_root_texts(check, subj, i, ssaid) := [x[1] | some x in xs] if {
	xs := ssaid[i]
	_ = [check, subj]
} else := _walk_root_msgs(object.union(check, {"items": [object.remove(it, ["whose"]) | some it in check.items], "checks": [check.checks[i]], "assertions": [check.assertions[i]]}), subj)

_for_free_root(m, ts) if {
	every p in split(m, "; ") {
		p in ts
	}
}

_for_root_of(check, subj, -1, m, _) if {
	every p in split(m, "; ") {
		p in {x | some t in _walk_root_msgs(check, subj); some x in array.concat([t], split(t, "; "))}
	}
}

_for_root_of(check, subj, i, m, ssaid) if {
	i >= 0
	c := check.checks[i]
	texts := {p | some t in array.concat(_for_sentence_root_texts(check, subj, i, ssaid), [x | some x in (_m_for_said(c) | _m_for_tally_said(c))]); some p in array.concat([t], split(t, "; "))}
	every p in split(m, "; ") {
		p in texts
	}
}

_for_free_said(_, _, [], _) := {}

_for_free_said(r, rs, once, free_as) := {a: _once(ts) |
	some a in free_as
	ts := array.concat(
		[t |
			some [l, f] in array.slice([[l, f] | some f in r.failed; some l in object.get(f, "failed_assertions", []); l.assertion == a], 0, 1)
			some m in _m_line_msg(l, f)
			some p in split(m, "; ")
			t := _m_unskipped(p, _m_root_skip(rs))
			t != ""
		],
		[t |
			some l in object.get(r, "free_lines", [])
			l.assertion == a
			some m in l.msg
			some t in split(m, "; ")
		],
	)
	ts != []
} if once != []

_for_item_texts(check, failed, k, skip, said, once, free_as) := {"lines": lines, "roots": [t | some l in lines; some t in l.roots], "walk": [], "inner": _for_line_inner_texts(failed[k])} if {
	f := failed[k]
	f.cause != "ambiguous"
	not _for_hoisted(f)
	not _for_said_why(f)
	not _m_bare_item(f)
	f.failed_assertions != []
	lines := [_for_line_texts(f, l, said, skip, free_as) | some l in f.failed_assertions]
} else := {"walk": [t | some t in ts; not t in said; _for_own_text(t, once, f)], "inner": _for_inner_texts(f), "roots": [t | some t in ts; t in said]} if {
	f := failed[k]
	fs := [_for_skipping(g, skip) | some g in failed]
	ts := [t | some p in _m_for_part(check, fs, k, _for_hoisted_or(fs[k], f)); some t in _m_for_unled(said, p)]
}

_for_skipping(f, []) := f

_for_skipping(f, skip) := object.union(f, {"skip": skip}) if skip != []

_for_hoisted(f) if f.hoisted == true

_for_said_why(f) if _ = f.msg

_for_said_why(f) if {
	_ = f.whose_of
	_ = _m_with_why(f).msg
}

_for_own_text(_, _, f) if _for_hoisted(f)

_for_own_text(t, once, _) if not t in once

_for_hoisted_or(g, f) := f if _for_hoisted(f)

else := g

_for_inner_texts(f) := [[_m_unled(name, _m_free_text(f, x, t)) | some t in _m_inner_fail(x)] | some x in f.failed_items] if {
	f.cause != "ambiguous"
	not _for_said_why(f)
	not _m_bare_item(f)
	f.failed_assertions == []
	count(object.get(f, "failed_items", [])) > 0
	name := object.get(f, "said", f.item)
} else := []

_for_line_inner_texts(f) := [[_m_unled(name, _m_free_text(f, x, t)) | some t in _m_inner_fail(x)] | some x in f.failed_items] if {
	count(object.get(f, "failed_items", [])) > 0
	name := object.get(f, "said", f.item)
} else := []

_for_cut(said, q) := _m_for_unled(said, concat("", ["item \u0003: ", q]))

_for_unsaid(said, q) := [q] if count(said) == 0

else := [y | some x in _for_cut(said, q); not x in said; y := trim_prefix(x, "item \u0003: "); y != ""]

_for_said_in(said, q) := [] if count(said) == 0

else := [x | some x in _for_cut(said, q); x in said]

_for_line_texts(f, l, said, skip, free_as) := {"m": "", "xs": [], "roots": []} if l.assertion in free_as

else := {
	"m": "",
	"xs": [_m_and_joined([_m_after_lead(_m_lead_of(y), y) | some q in _for_line_pieces(_m_line_text(x, _m_pair_owns(f, x.item)), skip); some y in _for_unsaid(said, q)]) | some x in l.items],
	"roots": [y | some x in l.items; some q in _for_line_pieces(_m_line_text(x, _m_pair_owns(f, x.item)), skip); some y in _for_said_in(said, q)],
} if {
	_ = l.items
}

else := {
	"m": _for_rendered(object.get(f, "said", f.item), [y | some q in qs; some y in _for_unsaid(said, q)]),
	"xs": [],
	"roots": [y | some q in qs; some y in _for_said_in(said, q)],
} if {
	qs := _for_line_pieces(_m_line_msg(l, f), skip)
}

_for_line_pieces(ps, []) := [p | some p in ps; p != ""]

_for_line_pieces(ps, skip) := [q | some p in ps; q := _m_unskipped(p, skip); q != ""] if skip != []

_for_rendered(_, []) := ""

_for_rendered(_, [q]) := q if not startswith(q, "\u0001")

_for_rendered(name, qs) := concat("; ", [_m_unled(name, _m_under(name, _m_group_text(g))) | some g in _m_groups(_once(qs), false)]) if {
	qs != []
	not _for_plain_one(qs)
}

_for_plain_one([q]) if not startswith(q, "\u0001")

_m_and_joined(xs) := concat(", and ", xs)

_m_unled(name, t) := substring(t, count(name) + 2, -1) if startswith(t, concat("", [name, ": "]))

else := t

_m_whose_said_in(spec, names, c, iv, cause) := _m_unclean_said(c, iv, cause) if {
	count(_key_item_flaws({"whose": [c]})) > 0
	_for_list_unclean(spec, object.get(names, "ergo/subject", null), c)
} else := _m_whose_said(c, iv, cause)

_for_list_unclean(spec, subj, c) if {
	some x in _for_listed_values(spec, _value_at(subj, spec.path))
	not _key_items_clean({"items": [{"iv": x}]}, [c])
}

_for_listed_values(spec, xs) := xs if {
	object.get(spec, "member", false) != true
	is_array(xs)
}

_for_listed_values(spec, xs) := [v | some v in xs] if {
	spec.member == true
	is_object(xs)
}

_key_item_unclean(e) if object.get(e, "ergo/unclean", false) == true

_m_whose_said(c, item, cause) := concat("; ", _m_cond_base_texts(item, c)) if {
	count(_key_item_flaws({"whose": [c]})) > 0
	_key_items_clean({"items": [{"iv": item}]}, [c])
} else := _message(c, item, cause)

_m_unclean_said(c, item, cause) := concat("; ", ps) if {
	cause in _value_fault_causes
	ps := _once([x |
		some [p, _] in _m_key_paths(c)
		some x in _m_null_base_pair(item, p)
	])
	ps != []
} else := concat("; ", bs) if {
	_m_message(_m_with_sides(_m_walked(c, item)), item, cause) == _m_fallback_text(c)
	bs := _m_cond_base_texts(item, c)
	bs != []
} else := _m_message(_m_with_sides(_m_walked(c, item)), item, cause)

_m_null_base_pair(subj, p) := [concat("", [_input_name(array.slice(p, 0, j)), " is null"]), _m_key_text(subj, p[i])] if {
	_key_step_later(p)
	i := min({k | some k, step in p; _m_key_text(subj, step)})
	i > 0
	j := min({m | some m in numbers.range(1, i); _resolved(subj, array.slice(p, 0, m)) == null})
	_input_name(array.slice(p, 0, j)) != "$params"
}
