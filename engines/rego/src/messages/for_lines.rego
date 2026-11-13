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
	some f in ["count_of", "sum_of"]
	p := object.get(y, f, null)
	is_array(p)
	_m_off_path(p)
}

_for_own_read_fails(c, e) if {
	fe := _focus_of(e, c)
	some x in _walk_sides_paths(c)
	is_array(x[0])
	not _walk_outside(x[0])
	_read_state(fe.iv, x[0]) in {"absent", "null", "unusable", "not_an_object"}
}

_for_root_why(c, cause, subj) := [t] if {
	t := _m_walked_root_text(c, cause)
} else := ts if {
	_for_counts_a_root(c)
	_root_read_flaw(subj, c) == cause
	ts := _m_cond_root_texts(subj, c)
	ts != []
} else := []

_for_why(first, item, e, names, wh, failure) := object.union(failure, _for_own_why_of(first, e, own)) if {
	failure != null
	wh.undecided != []
	_for_root_fails(item, e, names)
	own := _for_own_texts(item, e, names)
	own != []
} else := object.union(failure, {"why": [_m_aliased(ts[0])], "root_why": true, "free": _for_is_free(item, names)}) if {
	failure != null
	wh.undecided != []
	ts := [t |
		some c in item.whose
		cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
		not cause in {"satisfied", "value"}
		not _for_own_read_fails(c, e)
		not _for_first_ref_of_kinds(first, c)
		said := _for_root_why(c, _m_undecided(cause), object.get(names, "ergo/subject", null)) with input as {"ergo/names": names}
		some t in said
	]
	count(ts) > 0
	not _for_any_ref_of_kinds(first, item)
} else := object.union(failure, {"own": own}) if {
	first == false
	failure != null
	wh.undecided != []
	not _for_focus_lost(item, e)
	own := _for_own_texts(item, e, names)
	own != []
} else := object.union(failure, {"why": [_m_tally_item("count_of", e, set())[0][1]]}) if {
	failure != null
	wh.undecided != []
	some c in item.whose
	_focus_lost(e, c)
} else := object.union(failure, {"why": [ms[0]], "root_why": true, "free": _for_is_free(item, names)}) if {
	failure != null
	wh.undecided != []
	ms := [m |
		some c in item.whose
		cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
		not cause in {"satisfied", "value"}
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
		not cause in {"satisfied", "value"}
		said := _message(c, fe.iv, cause)
		roots := _m_keyed_roots(object.get(names, "ergo/subject", null), c, cause)
	] with input as {"ergo/names": names}
	ms := _for_own_first(first, pairs)
	count(ms) > 0
} else := failure

_for_own_first(true, pairs) := array.concat([m | some [m, true] in pairs], [m | some [m, false] in pairs])

_for_own_first(false, pairs) := [m | some [m, _] in pairs]

_for_own_why(true, item, e, names) if {
	some c in item.whose
	fe := _focus_of(e, c) with input as {"ergo/names": names}
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	not cause in {"satisfied", "value"}
	roots := _m_keyed_roots(object.get(names, "ergo/subject", null), c, cause) with input as {"ergo/names": names}
	_m_own_said(_message(c, fe.iv, cause), roots) with input as {"ergo/names": names}
}

_for_own_why_of(true, e, own) := {"why": [_m_why_text(_m_item_name(e.i, set()), own[0])]}

_for_own_why_of(false, _, own) := {"own": own}

_for_root_fails(item, e, names) if {
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	not cause in {"satisfied", "value"}
	subj := object.get(names, "ergo/subject", null)
	count(array.concat(_for_root_why(c, _m_undecided(cause), subj), _m_keyed_off(subj, c, cause))) > 0 with input as {"ergo/names": names}
}

_for_root_fails(item, e, names) if {
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	not cause in {"satisfied", "value"}
	not _root_read_flaw(object.get(names, "ergo/subject", null), c) in {"", "not_an_object"} with input as {"ergo/names": names}
}

