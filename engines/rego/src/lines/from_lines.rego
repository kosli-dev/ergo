package ergo

import rego.v1

_size(x) := count(x) if type_name(x) in {"array", "object", "set", "string"}

_from_path(req) := array.slice(_from_of(req), 0, count(_from_of(req)) - 1) if _has_step(req)

_from_path(req) := _from_of(req) if not _has_step(req)

default _has_step(_) := false

_has_step(req) if _each_step(req)

_each_step(req) := req["ergo/fixed"].each_step[0] if _has_fixed(req)

_each_step(req) := _each_step_of(req) if not _has_fixed(req)

_has_fixed(req) if is_set(req["ergo/fixed"].mark)

_with_fixed(req) := object.union(req, {"ergo/fixed": {
	"mark": set(),
	"each_step": [step | step := _each_step_of(req)],
	"has_parts": _has_parts_of(req),
	"names_subject": _names_subject_of(req),
	"tagging": _tagging_of(req),
	"scoped": _scoped_of(req),
}}) if is_object(req)

_each_step_of(req) := step if {
	f := _from_of(req)
	is_array(f)
	count(f) > 0
	step := f[count(f) - 1]
	is_object(step)
	not _is_ref(step)
}

default _stepped(_) := false

_stepped(req) if {
	f := _from_of(req)
	is_array(f)
	some seg in f
	is_object(seg)
	not _is_ref(seg)
}

default _from_well_formed(_) := false

_from_well_formed(req) if {
	is_object(req)
	is_array(_from_of(req))
	not _stepped(req)
}

_from_well_formed(req) if {
	_each_step(req)
	every seg in _from_path(req) {
		_plain_step(seg)
	}
}

_plain_step(seg) if not is_object(seg)

_plain_step(seg) if _is_ref(seg)

_valid_name(n) if {
	is_string(n)
	n != ""
	not startswith(n, "$")
	not n in {"params", "input"}
}

_listed_keys(step) := v if {
	_is_ref(step.keys)
	v := _ref_read(step.keys.ref)
	is_array(v)
}

_target(doc, req) := object.get(doc, _from_keys(req), null) if is_object(doc)

_target(doc, req) := object.get({"v": doc}, array.concat(["v"], _from_keys(req)), null) if _array_read(doc, req)

_target_read(doc, req) := object.get(doc, _from_keys(req), _absent) if is_object(doc)

_target_read(doc, req) := doc if {
	not _is_collection(doc)
	_from_keys(req) == []
}

_target_read(doc, req) := object.get({"v": doc}, array.concat(["v"], _from_keys(req)), _absent) if _array_read(doc, req)

_target_read(doc, req) := _absent if {
	not is_object(doc)
	count(_from_keys(req)) > 0
	not _array_read(doc, req)
}

default _array_read(_, _) := false

_array_read(doc, req) if {
	is_array(doc)
	not _keys_step(req)
	_from_keys(req) == []
}

_array_read(doc, req) if {
	is_array(doc)
	_index_step(_from_keys(req)[0])
}

_target_cause(doc, req) := c if {
	_from_well_formed(req)
	not _from_unreadable(req)
	not _keys_step(req)
	not _every_from(req)
	c := _target_state(doc, req)
	c != "value"
}

_target_cause(doc, req) := c if {
	_from_well_formed(req)
	not _from_unreadable(req)
	_every_from(req)
	c := _every_cause(doc, req)
}

_target_cause(doc, req) := c if {
	_from_well_formed(req)
	not _from_unreadable(req)
	_keys_step(req)
	c := _keyed_state(doc, req)
}

_keyed_state(doc, req) := "not_an_object" if {
	_target_state(doc, req) == "not_an_object"
} else := "unusable" if {
	_fl_keyed_met_at(doc, req)
} else := c if {
	c := _target_state(doc, req)
	c != "value"
} else := "unusable" if is_array(_target_read(doc, req))

default _walkable(_) := false

_walkable(doc) if is_object(doc)

_walkable(doc) if is_array(doc)

_every_cause(doc, req) := c if {
	not _walkable(doc)
	_every_unwalked(doc)
	c := _target_state(doc, req)
	c != "value"
} else := _worst_of({f.cause | some f in w.fails} | {"unusable" | count(w.notes) > 0}) if {
	w := _fl_broken(doc, _from_keys(req))
	count(w.fails) + count(w.notes) > 0
}

_every_unwalked(doc) if doc != null

_every_unwalked(_) if is_object(data.ergo_parent)

default _every_from(_) := false

_every_from(req) if {
	is_object(req)
	is_string(object.get(req, "subject", null))
	some m in graph.reachable({n: object.get(object.get(data.ergo_subject_sentences, "narrowing", {}), n, []) | some n, _ in data.ergo_resolved}, [req.subject])
	m in object.get(data.ergo_subject_sentences, "every", set())
}

_every_walk(doc, keys) := {"subjects": [{"subject": e.v, "at": _walk_at(w, e)} | some e in w.items; last], "fails": array.concat(array.concat(w.fails, _walk_stop(w)), [object.union(_every_end_fail(e), {"at": _walk_at(w, e)}) | some e in w.items; not last])} if {
	w := _walk({"c": [], "v": doc, "i": null, "iv": null, "r": [], "a": _doc_at}, keys, true)
	last := count(keys) in w.walked
}

