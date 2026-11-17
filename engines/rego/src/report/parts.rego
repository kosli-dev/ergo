package ergo

import rego.v1

_row_stash_keys := ["failed_items", "failed_assertions", "ergo/texts", "ergo/own", "ergo/outs", "ergo/for_texts"]

_parted(row, _, _) := _passed_row(row) if row.passed == true

_parted(row, at, where) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": _with_outcomes(row.inputs),
	"failures": _for_failures(row, at, where, t),
}) if {
	row.passed == false
	t := row["ergo/for_texts"]
}

_parted(row, at, where) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": ins,
	"failures": _row_failures(row, at, where, ins),
}) if {
	row.passed == false
	not _for_texted(row)
	ins := _with_outcomes(row.inputs)
}

_for_texted(row) if _ = row["ergo/for_texts"]

_for_failures(row, at, where, t) := _for_failures_of(row, at, where, t, _for_key_texts(where.check))

_for_failures_of(row, at, where, t, []) := array.concat(
	[e | some i, a in where.check.assertions; e := _for_assertion_entry(row, at, where, t, i, a)],
	_nested_items([e | some kind in ["list", "item"]; some e in _for_row_breaks(row, t, at, where); _leveled_kind(e) == kind]),
)

_for_failures_of(row, at, where, t, ks) := array.concat(
	[_for_keyed_entry(e, i, where.check) | some i, a in where.check.assertions; e := _for_assertion_entry(row, at, where, object.union(t, {"said": [_for_keyed_said(s, j, ks) | some j, s in t.said]}), i, a)],
	_nested_items([e | some kind in ["list", "item"]; some e in _for_row_breaks(row, t, at, where); _leveled_kind(e) == kind; not _for_key_break(e, ks)]),
) if ks != []

_for_key_texts(check) := _once([k | some item in check.items; some k in _walk_key_ref_texts(item.path)])

_for_keyed_said(s, 0, ks) := concat("; ", _once(array.concat(ks, [x | some x in split(s, "; "); x != ""])))

_for_keyed_said(s, j, _) := s if j > 0

_for_keyed_entry(e, 0, check) := object.union(e, {"inputs": _once(array.concat(e.inputs, [x | some item in check.items; some x in _with_outcomes(_walk_key_ref_entries(item.path))]))})

_for_keyed_entry(e, i, _) := e if i > 0

_for_key_break(e, ks) if _for_key_leaf(e, ks)

_for_key_break(e, ks) if {
	e.message == ""
	count(e.failures) > 0
	every f in e.failures {
		_for_key_leaf(f, ks)
	}
}

_for_key_leaf(e, ks) if {
	e.failures == []
	every x in split(e.message, "; ") {
		x in ks
	}
}

_leveled_kind(e) := "item" if _has_levels(e)

else := e.kind

_for_row_breaks(row, t, at, where) := array.concat(
	[_entry(w[0], w[1], row.cause, [], [], w[2]) | some w in t.walk],
	[e | some k, f in row.failed_items; rec := t.items[k]; "walk" in object.keys(rec); e := _for_walk_entry(f, _tie_texts(row, t, f, rec), at, where)],
)

_tie_texts(row, t, f, rec) := t.items[j] if {
	f.cause == "ambiguous"
	rec.walk == []
	rec.inner == []
	j := min({j | some j, g in row.failed_items; g.cause == "ambiguous"; t.items[j].walk != []})
} else := rec

_for_assertion_entry(row, at, where, t, i, a) := _policy_entry(
	"assertion",
	a,
	_worst_or_value(causes),
	_once(array.concat(
		array.concat(
			[x | some [_, _, l] in lines; some x in _with_outcomes(object.get(l, "inputs", [])); not _alias_named(x.name, aliases)],
			[x | some l in t.free; l.assertion == a; some x in _with_outcomes(_anchored_inputs(l.inputs, at))],
		),
		[x | t.flawed; lines == []; some x in _with_outcomes(row.inputs); _for_sentence_read(x.name, where.check.checks[i])],
	)),
	items,
	t.said[i],
	[_assertion_at(where, null, i)],
) if {
	i == min({j | some j, b in where.check.assertions; b == a})
	aliases := {item.as | some item in where.check.items}
	lines := [[k, j, l] | some k, f in row.failed_items; "lines" in object.keys(t.items[k]); some j, l in f.failed_assertions; l.assertion == a]
	items := _nested_items([_for_item_entry(row.failed_items[k], l, t.items[k].lines[j], aliases, at) | some [k, j, l] in lines; _for_item_said(t.items[k].lines[j])])
	causes := ({l.cause | some [_, _, l] in lines} | {l.cause | some l in t.free; l.assertion == a}) | {row.cause | lines == []; not a in {l.assertion | some l in t.free}}
	_for_assertion_said(t.said[i], items)
}

