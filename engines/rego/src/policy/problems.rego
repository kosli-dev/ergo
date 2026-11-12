package ergo

import rego.v1

_json_problems(v) := {"holds a key that isn't a string" |
	walk(v, [_, x])
	is_object(x)
	some k in object.keys(x)
	not is_string(k)
} | {"holds a set" |
	walk(v, [_, x])
	is_set(x)
}

_meta_problems(m) := _json_problems(m) | _number_flaws(m)

_meta_shaped(v) if {
	is_object(v)
	count(_meta_problems(v)) == 0
}

_req_meta_problems(req) := {["meta", p] |
	is_object(req)
	is_object(object.get(req, "meta", null))
	some p in _meta_problems(req.meta)
}

_reported_description(x) := object.get(x, "description", "") if {
	is_object(x)
	is_string(object.get(x, "description", ""))
} else := ""

_reported_meta(x) := json.unmarshal(_json_text(x.meta)) if {
	is_object(x)
	_meta_shaped(object.get(x, "meta", null))
} else := {}

_typed(req) if {
	is_object(req)
	_wrong_typed_fields(req) == []
}

_unknown_req_fields(req) := sort([f |
	some f in object.keys(req)
	not f in (object.keys(_wrong_type_problems) | {"require"})
]) if is_object(req)

_unknown_subject_fields(def) := sort([f |
	some f in object.keys(def)
	not f in (object.keys(_subject_wrong_type_problems) | {"has"})
])

_unknown_req_fields(req) := [] if not is_object(req)

_not_an_object_inputs(req) := [{"name": "requirement", "value": req, "locations": []}] if not is_object(req)

_not_an_object_inputs(req) := [] if is_object(req)

_wrong_type_problems := {
	"checks": "not an object",
	"min_subjects": "not a whole number from 0 to 1000000",
	"subject": "empty or not a string",
	"description": "not a string",
	"meta": "not an object",
}

_subject_wrong_type_problems := {
	"applies_to": "not an object",
	"from": "not a string",
	"identified_by": "not a string",
	"description": "not a string",
	"of": "empty or not a string",
}

_req_problems(req) := union({_req_meta_problems(req), _type_problems(req), _range_problems(req), _unknown_problems(req), _checks_problems(req), _require_problems(req), _req_json_problems(req), _subject_problems(req)})

_subject_problems(req) := (_subject_ref_problems(req) | _resolution_problems(req)) | _parent_problems(req)

_parent_problems(req) := union({_resolution_problems({"subject": a}) | some a in _s_ancestors(req.subject, data.ergo_subject_sentences.chains)}) if _chained(req)

_parent_problems(req) := set() if not _chained(req)

_resolution_problems(req) := r.problems if {
	r := _resolution_of(req)
} else := set()

_member_problems(members) := union({
	{[array.concat(["subjects", m], [p[0]]), p[1]] |
		some m in members
		some p in _def_problems(_raw_subject(m))
	},
	{[["subjects", m, "from"], "can't build on a subject read from another subject yet"] |
		some m in members
		of := object.get(_raw_subject(m), "of", null)
		is_string(of)
		of in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
	},
	{[["subjects", m, "of"], "not in subjects"] |
		some m in members
		of := object.get(_raw_subject(m), "of", null)
		_has_type("of", of)
		not of in object.keys(data.ergo_subjects)
	},
	{[["subjects", m], "not an object"] |
		some m in members
		not _raw_subject(m)
	},
	{[["subjects", m], p] |
		some m in members
		_bad_name(m)
		some p in _written_name_problems(m)
	},
	{[["subjects", m, f], p] |
		some m in members
		some f, ps in object.get(data.ergo_subject_sentences.problems, m, {})
		some p in ps
	},
	{[array.concat(["subjects", m], p[0]), p[1]] |
		some m in members
		some p in object.get(object.get(data.ergo_subject_sentences, "has_problems", {}), m, set())
	},
	{[["subjects", m, "applies_to", n], "also a filter of a subject it builds on"] |
		some m in members
		some n in object.keys(_object_or_empty(_filters_of(m)))
		some other in graph.reachable(_of_graph, [m])
		other != m
		n in object.keys(_object_or_empty(_filters_of(other)))
	},
})

