package ergo

import rego.v1

_row_stash_keys := ["failed_items", "failed_assertions", "ergo/texts", "ergo/own", "ergo/heads", "ergo/outs", "ergo/for_texts", "ergo/key_lists", "ergo/key_bases", "ergo/subj", "ergo/req"]

_parted(row, _, _) := _passed_row(row) if row.passed == true

_parted(row, at, where) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": _for_row_inputs(row, where),
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
	ins := _tally_outcomes(_with_outcomes(row.inputs), row, where.check)
}

_tally_outcomes(ins, row, check) := [_tally_outcome(i, said) | some i in ins] if {
	not _walks(check)
	check.op != "for"
	lists := _tally_list_names(check)
	count(lists) > 0
	said := {_list_clause_name(c): _clause_cause(c) | some c in _tally_clauses(row.message); _list_clause_name(c) in lists}
} else := ins

_tally_outcome(i, said) := object.union(i, {"outcome": said[i.name]}) if _ = said[i.name]

else := i

_for_texted(row) if _ = row["ergo/for_texts"]

_for_failures(row, at, where, t) := [_own_caused(e) | some e in _for_failures_raw(row, at, where, t)]

_own_caused(e) := _with_own_cause(e, [_own_caused_2(k) | some k in e.failures])

_own_caused_2(e) := _with_own_cause(e, [_own_caused_3(k) | some k in e.failures])

_own_caused_3(e) := _with_own_cause(e, [_with_own_cause(k, k.failures) | some k in e.failures])

_with_own_cause(e, kids) := object.union(e, {"failures": kids, "cause": c}) if {
	e.kind in {"item", "list"}
	own := {_cause_of_outcome(i.outcome) | some i in e.inputs; not object.get(i, "outcome", "usable") in {"usable", "value"}} | {k.cause | some k in kids}
	own != set()
	c := _worst_of(own)
	_worst_of({c, e.cause}) == e.cause
	not contains(e.message, ", and ")
	not contains(e.message, "; ")
} else := object.union(e, {"failures": kids})

_cause_of_outcome("missing") := "absent"

_cause_of_outcome(o) := o if o != "missing"

_for_failures_raw(row, at, where, t) := _for_failures_of(row, at, where, t, array.concat([x[1] | some x in _for_key_flaws(where.check); not _key_said_in_item(row, x[1])], [e.message | some e in _key_list_parts(row, at)]))

_key_said_in_item(row, k) if contains(row.message, concat("", [": ", k]))

_for_failures_of(row, at, where, t, ks) := array.concat(
	array.concat(
		asserted,
		_nested_items([p | some kind in ["list", "item"]; some e in _for_row_breaks(row, t, at, where); _leveled_kind(e) == kind; not _for_said_under(e, asserted); some p in _for_key_pruned(e, ks)]),
	),
	_key_list_parts(row, at),
) if asserted := [e | some i, a in where.check.assertions; e := _for_assertion_entry(row, at, where, t, i, a)]

_for_said_under(e, asserted) if {
	e.kind == "list"
	said := {concat(": ", [x.name, x.message]) | some a in asserted; some x in a.failures; x.message != ""}
	every m in split(e.message, "; ") {
		m in said
	}
}

_key_list_parts(row, at) := [_entry("list", x.input.name, x.cause, _anchored_all([object.union(object.remove(x.input, _input_stash_keys), {"outcome": _key_list_outcome(x.cause)})], at), [], _m_key_list_text(x.input.name, x)) | some x in object.get(row, "ergo/key_lists", [])]

_key_list_outcome("value") := "usable"

_key_list_outcome(c) := c if c != "value"

_for_key_flaws(check) := _once(array.concat(
	[[x, _for_key_text(x, x.outcome)] | some item in check.items; some x in _key_flaw_entries(item.path)],
	array.concat(
		[[x, _for_key_text(x, x.outcome)] | some item in check.items; some c in object.get(item, "whose", []); some [p, _] in _key_base_reads(c); some x in _key_flaw_entries(p)],
		[[x, _for_key_text(x, x.outcome)] | some item in check.items; by := object.get(item, ["pick", "by"], null); is_array(by); some x in _key_flaw_entries(by)],
	),
))

_key_flaw_entries(path) := [object.union(object.remove(x, _input_stash_keys), {"outcome": f}) |
	some seg in path
	f := _ref_step_flaw(seg)
	some x in _ref_read_entries({seg.ref})
]

_for_key_text(x, "unusable") := _m_isnt(x.name, x.value, "text")

_for_key_text(x, f) := concat("", [x.name, " is ", _key_ref_word[f]]) if f in _no_value_states

_for_row_inputs(row, where) := _once(array.concat(_with_outcomes(row.inputs), [x[0] | some x in _for_key_flaws(where.check)]))

_for_key_pruned(e, ks) := [] if _for_key_leaf(e, ks)

else := [object.union(e, {"failures": kept})] if {
	e.message == ""
	count(e.failures) > 0
	kept := [f | some f in e.failures; not _for_key_leaf(f, ks)]
	kept != []
} else := [] if {
	e.message == ""
	count(e.failures) > 0
} else := [e]

_for_key_leaf(e, ks) if {
	e.failures == []
	every x in split(e.message, "; ") {
		x in ks
	}
}

_leveled_kind(e) := "item" if _has_levels(e)

else := e.kind

_for_row_breaks(row, t, at, where) := array.concat(
	[_entry(w[0], w[1], row.cause, [i | some i in _with_outcomes(row.inputs); _list_read_of(i.name, w[1])], [], w[2]) | some w in t.walk],
	[e | some k, f in row.failed_items; rec := t.items[k]; "walk" in object.keys(rec); e := _for_walk_entry(f, _tie_texts(row, t, f, rec), at, where)],
)

_list_read_of(name, list) if name == list

_list_read_of(name, list) if name == concat("", [list, "[]"])

_tie_texts(row, t, f, rec) := t.items[j] if {
	f.cause == "ambiguous"
	rec.walk == []
	rec.inner == []
	j := min({j | some j, g in row.failed_items; g.cause == "ambiguous"; t.items[j].walk != []})
} else := rec

_for_assertion_entry(row, at, where, t, i, a) := _for_free_entry(_for_assertion_base(row, at, where, t, i, a), row, at, where, i)

_for_free_entry(e, row, at, where, i) := _tallied_entry(e, where.check.checks[i], {"cause": e.cause}, at, where, row) if {
	_ = row["ergo/subj"]
	not _reads_alias_of(where.check.checks[i], {item.as | some item in where.check.items})
} else := e

_reads_alias_of(c, aliases) if {
	some a in aliases
	_reads_name(c, a)
}

