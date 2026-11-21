package ergo

import rego.v1

_check_outcome(check, subj, flaw) := object.union(
	{
		"inputs": _row_inputs(subj, check),
		"passed": _check_passed(check, subj, flaw),
		"cause": cause,
	},
	_key_base_stash(check, subj, cause),
) if {
	not _all_of_run(check)
	not _any_of_run(check)
	not _walk_run(check)
	not _derived_once(check)
	cause := _row_cause(check, subj, flaw)
}

_check_outcome(check, subj, flaw) := object.union(
	{
		"inputs": _with_key_fields(subj, check, e.inputs),
		"passed": _once_passed(flaw, e),
		"cause": _once_cause(flaw, e),
	},
	_key_base_stash(check, subj, e.cause),
) if {
	_derived_once(check)
	e := _derived_eval(check, subj)
}

_key_base_stash(check, subj, cause) := {"ergo/key_bases": bs} if {
	cause in _value_fault_causes
	bs := _key_base_inputs(check, subj)
	bs != []
} else := {}

_key_base_inputs(check, subj) := _once([{"input": _path_input(subj, f.prefix), "cause": f.cause} |
	some [p, mode] in _key_base_reads(check)
	some f in _key_base_flaws(subj, p, mode)
])

_key_base_reads(check) := [[p, _key_base_mode(piece)] |
	some side in _key_base_sides(check)
	some piece in _side_pieces(side)
	some p in _side_paths(piece)
	is_array(p)
]

_key_base_sides(check) := [check.left, check.right] if _two_sided(check)

else := [check.path] if is_array(check.path)

else := []

_side_pieces(side) := side.add if _side_form(side) == "add"

else := side.join if _side_form(side) == "join"

else := [side]

_key_base_mode(piece) := "tally" if _basic_form(piece) in _tally_forms

else := "object"

_once_passed("", e) := e.passed

_once_passed(flaw, _) := false if flaw != ""

_once_cause("", e) := e.cause

_once_cause(flaw, _) := flaw if flaw != ""

default _derived_once(_) := false

_derived_once(check) if check["$once"] == true

_derived_once(check) if {
	not _answered_once(check)
	_once_shaped(check)
}

_answered_once(check) if {
	is_object(check)
	object.get(check, "$once", null) != null
}

default _once_shaped(_) := false

_once_shaped(check) if {
	check.op == "compare"
	_derived_sides(check) != []
	every f in _compare_sides {
		_side_form(object.get(check, f, null))
	}
}

_ref_cause(check) := check["$ref_cause"] if {
	is_object(check)
	"$ref_cause" in object.keys(check)
} else := _worst_of(states) if {
	_unreadable_ref(check)
	states := {s | some r in _unwhosed_refs(check); s := _used_ref_state(check, r); s != "value"}
	count(states) > 0
} else := ""

_unwhosed_refs(check) := {x.ref |
	walk(check, [p, x])
	_is_ref(x)
	not _under_literal(check, p)
	not "whose" in p
}

_derived_eval(check, subj) := {"passed": passed, "cause": cause, "inputs": array.concat(l.inputs, r.inputs)} if {
	l := _side_eval(subj, check.left)
	r := _side_eval(subj, check.right)
	passed := _eval_compared(check, l.v, r.v, subj)
	states := _eval_states(check, l, r, subj)
	cause := _eval_cause(passed, _ref_cause(check), states)
}

_eval_states(check, _, r, _) := r.states if {
	_side_form(check.right) == "join"
	count(r.states) > 0
}

_eval_states(check, l, r, subj) := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(check, lf, rf, subj)} if {
	not _side_form(check.right) == "join"
}

_eval_states(check, l, r, subj) := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(check, lf, rf, subj)} if {
	_side_form(check.right) == "join"
	count(r.states) == 0
}

_eval_compared(check, [lv], [rv], subj) if _compared(check, lv, rv, subj)

default _eval_compared(_, _, _, _) := false

_eval_cause(true, _, _) := "satisfied"

_eval_cause(false, "", states) := _worst_or_value(states)

_eval_cause(false, ref_cause, states) := _worst_of(states | {ref_cause}) if ref_cause in _no_value_states

_eval_cause(false, ref_cause, _) := ref_cause if not ref_cause in _no_read_fault_causes

_basic_eval(subj, side) := {"v": v, "found": [x | x := _simple_found(subj, side)], "states": {_side_state(subj, side)}, "inputs": _basic_inputs(subj, side)} if {
	_basic_form(side) == "path"
	v := [x | x := _value_at(subj, side)]
}

_basic_eval(subj, side) := {"v": [_written(side)], "found": [x | x := _simple_found(subj, side)], "states": set(), "inputs": []} if _basic_form(side) == "literal"

_basic_eval(subj, side) := {"v": v, "found": v, "states": t.states, "inputs": _tally_inputs(subj, side, t)} if {
	_basic_form(side) in _tally_forms
	t := _tally(subj, side)
	v := [x | x := t.value]
}

