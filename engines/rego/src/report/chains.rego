package ergo

import rego.v1

_evaluated(doc, req, name, parts) := object.union(e, {"unique_ancestor_ids": []}) if {
	not _chained(req)
	e := _evaluation(doc, req, name, parts)
}

_evaluated(doc, req, name, parts) := object.union(_chain_evaluation(req, name, pick, parts), {"unique_ancestor_ids": [_ancestor_ids_row(pick, data.ergo_subject_sentences.chains[req.subject], name)]}) if {
	_chained(req)
	not _grand_chained(req)
	pick := _parent_pick(doc, req)
}

_evaluated(doc, req, name, parts) := _grand_evaluation(req, name, _parent_pick_of(doc, {"subject": grand, "checks": {}}), parent, grand, _fixed(req), parts) if {
	_grand_chained(req)
	parent := data.ergo_subject_sentences.chains[req.subject]
	grand := data.ergo_subject_sentences.chains[parent]
}

_grand_chained(req) if {
	_chained(req)
	data.ergo_subject_sentences.chains[req.subject] in object.keys(data.ergo_subject_sentences.chains)
}

_grand_evaluation(req, name, gpick, _, grand, _, parts) := object.union(_no_parent_evaluation(req, name, gpick.cause, parts), {"unique_ancestor_ids": [_ancestor_ids_row(gpick, grand, name)]}) if "cause" in object.keys(gpick)

_grand_evaluation(req, name, gpick, parent, grand, fixed, parts) := object.union(_grand_branches(req, name, [e | some b in branches; some e in b.es], parts), {"unique_ancestor_ids": array.concat([_ancestor_ids_row(gpick, grand, name)], [r | some b in branches; some r in b.rows])}) if {
	"parents" in object.keys(gpick)
	branches := [_grand_branch(req, name, parent, grand, g, fixed) | some g in gpick.parents]
}

_grand_branches(req, name, es, parts) := _parents_evaluation(req, name, es, parts) if count(es) > 0

else := _no_parent_evaluation(req, name, "none", parts)

_grand_branch(req, name, _, grand, g, fixed) := {"es": [_parent_evaluation(req, name, grand, g, fixed)], "rows": []} if "cause" in object.keys(g)

_grand_branch(req, name, parent, grand, g, fixed) := {"es": _grand_children(req, name, parent, grand, g, pick, fixed), "rows": [_copied_ancestor_row(row, g)]} if {
	"subject" in object.keys(g)
	gat := _copy_base(g, "~g")
	pick := _parent_pick_of(g.subject, {"subject": parent, "checks": {}}) with data.ergo_in as {grand: g.id} with data.ergo_parent as {grand: g.subject} with input as {"ergo/names": {"$at": {"doc": gat, "names": {grand: gat}}}}
	row := _ancestor_ids_row(pick, parent, name) with data.ergo_in as {grand: g.id} with data.ergo_parent as {grand: g.subject} with input as {"ergo/names": {"$at": {"doc": gat, "names": {grand: gat}}}}
}

_copied_ancestor_row(row, g) := row if object.get(g, "ats", null) == null

else := _copied_row(row, {"from": "~g", "to": g.ats})

_ancestor_ids_row(pick, ancestor, name) := object.union(_unique_ids_row(pick.raw, pick.refs, {"subject": ancestor, "checks": {}}, name), {"check": "$unique_ancestor_ids"}) if "raw" in object.keys(pick)

else := object.union(_unique_ids_row([], {}, {"subject": ancestor, "checks": {}}, name), {"check": "$unique_ancestor_ids"})

_grand_children(req, name, _, grand, g, pick, fixed) := [_parent_evaluation(req, name, grand, {"id": g.id, "cause": pick.cause}, fixed)] if "cause" in object.keys(pick)

_grand_children(req, name, parent, grand, g, pick, fixed) := [_grandchild_evaluation(req, name, parent, grand, g, p, fixed) | some p in pick.parents] if "parents" in object.keys(pick)