_for_assertion_base(row, at, where, t, i, a) := _policy_entry(
	"assertion",
	a,
	_worst_or_value(causes),
	_once(array.concat(
		array.concat(
			[x | some [_, _, l] in lines; some x in _with_outcomes(object.get(l, "inputs", [])); not _alias_named(x.name, aliases); not _sentence_walked_read(x, where.check.checks[i])],
			[_with_row_part(x, row.inputs) | some l in t.free; l.assertion == a; some x in _with_outcomes(_anchored_inputs(l.inputs, at))],
		),
		[x | lines == []; not a in {l.assertion | some l in t.free}; some x in _with_outcomes(row.inputs); _for_sentence_read(x.name, where.check.checks[i]); not _alias_named(x.name, aliases)],
	)),
	items,
	t.said[i],
	[_assertion_at(where, null, i)],
) if {
	i == min({j | some j, b in where.check.assertions; b == a})
	aliases := {item.as | some item in where.check.items}
	lines := [[k, j, l] | some k, f in row.failed_items; "lines" in object.keys(t.items[k]); some j, l in f.failed_assertions; l.assertion == a]
	items := _nested_items([_for_item_of(row, where, i, row.failed_items[k], l, t.items[k].lines[j], aliases, at) | some [k, j, l] in lines; _for_item_said(t.items[k].lines[j])])
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

_for_bindable(v, _, _) if is_object(v)

_for_bindable(v, c, a) if {
	is_array(v)
	_for_walks_alias(c, a)
}

_for_walks_alias(c, a) if {
	_walks(c)
	c.path[0] == concat("", ["$", a])
}

_for_walks_alias(c, a) if {
	some k in ["left", "right"]
	side := object.get(c, k, null)
	is_object(side)
	p := side[_basic_form(side)]
	is_array(p)
	p[0] == concat("", ["$", a])
}

_for_item_of(row, where, i, f, l, x, aliases, at) := _leveled_by(object.union(e, {"value": f.value, "locations": f.locations}), object.get(f, "ergo/levels", []), at) if {
	count(where.check.items) == 1
	_for_bindable(f.value, where.check.checks[i], where.check.items[0].as)
	bound := _bound(_for_names, where.check.items[0].as, f.value, f.locations[0])
	e := _for_sentence_part(row, where, i, f.item, l.cause, [y | some y in _with_outcomes(object.get(l, "inputs", [])); _alias_named(y.name, aliases)], x.m, at, bound)
} else := _for_item_entry(f, l, x, aliases, at, row, where, i)

_for_second_of(row, where, i, f, y, text, at) := object.union(e, object.filter(y, {"value", "locations"})) if {
	count(where.check.items) == 2
	_for_bindable(f.value, where.check.checks[i], where.check.items[0].as)
	_for_bindable(y.value, where.check.checks[i], where.check.items[1].as)
	bound := _bound(_bound(_for_names, where.check.items[0].as, f.value, f.locations[0]), where.check.items[1].as, y.value, y.locations[0])
	e := _for_sentence_part(row, where, i, y.item, y.cause, _with_outcomes(y.inputs), text, at, bound)
} else := object.union(_entry(_walk_kind(y.item), y.item, y.cause, _with_outcomes(y.inputs), [], text), object.filter(y, {"value", "locations"}))

_for_sentence_part(row, where, i, name, cause, ins, text, at, bound) := _entry("item", name, cause, [y | some y in w.inputs; _alias_named(y.name, {it.as | some it in where.check.items})], w.failures, "") if {
	c := where.check.checks[i]
	_walks(c)
	c.op != "for"
	w := _for_walk_part(c, row["ergo/subj"], row["ergo/req"], at, where, i) with input as {"ergo/names": bound}
	w.message == ""
} else := _entry("item", name, cause, w.inputs, _unmarked_entries(w.failures), w.message) if {
	c := where.check.checks[i]
	not _walks(c)
	_tally_worded({"expression": where.check.assertions[i]})
	w := _tallied_entry(_entry("assertion", where.check.assertions[i], cause, ins, [], text), c, {"cause": cause}, at, where, row) with input as {"ergo/names": bound}
	w.failures != []
}

_unmarked_entries(es) := [_unmarked_entry(e, [_unmarked_entry(g, [_unmarked_entry(h, h.failures) | some h in g.failures]) | some g in e.failures]) | some e in es]

_unmarked_entry(e, failures) := object.union(e, {"name": _m_aliased(e.name), "message": _m_aliased(e.message), "inputs": [object.union(y, {"name": _m_aliased(y.name)}) | some y in e.inputs], "failures": failures})

_for_walk_part(c, subj, req, at, where, i) := _walk_assertion_entry(wrow, at, object.union(where, {"check": object.union(c, {"expression": where.check.assertions[i]}), "ats": {"": [""]}}), _with_outcomes(wrow.inputs)) if {
	raw := _check_outcome(c, subj, "")
	raw.passed == false
	wrow := object.union(_anchored(_alias_unmarked(_keyed_rooted(_for_said(raw), c, subj)), at), {"ergo/subj": subj, "ergo/req": req})
}

_alias_unmarked(o) := object.union(o, object.filter(
	{
		"message": _m_aliased(o.message),
		"inputs": [object.union(x, {"name": _m_aliased(x.name)}) | some x in o.inputs],
		"failed_items": [object.union(f, object.filter({"item": _m_aliased(f.item), "path": _m_aliased(f.path), "ergo/read": _m_aliased(object.get(f, "ergo/read", ""))}, object.keys(f))) | some f in object.get(o, "failed_items", [])],
		"ergo/texts": [object.union(c, {"text": _m_aliased(c.text)}) | some c in object.get(o, "ergo/texts", [])],
		"ergo/own": [_m_aliased(t) | some t in object.get(o, "ergo/own", [])],
	},
	object.keys(o),
))

_for_item_entry(f, l, x, aliases, at, row, where, i) := _leveled_by(
	object.union(
		_entry(
			_walk_kind(f.item),
			f.item,
			l.cause,
			[y | some y in _with_outcomes(object.get(l, "inputs", [])); _alias_named(y.name, aliases)],
			_nested_items([_leveled_by(_for_second_of(row, where, i, f, y, x.xs[n], at), object.get(y, "ergo/levels", []), at) | some n, y in object.get(l, "items", []); x.xs[n] != ""]),
			x.m,
		),
		{"value": f.value, "locations": f.locations},
	),
	object.get(f, "ergo/levels", []),
	at,
)

_for_walk_entry(f, rec, at, where) := _leveled_by(_for_walk_entry_of(f, rec, at, _for_item_whose(where.check.items, f), object.get(where.check.items[count(where.check.items) - 1], "whose", []), where), object.get(f, "ergo/levels", []), at)

_key_cut_name(name, where) := substring(name, 0, indexof(name, " named by ")) if {
	contains(name, " named by ")
	some item in where.check.items
	by := object.get(item, ["pick", "by"], null)
	is_array(by)
	count(_key_flaw_entries(by)) > 0
} else := name

_for_item_whose(items, f) := object.get(items[1], "whose", []) if {
	count(items) == 2
	_list_base(f.item) == _path_name(items[1].path)
	_list_base(f.item) != _path_name(items[0].path)
} else := object.get(items[0], "whose", [])

_for_walk_entry_of(f, rec, at, first_whose, whose, where) := object.union(
	_entry("item", f.item, f.cause, [], [_for_sorted_entry(x, x["ergo/sorted"], concat("; ", [_entry_text(m, f.item) | some m in rec.walk]), at) | some x in f.failed_items; x.cause == "ambiguous"], ""),
	{"value": f.value, "locations": f.locations},
) if {
	rec.walk != []
	some x in object.get(f, "failed_items", [])
	_ = x["ergo/sorted"]
} else := object.union(
	_entry("item", f.item, f.cause, [{"name": _key_cut_name(x.name, where), "value": f.value, "locations": f.locations, "outcome": x.outcome}], [], _sorted_item_text(rec.walk, f.item)),
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
	_entry(_walk_kind(f.item), f.item, _whose_own_cause(first_whose, f, rec.walk), array.concat([_item_read(f) | _walk_kind(f.item) == "list"], _whose_reads(first_whose, f)), [], concat("; ", [_entry_text(m, f.item) | some m in rec.walk])),
	{"value": f.value, "locations": f.locations},
) if {
	rec.walk != []
	_walk_kind(f.item) == "item"
} else := _entry("list", f.item, f.cause, [_item_read(f)], [], concat("; ", rec.walk)) if rec.walk != []

_whose_read_name(p, f) := concat("", [_whose_item_name(f), ".", _path_name(array.slice(p, 0, i))]) if {
	i := min({j | some j, seg in p; _ref_step_flaw(seg)})
	i > 0
} else := concat("", [_whose_item_name(f), ".", _path_name(p)]) if p != []

else := _whose_item_name(f)

_whose_item_name(f) := concat("", [p[1], ".", substring(p[0], 7, -1)]) if p := _member_parts(f.item)

else := concat("", [_list_base(f.item), "[", format_int(to_number(substring(f.item, 5, indexof(f.item, " of ") - 5)) - 1, 10), "]"])

_whose_read(_, p, f, st) := {"name": _whose_read_name(p, f), "value": null, "locations": f.locations, "outcome": _worst_of({st} | {x | some seg in p; x := _ref_step_flaw(seg); x in _value_fault_causes})} if st in _no_value_states

_whose_read(c, p, f, "value") := {"name": _whose_read_name(p, f), "value": object.get(f.value, _plain_keys(p), null), "locations": [_joined(f.locations[0], _plain_keys(p))], "outcome": "unusable"} if {
	_plain_path(p)
	_row_cause(c, f.value, "") == "unusable"
	not "unusable" in _key_item_flaws({"whose": [c]})
}

_whose_own_cause(whose, f, texts) := _worst_of(causes) if {
	count(_key_item_flaws({"whose": whose})) > 0
	not _texts_name_key(whose, texts)
	is_object(f.value)
	causes := {b.cause | some c in whose; some [p, mode] in _key_base_reads(c); not p[0] in _params_starts; p[0] != "$$input"; some b in _key_base_flaws(f.value, p, mode)}
	count(causes) > 0
} else := f.cause

_texts_name_key(whose, texts) if {
	some c in whose
	some [p, _] in _key_base_reads(c)
	some k in _m_key_texts(p)
	some t in texts
	contains(t, k)
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

else := object.union(i, {"outcome": "unusable"}) if {
	i.value != null
	i.name in data.ergo_unfit
} else := object.union(i, {"outcome": "unusable"}) if {
	_text_list_input(i.name)
	is_array(i.value)
	_text_items_state(i.value)
} else := object.union(i, {"outcome": "usable"}) if i.value != null

else := i

_text_list_input(name) if name in data.ergo_text_lists

_text_list_input(name) if replace(name, "[]", "") in data.ergo_text_lists

_entry(kind, name, cause, inputs, failures, message) := {
	"kind": kind,
	"name": name,
	"cause": cause,
	"inputs": inputs,
	"failures": failures,
	"message": message,
}

_policy_entry(kind, name, cause, inputs, failures, message, locations) := object.union(_entry(kind, name, cause, inputs, failures, message), {"locations": locations})

_row_failures(row, at, where, ins) := [_policy_entry("assertion", where.check.expression, row.cause, [i | some i in _with_key_bases(array.concat(ins, _check_key_ref_entries(where.check, ins, row.cause, row.message)), object.get(row, "ergo/key_bases", []), at); not i.name in names; not _item_input(i, lists); not _tally_own_read(i, where.check, names, items)], array.concat(ls, items), _tally_rest_of(row.message, names, texts), [_assertion_at(where, null, 0)])] if {
	not _walks(where.check)
	not _all_of_run(where.check)
	not _any_of_run(where.check)
	not where.check.op == "for"
	lists := (_tally_list_names(where.check) | _tally_keyed_list_names(where.check, object.get(row, "ergo/subj", null))) | _tally_unkeyed_lists(where.check, object.get(row, "ergo/subj", null))
	ls := _plain_tally_lists(row, at, lists, ins, where.check)
	names := {e.name | some e in ls}
	items := _tally_item_parts_of(row, where.check, at)
	texts := _tally_item_texts_of(row, where.check)
}

_row_mcheck(row, c) := _labelled_for(_list_read(c, row["ergo/req"], row["ergo/subj"]), row["ergo/req"], row["ergo/subj"])

_plain_tally_lists(row, at, lists, ins, c) := [] if count(lists) == 0

else := _tally_list_entries(object.union(row, {"ergo/check": _row_mcheck(row, c)}), at, lists, ins)

_tally_worded(c) if contains(object.get(c, "expression", ""), "count of ")

_tally_worded(c) if contains(object.get(c, "expression", ""), "sum of ")

_subj_tally_lists(row, at, lists, ins, subj, c) := [] if count(lists) == 0

else := _tally_list_entries(object.union(row, {"ergo/subj": subj, "ergo/check": c}), at, lists, ins)

_gated_tally_parts(c, expr, subj, cause, at, m) := _tally_item_parts(c, subj, cause, at, m) if _tally_worded({"expression": expr})

else := []

_gated_tally_texts(c, expr, subj, cause, m) := _tally_item_texts(c, subj, cause, m) if _tally_worded({"expression": expr})

else := set()

_tally_item_parts_of(row, c, at) := [] if not _tally_worded(c)

else := _tally_item_parts(_row_mcheck(row, c), row["ergo/subj"], row.cause, at, row.message)

_tally_item_texts_of(row, c) := set() if not _tally_worded(c)

else := _tally_item_texts(_row_mcheck(row, c), row["ergo/subj"], row.cause, row.message)

_sub_mcheck(where, c, row) := m if {
	some i, x in where.check.checks
	x == c
	m := _row_mcheck(row, where.check).checks[i]
} else := c

_tally_said_in(t, m) if contains(m, t)

_tally_said_in(_, m) if regex.match(`(^|; )and [0-9]+ more$`, m)

_tally_item_texts(c, subj, cause, m) := _tally_record_texts(c, subj, cause, m) | {f.clause | some f in _tally_keyed_found(c, subj, m)}

_tally_record_texts(c, subj, cause, m) := {_m_aliased(r[1]) |
	is_object(c)
	mc := object.union(_m_with_sides(_m_walked(c, subj)), {"ergo/row": true})
	some side in _m_tally_parts(mc)
	rs := _m_tally_records(subj, side, cause)
	some r0 in rs
	count(r0) == 3
	not _tally_root_said(r0, rs)
	r := _tally_unrooted(r0, m)
	r != null
	_tally_record_listed(r[2])
	_tally_said_in(_m_aliased(r[1]), m)
}

_tally_root_said(r, rs) if {
	some x in rs
	count(x) == 2
	x[1] == r[1]
}

_tally_record_listed(src) if _m_positions(src.item.i) != []

_tally_record_listed(src) if _m_positions(src.key.i) != []

_tally_record_listed(src) if _m_positions(src.fail.path) != []

_tally_rest_of(m, names, texts) := _tally_rest(m, names) if count(texts) == 0

else := concat("; ", [c |
	some p in _m_top_split(m, "; ")
	not p in texts
	c := concat(", and ", [q | some q in _m_top_split(p, ", and "); not q in texts; not _list_clause_name(q) in names; not _and_more(q)])
	c != ""
])

_and_more(q) if regex.match(`^and [0-9]+ more$`, q)

_tally_own_read(i, c, _, _) if {
	contains(i.name, "[]")
	some side in _m_tally_parts(c)
	p := side[_basic_form(side)]
	is_array(p)
	_walked_path_read({"name": _m_aliased(i.name)}, _m_aliased(_input_name(p)))
}

_tally_own_read(i, c, _, items) if {
	items != []
	some side in _m_tally_parts(c)
	not side.member
	p := side[_basic_form(side)]
	is_array(p)
	_m_aliased(i.name) == _m_aliased(_input_name(p))
}

_tally_own_read(i, c, _, _) if {
	is_array(i.value)
	not contains(i.name, "[]")
	some side in _m_tally_parts(c)
	side.member == true
	p := side[_basic_form(side)]
	is_array(p)
	_m_aliased(i.name) == _m_aliased(_input_name(p))
}

_sentence_walked_read(x, c) if {
	_walks(c)
	c.op != "for"
	_walked_path_read(x, _m_aliased(_walked_name(c.path)))
}

_sentence_walked_read(x, c) if {
	contains(x.name, "[]")
	some side in _m_tally_parts(c)
	p := side[_basic_form(side)]
	is_array(p)
	_walked_path_read(x, _m_aliased(_input_name(p)))
}

_tally_own_read(i, c, _, _) if {
	contains(i.name, " named by ")
	i.value == []
	some side in _m_tally_parts(c)
	p := side[_basic_form(side)]
	is_array(p)
	_m_aliased(i.name) == _m_aliased(_input_name(p))
}

_tally_own_read(i, c, names, _) if {
	names != set()
	i.value == []
	some side in _m_tally_parts(c)
	p := side[_basic_form(side)]
	is_array(p)
	_m_aliased(i.name) == _m_aliased(_input_name(p))
}

_tally_clauses(m) := ps if {
	ps := _m_top_split(m, "; ")
	count(ps) > 1
} else := _m_top_split(m, ", and ")

_tally_rest(m, names) := m if count(names) == 0

else := concat(sep, [c | some c in cs; not _list_clause_name(c) in names]) if {
	cs := _tally_clauses(m)
	sep := _tally_sep(m, cs)
}

_tally_sep(_, cs) := ", and " if count(cs) == 1

_tally_sep(m, cs) := _semi_or_and(count(_m_top_split(m, "; "))) if count(cs) != 1

_semi_or_and(1) := ", and "

_semi_or_and(n) := "; " if n != 1

_tally_list_names(check) := {_m_aliased(_input_name(array.slice(p, 0, i))) |
	some side in _m_tally_parts(check)
	p := side[_basic_form(side)]
	is_array(p)
	some i in numbers.range(1, count(p))
	every seg in array.slice(p, 0, i) {
		is_string(seg)
	}
}

_tally_list_entries(row, at, lists, ins) := [] if count(lists) == 0

else := [_entry("list", n, cause, _tally_list_read(n, cause, row, ins, at), [], c) |
	some c in _tally_clauses(row.message)
	n := _list_clause_name(c)
	n in lists
	cause := _clause_cause(c)
]

_list_clause_name(c) := substring(c, 0, indexof(c, " can't be read: ")) if contains(c, " can't be read: ")

else := _m_clause_name(c)

_tally_keyed_list_names(check, subj) := {_m_aliased(_input_name(array.concat(array.slice(p, 0, i), [k]))) |
	some side in _m_tally_parts(check)
	p := side[_basic_form(side)]
	is_array(p)
	some i, seg in p
	i > 0
	is_object(seg)
	every s in array.slice(p, 0, i) {
		is_string(s)
	}
	k := _m_step_key(subj, seg)
}

_clause_cause(c) := "absent" if endswith(c, " is missing")

_clause_cause(c) := "null" if endswith(c, " is null")

_clause_cause(c) := "unusable" if {
	not endswith(c, " is missing")
	not endswith(c, " is null")
}

_tally_list_read(n, cause, row, ins, at) := [object.union(x, {"outcome": cause}) | some x in _key_base_entries(object.get(row, "ergo/key_bases", []), at); x.name == n] if {
	some b in object.get(row, "ergo/key_bases", [])
	b.input.name == n
} else := [object.union(object.remove(x, _input_stash_keys), {"outcome": cause, "value": _list_stop_value(row["ergo/subj"], p, cause, x.value)}) | some x in _anchored_all([_path_input(row["ergo/subj"], p)], at)] if {
	ps := _tally_list_paths(object.get(row, "ergo/check", null), n)
	count(ps) > 0
	p := ps[count(ps) - 1]
} else := [object.union(object.remove(x, _input_stash_keys), {"outcome": cause}) | some x in _anchored_all([_path_input(row["ergo/subj"], p)], at)] if {
	some p in _tally_keyed_list_paths(object.get(row, "ergo/check", null), row["ergo/subj"], n)
} else := [object.union(x, {"outcome": cause}) | some x in ins; x.name == n]

_list_stop_value(subj, p, cause, v) := vs[count(vs) - 1] if {
	cause == "unusable"
	v == null
	vs := [x | some i in numbers.range(1, count(p) - 1); x := _value_at(subj, array.slice(p, 0, i)); x != null]
	count(vs) > 0
} else := v

_tally_keyed_list_paths(check, subj, n) := [q |
	some side in _m_tally_parts(check)
	p := side[_basic_form(side)]
	is_array(p)
	some i, seg in p
	i > 0
	is_object(seg)
	k := _m_step_key(subj, seg)
	q := array.concat(array.slice(p, 0, i), [k])
	_m_aliased(_input_name(q)) == n
]

_tally_unkeyed_lists(check, subj) := _tally_unkeyed_list_names(check, subj) if contains(object.get(check, "expression", ""), " named by ")

else := set()

_tally_unkeyed_list_names(check, subj) := {_m_aliased(_input_name(p)) |
	some side in _m_tally_parts(check)
	p := side[_basic_form(side)]
	_tally_unkeyed_field(p, subj)
}

_tally_unkeyed_field(p, subj) if {
	is_array(p)
	some i, seg in p
	i > 0
	_field_step(seg)
	every s in array.slice(p, 0, i) {
		is_string(s)
	}
	not _m_step_key(subj, seg)
}

_tally_list_paths(c, n) := [q |
	some side in _m_tally_parts(c)
	path := side[_basic_form(side)]
	is_array(path)
	some i in numbers.range(1, count(path))
	q := array.slice(path, 0, i)
	_m_aliased(_input_name(q)) == n
]

_row_failures(row, at, where, _) := [_tallied_entry(
	_policy_entry(
		"assertion",
		fa.assertion,
		fa.cause,
		_sentence_inputs(where.check.checks[fa.at], fa, at, row["ergo/texts"][k]),
		[],
		row["ergo/texts"][k],
		[_assertion_at(where, null, fa.at)],
	),
	where.check.checks[fa.at], fa, at, where, row,
) |
	some k, fa in row.failed_assertions
] if _all_of_run(where.check)

_scoped_walk_outcome(c, req, subj, op) := o if {
	op != "for"
	_scoped(req)
	s := _scope_of(req, subj)
	r := _keyed_rooted(_for_said(_check_outcome(c, subj, "")), c, subj) with input as s
	o := object.union(r, {"inputs": _tagged(r.inputs, c, req, subj)}) with input as s
} else := _keyed_rooted(_for_said(_check_outcome(c, subj, "")), c, subj)

_tallied_entry(e, c, o, at, where, row) := object.union(e, {"inputs": x.inputs, "failures": x.failures, "message": x.message}) if {
	_walks(c)
	c.op != "for"
	_ = o
	raw := _scoped_walk_outcome(c, row["ergo/req"], row["ergo/subj"], where.check.op)
	raw.passed == false
	wrow := object.union(_anchored(raw, at), {"ergo/subj": row["ergo/subj"], "ergo/req": row["ergo/req"]})
	x := _walk_assertion_entry(wrow, at, object.union(where, {"check": object.union(c, {"expression": e.name}), "ats": {"": e.locations}}), _with_outcomes(wrow.inputs))
} else := object.union(e, {"inputs": [i | some i in e.inputs; not i.name in names; not _item_input(i, lists); not _tally_own_read(i, c, names, items)], "failures": array.concat(ls, items), "message": _tally_rest_of(e.message, names, texts)}) if {
	not _walks(c)
	count(_m_tally_parts(c)) > 0
	subj := row["ergo/subj"]
	mc := _sub_mcheck(where, c, row)
	lists := _tally_list_names(c) | _tally_keyed_list_names(c, subj)
	ls := _tally_list_entries({"message": e.message, "ergo/key_bases": object.get(o, "key_bases", []), "ergo/subj": subj, "ergo/req": row["ergo/req"], "ergo/check": mc}, at, lists, e.inputs)
	names := {x.name | some x in ls}
	items := _tally_item_parts(mc, subj, o.cause, at, e.message)
	texts := _tally_item_texts(mc, subj, o.cause, e.message)
	count(names) + count(items) > 0
} else := object.union(e, {"inputs": [i | some i in e.inputs; not _item_input(i, lists); not _tally_own_read(i, c, set(), [])]}) if {
	not _walks(c)
	count(_m_tally_parts(c)) > 0
	lists := _tally_list_names(c)
}

else := e

_row_failures(row, at, where, _) := [_policy_entry(
	"option",
	nm,
	_group_cause({row["ergo/outs"][i].line | some i, n in where.check.option_of; n == nm}),
	[],
	[_option_assertion(row, at, where, nm, i) | some i, n in where.check.option_of; n == nm; row["ergo/outs"][i].line != "satisfied"],
	"",
	[where.option_ats[nm]],
) |
	some nm in sort({n | some n in where.check.option_of})
] if _any_of_run(where.check)

_option_assertion(row, at, where, nm, i) := _tallied_entry(
	_policy_entry(
		"assertion",
		where.check.assertions[i],
		row["ergo/outs"][i].cause,
		_sentence_inputs(where.check.checks[i], row["ergo/outs"][i], at, row["ergo/texts"][i]),
		[],
		row["ergo/texts"][i],
		[_assertion_at(where, nm, count([j | some j, n in array.slice(where.check.option_of, 0, i); n == nm]))],
	),
	where.check.checks[i], row["ergo/outs"][i], at, where, row,
)

_row_failures(row, at, where, ins) := [_walk_assertion_entry(row, at, where, ins)] if {
	_walks(where.check)
	where.check.op != "for"
}

_walk_assertion_entry(row, at, where, ins) := _policy_entry(
	"assertion",
	where.check.expression,
	row.cause,
	_once(array.concat(array.concat(array.concat([ins[j] | some j, i in row.inputs; not _item_input(i, lists); not _walked_path_read(i, wname)], _key_flaw_entries(where.check.path)), _walk_cond_ref_entries(_walk_cond_refs(where.check), row.inputs)), _walk_param_entries(where.check, row.inputs))),
	array.concat([_keyed_walk_entry(x, where.check, row) | some x in entries], flaws),
	_tally_rest(concat("; ", [m | some m in _once(array.concat(object.get(row, "ergo/own", [row.message]), _walk_root_texts(row, clauses))); not m in {e.message | some e in kls}]), {e.name | some e in flaws}),
	[_assertion_at(where, null, 0)],
) if {
	clauses := object.get(row, "ergo/texts", [])
	lists := {_list_base(f.item) | some f in row.failed_items}
	kls := _key_list_parts(row, at)
	entries := array.concat(_walk_entries(row, _walk_owned_texts(row, clauses), at), kls)
	wname := _m_aliased(_walked_name(where.check.path))
	flaws := _walk_flaw_lists(row, at, where.check, entries)
}

_keyed_walk_entry(x, check, row) := object.union(x, {"inputs": reads}) if {
	x.kind == "item"
	x.failures == []
	some c in object.get(check, "whose", [])
	some s in _walk_sides_paths(c)
	is_array(s[0])
	_walk_outside(s[0])
	_item_keyed(s[0])
	every seg in check.path {
		is_string(seg)
	}
	some i in x.inputs
	i.name == _input_name(_as_subject_part(s[0]))
	_keyed_base_fine(s[0], row["ergo/subj"])
	n := to_number(trim_prefix(split(x.name, " of ")[0], "item "))
	ip := array.concat(check.path, [n - 1])
	reads := [r | some d in check.whose; some y in _walk_sides_paths(d); is_array(y[0]); some r in _keyed_walk_side_reads(x, y[0], ip)]
} else := x

_keyed_walk_side_reads(x, p, ip) := array.concat([i | some i in x.inputs; i.name == _input_name(_as_subject_part(p))], [_walk_item_read(x, [_fk(seg)], ip, true) | some seg in p; _item_key_step(seg)]) if {
	_walk_outside(p)
	_item_keyed(p)
} else := [] if _walk_outside(p)

else := [_walk_item_read(x, q, ip, false) | some q in _tally_item_paths(p)]

_walk_item_read(x, q, ip, key) := {"name": _input_name(array.concat(ip, q)), "value": _tally_read_value(x.value, q), "locations": [_pointer(x.locations[0], x.value, q)], "outcome": _walk_item_outcome(x.value, q, key)}

_walk_item_outcome(v, q, true) := _key_read_outcome(_probe(v, q))

_walk_item_outcome(v, q, false) := _tally_read_outcome(v, q, "usable")

_walk_flaw_lists(row, at, check, entries) := [_entry("list", n, cause, [object.union(object.remove(x, _input_stash_keys), {"value": _flaw_list_value(cause, x.value), "outcome": _key_list_outcome(cause)}) | some x in _anchored_all([_path_input(subj, p)], at)], [], c) |
	some h in object.get(row, "ergo/heads", [])
	is_string(h.name)
	n := _m_aliased(h.name)
	some k in numbers.range(1, count(check.path))
	p := array.slice(check.path, 0, k)
	every seg in p {
		_plain_or_field_step(seg)
	}
	_m_aliased(_input_name(p)) == n
	cause := h.cause
	c := _m_aliased(h.text)
] if {
	entries == []
	is_array(check.path)
	subj := _flaw_list_subject(row, check.path)
} else := []

_plain_or_field_step(seg) if is_string(seg)

_plain_or_field_step(seg) if _field_step(seg)

_flaw_list_subject(row, path) := row["ergo/subj"] if _ = path

else := null if path[0] in {"$$input", "$$params"}

_flaw_list_value(cause, _) := null if cause in _no_value_states

_flaw_list_value(cause, v) := v if not cause in _no_value_states

_walked_name(path) := _input_name(path) if is_array(path)

else := ""

_walked_path_read(i, name) if replace(i.name, "[]", "") == name

_walk_param_entries(check, inputs) := [x |
	some x in _with_outcomes(_once([_path_input(null, p) | walk(object.get(check, "check", {}), [_, p]); is_array(p); count(p) > 0; p[0] == "$$params"]))
	not x.name in {i.name | some i in inputs}
]

_check_key_ref_entries(check, inputs, cause, said) := _check_key_refs(check, inputs) if {
	cause in _value_fault_causes
} else := [x | some x in _check_key_refs(check, inputs); contains(said, _for_key_text(x, x.outcome))] if {
	cause == "not_an_object"
} else := []

_check_key_refs(check, inputs) := [x |
	some x in _key_flaw_entries(_once([seg |
		walk(check, [_, p])
		is_array(p)
		count(p) > 1
		is_string(p[0])
		some k, seg in p
		k > 0
		_is_ref(seg)
	]))
	not x.name in {i.name | some i in inputs}
]

_key_base_entries(bases, at) := _anchored_all([object.union(object.remove(x.input, _input_stash_keys), {"outcome": _key_list_outcome(x.cause)}) | some x in bases], at)

_sentence_inputs(c, o, at, said) := _with_key_bases(array.concat(array.concat(_with_outcomes(_anchored_inputs(o.inputs, at)), _sentence_ref_entries(c, o.inputs)), _sentence_key_entries(c, o, said)), o.key_bases, at)

_with_key_bases(ins, bases, at) := array.concat(ins, [x | some x in _key_base_entries(bases, at); not x.name in {i.name | some i in ins}])

_sentence_key_entries(c, o, said) := _check_key_ref_entries(c, o.inputs, o.cause, said) if not _walks(c)

else := []

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

_unitemed(name) := p[1] if p := _item_parts(name)

else := name

_walk_entries(_, [], _) := []

_walk_owned_texts(row, clauses) := [_walk_owned_text(row, k, c) | some k, c in clauses]

_walk_owned_text(row, k, c) := "" if _walk_root_clause(row, k, c)

else := c.text

_walk_root_texts(row, clauses) := [c.text | some k, c in clauses; _walk_root_clause(row, k, c)]

_walk_root_clause(row, k, c) if {
	c.text != ""
	c.kind != "item"
	_walk_kind(row.failed_items[k].item) == "item"
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

_level_names(name, m) := array.concat(_outer_level_names(b, m), [concat("", [p[0], " of ", _level_field(b.fields[m])])]) if {
	p := _item_parts(name)
	b := _level_bits(p[1], m)
}

_level_names(name, m) := array.concat(_outer_level_names(b, m), [b.fields[m]]) if {
	_walk_kind(name) == "list"
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
		[_said_missing(r, texts[k]) | some k, f in row.failed_items; f.item == name; some r in _walk_reads(f, name)],
		[],
		concat("; ", _once([_entry_text(texts[k], name) | some k, f in row.failed_items; f.item == name; texts[k] != ""])),
	),
	_item_seen(row, name, at),
)

_said_missing(r, t) := object.union(r, {"outcome": "absent"}) if {
	r.outcome == "null"
	endswith(t, " is missing")
} else := r

_walk_reads(f, name) := [_item_read(f)] if _reads_inside(f, name)

else := [object.union(_item_read(f), {"name": n})] if n := f["ergo/read"]

else := []

_reads_inside(f, name) if f.path != name

_reads_inside(_, name) if _walk_kind(name) == "list"

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

_item_read(f) := {"name": f.path, "value": f.value, "locations": f.locations, "outcome": object.get(f, "ergo/read_outcome", _item_outcome(f.cause, f.value))}

_item_outcome(cause, value) := cause if cause in _failed_read_states

else := "usable" if value != null

else := "null"

_sorted_item_text(texts, name) := concat("; ", [_entry_text(m, name) | some m in texts; startswith(m, concat("", [name, ": "]))]) if {
	some m in texts
	startswith(m, concat("", [name, ": "]))
} else := concat("; ", texts)

_entry_text(text, name) := substring(text, count(name) + 2, -1) if startswith(text, concat("", [name, ": "]))

else := text

_where(req_name, name, check) := object.union(w, {
	"ats": object.union({"": a | a := _assertion_ats(w, null)}, {nm: a | some nm in _option_names(check); a := _assertion_ats(w, nm)}),
	"option_ats": {nm: _option_at(w, nm) | some nm in _option_names(check)},
	"unfit": _unfit_refs(check),
	"text_lists": _text_list_names(check),
}) if w := {"check": check, "req": req_name, "name": name}

_text_list_names(check) := {n |
	walk(check, [_, x])
	is_object(x)
	x.ignoring
	n := _text_list_name(x)
}

_text_list_name(x) := _ref_label(x.values.ref) if {
	x.op in _membership_ops
	_is_ref(x.values)
}

_text_list_name(x) := _input_name(_as_subject_part(x.right)) if {
	x.op == "compare"
	x.cmp in _membership_ops
	is_array(x.right)
}

_option_names(check) := {n | some n in check.option_of}

_assertion_ats(where, option) := [concat("", [x]) | some x in _lines_at(lines, n)] if {
	lines := _written_lines(where, option)
	n := _assertion_count(where, option)
}

_assertion_at(where, null, k) := where.ats[""][k]

_assertion_at(where, option, k) := where.ats[option][k] if option != null

_condition_of(req, name, c) := object.union({"expression": e | e := _expression_of(c)}, object.union({"at": a | a := _condition_at(req, name)}, {"unfit": _unfit_refs(c), "text_lists": _text_list_names(c)}))

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

_parted_applies(row, _, _, _, _, _) := _passed_row(row) if row.passed == true

_parted_applies(row, at, evals, req, conds, subj) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": ins,
	"failures": _applies_entries(row, at, evals, req, conds, ins, subj),
}) if {
	row.passed == false
	ins := _applies_outcomes(_with_outcomes(row.inputs), row, req)
}

