package ergo

import rego.v1

_p_alias_ok(alias) if {
	is_string(alias)
	regex.match(`^[A-Za-z_][A-Za-z0-9_-]*$`, alias)
	not _s_bad_name(alias)
}

_p_own_reads(subjects) := {name: {alias: _p_part_read(alias, entry) | some alias, entry in def.has} |
	some name, def in subjects
	is_object(def)
	is_object(object.get(def, "has", null))
} if is_object(subjects)

_p_part_read(alias, entry) := {"from": from, "identified_by": id, "problems": sort(problems)} if {
	from := _p_field_read(entry, "from")
	id := _p_field_read(entry, "identified_by")
	problems := ((_p_alias_problems(alias) | _p_shape_problems(entry)) | _p_prefixed("from", from)) | _p_prefixed("identified_by", id)
}

_p_alias_problems(alias) := _written_name_problems(alias) if count(_written_name_problems(alias)) > 0

_p_alias_problems(alias) := {"invalid alias" | not _p_alias_ok(alias)} if count(_written_name_problems(alias)) == 0

_p_shape_problems(entry) := {"not a string or an object"} if {
	not is_string(entry)
	not is_object(entry)
}

_p_shape_problems(entry) := ({concat("", ["unknown field ", _text(f)]) | some f in object.keys(entry); not f in {"from", "identified_by"}} | {"missing from" | not "from" in object.keys(entry)}) | {concat("", ["invalid ", f]) | some f in ["from", "identified_by"]; f in object.keys(entry); not is_string(entry[f])} if is_object(entry)

_p_shape_problems(entry) := set() if is_string(entry)

_p_prefixed(f, read) := {concat("", [f, ": ", p]) |
	is_object(read)
	some p in object.get(read, "problems", [])
}

_p_field_read(entry, "from") := _p_path_read(entry) if is_string(entry)

_p_field_read(entry, f) := _p_path_read(entry[f]) if {
	is_object(entry)
	is_string(object.get(entry, f, null))
}

_p_field_read(entry, f) := {} if {
	is_object(entry)
	f in object.keys(entry)
	not is_string(entry[f])
}

_p_field_read(entry, "identified_by") := null if {
	is_object(entry)
	not "identified_by" in object.keys(entry)
}

_p_field_read(entry, "identified_by") := null if is_string(entry)

_p_field_read(entry, "from") := {} if {
	not is_string(entry)
	not is_object(entry)
}

_p_field_read(entry, "identified_by") := null if {
	not is_string(entry)
	not is_object(entry)
}

_p_field_read(entry, "from") := {} if {
	is_object(entry)
	not "from" in object.keys(entry)
}

_p_path_read(text) := {"path": path, "text": _path_name(path)} if {
	fl := _from_line(text)
	count(_p_path_problems(fl)) == 0
	path := _s_model_path(fl.path)
}

_p_path_read(text) := {"problems": sort(_p_path_problems(_from_line(text)))} if count(_p_path_problems(_from_line(text))) > 0

_p_path_problems(fl) := {p | some p in object.get(fl, "problems", ["doesn't parse"])} if not "path" in object.keys(fl)

_p_path_problems(fl) := ({"a part is a path: whose and named by each of can't go in it" | object.keys(fl) != {"path"}} | {"a part reads inside its subject, so it can't start at $params or $input" | "start" in object.keys(fl.path)}) | _s_from_paths_unsupported({"path": fl.path}) if "path" in object.keys(fl)

_p_valid(read) if {
	read.problems == []
	"path" in object.keys(read.from)
}

_p_lines(subjects) := {name: _from_line(def.from) | some name, def in subjects; is_object(def); is_string(def.from)}

_p_narrow(subjects, lines) := {name: _s_chain_parent(name, lines, subjects) | some name, _ in subjects}

_p_descend(subjects, lines) := {name: lines[name].path.steps[0] | some name, _ in lines; "path" in object.keys(lines[name]); _s_descends(name, lines[name], subjects)}

_p_parts(subjects) := {"own": own, "effective": {name: _p_merged(name, own, narrow) | some name, _ in subjects}, "problems": _p_problems(subjects, own, narrow, descend), "lines": lines, "narrow": narrow, "descend": descend} if {
	is_object(subjects)
	lines := _p_lines(subjects)
	read := {name: object.get(line, "parsed", line) | some name, line in lines}
	narrow := _p_narrow(subjects, read)
	descend := _p_descend(subjects, read)
	own := _p_own_reads(subjects)
}

_p_parts(subjects) := _p_no_parts if not is_object(subjects)

_p_members(name, narrow) := graph.reachable(narrow, [name])

_p_merged(name, own, narrow) := {a: own[_p_owner(a, members, own)][a] | some a in {a | some m in members; some a, _ in object.get(own, m, {})}} if members := sort(_p_members(name, narrow))

_p_owner(a, members, own) := [m | some m in members; a in object.keys(object.get(own, m, {}))][0]

_p_problems(subjects, own, narrow, descend) := {name: probs |
	some name, def in subjects
	is_object(def)
	probs := _p_subject_problems(name, def, own, narrow, descend, subjects)
	count(probs) > 0
}

