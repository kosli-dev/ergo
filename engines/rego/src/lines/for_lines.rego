package ergo

import rego.v1

_for_names := object.get(input, "ergo/names", {})

_bound(names, name, v, at) := object.union(names, {name: v, "$at": object.union(object.get(names, "$at", {}), {"names": object.union(object.get(object.get(names, "$at", {}), "names", {}), {name: at})})})

_for_row(check, subj) := _for_row_of(check, subj, _for_row_raw(check, subj))

_for_row_of(check, subj, r) := r if {
	r.cause == "satisfied"
} else := object.union(object.remove(r, ["root_msgs", "other_roots", "natural"]), {"failed": [], "message": _m_fallback(check)}) if {
	not r.cause in {"satisfied", "ambiguous"}
	_m_params_unread(check)
} else := object.union(object.remove(r, ["root_msgs", "other_roots", "natural"]), {"failed": [_m_strip(f) | some f in r.failed], "message": _for_row_text(check, subj, r)}) if {
	r.cause != "satisfied"
}

_for_row_raw(check, subj) := object.union(r, {"cause": _for_shape_cause(r), "natural": r.cause}) if {
	_params_shape_only_unreadable(check)
	not _param_broken(check, set())
	r := _for_rooted(check, subj, _for_outer(check, subj, _for_names))
} else := object.union(r, {"cause": _for_flawed_cause(r), "failed": _for_unreadable_failed(check, r)}) if {
	_walk_flawed(check)
	_walk_root_flaw(check, subj) != ""
	r := _for_rooted(check, subj, _for_outer(check, subj, _for_names))
} else := object.union(r, {"root_msgs": ms | ms := array.concat(_flawed_root_msgs(check, subj, _for_message(check, subj, r)), [m | some x in _for_second_roots(check, subj); some m in x.ms]); ms != []}) if {
	_walk_flawed(check)
	r := object.union(_for_outer(check, subj, _for_names), {"cause": "unusable", "failed": []})
} else := {"cause": "not_an_object", "inputs": [], "failed": []} if {
	some item in check.items
	not _off_subject(item.path)
	not _for_list_item(item, subj)
	not is_object(subj)
} else := _for_rooted(check, subj, _for_outer(check, subj, _for_names))

_for_flawed_cause(r) := "ambiguous" if {
	_params_not_an_object
	r.cause == "ambiguous"
}

_for_flawed_cause(r) := "unusable" if {
	_params_not_an_object
	r.cause != "ambiguous"
}

_for_flawed_cause(r) := _worst_of({"unusable", r.cause}) if not _params_not_an_object

_for_shape_cause(r) := "ambiguous" if r.cause == "ambiguous"

_for_shape_cause(r) := "unusable" if r.cause != "ambiguous"

_params_not_an_object if {
	some p in data.ergo_unreadable
	p.name == "$params"
	"not an object" in p.value
}

_for_row_text(check, _, r) := _m_fallback(check) if object.get(r, "natural", null) == "satisfied"

_for_row_text(check, subj, r) := _for_row_message(check, subj, r) if object.get(r, "natural", null) != "satisfied"

_for_unreadable_failed(check, r) := [] if {
	_unreadable_input
	r.cause == "unusable"
	not "other_roots" in object.keys(r)
	not _params_shape_only_unreadable(check)
}

else := r.failed

_params_shape_only_unreadable(check) if {
	[{"name": "$params", "value": ["not an object"], "locations": []}] == data.ergo_unreadable
	not _m_reads_params(check)
}

_flawed_root_msgs(check, subj, said) := _with_roots(split(said, "; "), roots) if {
	roots := _walk_root_msgs(check, subj)
	roots != []
} else := []

_with_roots(said, roots) := roots if {
	every part in said {
		part in roots
	}
} else := array.concat([m | some m in roots; not _m_said_in(m, said)], said)

_for_alias_list(item, v) if {
	is_array(v)
	not "pick" in object.keys(item)
	is_string(item.path[1])
}

_for_list_item(item, subj) if {
	not "pick" in object.keys(item)
	_list_start(item.path, subj)
}

_for_rooted(check, subj, r) := _for_rooted_second(check, _for_rooted_row(check, subj, r), _for_second_roots(check, subj))

_for_rooted_second(check, rr, xs) := _for_second_rooted(rr, xs) if {
	xs != []
	not _for_some_passed(check, rr, xs)
} else := rr

_for_some_passed(check, rr, xs) if {
	check.items[0].q == "some"
	rr.cause == "satisfied"
	unread := {x.i | some x in xs}
	some i in object.get(rr, "passed_items", set())
	not i in unread
}

_for_second_rooted(rr, xs) := object.union(rr, {"cause": _worst_of({rr.cause} | {x.fl | some x in xs}), "root_msgs": array.concat(rr.root_msgs, [m | some x in xs; some m in x.ms])}) if {
	"root_msgs" in object.keys(rr)
} else := object.union(rr, {"cause": _worst_of({rr.cause} | {x.fl | some x in xs}), "other_roots": array.concat(rr.other_roots, [m | some x in xs; some m in x.ms])}) if {
	"other_roots" in object.keys(rr)
} else := object.union(rr, {"cause": _worst_of({x.fl | some x in xs}), "failed": [], "root_msgs": [m | some x in xs; some m in x.ms]}) if {
	rr.cause == "satisfied"
} else := object.union(rr, {"cause": _worst_of({rr.cause} | {x.fl | some x in xs}), "other_roots": [m | some x in xs; some m in x.ms]}) if {
	_for_list_failures(rr)
} else := object.union(rr, {"cause": _worst_of({x.fl | some x in xs}), "failed": [], "root_msgs": [m | some x in xs; some m in x.ms]}) if {
	rr.cause == "value"
} else := object.union(rr, {"root_msgs": [m | some x in xs; some m in x.ms]}) if {
	rr.cause == _worst_of({x.fl | some x in xs})
} else := object.union(rr, {"cause": _worst_of({rr.cause} | {x.fl | some x in xs}), "other_roots": [m | some x in xs; some m in x.ms]})

_for_list_failures(r) if {
	r.cause != "satisfied"
	r.failed != []
	every f in r.failed {
		object.get(f, "failed_assertions", []) == []
		object.get(f, "failed_items", []) == []
	}
}

