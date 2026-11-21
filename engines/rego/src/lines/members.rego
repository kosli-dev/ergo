package ergo

import rego.v1

_fm_mark := {"ergo/member": true}

default _fm_any := false

_fm_any if some _ in data.ergo_subject_sentences.member

default _member_from(_) := false

_member_from(req) if {
	_fm_any
	is_object(req)
	is_string(object.get(req, "subject", null))
	some m in graph.reachable({n: object.get(object.get(data.ergo_subject_sentences, "narrowing", {}), n, []) | some n, _ in data.ergo_resolved}, [req.subject])
	m in object.get(data.ergo_subject_sentences, "member", set())
}

_fl_keys(req) := array.concat(_from_keys(req), [_fm_mark]) if _member_from(req)

else := _from_keys(req)

_fm_keyed(keys) if {
	_fm_any
	count(keys) > 0
	keys[count(keys) - 1] == _fm_mark
}

_fm_path(keys) := array.slice(keys, 0, count(keys) - 1)

_fm_walk(doc, keys) := r if {
	l0 := _fm_level([{"c": [], "i": [], "v": doc, "x": false}], keys, 0)
	l1 := _fm_level(l0.next, keys, 1)
	l2 := _fm_level(l1.next, keys, 2)
	l3 := _fm_level(l2.next, keys, 3)
	l4 := _fm_level(l3.next, keys, 4)
	l5 := _fm_level(l4.next, keys, 5)
	l6 := _fm_level(l5.next, keys, 6)
	l7 := _fm_level(l6.next, keys, 7)
	l8 := _fm_level(l7.next, keys, 8)
	l9 := _fm_level(l8.next, keys, 9)
	r := _fm_result(doc, keys, [l0, l1, l2, l3, l4, l5, l6, l7, l8, l9], l9.next)
}

_fm_level(es, keys, i) := {"next": es, "fails": [], "lists": false, "notes": []} if i >= count(keys)

else := _fl_level(es, keys, i)

_fm_result(doc, keys, levels, ends) := object.union(_every_walk(doc, keys), {"subjects": [], "notes": []}) if {
	not _fm_listed(levels)
	some e in ends
	_fl_gone(e.v)
} else := {"subjects": [{"subject": m.v, "at": _joined(_doc_at, m.c), "c": m.c, "key": m.k} | some m in members], "fails": [_fl_at(doc, f) | some f in fails], "notes": [_fl_note_at(doc, n) | some n in array.concat([n | some l in levels; some n in l.notes], _fl_type_note(members))]} if {
	members := [m | some e in ends; _fm_object(e.v); some k in sort(object.keys(e.v)); m := {"c": array.concat(e.c, [k]), "v": e.v[k], "k": k}]
	fails := array.concat([f | some l in levels; some f in l.fails], [_fm_end_fail(e) | some e in ends; not _fm_object(e.v)])
}

_fm_listed(levels) if {
	some l in levels
	l.lists
}

_fm_object(v) if {
	is_object(v)
	not _walk_marked(v)
}

_fm_entries_of(entries, req) := _fm_entries(entries, _id_of(req)) if _member_from(req)

else := entries

_fm_entries(entries, []) := entries

_fm_entries(entries, ids) := [object.remove(e, ["key"]) | some e in entries] if ids != []

_fm_end_fail(e) := _fl_fail(object.union({"w": null}, e), _walk_state(e.v)) if _fl_gone(e.v)

else := object.union(_fl_fail(object.union({"w": null}, e), "unusable"), {"why": {"path": e.c, "value": e.v, "kind": "an object"}})

_walk_members(keys) if {
	count(keys) > 0
	keys[count(keys) - 1] == _fm_mark
}

_member_walk(start, keys, if_any) := {"items": items, "fails": fails, "walked": walked, "trail": trail, "members": true} if {
	r0 := _member_list_level([start], keys, 0, if_any, start)
	r1 := _member_list_level(r0.entries, keys, 1, if_any, start)
	r2 := _member_list_level(r1.entries, keys, 2, if_any, start)
	r3 := _member_list_level(r2.entries, keys, 3, if_any, start)
	r4 := _member_list_level(r3.entries, keys, 4, if_any, start)
	r5 := _member_list_level(r4.entries, keys, 5, if_any, start)
	r6 := _member_list_level(r5.entries, keys, 6, if_any, start)
	r7 := _member_list_level(r6.entries, keys, 7, if_any, start)
	r8 := _member_list_level(r7.entries, keys, 8, if_any, start)
	r9 := _member_list_level(r8.entries, keys, 9, if_any, start)
	levels := [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9]
	lists := {i | some i, r in levels; r.walked}
	stops := _member_stops(lists, r9.entries)
	walked := lists | {"members" | not stops}
	fails := [object.union(f, {"at": _pointer(start.a, start.v, array.slice(f.path, count(start.c), count(f.path))), "lv": _list_levels(start, f.path)}) | some f in array.concat([f | some r in levels; some f in r.fails], [f | not stops; some e in r9.entries; some f in _member_fails(e, if_any)])]
	items := [m | not stops; some e in r9.entries; _fm_object(e.v); some k in sort(object.keys(e.v)); m := {"c": array.concat(e.c, [{"member": k}]), "v": e.v[k], "i": array.concat(e.c, [{"member": k}]), "iv": e.v[k], "r": []}]
	trail := array.concat([start], [r.entries[0] | some i, r in levels; i < count(keys) - 1; count(r.entries) == 1])
}

_member_list_level(entries, keys, i, if_any, start) := _walk_level(entries, keys, i, if_any, start) if i < count(keys) - 1

else := {"entries": entries, "fails": [], "walked": false}

default _member_stops(_, _) := false

_member_stops(set(), ends) if {
	some e in ends
	not _fm_object(e.v)
}

_member_fails(e, if_any) := [{"path": e.c, "item": e.c, "cause": _walk_state(e.v), "value": _walk_shown(e.v), "msg": "an object"}] if {
	_ = if_any
	not _fm_object(e.v)
} else := [{"path": e.c, "item": e.c, "cause": "value", "value": {}, "msg": ""}] if {
	e.v == {}
	if_any == false
} else := []