_p_subject_problems(name, def, own, narrow, descend, subjects) := (({[["has"], "not an object"] | "has" in object.keys(def); not is_object(def.has)} | {[["has", alias], p] | some alias, read in object.get(own, name, {}); some p in read.problems}) | {[["has", alias], concat("", [alias, " can't be an alias: it's a subject's name"])] |
	some alias, _ in object.get(own, name, {})
	alias in object.keys(subjects)
}) | {[["has", alias], concat("", [alias, " can't be an alias: it's a part of ", _p_name_text(declarer)])] |
	some alias, _ in object.get(own, name, {})
	some owner in _p_part_owners(name, narrow, descend)
	some declarer in _p_members(owner, narrow)
	alias in object.keys(object.get(own, declarer, {}))
}

_p_name_text(name) := _s_key_text(name)

_p_part_owners(name, narrow, descend) := ({m | some m in _p_members(name, narrow); m != name} | {a | a := descend[name]}) | {a | a := descend[descend[name]]}

_s_subjects(subjects, reads, parts) := {name: _s_subject(name, def, reads, parts) | some name, def in subjects} if is_object(subjects)

_s_subjects(subjects, _, _) := subjects if not is_object(subjects)

_s_subject(name, null, _, _) := {"from": [name]}

_s_subject(name, def, reads, parts) := object.union(_s_without_narrowed_from(_p_old_filters(def, _p_own_context(name, parts.effective)), reads[name]), object.union(_s_from_fields(name, def, reads), _s_id_field(reads[name]))) if is_object(def)

_s_without_narrowed_from(def, read) := object.remove(def, ["from"]) if {
	"of" in object.keys(object.get(read, "fields", {}))
	_s_from_used(def, read)
} else := def

_s_subject(_, def, _, _) := def if {
	def != null
	not is_object(def)
}

_s_from_fields(name, def, reads) := {"from": [name]} if {
	not "from" in object.keys(def)
	not "of" in object.keys(def)
} else := reads[name].fields if {
	_s_from_used(def, reads[name])
} else := {}

_s_from_used(def, read) if {
	is_string(def.from)
	read.problems == []
	not "applies_to" in object.keys(def)
	not "of" in object.keys(def)
}

_s_from_read(name, fl, subjects, chains) := _s_from_read_of(name, fl, subjects, chains) if "path" in object.keys(fl)

else := object.union(r, {"problems": sort(names | ({p | some p in r.problems} - {concat("", ["whose: ", n]) | some n in names}))}) if {
	r := _s_from_read_of(name, fl.parsed, subjects, chains)
	"parent" in object.keys(r)
	names := {n | some n in fl.problems}
}

else := {"problems": object.get(fl, "problems", ["doesn't parse"]), "fields": {}}

_s_from_read_of(name, fl, subjects, chains) := object.union(object.union({"problems": problems, "fields": fields, "parent": parent, "every": every_list, "distinct": object.get(fl, "distinct", false) == true}, _p_from_part(name, fl, subjects, chains.parts)), _s_follows(name, fl, subjects, chains)) if {
	"path" in object.keys(fl)
	names := {a | some a in _s_ancestors(name, chains.descend)}
	keep := names | object.keys(object.get(chains.parts, name, {}))
	pc := {"own": _p_steps_of(object.get(chains.parts, name, {})), "ancestors": {a: _p_steps_of(object.get(chains.parts, a, {})) | some a in names}}
	conds := [_s_from_filter(name, c, names, keep, pc) | some c in object.get(fl, "where", [])]
	problems := sort((((((((((_s_chain_unsupported(name, fl, subjects, chains) | _s_loop(name, fl, subjects, chains)) | _s_blank_start(fl, subjects)) | _s_every_unsupported(name, fl, subjects)) | _s_from_start_problems(fl)) | _s_from_paths_unsupported({"path": fl.path})) | _s_elapsed_flaw({"where": object.get(fl, "where", [])})) | {_whose_problem(p) | some c in conds; some p in object.get(c, "$sentence", [])}) | {"whose: a condition can't be read" | count(conds) != count(object.get(fl, "where", []))}) | _s_join_unsupported({"where": object.get(fl, "where", [])})))
	fields := object.union(_s_source(name, fl, subjects, chains.parts), _s_whose_filters(_s_filter_prefix(name, chains.narrow), conds))
	parent := _s_descend_parent(name, fl, subjects)
	every_list := object.get(fl, "every", false) == true
}

_s_from_filter(name, c, names, keep, pc) := object.union(_rooted(_p_applied(_s_parent_named(t, _s_check([t], {}, _p_part_walk_problems([t], "", pc_named), keep_named), names), pc_named)), {"expression": _s_cond_body(_s_from_cond(c, names, keep_named))}) if {
	not _s_that(c)
	keep_named := keep | {name}
	pc_named := _s_whose_context(name, c, pc)
	t := _s_cond_body(_s_from_cond(_s_left_dotted(c, name), names, keep_named))
}

_s_from_filter(name, c, names, keep, pc) := _p_applied(_s_parent_named(t, _s_check([t], {}, _p_part_walk_problems([t], "", pc_named), keep_named), names), pc_named) if {
	_s_that(c)
	keep_named := keep | {name}
	pc_named := object.union(pc, {"own": object.union(pc.own, {name: []})})
	t := concat(" ", [_s_path_text({"steps": [name], "quoted": true}, "left"), _s_phrase_text(c.phrase)])
}