_grandchild_evaluation(req, name, parent, grand, g, p, fixed) := _copied_evaluation(_copied_evaluation(e, p, "~p"), g, "~g") if {
	"subject" in object.keys(p)
	gat := _copy_base(g, "~g")
	pat := _copy_base(p, "~p")
	e := _evaluation_with(p.subject, req, name, fixed) with data.ergo_in as {grand: g.id, parent: p.id} with data.ergo_parent as {grand: g.subject, parent: p.subject} with input as {"ergo/names": {"$at": {"doc": pat, "names": {grand: gat, parent: pat}}}}
}

_grandchild_evaluation(req, name, parent, grand, g, p, _) := {
	"min_subjects": [row],
	"unique_ids": [],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
} if {
	"cause" in object.keys(p)
	row := _parent_min_subjects_row(req, name, p.cause) with data.ergo_in as {grand: g.id, parent: p.id}
}

_chain_evaluation(req, name, pick, parts) := _parents_evaluation(req, name, [_parent_evaluation(req, name, pick.parent, p, fixed) | some p in pick.parents], parts) if {
	fixed := _fixed(req)
	"parents" in object.keys(pick)
	count(pick.parents) > 0
}

_chain_evaluation(req, name, pick, parts) := _no_parent_evaluation(req, name, "none", parts) if {
	"parents" in object.keys(pick)
	count(pick.parents) == 0
}

_chain_evaluation(req, name, pick, parts) := _no_parent_evaluation(req, name, pick.cause, parts) if "cause" in object.keys(pick)

_no_parent_evaluation(req, name, cause, parts) := object.union(_evaluation({}, req, name, parts), {
	"min_subjects": [_parent_min_subjects_row(req, name, cause)],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
})

_parent_evaluation(req, name, parent, p, fixed) := _copied_evaluation(e, p, "~p") if {
	"subject" in object.keys(p)
	pat := _copy_base(p, "~p")
	e := _evaluation_with(p.subject, req, name, fixed) with data.ergo_in as {parent: p.id} with data.ergo_parent as {parent: p.subject} with input as {"ergo/names": {"$at": {"doc": pat, "names": {parent: pat}}}}
}

_copy_base(p, token) := p.at if object.get(p, "ats", null) == null

else := token

_parent_evaluation(req, name, parent, p, _) := {
	"min_subjects": [row],
	"unique_ids": [],
	"applies": [],
	"subject_rows": [],
	"total": 0,
	"matching": 0,
	"scope_readable": true,
	"rows_complete": true,
} if {
	"cause" in object.keys(p)
	row := _parent_min_subjects_row(req, name, p.cause) with data.ergo_in as {parent: p.id}
}

_copied_evaluation(e, p, token) := e if object.get(p, "ats", null) == null

else := object.union(e, {
	"min_subjects": [_copied_row(r, c) | some r in e.min_subjects],
	"unique_ids": [_copied_row(r, c) | some r in e.unique_ids],
	"applies": [_copied_row(r, c) | some r in e.applies],
	"subject_rows": [[_copied_row(r, c) | some r in group] | some group in e.subject_rows],
}) if {
	c := {"from": token, "to": p.ats}
}

_copied_row(row, c) := object.union(row, object.union({"inputs": _copied_inputs(row.inputs, c)}, {"failed_items": [_copied_failed(f, c) | some f in row.failed_items] | "failed_items" in object.keys(row)}))

_copied_failed(f, c) := object.union(f, object.union(
	{"locations": _copied_locations(f.locations, c)},
	object.union(
		{"failed_items": _copied_inputs(f.failed_items, c) | "failed_items" in object.keys(f)},
		{"failed_assertions": [_copied_line(l, c) | some l in f.failed_assertions] | "failed_assertions" in object.keys(f)},
	),
))

