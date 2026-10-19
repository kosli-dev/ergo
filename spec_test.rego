package spec_test

import data.ergo

known_differences := {
	"derived / a count in the whose of a count / counts the items whose own count passes, and shows every item",
	"derived / a count in the whose of a count / fails as absent when an item's list is missing, so the item cannot be decided",
	"derived / a count in the whose of a sum / adds only the items whose own count passes",
	"derived / a count with is between / fails as absent when the list is missing",
	"derived / a count with is between / fails as null when the list is null",
	"derived / a count with is between / fails as unusable when the list is a string",
	"derived / a count with is between / fails as value above the upper bound",
	"derived / a count with is between / fails as value on an empty list, which counts 0",
	"derived / a count with is between / passes at the lower bound",
	"derived / a count with is between / passes at the upper bound",
	"derived / a count with is between / passes between the bounds",
	"derived / a plus with is between / fails as absent when the path is missing",
	"derived / a plus with is between / fails as value above the upper bound",
	"derived / a plus with is between / passes between the bounds",
	"derived / a sum with is between / fails as unusable when a value is text",
	"derived / a sum with is between / fails as value below the lower bound",
	"derived / a sum with is between / passes at the upper bound",
	"derived / a sum with is between / passes between the bounds",
	"derived / days elapsed added to another term / adds a number to the elapsed days",
	"derived / days elapsed added to another term / fails as absent when the end is missing",
	"derived / days elapsed added to another term / fails as value when the end is before the start, and shows no number",
	"derived / days elapsed added to another term / fails as value when the sum is different",
	"derived / days elapsed added to another term, first / adds the elapsed days to a number",
	"derived / days elapsed added to another term, first / fails as absent when the start is missing",
	"derived / days elapsed in a plus on the right side / compares a field with a number plus the elapsed days",
	"derived / days elapsed in a plus on the right side / fails as value when the field is not more",
	"derived / days elapsed in the whose of a count / counts the items whose elapsed days pass, and shows every item",
	"derived / days elapsed in the whose of a count / fails as absent when an item cannot be decided because its end is missing",
	"derived / days elapsed in the whose of a count / fails as value when fewer items pass",
	"derived / days elapsed in the whose of a count / leaves out an item whose end is before its start",
	"derived / days elapsed in the whose of an every / checks the items whose elapsed days pass, and leaves the others out",
	"derived / days elapsed in the whose of an every / fails as value when a kept item fails",
	"derived / days elapsed in the whose of an every / fails as value when whose leaves no item",
	"derived / days elapsed in the whose of an every / leaves out an item whose end is before its start",
	"derived / days elapsed on the right side of a phrase / compares a field with the elapsed days",
	"derived / days elapsed on the right side of a phrase / fails as absent when the end is missing",
	"derived / days elapsed on the right side of a phrase / fails as value when they differ",
	"derived / days elapsed with is between / fails as absent when the end is missing",
	"derived / days elapsed with is between / fails as value above the upper bound",
	"derived / days elapsed with is between / fails as value when the end is before the start, and shows no number",
	"derived / days elapsed with is between / passes at the lower bound",
	"derived / days elapsed with is between / passes at the upper bound",
	"sentences / a time is after a written number / fails as unusable when the field is a string, because the written time is a number",
	"sentences / a time is after a written number / fails as value on the same number",
	"sentences / a time is after a written number / passes when the number is higher",
	"sentences / a time is before a written time / fails as absent when the field is missing",
	"sentences / a time is before a written time / fails as unusable when the field is a number, because the written time is a string",
	"sentences / a time is before a written time / fails as unusable when the field is text that is not a time",
	"sentences / a time is before a written time / fails as value on the same instant written in another offset",
	"sentences / a time is before a written time / passes when the order holds",
	"sentences / a time is on or before a written time / fails as value when it is later",
	"sentences / a time is on or before a written time / passes on the same instant written in another offset",
	"sentences / is in a list read with named by / fails as value when it does not",
	"sentences / is in a list read with named by / passes when the list under the key has the value",
	"sentences / is in a list read with named by a key that has no list / fails as absent whatever the field holds",
	"sentences / matches patterns read with named by / fails as value when only a pattern under another key matches",
	"sentences / matches patterns read with named by / passes when a pattern under the key matches",
}

failures := union({_topic_failures(topic) | some topic, _ in data.spec.cases})

_topic_failures(topic) := {concat(" / ", [topic, group.description, c.description]) |
	some group in data.spec.cases[topic]
	some c in group.cases
	not _passes(group, c)
}

_known_in(topic) := known_differences & _case_names(topic)

_compiled_differences(topic) := {concat(" / ", [topic, group.description, c.description]) |
	some group in data.spec.cases[topic]
	form := json.unmarshal(json.marshal(ergo.compile(group.policy)))
	some c in group.cases
	ergo.report(c.input, form, object.get(group, "params", {})) != _report(group, c)
}

_case_names(topic) := {concat(" / ", [topic, group.description, c.description]) |
	some group in data.spec.cases[topic]
	some c in group.cases
}

test_every_known_difference_names_a_case if known_differences - union({_case_names(topic) | some topic, _ in data.spec.cases}) == set()

