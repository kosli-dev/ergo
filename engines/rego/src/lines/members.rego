package ergo

import rego.v1

_fm_mark := {"ergo/member": true}

default _member_from(_) := false

_member_from(req) if {
	object.get(data.ergo_subject_sentences, "member", set()) != set()
	is_object(req)
	is_string(object.get(req, "subject", null))
	some m in graph.reachable({n: object.get(object.get(data.ergo_subject_sentences, "narrowing", {}), n, []) | some n, _ in data.ergo_resolved}, [req.subject])
	m in object.get(data.ergo_subject_sentences, "member", set())
}

_fl_keys(req) := array.concat(_from_keys(req), [_fm_mark]) if _member_from(req)

else := _from_keys(req)

_fm_keyed(keys) if {
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

_fm_end_fail(e) := _fl_fail(e, _walk_state(e.v)) if _fl_gone(e.v)

else := object.union(_fl_fail(e, "unusable"), {"why": {"path": e.c, "value": e.v, "kind": "an object"}})
