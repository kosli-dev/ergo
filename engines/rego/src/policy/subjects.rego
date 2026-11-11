package ergo

import rego.v1

_raw_subject(name) := def if {
	is_object(data.ergo_subjects)
	def := object.get(data.ergo_subjects, name, null)
	is_object(def)
}

_of_graph := {name: _of_edges(def, data.ergo_subjects) | some name, def in data.ergo_subjects} if is_object(data.ergo_subjects)

_of_edges(def, subjects) := [def.of] if {
	is_object(def)
	_has_type("of", object.get(def, "of", null))
	def.of in object.keys(subjects)
} else := []

default _is_root(_) := false

_is_root(name) if {
	def := _raw_subject(name)
	not "of" in object.keys(def)
}

_filters_of(name) := object.get(_raw_subject(name), "applies_to", {})

_built_on_count(name) := count(graph.reachable(_of_graph, [name]))

_resolved_subjects := {name: _resolution(name) | some name, _ in data.ergo_subjects} if is_object(data.ergo_subjects)

default _resolved_subjects := {}

_resolution(name) := object.union({"members": members, "problems": problems}, resolved) if {
	members := {m | some m in graph.reachable(_of_graph, [name])}
	resolved := _resolved_def(members)
	problems := _member_problems(members)
}

_resolved_def(members) := {"def": def, "filter_owners": owners} if {
	some r in members
	_is_root(r)
	root := _raw_subject(r)
	owners := {n: _filter_owner_in(members, n) | some m in members; some n, _ in _object_or_empty(_filters_of(m))}
	def := object.union(
		{f: _root_field(f, root[f], r, members) | some f in ["from", "identified_by"]; f in object.keys(root)},
		{"applies_to": _merged_filters(members, owners)},
	)
} else := {}

_root_field("from", _, r, members) := "<built on a subject read from another subject>" if {
	count(members) > 1
	r in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
} else := v if {
	v := _raw_subject(r).from
}

_root_field("identified_by", v, _, _) := v

_merged_filters(members, owners) := {n: _filters_of(owner)[n] | some n, owner in owners} if {
	every m in members {
		is_object(_filters_of(m))
	}
}

_filter_owner_in(members, n) := owners[count(owners) - 1][1] if {
	owners := sort([[_built_on_count(m), m] |
		some m in members
		n in object.keys(_object_or_empty(_filters_of(m)))
	])
	count(owners) > 0
}

_resolution_of(req) := data.ergo_resolved[req.subject] if _names_a_subject(req)

_subject_def(req) := _resolution_of(req).def

default _resolves(_) := false

_resolves(req) if _subject_def(req)

default _names_a_subject(_) := false

_names_a_subject(req) if {
	is_object(req)
	_has_type("subject", object.get(req, "subject", null))
}

_subject_field(req, f, d) := object.get(_subject_def(req), f, d)

_applies_to_of(req) := _object_or_empty(_subject_field(req, "applies_to", {})) if _resolves(req)

_applies_to_of(req) := {} if not _resolves(req)

_from_of(req) := _subject_field(req, "from", []) if _resolves(req)

_from_of(req) := null if not _resolves(req)

_id_of(req) := _subject_field(req, "identified_by", []) if _resolves(req)

_id_of(req) := [] if not _resolves(req)

_subject_type_of(req) := _req_field(req, "subject", "subject")

_min_subjects_of(req) := _req_field(req, "min_subjects", 1)

_require_of(req) := _req_field(req, "require", "every")

_wrong_typed_fields(req) := _wrong_typed(req, _wrong_type_problems)

_wrong_typed(x, problems) := [f |
	is_object(x)
	some f in sort(object.keys(problems))
	f in object.keys(x)
	not _has_type(f, x[f])
]