_for_root_fails(item, e, names) if {
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	not cause in {"satisfied", "value"}
	_for_counts_a_root(c)
	_root_read_flaw(object.get(names, "ergo/subject", null), c) == "not_an_object" with input as {"ergo/names": names}
}

_for_own_texts(item, e, names) := [t |
	some c in item.whose
	cause := _for_focus_cause(c, e) with input as {"ergo/names": names}
	not cause in {"satisfied", "value"}
	fe := _focus_of(e, c)
	some x in _walk_sides_paths(c)
	is_array(x[0])
	not _walk_outside(x[0])
	own := _read_state(fe.iv, x[0])
	own in {"absent", "null", "unusable", "not_an_object"}
	subj := object.get(names, "ergo/subject", null)
	roots := {piece | some r in array.concat(array.concat(_for_root_why(c, _m_undecided(own), subj), _m_keyed_off(subj, c, own)), _m_cond_root_texts(subj, c)); some piece in split(r, "; ")} with input as {"ergo/names": names}
	said := _message(c, fe.iv, own) with input as {"ergo/names": names}
	parts := [y | some z in split(said, "; "); some y in split(z, ", and "); not y in roots; not regex.match(`^and [0-9]+ more$`, y)]
	parts != []
	t := _m_aliased(concat(", and ", parts))
]

_m_inner_text(check, f) := [_m_why_text(_m_for_item_name(check, f.path), f.own[0])] if count(object.get(f, "own", [])) > 0

else := _m_root_why(f)

_m_inner_free(f) := false if count(object.get(f, "own", [])) > 0

else := object.get(f, "free", false)

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

_m_strip(f) := object.union(object.remove(f, ["msg", "said", "raw", "bare", "hoisted"]), object.union({"failed_assertions": [_m_strip_line(l) | some l in f.failed_assertions]}, _m_strip_items(f))) if "failed_assertions" in object.keys(f)

else := object.remove(f, ["msg", "said", "raw", "bare", "hoisted"])

_m_strip_items(f) := {"failed_items": [object.remove(x, ["msg", "text", "free"]) | some x in f.failed_items]} if "failed_items" in object.keys(f)

else := {}

_m_strip_line(l) := object.union(object.remove(l, ["msg", "own_msg"]), {"items": [object.remove(x, ["msg", "own"]) | some x in l.items]}) if "items" in object.keys(l)

else := object.remove(l, ["msg", "own_msg"])

_for_message(check, subj, r) := _m_not_object(check, subj) if {
	r.cause == "not_an_object"
	r.failed == []
}

_for_message(check, subj, r) := _m_joined(_m_for_empty(object.union(check, {"items": object.get(r, "said_items", check.items)}), subj, r.cause)) if {
	r.cause != "not_an_object"
	r.failed == []
}

_m_for_empty(check, subj, cause) := cs if {
	cause in {"absent", "null"}
	cs := _once([c | some item in check.items; some c in _m_key_states(subj, _m_for_item(item), cause)])
	cs != []
} else := cs if {
	cause in {"absent", "null"}
	cs := _once([concat("", [_m_unbound_name(check, s), " is ", _m_state_word(cause)]) | some item in check.items; some s in _m_sources(subj, _m_for_item(item)); s.state == cause])
	cs != []
} else := cs if {
	cause == "unusable"
	cs := _once([c | some item in check.items; some c in array.concat(_m_key_faults(subj, _m_for_item(item)), _m_whose_ref_faults(item))])
	cs != []
} else := [_m_fallback(check)] if {
	cause == "unusable"
	_m_params_unread(check)
} else := cs if {
	cs := _once([c | some item in check.items; _m_narrows(subj, item); some c in _m_list_found(subj, item.path)])
	cs != []
} else := cs if {
	cs := _once([c | some item in check.items; some c in _m_list_found(subj, item.path)])
	cs != []
} else := [_m_fallback(check)]