_for_rooted_row(check, subj, r) := object.union(r, {"cause": _worst_of({flaw, r.cause}), "other_roots": ms}) if {
	_for_list_failures(r)
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
	ms := _walk_root_msgs(check, subj)
	ms != []
} else := _for_worse_root(check, subj, _rooted_row(check, subj, r))

_for_worse_root(check, subj, rr) := object.union(rr, {"cause": _worst_of({rr.cause, flaw})}) if {
	"other_roots" in object.keys(rr)
	flaw := _walk_root_flaw(check, subj)
	flaw != ""
} else := rr

_for_second_roots(check, subj) := [{"i": e.i, "fl": fl, "ms": ms, "raw": [_m_aliased(m) | some m in _m_cond_root_texts(subj, c) with input as {"ergo/names": names}]} |
	count(check.items) == 2
	item := check.items[0]
	w := _for_walk(item, subj, _for_names)
	outer := _walk_root_msgs(check, subj)
	conds := array.concat(object.get(check.items[1], "whose", []), _for_sentence_conds(check))
	some e in w.items
	wh := _for_whose(item, e, _for_names)
	wh.undecided == []
	wh.kept
	names := _bound(_for_names, item.as, e.v, _walk_at(w, e))
	some c in conds
	fl := _root_read_flaw(subj, c) with input as {"ergo/names": names}
	not fl in {"", "not_an_object"}
	ms := [_m_under(_m_for_item_name(check, e.i), _m_aliased(m)) | some m in _m_cond_root_texts(subj, c) with input as {"ergo/names": names}; not m in outer]
	ms != []
]

_for_row_message(check, subj, r) := _m_joined(array.concat(once, [t | some t in split(_for_item_text(check, subj, r, once), "; "); t != ""; not t in once])) if {
	rs := object.get(r, "root_msgs", object.get(r, "other_roots", []))
	second := {m | some x in _for_second_roots(check, subj); some m in x.ms}
	once := _once(array.concat(array.concat(array.concat([m | some m in rs; not m in second], [t | some p in _for_free_texts(check, r); t := _m_unskipped(p, rs); t != ""]), _for_hoisted_texts(check, r)), [m | some m in rs; m in second]))
	once != []
} else := _for_message(check, subj, r)

_for_hoisted_texts(check, r) := [p |
	rs := object.get(r, "root_msgs", object.get(r, "other_roots", []))
	rs != []
	some i, f in r.failed
	object.get(f, "hoisted", false) == true
	some p in _m_for_part(check, r.failed, i, f)
]

_for_item_text(check, subj, r, once) := "" if {
	"root_msgs" in object.keys(r)
	r.failed == []
} else := "" if {
	"free_lines" in object.keys(r)
	r.failed == []
} else := _for_message(check, subj, r) if {
	r.failed == []
} else := _for_message(check, subj, object.union(r, {"failed": [object.union(f, {"skip": skip}) | some f in r.failed]})) if {
	skip := array.concat(once, [m | some x in _for_second_roots(check, subj); some m in x.raw])
}

_for_free_texts(check, r) := array.concat(
	[p |
		some f in r.failed
		some l in object.get(f, "failed_assertions", [])
		_for_free_line(check, l)
		some m in _m_line_msg(l, f)
		some p in split(m, "; ")
	],
	[p |
		some l in object.get(r, "free_lines", [])
		some m in l.msg
		some p in split(m, "; ")
	],
)

_for_free_line(check, l) if {
	not "items" in object.keys(l)
	some i, a in check.assertions
	a == l.assertion
	not _for_reads_an_alias(check, check.checks[i])
}

_for_reads_an_alias(check, c) if {
	some item in check.items
	_reads_name(c, item.as)
}

_for_outer(check, subj, names) := object.union(_for_outer_of(_for_after_first(check), subj, names), {"inputs": _for_inputs(check, subj, names, check.items[0], w), "said_items": [check.items[1]]}) if {
	count(check.items) == 2
	object.get(check.items[0], "if_any", false) == true
	not _for_needs_first(check)
	_for_after_first(check).checks != []
	w := _for_walk(check.items[0], subj, names)
	_for_none_kept(check.items[0], w, names)
} else := _for_outer_of(check, subj, names)

_for_none_kept(item, w, names) if {
	object.get(item, "if_any", false) == true
	not "unread" in object.keys(w)
	w.fails == []
	_walk_stop(w) == []
	every e in w.items {
		wh := _for_whose(item, e, names)
		wh.undecided == []
		wh.kept == false
	}
}

_for_needs_first(check) if _for_from_first(check)

_for_needs_first(check) if _for_whose_reads(object.get(check.items[1], "whose", []), check.items[0].as)

_for_after_first(check) := object.union(_for_without(check, check.items[0].as), {"items": [check.items[1]]})

_for_unaliased(check) := object.union(check, {
	"checks": [x | some x in check.checks; not _for_reads_an_alias(check, x)],
	"assertions": [check.assertions[i] | some i, x in check.checks; not _for_reads_an_alias(check, x)],
})

_for_with_free(check, subj, names, item, w, r) := object.union(r, {"cause": free.cause, "free_lines": free.lines}) if {
	r.cause == "satisfied"
	_for_none_kept(item, w, names)
	free := _for_lines(_for_unaliased(check), subj, names)
	not free.passed
} else := r

_for_outer_of(check, subj, names) := {"cause": w.unread, "inputs": _for_inputs(check, subj, names, check.items[0], w), "failed": _for_failed(check, w.unread, [object.union(f, {"lines": []}) | some f in w.fails])} if {
	w := _for_walk(check.items[0], subj, names)
	"unread" in object.keys(w)
} else := {"cause": cause, "inputs": _for_inputs(check, subj, names, check.items[0], _for_walk(check.items[0], subj, names)), "failed": _for_failed(check, cause, [object.union(f, {"lines": []}) | some f in _for_pick_fails(check, pre)])} if {
	pre := _for_pre(check, subj, names)
	pre != null
	"pick" in object.keys(check.items[1])
	not _for_pick_reads_first(check)
	cause := _for_pick_failure(pre)
} else := _for_with_free(check, subj, names, item, w, {"cause": cause, "inputs": inputs, "failed": failed, "passed_items": passed}) if {
	item := check.items[0]
	w := _for_walk(item, subj, names)
	pre := _for_pre(check, subj, names)
	raw := [_for_judge_outer(check, subj, names, item, e, pre, w) | some e in w.items]
	judged := _for_copies_merged(item, names, w, raw)
	passed := _for_passed_items(item, w, raw)
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	failed := _for_failed(check, cause, _for_shared(check, fails, pre, names))
	inputs := _for_inputs(check, subj, names, item, w)
}