_applies_outcomes(ins, row, req) := _tally_outcomes(ins, row, c) if {
	not "failed_items" in object.keys(row)
	cs := [x | some _, x in _applies_to_of(req)]
	count(cs) == 1
	c := cs[0]
} else := ins

_applies_entries(row, at, evals, req, conds, ins, subj) := [_walk_assertion_entry(
	object.union(row, {"cause": e.assertion_cause, "ergo/own": object.get(e, "ergo/own", [row.message]), "ergo/texts": object.get(e, "ergo/texts", []), "ergo/heads": object.get(e, "ergo/heads", [])}),
	at,
	{"check": object.union(_applies_to_of(req)[name], {"expression": conds[name].expression}), "ats": {"": [conds[name].at]}, "subj": subj},
	ins,
)] if {
	count(evals) == 1
	some name, e in evals
	"failed_items" in object.keys(row)
}

_applies_entries(row, at, evals, req, conds, ins, subj) := [_policy_entry(
	"assertion",
	conds[name].expression,
	e.assertion_cause,
	[i | some i in ins; not i.name in names; not _item_input(i, lists); not _tally_own_read(i, c, names, items)],
	array.concat(ls, items),
	_tally_rest_of(row.message, names, texts),
	[conds[name].at],
)] if {
	count(evals) == 1
	some name, e in evals
	not "failed_items" in object.keys(row)
	c := _applies_to_of(req)[name]
	lists := _tally_list_names(c)
	ls := _subj_tally_lists(row, at, lists, ins, subj, c)
	names := {x.name | some x in ls}
	items := _gated_tally_parts(c, conds[name].expression, subj, e.assertion_cause, at, row.message)
	texts := _gated_tally_texts(c, conds[name].expression, subj, e.assertion_cause, row.message)
}

