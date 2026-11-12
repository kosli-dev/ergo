package ergo

import rego.v1

_walk_row(check, subj) := object.union(r, {"root_msgs": ms | ms := _flawed_root_msgs(check, subj, _walk_message(check, subj, r, r)); ms != []}) if {
	_walk_flawed(check)
	r := object.union(_walk_read_row(check, subj), {"cause": "unusable", "failed": []})
} else := {"cause": "not_an_object", "inputs": [], "failed": []} if {
	not _off_subject(check.path)
	not _reads_subject(check.path)
	not _list_start(check.path, subj)
	not is_object(subj)
} else := _walk_rooted(check, subj, _walk_read_row(check, subj))

_list_start(path, subj) if {
	_subject_part(path)
	_part_of(path).n == 0
	is_array(_start_of(subj, path))
}

_walk_rooted(check, subj, r) := _rooted_row(check, subj, r)

_walk_flawed(check) if _param_broken(check, set())

_walk_flawed(_) if _unreadable_input

_walk_read_row(check, subj) := {"cause": state, "inputs": _merged_inputs(array.concat([{"name": _path_name(check.path), "value": [], "locations": []}], _walk_side_inputs(subj, check))), "failed": _walk_failed(state, _null_prefix_fails(check, subj), check.path)} if {
	state := _walk_read_state(subj, check.path)
	not _walk_keys(check, subj)
}

_walk_read_row(check, subj) := {"cause": cause, "inputs": inputs, "failed": failed, "fails": fails} if {
	keys := _walk_keys(check, subj)
	w := _walk(_walk_start(check, subj), keys, check.if_any == true)
	judged := _walk_judged(check, w)
	fails := array.concat(array.concat(w.fails, [j.failure | some j in judged; j.failure != null]), _walk_stop(w))
	cause := _walk_cause(check, w, judged, fails)
	failed := _walk_failed(cause, fails, check.path)
	inputs := _merged_inputs(array.concat(_walk_inputs(check, w), _walk_side_inputs(subj, check)))
}

_walk_side_inputs(subj, check) := array.concat(array.concat(_named_inputs(subj, _walk_condition_paths(check)), _field_named_inputs(subj, _walk_condition_paths(check))), _input_ref_inputs(array.concat([check.check], check.whose))) if _walk_list_ref(check)

else := array.concat(_named_inputs(subj, _walk_condition_paths(check)), _field_named_inputs(subj, _walk_condition_paths(check)))

_walk_list_ref(check) if check.check.op in _right_ref_ops

_walk_list_ref(check) if {
	some c in check.whose
	c.op in _right_ref_ops
}

_walk_judged(check, w) := [_walk_judge(check, w, e) | some e in w.items] if object.get(check, "distinct", false) != true

else := [_walk_copied(j, i, w, copies) | some i, j in judged; not i in copies.dropped] if {
	judged := [object.union(_walk_judge(check, w, e), {"decided": _walk_decided(check, e)}) | some e in w.items]
	copies := _copies_of([[_exact_key(w.items[i].v, [json.marshal(w.items[i].v) | _holds_numbers(w.items[i].v)]), i] | some i, j in judged; j.kept; j.decided; not _walk_marked(w.items[i].v)])
}

default _walk_decided(_, _) := false

_walk_decided(check, e) if {
	every c in check.whose {
		_focus_cause(c, e) in {"satisfied", "value"}
	}
}

_copies_of(pairs) := {"dropped": {k | some g in groups; some k in array.slice(g, 1, count(g))}, "groups": {g[0]: g | some g in groups; count(g) > 1}} if {
	sorted := sort(pairs)
	starts := [j | some j, _ in sorted; _starts_group(sorted, j)]
	ends := array.concat([starts[g] | some g, _ in starts; g > 0], [count(sorted)])
	groups := [[x[1] | some x in array.slice(sorted, starts[g], ends[g])] | some g, _ in starts]
}