_for_passed_items(item, w, raw) := {w.items[k].i | some k, j in raw; j.passed} if item.q == "some"

else := set()

_for_unwalked(check, w) := [f | some f in array.concat(w.fails, _walk_stop(w))] if not "unread" in object.keys(w)

else := w.fails if w.fails != []

else := [object.union({"path": check.items[1].path, "item": check.items[1].path, "cause": w.unread, "value": null}, object.get(w, "unread_at", {}))]

_m_unread_text(f) := f.msg if is_array(object.get(f, "msg", null))

else := []

_m_inner_fail(x) := x.text if count(object.get(x, "text", [])) > 0

else := [_m_named_fail(object.union(x, {"path": object.get(x, "msg", x.path)}))]

_m_unread_names(path, subj, f) := {"msg": ms} if {
	f.path == path
	f.value == null
	is_array(path)
	ms := [_m_name_state(n, v) | some seg in path; [n, v] := _m_step_name(seg, subj); not is_string(v)]
	ms != []
} else := {}

_m_step_name(seg, _) := [seg.named_by, object.get(input, ["ergo/names", seg.named_by], _absent)] if _name_step(seg)

_m_step_name(seg, subj) := [_fk(seg), object.get(_fb(subj, seg), _fk(seg), _absent)] if {
	_field_step(seg)
	is_object(subj)
}

_m_name_state(n, v) := concat("", [n, " is missing"]) if v == _absent

else := concat("", [n, " is null"]) if v == null

else := _m_isnt(n, v, "text")

_for_pick_fails(check, pre) := _for_unwalked(check, pre) if pre.walked == set()

else := pre.fails

_for_shared(_, fails, null, _) := fails

_for_shared(check, fails, pre, names) := array.concat([trimmed[i] | some i, f in fails; not _for_only_shared(f, trimmed[i])], shared) if {
	pre != null
	seen := {h.path | some f in fails; some h in object.get(f, "inner", [])}
	shared := [object.union(g, {"hoisted": true}) | some g in array.concat([object.union(f, {"lines": []}) | some f in _for_unwalked(check, pre)], _for_free_undecided(check, pre, names)); g.path in seen]
	paths := {g.path | some g in shared}
	trimmed := [_for_trim(f, [g | some g in object.get(f, "inner", []); not g.path in paths]) | some f in fails]
}

_for_free_undecided(check, _, _) := [] if _for_whose_reads(check.items[1].whose, check.items[0].as)

_for_free_undecided(check, pre, names) := [{"path": e.i, "item": e.i, "rest": _for_rest(e), "cause": wh.undecided[0], "value": _walk_value(e.v, e, pre), "lines": [], "at": _walk_at(pre, e)} |
	some e in pre.items
	wh := _for_whose(check.items[1], e, names)
	wh.undecided != []
] if not _for_whose_reads(check.items[1].whose, check.items[0].as)

_for_whose_reads(whose, name) if {
	some c in whose
	_reads_name(c, name)
}

_for_trim(f, own) := object.union(f, {"inner": own, "cause": _walk_worst([{"cause": c} | some c in ({l.cause | some l in f.lines} | {g.cause | some g in own})])}) if {
	count(own) < count(object.get(f, "inner", []))
	count(f.lines) + count(own) > 0
} else := object.union(f, {"inner": own})

_for_only_shared(f, t) if {
	f.lines == []
	object.get(f, "inner", []) != []
	t.inner == []
}

_for_walk(item, subj, names) := _for_picked(item, w, names) if {
	keys := _walk_keys(item, subj) with input as {"ergo/names": names}
	w := _walk(_walk_start(item, subj), keys, _for_empty_ok(item)) with input as {"ergo/names": names}
} else := object.union({"items": [], "fails": _for_null_fails(item, subj, names), "walked": set(), "trail": [], "unread": _for_unread(subj, item.path, names)}, _unread_at(subj, item, names))

_for_unread(subj, path, names) := _key_state(object.get(_fb(subj, path[i]), _fk(path[i]), _absent)) if {
	is_object(subj)
	i := _bad_field_at(subj, path)
	_open_before_field(subj, array.slice(path, 0, i)) with input as {"ergo/names": names}
} else := "null" if {
	is_object(subj)
	i := _bad_field_at(subj, path)
	_null_before_field(subj, array.slice(path, 0, i)) with input as {"ergo/names": names}
} else := s if {
	s := _walk_read_state(subj, path) with input as {"ergo/names": names}
}

_open_before_field(subj, prefix) if _read_before_field(_resolved(subj, prefix))

_open_before_field(subj, prefix) if _walks_before_field(subj, prefix)

_unread_at(subj, item, names) := {"unread_at": {"at": at}} if at := _unread_pointer(subj, item.path) with input as {"ergo/names": names}

else := {}

_unread_pointer(subj, path) := _pointer(_start_at(path), start, _leading_keys(subj, path)) if start := _start_of(subj, path)

_for_empty_ok(item) if "pick" in object.keys(item)

else := item.if_any == true

_for_picked(item, w, _) := w if not "pick" in object.keys(item)

_for_picked(item, w, _) := w if {
	"pick" in object.keys(item)
	w.walked == set()
}

_for_picked(item, w, names) := _for_pick_sorted(item, object.union(w, {"items": kept}), w.items, names) if {
	"pick" in object.keys(item)
	w.walked != set()
	judged := [[e, _for_whose(item, e, names)] | some e in w.items]
	whose_fails := [{"path": j[0].i, "item": j[0].i, "cause": j[1].undecided[0], "value": _walk_value(j[0].v, j[0], w), "at": _walk_at(w, j[0])} | some j in judged; j[1].undecided != []]
	kept := [j[0] | some j in judged; j[1].undecided == []; j[1].kept]
	_for_no_fails(w, whose_fails)
}