_subject_ref_problems(req) := (({["subject", "missing"] |
	is_object(req)
	not "subject" in object.keys(req)
} | {[["subjects"], "not an object"] |
	_names_a_subject(req)
	not is_object(data.ergo_subjects)
}) | {["subject", "not in subjects"] |
	_names_a_subject(req)
	is_object(data.ergo_subjects)
	not req.subject in object.keys(data.ergo_subjects)
}) | {[["subjects", req.subject], "not an object"] |
	_names_a_subject(req)
	is_object(data.ergo_subjects)
	req.subject in object.keys(data.ergo_subjects)
	not is_object(data.ergo_subjects[req.subject])
}

_def_problems(def) := union({
	{[f, _subject_wrong_type_problems[f]] | some f in _wrong_typed(def, _subject_wrong_type_problems)},
	{[f, "unknown field"] | some f in _unknown_subject_fields(def)},
	{["identified_by", "not allowed on a subject that narrows another"] | "of" in object.keys(def); "identified_by" in object.keys(def)},
	_path_problems(def, "from"),
	_path_problems(def, "identified_by"),
	_def_json_problems(def),
})

_req_json_problems(req) := {["checks", "holds a key that isn't a string"] |
	v := _req_field(req, "checks", null)
	is_object(v)
	some k in object.keys(v)
	not is_string(k)
}

_def_json_problems(def) := {[f, p] |
	some f in ["from", "identified_by"]
	v := object.get(def, f, null)
	is_array(v)
	some p in _json_problems(v)
} | {["applies_to", "holds a key that isn't a string"] |
	v := object.get(def, "applies_to", null)
	is_object(v)
	some k in object.keys(v)
	not is_string(k)
}

_type_problems(req) := {[f, _wrong_type_problems[f]] |
	some f in _wrong_typed_fields(req)
	not _min_subjects_out_of_range(req, f)
}

_min_subjects_out_of_range(req, "min_subjects") if {
	is_number(req.min_subjects)
	_out_of_range(req.min_subjects)
}

_min_subjects_out_of_range(req, "min_subjects") if {
	is_number(req.min_subjects)
	_number_flaw(req.min_subjects, json.marshal(req.min_subjects)) == _too_long_problem
}

_range_problems(req) := {["min_subjects", "number out of range"] |
	is_number(_min_subjects_of(req))
	_out_of_range(_min_subjects_of(req))
} | {["min_subjects", _too_long_problem] |
	m := _req_field(req, "min_subjects", null)
	is_number(m)
	_number_flaw(m, json.marshal(m)) == _too_long_problem
}

_unknown_problems(req) := {[f, "unknown field"] | some f in _unknown_req_fields(req)}

_checks_problems(req) := {["checks", "missing"] | is_object(req); not "checks" in object.keys(req)} | {["checks", "empty"] | req.checks == {}}

_reserved_name_problems(req) := {[_field_path_name(["checks", name]), p] |
	some name, _ in _checks_of(req)
	_bad_name(name)
	some p in _written_name_problems(name)
}

_dollar_name_problem := "a name can't start with $"

_edge_name_problem := "a name can't start or end with a space or an invisible character"

_empty_name_problem := "a name can't be empty"

_dollar_name(name) if {
	is_string(name)
	startswith(name, "$")
}

_empty_name(name) if name == ""

_edge_name(name) if {
	is_string(name)
	name != ""
	not _plain_start(name)
	_edge_char(substring(name, 0, 1))
}

_edge_name(name) if {
	is_string(name)
	name != ""
	not _plain_end(name)
	_edge_char(substring(name, count(name) - 1, 1))
}