_basic_eval(subj, side) := {"v": v, "found": v, "states": _elapsed_states(subj, side), "inputs": _basic_inputs(subj, side)} if {
	_basic_form(side) == "elapsed"
	v := [x | x := _basic_value(subj, side)]
}

_side_eval(subj, side) := _basic_eval(subj, side) if _basic_form(side)

_side_eval(subj, side) := {"v": v, "found": v, "states": (union({o.states | some o in ops}) | _add_states(ops)), "inputs": array.concat([_number_input(_side_text(side), _first_or_null(v), operands)], operands)} if {
	_side_form(side) == "add"
	ops := [_operand_eval(subj, operand) | some operand in side.add]
	operands := [i | some o in ops; some i in o.inputs]
	v := _added(side, ops)
}

_side_eval(subj, side) := {"v": v, "found": v, "states": _join_states(ops), "inputs": [i | some o in ops; some i in o.inputs]} if {
	_side_form(side) == "join"
	ops := [_basic_eval(subj, piece) | some piece in side.join]
	v := _joined_pieces(ops)
}

_joined_pieces(ops) := [concat("", pieces)] if {
	pieces := [v | some o in ops; [v] := o.v]
	count(pieces) == count(ops)
	every v in pieces {
		is_string(v)
	}
} else := []

_piece_state(o) := state if {
	count(o.states) == 1
	some state in o.states
	state != "value"
}

_piece_state(o) := "unusable" if {
	o.states == {"value"}
	[v] := o.v
	not is_string(v)
}

_join_states(ops) := {_piece_state(ops[i]) |
	some i, _ in ops
	not _earlier_bad(ops, i)
}

_earlier_bad(ops, i) if {
	some j, o in ops
	j < i
	_piece_state(o)
}

_operand_eval(subj, operand) := object.union(_basic_eval(subj, operand), {"states": _number_states(subj, operand)}) if _basic_form(operand) == "path"

_operand_eval(subj, operand) := _basic_eval(subj, operand) if _basic_form(operand) != "path"

_add_states(ops) := {"unusable" |
	nums := [n | some o in ops; [n] := o.v]
	count(nums) == count(ops)
	_unaddable(nums)
}

_added(side, ops) := [_add_numbers(side, nums)] if {
	nums := [n | some o in ops; [n] := o.v]
	count(nums) == count(ops)
	every n in nums {
		is_number(n)
	}
} else := []

_check_outcome(check, subj, _) := object.union(
	{
		"inputs": _with_key_fields(subj, check, r.inputs),
		"passed": r.cause == "satisfied",
		"cause": r.cause,
		"failed_items": r.failed,
	},
	object.union(_m_walk_outcome(check, subj, r), object.filter(r, {"ergo/key_lists"})),
) if {
	_walks(check)
	_walk_run(check)
	r := _walk_row(check, subj)
}

_m_walk_outcome(_, _, r) := {} if r.cause == "satisfied"

_m_walk_outcome(check, _, r) := {"message": concat("; ", array.concat(own, [_m_joined(said) | said := [m | some m in ms; m in items]; said != []])), "ergo/own": own, "ergo/texts": items} if {
	r.cause != "satisfied"
	"root_msgs" in object.keys(r)
	ms := _walk_roots_sorted(r.root_msgs, check)
	items := object.get(r, "ergo/alone_items", [])
	items != []
	own := _once([m | some m in ms; not m in items])
} else := {"message": _m_joined(ms), "ergo/own": ms, "ergo/texts": []} if {
	r.cause != "satisfied"
	"root_msgs" in object.keys(r)
	ms := _walk_roots_sorted(r.root_msgs, check)
	object.get(r, "ergo/alone_items", []) == []
}

_m_walk_outcome(check, subj, r) := {"message": _m_joined(ps), "ergo/own": [p | some p in ps; not p in items], "ergo/texts": items} if {
	r.cause != "satisfied"
	not "root_msgs" in object.keys(r)
	parts := _walk_parts(check, subj, r, r)
	items := _walk_item_texts(parts, r)
	ps := _walk_roots_sorted(_parts_ahead(parts, r), check)
}

_walk_roots_sorted(ps, check) := ps if {
	count([p | some p in ps; _walk_kind(p) == "list"]) == 0
	count({_m_item_list_of(p) | some p in ps}) < 2
} else := _walk_roots_sorted_in(ps, _walk_list_names(check))

_m_item_list_of(p) := split(split(_item_parts(p)[1], ":")[0], " ")[0]

_walk_roots_sorted_in(ps, lists) := ps if count([p | some p in ps; _m_root_clause(p, lists)]) < 2

else := _roots_then_lists(ps, lists)

_walk_list_names(check) := {_input_name(array.slice(p, 0, i)) |
	p := check.path
	is_array(p)
	some i in numbers.range(1, count(p))
	every seg in array.slice(p, 0, i) {
		is_string(seg)
	}
}