_for_picked(item, w, names) := object.union(w, {"items": [], "fails": array.concat(w.fails, whose_fails), "input": _for_list_input(item, w)}) if {
	"pick" in object.keys(item)
	w.walked != set()
	whose_fails := [object.union({"path": e.i, "item": e.i, "rest": _for_rest(e), "cause": wh.undecided[0], "value": _walk_value(e.v, e, w), "at": _walk_at(w, e)}, _for_raw(e)) | some e in w.items; wh := _for_whose(item, e, names); wh.undecided != []]
	not _for_no_fails(w, whose_fails)
}

_for_no_fails(w, whose_fails) if {
	w.fails == []
	whose_fails == []
}

_for_pick_sorted(item, w, read, names) := object.union(w, {"items": [], "fails": bad, "input": _for_list_input(item, object.union(w, {"items": read}))}) if {
	bad := _for_unsortable(item, w, names)
	bad != []
} else := object.union(w, {"items": read, "unread": "absent"}) if {
	not _for_pick_index(item, w.items, names)
} else := object.union(w, {"items": [], "fails": tied, "input": _for_list_input(item, object.union(w, {"items": read}))}) if {
	tied := _for_tied(item, w, names)
	count(tied) > 1
} else := object.union(w, {"items": [e], "input": [_path_name(e.i), _walk_value(e.v, e, w), [_walk_at(w, e)]]}) if {
	e := w.items[_for_pick_index(item, w.items, names)]
}

_for_pick_failure(w) := w.unread if "unread" in object.keys(w)

else := _walk_worst(fails) if {
	fails := array.concat(w.fails, _walk_stop(w))
	fails != []
}

_for_list_input(item, w) := [_walk_name(item.path, w.walked), [_walk_value(e.v, e, w) | some e in w.items], _walk_locations(w)]

_for_sort_key(item, x, names) := _for_sortable_exact(_for_sortable(v, object.get(item.pick, "alphabetically", false)), [json.marshal(v) | is_number(v)]) if {
	"by" in object.keys(item.pick)
	e := _focus_entry(x)
	is_object(e.iv)
	v := _resolved(e.iv, item.pick.by) with input as {"ergo/names": names}
}

_for_sortable_exact(k, []) := k

_for_sortable_exact(k, [t]) := [k[0], json.unmarshal(t)]

_for_sortable(v, false) := ["number", v] if is_number(v)

_for_sortable(v, false) := ["time", _time_ns(v)] if _rfc3339_shaped(v)

_for_sortable(v, false) := ["date", v] if _date_shaped(v)

_for_sortable(v, true) := ["text", v] if is_string(v)

_for_kept_kind(kinds) := [k | some k in ["number", "time", "date", "text"]; k in kinds][0]

_for_unsortable(item, _, _) := [] if not "by" in object.keys(item.pick)

_for_unsortable(item, w, names) := array.concat(unread, mixed) if {
	"by" in object.keys(item.pick)
	items := w.items
	unread := [object.union({"path": e.i, "item": e.i, "cause": _for_sort_state(item, e, names), "value": _for_sort_shown(item, e, names), "raw": _focus_entry(e).iv, "at": _for_sort_at(item, w, e, names)}, _m_sort_why(item, _focus_entry(e), names)) | some e in items; not _for_sort_key(item, e, names)]
	kinds := {_for_sort_key(item, e, names)[0] | some e in items}
	mixed := [{"path": e.i, "item": e.i, "cause": "unusable", "value": _for_sort_shown(item, e, names), "at": _for_sort_at(item, w, e, names), "why": [_m_leaf(_focus_entry(e).i, _m_isnt(_input_name(item.pick.by), _for_sort_shown(item, e, names), _m_kind_word[_for_kept_kind(kinds)]))]} |
		count(kinds) > 1
		some e in items
		_for_sort_key(item, e, names)[0] != _for_kept_kind(kinds)
	]
}

_m_sort_why(item, e, names) := {"why": [m]} if {
	is_object(e.iv)
	state := _for_sort_state(item, e, names)
	m := _m_sort_text(item, e, state) with input as {"ergo/names": names}
	startswith(m, "$")
} else := {"why": [_m_leaf(e.i, m)]} if {
	is_object(e.iv)
	state := _for_sort_state(item, e, names)
	m := _m_sort_text(item, e, state) with input as {"ergo/names": names}
} else := {}

_m_kind_word := {"number": "a number", "time": "a time", "date": "a date", "text": "text"}

_m_sort_kind(true) := "text"

_m_sort_kind(false) := "a number, a time or a date"

_m_sort_text(item, e, state) := _message({"op": "present", "path": item.pick.by}, e.iv, state) if state in {"absent", "null"}

else := m if {
	ms := _m_key_faults(e.iv, {"op": "present", "path": item.pick.by})
	ms != []
	m := concat(", and ", ms)
} else := m if {
	ms := _m_blocked(e.iv, {"op": "present", "path": item.pick.by})
	ms != []
	m := concat(", and ", ms)
} else := _m_isnt(_input_name(item.pick.by), v, _m_sort_kind(object.get(item.pick, "alphabetically", false))) if {
	v := _resolved(e.iv, item.pick.by)
	v != _absent
}

_for_sort_state(item, x, names) := s if {
	e := _focus_entry(x)
	is_object(e.iv)
	s := _walk_read_state(e.iv, item.pick.by) with input as {"ergo/names": names}
	s != "value"
} else := "unusable" if is_object(_focus_entry(x).iv)

else := "not_an_object"

_for_sort_at(item, w, x, names) := _item_read_at(w, _focus_entry(x), item.pick.by) if is_object(_focus_entry(x).iv) with input as {"ergo/names": names}

else := _item_at(w, _focus_entry(x))

_for_sort_shown(item, x, names) := _walk_shown(v) if {
	e := _focus_entry(x)
	is_object(e.iv)
	v := _resolved(e.iv, item.pick.by) with input as {"ergo/names": names}
}

else := null

_for_order(item, items, names) := [pair[2] | some pair in sort([[k, _tie_rank(keys, i), i] | some i, k in keys])] if {
	"by" in object.keys(item.pick)
	keys := [_for_sort_key(item, e, names)[1] | some e in items]
}

_tie_rank(keys, i) := count([j | some j, k in keys; k == keys[i]; is_number(k); _text_order(json.marshal(k), json.marshal(keys[i])) < 0])

_for_order(item, items, _) := numbers.range(0, count(items) - 1) if not "by" in object.keys(item.pick)

_for_pick_index(item, items, names) := order[_for_pick_slot(item.pick, count(order))] if {
	order := _for_order(item, items, names)
	count(items) > 0
}