_plain_start(name) if {
	name >= "0"
	name < "{"
}

_plain_end(name) if regex.match(`[0-9A-Za-z_-]$`, name)

_edge_char(c) if {
	c < "0"
	c in _edge_chars
}

_edge_char(c) if {
	c > "z"
	c in _edge_chars
}

_written_name_problems(name) := ({_dollar_name_problem | _dollar_name(name)} | {_edge_name_problem | _edge_name(name)}) | {_empty_name_problem | _empty_name(name)}

_edge_chars := {"\u0009", "\u000a", "\u000b", "\u000c", "\u000d", "\u0020", "\u0085", "\u00a0", "\u1680", "\u2000", "\u2001", "\u2002", "\u2003", "\u2004", "\u2005", "\u2006", "\u2007", "\u2008", "\u2009", "\u200a", "\u2028", "\u2029", "\u202f", "\u205f", "\u3000", "\u00ad", "\u0600", "\u0601", "\u0602", "\u0603", "\u0604", "\u0605", "\u061c", "\u06dd", "\u070f", "\u0890", "\u0891", "\u08e2", "\u180e", "\u200b", "\u200c", "\u200d", "\u200e", "\u200f", "\u202a", "\u202b", "\u202c", "\u202d", "\u202e", "\u2060", "\u2061", "\u2062", "\u2063", "\u2064", "\u2066", "\u2067", "\u2068", "\u2069", "\u206a", "\u206b", "\u206c", "\u206d", "\u206e", "\u206f", "\ufeff", "\ufff9", "\ufffa", "\ufffb", "\ud804\udcbd", "\ud804\udccd", "\ud80d\udc30", "\ud80d\udc31", "\ud80d\udc32", "\ud80d\udc33", "\ud80d\udc34", "\ud80d\udc35", "\ud80d\udc36", "\ud80d\udc37", "\ud80d\udc38", "\ud80d\udc39", "\ud80d\udc3a", "\ud80d\udc3b", "\ud80d\udc3c", "\ud80d\udc3d", "\ud80d\udc3e", "\ud80d\udc3f", "\ud82f\udca0", "\ud82f\udca1", "\ud82f\udca2", "\ud82f\udca3", "\ud834\udd73", "\ud834\udd74", "\ud834\udd75", "\ud834\udd76", "\ud834\udd77", "\ud834\udd78", "\ud834\udd79", "\ud834\udd7a", "\udb40\udc01", "\udb40\udc20", "\udb40\udc21", "\udb40\udc22", "\udb40\udc23", "\udb40\udc24", "\udb40\udc25", "\udb40\udc26", "\udb40\udc27", "\udb40\udc28", "\udb40\udc29", "\udb40\udc2a", "\udb40\udc2b", "\udb40\udc2c", "\udb40\udc2d", "\udb40\udc2e", "\udb40\udc2f", "\udb40\udc30", "\udb40\udc31", "\udb40\udc32", "\udb40\udc33", "\udb40\udc34", "\udb40\udc35", "\udb40\udc36", "\udb40\udc37", "\udb40\udc38", "\udb40\udc39", "\udb40\udc3a", "\udb40\udc3b", "\udb40\udc3c", "\udb40\udc3d", "\udb40\udc3e", "\udb40\udc3f", "\udb40\udc40", "\udb40\udc41", "\udb40\udc42", "\udb40\udc43", "\udb40\udc44", "\udb40\udc45", "\udb40\udc46", "\udb40\udc47", "\udb40\udc48", "\udb40\udc49", "\udb40\udc4a", "\udb40\udc4b", "\udb40\udc4c", "\udb40\udc4d", "\udb40\udc4e", "\udb40\udc4f", "\udb40\udc50", "\udb40\udc51", "\udb40\udc52", "\udb40\udc53", "\udb40\udc54", "\udb40\udc55", "\udb40\udc56", "\udb40\udc57", "\udb40\udc58", "\udb40\udc59", "\udb40\udc5a", "\udb40\udc5b", "\udb40\udc5c", "\udb40\udc5d", "\udb40\udc5e", "\udb40\udc5f", "\udb40\udc60", "\udb40\udc61", "\udb40\udc62", "\udb40\udc63", "\udb40\udc64", "\udb40\udc65", "\udb40\udc66", "\udb40\udc67", "\udb40\udc68", "\udb40\udc69", "\udb40\udc6a", "\udb40\udc6b", "\udb40\udc6c", "\udb40\udc6d", "\udb40\udc6e", "\udb40\udc6f", "\udb40\udc70", "\udb40\udc71", "\udb40\udc72", "\udb40\udc73", "\udb40\udc74", "\udb40\udc75", "\udb40\udc76", "\udb40\udc77", "\udb40\udc78", "\udb40\udc79", "\udb40\udc7a", "\udb40\udc7b", "\udb40\udc7c", "\udb40\udc7d", "\udb40\udc7e", "\udb40\udc7f"}