_m_unbound_name(check, s) := _input_name(array.concat([{"plain": substring(s.side[0], 1, -1)}], array.slice(s.side, 1, count(s.side)))) if {
	s.state == "absent"
	s.side[0] in {concat("", ["$", item.as]) | some item in check.items}
} else := s.name

_m_narrows(_, item) if count(object.get(item, "whose", [])) > 0

_m_narrows(_, item) if "pick" in object.keys(item)

_m_narrows(subj, item) if _value_at(subj, item.path) == []

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

_for_message_parts(check, subj, r) := _once([e.t | some e in _for_ents(check, r)]) if r.failed != []

else := split(_for_message(check, subj, r), "; ")

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
	some cause in ["absent", "null", "unusable"]
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

_m_for_said(check) := {t |
	walk(check, [_, c])
	is_object(c)
	_list_phrase(c)
	some cause in ["absent", "null", "unusable"]
	t := _m_walked_root_text(c, cause)
}

_m_for_unled(said, p) := [t] if {
	startswith(p, "item ")
	some t in said
	endswith(p, concat("", [": ", t]))
} else := [t, substring(p, 0, count(p) - count(tail))] if {
	startswith(p, "item ")
	some t in said
	tail := concat("", [", and ", t])
	endswith(p, tail)
} else := [t, concat("", [substring(p, 0, i + 2), substring(p, (i + count(t)) + 8, -1)])] if {
	startswith(p, "item ")
	some t in said
	i := indexof(p, concat("", [": ", t, ", and "]))
	i > 0
} else := [t, concat("", [substring(p, 0, i), substring(p, (i + count(t)) + 6, -1)])] if {
	startswith(p, "item ")
	some t in said
	i := indexof(p, concat("", [", and ", t, ", and "]))
	i > 0
} else := [p]

_m_for_joined(ents) := concat("; ", _once([e.t | some e in ents])) if count(_once([e.t | some e in ents; e.x == false])) <= 3

_m_for_joined(ents) := concat("; ", array.concat(_once([e.t | some e in ents; _m_kept(e, shown, ents)]), [concat("", ["and ", _literal_text(count(counted) - 3), " more"])])) if {
	counted := _once([e.t | some e in ents; e.x == false])
	count(counted) > 3
	shown := array.slice(counted, 0, 3)
}

_m_kept(e, shown, _) if {
	e.x == false
	e.t in shown
}

_m_kept(e, shown, ents) if {
	e.x == true
	some o in ents
	o.i == e.i
	o.x == false
	o.t in shown
}

_m_for_part(_, _, _, f) := _m_for_fail(f) if f.cause != "ambiguous"

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

_m_for_fail(f) := [_m_under(object.get(f, "said", f.item), _m_group_text(g)) | some g in _m_for_groups(f)] if {
	not "msg" in object.keys(f)
	not _m_bare_item(f)
	f.failed_assertions != []
}

_m_for_groups(f) := _m_groups(_once([q | some ps in lines; some p in ps; q := _m_unskipped(p, object.get(f, "skip", [])); q != ""]), _m_two_list(f)) if lines := [_m_line_msg(l, f) | some l in f.failed_assertions]

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
	startswith(t, "item ")
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

_m_grouped(texts, ls, false) := [[texts[j] | some j, l in ls; l == lead] | some lead in _m_all_leads(ls)] if count(_m_leads(ls)) > 0

_m_leads(ls) := [l | some i, l in ls; l != ""; not l in array.slice(ls, 0, i)]

_m_pair_leads(ls) := [x[2] | some x in sort([[_m_lead_n(l), i, l] | some i, l in ls; l != ""; not l in array.slice(ls, 0, i)])]

_m_lead_n(l) := to_number(tok) if {
	tok := split(substring(l, 5, -1), " ")[0]
	regex.match(`^[0-9]+$`, tok)
} else := 0