_for_pick_slot(pick, n) := pick.at - 1 if {
	not pick.from_last
	pick.at <= n
}

_for_pick_slot(pick, n) := n - pick.at if {
	pick.from_last
	pick.at <= n
}

_for_tied(item, _, _) := [] if not "by" in object.keys(item.pick)

_for_tied(item, w, names) := [{"path": e.i, "item": e.i, "cause": "ambiguous", "value": _for_sort_shown(item, e, names), "at": _for_sort_at(item, w, e, names)} |
	some e in w.items
	k := _for_sort_key(item, e, names)[1]
	k == key
	_same_texts(json.marshal(k), json.marshal(key))
] if {
	"by" in object.keys(item.pick)
	key := _for_sort_key(item, w.items[_for_pick_index(item, w.items, names)], names)[1]
}

_for_pre(check, subj, names) := _for_walk(check.items[1], subj, names) if {
	count(check.items) == 2
	not _for_from_first(check)
	not _for_pick_reads_first(check)
} else := w if {
	count(check.items) == 2
	not _for_from_first(check)
	_for_pick_reads_first(check)
	w := _for_plain_walk(check, subj, names)
	w.walked == set()
} else := null

_for_plain_walk(check, subj, names) := _for_walk(object.union(object.remove(check.items[1], ["pick", "whose"]), {"if_any": true}), subj, names)

_for_pick_reads_first(check) if {
	"pick" in object.keys(check.items[1])
	_for_whose_reads(check.items[1].whose, check.items[0].as)
}

_for_from_first(check) if check.items[1].path[0] == concat("", ["$", check.items[0].as])

_for_from_first(check) if {
	some step in check.items[1].path
	_name_step(step)
	step.named_by == check.items[0].as
}

_for_judge_outer(check, subj, names, item, e, pre, w) := {"passed": res.passed, "kept": wh.kept, "failure": _for_why(true, item, e, names, wh, _for_failure(e, wh.undecided, wh.kept, res, _walk_at(w, e))), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_outer_next(check, subj, _bound(names, item.as, e.v, _walk_at(w, e)), wh.undecided, wh.kept, pre)
}

_for_judge_inner(check, subj, names, item, e, w) := {"passed": res.passed, "kept": wh.kept, "failure": _for_why(false, item, e, names, wh, _for_failure(e, wh.undecided, wh.kept, res, _walk_at(w, e))), "lines": res.lines} if {
	wh := _for_whose(item, e, names)
	res := _for_inner_next(check, subj, _bound(names, item.as, e.v, _walk_at(w, e)), wh.undecided, wh.kept)
}

_for_copies_merged(item, _, _, judged) := judged if object.get(item, "distinct", false) != true

_for_copies_merged(item, names, w, judged) := [_for_copied(j, i, w, copies) | some i, j in judged; not i in copies.dropped] if {
	object.get(item, "distinct", false) == true
	copies := _for_copies(item, names, w)
}

_for_copied(j, i, w, copies) := object.union(j, {"failure": _copied_failure(j.failure, [_walk_at(w, w.items[k]) | some k in copies.groups[i]])}) if {
	j.failure != null
	i in object.keys(copies.groups)
} else := j

_copied_failure(f, ats) := object.union(f, {"ats": ats})

_copied_line(l, c) := object.union(l, object.union({"inputs": _copied_inputs(l.inputs, c) | "inputs" in object.keys(l)}, {"items": [object.union(x, {"inputs": _copied_inputs(x.inputs, c)}) | some x in l.items] | "items" in object.keys(l)}))

_copied_inputs(xs, c) := [object.union(x, {"locations": _copied_locations(x.locations, c)}) | some x in xs]

_copied_locations(ls, c) := [m | some l in ls; some m in _copied_location(l, c)]

_copied_location(l, c) := [concat("", [a, substring(l, count(c.from), -1)]) | some a in c.to] if _under_location(l, c.from)

else := [l]

_under_location(l, at) if l == at

_under_location(l, at) if startswith(l, concat("", [at, "/"]))

_for_whose(item, e, names) := {"undecided": _for_undecided(undecided, kept, e), "kept": kept} if {
	causes := [_for_focus_cause(c, e) | some c in item.whose] with input as {"ergo/names": names}
	undecided := [c | some c in causes; not c in {"satisfied", "value"}]
	kept := count([c | some c in causes; c == "value"]) == 0
}

_for_focus_cause(c, e) := "unusable" if {
	_node_param_broken(c)
} else := _focus_cause(c, e)

_for_undecided(undecided, true, e) := _for_worst_first(array.concat(undecided, _for_mark_cause(e)))

_for_undecided(undecided, false, _) := _for_worst_first(undecided)

_for_worst_first(causes) := array.concat([c | some p in _cause_precedence; some c in causes; c == p], [c | some c in causes; not c in _cause_precedence])

_for_mark_cause(e) := ["not_an_object"] if {
	_walk_marked(e.v)
	not is_object(e.iv)
}

_for_mark_cause(e) := ["absent"] if {
	e.v == _absent
	is_object(e.iv)
}

_for_mark_cause(e) := ["unusable"] if {
	e.v == _unusable_mark
	is_object(e.iv)
}

_for_mark_cause(e) := [] if not _walk_marked(e.v)

_for_outer_next(_, _, _, undecided, _, _) := {"passed": false, "cause": undecided[0], "lines": []} if undecided != []

_for_outer_next(_, _, _, [], false, _) := {"passed": false, "cause": "value", "lines": []}

_for_outer_next(check, subj, bound, [], true, null) := _for_inner(check, subj, bound, _for_walk(check.items[1], subj, bound)) if count(check.items) == 2

_for_outer_next(check, subj, bound, [], true, pre) := _for_inner(check, subj, bound, pre) if pre != null

_for_outer_next(check, subj, bound, [], true, _) := _for_lines(check, subj, bound) if count(check.items) == 1

_for_inner_next(_, _, _, undecided, _) := {"passed": false, "cause": undecided[0], "lines": []} if undecided != []

_for_inner_next(_, _, _, [], false) := {"passed": false, "cause": "value", "lines": []}

_for_inner_next(check, subj, bound, [], true) := _for_lines(check, subj, bound)

_for_failure(_, [], false, _, _) := null

