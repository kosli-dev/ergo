package ergo

import rego.v1

_row_stash_keys := ["failed_items", "failed_assertions", "ergo/texts", "ergo/own", "ergo/outs"]

_parted(row, _, _) := _passed_row(row) if row.passed == true

_parted(row, _, where) := object.union(row, {"inputs": _with_outcomes(row.inputs), "failed_items": [_for_item_clean(f) | some f in row.failed_items]}) if {
	row.passed == false
	where.check.op == "for"
}

_for_item_clean(f) := object.union(f, {"failed_assertions": [_for_line_clean(l) | some l in f.failed_assertions]}) if "failed_assertions" in object.keys(f)

else := f

_for_line_clean(l) := object.union(l, object.union({"inputs": _unstashed_inputs(l.inputs) | "inputs" in object.keys(l)}, {"items": [object.union(x, {"inputs": _unstashed_inputs(x.inputs)}) | some x in l.items] | "items" in object.keys(l)}))

_unstashed_inputs(inputs) := [object.remove(i, _input_stash_keys) | some i in inputs]

_parted(row, at, where) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": _with_outcomes(row.inputs),
	"failures": _row_failures(row, at, where),
}) if {
	row.passed == false
	where.check.op != "for"
}

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

_row_failures(row, _, where) := [_policy_entry("assertion", where.check.expression, row.cause, _with_outcomes(row.inputs), [], row.message, [_assertion_at(where, null, 0)])] if {
	not _walks(where.check)
	not _all_of_run(where.check)
	not _any_of_run(where.check)
	not where.check.op == "for"
}

_row_failures(row, at, where) := [_policy_entry(
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

_row_failures(row, at, where) := [_policy_entry(
	"option",
	nm,
	_group_cause({row["ergo/outs"][i].line | some i, n in where.check.option_of; n == nm}),
	[],
	[_option_assertion(row, at, where, nm, i) | some i, n in where.check.option_of; n == nm; row["ergo/outs"][i].line != "satisfied"],
	concat(", and ", [t | some i, n in where.check.option_of; n == nm; t := row["ergo/texts"][i]; t != ""]),
	[_option_at(where, nm)],
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

_row_failures(row, at, where) := [_policy_entry(
	"assertion",
	where.check.expression,
	row.cause,
	_with_outcomes([i | some i in row.inputs; not _item_input(i, lists)]),
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

_assertion_at(where, option, k) := concat("", [_lines_at(where, option, lines, n)[k]]) if {
	lines := _written_lines(where, option)
	n := _assertion_count(where, option)
}

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

_lines_at(_, _, lines, n) := [lines.at | some _ in numbers.range(1, n)] if {
	not lines.list
	n == 1
}

_lines_at(_, _, lines, n) := [concat("", [lines.at, "#", format_int(k, 10)]) | some k in numbers.range(1, n)] if {
	not lines.list
	n > 1
}

_lines_at(_, _, lines, n) := [_joined(lines.at, [j]) | some j, _ in lines.lines] if {
	lines.list
	count(lines.lines) == n
}

_lines_at(_, _, lines, n) := [_line_mark(lines.at, j, counts[j], k) | some j, _ in lines.lines; some k in numbers.range(1, counts[j])] if {
	lines.list
	count(lines.lines) != n
	counts := [count(object.get(_sentence(line), "assertions", [line])) | some line in lines.lines]
}

_line_mark(at, j, 1, _) := _joined(at, [j])

_line_mark(at, j, c, k) := concat("", [_joined(at, [j]), "#", format_int(k, 10)]) if c > 1

_parted_applies(row, _, _, _) := _passed_row(row) if row.passed == true

_parted_applies(row, at, evals, req) := object.union(object.remove(row, _row_stash_keys), {
	"inputs": _with_outcomes(row.inputs),
	"failures": _applies_entries(row, at, evals, req),
}) if row.passed == false

_applies_entries(row, at, evals, req) := [_policy_entry(
	"assertion",
	_expression_of(_applies_to_of(req)[name]),
	e.assertion_cause,
	_with_outcomes([i | some i in row.inputs; not _item_input(i, lists)]),
	_walk_entries(row, texts, at),
	concat("; ", _once(object.get(e, "ergo/own", [row.message]))),
	[_condition_at(req, name)],
)] if {
	count(evals) == 1
	some name, e in evals
	"failed_items" in object.keys(row)
	texts := object.get(e, "ergo/texts", [])
	lists := {_list_base(f.item) | some f in row.failed_items}
}

_applies_entries(row, _, evals, req) := [_policy_entry(
	"assertion",
	_expression_of(_applies_to_of(req)[name]),
	e.assertion_cause,
	_with_outcomes(row.inputs),
	[],
	row.message,
	[_condition_at(req, name)],
)] if {
	count(evals) == 1
	some name, e in evals
	not "failed_items" in object.keys(row)
}

_applies_entries(_, at, evals, req) := [_policy_entry(
	"assertion",
	_expression_of(_applies_to_of(req)[name]),
	evals[name].assertion_cause,
	_with_outcomes(_anchored_inputs(evals[name].inputs, at)),
	[],
	_first_text(texts, k),
	[_condition_at(req, name)],
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