_for_assertion_said(said, _) if said != ""

_for_assertion_said(_, items) if items != []

_for_item_said(x) if x.m != ""

_for_item_said(x) if {
	some m in x.xs
	m != ""
}

_for_sentence_read(name, c) if {
	some p in _for_read_paths(c)
	name == _input_name(p)
}

_for_sentence_read(name, c) if {
	some r in _check_refs(c)
	name == _ref_label(r)
}

_alias_named(name, aliases) if {
	some a in aliases
	some w in split(name, " ")
	_alias_name_start(w, a)
}

_alias_name_start(name, a) if name == a

_alias_name_start(name, a) if startswith(name, concat("", [a, "."]))

_alias_name_start(name, a) if startswith(name, concat("", [a, "["]))

_for_item_entry(f, l, x, aliases, at) := _leveled_by(
	object.union(
		_entry(
			_walk_kind(f.item),
			f.item,
			l.cause,
			[y | some y in _with_outcomes(object.get(l, "inputs", [])); _alias_named(y.name, aliases)],
			_nested_items([_leveled_by(object.union(_entry(_walk_kind(y.item), y.item, y.cause, _with_outcomes(y.inputs), [], x.xs[n]), object.filter(y, {"value", "locations"})), object.get(y, "ergo/levels", []), at) | some n, y in object.get(l, "items", []); x.xs[n] != ""]),
			x.m,
		),
		{"value": f.value, "locations": f.locations},
	),
	object.get(f, "ergo/levels", []),
	at,
)

_for_walk_entry(f, rec, at, where) := _leveled_by(_for_walk_entry_of(f, rec, at, _for_item_whose(where.check.items, f), object.get(where.check.items[count(where.check.items) - 1], "whose", [])), object.get(f, "ergo/levels", []), at)

_for_item_whose(items, f) := object.get(items[1], "whose", []) if {
	count(items) == 2
	_list_base(f.item) == _path_name(items[1].path)
	_list_base(f.item) != _path_name(items[0].path)
} else := object.get(items[0], "whose", [])

_for_walk_entry_of(f, rec, at, first_whose, whose) := object.union(
	_entry("item", f.item, f.cause, [], [_for_sorted_entry(x, x["ergo/sorted"], concat("; ", [_entry_text(m, f.item) | some m in rec.walk]), at) | some x in f.failed_items; x.cause == "ambiguous"], ""),
	{"value": f.value, "locations": f.locations},
) if {
	rec.walk != []
	some x in object.get(f, "failed_items", [])
	_ = x["ergo/sorted"]
} else := object.union(
	_entry("item", f.item, f.cause, [{"name": x.name, "value": f.value, "locations": f.locations, "outcome": x.outcome}], [], concat("; ", [_entry_text(m, f.item) | some m in rec.walk])),
	{"value": x.value, "locations": _anchored_all([{"locations": [x.at]}], at)[0].locations},
) if {
	x := f["ergo/sorted"]
	rec.walk != []
} else := object.union(
	_entry(_walk_kind(f.item), f.item, f.cause, [], [_for_inner_entry(x, rec.inner[n], whose) | some n, x in f.failed_items; rec.inner[n] != []], ""),
	{"value": f.value, "locations": f.locations},
) if {
	rec.inner != []
}