_walk_copied(j, i, w, copies) := object.union(j, {"failure": object.union(j.failure, {"ats": [_walk_at(w, w.items[k]) | some k in copies.groups[i]]})}) if {
	j.failure != null
	i in object.keys(copies.groups)
} else := j

_walk_condition_paths(check) := array.concat([p | some p in _condition_paths(check.check)], [p | some c in check.whose; some p in _condition_paths(c)])

_named_inputs(subj, paths) := [_path_input(subj, shown) |
	some p in paths
	_read_off_item(p)
	not _has_field_step(p)
	shown := _as_subject_part(p)
]

_field_named_inputs(subj, paths) := array.concat(
	[_path_input(subj, shown) |
		some p in paths
		_read_off_item(p)
		_has_field_step(p)
		not _root_read_fields(p)
		shown := _as_subject_part(_before_field_step(p))
		not _through_list(subj, shown)
	],
	[x |
		some p in paths
		_root_read_fields(p)
		some x in array.concat([_path_input(subj, _as_subject_part(p)) | not _alias_start(p); not _item_start(p)], [_path_input(subj, [f]) | some f in _own_key_fields(p)])
	],
)

_item_start(p) if {
	is_string(p[0])
	not startswith(p[0], "$")
}

_alias_start(p) if {
	is_string(p[0])
	startswith(p[0], "$")
	not startswith(p[0], "$$")
	not startswith(p[0], "${")
	not _parent_name(p[0])
}

_before_field_step(p) := array.slice(p, 0, min([j | some j, step in p; j > 0; _field_step(step)]))

_as_subject_part(p) := array.concat([_p_marker(m.alias, m.n, m.of, false)], array.slice(p, 1, count(p))) if {
	_part_start(p)
	m := _part_of(p)
	m.old == true
}

_as_subject_part(p) := p if not _old_part(p)

_old_part(p) if {
	_part_start(p)
	_part_of(p).old == true
}

_read_off_item(p) if _starts_at_name(p)

_read_off_item(p) if {
	_part_start(p)
	_part_of(p).of == null
}

_read_off_item(p) if p[0] == "$$input"

_walk_keys(check, subj) := ks if {
	_ := _start_of(subj, check.path)
	ks := _keys_in(subj, check.path)
}

_walk_start(check, subj) := {"c": _walk_root(check.path), "v": _walk_start_value(subj, check.path), "i": null, "iv": null, "r": [], "a": _walk_base(check.path)}

_walk_start_value(subj, path) := _start_of(subj, path) if not _params_null(path)

_walk_start_value(_, path) := _absent if _params_null(path)

_walk_base(path) := base if base := _start_at(path)

else := ""

_walk_at(w, e) := _joined(w.trail[0].a, array.slice(e.c, count(w.trail[0].c), count(e.c))) if not _walk_marked(e.v)

else := _pointer(w.trail[0].a, w.trail[0].v, array.slice(e.c, count(w.trail[0].c), count(e.c)))

_walk_locations(w) := [_walk_at(w, e) | some e in w.items]

_item_at(w, e) := _pointer(w.trail[0].a, w.trail[0].v, array.slice(e.i, count(w.trail[0].c), count(e.i)))

_fail_locations(f) := f.ats if "ats" in object.keys(f)

else := [f.at] if "at" in object.keys(f)

else := []

_item_read_at(w, e, path) := _pointer(_item_at(w, e), e.iv, _resolved_prefix(e.iv, path))

_walk_root(path) := [path[0]] if _named(path)

_walk_root(path) := [] if not _named(path)