_applies_entries(_, at, evals, req, conds, _, subj) := [_applies_cond_entry(evals[name], _applies_to_of(req)[name], conds[name], texts[k], at, subj) |
	some k, name in failed
] if {
	count(evals) > 1
	failed := [n | some n in _applies_to_names(req); evals[n].assertion_cause != "satisfied"]
	texts := [evals[n].message | some n in failed]
}

_applies_cond_entry(e, c, cond, text, at, subj) := _walk_assertion_entry(
	{"inputs": _anchored_all(e.inputs, at), "failed_items": [_anchored_failed(f, at) | some f in e.failed_items], "message": text, "cause": e.assertion_cause, "ergo/own": object.get(e, "ergo/own", [text]), "ergo/texts": object.get(e, "ergo/texts", []), "ergo/heads": object.get(e, "ergo/heads", [])},
	at,
	{"check": object.union(c, {"expression": cond.expression}), "ats": {"": [cond.at]}, "subj": subj},
	_with_outcomes(_anchored_all(e.inputs, at)),
) if {
	"failed_items" in object.keys(e)
	_walks(c)
} else := _policy_entry(
	"assertion",
	cond.expression,
	e.assertion_cause,
	[i | some i in _with_outcomes(_anchored_inputs(e.inputs, at)); not _item_input(i, _tally_list_names(c)); not i.name in names; not _tally_own_read(i, c, names, items)],
	array.concat(ls, items),
	_tally_rest_of(text, names, texts),
	[cond.at],
) if {
	lists := _tally_list_names(c)
	ls := _subj_tally_lists({"message": text}, at, lists, _with_outcomes(_anchored_inputs(e.inputs, at)), subj, c)
	names := {x.name | some x in ls}
	items := _gated_tally_parts(c, cond.expression, subj, e.assertion_cause, at, text)
	texts := _gated_tally_texts(c, cond.expression, subj, e.assertion_cause, text)
}

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