else := object.union(
	_entry(_walk_kind(f.item), f.item, f.cause, array.concat([_item_read(f) | _walk_kind(f.item) == "list"], _whose_reads(first_whose, f)), [], concat("; ", [_entry_text(m, f.item) | some m in rec.walk])),
	{"value": f.value, "locations": f.locations},
) if {
	rec.walk != []
	_walk_kind(f.item) == "item"
} else := _entry("list", f.item, f.cause, [_item_read(f)], [], concat("; ", rec.walk)) if rec.walk != []

_whose_read_name(p, f) := concat("", [_whose_item_name(f), ".", _path_name(p)]) if p != []

else := _whose_item_name(f)

_whose_item_name(f) := concat("", [_list_base(f.item), "[", format_int(to_number(substring(f.item, 5, indexof(f.item, " of ") - 5)) - 1, 10), "]"])

_whose_read(_, p, f, st) := {"name": _whose_read_name(p, f), "value": null, "locations": f.locations, "outcome": st} if st in _no_value_states

_whose_read(c, p, f, "value") := {"name": _whose_read_name(p, f), "value": object.get(f.value, _plain_keys(p), null), "locations": [_joined(f.locations[0], _plain_keys(p))], "outcome": "unusable"} if {
	_plain_path(p)
	_row_cause(c, f.value, "") == "unusable"
}

_for_sorted_entry(x, s, text, at) := object.union(
	_entry("item", x.item, x.cause, [{"name": s.name, "value": x.value, "locations": x.locations, "outcome": s.outcome}], [], _entry_text(text, x.item)),
	{"value": s.value, "locations": _anchored_all([{"locations": [s.at]}], at)[0].locations},
)

_for_inner_entry(x, ts, whose) := object.union(_entry("item", x.item, x.cause, _whose_reads(whose, x), [], concat("; ", [_entry_text(t, x.item) | some t in ts])), {"value": x.value, "locations": x.locations}) if _walk_kind(x.item) == "item"

else := _entry("list", x.item, x.cause, [_item_read(x)], [], concat("; ", ts)) if _ = whose

_passed_row(row) := row if {
	not _row_stashed(row)
	_inputs_clean(row.inputs)
} else := object.union(object.remove(row, _row_stash_keys), {"inputs": [object.remove(i, _input_stash_keys) | some i in row.inputs]})

_row_stashed(row) if {
	some k in _row_stash_keys
	_ = row[k]
}

_inputs_clean(inputs) if {
	every i in inputs {
		not _input_stashed(i)
	}
}

_input_stashed(i) if {
	some k in _input_stash_keys
	_ = i[k]
}

_with_outcomes(inputs) := [_with_outcome(i) | some i in inputs]

_with_outcome(i) := object.union(object.remove(i, _input_stash_keys), {"outcome": i["ergo/outcome"]}) if _ = i["ergo/outcome"]

else := object.remove(i, _input_stash_keys) if i["ergo/worked"] == true

else := object.union(i, {"outcome": "found"}) if i.value != null

else := i

_entry(kind, name, cause, inputs, failures, message) := {
	"kind": kind,
	"name": name,
	"cause": cause,
	"inputs": inputs,
	"failures": failures,
	"message": message,
}

_policy_entry(kind, name, cause, inputs, failures, message, locations) := object.union(_entry(kind, name, cause, inputs, failures, message), {"locations": locations})

_row_failures(row, _, where, ins) := [_policy_entry("assertion", where.check.expression, row.cause, array.concat(ins, _tally_key_ref_entries(where.check, ins, row.cause)), [], row.message, [_assertion_at(where, null, 0)])] if {
	not _walks(where.check)
	not _all_of_run(where.check)
	not _any_of_run(where.check)
	not where.check.op == "for"
}

_row_failures(row, _, where, ins) := [_policy_entry("assertion", a, row.cause, ins, [], row.message, [_assertion_at(where, null, i)]) | some i, a in where.check.assertions] if where.check.op == "for"

_row_failures(row, at, where, _) := [_policy_entry(
	"assertion",
	fa.assertion,
	fa.cause,
	array.concat(_with_outcomes(_anchored_inputs(fa.inputs, at)), _sentence_ref_entries(where.check.checks[fa.at], fa.inputs)),
	[],
	row["ergo/texts"][k],
	[_assertion_at(where, null, fa.at)],
) |
	some k, fa in row.failed_assertions
] if _all_of_run(where.check)