_require_problems(req) := {["require", "neither every nor some"] | is_object(req); not _require_of(req) in {"every", "some"}}

_path_problems(req, f) := {[f, "number out of range"] | is_array(_req_field(req, f, null)); _out_of_range(req[f])}

_field_problem_inputs(req) := [{"name": _field_key_name(k), "value": sort({p[1] | some p in problems; _field_sort_key(p[0]) == k}), "locations": []} | some k in sort({_field_sort_key(p[0]) | some p in problems; p[0] != "require"})] if {
	problems := _req_problems(req)
}

_field_sort_key(f) := [1, _field_name(f)] if is_string(f)

_field_sort_key(f) := [2, _field_name(f)] if is_array(f)

_field_sort_key(f) := [0, f] if {
	not is_string(f)
	not is_array(f)
}

_field_key_name([1, name]) := name

_field_key_name([2, name]) := name

_field_key_name([0, f]) := _field_name(f)

_field_name(f) := _field_path_name([f]) if is_string(f)

_field_name(f) := _field_path_name(f) if {
	is_array(f)
	is_string(f[count(f) - 1])
}

_field_name(f) := concat(".", [_field_path_name(array.slice(f, 0, count(f) - 1)), _invalid_key_name(f[count(f) - 1])]) if {
	is_array(f)
	not is_string(f[count(f) - 1])
}

_field_name(f) := _invalid_key_name(f) if {
	not is_string(f)
	not is_array(f)
}

_invalid_key_name(k) := concat("", ["<invalid key ", _literal_text(k), ">"])

_has_problems(req, f) if {
	some p in _req_problems(req)
	p[0] == f
}

_required_fields := {
	"range": {"path", "min", "max"},
	"outside_range": {"path", "min", "max"},
	"includes_some": {"path"},
	"not_includes_all": {"path"},
	"lacks_type": {"path", "type"},
	"not_non_empty_string": {"path"},
	"excludes": {"path"},
	"includes": {"path"},
	"in": {"path", "values"},
	"equals": {"path", "value"},
	"present": {"path"},
	"missing": {"path"},
	"non_empty_string": {"path"},
	"empty_string_or_list": {"path"},
	"not_in": {"path", "values"},
	"has_type": {"path", "type"},
	"all_of": {"checks", "assertions"},
	"sentence_any_of": {"checks", "assertions", "option_of"},
	"every": {"path", "check", "whose", "if_any"},
	"for": {"items", "checks", "assertions"},
	"some": {"path", "check", "whose", "if_any"},
	"not_empty_string_or_list": {"path"},
	"matches_any": {"path", "patterns"},
	"not_matches_any": {"path", "patterns"},
	"compare": {"left", "right", "cmp"},
	"compare_time": {"left", "right", "cmp"},
	"all": {"path", "check"},
	"any": {"path", "check"},
	"any_of": {"options"},
}