_parted_in(raw, at, where) := _said_outcomes(_parted_in_of(raw, at, where))

_parted_in_of(raw, at, where) := p if {
	raw.passed == false
	count(where.unfit) + count(where.text_lists) > 0
	p := _parted(raw, at, where) with data.ergo_unfit as where.unfit with data.ergo_text_lists as where.text_lists
} else := _parted(raw, at, where)

_said_outcomes(row) := row if row.passed == true

else := _said_outcomes_of(_unled_dropped(row))

_said_outcomes_of(row) := object.union(row, {
	"inputs": [_unfit_on_entry(i, unfit) | some i in _said_unusable(row.inputs, row.message)],
	"failures": fs,
}) if {
	fs := [_said_entry(e) | some e in row.failures]
	unfit := _entries_unfit(fs)
}

_entries_unfit(entries) := {[i.name, i.value, i.locations] |
	some e in entries
	some a in _entry_assertions(e)
	some i in a.inputs
	i.outcome == "unusable"
}

_entry_assertions(e) := [e] if e.kind == "assertion"

else := [a | some a in e.failures; a.kind == "assertion"] if e.kind == "option"

else := []

_unfit_on_entry(i, unfit) := object.union(i, {"outcome": "unusable"}) if {
	i.outcome == "usable"
	[i.name, i.value, i.locations] in unfit
} else := i