_m_all_leads(ls) := [l | some i, l in ls; not l in array.slice(ls, 0, i)]

_m_in_group(l, lead, _, _) if l == lead

_m_in_group("", _, 0, true)

_m_after_lead(lead, x) := substring(x, count(prefix), -1) if {
	lead != ""
	prefix := concat("", [lead, ": "])
	startswith(x, prefix)
} else := x

_m_group_text(g) := g[0] if count(g) == 1

else := concat(", and ", _m_first_marked(array.concat([g[0]], [_m_after_lead(_m_lead_of(g[0]), x) | some x in array.slice(g, 1, count(g))])))

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

_m_named_item(f) := concat("", [object.get(f, "bare", object.get(f, "said", f.item)), " is ", _m_state_word(f.cause)]) if f.cause in {"absent", "null"}

_m_named_item(f) := _m_isnt(object.get(f, "bare", object.get(f, "said", f.item)), object.get(f, "raw", f.value), "an object") if f.cause == "not_an_object"

_m_named_item(f) := _m_isnt(object.get(f, "said", f.item), f.value, _m_walk_kind(f.value)) if f.cause == "unusable"

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
} else := _m_leaf_in(e.i, _message(leaf, e.iv, cause), roots) if leaf != null

else := ""

_m_line(c, subj, cause) := _m_sentence(c, subj, cause)

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
	_rfailed(subj, shown)
} else := _m_walked_root_fault(leaf, shown, subj, cause) if {
	_list_phrase(leaf)
	not _one_right(leaf)
	_rwalking(subj, shown)
}

else := concat("", [_input_name(shown), " is missing"]) if {
	not _m_walks_root(leaf, shown, subj)
	cause == "absent"
	_any_read_state(subj, shown) == cause
	i := min({j | some j in numbers.range(1, count(shown)); _any_read_state(subj, array.slice(shown, 0, j)) == cause})
	i < count(shown)
	not _has_field_step(array.slice(shown, 0, i))
} else := _message({"op": "present", "path": shown}, subj, cause) if {
	not _m_walks_root(leaf, shown, subj)
	cause in {"absent", "null", "unusable"}
	_any_read_state(subj, shown) == cause
} else := _m_isnt(_input_name(shown), v, kind) if {
	not _m_walks_root(leaf, shown, subj)
	cause == "unusable"
	_any_read_state(subj, shown) == "value"
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
	some f in ["values", "patterns"]
	_is_ref(object.get(leaf, f, null))
	cmp := _m_ref_cmp(leaf.op, f)
	not _list_right_usable(cmp, v)
}

_list_phrase(leaf) if _list_cmp(leaf)

_list_phrase(leaf) if leaf.op in {"in", "not_in", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}