_parents_evaluation(req, name, es, parts) := {
	"well_formed": _well_formed_row(req, name, parts),
	"min_subjects": [row | some e in es; some row in e.min_subjects],
	"unique_ids": [row | some e in es; some row in e.unique_ids],
	"applies": [row | some e in es; some row in e.applies],
	"subject_rows": [group | some e in es; some group in e.subject_rows],
	"total": sum([e.total | some e in es]),
	"matching": sum([e.matching | some e in es]),
	"scope_readable": every_readable,
	"rows_complete": every_complete,
} if {
	every_readable := count([e | some e in es; not e.scope_readable]) == 0
	every_complete := count([e | some e in es; not e.rows_complete]) == 0
}

_chained(req) if {
	is_object(req)
	is_string(object.get(req, "subject", null))
	req.subject in object.keys(object.get(data.ergo_subject_sentences, "chains", {}))
}

_parent_pick(doc, req) := pick if {
	parent := data.ergo_subject_sentences.chains[req.subject]
	preq := {"subject": parent, "checks": {}}
	pick := _parent_pick_of(doc, preq)
}

_parent_pick_of(doc, preq) := {"cause": c} if {
	c := _target_cause(doc, preq)
	not _fl_typed_only(doc, preq)
} else := {"cause": _from_cause(preq)} if {
	_from_well_formed(preq)
	_from_unreadable(preq)
} else := r if {
	raw := _raw_entries(doc, preq)
	flaws := {n: flaw |
		some n, check in _applies_to_of(preq)
		here := _s_written_here(preq, "applies_to", n)
		flaw := _flaw(check, _from_names(preq, here))
	}
	refs := {i: _entry_ref_of(entry, preq) | some i, entry in raw}
	evals := {i: _applies_evals(preq, entry.subject, flaws) | some i, entry in raw}
	applies := {i: {"passed": matched, "cause": _applies_cause(evals[i], matched)} |
		some i, _ in raw
		matched := _subject_matches(evals[i], preq)
	}
	r := _parent_pick_from(raw, refs, applies, preq)
}

_parent_pick_from(raw, refs, applies, preq) := {"parent": preq.subject, "raw": raw, "refs": refs, "parents": [p |
	some i, entry in raw
	some p in _parent_of(entry, refs[i], applies, i, preq)
]}

_parent_of(entry, ref, _, _, preq) := [_parent_ref(entry, ref)] if _size(_applies_to_of(preq)) == 0

_parent_of(entry, ref, applies, i, preq) := [_parent_ref(entry, ref)] if {
	_size(_applies_to_of(preq)) > 0
	applies[i].passed
}

_parent_of(_, ref, applies, i, preq) := [{"id": ref.id, "cause": applies[i].cause}] if {
	_size(_applies_to_of(preq)) > 0
	not applies[i].cause in {"satisfied", "value"}
}

_parent_of(_, _, applies, i, preq) := [] if {
	_size(_applies_to_of(preq)) > 0
	applies[i].cause == "value"
}

_parent_ref(entry, ref) := {"subject": entry.subject, "id": ref.id, "at": entry.at} if object.get(entry, "ats", null) == null

else := {"subject": entry.subject, "id": ref.id, "at": entry.at, "ats": entry.ats}

_parent_min_subjects_row(req, name, "none") := object.union(
	{
		"requirement": name,
		"subject": _req_subject_ref(req),
		"check": "$min_subjects",
		"inputs": array.concat([{"name": _subject_count_name(req), "value": 0, "locations": []}], data.ergo_unreadable),
		"passed": _min_subjects_of(req) == 0,
		"cause": _verdict_cause(_min_subjects_of(req) == 0),
	},
	_every_no_items(req),
)

_parent_min_subjects_row(req, name, cause) := object.union(
	{
		"requirement": name,
		"subject": _req_subject_ref(req),
		"check": "$min_subjects",
		"inputs": array.concat([{"name": _subject_count_name(req), "value": 0, "locations": []}], data.ergo_unreadable),
		"passed": false,
		"cause": cause,
	},
	_every_no_items(req),
) if cause != "none"

_every_no_items(req) := {"failed_items": []} if _every_from(req)

else := {}
