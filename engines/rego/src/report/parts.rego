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

_for_failures(row, at, where, t) := array.concat(
	[e | some i, a in where.check.assertions; e := _for_assertion_entry(row, at, where, t, i, a)],
	[e | some kind in ["list", "item"]; some e in _for_row_breaks(row, t); e.kind == kind],
)

_for_row_breaks(row, t) := array.concat(
	[_entry(w[0], w[1], row.cause, [], [], w[2]) | some w in t.walk],
	[e | some k, f in row.failed_items; rec := t.items[k]; "walk" in object.keys(rec); e := _for_walk_entry(f, rec)],
)

_for_assertion_entry(row, at, where, t, i, a) := _policy_entry(
	"assertion",
	a,
	_worst_or_value(causes),
	_once(array.concat(
		[x | some [_, _, l] in lines; some x in _with_outcomes(object.get(l, "inputs", [])); not _alias_named(x.name, aliases)],
		[x | some l in t.free; l.assertion == a; some x in _with_outcomes(_anchored_inputs(l.inputs, at))],
	)),
	items,
	t.said[i],
	[_assertion_at(where, null, i)],
) if {
	i == min({j | some j, b in where.check.assertions; b == a})
	aliases := {item.as | some item in where.check.items}
	lines := [[k, j, l] | some k, f in row.failed_items; "lines" in object.keys(t.items[k]); some j, l in f.failed_assertions; l.assertion == a]
	items := [_for_item_entry(row.failed_items[k], l, t.items[k].lines[j], aliases) | some [k, j, l] in lines; _for_item_said(t.items[k].lines[j])]
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

_alias_named(name, aliases) if {
	some a in aliases
	_alias_name_start(name, a)
}

_alias_name_start(name, a) if name == a

_alias_name_start(name, a) if startswith(name, concat("", [a, "."]))

_alias_name_start(name, a) if startswith(name, concat("", [a, "["]))

_for_item_entry(f, l, x, aliases) := object.union(
	_entry(
		_walk_kind(f.item),
		f.item,
		l.cause,
		[y | some y in _with_outcomes(object.get(l, "inputs", [])); _alias_named(y.name, aliases)],
		[object.union(_entry(_walk_kind(y.item), y.item, y.cause, _with_outcomes(y.inputs), [], x.xs[n]), object.filter(y, {"value", "locations"})) | some n, y in object.get(l, "items", []); x.xs[n] != ""],
		x.m,
	),
	{"value": f.value, "locations": f.locations},
)

_for_walk_entry(f, rec) := object.union(
	_entry(_walk_kind(f.item), f.item, f.cause, [], [_for_inner_entry(x, rec.inner[n]) | some n, x in f.failed_items; rec.inner[n] != []], ""),
	{"value": f.value, "locations": f.locations},
) if rec.inner != []

else := object.union(
	_entry(_walk_kind(f.item), f.item, f.cause, [_item_read(f) | _walk_kind(f.item) == "list"], [], concat("; ", [_entry_text(m, f.item) | some m in rec.walk])),
	{"value": f.value, "locations": f.locations},
) if {
	rec.walk != []
	_walk_kind(f.item) == "item"
} else := _entry("list", f.item, f.cause, [_item_read(f)], [], concat("; ", rec.walk)) if rec.walk != []

_for_inner_entry(x, ts) := object.union(_entry("item", x.item, x.cause, [], [], concat("; ", ts)), {"value": x.value, "locations": x.locations}) if _walk_kind(x.item) == "item"

else := _entry("list", x.item, x.cause, [_item_read(x)], [], concat("; ", ts))

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

_row_failures(row, _, where, ins) := [_policy_entry("assertion", where.check.expression, row.cause, ins, [], row.message, [_assertion_at(where, null, 0)])] if {
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
	_with_outcomes(_anchored_inputs(fa.inputs, at)),
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
	concat(", and ", [t | some i, n in where.check.option_of; n == nm; t := row["ergo/texts"][i]; t != ""]),
	[where.option_ats[nm]],
) |
	some nm in sort({n | some n in where.check.option_of})
] if _any_of_run(where.check)

_option_assertion(row, at, where, nm, i) := _policy_entry(
	"assertion",
	where.check.assertions[i],
	row["ergo/outs"][i].cause,
	_with_outcomes(_anchored_inputs(row["ergo/outs"][i].inputs, at)),
	[],
	row["ergo/texts"][i],
	[_assertion_at(where, nm, count([j | some j, n in array.slice(where.check.option_of, 0, i); n == nm]))],
)

_row_failures(row, at, where, ins) := [_policy_entry(
	"assertion",
	where.check.expression,
	row.cause,
	[ins[j] | some j, i in row.inputs; not _item_input(i, lists)],
	_walk_entries(row, texts, at),
	concat("; ", _once(object.get(row, "ergo/own", [row.message]))),
	[_assertion_at(where, null, 0)],
)] if {
	_walks(where.check)
	where.check.op != "for"
	texts := object.get(row, "ergo/texts", [])
	lists := {_list_base(f.item) | some f in row.failed_items}
}

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

_walk_entries(row, texts, at) := [_walk_entry(row, texts, name, at) |
	some k, f in row.failed_items
	name := f.item
	not name in [g.item | some g in array.slice(row.failed_items, 0, k)]
] if texts != []

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
	_walk_entries(row, texts, at),
	concat("; ", _once(object.get(e, "ergo/own", [row.message]))),
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
	_first_text(texts, k),
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
