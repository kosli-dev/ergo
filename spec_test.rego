package spec_test

import data.ergo

known_differences := {
	"present / present written wrong / fails every check as ill_formed whatever the subject holds",
	"present / present as a filter / rules a subject out when the field is missing, even though the other filter can't read it",
	"present / present as a filter / rules a subject out when the field is null",
	"present / present as a filter / keeps a subject in scope when the field is there",
}

failures contains concat(" / ", [topic, group.description, c.description]) if {
	some topic, groups in data.spec.cases
	some group in groups
	some c in group.cases
	not _passes(group, c)
}

test_every_spec_case_passes_except_the_known_differences if failures == known_differences

test_a_case_with_the_wrong_rows_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": []}],
	}]}
}

test_a_case_with_the_wrong_status_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "status": {"s": "not_met"}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_compliant_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "compliant": false, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

_passes(group, c) if {
	report := _report(group, c)
	[r | some r in report.results; _compared(r.check, c)] == c.results
	every name, status in object.get(c, "status", {}) {
		report.requirements[name].status == status
	}
	object.get(c, "compliant", report.compliant) == report.compliant
}

_report(group, c) := ergo.report_with_params(c.input, group.params, group.policy) if "params" in object.keys(group)

_report(group, c) := ergo.report(c.input, group.policy) if not "params" in object.keys(group)

_compared(check, _) if not startswith(check, "$")

_compared("$applies", _)

_compared(check, c) if {
	some r in c.results
	r.check == check
}