_walk(start, keys, if_any) := {"items": items, "fails": fails, "walked": walked, "trail": trail} if {
	r0 := _walk_level([start], keys, 0, if_any, start)
	r1 := _walk_level(r0.entries, keys, 1, if_any, start)
	r2 := _walk_level(r1.entries, keys, 2, if_any, start)
	r3 := _walk_level(r2.entries, keys, 3, if_any, start)
	r4 := _walk_level(r3.entries, keys, 4, if_any, start)
	r5 := _walk_level(r4.entries, keys, 5, if_any, start)
	r6 := _walk_level(r5.entries, keys, 6, if_any, start)
	r7 := _walk_level(r6.entries, keys, 7, if_any, start)
	r8 := _walk_level(r7.entries, keys, 8, if_any, start)
	r9 := _walk_level(r8.entries, keys, 9, if_any, start)
	r10 := _walk_level(r9.entries, keys, 10, if_any, start)
	levels := [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10]
	fails := [object.union(f, {"at": _pointer(start.a, start.v, array.slice(f.path, count(start.c), count(f.path)))}) | some r in levels; some f in r.fails]
	walked := {i | some i, r in levels; r.walked}
	items := [e | some e in r10.entries; e.i != null]
	trail := array.concat([start], [r.entries[0] | some i, r in levels; i < count(keys); count(r.entries) == 1])
}

_walk_level(entries, keys, i, _, _) := {"entries": entries, "fails": [], "walked": false} if i > count(keys)

_walk_level(entries, keys, i, if_any, start) := {"entries": [_walk_step(e, keys, i, start) | some e in expanded], "fails": fails, "walked": walked} if {
	i <= count(keys)
	walked := _walks_here(entries, keys, i)
	expanded := [x | some e in entries; some x in _walk_expand(e, walked, i, start)]
	fails := [f | some e in entries; some f in _walk_expand_fail(e, walked, if_any, start)]
}

_walks_here(entries, keys, i) if {
	some e in entries
	is_array(e.v)
	i == count(keys)
} else if {
	some e in entries
	is_array(e.v)
	not is_number(keys[i])
} else := false

_walk_expand(e, false, _, _) := [e]

_walk_expand(e, true, i, start) := [{"c": array.concat(_walk_unaliased(e.c, i), [j]), "v": x, "i": array.concat(_walk_unaliased(e.c, i), [j]), "iv": x, "r": []} | some j, x in e.v] if {
	is_array(e.v)
	_ = start
}

_walk_expand(e, true, _, _) := [] if not is_array(e.v)

_walk_unaliased(c, i) := array.concat([_p_marker(m.alias, -1, m.of, m.old)], array.slice(c, 1, count(c))) if {
	_part_start(c)
	m := _part_of(c)
	m.n > 0
	i > 0
	i < m.n
}

_walk_unaliased(c, i) := c if not _walk_inside_part(c, i)

_walk_inside_part(c, i) if {
	_part_start(c)
	m := _part_of(c)
	m.n > 0
	i > 0
	i < m.n
}

_walk_expand_fail(_, false, _, _) := []

_walk_expand_fail(e, true, if_any, start) := [] if {
	_ = start
	is_array(e.v)
	_walk_empty_ok(e.v, if_any)
}

_walk_expand_fail(e, true, if_any, _) := [{"path": e.c, "item": e.c, "cause": "value", "value": [], "msg": ""}] if {
	e.v == []
	not _walk_empty_ok(e.v, if_any)
}

_walk_expand_fail(e, true, _, _) := [{"path": e.c, "item": e.c, "cause": _walk_state(e.v), "value": null, "msg": "a list"}] if {
	not is_array(e.v)
	_walk_marked(e.v)
}

_walk_expand_fail(e, true, _, _) := [{"path": e.c, "item": e.c, "cause": _walk_state(e.v), "value": e.v, "msg": "a list"}] if {
	not is_array(e.v)
	not _walk_marked(e.v)
}

_walk_empty_ok(v, _) if count(v) > 0

_walk_empty_ok(_, true)

_walk_step(e, keys, i, _) := e if i >= count(keys)

