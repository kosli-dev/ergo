package ergo

import rego.v1

_params_said_first(doc, req, name, ev) := object.union(ev, {
	"applies": [_params_first_row(r, _applies_to_of(req), nat.applies) | some r in ev.applies],
	"subject_rows": [[_params_first_row(r, _checks_of(req)[r.check], [x | some xs in nat.subject_rows; some x in xs]) | some r in rows] | some rows in ev.subject_rows],
}) if {
	_params_not_an_object
	nat := _evaluation_with(doc, req, name, _fixed(req)) with data.ergo_params as null
		with data.ergo_unreadable as _unreadable_but_params
} else := ev

_unreadable_but_params := [u | some u in data.ergo_unreadable; u.name != "$params"]

_params_first_row(row, check, nat) := object.union(row, {"message": _params_first_message(row, nat)}) if {
	row.passed == false
	not _m_reads_params(check)
} else := row

_params_first_message(row, nat) := concat("; ", [_m_isnt("$params", data.ergo_params, "an object"), n.message]) if {
	some n in nat
	_same_row(n, row)
	n.passed == false
} else := _m_isnt("$params", data.ergo_params, "an object")

_same_row(a, b) if {
	a.subject == b.subject
	a.check == b.check
	object.get(a, "in", null) == object.get(b, "in", null)
}

_params_applies_message(evals, req, matched, entry) := {"message": concat("; ", ms)} if {
	matched == false
	_params_not_an_object
	_m_reads_params(_applies_to_of(req))
	nat := _applies_evals(req, entry.subject, _fixed(req).filter_flaws) with data.ergo_params as null
		with data.ergo_unreadable as _unreadable_but_params
	ms := _once([m |
		some n in _applies_to_names(req)
		evals[n].passed == false
		some m in _params_condition_said(evals[n], nat[n], _applies_to_of(req)[n])
	])
} else := _m_applies(evals, req, matched)

_params_condition_said(e, nat, check) := [e.message] if _m_reads_params(check)

else := [nat.message] if nat.passed == false

else := []