_for_failure(e, undecided, _, res, at) := object.union({"path": e.i, "item": e.i, "rest": _for_rest(e), "cause": res.cause, "value": _walk_value(e.v, e, at), "lines": res.lines, "inner": object.get(res, "unchecked", []), "at": at}, _for_raw(e)) if undecided != []

_for_failure(e, [], true, res, at) := {"path": e.i, "item": e.i, "rest": _for_rest(e), "cause": res.cause, "value": _walk_value(e.v, e, at), "lines": res.lines, "inner": object.get(res, "unchecked", []), "at": at, "nothing_picked": object.get(res, "nothing_picked", false)} if not res.passed

_for_failure(_, [], true, res, _) := null if res.passed

_for_raw(e) := {"raw": e.iv} if {
	_walk_marked(e.v)
	not is_object(e.iv)
} else := {}

_for_inner(check, subj, names, w) := {"passed": false, "cause": "not_an_object", "lines": []} if {
	check.items[1].path[0] == concat("", ["$", check.items[0].as])
	count(check.items[1].path) > 1
	not is_object(names[check.items[0].as])
	not _for_alias_list(check.items[1], names[check.items[0].as])
} else := {"passed": false, "cause": w.unread, "lines": [], "unchecked": [], "nothing_picked": true} if {
	"unread" in object.keys(w)
	"pick" in object.keys(check.items[1])
	not _for_from_first(check)
	w.walked != set()
} else := {"passed": false, "cause": w.unread, "lines": [], "unchecked": u} if {
	"unread" in object.keys(w)
	u := [object.union(f, _m_unread_names(check.items[1].path, subj, f)) | some f in _for_unwalked(check, w)] with input as {"ergo/names": names}
} else := res if {
	item := check.items[1]
	judged := _for_copies_merged(item, names, w, [_for_judge_inner(check, subj, names, item, e, w) | some e in w.items])
	fails := array.concat(array.concat([object.union(f, {"lines": []}) | some f in w.fails], [object.union(f, {"lines": []}) | some f in _walk_stop(w)]), [j.failure | some j in judged; j.failure != null])
	cause := _for_verdict(item, w, judged, fails)
	res := _for_inner_result(check, subj, names, judged, fails, cause)
}

_for_inner_result(check, subj, names, judged, fails, cause) := _for_lines(_for_without(check, check.items[1].as), subj, names) if {
	cause == "satisfied"
	check.items[1].if_any == true
	every j in judged {
		j.kept == false
	}
} else := {"passed": cause == "satisfied", "cause": cause, "lines": _for_merge_lines(check, cause, fails), "unchecked": [f | some f in fails; f.lines == []]}

_for_without(check, name) := object.union(check, {
	"checks": [c | some c in check.checks; not _reads_name(c, name)],
	"assertions": [check.assertions[i] | some i, c in check.checks; not _reads_name(c, name)],
})

_for_lines(check, subj, names) := {"passed": count(lines) == 0, "cause": _all_of_cause(lines), "lines": lines} if {
	lines := [object.union({"assertion": check.assertions[i], "cause": cause, "inputs": _for_line_inputs(check, c, read), "msg": [_m_aliased(x) | some x in m]}, _m_own_msg(check, c, m, count(read) == 1)) |
		some i, c in check.checks
		cause := _for_cause(c, subj) with input as {"ergo/names": names}
		cause != "satisfied"
		read := _for_read(c, subj) with input as {"ergo/names": names}
		m := _m_line(c, subj, cause) with input as {"ergo/names": names}
	]
}

_for_cause(c, subj) := e.cause if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := _assertion_cause(c, subj, "unusable") if {
	not _walks(c)
	_node_param_broken(c)
} else := _assertion_cause(c, subj, "")

_for_read(c, subj) := _with_key_fields(subj, c, e.inputs) if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := _with_key_fields(subj, c, _assertion_inputs(subj, c))

_for_merge_lines(_, "satisfied", _) := []

_for_merge_lines(check, cause, fails) := [object.union({"assertion": a, "cause": _walk_worst([{"cause": c} | some c in causes])}, _for_line_items(check, i, a, fails)) |
	some i, a in check.assertions
	causes := [l.cause | some f in fails; some l in f.lines; l.assertion == a]
	count(causes) > 0
] if cause != "satisfied"

_for_line_inputs(check, c, inputs) := array.concat([r | some i in inputs; r := _for_renamed(check, i); r.name != i.name], [i | some i in inputs; _for_renamed(check, i).name == i.name]) if _walks(c)

_for_line_inputs(check, c, inputs) := [_for_renamed(check, i) | some i in inputs] if not _walks(c)

_for_renamed(check, i) := object.union(i, {"name": _for_input_name(i.name, {item.as | some item in check.items})})

_for_input_name(name, aliases) := concat("", [parts[0], alias, rest]) if {
	parts := split(name, "\u0002")
	count(parts) == 2
	regex.match(`^(?:item [0-9]+ of )?$`, parts[0])
	some alias in aliases
	startswith(parts[1], alias)
	rest := substring(parts[1], count(alias), -1)
	_alias_rest(rest)
} else := name

_alias_rest("")

_alias_rest(rest) if regex.match(`^[.\[ ]`, rest)

_for_line_items(check, i, a, fails) := {"items": [{"item": _for_item_name(check, f.path), "cause": l.cause, "inputs": l.inputs, "msg": [_m_under(_m_for_item_name(check, f.path), x) | some x in l.msg], "own": _m_own_under(_m_for_item_name(check, f.path), object.get(l, "own_msg", null))} |
	some p in sort({f.path | some f in fails; some l in f.lines; l.assertion == a})
	some f in fails
	f.path == p
	some l in f.lines
	l.assertion == a
]} if _reads_name(check.checks[i], check.items[1].as)

else := {"inputs": _for_line_first_inputs(a, fails), "msg": _for_line_first_msg(a, fails)}

_for_line_first_msg(a, fails) := ms[0] if ms := [l.msg | some f in fails; some l in f.lines; l.assertion == a]

_for_line_first_inputs(a, fails) := inputs[0] if inputs := [l.inputs | some f in fails; some l in f.lines; l.assertion == a]

_reads_name(c, name) if {
	walk(c, [at, x])
	not _under_data(at)
	not _under_literal(c, at)
	_name_read(x, name)
}

_under_data(at) if {
	some k in at
	k in {"value", "values", "patterns", "min", "max"}
}