_s_left_dotted(c, name) := object.union(c, object.union(
	{k: _s_name_dotted(c[k], name) | some k in ["path", "every", "some"]; is_object(object.get(c, k, null))},
	{"terms": [_s_term_dotted(t, name) | some t in c.terms] | is_array(object.get(c, "terms", null))},
))

_s_term_dotted(t, name) := _s_name_dotted(
	object.union(t, {f: _s_name_dotted(t[f], name) |
		some f in ["count", "sum", "elapsed_from", "elapsed_to"]
		is_object(object.get(t, f, null))
	}),
	name,
)

_s_name_dotted(p, name) := object.union(p, {"dot": true}) if {
	is_object(p)
	is_array(object.get(p, "steps", null))
	p.steps[0] == name
	not "start" in object.keys(p)
	not _s_itself(p)
} else := p

_s_whose_context(name, c, pc) := object.union(pc, {"own": object.union(pc.own, {name: []})}) if _s_text_has(json.marshal(c), name)

_s_whose_context(name, c, pc) := pc if not _s_text_has(json.marshal(c), name)

_s_text_has(text, name) if {
	is_string(name)
	quoted := json.marshal(name)
	contains(text, substring(quoted, 1, count(quoted) - 2))
}

_s_text_has(text, name) if {
	is_string(name)
	contains(text, "\\\\")
}

_whose_problem(p) := p if p == "every and some over more than ten steps aren't supported yet"

else := concat("", ["whose: ", substring(p, 0, indexof(p, " is compared with itself") + count(" is compared with itself"))]) if contains(p, " is compared with itself")

else := concat("", ["whose: ", p])

_s_from_cond(c, names, keep) := object.union(c, object.union(
	{q: _s_from_dot(c[q], names, keep) | some q in ["every", "some"]; is_object(object.get(c, q, null))},
	object.union(
		{"path": _s_from_dot(c.path, names, keep) | is_object(object.get(c, "path", null))},
		object.union(
			{"terms": [_s_from_term(t, names, keep) | some t in c.terms] | is_array(object.get(c, "terms", null))},
			{"phrase": _s_from_phrase(c.phrase, keep) | is_object(object.get(c, "phrase", null))},
		),
	),
))

_s_from_phrase(ph, keep) := object.union(ph, object.union(
	{"path": _s_from_dot(ph.path, set(), keep) | is_object(object.get(ph, "path", null))},
	{"terms": [_s_from_term(t, set(), keep) | some t in ph.terms] | is_array(object.get(ph, "terms", null))},
))

_s_from_term(t, names, keep) := object.union(t, {f: _s_from_dot(t[f], names, keep) |
	some f in ["count", "sum", "elapsed_from", "elapsed_to"]
	f in object.keys(t)
}) if {
	is_object(t)
	not "steps" in object.keys(t)
} else := _s_from_dot(t, names, keep)

_s_from_dot(p, names, keep) := object.union(p, {"field": true, "own": false}) if {
	_s_markable(p, keep)
	object.get(p, "dot", false) == true
} else := object.union(p, {"field": true, "own": false}) if {
	_s_markable(p, names)
} else := p

_p_from_part(name, fl, subjects, eff) := {"part": rest[0]} if {
	_s_descends(name, fl, subjects)
	rest := array.slice(_s_model_path(fl.path), 1, count(_s_model_path(fl.path)))
	count(rest) > 0
	is_string(rest[0])
	rest[0] in object.keys(_p_steps_of(object.get(eff, fl.path.steps[0], {})))
} else := {}

_s_source(name, fl, subjects, eff) := {"of": fl.path.steps[0]} if {
	_s_narrows(name, fl, subjects)
} else := {"from": array.concat(_s_from_steps(_p_descend_steps(array.slice(_s_model_path(fl.path), 1, count(_s_model_path(fl.path))), object.get(eff, fl.path.steps[0], {}))), _s_each_step(fl))} if {
	_s_descends(name, fl, subjects)
} else := {"from": array.concat(_s_from_steps(_s_model_path(fl.path)), _s_each_step(fl))}

_s_descend_parent(name, fl, subjects) := fl.path.steps[0] if _s_descends(name, fl, subjects)

else := null

_s_descends(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	object.get(fl.path, "dot", false) != true
	count(fl.path.steps) > 1
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
}

_s_descends(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	object.get(fl.path, "dot", false) != true
	fl.path.steps == [fl.path.steps[0]]
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
	"named_by_each_of" in object.keys(fl)
}

_s_descends(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	object.get(fl.path, "dot", false) != true
	fl.path.steps == [fl.path.steps[0]]
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
	"position" in object.keys(fl.path)
}

_s_narrows(name, fl, subjects) if {
	not "start" in object.keys(fl.path)
	not "position" in object.keys(fl.path)
	object.get(fl.path, "dot", false) != true
	fl.path.steps == [fl.path.steps[0]]
	is_string(fl.path.steps[0])
	fl.path.steps[0] != name
	fl.path.steps[0] in object.keys(subjects)
	not "named_by_each_of" in object.keys(fl)
}

_s_from_steps(path) := [_s_plain_from_step(st) | some st in array.slice(path, 1, count(path))] if {
	count(path) > 0
	path[0] == "$$input"
} else := [_s_plain_from_step(st) | some st in path]