_row_failures(row, at, where, _) := [_policy_entry(
	"option",
	nm,
	_group_cause({row["ergo/outs"][i].line | some i, n in where.check.option_of; n == nm}),
	[],
	[_option_assertion(row, at, where, nm, i) | some i, n in where.check.option_of; n == nm; row["ergo/outs"][i].line != "satisfied"],
	concat(", and ", _once([t | some i, n in where.check.option_of; n == nm; t := row["ergo/texts"][i]; t != ""])),
	[where.option_ats[nm]],
) |
	some nm in sort({n | some n in where.check.option_of})
] if _any_of_run(where.check)

_option_assertion(row, at, where, nm, i) := _policy_entry(
	"assertion",
	where.check.assertions[i],
	row["ergo/outs"][i].cause,
	array.concat(_with_outcomes(_anchored_inputs(row["ergo/outs"][i].inputs, at)), _sentence_ref_entries(where.check.checks[i], row["ergo/outs"][i].inputs)),
	[],
	row["ergo/texts"][i],
	[_assertion_at(where, nm, count([j | some j, n in array.slice(where.check.option_of, 0, i); n == nm]))],
)

_row_failures(row, at, where, ins) := [_policy_entry(
	"assertion",
	where.check.expression,
	row.cause,
	array.concat(array.concat([ins[j] | some j, i in row.inputs; not _item_input(i, lists)], _with_outcomes(_walk_key_ref_entries(where.check.path))), _walk_cond_ref_entries(_walk_cond_refs(where.check), row.inputs)),
	_walk_entries(row, _item_owned(row, texts), at),
	concat("; ", _once(array.concat(object.get(row, "ergo/own", [row.message]), _root_texts(row, texts)))),
	[_assertion_at(where, null, 0)],
)] if {
	_walks(where.check)
	where.check.op != "for"
	texts := object.get(row, "ergo/texts", [])
	lists := {_list_base(f.item) | some f in row.failed_items}
}

_tally_key_ref_entries(check, inputs, cause) := [x |
	some x in _with_outcomes(_walk_key_ref_entries([seg |
		walk(check, [_, y])
		is_object(y)
		some f in _tally_forms
		p := object.get(y, f, null)
		is_array(p)
		some seg in p
	]))
	not x.name in {i.name | some i in inputs}
] if {
	cause in _no_value_states
	some i in inputs
	_tally_input_name(i.name)
} else := []

_tally_input_name(name) if startswith(name, "count of ")

_tally_input_name(name) if startswith(name, "sum of ")

_sentence_ref_entries(c, inputs) := _walk_cond_ref_entries(_walk_cond_refs(c), inputs) if {
	_walks(c)
	c.op != "for"
} else := []

_walk_cond_refs(c) := _check_refs(conds) if {
	conds := array.concat([c.check], c.whose)
	some d in conds
	_cond_may_ref(d)
} else := set()

_cond_may_ref(d) if {
	some k, v in d
	k != "path"
	is_object(v)
}

_cond_may_ref(d) if {
	some k, v in d
	k != "path"
	is_array(v)
}

_walk_cond_ref_entries(refs, inputs) := [] if count(refs) == 0

else := [x |
	some x in _with_outcomes(_ref_read_entries(refs))
	not x.name in {i.name | some i in inputs}
]

_item_input(i, lists) if {
	contains(i.name, "[]")
	substring(i.name, 0, indexof(i.name, "[]")) in lists
}

_list_base(name) := substring(n, 0, indexof(n, "[")) if {
	n := _unitemed(name)
	contains(n, "[")
} else := _unitemed(name)

_unitemed(name) := concat(" of ", array.slice(ps, 1, count(ps))) if {
	startswith(name, "item ")
	ps := split(name, " of ")
	count(ps) > 1
} else := name

_walk_entries(_, [], _) := []

_item_owned(row, texts) := texts if {
	every k, t in texts {
		not _root_text(row.failed_items[k].item, t)
	}
} else := [_owned_text(row.failed_items[k].item, t) | some k, t in texts]

_owned_text(name, t) := "" if _root_text(name, t)