_walk_item_texts(parts, r) := parts if count(parts) == count(r.failed)

else := []

_walk_run(check) if {
	check.op in {"every", "some", "for"}
}

_check_outcome(check, subj, _) := object.union(
	{
		"inputs": r.inputs,
		"passed": r.cause == "satisfied",
		"cause": r.cause,
		"failed_items": r.failed,
	},
	object.filter(r, {"message", "ergo/for_raw", "ergo/key_lists"}),
) if {
	check.op == "for"
	_walk_run(check)
	r := _for_row(check, subj)
}

_all_of_run(check) if {
	check.op == "all_of"
}

_check_outcome(check, subj, flaw) := {
	"inputs": _merged_inputs([i | some o in outs; some i in o.inputs]),
	"passed": count(failed) == 0,
	"cause": _all_of_cause(failed),
	"failed_assertions": failed,
} if {
	_all_of_run(check)
	outs := [_assertion_out(c, subj, flaw) | some c in check.checks]
	failed := [{"assertion": check.assertions[i], "cause": o.cause, "inputs": o.inputs, "at": i, "key_bases": o.key_bases} | some i, o in outs; o.cause != "satisfied"]
}

_any_of_run(check) if {
	check.op == "sentence_any_of"
}

_check_outcome(check, subj, flaw) := object.union(
	{
		"inputs": _merged_inputs([i | some o in outs; some i in o.inputs]),
		"passed": cause == "satisfied",
		"cause": cause,
	},
	_option_outs(outs, lines, cause),
) if {
	_any_of_run(check)
	outs := [_assertion_out(c, subj, flaw) | some c in check.checks]
	lines := [_option_line_cause(c, outs[i].cause, subj) | some i, c in check.checks]
	cause := _any_of_lines_cause(check.option_of, lines, flaw)
}

_option_outs(_, _, "satisfied") := {}

_option_outs(outs, lines, cause) := {"ergo/outs": [{"cause": o.cause, "line": lines[i], "inputs": o.inputs, "key_bases": o.key_bases} | some i, o in outs]} if cause != "satisfied"

_option_line_cause(c, cause, subj) := "missing" if {
	cause == "value"
	not _walks(c)
	_asks_presence(c, subj)
	_read_state(subj, c.path) in _no_value_states
} else := cause

_any_of_lines_cause(_, _, flaw) := flaw if flaw != ""

_any_of_lines_cause(option_of, lines, "") := "satisfied" if {
	some nm in option_of
	every i, n in option_of {
		_line_passed_or_elsewhere(n, nm, lines[i])
	}
} else := _worst_or_value({_group_cause({lines[i] | some i, n in option_of; n == nm}) | some nm in option_of})

_line_passed_or_elsewhere(n, nm, _) if n != nm

_line_passed_or_elsewhere(_, _, "satisfied")

_assertion_out(c, subj, "") := {"cause": e.cause, "inputs": _with_key_fields(subj, c, e.inputs), "key_bases": _assertion_key_bases(c, subj, e.cause)} if {
	_derived_once(c)
	e := _derived_eval(c, subj)
} else := {"cause": cause, "inputs": _with_key_fields(subj, c, _assertion_inputs(subj, c)), "key_bases": _assertion_key_bases(c, subj, cause)} if {
	cause := _assertion_cause(c, subj, "")
}

_assertion_out(c, subj, flaw) := {"cause": cause, "inputs": _with_key_fields(subj, c, _assertion_inputs(subj, c)), "key_bases": _assertion_key_bases(c, subj, cause)} if {
	flaw != ""
	cause := _assertion_cause(c, subj, flaw)
}

_assertion_key_bases(c, subj, cause) := _key_base_inputs(c, subj) if {
	cause in _value_fault_causes
	not _walks(c)
}

else := []

_assertion_cause(c, subj, "") := _row_cause(c, subj, "") if not _walks(c)

_assertion_cause(c, subj, _) := _walk_row(c, subj).cause if _walks(c)

_assertion_cause(c, subj, "unusable") := "unusable" if {
	not _walks(c)
	_unusable_assertion(c)
} else := _row_cause(c, subj, "") if not _walks(c)

_unusable_assertion(_) if _unreadable_input

_unusable_assertion(c) if _node_param_broken(c)

_assertion_inputs(subj, c) := _row_inputs(subj, c) if not _walks(c)

_assertion_inputs(subj, c) := _walk_row(c, subj).inputs if _walks(c)

_all_of_cause([]) := "satisfied"

_all_of_cause(failed) := [c | some c in array.concat(_cause_precedence, ["value"]); c in {f.cause | some f in failed}][0] if failed != []

default _subject_matches(_, _) := false

_subject_matches(evals, req) if {
	count(evals) == count(_applies_to_of(req))
	every _, e in evals {
		e.passed
	}
}

_req_subject_ref(req) := object.union({"type": _subject_type_of(req), "id": null}, _row_in)

default _row_in := {}

_row_in := {"in": data.ergo_in} if data.ergo_in != {}
