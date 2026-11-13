package ergo

import rego.v1

_ref_read(path) := v if {
	_builtin(path)
	start := _start_of(null, path)
	is_object(start)
	v := object.get(start, [_key(seg) | some seg in array.slice(path, 1, count(path))], _absent)
	v != _absent
} else := v if {
	_builtin(path)
	start := _start_of(null, path)
	v := _read_from(start, [_key(seg) | some seg in array.slice(path, 1, count(path))])
	v != _absent
} else := w.value if {
	_ref_walks(path)
	w := _ref_walk(path)
	not w.failed
} else := _absent if {
	_builtin(path)
	start := _start_of(null, path)
	start != null
}

_unnamed_root(path) if {
	_part_start(path)
	_part_of(path).alias == ""
}

_ref_walks(path) if {
	path[0] in {"$$input[]", "$$params[]"}
	_rwalks(null, path)
}

_params_starts := {"$$params", "$$params[]"}

_ref_walk(path) := _rwalk(null, path)

_ref_walk_text(path) := _rwalk_text(null, path)

_rkeys(path) := _plain_keys(path) if _plain_path(path)

_rkeys(path) := [_key(seg) | some seg in array.slice(path, 1, count(path))] if {
	_builtin(path)
	every seg in array.slice(path, 1, count(path)) {
		not is_object(seg)
	}
}

_rkeys(path) := [_key(seg) | some seg in array.slice(path, 1, count(path))] if {
	_named_walk_path(path)
	every seg in array.slice(path, 1, count(path)) {
		not is_object(seg)
	}
}

_rstart(x, path) := x if {
	_plain_path(path)
	is_object(x)
}

_rstart(_, path) := _start_of(null, path) if _builtin(path)

_rstart(x, path) := _start_of(x, path) if _named_walk_path(path)

_rstart(x, path) := x if {
	_literal_walk_path(path)
	is_object(x)
}

_literal_walk_path(path) if {
	is_array(path)
	_is_literal(path[0])
	every seg in array.slice(path, 1, count(path)) {
		not is_object(seg)
	}
}

_rkeys(path) := array.concat([_key(path[0].literal)], [_key(seg) | some seg in array.slice(path, 1, count(path))]) if _literal_walk_path(path)

_named_walk_path(path) if {
	_named(path)
	not _builtin(path)
	not _has_field_step(path)
}

_rwalks(x, path) if {
	is_array(path)
	start := _rstart(x, path)
	is_object(start)
	keys := _rkeys(path)
	object.get(start, keys, _absent) == _absent
	some i, k in keys
	is_string(k)
	is_array(object.get(start, array.slice(keys, 0, i), _absent))
}

_rwalks(x, path) if {
	is_array(path)
	_named_walk_path(path)
	not _unnamed_root(path)
	is_array(_rstart(x, path))
	keys := _rkeys(path)
	count(keys) > 0
	is_string(keys[0])
}

_rwalks(_, path) if {
	path[0] == "$$input[]"
	is_array(data.ergo_document)
	keys := _rkeys(path)
	doc := {"start": data.ergo_document}
	object.get(doc, array.concat(["start"], keys), _absent) == _absent
	some i, k in keys
	is_string(k)
	is_array(object.get(doc, array.concat(["start"], array.slice(keys, 0, i)), _absent))
}

_rwalk_run(x, path) := _walk(_walk_start({"path": path}, x), _rkeys(path), false)

_rwalk_item_states(e) := {"unusable"} if {
	e.v in {_absent, _unusable_mark}
	not is_object(e.iv)
}

_rwalk_item_states(e) := {"absent"} if {
	e.v == _absent
	is_object(e.iv)
}

_rwalk_item_states(e) := {"null"} if e.v == null

_rwalk_item_states(e) := {"unusable"} if {
	e.v == _unusable_mark
	is_object(e.iv)
}

_rwalk(x, path) := {"state": _worst_or_value(states), "failed": count(states) > 0, "name": _walk_name(path, w.walked), "value": _walk_listed_values(w), "locations": _walk_listed_locations(w)} if {
	w := _rwalk_run(x, path)
	states := _rwalk_states(w)
}

_rwalk_states(w) := ({f.cause | some f in w.fails} | {f.cause | some f in _walk_stop(w)}) | {s | some e in w.items; some s in _rwalk_item_states(e)}

_rwalk_text(x, path) := _m_joined(_m_fail_parts("unusable", fails, _dotted_roots([path]))) if {
	w := _rwalk_run(x, path)
	fails := array.concat(array.concat([_rwalk_broken(x, path, f) | some f in w.fails], [f | some e in w.items; some f in _rwalk_item_fails(e, _dotted_roots([path]))]), _walk_stop(w))
}

