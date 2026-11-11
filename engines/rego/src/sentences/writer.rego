package ergo

import rego.v1

_s_check_text(parsed) := concat(" and ", [_s_assertion_text(a) | some a in parsed.assertions])

_s_for_line_text(parsed) := concat(", ", [_s_for_item_text(a) | some a in parsed.items])

_s_from_line_text(parsed) := concat("", [_s_every_text(parsed), _s_distinct_text(parsed), _s_path_text(parsed.path, "left"), _s_each_text(parsed), _s_where_text(parsed)])

_s_every_text(parsed) := "every " if object.get(parsed, "every", false) == true

else := ""

_s_each_text(parsed) := concat("", [" named by each of ", _s_path_text(parsed.named_by_each_of, "right")]) if "named_by_each_of" in object.keys(parsed)

_s_each_text(parsed) := "" if not "named_by_each_of" in object.keys(parsed)

_s_for_item_text(item) := concat("", [_s_quantified_text(item), " as ", item.as]) if not "pick" in object.keys(item)

_s_for_item_text(item) := concat("", [_s_distinct_text(item), _s_path_text(item.pick, "left"), _s_where_text(item), _s_sorted_by_text(item), " as ", item.as]) if "pick" in object.keys(item)

_s_sorted_by_text(item) := concat("", [" sorted by ", _s_path_text(item.sorted_by, "left"), _s_alphabetically_text(item)]) if "sorted_by" in object.keys(item)

else := ""

