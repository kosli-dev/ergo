package ergo

import rego.v1

_elapsed_seconds := {"seconds": 1, "minutes": 60, "hours": 3600, "days": 86400, "weeks": 604800}

_join_piece(piece) if _basic_form(piece) == "path"

_join_piece(piece) if {
	_basic_form(piece) == "literal"
	is_string(_written(piece))
}

_operand(x) if _basic_form(x) in {"path", "count_of", "sum_of", "elapsed"}

_operand(x) if {
	_basic_form(x) == "literal"
	is_number(_written(x))
}

default _derived(_) := false

_derived(side) if _side_form(side) in {"add", "join", "count_of", "sum_of", "elapsed"}

_simple_value(subj, side) := _value_at(subj, side) if is_array(side)

_simple_value(_, side) := _written(side) if _basic_form(side) == "literal"

_basic_value(subj, side) := _simple_value(subj, side) if _basic_form(side) in {"path", "literal"}

_basic_value(subj, side) := _elapsed_units(side.unit, _value_at(subj, side.elapsed_from), _value_at(subj, side.elapsed_to)) if _basic_form(side) == "elapsed"

_basic_value(subj, side) := r.value if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
	r.states == set()
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, _time_ns(y) - _time_ns(x)) if {
	_rfc3339_shaped(x)
	_rfc3339_shaped(y)
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, _time_ns(y) - _time_ns(x)) if {
	_date_shaped(x)
	_date_shaped(y)
}

_elapsed_units(unit, x, y) := _elapsed_ns(unit, (round(y * 1000000) - round(x * 1000000)) * 1000) if {
	_elapsed_seconds_time(x)
	_elapsed_seconds_time(y)
}

_elapsed_ns(unit, n) := ((n - (n % step)) / step) / 1000000 if {
	n >= 0
	step := _elapsed_seconds[unit] * 1000
}

_elapsed_seconds_time(v) if {
	is_number(v)
	v >= -9000000000
	v <= 9000000000
}

_elapsed_times(x, y) if {
	_rfc3339_shaped(x)
	_rfc3339_shaped(y)
}

_elapsed_times(x, y) if {
	_date_shaped(x)
	_date_shaped(y)
}

_elapsed_times(x, y) if {
	_elapsed_seconds_time(x)
	_elapsed_seconds_time(y)
}

_time_ns(v) := time.parse_rfc3339_ns(v) if _rfc3339_shaped(v)

_time_ns(v) := time.parse_rfc3339_ns(concat("", [v, "T00:00:00Z"])) if _date_shaped(v)

_elapsed_path_states(subj, path) := {s} if {
	s := _read_state(subj, path)
	s != "value"
}

_elapsed_path_states(subj, path) := set() if _read_state(subj, path) == "value"

_elapsed_states(subj, side) := (_elapsed_path_states(subj, side.elapsed_from) | _elapsed_path_states(subj, side.elapsed_to)) | {"unusable" |
	_elapsed_path_states(subj, side.elapsed_from) == set()
	_elapsed_path_states(subj, side.elapsed_to) == set()
	not _elapsed_times(_value_at(subj, side.elapsed_from), _value_at(subj, side.elapsed_to))
}

_side_value(subj, side) := _basic_value(subj, side) if _basic_form(side)

_side_value(subj, side) := _add_numbers(side, nums) if {
	_side_form(side) == "add"
	nums := [n | some operand in side.add; n := _basic_value(subj, operand)]
	count(nums) == count(side.add)
	every n in nums {
		is_number(n)
	}
}

_add_numbers(side, nums) := _decimal_sum(nums) if "text" in object.keys(side)

_number_states(x, path) := {s} if {
	s := _read_state(x, path)
	s != "value"
}

_number_states(x, path) := {"unusable"} if {
	_read_state(x, path) == "value"
	not is_number(_value_at(x, path))
}

_number_states(x, path) := set() if {
	_read_state(x, path) == "value"
	is_number(_value_at(x, path))
}

_usable_sides(check, l, r) if {
	not "within" in object.keys(check)
	_usable_pair(check.cmp, l, r)
}

_usable_sides(check, l, r) if {
	"within" in object.keys(check)
	_within_usable(check, l, r)
}

_usable_sides(check, l, r) if {
	check.cmp in {"includes", "excludes"}
	is_array(l)
	is_string(r)
	_items_fit(l, [r])
}

_within_usable(check, l, r) if {
	_numbers(l, r)
	is_number(check.within)
	_within_spread([json.marshal(l), json.marshal(r), json.marshal(check.within)]) <= 4096
}

_within_gap(l, r, w) if {
	texts := [json.marshal(l), json.marshal(r), json.marshal(w)]
	_within_spread(texts) <= 4096
	_within_texts(texts)
}