_flaw(check, names) := "unusable" if {
	_param_broken(check, names)
} else := "unusable" if {
	_unreadable_input
} else := ""

_unreadable_input if data.ergo_unreadable != []

_check_problems(check, names, here) := {[node[1], msg] |
	some node in _static_nodes(check, names)
	some msg in _node_problems(node[0], node[2], node[3], here)
}

_static_nodes(check, names) := _walk_nodes([[check, [], [], names]])

_walk_nodes(l0) := nodes if {
	l1 := _descend(l0)
	l2 := _descend(l1)
	l3 := _descend(l2)
	l4 := _descend(l3)
	l5 := _descend(l4)
	nodes := array.concat(array.concat(array.concat(l0, l1), array.concat(l2, l3)), array.concat(l4, l5))
}

_descend(level) := [[child[0], array.concat(node[1], child[1]), array.concat(node[2], [child[2]]), child[3]] |
	some node in level
	some child in _children(node[0], node[3])
]

_children(node, names) := array.concat(_where_children(node, names), _assertion_children(node, names))

default _assertion_children(_, _) := []

_assertion_children(node, names) := [[c, ["checks", i], "assertion", names] | some i, c in node.checks] if {
	node.op in {"all_of", "sentence_any_of"}
	is_array(node.checks)
}

_assertion_children(node, names) := array.concat([[node.check, ["check"], "assertion", names]], [[c, ["whose", i], "assertion", names] | some i, c in node.whose]) if {
	_walks(node)
	is_object(node.check)
	is_array(node.whose)
}

_assertion_children(node, names) := array.concat([[c, ["checks", i], "assertion", (names | _for_item_names(node.items, count(node.items)))] | some i, c in node.checks], [[c, ["items", i, "whose", j], "assertion", (names | _for_item_names(node.items, i))] | some i, item in node.items; some j, c in item.whose]) if {
	node.op == "for"
	is_array(node.checks)
	is_array(node.items)
}

_for_item_names(items, n) := {item.as | some item in array.slice(items, 0, n); _valid_name(object.get(item, "as", null))}

_walks(check) if check.op in {"every", "some"}

_node_problems(node, _, _, _) := {"invalid check"} if not is_object(node)

_node_problems(node, kinds, names, here) := (_field_problems(node, here) | _name_problems(node, names)) | _derived_placement_problem(node, kinds, here) if {
	is_object(node)
	not _s_unread(node, here)
}

_node_problems(node, _, _, here) := {p | some p in node["$sentence"]} | _wording_problem(node) if _s_unread(node, here)

_field_problems(node, here) := union({_side_problem(node, here), _within_problem(node), _wording_problem(node), _unknown_fields_problem(node, here), _compare_max_problem(node), _missing_fields_problem(node), _range_bounds_problem(node), _range_order_problem(node), _values_problem(node), _value_or_values_problem(node), _patterns_problem(node), _nested_wrapper_problem(node), _cmp_problem(node, here), _out_of_range_problem(node), _refs_problem(node), _json_problem(node)})

_json_problem(node) := _json_problems(object.remove(_own_fields(node), ["meta"]))

_missing_fields_problem(node) := {concat("", ["missing ", f]) |
	is_string(node.op)
	some f in object.get(_required_fields, node.op, set())
	not f in object.keys(node)
}

_value_or_values_problem(node) := {"missing value or values" |
	node.op in _contain_ops
	count({"value", "values"} & object.keys(node)) == 0
} | {"both value and values" |
	node.op in _contain_ops
	count({"value", "values"} & object.keys(node)) == 2
}

_unknown_fields_problem(node, here) := {concat("", ["unknown field ", _text(f)]) |
	node.op in object.keys(_op_fields)
	some f in object.keys(node)
	not f in _op_fields[node.op]
	not f in {"op", "description", "meta", "expression", "inputs"}
	not _sentence_max(f, node, here)
}