_tested_topics := {"any_of", "compare", "compare_time", "contains", "custom", "derived", "empty", "equals", "for", "in", "lists", "missing", "non_empty_string", "parts", "patterns", "present", "range", "requirements", "sentences", "subjects", "substitutes", "walks"}

test_every_folder_of_cases_has_a_test_of_its_own if {t | some t, _ in data.spec.cases} == _tested_topics

test_the_any_of_cases_pass if {
	_topic_failures("any_of") == _known_in("any_of")
	_compiled_differences("any_of") == set()
}

test_the_compare_cases_pass if {
	_topic_failures("compare") == _known_in("compare")
	_compiled_differences("compare") == set()
}

test_the_compare_time_cases_pass if {
	_topic_failures("compare_time") == _known_in("compare_time")
	_compiled_differences("compare_time") == set()
}

test_the_contains_cases_pass if {
	_topic_failures("contains") == _known_in("contains")
	_compiled_differences("contains") == set()
}

test_the_custom_cases_pass if {
	_topic_failures("custom") == _known_in("custom")
	_compiled_differences("custom") == set()
}

test_the_derived_cases_pass if {
	_topic_failures("derived") == _known_in("derived")
	_compiled_differences("derived") == set()
}

test_the_empty_cases_pass if {
	_topic_failures("empty") == _known_in("empty")
	_compiled_differences("empty") == set()
}

test_the_equals_cases_pass if {
	_topic_failures("equals") == _known_in("equals")
	_compiled_differences("equals") == set()
}

test_the_for_cases_pass if {
	_topic_failures("for") == _known_in("for")
	_compiled_differences("for") == set()
}

test_the_in_cases_pass if {
	_topic_failures("in") == _known_in("in")
	_compiled_differences("in") == set()
}

test_the_lists_cases_pass if {
	_topic_failures("lists") == _known_in("lists")
	_compiled_differences("lists") == set()
}

test_the_missing_cases_pass if {
	_topic_failures("missing") == _known_in("missing")
	_compiled_differences("missing") == set()
}

test_the_non_empty_string_cases_pass if {
	_topic_failures("non_empty_string") == _known_in("non_empty_string")
	_compiled_differences("non_empty_string") == set()
}

test_the_parts_cases_pass if {
	_topic_failures("parts") == _known_in("parts")
	_compiled_differences("parts") == set()
}

test_the_patterns_cases_pass if {
	_topic_failures("patterns") == _known_in("patterns")
	_compiled_differences("patterns") == set()
}

test_the_present_cases_pass if {
	_topic_failures("present") == _known_in("present")
	_compiled_differences("present") == set()
}

test_the_range_cases_pass if {
	_topic_failures("range") == _known_in("range")
	_compiled_differences("range") == set()
}

test_the_requirements_cases_pass if {
	_topic_failures("requirements") == _known_in("requirements")
	_compiled_differences("requirements") == set()
}

test_the_sentences_cases_pass if {
	_topic_failures("sentences") == _known_in("sentences")
	_compiled_differences("sentences") == set()
}

test_the_subjects_cases_pass if {
	_topic_failures("subjects") == _known_in("subjects")
	_compiled_differences("subjects") == set()
}

test_the_substitutes_cases_pass if {
	_topic_failures("substitutes") == _known_in("substitutes")
	_compiled_differences("substitutes") == set()
}

test_the_walks_cases_pass if {
	_topic_failures("walks") == _known_in("walks")
	_compiled_differences("walks") == set()
}

test_a_case_with_the_wrong_rows_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": []}],
	}]}
}

test_a_case_with_the_wrong_status_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "status": {"s": "not_met"}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_expression_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "expressions": {"s": {"c": "y is present"}}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_refs_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
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
			"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
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
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "violations": [{}], "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_compliant_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "compliant": false, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_report_field_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "report": {"description": "nope"}, "results": [{
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
	_violations_match(c, report)
	every field, value in object.get(c, "report", {}) {
		report[field] == value
	}
	every name, checks in object.get(c, "refs", {}) {
		every check, refs in checks {
			object.get(report.requirements[name].checks[check], "$refs", []) == refs
		}
	}
}

_violations_match(c, _) if not "violations" in object.keys(c)

_violations_match(c, report) if c.violations == ergo.violations(report)

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

_report(group, c) := ergo.report(c.input, group.policy, group.params) if "params" in object.keys(group)

_report(group, c) := ergo.report(c.input, group.policy, {}) if not "params" in object.keys(group)

_compared(check, _) if not startswith(check, "$")

_compared("$applies", _)

_compared(check, c) if {
	some r in c.results
	r.check == check
}

test_a_known_difference_that_passes_fails_its_folder if {
	cases := {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
	_topic_failures("topic") == set() with data.spec.cases as cases
	_known_in("topic") == {"topic / group / case"} with data.spec.cases as cases with known_differences as {"topic / group / case", "other / g / c"}
}

_wrapped_compile(policy) := {"wrapped": policy}

test_a_case_whose_compiled_policy_gives_another_report_is_listed_by_name if {
	_compiled_differences("topic") == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"subjects": {"subject": {"from": []}}, "requirements": {"s": {"subject": "subject", "checks": {"c": {"op": "present", "path": ["x"]}}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": []}],
	}]}
		with data.ergo.compile as _wrapped_compile
}