_within_texts(texts) := _at_most(gap, round(to_number(texts[2]) * scale)) if {
	scale := _text_scale(texts)
	gap := abs(round(to_number(texts[0]) * scale) - round(to_number(texts[1]) * scale))
	gap < 1e15
} else := _within_exact(texts)

_at_most(a, b) := a <= b

_text_scale(texts) := scale if {
	every t in texts {
		count(_decimal_parts(t).digits) + _decimal_parts(t).exponent <= 15
	}
	places := max([_text_places(t) | some t in texts])
	places <= 15
	scale := product([10 | some i in numbers.range(1, 15); i <= places])
	every t in texts {
		round(abs(to_number(t)) * scale) < 1e15
	}
}

_text_places(text) := max([0, count(trim_right(digits, "0")) - point]) if {
	m := _number_match(text)
	digits := concat("", [m[1], m[2]])
	point := count(m[1]) + _exponent(m[3])
}

_within_spread(texts) := max(exponents) - min(exponents) if exponents := [_decimal_parts(t).exponent | some t in texts]

_decimal_parts(text) := {"negative": false, "digits": "0", "exponent": 0} if trim_left(_number_digits(text), "0") == ""

_decimal_parts(text) := {"negative": startswith(text, "-"), "digits": trimmed, "exponent": ((_exponent(m[3]) - count(m[2])) + count(stripped)) - count(trimmed)} if {
	m := _number_match(text)
	stripped := trim_left(_number_digits(text), "0")
	stripped != ""
	trimmed := trim_right(stripped, "0")
}

_number_match(text) := regex.find_all_string_submatch_n(`^-?([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$`, text, 1)[0]

_number_digits(text) := concat("", [m[1], m[2]]) if m := _number_match(text)

_within_exact(texts) if {
	parts := [_decimal_parts(t) | some t in texts]
	low := min([p.exponent | some p in parts])
	mags := [concat("", [p.digits, _zeros(p.exponent - low)]) | some p in parts]
	width := 7 * ceil((max([count(m) | some m in mags]) + 1) / 7)
	chunks := [_chunks(m, width) | some m in mags]
	_within_chunks(parts[0].negative == parts[1].negative, chunks)
}

_within_chunks(true, chunks) if {
	chunks[0] <= _sum_chunks(chunks[1], chunks[2])
	chunks[1] <= _sum_chunks(chunks[0], chunks[2])
}

_within_chunks(false, chunks) if _sum_chunks(chunks[0], chunks[1]) <= chunks[2]

_chunks(mag, width) := [_chunk(substring(padded, start, 7)) | some i in numbers.range(0, (width / 7) - 1); start := i * 7] if padded := concat("", [_zeros(width - count(mag)), mag])

_chunk(text) := 0 if trim_left(text, "0") == ""

_chunk(text) := to_number(trim_left(text, "0")) if trim_left(text, "0") != ""

_sum_chunks(x, y) := [_normalized(sums, i) | some i, _ in sums] if {
	sums := [total | some i, v in x; total := v + y[i]]
}

_normalized(sums, i) := total - 10000000 if {
	total := sums[i] + _carry(sums, i)
	total >= 10000000
}

_normalized(sums, i) := total if {
	total := sums[i] + _carry(sums, i)
	total < 10000000
}

_carry(sums, i) := _carry_from(sums, [j | some j, s in sums; j > i; s != 9999999])

_carry_from(_, []) := 0

_carry_from(sums, later) := 1 if {
	later != []
	sums[min(later)] >= 10000000
}

_carry_from(sums, later) := 0 if {
	later != []
	sums[min(later)] < 10000000
}

_basic_inputs(subj, side) := [_path_input(subj, side)] if _basic_form(side) == "path"

_basic_inputs(_, side) := [] if _basic_form(side) == "literal"

_basic_inputs(subj, side) := _tally_inputs(subj, side, r) if {
	_basic_form(side) in {"count_of", "sum_of"}
	r := _tally(subj, side)
}

_tally_inputs(subj, side, t) := array.concat(
	[
		{"name": side.text, "value": object.get(t, "value", null), "locations": t.locations},
		_tally_list_input(t),
	],
	_merged_inputs(array.concat(
		_named_inputs(subj, [p | some c in object.get(side, "whose", []); some p in _condition_paths(c)]),
		array.concat(_field_named_inputs(subj, [p | some c in object.get(side, "whose", []); some p in _condition_paths(c)]), _input_ref_inputs(object.get(side, "whose", []))),
	)),
)

_tally_list_input(t) := {"name": t.list, "value": t.values, "locations": t.locations}

_basic_inputs(subj, side) := [_number_input(side.text, _first_or_null([x | x := _basic_value(subj, side)]), [from, to]), from, to] if {
	_basic_form(side) == "elapsed"
	from := _path_input(subj, side.elapsed_from)
	to := _path_input(subj, side.elapsed_to)
}

