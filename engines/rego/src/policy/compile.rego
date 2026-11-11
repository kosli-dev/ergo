package ergo

import rego.v1

compile(policy) := policy if _compiled(policy)

else := policy if _stale_compiled(policy)

else := {"ergo/compiled": object.union({"policy": policy, "engine": _engine}, _to_compiled(rd))} if rd := _read_ahead(policy)

else := policy

_read(policy) := {"subjects": subjects, "subject_sentences": subject_sentences, "reqs": reqs, "sentences": sentences, "resolved": resolved, "ahead": {}} if {
	raw := _section(policy, "requirements")
	written_subjects := _section(policy, "subjects")
	parts := _p_parts(written_subjects)
	reads := _s_from_reads(written_subjects, parts)
	subjects := _s_subjects(_s_new_subjects(written_subjects), reads, parts)
	subject_sentences := _s_subject_sentences(written_subjects, reads, parts)
	reqs := _p_requirements(_object_or_empty(raw), subject_sentences.chains, parts)
	sentences := _s_sentences(raw, reqs)
	resolved := _resolved_subjects with data.ergo_subjects as subjects with data.ergo_subject_sentences as subject_sentences
}

_s_new_subjects(subjects) := {name: _s_new_subject(def) | some name, def in subjects} if is_object(subjects)

else := subjects

_s_new_subject(def) := object.union(object.remove(def, ["applies_to", "of", "from", "identified_by"]), {f: _s_new_field(def[f]) | some f in ["from", "identified_by"]; f in object.keys(def)}) if is_object(def)

else := def

_s_new_field(v) := v if is_string(v)

else := false

_read_ahead(policy) := object.union(rd, {"ahead": ahead}) if {
	rd := _read(policy)
	ahead := {
		"policy_problems": _policy_problem_inputs(policy),
		"listed": _reported_subjects(_section(policy, "subjects"), rd.reqs),
		"requirements": {name: {"well_formed": _well_formed_row_of(req, name), "defs": _requirement_check_defs(req)} | some name, req in rd.reqs},
	} with data.ergo_policy_problems as _policy_problem_inputs(policy) with data.ergo_document as {} with data.ergo_params as {} with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_reading as true with data.ergo_unreadable as [] with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences with input as {"ergo/names": {}}
}

_to_compiled(rd) := {
	"subjects": rd.subjects,
	"subject_sentences": object.union(object.remove(rd.subject_sentences, ["lines", "distinct"]), object.union({"distinct": sort(rd.subject_sentences.distinct) | count(rd.subject_sentences.distinct) > 0}, {
		"every": sort(rd.subject_sentences.every),
		"narrowed": sort(rd.subject_sentences.narrowed),
		"filters": sort(rd.subject_sentences.filters),
		"has_problems": {n: sort(ps) | some n, ps in rd.subject_sentences.has_problems},
	})),
	"requirements": rd.reqs,
	"sentences": sort(rd.sentences),
	"resolved": {n: object.union(r, {"members": sort(r.members), "problems": sort(r.problems)}) | some n, r in rd.resolved},
	"ahead": rd.ahead,
}

_from_compiled(c) := {
	"subjects": c.subjects,
	"subject_sentences": object.union(c.subject_sentences, {
		"every": {x | some x in c.subject_sentences.every},
		"distinct": {x | some x in object.get(c.subject_sentences, "distinct", [])},
		"narrowed": {x | some x in c.subject_sentences.narrowed},
		"filters": {x | some x in c.subject_sentences.filters},
		"has_problems": {n: {p | some p in ps} | some n, ps in c.subject_sentences.has_problems},
	}),
	"reqs": c.requirements,
	"sentences": {x | some x in c.sentences},
	"resolved": {n: object.union(r, {"members": {m | some m in r.members}, "problems": {p | some p in r.problems}}) | some n, r in c.resolved},
	"ahead": c.ahead,
}

_stale_compiled(x) := c if {
	is_object(x)
	object.keys(x) == {"ergo/compiled"}
	c := x["ergo/compiled"]
	is_object(c)
	"policy" in object.keys(c)
	object.get(c, "engine", null) != _engine
}

_stale_read(c) := object.union(_read(c.policy), {"ahead": {"policy_problems": array.concat([_engine_problem(object.get(c, "engine", null))], _policy_problem_inputs(c.policy))}})

_engine_problem(null) := {"name": "ergo/compiled engine", "value": ["missing"], "locations": []}

_engine_problem(e) := {"name": "ergo/compiled engine", "value": [concat("", ["compiled by another engine, expected ", _engine.name, " ", _engine.version])], "locations": []} if e != null

_compiled(x) := c if {
	is_object(x)
	object.keys(x) == {"ergo/compiled"}
	c := x["ergo/compiled"]
	is_object(c)
	c.engine == _engine
	every f in ["policy", "subjects", "requirements"] {
		f in object.keys(c)
	}
	every f in ["resolved", "subject_sentences", "ahead"] {
		is_object(object.get(c, f, null))
	}
	is_array(object.get(c, "sentences", null))
	every f in ["every", "narrowed", "filters"] {
		is_array(object.get(c.subject_sentences, f, null))
	}
	is_object(object.get(c.subject_sentences, "has_problems", null))
	every f in ["listed", "requirements"] {
		is_object(object.get(c.ahead, f, null))
	}
	is_array(object.get(c.ahead, "policy_problems", null))
}

_ahead_check_defs(req, parts) := {n: _ahead_refs(def) | some n, def in parts.defs} if {
	parts.defs
} else := _requirement_check_defs(req)

_ahead_refs(def) := object.union(object.remove(def, ["$refs_of"]), {"$refs": _ref_inputs(def["$refs_of"])}) if "$refs_of" in object.keys(def)

else := def

_listed_of(policy, rd) := v if {
	v := rd.ahead.listed
} else := _reported_subjects(_section(policy, "subjects"), rd.reqs)

_policy_problems_of(policy, rd) := v if {
	v := rd.ahead.policy_problems
} else := _policy_problem_inputs(policy)
