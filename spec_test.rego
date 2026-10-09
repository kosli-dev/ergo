package spec_test

import data.ergo

known_differences := set()

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

test_a_case_with_the_wrong_expression_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "expressions": {"s": {"c": "y is present"}}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_refs_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "refs": {"s": {"c": [{"name": "$$params.x", "value": 1}]}}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_requirement_entry_is_listed_by_name if {
	every want in [{"subjects": {"matching": 2, "total": 1}}, {"checks": {"$min_subjects": {"description": "nope"}}}] {
		failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
			"description": "group",
			"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
			"cases": [{"description": "case", "input": {"x": 1}, "requirements": {"s": want}, "results": [{
				"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
				"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
			}]}],
		}]}
	}
}

test_a_case_with_the_wrong_violations_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"s": {"checks": {"c": {"op": "present", "path": ["x"]}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "violations": [{}], "results": [{
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
	every name, checks in object.get(c, "expressions", {}) {
		every check, expression in checks {
			report.requirements[name].checks[check].expression == expression
		}
	}
	every name, want in object.get(c, "requirements", {}) {
		every field, value in want {
			_field_matches(report.requirements[name], field, value)
		}
	}
	object.get(c, "violations", ergo.violations(report)) == ergo.violations(report)
	every name, checks in object.get(c, "refs", {}) {
		every check, refs in checks {
			object.get(report.requirements[name].checks[check], "$refs", []) == refs
		}
	}
}

_field_matches(entry, "checks", value) if {
	every check, fields in value {
		every field, value in fields {
			entry.checks[check][field] == value
		}
	}
}

_field_matches(entry, field, value) if {
	field != "checks"
	entry[field] == value
}

_report(group, c) := ergo.report_with_params(c.input, group.params, group.policy) if "params" in object.keys(group)

_report(group, c) := ergo.report(c.input, group.policy) if not "params" in object.keys(group)

_compared(check, _) if not startswith(check, "$")

_compared("$applies", _)

_compared(check, c) if {
	some r in c.results
	r.check == check
}
