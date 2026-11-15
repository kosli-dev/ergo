package ergo

import rego.v1

_keyed_rooted(o, check, subj) := object.union(o, {"cause": _worst_of(causes), "message": _m_joined(array.concat([f.text | some f in faults], [x.text | some x in items; x.text != ""]))}) if {
	o.passed == false
	_keyed_shaped(check)
	is_string(object.get(o, "message", null))
	lists := _keyed_lists(check)
	count(lists) == 1
	k := lists[0]
	faults := _keyed_root_faults(subj, k.whose)
	faults != []
	w := _walk(_walk_start({"path": k.path}, subj), _walk_keys({"path": k.path}, subj), true)
	w.fails == []
	items := [x | some e in w.items; x := _keyed_item(e, faults, k.path, split(o.message, "; "))]
	causes := ({f.cause | some f in faults} | {c | some x in items; some c in x.causes}) | {o.cause | some x in items; x.other}
} else := o

_keyed_shaped(check) if check.whose

_keyed_shaped(check) if check.left.whose

_keyed_shaped(check) if check.right.whose

_keyed_lists(check) := [{"path": check.path, "whose": check.whose} |
	check.op in {"every", "some"}
	is_array(object.get(check, "path", null))
	is_array(object.get(check, "whose", null))
] if check.op in {"every", "some"}

else := [{"path": side[f], "whose": side.whose} |
	some s in ["left", "right"]
	side := object.get(check, s, null)
	is_object(side)
	some f in ["count_of", "sum_of"]
	is_array(object.get(side, f, null))
	is_array(object.get(side, "whose", null))
]

_keyed_root_faults(subj, whose) := [f |
	some x in sort({[i, f.text, f] |
		some p in {q | some c in whose; walk(c, [_, q]); _keyed_root_path(q)}
		f := _keyed_root_fault(subj, p)
		some i, c in _cause_precedence
		c == f.cause
	})
	f := x[2]
]

_keyed_root_path(p) if {
	is_array(p)
	_item_keyed(p)
	_keyed_off_start(p)
}

_keyed_off_start(p) if _part_start(p)

_keyed_off_start(p) if _starts_at_name(p)

_keyed_off_start(p) if _builtin(p)

_keyed_at(p) := min({i | some i, step in p; _field_step(step); not _from_root(step)})

_keyed_root_fault(subj, p) := object.union(fs[0], {"path": p, "at": k}) if {
	k := _keyed_at(p)
	k > 1
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

_keyed_item(e, _, path, _) := {"text": _m_isnt(_m_item_name(e.i, _dotted_roots([path])), e.iv, "an object"), "causes": {"not_an_object"}, "other": false} if not is_object(e.iv)

_keyed_item(e, faults, path, parts) := {"text": _keyed_item_text(name, own), "causes": {k[0] | some k in keys}, "other": count(other) > 0} if {
	is_object(e.iv)
	name := _m_item_name(e.i, _dotted_roots([path]))
	keys := _once([k | some f in faults; k := _keyed_key(e.iv, f.path[f.at])])
	key_texts := [k[1] | some k in keys]
	other := _once([c |
		some c in _keyed_said(name, parts)
		not c in key_texts
		not _keyed_root_clause(c, faults)
	])
	own := array.concat(other, key_texts)
}

_keyed_item_text(_, []) := ""

_keyed_item_text(name, own) := concat("", [name, ": ", concat(", and ", own)]) if own != []

_keyed_key(item, step) := ["absent", concat("", [_fk_text(step), " is missing"])] if not _fk(step) in object.keys(item)

else := ["null", concat("", [_fk_text(step), " is null"])] if item[_fk(step)] == null

else := ["unusable", _m_isnt(_fk_text(step), item[_fk(step)], "text")] if not is_string(item[_fk(step)])

_keyed_said(name, parts) := [c |
	some i, part in parts
	owners := {j | some j in numbers.range(0, i); startswith(parts[j], "item ")}
	count(owners) > 0
	owner := max(owners)
	startswith(parts[owner], concat("", [name, ": "]))
	text := _keyed_unprefixed(part, i == owner, name)
	some c in split(text, ", and ")
]

_keyed_unprefixed(part, true, name) := substring(part, count(name) + 2, -1)

_keyed_unprefixed(part, false, _) := part

_keyed_root_clause(c, faults) if {
	some f in faults
	some j in numbers.range(2, count(f.path))
	startswith(c, concat("", [_input_name(_as_subject_part(array.slice(f.path, 0, j))), " "]))
}
