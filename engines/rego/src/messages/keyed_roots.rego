package ergo

import rego.v1

_keyed_rooted(o, check, subj) := _keyed_said(o, k, fault, subj) if {
	o.passed == false
	k := _keyed_list(check)
	not _unreadable_input
	fault := _keyed_root_fault(subj, k.clause.right)
} else := o

_keyed_said(o, k, fault, subj) := object.union(object.union(o, {"cause": _worst_of(causes), "message": _m_joined(array.concat([fault.text], said)), "ergo/own": [fault.text], "ergo/texts": [_m_clause("item", f.item, f.cause, _keyed_said_text(said, f.item)) | some f in failed]}), {"failed_items": failed | "failed_items" in object.keys(o)}) if {
	w := _walk(_walk_start({"path": k.path}, subj), _walk_keys({"path": k.path}, subj), true)
	_keyed_list_read(w)
	items := [x | some e in w.items; x := _keyed_item(e, k)]
	count(items) == count(w.items)
	causes := {fault.cause} | {c | some x in items; some c in x.causes}
	said := [x.text | some x in items; x.text != ""]
	failed := [_keyed_failed(f, items) | some f in object.get(o, "failed_items", [])]
} else := object.union(o, {"cause": _worst_of({fault.cause, o.cause}), "message": _m_joined([fault.text, o.message]), "ergo/own": array.concat([fault.text], object.get(o, "ergo/own", [o.message]))}) if {
	is_string(object.get(o, "message", null))
	w := _walk(_walk_start({"path": k.path}, subj), _walk_keys({"path": k.path}, subj), true)
	not _keyed_list_read(w)
} else := o

_keyed_failed(f, items) := object.union(f, {"cause": _worst_of(cs[0])}) if {
	cs := [x.causes | some x in items; x.text != ""; _names_item(x.text, f.item)]
	cs != []
} else := f

_keyed_said_text(said, name) := ts[0] if {
	ts := [t | some t in said; _names_item(t, name)]
	ts != []
} else := ""

_names_item(t, name) if startswith(t, concat("", [name, ": "]))

_names_item(t, name) if startswith(t, concat("", [name, " "]))

_keyed_list_read(w) if {
	w.fails == []
	count(w.items) > 0
}

_keyed_list(check) := {"path": check.path, "clause": c} if {
	check.op in {"every", "some"}
	is_array(object.get(check, "whose", null))
	object.get(check, "distinct", false) != true
	object.get(check, "check", null) == {"op": "present", "path": ["x"]}
	c := _keyed_clause(check.path, check.whose)
}

_keyed_list(check) := k if {
	check.op == "compare"
	k := _keyed_side(object.get(check, "left", null), object.get(check, "right", null))
}

_keyed_side(side, other) := {"path": side.count_of, "clause": c} if {
	is_object(side)
	is_array(object.get(side, "whose", null))
	object.keys(side) == {"count_of", "text", "whose"}
	is_object(other)
	object.keys(other) == {"literal"}
	c := _keyed_clause(side.count_of, side.whose)
}

_keyed_clause(path, whose) := c if {
	c := _keyed_clause_of(path, whose)
	c.cmp in {"includes", "matches_any"}
}

_keyed_clause_of(path, whose) := c if {
	_keyed_plain(path)
	count(path) == 1
	is_array(whose)
	count(whose) == 1
	c := whose[0]
	c.op == "compare"
	is_array(c.left)
	count(c.left) == 1
	_keyed_plain(c.left)
	_keyed_root_path(c.right)
}

_keyed_plain(path) if {
	is_array(path)
	count(path) > 0
	every step in path {
		is_string(step)
		not startswith(step, "$")
	}
}

_keyed_root_path(p) if {
	is_array(p)
	_keyed_off_start(p)
	k := count(p) - 1
	k > 1
	_field_step(p[k])
	not _from_root(p[k])
	_fk(p[k]) == p[k].named_by_field
	every step in array.slice(p, 1, k) {
		is_string(step)
	}
}

_keyed_off_start(p) if _part_start(p)

_keyed_off_start(p) if _starts_at_name(p)

_keyed_off_start(p) if _builtin(p)

_keyed_root_fault(subj, p) := fs[0] if {
	k := count(p) - 1
	fs := [f | some j in numbers.range(2, k); f := _keyed_prefix_fault(subj, p, j, k)]
	count(fs) > 0
}

_keyed_prefix_fault(subj, p, j, k) := {"cause": st, "text": concat("", [_input_name(shown), " is ", _m_state_word(st)])} if {
	shown := _as_subject_part(array.slice(p, 0, j))
	st := _any_read_state(subj, shown)
	st in {"absent", "null"}
} else := {"cause": "unusable", "text": _m_isnt(_input_name(shown), v, "an object")} if {
	j == k
	shown := _as_subject_part(array.slice(p, 0, j))
	_any_read_state(subj, shown) == "value"
	v := _value_at(subj, shown)
	not is_object(v)
}

_keyed_item(e, k) := {"text": _m_isnt(_m_item_name(e.i, _dotted_roots([k.path])), e.iv, "an object"), "causes": {"not_an_object"}} if not is_object(e.iv)

_keyed_item(e, k) := {"text": _keyed_item_text(_m_item_name(e.i, _dotted_roots([k.path])), [p[1] | some p in own]), "causes": {p[0] | some p in own}} if {
	is_object(e.iv)
	operand := _keyed_operand(e.iv, k.clause)
	own := array.concat(operand, [p | p := _keyed_key(e.iv, k.clause.right[count(k.clause.right) - 1])])
}

_keyed_operand(item, c) := [] if {
	v := item[c.left[0]]
	_keyed_operand_fits(c.cmp, v)
} else := [["absent", concat("", [_path_name(c.left), " is missing"])]] if {
	not c.left[0] in object.keys(item)
} else := [["null", concat("", [_path_name(c.left), " is null"])]] if {
	item[c.left[0]] == null
} else := [["unusable", _m_isnt(_path_name(c.left), item[c.left[0]], _keyed_kind(c.cmp))]] if {
	not _keyed_operand_mixed(c.cmp, item[c.left[0]])
}

_keyed_operand_fits("includes", v) if {
	is_array(v)
	not _keyed_operand_mixed("includes", v)
}

_keyed_operand_fits("matches_any", v) if is_string(v)

_keyed_operand_fits("eq", v) if v != null

_keyed_operand_mixed("includes", v) if {
	is_array(v)
	count({type_name(x) | some x in v}) > 1
}

_keyed_kind("includes") := "a list"

_keyed_kind("matches_any") := "text"

_keyed_item_text(_, []) := ""

_keyed_item_text(name, own) := concat("", [name, ": ", concat(", and ", own)]) if own != []

_keyed_key(item, step) := ["absent", concat("", [_fk_text(step), " is missing"])] if not _fk(step) in object.keys(item)

else := ["null", concat("", [_fk_text(step), " is null"])] if item[_fk(step)] == null

else := ["unusable", _m_isnt(_fk_text(step), item[_fk(step)], "text")] if not is_string(item[_fk(step)])