_every_end_fail(e) := {"path": e.c, "item": e.c, "cause": _walk_stop_state(e.v), "value": _walk_value(e.v, e, null)}

_fl_walk(doc, keys) := {"subjects": [{"subject": x, "at": concat("", [base, "/", format_int(i, 10)])} | some i, x in end], "fails": [], "notes": []} if {
	end := _fl_simple_end(doc, keys)
	base := _joined(_doc_at, keys)
} else := _fl_full_walk(doc, keys)

_fl_broken(doc, keys) := {"fails": [], "notes": []} if {
	_fl_simple_end(doc, keys)
} else := _fl_full_walk(doc, keys)

_fl_simple_end(doc, keys) := end if {
	end := _fl_value_at(doc, keys, count(keys))
	is_array(end)
	every j in numbers.range(0, count(keys) - 1) {
		is_object(_fl_value_at(doc, keys, j))
	}
	count({_fl_type(x) | some x in end; x != null}) < 2
}

_fl_full_walk(doc, keys) := r if {
	l0 := _fl_level([{"c": [], "i": [], "v": doc, "x": false}], keys, 0)
	l1 := _fl_level(l0.next, keys, 1)
	l2 := _fl_level(l1.next, keys, 2)
	l3 := _fl_level(l2.next, keys, 3)
	l4 := _fl_level(l3.next, keys, 4)
	l5 := _fl_level(l4.next, keys, 5)
	l6 := _fl_level(l5.next, keys, 6)
	l7 := _fl_level(l6.next, keys, 7)
	l8 := _fl_level(l7.next, keys, 8)
	l9 := _fl_level(l8.next, keys, 9)
	l10 := _fl_level(l9.next, keys, 10)
	r := _fl_result(doc, keys, [l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10], l10.next)
}

_fl_result(doc, keys, levels, ends) := {"subjects": [{"subject": e.v, "at": _joined(_doc_at, e.c)} | some e in kept], "fails": [_fl_at(doc, f) | some f in fails], "notes": [_fl_note_at(doc, n) | some n in array.concat([n | some l in levels; some n in l.notes], _fl_type_note(kept))]} if {
	some l in levels
	l.lists
	kept := [e | some e in ends; _fl_kept_end(e)]
	fails := array.concat([f | some l in levels; some f in l.fails], [_fl_fail(e, _walk_state(e.v)) | some e in ends; not _fl_kept_end(e)])
} else := object.union(_every_walk(doc, keys), {"notes": []})

_fl_at(doc, f) := object.union(f, {"at": _pointer(_doc_at, doc, f.path)})

_fl_note_at(doc, n) := object.union(n, {"items": [_fl_at(doc, f) | some f in n.items]})

_fl_level(es, keys, i) := {"next": es, "fails": [], "lists": false, "notes": []} if i > count(keys)

_fl_level(es, keys, i) := {"next": next, "fails": array.concat(gone, bad), "lists": lists, "notes": _fl_mixed_note(es, lists)} if {
	i <= count(keys)
	lists := _fl_lists_here(es, keys, i)
	gone := [_fl_fail(e, _walk_state(e.v)) | some e in es; _fl_dropped(e, lists)]
	expanded := [x | some e in es; not _fl_dropped(e, lists); some x in _fl_expand(e, lists)]
	bad := [_fl_item_fail(x) | some x in expanded; _fl_list_item_read(x, keys, i)]
	next := [_fl_step(x, keys, i) | some x in expanded; not _fl_list_item_read(x, keys, i)]
}

_fl_lists_here(es, keys, i) if {
	_fl_reads(keys, i)
	some e in es
	is_array(e.v)
} else := false

_fl_reads(keys, i) if i == count(keys)

_fl_reads(keys, i) if {
	i < count(keys)
	not is_number(keys[i])
}

_fl_dropped(e, true) if {
	not is_array(e.v)
	_fl_gone(e.v)
}

_fl_gone(v) if _walk_marked(v)

_fl_gone(null)

_fl_expand(e, lists) := [{"c": array.concat(e.c, [j]), "i": array.concat(e.c, [j]), "v": x, "x": true, "w": null} | some j, x in e.v] if {
	lists
	is_array(e.v)
} else := [e]

_fl_list_item_read(x, keys, i) if {
	i < count(keys)
	is_string(keys[i])
	x.x
	not is_object(x.v)
	x.v != null
}

_fl_step(x, keys, i) := x if i >= count(keys)

_fl_step(x, keys, i) := {"c": array.concat(x.c, [keys[i]]), "i": x.i, "v": _walk_read(x.v, keys[i], x, null), "x": false, "w": _fl_why(x, keys[i])} if i < count(keys)

_fl_why(x, k) := x.w if {
	_walk_marked(x.v)
	_is_key(k)
} else := {"path": x.c, "value": x.v, "kind": _fl_wanted(k)} if {
	not _fl_readable(x.v, k)
	x.v != null
} else := null

_fl_wanted(k) := "an object" if is_string(k)

else := "a list"

_fl_readable(v, k) if {
	is_string(k)
	is_object(v)
}

_fl_readable(v, k) if {
	is_number(k)
	is_array(v)
}

_fl_fail(e, cause) := {"path": e.c, "item": e.c, "cause": cause, "value": _walk_value(e.v, e, null), "why": e.w}