_s_assertion_text(a) := concat(" ", [_s_quantified_text(a), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) != ""

_s_assertion_text(a) := concat(" ", [concat("", [_s_left_text(a), _s_where_text(a)]), _s_phrase_text(a.phrase)]) if _s_quantifier_of(a) == ""

_s_quantified_text(a) := concat("", [_s_quantifier_of(a), " ", _s_distinct_text(a), _s_path_text(a[_s_quantifier_of(a)], "left"), _s_where_text(a), _s_if_any_text(a)])

_s_quantifier_of(a) := "every" if "every" in object.keys(a)

_s_quantifier_of(a) := "some" if "some" in object.keys(a)

_s_quantifier_of(a) := "pick" if "pick" in object.keys(a)

_s_quantifier_of(a) := "" if object.keys(a) & {"every", "some", "pick"} == set()

_s_if_any_text(a) := ", if any," if object.get(a, "if_any", false) == true

_s_if_any_text(a) := "" if not object.get(a, "if_any", false)

_s_where_text(a) := concat("", [" ", concat(" and ", [_s_cond_text(c) | some c in a.where])]) if "where" in object.keys(a)

_s_where_text(a) := "" if not "where" in object.keys(a)

_s_cond_text(c) := concat(" ", ["that", _s_phrase_text(c.phrase)]) if _s_that(c)

_s_cond_text(c) := concat(" ", ["whose", _s_cond_body(c)]) if not _s_that(c)

_s_that(c) if object.get(object.get(c, "path", {}), "that", false) == true

_s_itself(p) if object.get(p, "that", false) == true

_s_cond_body(c) := concat(" ", [_s_left_text(c), _s_phrase_text(c.phrase)]) if _s_quantifier_of(c) == ""

_s_cond_body(c) := concat(" ", [concat("", [_s_quantifier_of(c), " ", _s_distinct_text(c), _s_path_text(c[_s_quantifier_of(c)], "left"), _s_if_any_text(c)]), _s_phrase_text(c.phrase)]) if _s_quantifier_of(c) in {"every", "some"}

_s_left_text(c) := _s_path_text(c.path, "left") if "path" in object.keys(c)

_s_left_text(c) := _s_terms_text(c.terms) if "terms" in object.keys(c)

_s_terms_text(terms) := concat(" plus ", [_s_term_text(t) | some t in terms])

_s_term_text(t) := _json_text(t) if is_number(t)

_s_term_text(t) := concat("", ["count of ", _s_distinct_text(t), _s_path_text(t.count, "left")]) if {
	is_object(t)
	"count" in object.keys(t)
}

_s_term_text(t) := concat("", ["sum of ", _s_distinct_text(t), _s_path_text(t.sum, "left")]) if {
	is_object(t)
	"sum" in object.keys(t)
}

_s_term_text(t) := concat("", [t.unit, " elapsed from ", _s_path_text(t.elapsed_from, "left"), " to ", _s_path_text(t.elapsed_to, "left")]) if {
	is_object(t)
	"elapsed_from" in object.keys(t)
}

_s_term_text(t) := _s_path_text(t, "right") if {
	is_object(t)
	"steps" in object.keys(t)
}

_s_path_text(p, side) := concat("", [_s_position_text(p), _s_start_text(p, side), concat("", [_s_step_text(s) | some s in array.slice(p.steps, _s_first_step(p), count(p.steps))])])

_s_position_text(p) := concat("", ["item ", _json_text(p.position), _s_from_last_text(p), " of "]) if is_number(object.get(p, "position", null))

_s_position_text(p) := concat("", [p.position, " of "]) if is_string(object.get(p, "position", null))

_s_position_text(p) := "" if not "position" in object.keys(p)

_s_from_last_text(p) := " from last" if object.get(p, "from_last", false) == true

else := ""

_s_first_step(p) := 0 if "start" in object.keys(p)

_s_first_step(p) := 1 if not "start" in object.keys(p)

_s_start_text(p, _) := "$params" if object.get(p, "start", "") == "params"

_s_start_text(p, _) := "$input" if object.get(p, "start", "") == "input"

_s_start_text(p, _) := p.start if startswith(object.get(p, "start", ""), "$")

_s_start_text(p, side) := concat("", [_s_start_dot(p, side), _s_start_key(p)]) if not "start" in object.keys(p)

_s_start_key(p) := _json_text(p.steps[0]) if _s_quoted_start(p)

else := _s_key_text(p.steps[0])

_s_quoted_start(p) if {
	p.steps[0] in _s_words
	object.get(p, "dot", false) != true
	object.get(p, "field", false) != true
	not _s_itself(p)
	object.get(p, "part", false) == true
}

_s_quoted_start(p) if {
	p.steps[0] in _s_words
	object.get(p, "dot", false) != true
	object.get(p, "quoted", false) == true
}

_s_quoted_start(p) if {
	p.steps[0] in _s_words
	object.get(p, "dot", false) != true
	object.get(p, "field", false) == true
	object.get(p, "own", false) == true
}

_s_start_dot(p, side) := "." if {
	object.get(p, "field", false) == true
	object.get(p, "own", false) != true
}

else := "." if object.get(p, "kept_dot", false) == true

else := "" if _s_itself(p)

else := "" if _s_quoted_start(p)

else := _s_dot(p.steps[0], side)

_s_dot(key, side) := "." if {
	_s_needs_dot(key, side)
} else := ""

_s_needs_dot(key, _) if key in _s_words

_s_needs_dot(key, "right") if not _s_bare_key(key)

_s_bare_key(key) if regex.match(`^[A-Za-z_][A-Za-z0-9_-]*$`, key)

_s_key_text(key) := key if _s_bare_key(key)

_s_key_text(key) := _json_text(key) if not _s_bare_key(key)

_s_step_text(s) := concat("", [".", _s_key_text(s)]) if is_string(s)

_s_step_text(s) := concat("", [" named by ", _s_ref_text(s.named_by)]) if {
	is_object(s)
	"named_by" in object.keys(s)
}

_s_step_text(s) := concat("", ["[", _json_text(s.index), "]"]) if {
	is_object(s)
	"index" in object.keys(s)
}

_s_ref_text(r) := concat("", ["$", r.start, ".", _s_key_text(r.steps[0])]) if "start" in object.keys(r)

_s_ref_text(r) := r.steps[0] if not "start" in object.keys(r)

_s_phrase_text(ph) := concat(" ", [_s_phrase_words(ph), _s_args_text(ph)]) if _s_args_text(ph) != ""

_s_phrase_text(ph) := _s_phrase_words(ph) if _s_args_text(ph) == ""

_s_phrase_words(ph) := "equals" if {
	ph.op == "is"
	"terms" in object.keys(ph)
}

_s_phrase_words(ph) := "is" if {
	ph.op == "is"
	object.keys(ph) & {"value", "join"} != set()
}

_s_phrase_words(ph) := "does not equal" if {
	ph.op == "is not"
	"terms" in object.keys(ph)
}

_s_phrase_words(ph) := "is not" if {
	ph.op == "is not"
	object.keys(ph) & {"value", "join"} != set()
}

_s_phrase_words(ph) := "is one of" if {
	ph.op == "is one of"
	"values" in object.keys(ph)
}

_s_phrase_words(ph) := "is in" if {
	ph.op == "is one of"
	"path" in object.keys(ph)
}

_s_phrase_words(ph) := "is not one of" if {
	ph.op == "is not one of"
	"values" in object.keys(ph)
}

_s_phrase_words(ph) := "is not in" if {
	ph.op == "is not one of"
	"path" in object.keys(ph)
}

_s_phrase_words(ph) := "is an" if {
	ph.op == "is a"
	ph.type == "object"
}

_s_phrase_words(ph) := "is a" if {
	ph.op == "is a"
	ph.type != "object"
}

_s_phrase_words(ph) := "is not an" if {
	ph.op == "is not a"
	ph.type == "object"
}

_s_phrase_words(ph) := "is not a" if {
	ph.op == "is not a"
	ph.type != "object"
}

_s_phrase_words(ph) := ph.op if not ph.op in {"is", "is not", "is one of", "is not one of", "is a", "is not a"}

_s_args_text(ph) := ph.type if ph.op in {"is a", "is not a"}

_s_args_text(ph) := concat(" and ", [_json_text(ph.min), _json_text(ph.max)]) if ph.op in {"is between", "is not between"}

_s_args_text(ph) := concat(" within ", [_s_operand_text(ph), _json_text(ph.within)]) if "within" in object.keys(ph)

_s_args_text(ph) := _s_operand_text(ph) if {
	not ph.op in {"is a", "is not a", "is between", "is not between"}
	not "within" in object.keys(ph)
}

_s_operand_text(ph) := _s_value_text(ph.value) if "value" in object.keys(ph)

_s_operand_text(ph) := _s_terms_text(ph.terms) if "terms" in object.keys(ph)

_s_operand_text(ph) := concat(" followed by ", [_s_piece_text(piece) | some piece in ph.join]) if "join" in object.keys(ph)

_s_piece_text(piece) := _s_value_text(piece.value) if "value" in object.keys(piece)

_s_piece_text(piece) := _s_terms_text(piece.terms) if "terms" in object.keys(piece)

_s_operand_text(ph) := concat(", ", [_s_value_text(v) | some v in ph.values]) if "values" in object.keys(ph)

_s_operand_text(ph) := _s_path_text(ph.path, "right") if "path" in object.keys(ph)

_s_operand_text(ph) := "" if object.keys(ph) & {"value", "terms", "values", "path", "join"} == set()

_s_value_text(v) := concat("", ["'", v, "'"]) if {
	_s_single_quoted(v)
} else := _json_text(v)

_s_single_quoted(v) if {
	is_string(v)
	contains(v, `\`)
	not contains(v, "'")
	not contains(v, `\\`)
	not endswith(v, `\`)
	regex.match(`^[^\x00-\x1f]*$`, v)
}

_s_from_reads(subjects, parts) := {name: object.union(_s_from_part(name, parts.lines, subjects, {"narrow": parts.narrow, "descend": parts.descend, "parts": parts.effective}), _s_id_part(def)) | some name, def in subjects; is_object(def)} if is_object(subjects)

_s_from_part(name, lines, subjects, chains) := _s_from_read(name, lines[name], subjects, chains) if name in object.keys(lines)

_s_from_part(name, lines, _, _) := {} if not name in object.keys(lines)

_s_id_part(def) := {"identified_by": _s_id_read(def.identified_by)} if is_string(object.get(def, "identified_by", null))

_s_id_part(def) := {} if not is_string(object.get(def, "identified_by", null))

_s_id_read(text) := {"path": _s_model_path(fl.path)} if {
	fl := _from_line(text)
	object.keys(fl) == {"path"}
	count(_s_from_paths_unsupported({"path": fl.path})) == 0
} else := {"problems": [`identified_by is a path, like "id" or "build.number"`]}

_s_from_reads(subjects, _) := {} if not is_object(subjects)

as_sentences(policy) := object.union(object.remove(policy, ["subjects", "requirements"]), object.union(_c_sections(policy), {"ergo_spec": _spec})) if is_object(policy)

as_sentences(policy) := policy if not is_object(policy)

_c_sections(policy) := {f: _c_section(f, policy[f], {"chains": _c_chains(policy), "aliases": _c_aliases(policy)}) | some f in ["subjects", "requirements"]; f in object.keys(policy)}

_c_aliases(policy) := {name: {a | some a, _ in parts} | some name, parts in _p_parts(policy.subjects).effective} if is_object(object.get(policy, "subjects", null))

_c_aliases(policy) := {} if not is_object(object.get(policy, "subjects", null))

_c_chains(policy) := _s_subject_sentences(policy.subjects, _s_from_reads(policy.subjects, _p_parts(policy.subjects)), _p_no_parts).chains if is_object(object.get(policy, "subjects", null))

_c_chains(policy) := {} if not is_object(object.get(policy, "subjects", null))

_c_section("subjects", section, _) := _c_subjects(section) if is_object(section)

_c_section("requirements", section, ctx) := _c_requirements(section, ctx) if is_object(section)

_c_section(_, section, _) := section if not is_object(section)

_c_requirements(reqs, ctx) := {name: _c_requirement(req, ctx) | some name, req in reqs}

_c_requirement(req, ctx) := object.union(object.remove(req, ["checks"]), {"checks": {name: _c_check_of(check, _c_names(req, ctx)) | some name, check in req.checks}}) if {
	is_object(req)
	is_object(object.get(req, "checks", null))
	not object.get(req, "subject", null) in object.keys(ctx.chains)
} else := req

_c_names(req, ctx) := object.get(ctx.aliases, object.get(req, "subject", null), set()) | {x | x := object.get(req, "subject", null); is_string(x)}

_c_check_of(check, aliases) := check if {
	aliases & {x | walk(check, [_, x]); is_string(x)} != set()
} else := _c_check(check)

_c_check(check) := _c_written(check, text) if {
	text := _c_sentence(_c_bare(check))
} else := check

_c_bare(check) := object.remove(check, ["description", "meta"]) if is_object(check)

_c_written(check, text) := text if object.keys(check) & {"description", "meta"} == set()

_c_written(check, text) := object.union(object.filter(check, {"description", "meta"}), {"assert": text}) if object.keys(check) & {"description", "meta"} != set()

_c_sentence(model) := [t | some t in _c_candidates(model); _c_reads_back(t, model)][0]

_c_reads_back(text, model) if {
	parsed := _sentence(text)
	count(parsed.assertions) == 1
	count(_s_unsupported(parsed)) == 0
	_s_line_self(text, set()) == set()
	_s_model(parsed.assertions[0]) == _c_params_walked(model)
}

_c_params_walked(model) := object.union(model, {f: {"ref": array.concat(["$$params[]"], array.slice(model[f].ref, 1, count(model[f].ref)))} |
	some f in ["values", "patterns"]
	_is_ref(object.get(model, f, null))
	model[f].ref[0] == "$$params"
})

_c_path(p) := _path_name(p) if is_array(p)

_c_values(vs) := concat(", ", [_json_text(v) | some v in vs]) if is_array(vs)

_c_values(vs) := _ref_name(vs.ref) if _is_ref(vs)

_c_candidates(m) := [concat("", [_c_path(m.path), " exists"])] if m.op == "present"

_c_candidates(m) := [concat("", [_c_path(m.path), " does not exist"])] if m.op == "missing"

_c_candidates(m) := [concat("", [_c_path(m.path), " is ", _json_text(m.value)])] if m.op == "equals"

_c_candidates(m) := [concat("", [_c_path(m.path), " is a non-empty string"])] if m.op == "non_empty_string"

_c_candidates(m) := [concat("", [_c_path(m.path), " is one of ", _c_values(m.values)]), concat("", [_c_path(m.path), " is in ", _c_values(m.values)])] if m.op == "in"

_c_candidates(m) := [concat("", [_c_path(m.path), " is between ", _json_text(m.min), " and ", _json_text(m.max)])] if m.op == "range"

_c_candidates(m) := [concat("", [_c_path(m.path), " matches ", _c_values(m.patterns)])] if m.op == "matches_any"

_c_candidates(m) := [concat("", [_c_path(m.path), " does not match ", _c_values(m.patterns)])] if m.op == "not_matches_any"

_c_candidates(m) := [concat("", [_c_path(m.path), " contains ", _c_one(m.value)])] if {
	m.op == "includes"
	"value" in object.keys(m)
	not "values" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " contains all of ", _c_values(m.values)])] if {
	m.op == "includes"
	"values" in object.keys(m)
	not "value" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " does not contain ", _c_one(m.value)])] if {
	m.op == "excludes"
	"value" in object.keys(m)
	not "values" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.path), " contains none of ", _c_values(m.values)])] if {
	m.op == "excludes"
	"values" in object.keys(m)
	not "value" in object.keys(m)
}

_c_candidates(m) := [concat("", [_c_path(m.left), " ", _c_compare_words[m.cmp], " ", _c_side(m.right), _c_within(m)])] if {
	m.op == "compare"
	m.cmp in object.keys(_c_compare_words)
}

_c_candidates(m) := [concat("", [_c_path(m.left), " ", _c_time_words[m.cmp], " ", _c_path(m.right)])] if {
	m.op == "compare_time"
	m.cmp in object.keys(_c_time_words)
}

_c_one(v) := _ref_name(v.ref) if _is_ref(v)

_c_one(v) := _json_text(v) if not _is_ref(v)

_c_side(s) := _c_path(s) if is_array(s)

_c_side(s) := _json_text(s.literal) if _basic_form(s) == "literal"

_c_within(m) := concat("", [" within ", _json_text(m.within)]) if "within" in object.keys(m)

_c_within(m) := "" if not "within" in object.keys(m)

_c_compare_words := {"eq": "equals", "ne": "does not equal", "gt": "is more than", "gte": "is at least", "lt": "is less than", "lte": "is at most"}

_c_time_words := {"gt": "is after", "lt": "is before", "gte": "is on or after", "lte": "is on or before"}

_c_subjects(subjects) := {name: _c_subject(name, def, subjects) | some name, def in subjects}

_c_subject(name, def, subjects) := object.union(object.remove(def, ["from", "applies_to", "of"]), object.union({"from": from}, _c_id(def))) if {
	is_object(def)
	from := _c_from_line(name, def, subjects)
} else := def

_c_id(def) := {"identified_by": text} if {
	is_array(object.get(def, "identified_by", null))
	text := _path_name(def.identified_by)
	object.get(_s_id_read(text), "path", null) == def.identified_by
} else := {}

_c_from_line(name, def, subjects) := concat("", [source, _c_whose(conds)]) if {
	not "of" in object.keys(def)
	is_array(def.from)
	source := _c_source(name, def.from, subjects)
	conds := _c_conditions(def)
}

_c_from_line(name, def, subjects) := concat("", [parent, _c_whose(conds)]) if {
	is_string(object.get(def, "of", null))
	not "from" in object.keys(def)
	not "identified_by" in object.keys(def)
	def.of != name
	def.of in object.keys(subjects)
	not startswith(def.of, "$")
	parent := _path_name([def.of])
	fl := _from_line(parent)
	object.keys(fl) == {"path"}
	_s_narrows(name, fl, subjects)
	fl.path.steps == [def.of]
	conds := _c_conditions(def)
}

_c_whose([]) := ""

_c_whose(conds) := concat("", [" ", concat(" and ", [concat(" ", ["whose", c]) | some c in conds])]) if conds != []

_c_conditions(def) := [] if not "applies_to" in object.keys(def)

_c_conditions(def) := conds if {
	is_object(def.applies_to)
	conds := [text |
		some n in sort(object.keys(def.applies_to))
		f := def.applies_to[n]
		is_object(f)
		object.keys(f) & {"description", "meta"} == set()
		text := _c_sentence(f)
	]
	count(conds) == count(def.applies_to)
}

_c_source(_, [], _) := "$input"

_c_source(name, from, subjects) := text if {
	count(from) > 0
	not _c_naming(from[count(from) - 1])
	text := _c_from_path(name, from, subjects)
	_c_from_reads_back(text, from)
}

_c_source(name, from, subjects) := text if {
	count(from) > 1
	step := from[count(from) - 1]
	is_object(step)
	object.keys(step) == {"each_as", "keys"}
	step.each_as == "subject"
	_is_ref(step.keys)
	text := concat("", [_c_from_path(name, array.slice(from, 0, count(from) - 1), subjects), " named by each of ", _ref_name(step.keys.ref)])
	_c_from_reads_back(text, from)
}

_c_naming(step) if {
	is_object(step)
	not _is_ref(step)
}

_c_from_path(name, steps, subjects) := concat("", ["$input.", _steps_name(_from_steps(steps))]) if {
	is_string(steps[0])
	steps[0] != name
	steps[0] in object.keys(subjects)
} else := _steps_name(_from_steps(steps))

_c_from_reads_back(text, from) if {
	fl := _from_line(text)
	object.keys(fl) - {"named_by_each_of"} == {"path"}
	array.concat(_s_from_steps(_s_model_path(fl.path)), _c_each_back(fl, from)) == from
}

_c_each_back(fl, from) := [object.union(from[count(from) - 1], {"keys": {"ref": _s_model_path(fl.named_by_each_of)}})] if "named_by_each_of" in object.keys(fl)

_c_each_back(fl, _) := [] if not "named_by_each_of" in object.keys(fl)