else := t

_root_texts(row, texts) := [t | some k, t in texts; _root_text(row.failed_items[k].item, t)]

_root_text(name, t) if {
	t != ""
	startswith(name, "item ")
	not startswith(t, "item ")
}

_walk_entries(row, texts, at) := _nested_items([_leveled(_walk_entry(row, texts, name, at), row, name, at) |
	some k, f in row.failed_items
	name := f.item
	not name in [g.item | some g in array.slice(row.failed_items, 0, k)]
	_said_for(row, texts, name)
]) if texts != []

_said_for(row, texts, name) if {
	some k, f in row.failed_items
	f.item == name
	texts[k] != ""
}

_leveled(e, row, name, at) := _leveled_by(e, _item_levels_of(row, name), at)

_leveled_by(e, levels, at) := object.union(e, {
	"name": names[count(levels)],
	"message": _level_text(e.message, _level_said(e.kind, names)),
	"ergo/levels": [object.union(_anchored_all([lv], at)[0], {"name": names[j]}) | some j, lv in levels],
}) if {
	count(levels) > 0
	count(levels) < 4
	names := _level_names(e.name, count(levels))
	count(names) == count(levels) + 1
} else := e

_level_said("item", names) := names

_level_said("list", names) := array.slice(names, 0, count(names) - 1)

_level_text(text, names) := substring(text, count(p) + 2, -1) if {
	p := concat(": ", names)
	startswith(text, concat("", [p, ": "]))
} else := substring(text, count(p) + 2, -1) if {
	p := concat(": ", array.slice(names, 0, count(names) - 1))
	startswith(text, concat("", [p, ": "]))
} else := _entry_text(text, names[count(names) - 1])

_item_levels_of(row, name) := ls[0] if {
	ls := [x | some f in row.failed_items; f.item == name; x := f["ergo/item"].levels]
	count(ls) > 0
} else := []

_level_names(name, m) := array.concat(_outer_level_names(b, m), [concat("", ["item ", substring(name, 5, at - 5), " of ", _level_field(b.fields[m])])]) if {
	startswith(name, "item ")
	at := indexof(name, " of ")
	b := _level_bits(substring(name, at + 4, -1), m)
}

_level_names(name, m) := array.concat(_outer_level_names(b, m), [b.fields[m]]) if {
	not startswith(name, "item ")
	b := _level_bits(name, m)
}

_outer_level_names(b, m) := [concat("", ["item ", format_int(to_number(b.idx[j + 1]) + 1, 10), " of ", _level_field(b.fields[j])]) | some j in numbers.range(0, m - 1)]

_level_field(field) := "it" if field == ""

else := field

_level_bits(path, m) := {"idx": idx, "fields": fields} if {
	pieces := split(path, "[")
	count(pieces) == m + 1
	idx := array.concat([""], [substring(p, 0, indexof(p, "]")) | some p in array.slice(pieces, 1, count(pieces))])
	every j in numbers.range(1, m) {
		regex.match(`^[0-9]+$`, idx[j])
	}
	fields := array.concat([pieces[0]], [trim_prefix(substring(p, indexof(p, "]") + 1, -1), ".") | some p in array.slice(pieces, 1, count(pieces))])
}

_nested_items(es) := es if {
	every e in es {
		not _has_levels(e)
	}
} else := _nest_at0(es)

_has_levels(e) if _ = e["ergo/levels"]

_level_key(e, j) := e["ergo/levels"][j].name if count(object.get(e, "ergo/levels", [])) > j

else := concat("", ["\u0000", e.name])

_first_of_key(es, k, j) if {
	key := _level_key(es[k], j)
	not key in [_level_key(x, j) | some x in array.slice(es, 0, k)]
}

_level_group(lv, kids) := {"kind": "item", "name": lv.name, "cause": _worst_or_value({c.cause | some c in kids}), "inputs": [], "failures": kids, "message": "", "value": lv.value, "locations": lv.locations}

_level_leaf(e) := object.remove(e, ["ergo/levels"])

_nest_at0(es) := [_nest_node0(es, k) | some k, _ in es; _first_of_key(es, k, 0)]