_walk_step(e, keys, i, start) := {"c": array.concat(e.c, [keys[i]]), "v": _walk_read(e.v, keys[i], e, start), "i": e.i, "iv": e.iv, "r": array.concat(e.r, [keys[i]])} if i < count(keys)

_walk_read(v, k, at, start) := object.get(v, k, _absent) if {
	_ = at
	_ = start
	is_object(v)
	is_string(k)
	v != _absent
	v != _unusable_mark
} else := v[k] if {
	is_array(v)
	is_number(k)
	k < count(v)
} else := _absent if {
	is_array(v)
	is_number(k)
} else := _absent if {
	_walk_gone(v)
} else := _unusable_mark

_walk_gone(v) if v == _absent

_walk_gone(null)

_walk_state(v) := "absent" if v == _absent

_walk_state(null) := "null"

_walk_state(v) := "unusable" if not _walk_gone(v)

_walk_shown(v) := null if _walk_marked(v)

_walk_shown(v) := v if not _walk_marked(v)

_walk_value(v, _, _) := null if _walk_marked(v)

_walk_value(v, e, w) := v if {
	not _walk_marked(v)
	_ = e
	_ = w
}

_walk_marked(v) if v == _absent

_walk_marked(v) if v == _unusable_mark

_walk_judge(check, w, e) := j if {
	_holds_numbers(e.iv)
	t := json.marshal(e.iv)
	_long_text(t)
	j := _walk_judgement(check, w, e) with data.ergo_item as t
} else := _walk_judgement(check, w, e)

_walk_judgement(check, w, e) := {"kept": kept, "passed": passed, "failure": failure} if {
	undecided := [[c, cause] | some c in check.whose; cause := _focus_cause(c, e); not cause in {"satisfied", "value"}]
	kept := count([c | some c in check.whose; _focus_cause(c, e) == "value"]) == 0
	leaf := _walk_target(check.check, e.r)
	passed := _walk_passed(undecided, kept, leaf, e.iv)
	failure := _walk_failure(check.path, w, e, undecided, kept, leaf, passed)
}

_focus_entry(e) := object.union(object.remove(e, ["i", "iv", "r"]), {"i": e.c, "iv": e.v, "r": []}) if {
	e.r != []
	not _walk_marked(e.v)
} else := e

_focus_cause(c, e) := _row_cause(c, e.iv, "") if e.r == []

else := _focus_lost_state(e) if _focus_lost(e, c)

else := _row_cause(c, e.v, "")

_focus_lost_state(e) := [s | some s in _tally_mark(true, e)][0]

_focus_of(e, c) := _focus_entry(e) if _reads_focus(c)

else := e

_reads_focus(c) if {
	some p in _condition_paths(c)
	not _walk_outside(p)
}

_focus_lost(e, c) if {
	e.r != []
	_walk_marked(e.v)
	some p in _condition_paths(c)
	not _walk_outside(p)
}

default _walk_passed(_, _, _, _) := false

_walk_passed([], true, leaf, v) if _op_passed(leaf, v)

_walk_failure(path, w, e, [], true, leaf, false) := {"path": e.c, "item": e.i, "cause": cause, "value": _walk_value(e.v, e, w), "at": _walk_at(w, e), "msg": _m_leaf_message(e, leaf, cause, path)} if cause := _row_cause(leaf, e.iv, "")

_walk_failure(path, w, e, undecided, _, _, _) := {"path": e.c, "item": e.i, "cause": undecided[0][1], "value": null, "at": _walk_at(w, e), "msg": _m_walk_leaf(e, {"op": "present", "path": e.r}, undecided[0][1], _dotted_roots([path]))} if {
	undecided != []
	_focus_lost(e, undecided[0][0])
}

