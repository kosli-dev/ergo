package ergo_test

import data.ergo
import rego.v1

test_is_violation_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := report(
		{"items": [
			{"id": "a", "signed": true, "reviewed": true},
			{"id": "b", "signed": false, "reviewed": true},
		]},
		require_req("some"),
	)
	some row in rep.results
	row.passed == false
	not ergo._is_violation(rep.requirements, row)
}

test_definition_field_reads_only_the_requirements_so_violations_stay_linear_in_subjects if {
	rep := report({"items": [{"id": "a", "signed": true}]}, violating_req)
	some row in rep.results
	row.check == "reviewed"
	ergo._definition_field(rep.requirements, row, "description") == "Reviewed"
}