_sentence_max("max", node, here) if {
	node.op == "compare"
	_s_read(node, here)
}

_compare_max_problem(node) := ({"invalid max" |
	node.op == "compare"
	"max" in object.keys(node)
	not is_number(node.max)
} | {"max needs cmp gte" |
	node.op == "compare"
	"max" in object.keys(node)
	not object.get(node, "cmp", null) in {"gte", "outside"}
}) | {"max can't go with within" |
	node.op == "compare"
	"max" in object.keys(node)
	"within" in object.keys(node)
}

_wording_problem(node) := (({"invalid description" |
	"description" in object.keys(node)
	not _has_type("description", node.description)
} | {"invalid meta" |
	"meta" in object.keys(node)
	not _has_type("meta", node.meta)
}) | {concat("", ["meta ", p]) |
	"meta" in object.keys(node)
	is_object(node.meta)
	some p in (_meta_problems(node.meta) - {"number out of range", _too_long_problem})
}) | {_too_long_problem |
	"meta" in object.keys(node)
	is_object(node.meta)
	_too_long_problem in _meta_problems(node.meta)
}

_op_fields := object.union(_required_fields, {
	"compare": {"left", "right", "cmp", "within"},
	"excludes": {"path", "value", "values"},
	"includes": {"path", "value", "values"},
	"includes_some": {"path", "values"},
	"not_includes_all": {"path", "values"},
	"all": {"path", "check", "each", "as"},
	"any": {"path", "check", "each", "as"},
	"every": {"path", "check", "whose", "if_any", "distinct"},
	"some": {"path", "check", "whose", "if_any", "distinct"},
})

_range_bounds_problem(node) := {concat("", ["invalid ", f]) |
	node.op == "range"
	some f in ["min", "max"]
	f in object.keys(node)
	v := _written(node[f])
	not is_number(v)
}

_range_order_problem(node) := {"min above max" |
	node.op == "range"
	lo := _written(node.min)
	hi := _written(node.max)
	is_number(lo)
	is_number(hi)
	lo > hi
}

_values_problem(node) := ({"invalid values" |
	node.op in ({"in", "not_in"} | _contain_ops)
	"values" in object.keys(node)
	not _value_list(_written(node.values))
	not is_set(_written(node.values))
	not _is_ref(node.values)
} | {"values of mixed types" |
	node.op in ({"in", "not_in"} | _contain_ops)
	vals := _written(node.values)
	_value_list(vals)
	_mixed_types([_written(w) | some w in vals; not _is_ref(w)])
}) | {"empty values" |
	node.op in _contain_ops
	_value_list(_written(node.values))
	count(_written(node.values)) == 0
}

_patterns_problem(node) := {"invalid patterns" |
	node.op in {"matches_any", "not_matches_any"}
	"patterns" in object.keys(node)
	not _is_ref(node.patterns)
	not is_set(_written(node.patterns))
	not _written_patterns(_written(node.patterns))
}

_written_patterns(v) if {
	_value_list(v)
	every p in v {
		_written_pattern(p)
	}
}

_written_pattern(p) if _valid_pattern(_written(p))

