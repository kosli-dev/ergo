package ergo

import rego.v1

_s_requirements(reqs, chains) := _p_requirements(reqs, chains, _p_no_parts)

_p_requirements(reqs, chains, parts) := {name: _p_requirement(req, chains, parts) | some name, req in reqs} if is_object(reqs)

_p_requirements(reqs, _, _) := reqs if not is_object(reqs)

_p_requirement(req, chains, parts) := object.union(object.remove(req, ["checks"]), {"checks": {name: _subject_marked(req, _rooted(_p_applied_to(check, _s_parent_named(check, _p_written(check, _p_check_aliases(check, aliases, req), _s_parents_of(req, chains), pc), _s_parents_of(req, chains)), pc))) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
	aliases := _p_aliases(req, parts)
	pc := _p_context(req, chains, parts)
} else := req

_root_marker := _p_marker("", -1, null, true)

_subject_marked(req, m) := object.union(m, {"$sentence": [_s_with_subject(p, req) | some p in m["$sentence"]]}) if {
	is_object(m)
	is_array(object.get(m, "$sentence", null))
} else := m

_s_with_subject(p, req) := replace(p, _s_subject_mark, written) if {
	contains(p, _s_subject_mark)
	is_string(object.get(req, "subject", null))
	written := _s_path_text({"steps": [req.subject], "quoted": true}, "left")
	not startswith(written, "\"")
} else := substring(p, 0, indexof(p, ": to read the subject's ")) if contains(p, _s_subject_mark)

else := p

_rooted(m) := object.union(m, {"checks": [_rooted_leaf(c) | some c in m.checks]}) if {
	is_object(m)
	object.get(m, "op", "") in {"all_of", "sentence_any_of", "for"}
	is_array(object.get(m, "checks", null))
} else := _rooted_leaf(m)

_rooted_leaf(m) := object.union(m, {"check": object.union(m.check, {"right": _rooted_side(m.check.right)})}) if {
	is_object(m)
	object.get(m, "op", "") in {"every", "some"}
	is_object(object.get(m, "check", null))
	is_array(object.get(m.check, "right", null))
} else := m

_rooted_side(p) := array.concat([_root_marker], _root_fields(p)) if {
	count(p) > 0
	is_string(p[0])
	not startswith(p[0], "$")
} else := array.concat([_root_marker], _root_fields(p)) if {
	count(p) > 0
	_is_literal(p[0])
	is_string(p[0].literal)
} else := _root_fields(p)

_root_fields(p) := [_root_keyed_step(step) | some step in p]

_root_keyed_step(step) := {"named_by_field": concat("", [_root_key, step.named_by_field])} if _field_step(step)

else := step

_root_read_fields(p) if {
	some step in p
	_field_step(step)
	_from_root(step)
}

_p_check_aliases(check, aliases, req) := aliases | {req.subject} if {
	is_string(object.get(req, "subject", null))
	_s_text_has(json.marshal(check), req.subject)
}

else := aliases

_s_parents_of(req, chains) := {a | some a in _s_ancestors(req.subject, chains)} if {
	is_string(object.get(req, "subject", null))
	req.subject in object.keys(chains)
} else := set()

_s_parent_named(_, model, names) := model if names == set()

_s_parent_named(written, model, _) := model if not _s_written_as_sentence(written)

_s_parent_named(written, model, names) := model if {
	names != set()
	_s_written_as_sentence(written)
	"$sentence" in object.keys(model)
}

_s_parent_named(written, model, names) := _s_named_model(model, names) if {
	names != set()
	_s_written_as_sentence(written)
	not "$sentence" in object.keys(model)
}

_s_named_model(m, names) := object.union(m, {"checks": [_s_named_model_leaf(c, names) | some c in m.checks]}) if m.op in {"all_of", "sentence_any_of"}

_s_named_model(m, names) := object.union(m, {
	"checks": [_s_named_model_leaf(c, names) | some c in m.checks],
	"items": [object.union(item, {"path": _s_named_path(item.path, names), "whose": [_s_named(c, names) | some c in item.whose]}) | some item in m.items],
}) if m.op == "for"

_s_named_model(m, names) := _s_named_model_leaf(m, names) if not m.op in {"all_of", "sentence_any_of", "for"}

_s_named_model_leaf(m, names) := object.union(m, {
	"path": _s_named_path(m.path, names),
	"whose": [_s_named(c, names) | some c in m.whose],
	"check": object.union(_s_named(m.check, names), object.filter(m.check, {"path", "left"})),
}) if m.op in {"every", "some"}

_s_named_model_leaf(m, names) := _s_named(m, names) if not m.op in {"every", "some"}

_s_written_check(check) := _p_written(check, set(), set(), _p_context({}, {}, _p_no_parts))

_p_written(check, aliases, parents, pc) := _s_check_mixed([check], {}, ((_p_named_by_problems([check], "", aliases, object.get(pc, "subject", null)) | _p_part_walk_problems([check], "", pc)) | _p_subject_follow_problems(check, [check], "", pc)), aliases | parents) if is_string(check)

_p_written(check, aliases, parents, pc) := _s_check_mixed(_s_lines(check.assert), object.filter(check, {"description", "meta"}), (((_s_form_problems(check) | _p_named_by_problems(_s_lines(check.assert), "", aliases, object.get(pc, "subject", null))) | _p_part_walk_problems(_s_lines(check.assert), "", pc)) | _p_subject_follow_problems(check, _s_lines(check.assert), "", pc)), aliases | parents) if {
	_s_assert_form(check)
	"assert" in object.keys(check)
	not "for" in object.keys(check)
}

_p_written(check, aliases, parents, pc) := _s_check_for_mixed(_s_lines(check.assert), check.for, object.filter(check, {"description", "meta"}), ((((_s_form_problems(check) | _p_for_clash(check, pc)) | _p_named_by_problems(_s_lines(check.assert), object.get(check, "for", ""), aliases, object.get(pc, "subject", null))) | _p_part_walk_problems(_s_lines(check.assert), check.for, pc)) | _p_subject_follow_problems(check, _s_lines(check.assert), check.for, pc)), aliases | parents) if {
	_s_assert_form(check)
	"assert" in object.keys(check)
	"for" in object.keys(check)
}

_p_written(check, _, _, _) := object.union(object.filter(check, {"description", "meta"}), {"expression": "<missing assert>", "$sentence": sort(_s_form_problems(check))}) if {
	_s_assert_form(check)
	not "assert" in object.keys(check)
}

_p_written(check, aliases, parents, pc) := _s_any_of(check, aliases, aliases | parents, pc) if _s_any_of_form(check)

_s_lines(a) := a if is_array(a)

_s_lines(a) := [a] if not is_array(a)

_p_written(check, _, _, _) := check if not _s_written_as_sentence(check)

_s_written_as_sentence(check) if is_string(check)

_s_written_as_sentence(check) if _s_assert_form(check)

_s_written_as_sentence(check) if _s_any_of_form(check)

_s_any_of_form(check) if {
	is_object(check)
	"any_of" in object.keys(check)
	not "assert" in object.keys(check)
}

_s_any_of(check, aliases, names, pc) := object.union(object.filter(check, {"description", "meta"}), {
	"op": "sentence_any_of",
	"checks": [object.remove(p[0], ["expression"]) | some p in pairs],
	"assertions": [p[1] | some p in pairs],
	"option_of": [p[2] | some p in pairs],
	"expression": _one_of([[_text(nm), _option_text(nm, texts, texts)] | some nm in _names(options); texts := [p[1] | some p in pairs; p[2] == nm]]),
}) if {
	count(_s_any_of_problems(check)) == 0
	options := {nm: _s_check_mixed(_s_lines(o), {}, ((_p_named_by_problems(_s_lines(o), "", aliases, object.get(pc, "subject", null)) | _p_part_walk_problems(_s_lines(o), "", pc)) | _p_subject_follow_problems(o, _s_lines(o), "", pc)), names) | some nm, o in check.any_of}
	every m in options {
		not "$sentence" in object.keys(m)
	}
	pairs := [p | some nm in _names(options); some p in _s_option_lines(options[nm], nm)]
} else := object.union(object.filter(check, {"description", "meta"}), {
	"expression": _s_any_of_written(check.any_of),
	"$sentence": sort(_s_or_unrunnable(_s_any_of_problems(check) | _s_options_problems(check.any_of, aliases, names, pc))),
})

_s_option_lines(m, nm) := [[c, m.assertions[i], nm] | some i, c in m.checks] if m.op == "all_of"

_s_option_lines(m, nm) := [[m, m.expression, nm]] if m.op != "all_of"

_s_any_of_problems(check) := {concat("", ["unknown field ", _text(f)]) | some f in object.keys(check); not f in {"any_of", "description", "meta"}} | _s_options_shape(check.any_of)

_s_options_shape(options) := {"invalid any_of"} if not is_object(options)

_s_options_shape({}) := {"empty any_of"}

_s_options_shape(options) := {m | some nm, o in options; some m in _s_option_messages(nm, o)} if {
	is_object(options)
	options != {}
}

_s_option_messages(nm, _) := {concat("", ["option ", _text(nm), ": ", p]) | some p in _written_name_problems(nm)} if count(_written_name_problems(nm)) > 0

_s_option_messages(nm, o) := {_s_option_shape(nm, o)} if {
	count(_written_name_problems(nm)) == 0
	_s_option_shape(nm, o) != ""
}

_s_option_messages(nm, o) := set() if {
	count(_written_name_problems(nm)) == 0
	_s_option_shape(nm, o) == ""
}

_s_option_shape(nm, o) := concat("", ["empty option ", _text(nm)]) if o == []

else := concat("", ["invalid option ", _text(nm)]) if not _s_option_written(o)

else := ""

_s_option_written(o) if is_string(o)

_s_option_written(o) if {
	is_array(o)
	every line in o {
		is_string(line)
	}
}

_s_options_problems(options, aliases, names, pc) := {concat("", ["option ", _text(nm), ": ", p]) |
	some nm, o in options
	_s_option_written(o)
	o != []
	m := _s_check_mixed(_s_lines(o), {}, ((_p_named_by_problems(_s_lines(o), "", aliases, object.get(pc, "subject", null)) | _p_part_walk_problems(_s_lines(o), "", pc)) | _p_subject_follow_problems(o, _s_lines(o), "", pc)), names)
	some p in object.get(m, "$sentence", [])
} if is_object(options)

else := set()

_s_any_of_written(options) := _one_of([[_text(nm), _s_option_written_text(nm, o)] | some nm, o in options]) if is_object(options)

else := "<invalid any_of>"

_s_option_written_text(nm, o) := _option_text(nm, texts, texts) if {
	_s_option_written(o)
	texts := [_s_written_text(line) | some line in _s_lines(o)]
} else := _option_text(nm, null, [])

_s_assert_form(check) if {
	is_object(check)
	not _s_any_of_form(check)
}

_s_sentences(raw, reqs) := {[reqs[name], c] |
	some name, req in raw
	is_object(req)
	checks := object.get(req, "checks", {})
	is_object(checks)
	some c, check in checks
	_s_written_as_sentence(check)
} if is_object(raw)

else := set()

_s_form_problems(check) := ({concat("", ["unknown field ", _text(f)]) | some f in object.keys(check); not f in {"assert", "description", "meta", "for"}} | _s_assert_problems(check)) | _s_for_problem(check)

_s_assert_problems(check) := _s_assert_problem(check.assert) if "assert" in object.keys(check)

_s_assert_problems(check) := {"missing assert"} if not "assert" in object.keys(check)

_s_for_problem(check) := {"invalid for" | "for" in object.keys(check); not is_string(check.for)}

_s_assert_problem(a) := set() if is_string(a)

_s_assert_problem(a) := {"empty assert"} if a == []

_s_assert_problem(a) := {"invalid assert" | some line in a; not is_string(line)} if {
	is_array(a)
	a != []
}

_s_assert_problem(a) := {"invalid assert"} if {
	not is_string(a)
	not is_array(a)
}

_s_check(lines, wording, problems, parts) := object.union(wording, object.union(model, {"expression": _s_check_text({"assertions": marked})})) if {
	count(problems) == 0
	parsed := [_sentence(line) | some line in lines]
	every p in parsed {
		"assertions" in object.keys(p)
	}
	assertions := [a | some p in parsed; some a in p.assertions]
	count({u | some a in assertions; some u in _s_assertion_unsupported(a)}) == 0
	marked := [_s_aliased(a, _s_names(set(), parts)) | some a in assertions]
	count(_s_self_problems(marked)) == 0
	model := _s_model_of(marked)
} else := object.union(wording, {"expression": concat(" and ", [_s_written_text(line) | some line in lines]), "$sentence": sort(_s_or_unrunnable(((problems | _s_lines_problems(lines)) | _s_lines_self(lines, _s_names(set(), parts)))))})

_s_check_mixed(lines, wording, problems, parts) := m if {
	m := _s_check(lines, wording, problems, parts)
	not "$sentence" in object.keys(m)
	not _s_has_mixed([m])
} else := _s_check(lines, wording, problems | _s_mixed_lines(lines, _s_names(set(), parts)), parts)

_s_check_for_mixed(lines, ftext, wording, problems, parts) := m if {
	m := _s_check_for(lines, ftext, wording, problems, parts)
	not "$sentence" in object.keys(m)
	not _s_has_mixed(array.concat(object.get(m, "checks", []), [c | some item in object.get(m, "items", []); some c in item.whose]))
} else := _s_check_for(lines, ftext, wording, problems | _s_mixed_for(lines, ftext, parts), parts)

_s_has_mixed(models) if {
	some node in _walk_nodes([[m, [], [], set()] | some m in models])
	"values of mixed types" in _values_problem(node[0])
}

_s_lines_self([line], names) := _s_line_self(line, names)

_s_lines_self(lines, names) := {concat("", ["line ", _literal_text(i + 1), ": ", p]) | some i, line in lines; some p in _s_line_self(line, names)} if count(lines) > 1

_s_lines_self([], _) := set()

_s_line_self(line, names) := _s_self_problems([_s_aliased(a, names) | some a in parsed.assertions]) if {
	is_string(line)
	parsed := _sentence(line)
	"assertions" in object.keys(parsed)
} else := _s_self_problems([_s_aliased(a, names) | some a in anyway.assertions]) if {
	is_string(line)
	parsed := _sentence(line)
	count(parsed.problems) > 0
	every p in parsed.problems {
		startswith(p, "unknown name ")
	}
	anyway := _s_parsed_anyway(trim_space(line), _s_patterns)
	"assertions" in object.keys(anyway)
} else := set()

_s_model_of([a]) := _s_model(a)

_s_model_of(assertions) := {"op": "all_of", "checks": models, "assertions": [_s_assertion_text(a) | some a in assertions]} if {
	count(assertions) > 1
	models := [_s_model(a) | some a in assertions]
	count(models) == count(assertions)
}

_s_mixed_lines([line], names) := _s_line_mixed(line, names)

_s_mixed_lines(lines, names) := {concat("", ["line ", _literal_text(i + 1), ": ", p]) | some i, line in lines; some p in _s_line_mixed(line, names)} if count(lines) > 1

_s_mixed_lines([], _) := set()

_s_line_mixed(line, names) := {"values of mixed types" |
	some a in parsed.assertions
	some node in _walk_nodes([[_s_model(_s_aliased(a, names)), [], [], set()]])
	"values of mixed types" in _values_problem(node[0])
} if {
	is_string(line)
	parsed := _sentence(line)
	"assertions" in object.keys(parsed)
} else := set()

_s_mixed_for(lines, ftext, parts) := _s_mixed_lines(lines, _s_names({item.as | some item in fl.items}, parts)) | {"for: values of mixed types" |
	some i, item in _s_marked_items(fl, parts)
	some c in _s_for_item_model(item, {earlier.as | some earlier in array.slice(fl.items, 0, i)}).whose
	some node in _walk_nodes([[c, [], [], set()]])
	"values of mixed types" in _values_problem(node[0])
} if {
	is_string(ftext)
	fl := _for_line(ftext)
	"items" in object.keys(fl)
} else := _s_mixed_lines(lines, _s_names(set(), parts))

_s_lines_problems([line]) := _s_unread_problems(line)

_s_lines_problems(lines) := {concat("", ["line ", _literal_text(i + 1), ": ", p]) | some i, line in lines; some p in _s_unread_problems(line)} if count(lines) > 1

_s_lines_problems([]) := set()

_s_or_unrunnable(problems) := problems if count(problems) > 0

_s_or_unrunnable(problems) := {"can't be run"} if count(problems) == 0

_s_written_text(text) := trim_space(text) if is_string(text)

_s_written_text(text) := "<invalid assert>" if not is_string(text)

_s_unread_problems(text) := set() if not is_string(text)

_s_unread_problems(text) := {p | some p in object.get(parsed, "problems", [])} | _s_unsupported(parsed) if {
	is_string(text)
	parsed := _sentence(text)
}

_s_unread(node, here) if {
	_s_read(node, here)
	count(object.get(node, "$sentence", [])) > 0
}

_s_read(node, true) if is_object(node)

_s_written_here(req, "checks", n) if {
	[req, n] in data.ergo_sentences
} else := false

_s_written_here(req, "applies_to", n) if {
	some m in data.ergo_resolved[req.subject].members
	[m, n] in data.ergo_subject_sentences.filters
} else := false

_s_unsupported(parsed) := set() if not "assertions" in object.keys(parsed)

_s_unsupported(parsed) := {u | some a in parsed.assertions; some u in _s_assertion_unsupported(a)} if "assertions" in object.keys(parsed)

_s_assertion_unsupported(a) := ((((_s_paths_unsupported(a) | _s_argument_unsupported(a.phrase)) | {u | some c in object.get(a, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(a)) | _s_derived_too_long(a)) | {"count of, sum of and plus after every or some aren't supported yet" |
	terms := object.get(a.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
} if object.keys(a) & {"every", "some"} != set()

_s_cond_unsupported(c) := _s_derived_unsupported(c) if "terms" in object.keys(c)

_s_cond_unsupported(c) := _s_argument_unsupported(c.phrase) | _s_derived_too_long(c) if not "terms" in object.keys(c)

_s_walk_too_long(a) := {"every and some over more than ten steps aren't supported yet" | count(_walk_steps(_s_model_path(a[_s_quantifier_of(a)]))) > 10}

_s_assertion_unsupported(a) := _s_derived_unsupported(a) if "terms" in object.keys(a)

_s_derived_unsupported(a) := (_s_paths_unsupported(a) | {u | some c in object.get(a, "where", []); some u in _s_tally_cond_unsupported(c)}) | _s_derived_too_long(a)

_s_derived_too_long(a) := {"every and some over more than ten steps aren't supported yet" |
	some t in _s_nodes(a)
	_s_derived_term(t)
	count(_walk_steps(_s_model_path(object.get(t, "count", object.get(t, "sum", null))))) > 10
}

_s_tally_cond_unsupported(c) := ({"a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	"terms" in object.keys(c)
	not _s_one_elapsed(c.terms)
	not _s_one_count(c.terms)
} | {"a sum of or a plus in the whose of a count of or a sum of isn't supported yet" |
	terms := object.get(c.phrase, "terms", [])
	terms != []
	not _s_one_path(terms)
	not _s_one_elapsed(terms)
	not _s_one_count(terms)
}) | _s_argument_unsupported(c.phrase)

_s_one_count(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"count" in object.keys(terms[0])
}

_s_one_elapsed(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"elapsed_from" in object.keys(terms[0])
}

_s_assertion_unsupported(a) := (_s_paths_unsupported(a) | _s_argument_unsupported(a.phrase)) | _s_derived_too_long(a) if object.keys(a) & {"every", "some", "terms"} == set()

_s_model(a) := _s_leaf_model(a) if _s_quantifier_of(a) == ""

_s_model(a) := object.union(
	{
		"op": q,
		"path": _s_model_path(a[q]),
		"check": _s_leaf_model(object.union(object.remove(a, ["every", "some", "where", "if_any"]), {"path": {"steps": ["x"]}})),
		"whose": [_s_leaf_model(c) | some c in object.get(a, "where", [])],
		"if_any": object.get(a, "if_any", false),
	},
	_s_distinct_of_node(a),
) if {
	q := _s_quantifier_of(a)
	q != ""
}

_s_paths_unsupported(a) := ({`last of isn't supported yet here: pick the item on a for line, like "for: last of commits as commit"` |
	some node in _s_nodes(a)
	is_object(node)
	_s_from_last(node)
} | _s_elapsed_unsupported(a)) | _s_join_unsupported(a)

_s_join_unsupported(a) := set() if not _s_joins(a)

_s_join_unsupported(a) := {`"followed by" isn't supported yet after every or some, or in a whose` |
	_s_joins(a)
	some node in _s_nodes(a)
	is_object(node)
	"join" in object.keys(node)
	_s_join_misplaced(a, node)
}

_s_join_misplaced(a, _) if object.keys(a) & {"every", "some"} != set()

_s_join_misplaced(a, node) if node in _s_nodes(object.get(a, "where", []))

_s_from_last(node) if object.get(node, "position", null) == "last"

_s_from_last(node) if object.get(node, "from_last", false) == true

_s_elapsed_unsupported(a) := _s_elapsed_flaw(_s_whose_stripped(_s_without_terms(a)))

_s_elapsed_flaw(x) := {"an elapsed time isn't supported yet after every or some, or in a from line" |
	some node in _s_nodes(x)
	is_object(node)
	"elapsed_from" in object.keys(node)
}

_s_whose_stripped(a) := object.union(object.remove(a, ["where"]), {"where": [_s_cond_stripped(c) | some c in a.where]}) if "where" in object.keys(a)

_s_whose_stripped(a) := a if not "where" in object.keys(a)

_s_cond_stripped(c) := object.union(object.remove(c, ["terms", "phrase"]), {"phrase": object.remove(c.phrase, ["terms"])})

_s_without_terms(a) := object.union(object.remove(a, ["terms", "phrase"]), {"phrase": object.remove(a.phrase, ["terms"])}) if {
	"phrase" in object.keys(a)
	object.keys(a) & {"every", "some"} == set()
}

_s_without_terms(a) := a if not _s_stripped(a)

_s_stripped(a) if {
	"phrase" in object.keys(a)
	object.keys(a) & {"every", "some"} == set()
}

_s_from_paths_unsupported(a) := _s_paths_unsupported(a) | {concat("", ["unknown alias ", ref.steps[0]]) |
	some node in _s_nodes(a)
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
}

_s_argument_unsupported(ph) := {concat("", [`"`, _s_phrase_words(ph), `" can't take a count of, a sum of or a plus`])} if {
	terms := object.get(ph, "terms", [])
	terms != []
	not _s_one_path(terms)
	not ph.op in object.keys(_s_derived_cmps)
}

default _s_argument_unsupported(_) := set()

_s_one_path(terms) if {
	count(terms) == 1
	is_object(terms[0])
	"steps" in object.keys(terms[0])
}

_s_list_ops := {"is one of", "is not one of", "contains", "does not contain", "contains all of", "contains none of", "contains some of", "does not contain all of", "matches", "does not match"}

_s_list_path(ph) := ph.path if "path" in object.keys(ph)

_s_list_path(ph) := ph.terms[0] if {
	"terms" in object.keys(ph)
	_s_one_path(ph.terms)
}

_s_takes := object.union({op: "a time or a number" | some op, _ in _s_time_cmps}, {op: "a number" | some op, _ in _s_order_cmps})

_s_takes_value(op, v) if {
	op in object.keys(_s_time_cmps)
	_s_time_value(v)
}

_s_takes_value(op, v) if {
	op in object.keys(_s_order_cmps)
	is_number(v)
}

_s_takes_value(_, v) if {
	is_object(v)
	"out_of_range" in object.keys(v)
}

_s_takes_value(_, v) if {
	is_object(v)
	"too_long" in object.keys(v)
}

_s_time_value(v) if is_number(v)

_s_time_value(v) if _rfc3339_shaped(v)

_s_time_value(v) if _date_shaped(v)

_s_time_cmps := {"is before": "lt", "is after": "gt", "is on or after": "gte", "is on or before": "lte"}

_s_order_cmps := {"is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

_s_leaf_model(a) := object.union({"op": "compare", "left": _s_left_side(a.terms, object.get(a, "where", [])), "cmp": _s_derived_cmps[a.phrase.op], "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within", "max"})) if "terms" in object.keys(a)

_s_leaf_model(a) := _s_plain_model(a) if not "terms" in object.keys(a)

_s_cond_model(c) := _s_plain_model(c) if not "terms" in object.keys(c)

_s_cond_model(c) := object.union({"op": "compare", "left": _s_bare_side(c.terms), "cmp": _s_derived_cmps[c.phrase.op], "right": _s_side(c.phrase)}, object.filter(c.phrase, {"within", "max"})) if "terms" in object.keys(c)

_s_derived_cmps := {"is between": "gte", "is not between": "outside", "is": "eq", "is not": "ne", "is at least": "gte", "is at most": "lte", "is more than": "gt", "is less than": "lt"}

_s_plain_model(a) := {"op": "equals", "path": _s_model_path(a.path), "value": a.phrase.value} if {
	a.phrase.op == "is"
	"value" in object.keys(a.phrase)
	not "within" in object.keys(a.phrase)
}

_s_plain_model(a) := object.union({"op": "compare", "left": _s_model_path(a.path), "cmp": "eq", "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within"})) if {
	a.phrase.op == "is"
	_s_side_given(a.phrase)
}

_s_plain_model(a) := object.union({"op": "compare", "left": _s_model_path(a.path), "cmp": "ne", "right": _s_side(a.phrase)}, object.filter(a.phrase, {"within"})) if a.phrase.op == "is not"

_s_plain_model(a) := {"op": _s_compare_ops[a.phrase.op][0], "left": _s_model_path(a.path), "cmp": _s_compare_ops[a.phrase.op][1], "right": _s_side(a.phrase)} if a.phrase.op in object.keys(_s_compare_ops)

_s_plain_model(a) := {"op": "in", "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op == "is one of"
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "has_type", "path": _s_model_path(a.path), "type": a.phrase.type} if a.phrase.op == "is a"

_s_plain_model(a) := {"op": "lacks_type", "path": _s_model_path(a.path), "type": a.phrase.type} if a.phrase.op == "is not a"

_s_plain_model(a) := {"op": "not_non_empty_string", "path": _s_model_path(a.path)} if a.phrase.op == "is not a non-empty string"

_s_plain_model(a) := {"op": "not_in", "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op == "is not one of"
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "present", "path": _s_model_path(a.path)} if a.phrase.op == "exists"

_s_plain_model(a) := {"op": "missing", "path": _s_model_path(a.path)} if a.phrase.op == "does not exist"

_s_plain_model(a) := {"op": "non_empty_string", "path": _s_model_path(a.path)} if a.phrase.op == "is a non-empty string"

_s_plain_model(a) := {"op": "empty_string_or_list", "path": _s_model_path(a.path)} if a.phrase.op == "is empty"

_s_plain_model(a) := {"op": "not_empty_string_or_list", "path": _s_model_path(a.path)} if a.phrase.op == "is not empty"

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "value": _s_one(a.phrase)} if {
	a.phrase.op in {"contains", "does not contain"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "compare", "left": _s_model_path(a.path), "cmp": _s_list_cmps[a.phrase.op], "right": _s_side(a.phrase)} if {
	a.phrase.op in {"contains", "does not contain"}
	"join" in object.keys(a.phrase)
}

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "values": _s_list(a.phrase)} if {
	a.phrase.op in {"contains all of", "contains none of", "contains some of", "does not contain all of"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": _s_contains_ops[a.phrase.op], "path": _s_model_path(a.path), "patterns": _s_list(a.phrase)} if {
	a.phrase.op in {"matches", "does not match"}
	not _s_field_arg(a.phrase)
}

_s_plain_model(a) := {"op": "compare", "left": _s_model_path(a.path), "cmp": _s_list_cmps[a.phrase.op], "right": _s_model_path(_s_list_path(a.phrase))} if _s_field_arg(a.phrase)

_s_field_arg(ph) if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	not "start" in object.keys(p)
}

_s_field_arg(ph) if _s_named_arg(ph)

_s_named_arg(ph) if {
	ph.op in _s_list_ops
	p := _s_list_path(ph)
	"start" in object.keys(p)
	some s in p.steps
	is_object(s)
	"named_by" in object.keys(s)
}

_s_list_cmps := {
	"is one of": "in",
	"is not one of": "not_in",
	"contains": "includes",
	"does not contain": "excludes",
	"contains all of": "includes_all",
	"contains none of": "excludes_all",
	"contains some of": "includes_some",
	"does not contain all of": "not_includes_all",
	"matches": "matches_any",
	"does not match": "not_matches_any",
}

_s_plain_model(a) := {"op": "range", "path": _s_model_path(a.path), "min": a.phrase.min, "max": a.phrase.max} if a.phrase.op == "is between"

_s_plain_model(a) := {"op": "outside_range", "path": _s_model_path(a.path), "min": a.phrase.min, "max": a.phrase.max} if a.phrase.op == "is not between"

_s_compare_ops := object.union(
	object.union({op: ["compare", cmp] | some op, cmp in _s_order_cmps}, {op: ["compare_time", cmp] | some op, cmp in _s_time_cmps}),
	{"starts with": ["compare", "starts_with"], "ends with": ["compare", "ends_with"], "does not start with": ["compare", "not_starts_with"], "does not end with": ["compare", "not_ends_with"], "is alphabetically before": ["compare", "alphabetically_before"], "is alphabetically after": ["compare", "alphabetically_after"], "is alphabetically on or before": ["compare", "alphabetically_lte"], "is alphabetically on or after": ["compare", "alphabetically_gte"]},
)

_s_contains_ops := {
	"contains": "includes",
	"does not contain": "excludes",
	"contains all of": "includes",
	"contains none of": "excludes",
	"contains some of": "includes_some",
	"does not contain all of": "not_includes_all",
	"matches": "matches_any",
	"does not match": "not_matches_any",
}

_s_side_given(ph) if "terms" in object.keys(ph)

_s_side_given(ph) if "within" in object.keys(ph)

_s_side_given(ph) if "join" in object.keys(ph)

_s_side(ph) := {"literal": ph.value} if "value" in object.keys(ph)

_s_side(ph) := {"literal": ph.min} if ph.op in {"is between", "is not between"}

_s_side(ph) := _s_bare_side(ph.terms) if "terms" in object.keys(ph)

_s_side(ph) := {"join": [_s_piece_side(piece) | some piece in ph.join], "text": _s_operand_text(ph)} if "join" in object.keys(ph)

_s_piece_side(piece) := {"literal": piece.value} if "value" in object.keys(piece)

_s_piece_side(piece) := _s_bare_side(piece.terms) if "terms" in object.keys(piece)

_s_bare_side([t]) := _s_term_side(t)

_s_bare_side(terms) := {"add": [_s_term_side(t) | some t in terms], "text": _s_terms_text(terms)} if count(terms) > 1

_s_left_side(terms, []) := _s_bare_side(terms)

_s_left_side(terms, where) := _s_whose_side(terms[0], where) if {
	where != []
	count(terms) == 1
}

_s_left_side(terms, where) := {"add": array.concat([_s_term_side(t) | some t in array.slice(terms, 0, count(terms) - 1)], [_s_whose_side(terms[count(terms) - 1], where)]), "text": concat("", [_s_terms_text(terms), _s_where_text({"where": where})])} if {
	where != []
	count(terms) > 1
}

_s_whose_side(t, where) := object.union(_s_term_side(t), {"whose": [_s_cond_model(c) | some c in where], "text": concat("", [_s_term_text(t), _s_where_text({"where": where})])})

_s_term_side(t) := {"literal": t} if is_number(t)

_s_term_side(t) := {"unit": t.unit, "elapsed_from": _s_model_path(t.elapsed_from), "elapsed_to": _s_model_path(t.elapsed_to), "text": _s_term_text(t)} if {
	is_object(t)
	"elapsed_from" in object.keys(t)
}

_s_term_side(t) := _s_model_path(t) if {
	is_object(t)
	"steps" in object.keys(t)
}

_s_term_side(t) := object.union({concat("", [k, "_of"]): _s_model_path(t[k]), "whose": [], "text": _s_term_text(t)}, _s_distinct_of_node(t)) if {
	is_object(t)
	some k in ["count", "sum"]
	k in object.keys(t)
}

_s_one(ph) := ph.value if "value" in object.keys(ph)

_s_one(ph) := {"ref": _s_model_path(ph.terms[0])} if "terms" in object.keys(ph)

_s_list(ph) := ph.values if "values" in object.keys(ph)

_s_list(ph) := {"ref": _s_walked(_s_model_path(ph.path))} if "path" in object.keys(ph)

_s_walked(p) := array.concat(["$$input[]"], array.slice(p, 1, count(p))) if p[0] == "$$input"

else := array.concat(["$$params[]"], array.slice(p, 1, count(p))) if p[0] == "$$params"

else := p

_s_model_path(p) := array.concat(array.concat(_s_model_start(p), [_s_model_step(s) | some s in array.slice(p.steps, _s_first_step(p), count(p.steps))]), _s_model_position(p))

_s_model_start(p) := [concat("", ["$$", p.start])] if "start" in object.keys(p)

_s_model_start(p) := [] if {
	not "start" in object.keys(p)
	_s_itself(p)
}

_s_model_start(p) := [concat("", ["$", p.steps[0]])] if {
	not "start" in object.keys(p)
	not _s_itself(p)
	object.get(p, "alias", false) == true
}

_s_model_start(p) := [{"literal": p.steps[0]}] if {
	not "start" in object.keys(p)
	not _s_itself(p)
	object.get(p, "alias", false) != true
	_s_literal_start(p)
}

_s_model_start(p) := [p.steps[0]] if {
	not "start" in object.keys(p)
	not _s_itself(p)
	object.get(p, "alias", false) != true
	not _s_literal_start(p)
}

_s_literal_start(p) if {
	startswith(p.steps[0], "$")
	object.get(p, "part", false) != true
}

_s_literal_start(p) if object.get(p, "field", false) == true

_s_model_step(s) := s if is_string(s)

_s_model_step(s) := s.index if {
	is_object(s)
	is_number(object.get(s, "index", null))
}

_s_model_step(s) := {"ref": [concat("", ["$$", s.named_by.start]), s.named_by.steps[0]]} if {
	is_object(s)
	"named_by" in object.keys(s)
	"start" in object.keys(s.named_by)
}

_s_model_step(s) := {"named_by_field": s.named_by.steps[0]} if {
	is_object(s)
	"named_by" in object.keys(s)
	not "start" in object.keys(s.named_by)
}

_s_model_position(p) := [p.position - 1] if is_number(object.get(p, "position", null))

_s_model_position(p) := [0] if object.get(p, "position", null) == "first"

_s_model_position(p) := [0] if object.get(p, "position", null) == "last"

_s_model_position(p) := [] if not "position" in object.keys(p)

_s_marked_items(fl, parts) := [_s_sort_marked(_s_aliased_item(item, _s_names({earlier.as | some earlier in array.slice(fl.items, 0, i)}, parts)), _s_names({i.as | some i in fl.items}, parts)) | some i, item in fl.items]

_s_sort_marked(item, names) := object.union(object.remove(item, ["sorted_by"]), {"sorted_by": _s_marked(item.sorted_by, names, false)}) if "sorted_by" in object.keys(item)

else := item

_s_for_self(lines, ftext, parts) := _s_lines_self(lines, _s_names({item.as | some item in fl.items}, parts)) | {concat("", ["for: ", p]) | some p in _s_whose_self_problems(_s_marked_items(fl, parts))} if {
	is_string(ftext)
	fl := _for_line(ftext)
	"items" in object.keys(fl)
} else := set()

_s_for_written_text(lines, ftext) := concat("", ["for ", trim_space(ftext), ": ", concat(" and ", [_s_written_text(line) | some line in lines])]) if is_string(ftext)

_s_for_written_text(lines, ftext) := concat(" and ", [_s_written_text(line) | some line in lines]) if not is_string(ftext)

_s_for_problems(lines, ftext) := {concat("", ["for: ", p]) | some p in object.get(_for_line(ftext), "problems", [])} | _s_for_line_unsupported(lines, ftext) if is_string(ftext)

_s_for_problems(lines, ftext) := _s_lines_problems(lines) if not is_string(ftext)

_s_for_line_unsupported(lines, ftext) := _s_lines_problems(lines) if not "items" in object.keys(_for_line(ftext))

_s_for_line_unsupported(lines, ftext) := {concat("", ["for: ", u]) | some u in _s_for_unsupported(fl, [])} | _s_lines_problems(lines) if {
	fl := _for_line(ftext)
	"items" in object.keys(fl)
}

_s_for_unsupported(fl, assertions) := ({u | some item in fl.items; some u in _s_item_unsupported(item)} | {u | some a in assertions; some u in _s_assertion_unsupported(a)}) | {u | some i, item in fl.items; some u in _s_names_not_given(item, {later.as | some later in array.slice(fl.items, i, count(fl.items))})}

_s_names_not_given(x, later) := {concat("", ["unknown alias ", ref.steps[0]]) |
	some node in _s_nodes(x)
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
	ref.steps[0] in later
}

_s_item_unsupported(item) := (_s_paths_unsupported(_s_unpicked(item)) | {u | some c in object.get(item, "where", []); some u in _s_cond_unsupported(c)}) | _s_walk_too_long(_s_unpicked(item))

_s_unpicked(item) := object.union(object.remove(item, ["pick"]), {"pick": object.remove(item.pick, ["position", "from_last"])}) if "pick" in object.keys(item)

else := item

_s_for_item_model(item, names) := object.union(
	{
		"q": q,
		"path": _s_named_path(_s_model_path(item[q]), names),
		"whose": [_s_named(_s_leaf_model(c), names) | some c in object.get(item, "where", [])],
		"if_any": object.get(item, "if_any", false),
		"as": item.as,
	},
	_s_distinct_of_node(item),
) if {
	q := _s_quantifier_of(item)
	q != "pick"
}

_s_for_item_model(item, names) := {
	"q": "every",
	"path": _s_named_path(_s_model_path(_s_unpicked(item).pick), names),
	"whose": [_s_named(_s_leaf_model(c), names) | some c in object.get(item, "where", [])],
	"if_any": false,
	"as": item.as,
	"pick": object.union({"at": _s_pick_at(item.pick.position), "from_last": _s_picks_from_last(item.pick)}, object.union({"by": _s_model_path(item.sorted_by) | "sorted_by" in object.keys(item)}, {"alphabetically": true | object.get(item, "alphabetically", false) == true})),
} if "pick" in object.keys(item)

_s_pick_at(n) := n if is_number(n)

_s_pick_at(n) := 1 if n in {"first", "last"}

_s_picks_from_last(p) if p.position == "last"

else := object.get(p, "from_last", false)

_s_named(m, names) := object.union(object.union(m, {f: _s_named_side(m[f], names) | some f in ["path", "left", "right"]; f in object.keys(m)}), {"inputs": [_s_named_side(i, names) | some i in m.inputs] | is_array(object.get(m, "inputs", null))})

_s_named_side(side, names) := _s_named_path(side, names) if is_array(side)

_s_named_side(side, names) := object.union(side, {"add": [_s_named_tally(o, names) | some o in side.add]}) if {
	is_object(side)
	"add" in object.keys(side)
}

_s_named_side(side, names) := object.union(side, {"join": [_s_named_tally(o, names) | some o in side.join]}) if {
	is_object(side)
	"join" in object.keys(side)
}

_s_named_side(side, names) := _s_named_tally(side, names) if {
	is_object(side)
	not "add" in object.keys(side)
	not "join" in object.keys(side)
}

_s_named_tally(side, names) := _s_named_path(side, names) if is_array(side)

_s_named_tally(side, names) := object.union(side, {f: _s_named_path(side[f], names), "whose": [_s_named_cond(c, names) | some c in side.whose]}) if {
	is_object(side)
	some f in ["count_of", "sum_of"]
	f in object.keys(side)
}

_s_named_tally(side, names) := object.union(side, {f: _s_named_path(side[f], names) | some f in ["elapsed_from", "elapsed_to"]}) if {
	is_object(side)
	"elapsed_from" in object.keys(side)
}

_s_named_tally(side, _) := side if {
	is_object(side)
	object.keys(side) & {"count_of", "sum_of", "elapsed_from"} == set()
}

_s_named_cond(c, names) := object.union(object.union(c, {f: _s_named_path(c[f], names) | some f in ["path", "left", "right"]; is_array(object.get(c, f, null))}), {"right": _s_named_right(c.right, names) | is_object(object.get(c, "right", null))})

_s_named_right(side, names) := object.union(side, {f: _s_named_path(side[f], names) | some f in ["count_of", "sum_of", "elapsed_from", "elapsed_to"]; is_array(object.get(side, f, null))})

_s_named_path(p, names) := [_s_named_step(i, step, names) | some i, step in p]

_s_named_step(i, step, names) := concat("", ["$", step]) if {
	i == 0
	is_string(step)
	step in names
} else := {"named_by": step.named_by_field} if {
	_field_step(step)
	step.named_by_field in names
} else := step