_unled_dropped(row) := object.union(row, {
	"message": concat("; ", [x | some x in ps; not endswith(x, ": ")]),
	"failures": [e | some e in row.failures; not _blank_item(e)],
}) if {
	_unled_said(row.message)
	ps := _m_top_split(row.message, "; ")
	some x in ps
	endswith(x, ": ")
} else := row

_unled_said(m) if contains(m, ": ; ")

_unled_said(m) if endswith(m, ": ")

_blank_item(e) if {
	e.kind == "item"
	e.message == ""
	e.failures == []
}

_said_entry(e) := object.union(e, {"failures": [_said_assertion(f) | some f in e.failures]}) if e.kind == "option"

else := _said_assertion(e)

_said_assertion(e) := object.union(e, {"inputs": _said_unusable(e.inputs, e.message)}) if e.kind == "assertion"

else := e

_said_unusable(ins, message) := ins if not contains(message, ", which isn't ")

else := [_said_input(i, names) | some i in ins] if {
	names := {_m_clause_name(c) | some p in _m_top_split(message, "; "); some c in _m_top_split(p, ", and "); _m_isnt_clause(c)}
}

_m_isnt_clause(c) if {
	ps := split(c, ", which isn't ")
	count(ps) > 1
	some k in numbers.range(1, count(ps) - 1)
	_clause_quotes_shut(concat(", which isn't ", array.slice(ps, 0, k)))
}