_fl_item_fail(x) := {"path": x.c, "item": x.c, "cause": _fl_item_cause(x.v), "value": x.v, "why": {"path": x.c, "value": x.v, "kind": "an object"}}

_fl_item_cause(v) := "not_an_object" if is_array(v)

else := "unusable"

_fl_note_item(path, v) := {"path": path, "item": path, "cause": "unusable", "value": v}

_fl_kept_end(e) if {
	not _walk_marked(e.v)
	e.v != null
}

_fl_kept_end(e) if {
	e.v == null
	e.x
}

_fl_mixed_note(es, lists) := [{"list": ls[0], "other": os[0], "items": [_fl_note_item(ls[0].c, ls[0].v), _fl_note_item(os[0].c, os[0].v)]}] if {
	lists
	ls := [e | some e in es; is_array(e.v)]
	os := [e | some e in es; not is_array(e.v); not _fl_gone(e.v)]
	count(os) > 0
} else := []

_fl_type_note(kept) := [{"types": types, "items": [_fl_note_item(t[1], t[2]) | some t in types]}] if {
	typed := [[_fl_type(e.v), e.c, e.v] | some e in kept; e.v != null]
	ks := sort({min({i | some i, x in typed; x[0] == t}) | some t in {x[0] | some x in typed}})
	count(ks) > 1
	types := [typed[k] | some k in ks]
} else := []

_fl_type(v) := "an object" if is_object(v)

else := "a list" if is_array(v)

else := "text" if is_string(v)

else := "a number" if is_number(v)

else := "true or false"

_fl_plain_types(doc, req) := [{"types": types, "plain": true, "items": [_fl_at(doc, _fl_note_item(t[1], t[2])) | some t in types]}] if {
	coll := _target(doc, req)
	is_array(coll)
	count({_fl_type(x) | some x in coll; x != null}) > 1
	not _every_from(req)
	not _keys_step(req)
	keys := _from_keys(req)
	typed := [[_fl_type(x), array.concat(keys, [i]), x] | some i, x in coll; x != null]
	ks := sort({min({i | some i, x in typed; x[0] == t}) | some t in {x[0] | some x in typed}})
	count(ks) > 1
	types := [typed[k] | some k in ks]
}

_fl_note_text(req, n) := concat(", ", [concat("", [_fl_type_name(req, n, t[1]), " is ", t[0]]) | some t in n.types]) if "types" in object.keys(n)

_fl_type_name(req, n, path) := _visible_path_name(_visible(path), _m_from_root(req)) if object.get(n, "plain", false) == true

else := _m_from_item_name(req, path)

_fl_note_text(req, n) := concat("", [_fl_field_name(n.list), " is a list in ", a, " but ", _literal_text(n.other.v), " in ", _fl_other_item(a, b)]) if {
	"list" in object.keys(n)
	a := _m_from_item_name(req, n.list.i)
	b := _m_from_item_name(req, n.other.i)
}

_fl_field_name(e) := _plain_steps_name(array.slice(e.c, count(e.i), count(e.c)))

_fl_other_item(a, b) := concat("", ["item ", mb[1]]) if {
	ma := regex.find_all_string_submatch_n(`^item [0-9]+ of (.+)$`, a, 1)[0]
	mb := regex.find_all_string_submatch_n(`^item ([0-9]+) of (.+)$`, b, 1)[0]
	ma[1] == mb[2]
	not contains(ma[1], ":")
} else := b

_fl_key_names(req) := count([k | some k in _from_keys(req); is_string(k)])

_fl_many_names(req) if _fl_key_names(req) + count([1 | _chained(req)]) > 1

else if {
	_fl_key_names(req) + count([1 | _chained(req)]) == 1
	_fl_rooted(req)
}

_fl_rooted(req) if object.get(object.get(data.ergo_subject_sentences, "rooted", {}), req.subject, false) == true

_fl_named_start(req) if _chained(req)

_fl_named_start(req) if _fl_rooted(req)

_fl_value_at(doc, _, 0) := doc

_fl_value_at(doc, keys, j) := object.get(doc, array.slice(keys, 0, j), _absent) if {
	j > 0
	is_object(doc)
}

_fl_value_at(doc, keys, j) := object.get({"v": doc}, array.concat(["v"], array.slice(keys, 0, j)), _absent) if {
	j > 0
	not is_object(doc)
}

_fl_point(keys, j, _) if j == count(keys)

_fl_point(keys, j, _) if {
	j > 0
	j < count(keys)
	is_string(keys[j])
}

_fl_point(keys, 0, req) if {
	count(keys) > 0
	is_string(keys[0])
	_fl_named_start(req)
}

_fl_met_at(doc, req) := js[0] if {
	_fl_many_names(req)
	not _keys_step(req)
	not _every_from(req)
	keys := _from_keys(req)
	js := [j | some j in numbers.range(0, count(keys)); _fl_point(keys, j, req); is_array(_fl_value_at(doc, keys, j))]
	count(js) > 0
}

_fl_keyed_met_at(doc, req) := js[0] if {
	_keys_step(req)
	keys := _from_keys(req)
	js := [j | some j in numbers.range(0, count(keys)); _fl_keyed_point(keys, j, req); is_array(_fl_value_at(doc, keys, j))]
	count(js) > 0
}