_name_read(x, name) if {
	is_array(x)
	count(x) > 0
	x[0] == concat("", ["$", name])
}

_name_read(x, name) if {
	is_object(x)
	x.named_by == name
}

_for_item_name(check, p) := _input_name(array.concat([substring(p[0], 1, -1)], array.slice(p, 1, count(p)))) if p[0] in {concat("", ["$", item.as]) | some item in check.items}

else := _failed_name(p, _for_dotted(check))

_m_for_item_name(check, p) := _input_name(array.slice(p, 1, count(p))) if {
	p[0] in {concat("", ["$", item.as]) | some item in check.items}
	_m_unaliased(p)
}

_m_for_item_name(check, p) := _for_item_name(check, p) if {
	p[0] in {concat("", ["$", item.as]) | some item in check.items}
	not _m_unaliased(p)
}

_m_for_item_name(check, p) := _m_item_name(p, _for_dotted(check)) if not p[0] in {concat("", ["$", item.as]) | some item in check.items}

_m_unaliased(p) if {
	count(p) > 2
	not is_number(p[1])
	startswith(p[0], "$")
}

_for_verdict(item, w, judged, fails) := _walk_stop(w)[0].cause if {
	w.walked == set()
	count(_walk_stop(w)) > 0
} else := _walk_verdict(item.q, item.if_any == true, judged, fails)

_for_dotted(check) := _dotted_roots([item.path | some item in check.items])

_dotted_roots(paths) := {p[0].literal |
	some p in paths
	is_array(p)
	_string_literal(p[0])
	not startswith(p[0].literal, "$")
}

default _dotted_root(_, _) := false

_dotted_root(path, roots) if path[0] in roots

_failed_name(path, roots) := _input_name(path) if not _dotted_root(path, roots)

_failed_name(path, roots) := _with_dot(_input_name(path), true) if _dotted_root(path, roots)

_for_failed(_, "satisfied", _) := []

_for_failed(check, cause, fails) := [object.union(object.union({"path": _failed_name(f.path, _for_dotted(check)), "item": _failed_name(f.item, _for_dotted(check)), "cause": f.cause, "value": f.value, "failed_assertions": f.lines, "locations": _fail_locations(f), "said": _m_for_item_name(check, f.item), "bare": _m_rest_named(_m_for_item_name(check, f.item), f)}, _for_unchecked(check, object.get(f, "inner", []))), object.union(object.union({"msg": f.why | "why" in object.keys(f)}, {"raw": f.raw | "raw" in object.keys(f)}), {"hoisted": true | object.get(f, "hoisted", false) == true})) |
	some p in sort({f.path | some f in fails; not object.get(f, "nothing_picked", false)})
	some f in fails
	f.path == p
	not object.get(f, "nothing_picked", false)
] if cause != "satisfied"

_for_unchecked(_, []) := {}

_for_unchecked(check, inner) := {"failed_items": [{"path": _for_item_name(check, f.path), "item": _for_item_name(check, f.item), "cause": f.cause, "value": f.value, "locations": _fail_locations(f), "msg": _m_rest_named(_m_for_item_name(check, f.path), f), "text": _m_root_why(f), "free": object.get(f, "free", false)} |
	some p in sort({f.path | some f in inner})
	some f in inner
	f.path == p
]} if inner != []

_for_inputs(check, subj, names, item, w) := _merged_inputs([{"name": t[0], "value": t[1], "locations": t[2]} | some t in (_for_input_pairs(check, subj, names, item, w) | _for_listed_pairs(check, subj))])

_for_listed_pairs(check, subj) := {[r.name, r.value, r.locations] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	_for_listed(subj, c, p)
	r := _rwalk(subj, p)
}

_for_listed(subj, c, p) if {
	_for_listed_right(c, p)
	not _named(p)
	_rwalks(subj, p)
}

_for_listed(subj, c, p) if {
	_for_listed_right(c, p)
	_list_start(p, subj)
	_rwalks(subj, p)
}

_for_listed(subj, c, p) if {
	_for_listed_right(c, p)
	is_string(p[0])
	_parent_name(p[0])
	_rwalks(subj, p)
}

_for_listed_right(c, p) if {
	_list_cmp(c)
	not _one_right(c)
	p == c.right
}