_said_input(i, names) := object.union(i, {"outcome": "unusable"}) if {
	i.outcome == "usable"
	i.name in names
} else := i

_unfit_refs(check) := {_ref_label(r) | some r in _listed_refs(check); _ref_use(check, r) == "unusable"}

_parted_applies_in(raw, at, evals, req, conds, subj) := p if {
	raw.passed == false
	unfit := {u | some n, _ in evals; some u in conds[n].unfit}
	lists := {u | some n, _ in evals; some u in conds[n].text_lists}
	count(unfit) + count(lists) > 0
	p := _parted_applies(raw, at, evals, req, conds, subj) with data.ergo_unfit as unfit with data.ergo_text_lists as lists
} else := _parted_applies(raw, at, evals, req, conds, subj)

_tally_item_parts(c, subj, cause, at, m) := _nested_items(_tally_one_per_item(array.concat(xs, _tally_keyed_extra(c, subj, at, m, xs)))) if {
	xs := _tally_item_records(c, subj, cause, at, m)
}

_tally_one_per_item(es) := [_tally_joined_item(e, [y | some y in es; _tally_same_item(y, e)]) |
	some k, e in es
	not _tally_item_before(es, k, e)
]

_tally_item_before(es, k, e) if {
	some j, y in es
	j < k
	_tally_same_item(y, e)
}

_tally_same_item(a, b) if {
	a.kind == "item"
	object.remove(a, ["message", "cause"]) == object.remove(b, ["message", "cause"])
}

_tally_joined_item(e, same) := e if count(same) < 2

else := object.union(e, {"message": concat("; ", _once([y.message | some y in same; y.message != ""])), "cause": _worst_of({y.cause | some y in same})})

_tally_keyed_extra(c, subj, at, m, xs) := [x |
	some f in _tally_keyed_found(c, subj, m)
	not f.lead in {y.name | some y in xs}
	x := _tally_leveled(_tally_item_entry(f.e, _tally_clause_cause(_m_after_lead(f.lead, f.clause), "unusable"), f.clause, f.side, f.w, f.roots, subj), f.e.i, f.w, at)
]

_tally_keyed_found(c, subj, m) := [{"side": side, "w": w, "roots": roots, "e": e, "lead": lead, "clause": clause} |
	is_object(c)
	mc := object.union(_m_with_sides(_m_walked(c, subj)), {"ergo/row": true})
	some side in _m_tally_parts(mc)
	_tally_outside_keyed(side, subj)
	f := _basic_form(side)
	every seg in side[f] {
		is_string(seg)
	}
	w := _tally_walk(subj, side)
	roots := _dotted_roots([side[f]])
	some clause in _m_top_split(m, "; ")
	lead := _m_lead_of(clause)
	some e in w.items
	_m_item_name(e.i, roots) == lead
]

_tally_outside_keyed(side, subj) if {
	some d in object.get(side, "whose", [])
	some s in _walk_sides_paths(d)
	is_array(s[0])
	_walk_outside(s[0])
	_item_keyed(s[0])
	_keyed_base_fine(s[0], subj)
}

_tally_item_records(c, subj, cause, at, m) := [x |
	is_object(c)
	mc := object.union(_m_with_sides(_m_walked(c, subj)), {"ergo/row": true})
	some side in _m_tally_parts(mc)
	f := _basic_form(side)
	w := _tally_walk(subj, side)
	roots := _dotted_roots([side[f]])
	rs := _m_tally_records(subj, side, cause)
	some r0 in rs
	count(r0) == 3
	not _tally_root_said(r0, rs)
	r := _tally_unrooted(r0, m)
	r != null
	_tally_said_in(_m_aliased(r[1]), m)
	x := _tally_record_entry(r, side, w, roots, at, subj)
]

_tally_unrooted(r, m) := _tally_kept(r, lead, ps, [p | some p in ps; not p in tops]) if {
	head := _m_lead_of(r[1])
	head != ""
	lead := concat("", [head, ": "])
	startswith(r[1], lead)
	ps := _m_top_split(substring(r[1], count(lead), -1), "; ")
	tops := {t | some t in _m_top_split(m, "; ")}
} else := r

_tally_kept(r, lead, ps, kept) := r if count(kept) == count(ps)

else := null if kept == []

else := [_worst_of({_tally_clause_cause(c, r[0]) | some c in kept}), concat("", [lead, concat("; ", kept)]), r[2]]

_tally_clause_cause(c, state) := _tally_word_cause(c, _m_src_cause(state))

_tally_word_cause(c, _) := "absent" if endswith(c, " is missing")

_tally_word_cause(c, _) := "null" if endswith(c, " is null")

_tally_word_cause(c, cause) := cause if {
	not endswith(c, " is missing")
	not endswith(c, " is null")
	not cause in {"absent", "null"}
}

_tally_word_cause(c, cause) := "unusable" if {
	not endswith(c, " is missing")
	not endswith(c, " is null")
	cause in {"absent", "null"}
}

_tally_record_entry([state, text, src], side, w, roots, at, subj) := _tally_leveled(_tally_item_entry(e, _m_src_cause(state), text, side, w, roots, subj), e.i, w, at) if {
	e := src.item
	_m_positions(e.i) != []
}

_tally_record_entry([state, text, src], _, w, roots, at, _) := _tally_leveled(object.union(_entry("item", _m_item_name(e.i, roots), _m_src_cause(state), [_tally_key_read(src, w)], [], text), {"value": e.iv, "locations": [_item_at(w, e)]}), e.i, w, at) if {
	e := src.key
	_m_positions(e.i) != []
}

_tally_record_entry([state, text, src], _, w, roots, at, _) := _tally_leveled(_entry("list", _m_item_name(x.path, roots), x.cause, [{"name": _input_name(x.path), "value": x.value, "locations": [x.at], "outcome": x.cause}], [], text), x.path, w, at) if {
	x := src.fail
	_m_positions(x.path) != []
	_ = state
}

_tally_key_read(src, w) := {"name": _input_name(array.concat(src.key.c, src.flaw.prefix)), "value": _key_list_value(src.flaw.value), "locations": [_item_read_at(w, src.key, array.concat(object.get(src.key, "r", []), src.flaw.prefix))], "outcome": _key_flaw_outcome(src.flaw, src.steps)}

_tally_item_entry(e, cause, text, side, w, roots, subj) := object.union(
	_entry("item", _m_item_name(e.i, roots), cause, _tally_item_reads(e, cause, side, w, text, subj), [], text),
	{"value": e.iv, "locations": [_item_at(w, e)]},
)