_s_plain_from_step(st) := st.literal if {
	is_object(st)
	object.keys(st) == {"literal"}
} else := st

_s_from_start_problems(fl) := {"a from reads the input, so it can't start at $params" | object.get(fl.path, "start", "") == "params"} | {"named by each of takes a list from $params or $input, so it can't start at a field or a subject" | _s_each_starts_elsewhere(fl)}

_s_each_starts_elsewhere(fl) if {
	"named_by_each_of" in object.keys(fl)
	not "start" in object.keys(fl.named_by_each_of)
}

_s_each_step(fl) := [{"each_as": "subject", "keys": {"ref": _s_model_path(fl.named_by_each_of)}}] if "named_by_each_of" in object.keys(fl)

_s_each_step(fl) := [] if not "named_by_each_of" in object.keys(fl)

_s_whose_filters(_, []) := {}

_s_whose_filters(prefix, conds) := {"applies_to": {concat("", [prefix, _s_filter_name(i, count(conds))]): c | some i, c in conds}} if conds != []

_s_filter_prefix(name, chain) := concat("", [_s_pad(count(graph.reachable(chain, [name])) - 1), " ", _text(name), " "])

_s_pad(i) := concat("", [substring("         ", 0, 9 - count(format_int(i, 10))), format_int(i, 10)])

_s_chain_parent(n, lines, subjects) := [lines[n].path.steps[0]] if {
	"path" in object.keys(object.get(lines, n, {}))
	_s_narrows(n, lines[n], subjects)
} else := [subjects[n].of] if {
	is_object(subjects[n])
	is_string(object.get(subjects[n], "of", null))
} else := []

_s_filter_name(i, n) := concat("", ["whose ", strings.replace_n({" ": "0"}, sprintf_pad)]) if {
	width := count(format_int(n - 1, 10))
	digits := format_int(i, 10)
	sprintf_pad := concat("", [substring("                    ", 0, width - count(digits)), digits])
}

_s_every_unsupported(_, fl, _) := {_s_distinct_on_from | object.get(fl, "distinct", false) == true} if object.get(fl, "every", false) != true

_s_distinct_on_from := `on a from line, distinct goes after every, like "every distinct sbom.components"`

_s_every_unsupported(name, fl, subjects) := ({concat("", [t, " is a subject: write ", t, " whose … to narrow it, without every"]) |
	_s_narrows(name, fl, subjects)
	t := _s_path_text({"steps": [fl.path.steps[0]], "quoted": true}, "left")
} | {"every can't go with named by each of: start the from line at a subject to read its names one subject at a time" | "named_by_each_of" in object.keys(fl)}) | {"every over more than ten steps isn't supported yet" | count(_walk_steps(_s_model_path(fl.path))) > 10} if object.get(fl, "every", false) == true

_s_chain_unsupported(name, fl, subjects, chains) := {"a chain of more than three subjects isn't supported yet" |
	_s_descends(name, fl, subjects)
	parent := fl.path.steps[0]
	parent in object.keys(chains.descend)
	chains.descend[parent] in object.keys(chains.descend)
	not _s_in_loop(name, fl, subjects, chains)
}

_s_loop(name, fl, subjects, chains) := {"leads to a loop" | _s_in_loop(name, fl, subjects, chains)}

_s_in_loop(name, fl, subjects, chains) if {
	_s_starts_at_subject(name, fl, subjects)
	links := {n: array.concat(object.get(chains.narrow, n, []), [p | some p in [object.get(chains.descend, n, null)]; p != null]) | some n, _ in subjects}
	some m in graph.reachable(links, [fl.path.steps[0]])
	m in graph.reachable(links, links[m])
}

_s_follows(name, fl, subjects, chains) := {"follows": fl.path.steps[0]} if {
	_s_in_loop(name, fl, subjects, chains)
} else := {"follows": fl.path.steps[0]} if {
	_s_blank_start(fl, subjects) != set()
} else := {}

_s_starts_at_subject(name, fl, subjects) if _s_descends(name, fl, subjects)

_s_starts_at_subject(name, fl, subjects) if _s_narrows(name, fl, subjects)

_s_blank_start(fl, subjects) := {concat("", ["\"", fl.path.steps[0], "\" isn't a subject name"]) |
	not "start" in object.keys(fl.path)
	is_string(fl.path.steps[0])
	fl.path.steps[0] in object.keys(subjects)
	trim_space(fl.path.steps[0]) == ""
}

_s_id_field(read) := {"identified_by": read.identified_by.path} if "path" in object.keys(object.get(read, "identified_by", {}))

else := {}

_s_dotted_line(name, line) := object.union(line, {"path": object.union(line.path, {"kept_dot": true})}) if object.get(data.ergo_subject_sentences, "dotted", {})[name] == true

else := object.union(line, {"path": object.union(line.path, {"quoted": true})}) if {
	is_object(object.get(line, "path", null))
	not "start" in object.keys(line.path)
	object.get(line.path, "dot", false) != true
	is_string(line.path.steps[0])
	line.path.steps[0] != name
	line.path.steps[0] in object.keys(data.ergo_resolved)
} else := line