_side_inputs(subj, side) := _basic_inputs(subj, side) if _basic_form(side)

_side_inputs(subj, side) := [i | some piece in side.join; some i in _basic_inputs(subj, piece)] if _side_form(side) == "join"

_side_inputs(subj, side) := array.concat([_derived_input(subj, side, _side_text(side), operands)], operands) if {
	_side_form(side) == "add"
	operands := [i | some operand in side.add; some i in _basic_inputs(subj, operand)]
}

_tally(subj, side) := {"states": {"not_an_object"}, "list": _path_name(path), "values": [], "locations": []} if {
	path := side[_basic_form(side)]
	not _off_subject(path)
	not _old_subject_part(path)
	not _reads_subject(path)
	not _list_start(path, subj)
	not is_object(subj)
} else := {"states": {_walk_read_state(subj, path)}, "list": _path_name(path), "values": [], "locations": []} if {
	path := side[_basic_form(side)]
	not _walk_keys({"path": path}, subj)
} else := r if {
	f := _basic_form(side)
	w := _walk(_walk_start({"path": side[f]}, subj), _walk_keys({"path": side[f]}, subj), true)
	flaws := [_cond_flaw(c) | some c in side.whose]
	judged := [_tally_judge(side, e, flaws) | some e in w.items]
	kept := [e.v | some i, e in w.items; judged[i].kept]
	read := [e.v | some i, e in w.items; judged[i].read]
	states := (((({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {c | some j in judged; some c in j.states}) | _tally_number_states(f, _tally_distinct(side, read))) | {fl | some fl in flaws; fl != ""}) | {fl | some c in side.whose; fl := _root_read_flaw(subj, c); fl != ""}
	r := object.union({"states": states, "list": _walk_name(side[f], w.walked), "values": [_walk_shown(e.v) | some e in w.items], "locations": _walk_locations(w)}, _tally_value(f, _tally_distinct(side, kept), states))
}

_tally_judge(side, e, flaws) := {"kept": kept, "read": read, "states": (undecided | _tally_mark(read, e))} if {
	causes := [_tally_focus_cause(c, e, flaws[i]) | some i, c in side.whose]
	undecided := {c | some c in causes; not c in {"satisfied", "value", "missing"}}
	kept := count([c | some c in causes; c in {"value", "missing"}]) == 0
	read := count([c | some c in causes; c != "satisfied"]) == 0
}

_tally_focus_cause(c, e, flaw) := _tally_cond_cause(c, e.iv, flaw) if e.r == []

else := flaw if flaw != ""

else := _focus_lost_state(e) if _focus_lost(e, c)

else := _tally_cond_cause(c, e.v, flaw)

_tally_cond_cause(c, item, "") := _eval_cause(passed, _ref_cause(c), states) if {
	_derived_once(c)
	l := _cond_side(item, c.left)
	r := _cond_side(item, c.right)
	passed := _eval_compared(c, l.v, r.v)
	states := (l.states | r.states) | {"unusable" | [lf] := l.found; [rf] := r.found; not _usable_sides(c, lf, rf)}
}

_cond_side(item, side) := {"v": v, "found": v, "states": _elapsed_states(item, side)} if {
	_basic_form(side) == "elapsed"
	v := [x | x := _elapsed_units(side.unit, _value_at(item, side.elapsed_from), _value_at(item, side.elapsed_to))]
}

_cond_side(item, side) := {"v": [x | x := t.value], "found": [x | x := t.value], "states": t.states} if {
	_basic_form(side) == "count_of"
	t := _cond_tally(item, side)
}

_cond_tally(item, side) := {"states": {"not_an_object"}} if {
	not _off_subject(side.count_of)
	not _old_subject_part(side.count_of)
	not _reads_subject(side.count_of)
	not _list_start(side.count_of, item)
	not is_object(item)
} else := {"states": {_walk_read_state(item, side.count_of)}} if {
	not _walk_keys({"path": side.count_of}, item)
} else := r if {
	w := _walk(_walk_start({"path": side.count_of}, item), _walk_keys({"path": side.count_of}, item), true)
	kept := [e.v | some e in w.items]
	states := ({x.cause | some x in w.fails} | {x.cause | some x in _walk_stop(w)}) | {c | some e in w.items; some c in _tally_mark(true, e)}
	r := object.union({"states": states}, _tally_value("count_of", _tally_distinct(side, kept), states))
}

_cond_side(item, side) := {"v": [x | x := _value_at(item, side)], "found": [x | x := _simple_found(item, side)], "states": {_read_state(item, side)}} if _basic_form(side) == "path"

_cond_side(item, side) := {"v": [_written(side)], "found": [x | x := _simple_found(item, side)], "states": set()} if _basic_form(side) == "literal"

_tally_cond_cause(c, item, "") := _leaf_cause(c, item) if not _derived_once(c)

_tally_cond_cause(_, _, flaw) := flaw if flaw != ""

_cond_flaw(c) := "unusable" if {
	_node_param_broken(c)
} else := _worst_of({_used_ref_state(c, r) | some r in _check_refs(c)}) if {
	_unreadable_ref(c)
} else := ""

_tally_mark(true, e) := {"not_an_object"} if {
	e.v == _absent
	not is_object(e.iv)
}

_tally_mark(true, e) := {"absent"} if {
	e.v == _absent
	is_object(e.iv)
}

_tally_mark(true, e) := {_read_state(e.iv, e.r)} if e.v == _unusable_mark

_tally_mark(_, e) := set() if not _walk_marked(e.v)

_tally_mark(false, e) := set() if _walk_marked(e.v)

_tally_distinct(side, kept) := kept if object.get(side, "distinct", false) != true

else := [v | some j, v in sorted; _first_of_kind(sorted, j)] if sorted := sort(kept)

_first_of_kind(_, 0)

_first_of_kind(sorted, j) if {
	j > 0
	sorted[j] != sorted[j - 1]
}

_tally_value(_, _, states) := {} if states != set()

_tally_value("count_of", kept, set()) := {"value": count(kept)}

_tally_value("sum_of", kept, set()) := {"value": _decimal_sum(kept)}

_tally_number_states("count_of", _) := set()

_tally_number_states("sum_of", kept) := {_sum_state(n) | some n in kept; not _walk_marked(n); not is_number(n)} | {"unusable" | _unaddable(kept)}

_sum_state(null) := "null"

_sum_state(n) := "unusable" if n != null

_decimal_scale(nums) := scale if {
	places := max(array.concat([0], [_value_places(n) | some n in nums]))
	places <= 15
	scale := product([10 | some i in numbers.range(1, 15); i <= places])
	every n in nums {
		round(abs(n) * scale) < 1e15
	}
}

_decimal_sum(nums) := total / scale if {
	scale := _decimal_scale(nums)
	total := sum([round(n * scale) | some n in nums])
	abs(total) < 1e15
}

_value_places(n) := max([0, count(trim_right(digits, "0")) - point]) if {
	m := regex.find_all_string_submatch_n(`^-?([0-9]+)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$`, json.marshal(n), 1)[0]
	digits := concat("", [m[1], m[2]])
	point := count(m[1]) + _exponent(m[3])
}

_unaddable(nums) if {
	every n in nums {
		is_number(n)
	}
	not _decimal_sum(nums)
}

_derived_input(subj, side, name, operands) := _number_input(name, v, operands) if {
	v := _side_value(subj, side)
} else := _number_input(name, null, operands)

_side_text(side) := side.text if {
	_side_form(side) == "add"
	"text" in object.keys(side)
}

_sentence_side(side) if _basic_form(side) in {"count_of", "sum_of", "elapsed"}

_sentence_side(side) if {
	is_object(side)
	"text" in object.keys(side)
}

_where_children(node, names) := [[c, array.concat(at, ["whose", i]), "where", names] |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	some [at, side] in _tallies(node[f], [f])
	some i, c in side.whose
]

_tallies(side, at) := [[at, side]] if _basic_form(side) in {"count_of", "sum_of"}

_tallies(side, at) := [[array.concat(at, ["add", i]), operand] | some i, operand in side.add; _basic_form(operand) in {"count_of", "sum_of"}] if _side_form(side) == "add"

_tallies(side, _) := [] if not _side_form(side) in {"count_of", "sum_of", "add"}

_side_problem(node, here) := ({concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	not _side_form(node[f])
} | {concat("", ["invalid ", f]) |
	node.op == "compare"
	some f in ["left", "right"]
	f in object.keys(node)
	_sentence_side(node[f])
	not _s_read(node, here)
}) | {concat("", ["invalid ", f]) |
	node.op == "compare_time"
	some f in ["left", "right"]
	f in object.keys(node)
	not is_array(node[f])
	not _sentence_time_value(f, node, here)
}

_sentence_time_value("right", node, here) if {
	_basic_form(node.right) == "literal"
	_s_read(node, here)
}

_within_problem(node) := {"invalid within" |
	node.op == "compare"
	"within" in object.keys(node)
	not _non_negative(node.within)
}

_non_negative(n) if {
	is_number(n)
	n >= 0
}

_derived_placement_problem(node, kinds, here) := {concat("", [_side_form(side), " can't go here"]) |
	kinds != []
	not _assertion_kinds(kinds)
	some side in _derived_sides(node)
	not _sentence_side_in_whose(side, kinds, node, here)
}

_sentence_side_in_whose(side, kinds, node, here) if {
	_basic_form(side) in {"elapsed", "count_of"}
	kinds[count(kinds) - 1] == "where"
	_s_read(node, here)
}