_nest_node0(es, k) := _level_group(es[k]["ergo/levels"][0], _nest_at1([x | some x in es; _level_key(x, 0) == _level_key(es[k], 0)])) if count(object.get(es[k], "ergo/levels", [])) > 0

else := _level_leaf(es[k])

_nest_at1(es) := [_nest_node1(es, k) | some k, _ in es; _first_of_key(es, k, 1)]

_nest_node1(es, k) := _level_group(es[k]["ergo/levels"][1], _nest_at2([x | some x in es; _level_key(x, 1) == _level_key(es[k], 1)])) if count(object.get(es[k], "ergo/levels", [])) > 1

else := _level_leaf(es[k])

_nest_at2(es) := [_nest_node2(es, k) | some k, _ in es; _first_of_key(es, k, 2)]

_nest_node2(es, k) := _level_group(es[k]["ergo/levels"][2], [_level_leaf(x) | some x in es; _level_key(x, 2) == _level_key(es[k], 2)]) if count(object.get(es[k], "ergo/levels", [])) > 2

else := _level_leaf(es[k])

_walk_entry(row, texts, name, at) := object.union(
	_entry(
		_walk_kind(name),
		name,
		_worst_or_value({f.cause | some f in row.failed_items; f.item == name}),
		[_item_read(f) | some f in row.failed_items; f.item == name; _reads_inside(f, name)],
		[],
		concat("; ", _once([_entry_text(texts[k], name) | some k, f in row.failed_items; f.item == name; texts[k] != ""])),
	),
	_item_seen(row, name, at),
)

_reads_inside(f, name) if f.path != name

_reads_inside(_, name) if _walk_kind(name) == "list"

_walk_kind(name) := "item" if startswith(name, "item ")

else := "list"

_item_seen(row, name, at) := {"value": item.value, "locations": _anchored_all([item], at)[0].locations} if {
	_walk_kind(name) == "item"
	some f in row.failed_items
	f.item == name
	item := f["ergo/item"]
	is_object(item)
} else := {"value": f.value, "locations": _anchored_all([f], at)[0].locations} if {
	_walk_kind(name) == "item"
	f := [g | some g in row.failed_items; g.item == name][0]
} else := {}

_item_read(f) := {"name": f.path, "value": f.value, "locations": f.locations, "outcome": _item_outcome(f.cause, f.value)}

_item_outcome(cause, value) := cause if cause in _failed_read_states

else := "found" if value != null

else := "null"

_entry_text(text, name) := substring(text, count(name) + 2, -1) if startswith(text, concat("", [name, ": "]))

else := text

_where(req_name, name, check) := object.union(w, {
	"ats": object.union({"": a | a := _assertion_ats(w, null)}, {nm: a | some nm in _option_names(check); a := _assertion_ats(w, nm)}),
	"option_ats": {nm: _option_at(w, nm) | some nm in _option_names(check)},
}) if w := {"check": check, "req": req_name, "name": name}

_option_names(check) := {n | some n in check.option_of}

_assertion_ats(where, option) := [concat("", [x]) | some x in _lines_at(lines, n)] if {
	lines := _written_lines(where, option)
	n := _assertion_count(where, option)
}

_assertion_at(where, null, k) := where.ats[""][k]

_assertion_at(where, option, k) := where.ats[option][k] if option != null

_condition_of(req, name, c) := object.union({"expression": e | e := _expression_of(c)}, {"at": a | a := _condition_at(req, name)})

_option_at(where, nm) := _joined("$policy:", ["requirements", where.req, "checks", where.name, "any_of", nm])

_written_check(where) := object.get(_written_requirements, [where.req, "checks", where.name], null)

default _written_requirements := {}

_written_requirements := data.ergo_written

_written_lines(where, null) := {"at": _joined("$policy:", ["requirements", where.req, "checks", where.name]), "lines": w, "list": false} if {
	w := _written_check(where)
	is_string(w)
}

_written_lines(where, null) := {"at": _joined("$policy:", ["requirements", where.req, "checks", where.name, "assert"]), "lines": w.assert, "list": is_array(w.assert)} if {
	w := _written_check(where)
	is_object(w)
}