_fl_keyed_point(keys, j, req) if {
	j > 0
	_fl_point(keys, j, req)
}

_fl_keyed_point(keys, 0, req) if {
	_fl_named_start(req)
	not _fl_index_first(keys)
}

_fl_index_first(keys) if _index_step(keys[0])

_fl_list_name(req, 0) := _m_from_root(req)

_fl_list_name(req, j) := _visible_path_name(array.slice(_from_keys(req), 0, j), _m_from_root(req)) if j > 0

_fl_plain_message(doc, req) := concat("", [_fl_list_name(req, j), " is a list: write ", data.ergo_subject_sentences.every_text[req.subject], " to read each item"]) if {
	j := _fl_met_at(doc, req)
} else := concat("", [_fl_list_name(req, j), " is a list, but named by each of reads the keys of one object: make each item a subject and read the keys in it"]) if {
	j := _fl_keyed_met_at(doc, req)
} else := _fl_note_text(req, _fl_plain_typed(doc, req))

_fl_plain_typed(doc, req) := n if {
	not _from_unreadable(req)
	not _fl_met_at(doc, req)
	_target_state(doc, req) == "unusable"
	[n] := _fl_plain_types(doc, req)
}

_fl_failed(doc, req) := array.concat(w.fails, [f | some n in w.notes; some f in n.items]) if w := _fl_broken(doc, _from_keys(req))

_fl_items(req, fails) := [x |
	some p in sort({f.path | some f in fails})
	some x in {{"path": _fl_fail_name(req, f.path), "item": _fl_fail_name(req, f.item), "cause": f.cause, "value": f.value, "locations": _fail_locations(f)} | some f in fails; f.path == p}
]

_fl_fail_text(req, f) := _m_isnt(_m_from_item_name(req, f.why.path), f.why.value, f.why.kind) if is_object(object.get(f, "why", null))

else := _m_named_fail(object.union(f, {"path": _m_from_item_name(req, f.path)}))

_fl_typed_only(doc, req) if {
	not _every_from(req)
	_fl_plain_typed(doc, req)
}

_fl_typed_only(doc, req) if {
	_every_from(req)
	_walkable(doc)
	_fl_broken(doc, _from_keys(req)).fails == []
}

_fl_fail_name(req, path) := _visible_path_name(_visible(path), _m_from_root(req)) if {
	path != []
	_chained(req)
} else := _input_path_name(path)

_fl_parent_unread(doc, req) if {
	_chained(req)
	not _walkable(doc)
}

_fl_parent_unread(doc, req) if {
	_chained(req)
	doc == _absent
}

_keys_step(req) if "keys" in object.keys(_each_step(req))

_target_state(doc, req) := "not_an_object" if {
	is_object(data.ergo_parent)
	not is_object(doc)
	_reads_inside_parent(req)
	not _starts_at_position(req)
} else := "unusable" if {
	_fl_met_at(doc, req)
} else := "unusable" if {
	_fl_plain_types(doc, req)
} else := _from_state(doc, req)

_starts_at_position(req) if _index_step(_from_keys(req)[0])

_reads_inside_parent(req) if count(_from_keys(req)) > 0

_reads_inside_parent(req) if _keys_step(req)

default _from_state(_, _) := "absent"

_from_state(doc, req) := "null" if _target_read(doc, req) == null

_from_state(doc, req) := "unusable" if {
	is_array(doc)
	not _array_read(doc, req)
}

_from_state(doc, req) := "unusable" if {
	_target_read(doc, req) == _absent
	_blocked(doc, _from_keys(req))
}

_from_state(doc, req) := "unusable" if {
	v := _target_read(doc, req)
	v != _absent
	v != null
	not _is_collection(v)
	not _fl_scalar_subject(v, req)
}

_from_state(doc, req) := "value" if _fl_scalar_subject(_target_read(doc, req), req)

_fl_scalar_subject(v, req) if {
	v != _absent
	v != null
	not _is_collection(v)
	not _keys_step(req)
	_fl_reads_inside(req)
}

_fl_reads_inside(req) if count(_from_keys(req)) > 0

_from_state(doc, req) := "value" if {
	v := _target_read(doc, req)
	v != _absent
	_is_collection(v)
}

_from_keys(req) := ks if {
	p := _from_path(req)
	is_array(p)
	ks := [_step_key(seg) | some seg in p]
	count(ks) == count(p)
}

_from_unreadable(_) if _unreadable_input

_from_unreadable(req) if {
	p := _from_path(req)
	is_array(p)
	some seg in p
	_is_ref(seg)
	not _step_key(seg)
}

_from_unreadable(req) if {
	step := _each_step(req)
	_is_ref(step.keys)
	not _listed_keys(step)
}

_from_unreadable(req) if {
	some k in _listed_keys(_each_step(req))
	not is_string(k)
}

_from_cause(req) := "unusable" if {
	some r in _m_from_ref_list(req)
	_m_from_params_unread(r.ref)
} else := flaws[0] if {
	flaws := _from_path_flaws(req)
	count(flaws) > 0
} else := _worst_of(unread) if {
	unread := {_ref_state(r) | some r in _keys_refs(_each_step(req))} - {"value"}
	count(unread) > 0
} else := "unusable"