_for_input_pairs(check, subj, names, item, w) := (((((((((({object.get(w, "input", _for_list_input(item, w))} | _for_inner_pairs(check, subj, names, item, w)) | {[_input_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	not _for_listed(subj, c, p)
	shown := _before_names(p)
}) | {[_input_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	not _walks(c)
	some p in _leaf_paths(c)
	_starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	not _for_listed(subj, c, p)
	shown := _before_later_names(p)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	some side in _derived_sides(c)
	not _tally_named(check, side)
	some i in _for_side_inputs(subj, side)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	some side in _derived_sides(c)
	_tally_named(check, side)
	some part in _tally_parts(side)
	some i in _tally_kept_inputs(check, subj, part)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	not _for_alias_path(check, c.path)
	some i in _walk_read_row(c, subj).inputs
	not i in _named_inputs(subj, [p | some p in _walk_condition_paths(c); _for_alias_path(check, p)])
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	_for_alias_path(check, c.path)
	some i in array.concat(_conds_named_inputs_but(subj, array.concat([c.check], c.whose), {p | some p in _walk_condition_paths(c); _for_alias_path(check, p)}), _input_ref_inputs(array.concat([c.check], c.whose)))
}) | {[_input_name(shown), _value_at(subj, shown), _locations_of(subj, shown)] |
	some c in check.checks
	_walks(c)
	shown := _before_alias_name(check, subj, c.path)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	_walks(c)
	some i in _named_inputs(subj, [shown | some p in _walk_condition_paths(c); shown := _before_alias_name(check, subj, p)])
}) | {[_input_name([f]), _value_at(subj, [f]), _locations_of(subj, [f])] |
	some f in _for_key_fields(check)
}) | {[i.name, i.value, i.locations] |
	some c in check.checks
	c.op in _right_ref_ops
	some i in _ref_inputs(object.remove(c, ["path"]))
}

_for_side_inputs(subj, side) := array.concat([i | some i in _side_inputs(subj, side); not i in held], [_path_input(subj, x[0]) | some x in xs]) if {
	xs := [x | some t in _tally_parts(side); some x in _listed_reads(subj, t.whose)]
	held := {x[1] | some x in xs}
}

_for_alias_path(check, p) if p[0] in {concat("", ["$", item.as]) | some item in check.items}

_for_alias_path(_, p) if _has_name_step(p)

_before_alias_name(check, subj, p) := shown if {
	_has_name_step(p)
	_starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	shown := _before_later_names(p)
	not _through_list(subj, shown)
}

_before_alias_name(check, subj, p) := shown if {
	_has_name_step(p)
	not _starts_at_name(p)
	not p[0] in {concat("", ["$", item.as]) | some item in check.items}
	shown := _before_names(p)
	not _through_list(subj, shown)
}

_through_list(subj, path) if {
	count(path) > 1
	some i in numbers.range(1, count(path) - 1)
	is_array(_value_at(subj, array.slice(path, 0, i)))
}

_for_key_fields(check) := ({_fk(seg) |
	some item in check.items
	some seg in item.path
	_field_step(seg)
} | {f | some c in check.checks; some f in _key_fields(c)}) | {_fk(seg) |
	some c in check.checks
	contains(json.marshal(c), "\\u0003")
	walk(c, [_, seg])
	_subject_keyed_step(seg)
}

_subject_keyed_step(seg) if {
	is_object(seg)
	is_string(object.get(seg, "named_by_field", null))
	startswith(seg.named_by_field, _subject_key)
}

_for_inner_pairs(check, _, _, _, _) := set() if count(check.items) == 1

_for_inner_pairs(check, subj, names, item, w) := {[_for_list_name(check, check.items[1].path, walked), values, locations]} if {
	count(check.items) == 2
	_for_from_first(check)
	dropped := _for_dropped(item, names, w)
	inner := [_for_walk(check.items[1], subj, _bound(names, item.as, e.v, _walk_at(w, e))) |
		some i, e in w.items
		not i in dropped
		wh := _for_whose(item, e, names)
		wh.undecided == []
		wh.kept
	]
	walked := {i | some iw in inner; some i in iw.walked}
	values := [_walk_value(e2.v, e2, iw) | some iw in inner; some e2 in iw.items]
	locations := [_walk_at(iw, e2) | some iw in inner; some e2 in iw.items]
}

_for_inner_pairs(check, subj, names, item, w) := {object.get(iw, "input", [_for_list_name(check, check.items[1].path, iw.walked), [_walk_value(e.v, e, iw) | some e in iw.items], _walk_locations(iw)]) | some iw in inner} if {
	count(check.items) == 2
	not _for_from_first(check)
	_for_pick_reads_first(check)
	w.items != []
	dropped := _for_dropped(item, names, w)
	inner := [_for_walk(check.items[1], subj, _bound(names, item.as, e.v, _walk_at(w, e))) | some i, e in w.items; not i in dropped]
}

_for_dropped(item, _, _) := set() if object.get(item, "distinct", false) != true

_for_dropped(item, names, w) := _for_copies(item, names, w).dropped if object.get(item, "distinct", false) == true

_for_copies(item, names, w) := _copies_of([[keys[i], i] | some i, e in w.items; wh := _for_whose(item, e, names); wh.kept; wh.undecided == []; not _walk_marked(e.v)]) if {
	vs := [e.v | some e in w.items]
	keys := _exact_keys(vs, json.marshal(vs))
}

_for_inner_pairs(check, subj, names, _, w) := {object.get(pw, "input", [_for_list_name(check, check.items[1].path, pw.walked), [_walk_value(e.v, e, pw) | some e in pw.items], _walk_locations(pw)])} if {
	count(check.items) == 2
	not _for_from_first(check)
	_for_pick_reads_first(check)
	w.items == []
	pw := _for_plain_walk(check, subj, names)
}

_for_inner_pairs(check, subj, names, _, _) := {object.get(iw, "input", [_for_list_name(check, check.items[1].path, iw.walked), [_walk_value(e.v, e, iw) | some e in iw.items], _walk_locations(iw)])} if {
	count(check.items) == 2
	not _for_from_first(check)
	not _for_pick_reads_first(check)
	iw := _for_walk(check.items[1], subj, names)
}

_tally_named(check, side) if {
	some p in _side_paths(side)
	_for_alias_path(check, p)
}

_tally_named(check, side) if {
	some t in _tally_parts(side)
	some c in t.whose
	some p in _condition_paths(c)
	_for_alias_path(check, p)
}

_tally_kept_inputs(check, subj, part) := _basic_inputs(subj, part) if not _tally_named(check, part)

_tally_kept_inputs(check, subj, part) := array.concat(
	array.concat(
		[_tally_list_input(_tally(subj, part)) | not _for_alias_path(check, part[_basic_form(part)])],
		[{"name": _input_name(shown), "value": _value_at(subj, shown), "locations": _locations_of(subj, shown)} | shown := _before_alias_name(check, subj, part[_basic_form(part)])],
	),
	_merged_inputs(array.concat(
		array.concat(
			_for_conds_named_inputs(subj, part.whose, {p | some c in part.whose; some p in _condition_paths(c); _for_alias_path(check, p)}),
			_named_inputs(subj, [shown | some c in part.whose; some p in _condition_paths(c); shown := _before_alias_name(check, subj, p)]),
		),
		_input_ref_inputs(part.whose),
	)),
) if _tally_named(check, part)

_tally_parts(side) := [side] if _basic_form(side) in {"count_of", "sum_of"}

_tally_parts(side) := [o | some o in side.add; _basic_form(o) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_for_list_name(check, path, walked) := substring(_walk_name(path, walked), 1, -1) if path[0] in {concat("", ["$", item.as]) | some item in check.items}

_for_list_name(check, path, walked) := _walk_name(path, walked) if not path[0] in {concat("", ["$", item.as]) | some item in check.items}

_starts_at_name(p) if {
	_off_subject(p)
	not _builtin(p)
}

_before_names(p) := p if {
	not _starts_at_name(p)
	not _has_name_step(p)
} else := array.slice(p, 0, i) if {
	not _starts_at_name(p)
	i := min([j | some j, step in p; _name_step(step)])
	i > 0
}

_before_later_names(p) := array.slice(p, 0, min(array.concat([count(p)], [j | some j, step in p; j > 0; _name_step(step)])))

_has_name_step(p) if {
	is_array(p)
	some step in p
	_name_step(step)
}