_nested_wrapper_problem(node) := {concat("", [_wrapper(x), " inside ", f]) |
	node.op in _leaf_ops
	some f in ["value", "values", "patterns", "min", "max"]
	f in object.keys(node)
	walk(node[f], [p, x])
	_wrapper(x)
	p != []
	not _under_literal(node[f], p)
} | {concat("", [kind, " inside where"]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some path in _own_paths(node, f)
	some kind in _wrapped_in_where(path)
}

_wrapped_in_where(path) := {_wrapper(x) |
	is_array(path)
	some seg in path
	is_object(seg)
	is_object(object.get(seg, "where", null))
	some w in seg.where
	walk(w, [p, x])
	p != []
	_wrapper(x)
	not _under_literal(w, p)
}

_wrapper(x) := "ref" if _is_ref(x)

_cmp_problem(node, here) := {"invalid cmp" |
	_two_sided(node)
	"cmp" in object.keys(node)
	not node.cmp in {"eq", "ne", "gt", "gte", "lt", "lte"}
	not _sentence_cmp(node, here)
}

_text_cmps := {"starts_with", "ends_with", "not_starts_with", "not_ends_with", "alphabetically_before", "alphabetically_after", "alphabetically_lte", "alphabetically_gte"}

_sentence_cmp(node, here) if {
	node.op == "compare"
	node.cmp in ((_text_cmps | _list_cmps) | {"outside"})
	_s_read(node, here)
}

_out_of_range_problem(node) := {"number out of range" | _out_of_range(_own_fields(node))}

_refs_problem(node) := {"invalid ref" |
	some r in _check_refs(_own_fields(node))
	not _known_ref(r)
}

_known_ref(r) if {
	is_array(r)
	r[0] in {"$$input", "$$input[]", "$$params", "$$params[]"}
	every seg in array.slice(r, 1, count(r)) {
		_is_key(seg)
	}
}

_valid_patterns(v) if {
	_value_list(v)
	every p in v {
		_valid_pattern(p)
	}
}

_own_fields(node) := object.remove(node, ["check", "options"])

_own_paths(node, f) := [node[f]] if {
	f != "inputs"
	f in object.keys(node)
	not _side_field(node, f)
	is_array(node[f])
}

_own_paths(node, f) := _side_paths(node[f]) if _side_field(node, f)

_side_field(node, f) if {
	node.op == "compare"
	f in {"left", "right"}
	f in object.keys(node)
}

_own_paths(node, "inputs") := [p | some spec in node.inputs; some p in _input_paths(spec)] if is_array(node.inputs)

default _own_paths(_, _) := []

_input_paths(spec) := [spec] if not is_object(spec)

_name_problems(node, names) := _unknown_name_problem(node, names)

_unknown_name_problem(node, names) := {concat("", ["unknown alias ", p[0]]) |
	some f in ["path", "left", "right", "each", "inputs"]
	some p in _own_paths(node, f)
	_named(p)
	not _name_known(p[0], names)
}

_name_known(start, _) if start in {"$$input", "$$input[]", "$$params", "$$params[]"}

_name_known(start, _) if start == _root_marker

_name_known(start, names) if {
	_part_start([start])
	_part_of([start]).of == null
	_part_of([start]).alias in names
}

_name_known(start, names) if {
	_part_start([start])
	_part_of([start]).of != null
	_part_of([start]).of in names
}

_name_known(start, names) if {
	not start in {"$$input", "$$input[]", "$$params", "$$params[]"}
	substring(start, 1, -1) in names
}

default _param_broken(_, _) := false

_param_broken(check, names) if {
	some node in _static_nodes(check, names)
	_node_param_broken(node[0])
}

_node_param_broken(node) if {
	node.op in {"in", "not_in"}
	_is_ref(node.values)
	v := _arg(node.values)
	not _value_list(v)
}

_node_param_broken(node) if {
	node.op in ({"in", "not_in"} | _contain_ops)
	vals := _wants(node.values)
	_value_list(vals)
	_mixed_types(vals)
}

_node_param_broken(node) if {
	node.op in _contain_ops
	_is_ref(node.values)
	v := _arg(node.values)
	not _wanted(v)
}

_node_param_broken(node) if {
	node.op in {"matches_any", "not_matches_any"}
	_is_ref(node.patterns)
	v := _arg(node.patterns)
	not _valid_patterns(v)
}

_valid_pattern(p) if {
	is_string(p)
	regex.is_valid(p)
}

default _op_passed(_, _) := false

_op_passed(check, subj) if {
	_leaf_passed(check, subj)
}

_op_passed(check, subj) if {
	_derived_sides(check) != []
	l := _side_value(subj, check.left)
	r := _side_value(subj, check.right)
	_compared(check, l, r, subj)
}