_s_dotted(subjects, lines) := {name: true |
	some name, l in lines
	is_object(object.get(l, "path", null))
	l.path.dot == true
	not "start" in object.keys(l.path)
	is_string(l.path.steps[0])
	l.path.steps[0] != name
	l.path.steps[0] in object.keys(subjects)
}

_s_subject_sentences(subjects, reads, parts) := {"dotted": _s_dotted(subjects, parts.lines), "from_parts": {name: r.part | some name, r in reads; _s_from_used(subjects[name], r)}, "lines": parts.lines, "parts": parts.effective, "has_problems": parts.problems, "chains": {name: p | some name, r in reads; _s_from_used(subjects[name], r); p := object.get(r, "parent", null); p != null}, "listed": {name: _s_listed_parent(r) | some name, r in reads; _s_listed_parent(r) != null}, "narrowing": _s_narrowing_of(reads), "rooted": _s_rooted(subjects, reads, parts.lines), "every_text": _s_every_texts(subjects, reads, parts.lines), "every": {name | some name, r in reads; _s_from_used(subjects[name], r); object.get(r, "every", false) == true}, "distinct": {name | some name, r in reads; _s_from_used(subjects[name], r); object.get(r, "every", false) == true; object.get(r, "distinct", false) == true}, "narrowed": {name | some name, r in reads; _s_from_used(subjects[name], r); "of" in object.keys(r.fields)}, "filters": {[name, n] | some name, r in reads; _s_from_used(subjects[name], r); some n, _ in object.get(r.fields, "applies_to", {})}, "problems": {name: probs | some name, def in subjects; probs := _s_subject_problems(name, def, reads, parts.lines); probs != {}}, "follows": {name: r.follows | some name, r in reads; "follows" in object.keys(r)}} if is_object(subjects)

_s_narrowing_of(reads) := {name: [parent] | some name, r in reads; parent := _s_narrowed_parent(r); is_string(parent); trim_space(parent) != ""}

_s_root_line(name, reads, lines) := [lines[m] | some m in graph.reachable({n: object.get(narrowing, n, []) | some n, _ in reads}, [name]); not m in object.keys(narrowing); m in object.keys(lines)][0] if narrowing := _s_narrowing_of(reads)

_s_rooted(subjects, reads, lines) := {name: true |
	some name, _ in subjects
	line := _s_root_line(name, reads, lines)
	object.get(object.get(line, "path", {}), "start", "") == "input"
}

_s_every_texts(subjects, reads, lines) := {name: concat("", ["every ", _s_path_text(line.path, "left")]) |
	some name, _ in subjects
	line := _s_root_line(name, reads, lines)
	is_object(object.get(line, "path", null))
}

_s_listed_parent(r) := object.get(r, "parent", null) if object.get(r, "parent", null) != null

else := _s_narrowed_parent(r) if _s_narrowed_parent(r) != null

else := null

_s_narrowed_parent(r) := object.get(object.get(r, "fields", {}), "of", null)

_s_subject_sentences(subjects, _, _) := {"from_parts": {}, "lines": {}, "parts": {}, "has_problems": {}, "chains": {}, "listed": {}, "narrowing": {}, "every": set(), "distinct": set(), "narrowed": set(), "filters": set(), "problems": {}, "follows": {}, "dotted": {}, "rooted": {}, "every_text": {}} if not is_object(subjects)

_s_subject_problems(name, def, reads, lines) := {f: ps | some f in ["applies_to", "from", "identified_by", "of"]; ps := _s_field_problems(name, def, f, reads, lines); ps != []} if is_object(def)

_s_subject_problems(_, def, _, _) := {} if not is_object(def)

_s_field_problems(name, def, "from", reads, _) := reads[name].problems if is_string(object.get(def, "from", null))

_s_field_problems(name, def, "identified_by", reads, lines) := sort(array.concat(object.get(reads[name].identified_by, "problems", []), [p | some p in _s_keyed_id_problem(object.get(lines, name, {}))])) if is_string(object.get(def, "identified_by", null))

_s_keyed_id_problem(line) := {"not allowed with named by each of: the key is the id"} if "named_by_each_of" in object.keys(line)

_s_keyed_id_problem(line) := set() if not "named_by_each_of" in object.keys(line)

_s_field_problems(_, def, "from", _, _) := ["not a string"] if {
	"from" in object.keys(def)
	not is_string(def.from)
}

_s_field_problems(name, def, "identified_by", _, lines) := sort(array.concat(["not a string"], [p | some p in _s_keyed_id_problem(object.get(lines, name, {}))])) if {
	"identified_by" in object.keys(def)
	not is_string(def.identified_by)
}

_s_field_problems(_, def, f, _, _) := [] if {
	f in {"from", "identified_by"}
	not f in object.keys(def)
}

_s_field_problems(_, def, f, _, _) := ["unknown field"] if {
	f in {"applies_to", "of"}
	f in object.keys(def)
}

_s_field_problems(_, def, f, _, _) := [] if {
	f in {"applies_to", "of"}
	not f in object.keys(def)
}

_p_no_parts := {"own": {}, "effective": {}, "problems": {}, "lines": {}, "narrow": {}, "descend": {}}

_p_aliases(req, parts) := {alias | some alias, _ in object.get(parts.effective, req.subject, {})} if is_string(object.get(req, "subject", null))

_p_aliases(req, _) := set() if not is_string(object.get(req, "subject", null))

