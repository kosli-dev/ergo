package workings

by_subject(report) := {id: rows(report, id) |
	some r in report.results
	id := r.subject.id
	id != null
}

rows(report, id) := [row |
	some r in report.results
	r.subject.id == id
	not startswith(r.check, "$")
	check := report.requirements[r.requirement].checks[r.check]
	row := {
		"requirement": r.requirement,
		"clause": check.description,
		"check": r.check,
		"inputs": r.inputs,
		"expression": check.expression,
		"passed": r.passed,
	}
]