_m_right_needs(leaf, v) := "a number" if {
	leaf.op == "compare"
	leaf.cmp in {"gt", "gte", "lt", "lte"}
	not is_number(v)
} else := "a time" if {
	leaf.op == "compare_time"
	not _s_time_value(v)
} else := "text" if {
	leaf.op == "compare"
	leaf.cmp in {"starts_with", "ends_with", "not_starts_with", "not_ends_with", "alphabetically_before", "alphabetically_after", "alphabetically_lte", "alphabetically_gte"}
	not is_string(v)
} else := "a list" if {
	leaf.op == "compare"
	leaf.cmp in {"in", "not_in", "includes_all", "excludes_all", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}
	not is_array(v)
} else := "a list" if {
	leaf.op in {"in", "not_in", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}
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

_m_aliases_blocked(check) := [_m_isnt(_m_marked_alias(p[0]), v, _m_holder(p[1])) |
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
	ms := _m_from_refs(req, cause)
	count(ms) > 0
	m := _m_joined(ms)
} else := {"message": m} if {
	m := _fl_plain_message(doc, req)
} else := {"message": _m_isnt(_m_from_root(req), doc, "an object")} if {
	cause == "not_an_object"
	_chained(req)
	not _walkable(doc)
	not _walk_gone(doc)
} else := {"message": m} if {
	_every_from(req)
	w := _fl_broken(doc, _from_keys(req))
	ms := array.concat([_fl_fail_text(req, f) | some p in sort({f.path | some f in w.fails}); some f in w.fails; f.path == p], [_fl_note_text(req, n) | some n in w.notes])
	count(ms) > 0
	m := _m_joined(ms)
} else := {"message": m} if {
	not _every_from(req)
	fails := _every_walk(doc, _from_keys(req)).fails
	count(fails) > 0
	m := _m_joined([_m_named_fail(object.union(f, {"path": _m_from_item_name(req, f.path)})) | some p in sort({f.path | some f in fails}); some f in fails; f.path == p])
} else := {}

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
	state in {"absent", "null"}
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

_m_filter(check, subj, row) := object.union(row, {"message": _m_joined(_m_line(check, subj, "value"))}) if {
	row.passed == false
	row.cause == "missing"
}

_m_filter(check, subj, row) := object.union(row, {"message": _m_joined(_m_line(check, subj, row.cause))}) if {
	row.passed == false
	row.cause != "missing"
}

_m_filter_walk(_, _, true, _, _) := {}

_m_filter_walk(_, _, false, _, w) := {"message": _m_joined(w.root_msgs)} if "root_msgs" in object.keys(w)

_m_filter_walk(check, subj, false, cause, w) := {"message": _m_joined(_walk_parts(check, subj, {"cause": cause}, w))} if not "root_msgs" in object.keys(w)

_m_applies(_, _, true) := {}

_m_applies(evals, req, false) := {"message": concat("; ", ms)} if {
	ms := _once([evals[n].message | some n in _applies_to_names(req); not evals[n].passed])
	ms != []
} else := {"message": concat("", [_text(object.get(req, "subject", null)), " doesn't match"])}

_m_root_pieces(rs) := {p |
	some m in rs
	some p in split(m, "; ")
	not regex.match(`^and [0-9]+ more$`, p)
}

_m_without_roots(text, pieces) := text if count(pieces) == 0

else := concat("; ", [y |
	xs := split(text, "; ")
	some i, x in xs
	not _m_note_of_root(xs, i, pieces)
	y := _m_own_part(x, pieces)
	y != ""
])

_m_note_of_root(xs, i, pieces) if {
	i > 0
	regex.match(`^and [0-9]+ more$`, xs[i])
	_m_own_part(xs[i - 1], pieces) == ""
}

_m_own_part(x, pieces) := _m_own_joined([_m_own_piece(z, pieces) | some z in split(x, ", and ")])

_m_own_piece(z, pieces) := {"gone": true} if z in pieces

else := {"lead": substring(z, 0, (count(z) - n) - 2)} if {
	startswith(z, "item ")
	ns := [count(t) | some t in pieces; endswith(z, concat("", [": ", t]))]
	count(ns) > 0
	n := max(ns)
}

else := {"text": z}

_m_own_joined(zs) := "" if {
	every z in zs {
		not "text" in object.keys(z)
	}
}

else := concat("", [zs[0].lead, ": ", concat(", and ", [z.text | some z in zs; "text" in object.keys(z)])]) if "lead" in object.keys(zs[0])

else := concat(", and ", [z.text | some z in zs; "text" in object.keys(z)])

_for_focus_lost(item, e) if {
	some c in item.whose
	_focus_lost(e, c)
}

_for_focus_lost(item, e) if {
	some c in item.whose
	not is_object(_focus_of(e, c).iv)
}

_for_any_ref_of_kinds(first, item) if {
	some c in item.whose
	_for_first_ref_of_kinds(first, c)
}

_for_first_ref_of_kinds(true, c) if _for_ref_of_kinds(c)

_for_ref_of_kinds(c) if {
	some p in _m_walked_roots(c)
	_builtin(p)
	not _ref_walk(p).failed
}