_p_named_by_problems(lines, ftext, aliases, subject) := {_p_named_by_message(ref.steps[0], subject) |
	aliases != set()
	some tree in array.concat([_sentence(line) | some line in lines; is_string(line)], [_for_line(ftext) | is_string(ftext)])
	walk(tree, [at, node])
	is_object(node)
	ref := object.get(node, "named_by", {"start": ""})
	not "start" in object.keys(ref)
	ref.steps[0] in aliases
	not _p_subject_keyed(tree, at, ref, subject)
}

_p_subject_keyed(tree, at, ref, subject) if {
	ref.steps[0] == subject
	"where" in at
	count(at) > 0
	is_number(at[count(at) - 1])
	steps := object.get(tree, array.slice(at, 0, count(at) - 1), [])
	is_string(steps[at[count(at) - 1] + 1])
}

_p_named_by_message(name, subject) := concat("", ["named by ", name, ": ", name, " is the whole subject, so it can't name a key"]) if name == subject

_p_named_by_message(name, subject) := concat("", ["named by ", name, " reads a part, which isn't supported yet"]) if name != subject

_p_named_by_problems(_, _, aliases, _) := set() if aliases == set()

_p_for_clash(check, pc) := {concat("", [item.as, " can't be an alias: it's a subject's name"]) |
	some item in _p_for_items(check)
	item.as in pc.subjects
} | {concat("", [item.as, " can't be an alias: it's a part of ", _p_name_text(declarer)]) |
	some item in _p_for_items(check)
	some _, owned in pc.part_owners
	some declarer in object.get(owned, item.as, set())
}

_p_for_clash(check, _) := set() if not is_string(object.get(check, "for", ""))

_p_for_items(check) := object.get(_for_line(check.for), "items", []) if is_string(check.for)

_p_subject_follow_problems(check, lines, ftext, pc) := {concat("", [_s_path_text(object.union(written, {"quoted": true}), "left"), ": nothing can follow ", pc.subject, ", which means the subject: for a field called ", pc.subject, ", write ", concat("", [_s_step_text(st) | some st in written.steps])]) |
	_s_text_has(json.marshal(check), pc.subject)
	some node in _p_subject_nodes(lines, ftext)
	node.steps[0] == pc.subject
	_p_followed(node)
	object.get(node, "dot", false) != true
	not "start" in object.keys(node)
	written := _p_as_written(node)
} if is_string(object.get(pc, "subject", null))

_p_followed(node) if count(node.steps) > 1

_p_followed(node) if object.get(node, "bracketed", false) == true

_p_as_written(node) := object.union(object.remove(node, ["bracketed", "position"]), {"steps": array.concat(node.steps, [{"index": node.position - 1}])}) if object.get(node, "bracketed", false) == true

_p_as_written(node) := node if object.get(node, "bracketed", false) != true

_p_subject_follow_problems(_, _, _, pc) := set() if not is_string(object.get(pc, "subject", null))

_p_subject_nodes(lines, ftext) := {n |
	some line in lines
	is_string(line)
	walk(_sentence(line), [at, n])
	_p_subject_read(at, n)
} | {n |
	is_string(ftext)
	walk(_for_line(ftext), [at, n])
	_p_subject_read(at, n)
}

_p_subject_read(at, n) if {
	is_object(n)
	is_array(object.get(n, "steps", null))
	not _p_read_on_item(at)
}

_p_read_on_item(at) if "sorted_by" in at

_p_read_on_item(at) if "where" in at

_p_part_walk_problems(_, _, pc) := set() if _p_idle(pc)

_p_part_walk_problems(lines, ftext, pc) := {concat("", [prefix, "every and some over more than ten steps aren't supported yet"]) |
	some [prefix, p] in _p_part_walks(lines, ftext, pc)
	_p_part_walk_steps(p, pc) > 10
} if not _p_idle(pc)

_p_part_walks(lines, ftext, pc) := {["", p] |
	some line in lines
	is_string(line)
	some a in object.get(_sentence(line), "assertions", [])
	some p in _p_walk_paths(_s_aliased(a, _s_names(set(), _p_unaliased(ftext, object.keys(pc.own)) | object.keys(pc.ancestors))))
} | {["for: ", p] |
	is_string(ftext)
	fl := _for_line(ftext)
	some item in _s_marked_items(fl, object.keys(pc.own) | object.keys(pc.ancestors))
	some p in _p_walk_paths(_s_unpicked(item))
}

_p_unaliased(ftext, names) := names - {item.as |
	is_string(ftext)
	some item in object.get(_for_line(ftext), "items", [])
}

_p_walk_paths(x) := ({x[q] | some q in ["every", "some", "pick"]; is_object(object.get(x, q, null))} | {t[k] | some t in _s_nodes(object.remove(x, _p_item_keys(x))); some k in _p_derived_keys(t)}) | {t[k] | some t in _s_nodes(object.filter(x, _p_item_keys(x))); some k in _p_derived_keys(t)}

_p_derived_keys(t) := {k |
	_s_derived_term(t)
	some k in ["count", "sum"]
	is_object(object.get(t, k, null))
}

_p_item_keys(x) := ["where", "phrase"] if object.keys(x) & {"every", "some", "pick"} != set()

else := ["where"]