_tally_item_reads(e, cause, side, w, text, subj) := [{"name": _input_name(array.concat(e.c, ps[0])), "value": null, "locations": [_item_read_at(w, e, e.r)], "outcome": "not_an_object"}] if {
	e.r != []
	not _read_state(e.iv, e.r) in {"absent", "unusable"}
	not is_object(e.v)
	ps := _once([p | some c in object.get(side, "whose", []); some x in _walk_sides_paths(c); is_array(x[0]); some p in _tally_item_paths(x[0]); p != []; every step in p { is_string(step) }])
	ps != []
	_ = [cause, text, subj]
} else := [{"name": _input_name(e.c), "value": _walk_value(e.v, e, w), "locations": [_item_read_at(w, e, e.r)], "outcome": _tally_read_outcome(e.iv, e.r, cause)}] if {
	e.r != []
} else := rs if {
	rs := _keyed_item_reads(e, side, w, subj)
	rs != []
}

else := [{"name": _input_name(array.concat(e.i, p)), "value": _tally_read_value(e.iv, p), "locations": [_item_read_at(w, e, p)], "outcome": _tally_read_outcome(e.iv, p, _tally_said_cause(cause, ps, p, text))} |
	some p in ps
	not _tally_path_skipped(e, p, side)
] if {
	ps := _once([p | some c in object.get(side, "whose", []); some x in _walk_sides_paths(c); is_array(x[0]); some p in _tally_item_paths(x[0])])
	ps != []
	_ = text
} else := [{"name": _item_input_name(e.i), "value": e.iv, "locations": [_item_read_at(w, e, [])], "outcome": _tally_read_outcome(e.iv, [], cause)}]

_keyed_item_reads(e, side, w, subj) := [r |
	some c in object.get(side, "whose", [])
	some x in _walk_sides_paths(c)
	is_array(x[0])
	some r in _keyed_side_reads(e, x[0], w, subj)
] if {
	some c in object.get(side, "whose", [])
	some x in _walk_sides_paths(c)
	is_array(x[0])
	_walk_outside(x[0])
	_item_keyed(x[0])
	_keyed_base_fine(x[0], subj)
}

_keyed_base_fine(p, subj) if {
	shown := _as_subject_part(p)
	i := min({j | some j, seg in shown; _item_key_step(seg)})
	is_object(_value_at(subj, array.slice(shown, 0, i)))
}

_keyed_side_reads(e, p, w, subj) := array.concat([_keyed_outside_read(e, p, subj)], [_key_step_read(e, seg, w) | some seg in p; _item_key_step(seg)]) if {
	_walk_outside(p)
	_item_keyed(p)
} else := [] if _walk_outside(p)

else := [_plain_item_read_of(e, q, w) | some q in _tally_item_paths(p)]

_plain_item_read_of(e, q, w) := {"name": _input_name(array.concat(e.i, q)), "value": _tally_read_value(e.iv, q), "locations": [_item_read_at(w, e, q)], "outcome": _tally_read_outcome(e.iv, q, "usable")}

_key_step_read(e, seg, w) := {"name": _input_name(array.concat(e.i, [_fk(seg)])), "value": _tally_read_value(e.iv, [_fk(seg)]), "locations": [_item_read_at(w, e, [_fk(seg)])], "outcome": _key_read_outcome(_probe(e.iv, [_fk(seg)]))}

_key_read_outcome(v) := "usable" if is_string(v)

else := _key_state(v)

_keyed_outside_read(e, p, subj) := {"name": _input_name(_as_subject_part(p)), "value": null, "locations": [_unread_pointer(subj, base)], "outcome": _key_read_outcome(bad[0])} if {
	shown := _as_subject_part(p)
	bad := [v | some seg in shown; _item_key_step(seg); v := _probe(e.iv, [_fk(seg)]); not is_string(v)]
	bad != []
	i := min({j | some j, seg in shown; _item_key_step(seg)})
	base := array.slice(shown, 0, i)
} else := {"name": _input_name(_as_subject_part(p)), "value": _tally_read_value(_start_of(subj, resolved), array.slice(resolved, 1, count(resolved))), "locations": [_unread_pointer(subj, resolved)], "outcome": _outcome_word(_read_state(subj, resolved))} if {
	resolved := [_keyed_step(e, seg) | some seg in _as_subject_part(p)]
}

_keyed_step(e, seg) := _probe(e.iv, [_fk(seg)]) if _item_key_step(seg)

else := seg

_tally_item_paths(p) := array.concat([p | not _walk_outside(p)], [[_fk(seg)] | some seg in p; _item_key_step(seg)])

_item_key_step(seg) if {
	is_object(seg)
	object.keys(seg) == {"named_by_field"}
	not _from_root(seg)
}

_tally_read_value(v, p) := null if _probe(v, p) == _absent

else := _probe(v, p)

_tally_read_outcome(v, p, cause) := _outcome_word(s) if {
	s := _read_state(v, p)
	s != "value"
} else := _tally_value_outcome(cause)

_tally_path_skipped(e, p, side) if {
	some c in object.get(side, "whose", [])
	qs := [q | some x in _walk_sides_paths(c); is_array(x[0]); some q in _tally_item_paths(x[0])]
	some i, q in qs
	q == p
	some j, r in qs
	j < i
	_read_state(e.iv, r) in {"absent", "null", "not_an_object"}
}

_tally_said_cause(cause, ps, p, text) := cause if {
	count(ps) == 1
	_ = p
	_ = text
}

else := cause if {
	cause == "unusable"
	some c in _m_top_split(text, "; ")
	some d in _m_top_split(c, ", and ")
	_m_isnt_clause(d)
	_m_clause_name(_m_after_lead(_m_lead_of(d), d)) == _input_name(p)
} else := "usable"

_tally_value_outcome("unusable") := "unusable"

_tally_value_outcome(cause) := "usable" if cause != "unusable"

_tally_leveled(e, path, w, at) := object.union(e, object.union(
	{
		"name": names[count(names) - 1],
		"message": _tally_level_text(e.message, names),
		"inputs": _anchored_all(e.inputs, at),
	},
	_levels_key([_tally_level(path, idx[j], names[j], w, at) | some j, _ in array.slice(names, 0, count(names) - 1)]),
)) if {
	e.kind == "list"
	names := _m_quote_split(e.name, ": ")
	idx := [j | some j, step in path; is_number(step)]
} else := object.union(e, object.union(
	{
		"name": names[count(names) - 1],
		"message": _tally_level_text(e.message, names),
		"locations": _anchored_all([e], at)[0].locations,
		"inputs": _anchored_all(e.inputs, at),
	},
	_levels_key([_tally_level(path, idx[j], names[j], w, at) | some j, _ in array.slice(names, 0, count(names) - 1)]),
)) if {
	names := _m_quote_split(e.name, ": ")
	idx := [j | some j, step in path; is_number(step)]
}

_levels_key([]) := {}

_levels_key(lv) := {"ergo/levels": lv} if lv != []

_tally_level(path, k, name, w, at) := {"name": name, "value": _tally_read_value(w.trail[0].v, keys), "locations": _anchored_all([{"locations": [_pointer(w.trail[0].a, w.trail[0].v, keys)]}], at)[0].locations} if {
	keys := array.slice(path, count(w.trail[0].c), k + 1)
}

_tally_level_text(text, names) := _entry_text(rest, names[count(names) - 1]) if {
	count(names) > 1
	p := concat("", [concat(": ", array.slice(names, 0, count(names) - 1)), ": "])
	startswith(text, p)
	rest := substring(text, count(p), -1)
} else := _entry_text(text, names[0])

_item_input_name(p) := _with_dot(_steps_name(p), _dot_kept(p)) if _has_parents

else := _steps_name(p)

_with_row_part(x, ins) := object.union(x, {"part": ps[0]}) if {
	not x.part
	ps := [i.part | some i in ins; i.name == x.name; i.part]
	count(ps) > 0
} else := x