_walk_failure(path, w, e, undecided, _, _, _) := {"path": _walk_named_path(fe, p), "item": e.i, "cause": undecided[0][1], "value": _value_at(fe.iv, p), "at": _walk_named_at(w, fe, p), "msg": _m_walk_leaf(fe, undecided[0][0], _m_undecided(undecided[0][1]), _dotted_roots([path]))} if {
	undecided != []
	not _focus_lost(e, undecided[0][0])
	fe := _focus_of(e, undecided[0][0])
	p := _walk_first_path(undecided[0][0], fe.iv)
}

_walk_named_path(_, p) := _as_subject_part(p) if _walk_outside(p)

_walk_named_path(e, p) := array.concat(e.i, p) if not _walk_outside(p)

_walk_named_at(_, _, p) := _ref_at(p) if _walk_outside(p)

_walk_named_at(w, e, p) := _item_read_at(w, e, p) if not _walk_outside(p)

_walk_outside(p) if _read_off_item(p)

_walk_outside(p) if _builtin(p)

_walk_failure(_, _, _, [], false, _, _) := null

_walk_failure(_, _, _, [], true, _, true) := null

_walk_first_path(c, v) := array.concat([e[0] | some e in _walk_sides_paths(c); not _walk_side_read(v, e)], [e[0] | some e in _walk_sides_paths(c)])[0]

_walk_side_read(v, e) if {
	_read_state(v, e[0]) == "value"
	_walk_list_read(e[1], _value_at(v, e[0]))
}

_walk_list_read("value", _)

_walk_list_read("list", x) if is_array(x)

_walk_sides_paths(c) := [e | some f in ["left", "right"]; some e in _walk_side_paths(c, c[f])] if _two_sided(c)

_walk_sides_paths(c) := [[p, "value"] | some p in _condition_paths(c)] if not _two_sided(c)

_walk_side_paths(_, side) := [[side, "value"]] if is_array(side)

_walk_side_paths(c, side) := [[p, _walk_side_needs(operand)] | some operand in _walk_operands(side); some p in _basic_paths(operand)] if {
	c.op == "compare"
	_derived(side)
}

_walk_operands(side) := side.add if _side_form(side) == "add"

else := [side]

_walk_side_needs(side) := "list" if _basic_form(side) in {"count_of", "sum_of"}

else := "value"

_condition_paths(c) := array.concat(_leaf_paths(c), [p | some side in _derived_sides(c); some p in _side_paths(side)])

_walk_target(leaf, r) := object.union(leaf, {"left": r}) if _two_sided(leaf)

_walk_target(leaf, r) := object.union(leaf, {"path": r}) if not _two_sided(leaf)

_walk_cause(_, w, _, _) := _walk_stop(w)[0].cause if w.walked == set()

_walk_cause(check, w, judged, fails) := _walk_verdict(check.op, check.if_any == true, judged, fails) if w.walked != set()

_m_walk_kind(v) := "a list" if is_object(v)

else := "a list or an object"

_walk_stopped_at(trail) := [e | some e in trail; not _walk_container(e.v)][0] if {
	some e in trail
	not _walk_container(e.v)
} else := trail[count(trail) - 1]

_walk_container(v) if {
	is_object(v)
	not _walk_marked(v)
}

_walk_container(v) if is_array(v)

_walk_stop_state(v) := _walk_state(v) if _walk_gone(v)

_walk_stop_state(v) := "unusable" if not _walk_gone(v)

_walk_verdict("every", if_any, judged, []) := "satisfied" if {
	_walk_some_kept(judged, if_any)
} else := "value"

_walk_verdict("every", _, _, fails) := _walk_worst(fails) if fails != []

_walk_verdict("some", _, judged, fails) := "satisfied" if {
	some j in judged
	j.passed
} else := _walk_worst(fails) if {
	fails != []
} else := "value"

_walk_some_kept(_, true)

_walk_some_kept(judged, false) if {
	some j in judged
	j.kept
}

_walk_worst(fails) := [c | some c in array.concat(_cause_precedence, ["value"]); c in {f.cause | some f in fails}][0]

_walk_failed("satisfied", _, _) := []