_p_part_walk_steps(p, pc) := (count(_walk_steps(_s_model_path(p))) - 1) + count(pc.own[p.steps[0]]) if {
	object.get(p, "part", false) == true
	p.steps[0] in object.keys(pc.own)
} else := _p_parent_walk_steps(p, pc)

_p_parent_walk_steps(p, pc) := (count(_walk_steps(_s_model_path(p))) - 2) + count(pc.ancestors[p.steps[0]][p.steps[1]]) if {
	object.get(p, "part", false) == true
	p.steps[1] in object.keys(pc.ancestors[p.steps[0]])
} else := 0

_p_steps_of(parts) := {alias: read.from.path | some alias, read in parts; _p_valid(read)}

_p_own_context(name, eff) := {"own": _p_steps_of(object.get(eff, name, {})), "ancestors": {}}

_p_context(req, chains, parts) := {"own": _p_steps_of(object.get(parts.effective, req.subject, {})), "subject": req.subject, "ancestors": {a: _p_steps_of(object.get(parts.effective, a, {})) | some a in _s_ancestors(req.subject, chains)}, "subjects": object.keys(parts.effective), "part_owners": {s: {a: {m | some m in _p_members(s, parts.narrow); a in object.keys(object.get(parts.own, m, {}))} | some a, _ in object.get(parts.effective, s, {})} | some s in array.concat([req.subject], _s_ancestors(req.subject, chains))}} if {
	is_string(object.get(req, "subject", null))
} else := {"own": {}, "ancestors": {}, "subjects": object.keys(parts.effective), "part_owners": {}}

_s_ancestors(name, chains) := array.concat([chains[name]], [chains[chains[name]] | chains[name] in object.keys(chains)]) if name in object.keys(chains)

else := []

_p_idle(pc) if {
	pc.own == {}
	every _, steps in pc.ancestors {
		steps == {}
	}
}

_p_mentions(x, pc) if contains(json.marshal(x), json.marshal(pc.subject))

_p_quiet(x, pc) if {
	_p_idle(pc)
	not _p_mentions(x, pc)
}

_p_full(pc) := object.union(pc, {"own": object.union(pc.own, {pc.subject: []})}) if is_string(object.get(pc, "subject", null))

else := pc

_p_applied(m, pc) := m if _p_quiet(m, pc)

_p_applied(m, pc) := m if {
	not _p_quiet(m, pc)
	"$sentence" in object.keys(m)
}

_p_applied(m, pc) := _p_smodel(m, _p_full(pc)) if {
	not _p_quiet(m, pc)
	not "$sentence" in object.keys(m)
}

_p_applied_to(_, model, pc) := model if _p_quiet(model, pc)

_p_applied_to(written, model, pc) := model if {
	not _p_quiet(model, pc)
	not _s_written_as_sentence(written)
}

_p_applied_to(written, model, pc) := _p_applied(model, pc) if {
	not _p_quiet(model, pc)
	_s_written_as_sentence(written)
}

_p_old_filters(def, pc) := def if _p_idle(pc)

_p_old_filters(def, pc) := def if {
	not _p_idle(pc)
	not is_object(object.get(def, "applies_to", null))
}

_p_descend_steps(rest, parts) := array.concat(_p_steps_of(parts)[rest[0]], array.slice(rest, 1, count(rest))) if {
	count(rest) > 0
	is_string(rest[0])
	rest[0] in object.keys(_p_steps_of(parts))
} else := rest

_p_marker(alias, n, of, old) := concat("", ["${\"alias\":", json.marshal(alias), ",\"n\":", format_int(n, 10), ",\"of\":", json.marshal(of), ",\"old\":", json.marshal(old), "}"])

_p_item_mode(mode) := "i" if mode != "o"

_p_path(path, pc, "s") := array.concat(array.concat([_p_marker(path[0], count(pc.own[path[0]]), null, false)], pc.own[path[0]]), array.slice(path, 1, count(path))) if {
	is_array(path)
	count(path) > 0
	is_string(path[0])
	not startswith(path[0], "$")
	path[0] in object.keys(pc.own)
} else := _p_parent_path(path, pc)

_p_path(path, pc, "i") := _p_parent_path(path, pc)

_p_path(path, pc, "o") := array.concat(array.concat([_p_marker(alias, count(pc.own[alias]), null, true)], pc.own[alias]), array.slice(path, 1, count(path))) if {
	is_array(path)
	count(path) > 0
	is_string(path[0])
	startswith(path[0], "$")
	not startswith(path[0], "$$")
	alias := substring(path[0], 1, -1)
	alias in object.keys(pc.own)
}

_p_parent_path(path, pc) := array.concat(array.concat([_p_marker(path[1], count(pc.ancestors[a][path[1]]), a, false)], pc.ancestors[a][path[1]]), array.slice(path, 2, count(path))) if {
	is_array(path)
	count(path) > 1
	is_string(path[0])
	a := substring(path[0], 1, -1)
	path[0] == concat("", ["$", a])
	a in object.keys(pc.ancestors)
	is_string(path[1])
	path[1] in object.keys(pc.ancestors[a])
} else := path

_p_smodel(m, pc) := object.union(m, {"checks": [_p_sleaf(c, pc) | some c in m.checks]}) if m.op in {"all_of", "sentence_any_of"}