_from_path_flaws(req) := [f | some seg in p; f := _ref_step_flaw(seg)] if {
	p := _from_path(req)
	is_array(p)
}

_keys_refs(step) := {step.keys.ref} if _is_ref(step.keys)

_listed_subjects(doc, req) := [] if {
	_fl_met_at(doc, req)
} else := [{"subject": subj, "at": concat("", [base, "/", format_int(i, 10)])} | some i, subj in coll] if {
	coll := _target(doc, req)
	is_array(coll)
	base := _pointer(_doc_at, doc, _from_keys(req))
} else := [{"subject": coll, "at": _pointer(_doc_at, doc, _from_keys(req))}] if {
	coll := _target(doc, req)
	is_object(coll)
} else := [{"subject": v, "at": _pointer(_doc_at, doc, _from_keys(req))}] if {
	v := _target_read(doc, req)
	_fl_scalar_subject(v, req)
} else := []

_raw_entries(doc, req) := [entry | some entry in _listed_subjects(doc, req)] if {
	not _stepped(req)
	_from_well_formed(req)
	not _every_from(req)
}

_raw_entries(doc, req) := _distinct_entries(_fl_walk(doc, _from_keys(req)).subjects, req) if {
	_from_well_formed(req)
	_every_from(req)
	_walkable(doc)
}

_distinct_entries(entries, req) := _copies_merged(entries) if _distinct_from(req)

else := entries

default _distinct_from(_) := false

_distinct_from(req) if {
	object.get(data.ergo_subject_sentences, "distinct", set()) != set()
	is_object(req)
	is_string(object.get(req, "subject", null))
	some m in graph.reachable({n: object.get(object.get(data.ergo_subject_sentences, "narrowing", {}), n, []) | some n, _ in data.ergo_resolved}, [req.subject])
	m in object.get(data.ergo_subject_sentences, "distinct", set())
}

_copies_merged(entries) := [_with_copies(entries, i, copies) | some i, e in entries; not i in copies.dropped] if {
	subjects := [e.subject | some e in entries]
	keys := _exact_keys(subjects, json.marshal(subjects))
	copies := _copies_of([[keys[i], i] | some i, _ in entries])
}

_with_copies(entries, i, copies) := object.union(entries[i], {"ats": [entries[k].at | some k in copies.groups[i]]}) if i in object.keys(copies.groups)

else := entries[i]

_matching_ats(matching, req) := [m.at | some m in matching] if not _distinct_from(req)

else := [a | some m in matching; some a in object.get(m, "ats", [m.at])]

_raw_entries(doc, req) := [] if {
	_from_well_formed(req)
	_every_from(req)
	not _walkable(doc)
}

_raw_entries(_, req) := [] if {
	_from_well_formed(req)
	_every_from(req)
	not _from_keys_read(req)
}

_from_keys_read(req) if _from_keys(req)

_raw_entries(doc, req) := [{"key": k, "subject": object.get(_keyed(doc, req), [k], _absent), "at": _pointer(_doc_at, doc, array.concat(_from_keys(req), [k]))} | some k in sort({k | some k in _listed_keys(_each_step(req))})] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	_listed_keys(_each_step(req))
	not _from_unreadable(req)
	_target_state(doc, req) != "not_an_object"
}

_raw_entries(_, req) := [] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	not _listed_keys(_each_step(req))
}

_raw_entries(_, req) := [] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	_listed_keys(_each_step(req))
	_from_unreadable(req)
}

_raw_entries(doc, req) := [] if {
	_from_well_formed(req)
	"keys" in object.keys(_each_step(req))
	_listed_keys(_each_step(req))
	not _from_unreadable(req)
	_target_state(doc, req) == "not_an_object"
}

_keyed(doc, req) := coll if {
	coll := _target(doc, req)
	is_object(coll)
}

_keyed(doc, req) := {} if not _target_is_object(doc, req)

_target_is_object(doc, req) if is_object(_target(doc, req))

_scope_of(req, subj) := {"ergo/names": object.union(object.union(object.union(names, _parent_names), _subject_name(req, subj)), {"$at": {"names": _name_ats(req), "subject": _subject_at}})} if names := _each_names(req, subj)

_name_ats(req) := object.union({_each_step(req).each_as: _subject_at}, _parent_ats) if {
	_has_step(req)
	_from_well_formed(req)
}

_name_ats(req) := _parent_ats if not _has_step(req)

_subject_name(req, subj) := {"ergo/subject": subj} if _carries_subject(req)

_subject_name(req, _) := {} if not _carries_subject(req)

_carries_subject(req) if _has_parts(req)

_carries_subject(req) if _names_subject(req)

default _names_subject(_) := false

_names_subject(req) if {
	_has_fixed(req)
	req["ergo/fixed"].names_subject == true
}

_names_subject(req) if {
	not _has_fixed(req)
	_names_subject_of(req)
}

default _names_subject_of(_) := false

_names_subject_of(req) if _names_subject_in(req)

_names_subject_of(req) if _names_subject_in(_applies_to_of(req))

_names_subject_of(req) if _has_root_field(req)

_names_subject_of(req) if _has_for_check(req)

_has_for_check(req) if {
	is_object(req)
	is_object(req.checks)
	some c in req.checks
	is_object(c)
	_for_check(c)
}

_for_check(c) if c.op == "for"