_rwalk_broken(x, path, f) := {"path": broken, "item": broken, "cause": "unusable", "value": v, "msg": _m_isnt(_m_item_name(broken, _dotted_roots([path])), v, _rwalk_wants(rest[j]))} if {
	f.cause == "unusable"
	f.value == null
	start := _walk_start({"path": path}, x)
	n := count(start.c)
	array.slice(f.path, 0, n) == start.c
	rest := array.slice(f.path, n, count(f.path))
	j := min({i |
		some i, k in rest
		v := object.get({"v": start.v}, array.concat(["v"], array.slice(rest, 0, i)), _absent)
		v != _absent
		v != null
		not _rwalk_holds(v, k)
	})
	v := object.get({"v": start.v}, array.concat(["v"], array.slice(rest, 0, j)), null)
	broken := array.slice(f.path, 0, n + j)
} else := f

_rwalk_item_fails(e, _) := [{"path": e.c, "item": e.i, "cause": state, "value": null, "msg": ""} | some state in _rwalk_item_states(e)] if {
	e.v != _unusable_mark
	is_object(e.iv)
}

_rwalk_item_fails(e, roots) := [{"path": e.i, "item": e.i, "cause": "unusable", "value": e.iv, "msg": _m_isnt(_m_item_name(e.i, roots), e.iv, "an object")}] if {
	e.v in {_absent, _unusable_mark}
	not is_object(e.iv)
}

_rwalk_item_fails(e, roots) := [{"path": broken, "item": e.i, "cause": "unusable", "value": v, "msg": _m_isnt(_m_item_name(broken, roots), v, _rwalk_wants(e.r[i]))}] if {
	e.v == _unusable_mark
	is_object(e.iv)
	i := _rwalk_break(e)
	v := object.get(e.iv, array.slice(e.r, 0, i), null)
	broken := array.concat(e.i, array.slice(e.r, 0, i))
}

_rwalk_break(e) := min({i |
	some i, k in e.r
	v := object.get(e.iv, array.slice(e.r, 0, i), _absent)
	v != _absent
	v != null
	not _rwalk_holds(v, k)
})

_rwalk_holds(v, k) if {
	is_string(k)
	is_object(v)
}

_rwalk_holds(v, k) if {
	is_number(k)
	is_array(v)
}

_rwalk_wants(k) := "an object" if is_string(k)

_rwalk_wants(k) := "a list" if is_number(k)

_walked_side(r) if {
	is_object(r)
	object.keys(r) == {"walked"}
}

_rpath(r) := r.walked if _walked_side(r)

_rpath(r) := r if is_array(r)

_rwalking(_, r) if _walked_side(r)

_rwalking(x, r) if _rwalks(x, r)

_rfailed(x, r) if {
	_rwalking(x, r)
	_rwalk(x, _rpath(r)).failed
}

_rstate(x, r) := _rwalk(x, _rpath(r)).state if _rfailed(x, r)

_rstate(x, r) := "value" if {
	_rwalking(x, r)
	not _rfailed(x, r)
}

_rstate(x, r) := _read_state(x, r) if not _rwalking(x, r)

_rvalue(x, r) := _rwalk(x, _rpath(r)).value if _rwalking(x, r)

_rvalue(x, r) := _value_at(x, r) if not _rwalking(x, r)

_rfound(x, r) := _rwalk(x, _rpath(r)).value if {
	_rwalking(x, r)
	not _rfailed(x, r)
}

_rfound(x, r) := _found(x, r) if not _rwalking(x, r)

_right_walks(check, x) if {
	check.op == "compare"
	_list_cmp(check)
	not _one_right(check)
	is_array(check.right)
	_rwalks(x, check.right)
}

_state_at(check, x, p) := _lstate(check, x) if {
	_list_cmp(check)
	p == check.right
	p != check.left
} else := _read_state(x, p)

default _one_right(_) := false

_one_right(leaf) if leaf.cmp in {"includes", "excludes"}

_lfailed(leaf, x) if {
	not _one_right(leaf)
	_rfailed(x, leaf.right)
}

_lstate(leaf, x) := _rstate(x, leaf.right) if not _one_right(leaf)

_lstate(leaf, x) := _read_state(x, leaf.right) if _one_right(leaf)

_lvalue(leaf, x) := _rvalue(x, leaf.right) if not _one_right(leaf)

_lvalue(leaf, x) := _value_at(x, leaf.right) if _one_right(leaf)
