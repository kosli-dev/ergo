package ergo

import rego.v1

violations(report) := _violations(report, _shadowing_report_parents(report))

_shadowing_report_parents(report) := _shadowing_in(report, _some_requirements(report))

_shadowing_in(report, some_requirements) := set() if count(some_requirements) == 0

else := {[requirement, subject.in] | some [requirement, subject] in (_child_check_subjects(report, some_requirements) - _failed_child_check_subjects(report, some_requirements))}

_some_requirements(report) := {name | some name, req in report.requirements; req.require == "some"}

_child_check_subjects(report, some_requirements) := {[row.requirement, row.subject] |
	some row in report.results
	_child_check_row(some_requirements, row)
}

_failed_child_check_subjects(report, some_requirements) := {[row.requirement, row.subject] |
	some row in report.results
	_child_check_row(some_requirements, row)
	row.passed == false
}

_child_check_row(some_requirements, row) if {
	row.requirement in some_requirements
	not startswith(row.check, "$")
	object.get(row.subject, "in", {}) != {}
}

_violations(report, shadowing) := [object.union(
	{
		"requirement": row.requirement,
		"subject": row.subject,
		"check": row.check,
		"description": _definition_field(report.requirements, row, "description"),
		"expression": _definition_field(report.requirements, row, "expression"),
		"inputs": array.concat(row.inputs, [r | some r in _recorded_refs(report.requirements, row); not r in row.inputs]),
		"cause": row.cause,
	},
	object.union(object.union(_failed_items_of(row), _failed_assertions_of(row)), _message_of(row)),
) |
	some row in _unshadowed_results(report, shadowing)
	_is_violation(report.requirements, row)
]

_unshadowed_results(report, shadowing) := report.results if count(shadowing) == 0

else := [row | some row in report.results; not _shadowed_in_report(row, shadowing)]

_shadowed_in_report(row, shadowing) if {
	count(shadowing) > 0
	not startswith(row.check, "$")
	[row.requirement, object.get(row.subject, "in", {})] in shadowing
}

_message_of(row) := {"message": row.message} if "message" in object.keys(row)

_message_of(row) := {} if not "message" in object.keys(row)

_failed_items_of(row) := {"failed_items": row.failed_items} if "failed_items" in object.keys(row)

_failed_items_of(row) := {} if not "failed_items" in object.keys(row)

_failed_assertions_of(row) := {"failed_assertions": row.failed_assertions} if "failed_assertions" in object.keys(row)

_failed_assertions_of(row) := {} if not "failed_assertions" in object.keys(row)

default _recorded_refs(_, _) := []

_recorded_refs(requirements, row) := refs if {
	refs := requirements[row.requirement].checks[row.check]["$refs"]
	is_array(refs)
}

default _is_violation(_, _) := false

_is_violation(requirements, row) if {
	row.passed == false
	not _out_of_scope_row(row)
	not _reported_as_holding(requirements, row.requirement)
}

_reported_as_holding(requirements, name) if requirements[name].status in {"met", "not_applicable"}

_out_of_scope_row(row) if {
	row.check == "$applies"
	row.cause == "value"
}

_definition_field(requirements, row, key) := object.get(
	requirements,
	[row.requirement, "checks", row.check, key],
	"",
)