_for_check(c) if "for" in object.keys(c)

_names_subject_of(req) if _has_root_field(_applies_to_of(req))

_has_root_field(x) if {
	contains(json.marshal(x), "\\u0002")
	walk(x, [_, s])
	is_string(s)
	startswith(s, _root_key)
}

_has_root_field(x) if {
	contains(json.marshal(x), "\\u0003")
	walk(x, [_, s])
	is_string(s)
	startswith(s, _subject_key)
}

_names_subject_in(req) if {
	contains(json.marshal(req), "\\\"of\\\":null")
	walk(req, [_, s])
	is_string(s)
	startswith(s, "${\"alias\":")
	contains(s, "\"of\":null")
	_subject_part([s])
}

_subjects_with_parts := {name | some name, parts in object.get(data.ergo_subject_sentences, "parts", {}); count(parts) > 0}

default _has_parts(_) := false

_has_parts(req) if {
	_has_fixed(req)
	req["ergo/fixed"].has_parts == true
}

_has_parts(req) if {
	not _has_fixed(req)
	_has_parts_of(req)
}

default _has_parts_of(_) := false

_has_parts_of(req) if {
	is_string(object.get(req, "subject", null))
	req.subject in _subjects_with_parts
}

_each_names(req, subj) := {_each_step(req).each_as: subj} if {
	_has_step(req)
	_from_well_formed(req)
}

_each_names(req, _) := {} if not _has_step(req)

default _parent_names := {}

_parent_names := data.ergo_parent if is_object(data.ergo_parent)

_scoped(req) if {
	_has_fixed(req)
	req["ergo/fixed"].scoped == true
}

_scoped(req) if {
	not _has_fixed(req)
	_scoped_of(req)
}

default _scoped_of(_) := false

_scoped_of(req) if _has_step(req)

_scoped_of(_) if _parent_names != {}

_scoped_of(req) if {
	_carries_subject(req)
	_reads_whole_subject(req)
}

_reads_whole_subject(req) if _has_old_marker(req)

_reads_whole_subject(req) if _has_old_marker(_applies_to_of(req))

_reads_whole_subject(req) if _has_root_field(req)

_reads_whole_subject(req) if _has_for_check(req)

_has_old_marker(x) if {
	walk(x, [_, s])
	is_string(s)
	startswith(s, "${\"alias\":")
	_part_start([s])
	_part_of([s]).old == true
}

_applies_evals(req, subj, flaws) := {name: _filter_eval(req, check, subj, flaws[name]) | some name, check in _applies_to_of(req)} if not _scoped(req)

else := evals if {
	_scoped(req)
	s := _scope_of(req, subj)
	evals := {name: _filter_eval(req, check, subj, flaws[name]) | some name, check in _applies_to_of(req)} with input as s
}

_filter_eval(req, check, subj, flaw) := object.union(
	{
		"passed": _filter_walk_passed(flaw, w),
		"cause": _filter_walk_cause(flaw, w),
		"assertion_cause": w.cause,
		"inputs": _tagged(_with_key_fields(subj, check, w.inputs), check, req, subj),
		"failed_items": w.failed,
	},
	_m_filter_walk(_named_check(check, req, subj), subj, _filter_walk_passed(flaw, w), _filter_walk_cause(flaw, w), w),
) if {
	_walks(check)
	w := _walk_row(check, subj)
}

_filter_eval(req, check, subj, flaw) := _m_filter(_named_check(check, req, subj), subj, {
	"passed": passed,
	"cause": _filter_cause(check, subj, flaw),
	"assertion_cause": _filter_assertion_cause(passed, check, subj, flaw),
	"inputs": _tagged(_row_inputs(subj, check), check, req, subj),
}) if {
	not _walks(check)
	passed := _check_passed(check, subj, flaw)
}

_filter_walk_passed("", w) := w.cause == "satisfied"

_filter_walk_passed(flaw, _) := false if flaw != ""

_filter_walk_cause("", w) := w.cause

_filter_walk_cause(flaw, _) := flaw if flaw != ""

_filter_assertion_cause(true, _, _, _) := "satisfied"

_filter_assertion_cause(false, check, subj, flaw) := _assertion_cause(check, subj, flaw)

_outcome(req, written, flaw, subj) := _tagged_outcome(_messaged(_check_outcome(_walk_labelled(check, req, subj), subj, flaw), check, req, subj), check, req, subj) if {
	not _scoped(req)
	check := _list_read(written, req, subj)
} else := o if {
	_scoped(req)
	check := _list_read(written, req, subj)
	s := _scope_of(req, subj)
	raw := _messaged(_check_outcome(_walk_labelled(check, req, subj), subj, flaw), check, req, subj) with input as s
	o := _tagged_failures(object.union(raw, {"inputs": _tagged(raw.inputs, check, req, subj)}), check, req, subj) with input as s
}

_list_read(check, req, subj) := _ls_check(check, req.subject) if {
	is_array(subj)
	is_string(object.get(req, "subject", null))
	is_object(check)
	not _reads_root_field(check)
} else := check

_reads_root_field(check) if {
	walk(check, [_, s])
	_field_step(s)
	_from_root(s)
}