_walk_failed(cause, fails, path) := [{"path": _failed_name(f.path, _dotted_roots([path])), "item": _failed_name(f.item, _dotted_roots([path])), "cause": f.cause, "value": f.value, "locations": _fail_locations(f)} |
	some p in sort({f.path | some f in fails})
	some f in fails
	f.path == p
] if cause != "satisfied"

_walk_inputs(check, w) := [{"name": _walk_name(check.path, w.walked), "value": [_walk_value(e.v, e, w) | some e in w.items], "locations": _walk_locations(w)}]

_walk_name(path, walked) := _walk_shown_name(_walk_unaliased(path, _walk_crossed(path, walked)), walked)

_walk_crossed(path, walked) := min({i | some i in walked; i > 0; i < _part_of(path).n}) if _part_start(path)

_walk_crossed(path, walked) := 0 if not _walk_crosses(path, walked)

_walk_crosses(path, walked) if {
	_part_start(path)
	some i in walked
	i > 0
	i < _part_of(path).n
}

_walk_shown_name(path, walked) := concat("", array.concat(array.concat(_walk_root_name(path), [concat("", [_walk_mark(i + _walk_hidden(path), walked), _step_name(i + count(_walk_root_name(path)), step)]) | some i, step in array.slice(_walk_steps(path), _walk_hidden(path), count(_walk_steps(path)))]), [_walk_mark(count(_walk_steps(path)), walked)]))

_walk_hidden(path) := max([_part_of(path).n, 0]) if _part_start(path)

_walk_hidden(path) := 0 if not _part_start(path)

_walk_root_name(path) := [_plain_step_name(0, path[0])] if {
	_named(path)
	not _part_start(path)
}

_walk_root_name(path) := [_plain_step_name(0, root[0])] if {
	_part_start(path)
	root := _visible_root(_part_of(path))
	count(root) == 1
}

_walk_root_name(path) := [_plain_step_name(0, root[0]), _step_name(1, root[1])] if {
	_part_start(path)
	root := _visible_root(_part_of(path))
	count(root) == 2
}

_walk_root_name(path) := [] if {
	_part_start(path)
	count(_visible_root(_part_of(path))) == 0
}

_walk_root_name([]) := ["the subject"]

_walk_root_name(path) := [] if {
	not _named(path)
	not _reads_subject(path)
}

_walk_steps(path) := array.slice(path, count(_walk_root(path)), count(path))

_walk_mark(i, walked) := "[]" if i in walked

_walk_mark(i, walked) := "" if not i in walked

_s_check_for(lines, ftext, wording, problems, parts) := object.union(wording, {
	"op": "for",
	"items": [_s_for_item_model(item, {earlier.as | some earlier in array.slice(fl.items, 0, i)}) | some i, item in items],
	"checks": [_s_named_model_leaf(_s_model(a), names) | some a in marked],
	"assertions": texts,
	"expression": concat("", ["for ", _s_for_line_text({"items": items}), ": ", concat(" and ", texts)]),
}) if {
	count(problems) == 0
	fl := _for_line(ftext)
	"items" in object.keys(fl)
	names := {item.as | some item in fl.items}
	parsed := [_sentence(line) | some line in lines]
	every p in parsed {
		"assertions" in object.keys(p)
	}
	assertions := [a | some p in parsed; some a in p.assertions]
	count(_s_for_unsupported(fl, assertions)) == 0
	items := _s_marked_items(fl, parts)
	marked := [_s_aliased(a, _s_names(names, parts)) | some a in assertions]
	count(_s_self_problems(marked) | _s_whose_self_problems(items)) == 0
	texts := [_s_assertion_text(a) | some a in marked]
} else := object.union(wording, {"expression": _s_for_written_text(lines, ftext), "$sentence": sort(_s_or_unrunnable(((problems | _s_for_problems(lines, ftext)) | _s_for_self(lines, ftext, parts))))})