_written_lines(where, nm) := {"at": _joined("$policy:", ["requirements", where.req, "checks", where.name, "any_of", nm]), "lines": w.any_of[nm], "list": is_array(w.any_of[nm])} if {
	nm != null
	w := _written_check(where)
}

_assertion_count(where, null) := count(where.check.assertions) if "assertions" in object.keys(where.check)

else := 1

_assertion_count(where, nm) := count([n | some n in where.check.option_of; n == nm]) if nm != null

_lines_at(lines, n) := [lines.at | some _ in numbers.range(1, n)] if {
	not lines.list
	n == 1
}

_lines_at(lines, n) := [concat("", [lines.at, "#", format_int(k, 10)]) | some k in numbers.range(1, n)] if {
	not lines.list
	n > 1
}

_lines_at(lines, n) := [_joined(lines.at, [j]) | some j, _ in lines.lines] if {
	lines.list
	count(lines.lines) == n
}

_lines_at(lines, n) := [_line_mark(lines.at, j, counts[j], k) | some j, _ in lines.lines; some k in numbers.range(1, counts[j])] if {
	lines.list
	count(lines.lines) != n
	counts := [count(object.get(_sentence(line), "assertions", [line])) | some line in lines.lines]
}

_line_mark(at, j, 1, _) := _joined(at, [j])

_line_mark(at, j, c, k) := concat("", [_joined(at, [j]), "#", format_int(k, 10)]) if c > 1

_parted_applies(row, _, _, _, _) := _passed_row(row) if row.passed == true

_parted_applies(row, at, evals, req, conds) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": ins,
	"failures": _applies_entries(row, at, evals, req, conds, ins),
}) if {
	row.passed == false
	ins := _with_outcomes(row.inputs)
}

_applies_entries(row, at, evals, _, conds, ins) := [_policy_entry(
	"assertion",
	conds[name].expression,
	e.assertion_cause,
	[ins[j] | some j, i in row.inputs; not _item_input(i, lists)],
	_walk_entries(row, _item_owned(row, texts), at),
	concat("; ", _once(array.concat(object.get(e, "ergo/own", [row.message]), _root_texts(row, texts)))),
	[conds[name].at],
)] if {
	count(evals) == 1
	some name, e in evals
	"failed_items" in object.keys(row)
	texts := object.get(e, "ergo/texts", [])
	lists := {_list_base(f.item) | some f in row.failed_items}
}

_applies_entries(row, _, evals, _, conds, ins) := [_policy_entry(
	"assertion",
	conds[name].expression,
	e.assertion_cause,
	ins,
	[],
	row.message,
	[conds[name].at],
)] if {
	count(evals) == 1
	some name, e in evals
	not "failed_items" in object.keys(row)
}

_applies_entries(_, at, evals, req, conds, _) := [_policy_entry(
	"assertion",
	conds[name].expression,
	evals[name].assertion_cause,
	_with_outcomes(_anchored_inputs(evals[name].inputs, at)),
	[],
	texts[k],
	[conds[name].at],
) |
	some k, name in failed
] if {
	count(evals) > 1
	failed := [n | some n in _applies_to_names(req); evals[n].assertion_cause != "satisfied"]
	texts := [_unpassed_message(evals[n]) | some n in failed]
}

_unpassed_message(e) := e.message if e.passed == false

else := ""

_condition_at(req, name) := _joined("$policy:", ["subjects", owner, "from"]) if {
	owner := _resolution_of(req).filter_owners[name]
	count([n | some n, o in _resolution_of(req).filter_owners; o == owner]) == 1
} else := concat("", [_joined("$policy:", ["subjects", owner, "from"]), "#", format_int(k + 1, 10)]) if {
	owner := _resolution_of(req).filter_owners[name]
	some k, n in sort([n | some n, o in _resolution_of(req).filter_owners; o == owner])
	n == name
}

_whose_reads(whose, f) := [r |
	is_object(f.value)
	some c in whose
	some x in _walk_sides_paths(c)
	p := x[0]
	is_array(p)
	not _walk_outside(p)
	r := _whose_read(c, p, f, _read_state(f.value, p))
] if _walk_kind(f.item) == "item"

else := []