_p_smodel(m, pc) := object.union(m, {
	"checks": [_p_sleaf(c, pc) | some c in m.checks],
	"items": [object.union(item, {"path": _p_path(item.path, pc, "s"), "whose": [_p_leaf(c, pc, "i") | some c in item.whose]}) | some item in m.items],
}) if m.op == "for"

_p_smodel(m, pc) := _p_sleaf(m, pc) if not m.op in {"all_of", "sentence_any_of", "for"}

_p_sleaf(m, pc) := object.union(m, {
	"path": _p_path(m.path, pc, "s"),
	"whose": [_p_leaf(c, pc, "i") | some c in m.whose],
	"check": _p_leaf(m.check, pc, "i"),
}) if m.op in {"every", "some"}

_p_sleaf(m, pc) := _p_leaf(m, pc, "s") if not m.op in {"every", "some"}

_p_leaf(m, pc, mode) := object.union(object.union(m, {f: _p_item_side(f, m[f], pc, mode) | some f in ["path", "left", "right"]; f in object.keys(m)}), {"inputs": [_p_side(i, pc, mode) | some i in m.inputs] | is_array(object.get(m, "inputs", null))})

_p_item_side(f, side, pc, mode) := _p_item_path(side, pc) if {
	f == "right"
	mode == "i"
	is_array(side)
} else := _p_item_right(side, pc) if {
	f == "right"
	mode == "i"
	is_object(side)
} else := _p_side(side, pc, mode)

_p_item_path(path, pc) := _p_subject_key(_p_path(_p_own_named(path), pc, "o"), pc) if {
	count(path) > 0
	is_string(path[0])
	not startswith(path[0], "$")
	path[0] in object.keys(pc.own)
} else := _p_subject_key(_p_path(path, pc, "i"), pc)

_p_subject_key(p, pc) := array.concat(array.concat(array.slice(p, 0, i), [{"named_by_field": concat("", [_subject_key, pc.subject, _subject_key, p[i + 1]])}]), array.slice(p, i + 2, count(p))) if {
	is_string(object.get(pc, "subject", null))
	i := min({j | some j, step in p; step == {"named_by_field": pc.subject}; j + 1 < count(p); is_string(p[j + 1])})
} else := p

_p_item_right(side, pc) := object.union(side, {"add": [_p_item_right_one(o, pc) | some o in side.add]}) if is_array(object.get(side, "add", null))

else := object.union(side, {"join": [_p_item_right_one(o, pc) | some o in side.join]}) if is_array(object.get(side, "join", null))

else := _p_item_right_one(side, pc)

_p_item_right_one(side, pc) := _p_item_path(side, pc) if is_array(side)

else := object.union(side, object.union({f: _p_item_path(side[f], pc) | some f in ["count_of", "sum_of", "elapsed_from", "elapsed_to"]; is_array(object.get(side, f, null))}, object.union({"whose": [_p_cond_flat(c, pc, "i") | some c in side.whose] | is_array(object.get(side, "whose", null))}, {"where": _p_cond_flat(side.where, pc, "i") | is_object(object.get(side, "where", null))}))) if is_object(side)

else := side

_p_own_named(side) := array.concat([concat("", ["$", side[0]])], array.slice(side, 1, count(side)))

_p_side(side, pc, mode) := _p_path(side, pc, mode) if is_array(side)

_p_side(side, pc, mode) := object.union(side, {"add": [_p_side_one(o, pc, mode) | some o in side.add]}) if {
	is_object(side)
	is_array(object.get(side, "add", null))
}

_p_side(side, pc, mode) := object.union(side, {"join": [_p_side_one(o, pc, mode) | some o in side.join]}) if {
	is_object(side)
	is_array(object.get(side, "join", null))
}

_p_side(side, pc, mode) := _p_side_one(side, pc, mode) if {
	is_object(side)
	not "add" in object.keys(side)
	not "join" in object.keys(side)
}

_p_side_one(side, pc, mode) := _p_path(side, pc, mode) if is_array(side)

_p_side_one(side, pc, mode) := object.union(_p_tally(side, pc, mode), object.union({"whose": [_p_cond(c, pc, _p_item_mode(mode)) | some c in side.whose] | is_array(object.get(side, "whose", null))}, {"where": _p_cond(side.where, pc, _p_item_mode(mode)) | is_object(object.get(side, "where", null))})) if is_object(side)

_p_tally(side, pc, mode) := object.union(side, {f: _p_path(side[f], pc, mode) | some f in ["count_of", "sum_of", "elapsed_from", "elapsed_to"]; is_array(object.get(side, f, null))})

_p_cond(c, pc, mode) := object.union(_p_cond_flat(c, pc, mode), {"right": _p_item_right(c.right, pc)}) if {
	is_object(c)
	mode == "i"
	is_object(object.get(c, "right", null))
} else := _p_cond_flat(c, pc, mode)

_p_cond_flat(c, pc, mode) := object.union(c, {f: _p_cond_side(f, c[f], pc, mode) | some f in ["path", "left", "right"]; is_array(object.get(c, f, null))}) if is_object(c)

_p_cond_side(f, side, pc, mode) := _p_item_path(side, pc) if {
	f == "right"
	mode == "i"
} else := _p_path(side, pc, mode)
