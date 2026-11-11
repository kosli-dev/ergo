package ergo

import rego.v1

default _two_sided(_) := false

_two_sided(check) if check.op in {"compare", "compare_time"}

_basic_form(side) := "path" if is_array(side)

_basic_form(side) := "literal" if {
	is_object(side)
	object.keys(side) == {"literal"}
}

_basic_form(side) := f if {
	is_object(side)
	some f in ["count_of", "sum_of"]
	object.keys(side) == {f, "whose", "text"}
	is_array(side[f])
	is_array(side.whose)
	is_string(side.text)
}

_basic_form(side) := f if {
	is_object(side)
	side.distinct == true
	some f in ["count_of", "sum_of"]
	object.keys(side) == {f, "whose", "text", "distinct"}
	is_array(side[f])
	is_array(side.whose)
	is_string(side.text)
}

_basic_form(side) := "elapsed" if {
	is_object(side)
	object.keys(side) == {"unit", "elapsed_from", "elapsed_to", "text"}
	side.unit in object.keys(_elapsed_seconds)
	is_array(side.elapsed_from)
	is_array(side.elapsed_to)
	is_string(side.text)
}

_side_form(side) := _basic_form(side)

_side_form(side) := "add" if {
	is_object(side)
	object.keys(side) - {"text"} == {"add"}
	is_string(object.get(side, "text", ""))
	is_array(side.add)
	count(side.add) > 0
	every operand in side.add {
		_operand(operand)
	}
}

_side_form(side) := "join" if {
	is_object(side)
	object.keys(side) - {"text"} == {"join"}
	is_string(object.get(side, "text", ""))
	is_array(side.join)
	count(side.join) > 0
	every piece in side.join {
		_join_piece(piece)
	}
}

default _derived_sides(_) := []

_derived_sides(check) := [check[f] | some f in ["left", "right"]; f in object.keys(check); _derived(check[f])] if check.op == "compare"

_basic_paths(side) := [side] if _basic_form(side) == "path"

_basic_paths(side) := [] if _basic_form(side) == "literal"

_basic_paths(side) := [side.elapsed_from, side.elapsed_to] if _basic_form(side) == "elapsed"

_basic_paths(side) := [side[f]] if {
	f := _basic_form(side)
	f in {"count_of", "sum_of"}
}

_side_paths(side) := _basic_paths(side) if _basic_form(side)

_side_paths(side) := [p | some operand in side.add; some p in _basic_paths(operand)] if _side_form(side) == "add"

_side_paths(side) := [p | some piece in side.join; some p in _basic_paths(piece)] if _side_form(side) == "join"

_side_paths(side) := [] if not _side_form(side)