_ls_check(check, l) := object.union(check, {"checks": [_ls_unit(c, l) | some c in check.checks]}) if {
	check.op in {"all_of", "sentence_any_of"}
	is_array(object.get(check, "checks", null))
} else := check if {
	_ls_plain_read(check)
} else := object.union(check, {"items": [_ls_item(it, l) | some it in check.items], "checks": [_ls_leaf(c, l) | some c in check.checks]}) if {
	check.op == "for"
	is_array(object.get(check, "items", null))
	is_array(object.get(check, "checks", null))
} else := _ls_leaf(check, l)

_ls_unit(c, l) := c if _ls_plain_read(c)

else := _ls_leaf(c, l)

_ls_plain_read(c) if {
	walk(c, [jp, x])
	_ls_root_read(x)
	not _ls_walk_pos(c, jp)
}

_ls_plain_read(c) if {
	c.op == "for"
	some s in c.checks
	walk(s, [jp, x])
	count(jp) == 1
	_ls_top_read(x)
	not _ls_walk_pos(s, jp)
}

_ls_root_read(x) if {
	is_array(x)
	count(x) > 1
	_part_start(x)
	_part_of(x).of == null
	not _index_step(x[1])
}

_ls_top_read(x) if {
	is_array(x)
	count(x) > 0
	not _named(x)
	not _index_step(x[0])
}

_ls_top_read(x) if {
	is_array(x)
	some step in x
	_field_step(step)
	not _from_root(step)
}

_ls_walk_pos(_, jp) if jp[count(jp) - 1] in {"count_of", "sum_of"}

_ls_walk_pos(c, jp) if {
	jp[count(jp) - 1] == "right"
	parent := object.get(c, array.slice(jp, 0, count(jp) - 1), null)
	_list_cmp(parent)
	not _one_right(parent)
}

_ls_walk_pos(c, jp) if {
	jp[count(jp) - 1] == "path"
	parent := object.get(c, array.slice(jp, 0, count(jp) - 1), null)
	_ls_walker(parent)
}

_ls_walker(parent) if parent.op in {"every", "some"}

_ls_walker(parent) if is_string(object.get(parent, "as", null))

_ls_item(it, l) := object.union(it, {"path": _ls_path(it.path, l, false), "whose": [_ls_sides(w, l, true) | some w in it.whose]}) if {
	is_object(it)
	not "pick" in object.keys(it)
	is_array(object.get(it, "whose", null))
}

else := it

_ls_leaf(c, l) := object.union(c, {"path": _ls_path(c.path, l, false), "check": _ls_sides(c.check, l, true), "whose": [_ls_sides(w, l, true) | some w in c.whose]}) if {
	c.op in {"every", "some"}
	is_array(object.get(c, "whose", null))
} else := _ls_sides(c, l, false)

_ls_sides(c, l, rooted) := object.union(c, {"left": _ls_tally(c.left, l, rooted), "right": _ls_right(c, l, rooted)}) if {
	is_object(c)
	c.op == "compare"
} else := c

_ls_right(c, l, rooted) := _ls_path(c.right, l, rooted) if {
	_list_cmp(c)
	not _one_right(c)
} else := _ls_tally(c.right, l, rooted)

_ls_tally(side, l, rooted) := object.union(side, {"add": [_ls_operand(o, l, rooted) | some o in side.add]}) if {
	_side_form(side) == "add"
	is_array(object.get(side, "add", null))
} else := _ls_operand(side, l, rooted)

_ls_operand(side, l, rooted) := object.union(side, object.union({f: _ls_path(side[f], l, rooted) | some f in ["count_of", "sum_of"]; is_array(object.get(side, f, null))}, {"whose": [_ls_cond(w, l) | some w in side.whose]})) if {
	_basic_form(side) in {"count_of", "sum_of"}
} else := side

_ls_cond(c, l) := object.union(c, {"left": _ls_cond_tally(c.left, l), "right": _ls_right_flat(c, l)}) if {
	is_object(c)
	c.op == "compare"
} else := c

_ls_right_flat(c, l) := _ls_path(c.right, l, true) if {
	_list_cmp(c)
	not _one_right(c)
} else := _ls_cond_tally(c.right, l)

_ls_cond_tally(side, l) := object.union(side, {f: _ls_path(side[f], l, true) | some f in ["count_of", "sum_of"]; is_array(object.get(side, f, null))}) if {
	_basic_form(side) in {"count_of", "sum_of"}
} else := side

_ls_path(p, l, rooted) := array.concat([_p_marker(l, 0, null, false)], p) if {
	rooted == false
	is_array(p)
	count(p) > 0
	not _named(p)
	not _index_step(p[0])
	not _has_field_step(p)
} else := array.concat([_p_marker(l, 0, null, true)], array.slice(p, 1, count(p))) if {
	is_array(p)
	count(p) > 1
	p[0] == _root_marker
	not _index_step(p[1])
	not _has_field_step(p)
} else := array.concat([_p_marker(l, 0, null, m.old)], array.slice(p, 1, count(p))) if {
	is_array(p)
	count(p) > 1
	_subject_part(p)
	m := _part_of(p)
	m.n > 0
	m.old == rooted
	not _index_step(p[1])
	not _has_field_step(p)
} else := p

_labelled(check, req) := object.union(check, {"label": req.subject, "checks": [object.union(c, {"label": req.subject}) | some c in check.checks]}) if {
	is_string(object.get(req, "subject", null))
	is_array(object.get(check, "checks", null))
}

_labelled(check, req) := object.union(check, {"label": req.subject}) if {
	is_string(object.get(req, "subject", null))
	not is_array(object.get(check, "checks", null))
}

_labelled_for(check, req, subj) := _labelled(check, req) if not is_object(subj)

_labelled_for(check, _, subj) := check if is_object(subj)

_named_check(check, req, subj) := c if {
	c := _labelled_for(check, req, subj)
} else := check

_walk_labelled(check, req, subj) := _labelled(check, req) if {
	not is_object(subj)
	_walks(check)
}

_walk_labelled(check, req, subj) := _labelled(check, req) if {
	not is_object(subj)
	check.op == "for"
}

_walk_labelled(check, _, subj) := check if is_object(subj)

_walk_labelled(check, _, _) := check if {
	not _walks(check)
	object.get(check, "op", "") != "for"
}

_tagged_outcome(raw, _, req, _) := raw if not _tagging(req)

_tagged_outcome(raw, check, req, subj) := _tagged_failures(object.union(raw, {"inputs": _tagged(raw.inputs, check, req, subj)}), check, req, subj) if _tagging(req)

_tagged_failures(row, check, req, subj) := object.union(row, {"failed_items": [_tagged_failure(f, check, req, subj) | some f in row.failed_items]}) if "failed_items" in object.keys(row)

else := row

_tagged_failure(f, check, req, subj) := object.union(f, {"failed_assertions": [_tagged_line(l, check, req, subj) | some l in f.failed_assertions]}) if "failed_assertions" in object.keys(f)

else := f

_tagged_line(l, check, req, subj) := object.union(l, object.union(_tagged_line_inputs(l, check, req, subj), _tagged_line_items(l, check, req, subj)))

_tagged_line_inputs(l, check, req, subj) := {"inputs": _tagged(l.inputs, check, req, subj)} if "inputs" in object.keys(l)

else := {}

_tagged_line_items(l, check, req, subj) := {"items": [object.union(x, {"inputs": _tagged(x.inputs, check, req, subj)}) | some x in l.items]} if "items" in object.keys(l)

else := {}

_tagging(req) if {
	_has_fixed(req)
	req["ergo/fixed"].tagging == true
}

_tagging(req) if {
	not _has_fixed(req)
	_tagging_of(req)
}

default _tagging_of(_) := false

_tagging_of(req) if _has_parts(req)

_tagging_of(req) if {
	is_string(object.get(req, "subject", null))
	some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)
	a in _subjects_with_parts
}

_tagged(inputs, _, req, _) := inputs if not _tagging(req)

_tagged(inputs, check, req, subj) := [_tagged_input(i, {{"name": p.name, "id": _part_id(p.ms, p.steps, p.read, subj)} | some p in parts; _mentions(_value_source(i.name), p.patterns)}) | some i in inputs] if {
	_tagging(req)
	parts := _check_parts(check, req)
}

_tagged_input(i, matches) := object.union(i, {"part": tag}) if {
	count(matches) == 1
	some tag in matches
}

_tagged_input(i, matches) := i if count(matches) != 1

_check_parts(check, req) := [{"patterns": [_mention_pattern(_steps_name([_p_marker(m.alias, m.n, m.of, false)])), _mention_pattern(_steps_name([ms])), _mention_pattern(_steps_name(array.concat([_p_marker(m.alias, -1, m.of, m.old)], steps)))], "name": _tag_name(m), "ms": ms, "steps": steps, "read": read} |
	some ms in {x[0] | walk(check, [_, x]); is_array(x); _part_start(x)}
	m := json.unmarshal(substring(ms, 1, -1))
	read := data.ergo_subject_sentences.parts[_marker_owner(req, m)][m.alias]
	steps := read.from.path
]

_marker_owner(req, m) := req.subject if m.of == null

_marker_owner(_, m) := m.of if m.of != null

_tag_name(m) := m.alias if m.of == null

_tag_name(m) := concat("", [_s_parent_key(m.of), ".", m.alias]) if m.of != null

_part_id(ms, steps, read, subj) := _value_at(subj, array.concat(array.concat([ms], steps), path)) if path := _id_path(read)

_part_id(_, _, read, _) := null if not _id_path(read)

_id_path(read) := path if {
	is_object(read.identified_by)
	path := read.identified_by.path
}

_value_source(name) := substring(name, 0, min(cuts)) if {
	regex.match(`^(count|sum) of `, name)
	cuts := [i |
		some word in [" whose ", " that "]
		i := indexof(name, word)
		i > 0
	]
	count(cuts) > 0
} else := name

_mentions(name, patterns) if {
	some pattern in patterns
	regex.match(pattern, replace(name, "[]", ""))
}

_mention_pattern(token) := concat("", [`(^|[^A-Za-z0-9_."$-])`, _quoted(replace(token, "[]", "")), `($|[^A-Za-z0-9_-])`])

_quoted(text) := strings.replace_n({`\`: `\\`, ".": `\.`, "+": `\+`, "*": `\*`, "?": `\?`, "(": `\(`, ")": `\)`, "|": `\|`, "[": `\[`, "]": `\]`, "{": `\{`, "}": `\}`, "^": `\^`, "$": `\$`}, text)
