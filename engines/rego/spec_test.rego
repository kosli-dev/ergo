package spec_test

import data.ergo

known_differences := set()

failures := union({_topic_failures(topic) | some topic, _ in data.spec.cases})

_topic_failures(topic) := _failures(topic, data.spec.cases[topic])

_failures(topic, groups) := {concat(" / ", [topic, group.description, c.description]) |
	some group in groups
	some c in group.cases
	not _passes(group, c)
}

_known_in(topic) := known_differences & _case_names(topic)

_compiled_differences(topic) := _differences_compiled(topic, data.spec.cases[topic])

_differences_compiled(topic, groups) := {concat(" / ", [topic, group.description, c.description]) |
	some group in groups
	form := json.unmarshal(json.marshal(ergo.compile(group.policy)))
	some c in group.cases
	ergo.report(c.input, form, object.get(group, "params", {})) != _report(group, c)
}

_case_names(topic) := {concat(" / ", [topic, group.description, c.description]) |
	some group in data.spec.cases[topic]
	some c in group.cases
}

test_every_known_difference_names_a_case if known_differences - union({_case_names(topic) | some topic, _ in data.spec.cases}) == set()

_tested_topics := {"any_of", "compare", "compare_time", "contains", "deep_walks", "derived", "distinct", "equals", "for", "in", "messages", "missing", "non_empty_string", "parts", "patterns", "present", "range", "requirements", "sentences", "subject_name", "subjects", "that", "walks"}

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

test_the_deep_walks_cases_pass if {
	_topic_failures("deep_walks") == _known_in("deep_walks")
	_compiled_differences("deep_walks") == set()
}

test_the_distinct_cases_pass_part_1_of_20 if _case_part_passes("distinct", 0, 20)

test_the_distinct_cases_pass_part_2_of_20 if _case_part_passes("distinct", 1, 20)

test_the_distinct_cases_pass_part_3_of_20 if _case_part_passes("distinct", 2, 20)

test_the_distinct_cases_pass_part_4_of_20 if _case_part_passes("distinct", 3, 20)

test_the_distinct_cases_pass_part_5_of_20 if _case_part_passes("distinct", 4, 20)

test_the_distinct_cases_pass_part_6_of_20 if _case_part_passes("distinct", 5, 20)

test_the_distinct_cases_pass_part_7_of_20 if _case_part_passes("distinct", 6, 20)

test_the_distinct_cases_pass_part_8_of_20 if _case_part_passes("distinct", 7, 20)

test_the_distinct_cases_pass_part_9_of_20 if _case_part_passes("distinct", 8, 20)

test_the_distinct_cases_pass_part_10_of_20 if _case_part_passes("distinct", 9, 20)

test_the_distinct_cases_pass_part_11_of_20 if _case_part_passes("distinct", 10, 20)

test_the_distinct_cases_pass_part_12_of_20 if _case_part_passes("distinct", 11, 20)

test_the_distinct_cases_pass_part_13_of_20 if _case_part_passes("distinct", 12, 20)

test_the_distinct_cases_pass_part_14_of_20 if _case_part_passes("distinct", 13, 20)

test_the_distinct_cases_pass_part_15_of_20 if _case_part_passes("distinct", 14, 20)

test_the_distinct_cases_pass_part_16_of_20 if _case_part_passes("distinct", 15, 20)

test_the_distinct_cases_pass_part_17_of_20 if _case_part_passes("distinct", 16, 20)

test_the_distinct_cases_pass_part_18_of_20 if _case_part_passes("distinct", 17, 20)

test_the_distinct_cases_pass_part_19_of_20 if _case_part_passes("distinct", 18, 20)

test_the_distinct_cases_pass_part_20_of_20 if _case_part_passes("distinct", 19, 20)

test_the_distinct_cases_pass_compiled_part_1_of_20 if _differences_compiled("distinct", _case_part("distinct", 0, 20)) == set()

test_the_distinct_cases_pass_compiled_part_2_of_20 if _differences_compiled("distinct", _case_part("distinct", 1, 20)) == set()

test_the_distinct_cases_pass_compiled_part_3_of_20 if _differences_compiled("distinct", _case_part("distinct", 2, 20)) == set()

test_the_distinct_cases_pass_compiled_part_4_of_20 if _differences_compiled("distinct", _case_part("distinct", 3, 20)) == set()

test_the_distinct_cases_pass_compiled_part_5_of_20 if _differences_compiled("distinct", _case_part("distinct", 4, 20)) == set()

test_the_distinct_cases_pass_compiled_part_6_of_20 if _differences_compiled("distinct", _case_part("distinct", 5, 20)) == set()

test_the_distinct_cases_pass_compiled_part_7_of_20 if _differences_compiled("distinct", _case_part("distinct", 6, 20)) == set()

test_the_distinct_cases_pass_compiled_part_8_of_20 if _differences_compiled("distinct", _case_part("distinct", 7, 20)) == set()

test_the_distinct_cases_pass_compiled_part_9_of_20 if _differences_compiled("distinct", _case_part("distinct", 8, 20)) == set()

test_the_distinct_cases_pass_compiled_part_10_of_20 if _differences_compiled("distinct", _case_part("distinct", 9, 20)) == set()

test_the_distinct_cases_pass_compiled_part_11_of_20 if _differences_compiled("distinct", _case_part("distinct", 10, 20)) == set()

test_the_distinct_cases_pass_compiled_part_12_of_20 if _differences_compiled("distinct", _case_part("distinct", 11, 20)) == set()

test_the_distinct_cases_pass_compiled_part_13_of_20 if _differences_compiled("distinct", _case_part("distinct", 12, 20)) == set()

test_the_distinct_cases_pass_compiled_part_14_of_20 if _differences_compiled("distinct", _case_part("distinct", 13, 20)) == set()

test_the_distinct_cases_pass_compiled_part_15_of_20 if _differences_compiled("distinct", _case_part("distinct", 14, 20)) == set()

test_the_distinct_cases_pass_compiled_part_16_of_20 if _differences_compiled("distinct", _case_part("distinct", 15, 20)) == set()

test_the_distinct_cases_pass_compiled_part_17_of_20 if _differences_compiled("distinct", _case_part("distinct", 16, 20)) == set()

test_the_distinct_cases_pass_compiled_part_18_of_20 if _differences_compiled("distinct", _case_part("distinct", 17, 20)) == set()

test_the_distinct_cases_pass_compiled_part_19_of_20 if _differences_compiled("distinct", _case_part("distinct", 18, 20)) == set()

test_the_distinct_cases_pass_compiled_part_20_of_20 if _differences_compiled("distinct", _case_part("distinct", 19, 20)) == set()

test_the_equals_cases_pass if {
	_topic_failures("equals") == _known_in("equals")
	_compiled_differences("equals") == set()
}

test_the_in_cases_pass if {
	_topic_failures("in") == _known_in("in")
	_compiled_differences("in") == set()
}

test_the_subject_name_cases_pass_part_1_of_4 if _part_passes("subject_name", 0, 4)

test_the_subject_name_cases_pass_part_2_of_4 if _part_passes("subject_name", 1, 4)

test_the_subject_name_cases_pass_part_3_of_4 if _part_passes("subject_name", 2, 4)

test_the_subject_name_cases_pass_part_4_of_4 if _part_passes("subject_name", 3, 4)

test_the_subject_name_cases_pass_compiled_part_1_of_4 if _differences_compiled("subject_name", _part("subject_name", 0, 4)) == set()

test_the_subject_name_cases_pass_compiled_part_2_of_4 if _differences_compiled("subject_name", _part("subject_name", 1, 4)) == set()

test_the_subject_name_cases_pass_compiled_part_3_of_4 if _differences_compiled("subject_name", _part("subject_name", 2, 4)) == set()

test_the_subject_name_cases_pass_compiled_part_4_of_4 if _differences_compiled("subject_name", _part("subject_name", 3, 4)) == set()

test_the_that_cases_pass if {
	_topic_failures("that") == _known_in("that")
	_compiled_differences("that") == set()
}

test_the_messages_cases_pass if {
	_topic_failures("messages") == _known_in("messages")
	_compiled_differences("messages") == set()
}

test_the_missing_cases_pass if {
	_topic_failures("missing") == _known_in("missing")
	_compiled_differences("missing") == set()
}

test_the_non_empty_string_cases_pass if {
	_topic_failures("non_empty_string") == _known_in("non_empty_string")
	_compiled_differences("non_empty_string") == set()
}

test_the_parts_cases_pass_part_1_of_3 if _part_passes("parts", 0, 3)

test_the_parts_cases_pass_part_2_of_3 if _part_passes("parts", 1, 3)

test_the_parts_cases_pass_part_3_of_3 if _part_passes("parts", 2, 3)

test_the_parts_cases_pass_compiled_part_1_of_3 if _differences_compiled("parts", _part("parts", 0, 3)) == set()

test_the_parts_cases_pass_compiled_part_2_of_3 if _differences_compiled("parts", _part("parts", 1, 3)) == set()

test_the_parts_cases_pass_compiled_part_3_of_3 if _differences_compiled("parts", _part("parts", 2, 3)) == set()

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

_part(topic, n, parts) := [group | some i, group in data.spec.cases[topic]; i % parts == n]

_case_part(topic, n, parts) := [object.union(group, {"cases": cases}) |
	some i, group in data.spec.cases[topic]
	cases := [c | some j, c in group.cases; (i + j) % parts == n]
	count(cases) > 0
]

_case_part_passes(topic, n, parts) if _failures(topic, _case_part(topic, n, parts)) == known_differences & {concat(" / ", [topic, group.description, c.description]) |
	some group in _case_part(topic, n, parts)
	some c in group.cases
}

_part_passes(topic, n, parts) if _failures(topic, _part(topic, n, parts)) == known_differences & {concat(" / ", [topic, group.description, c.description]) |
	some group in _part(topic, n, parts)
	some c in group.cases
}

test_the_sentences_cases_pass_part_1_of_8 if _part_passes("sentences", 0, 8)

test_the_sentences_cases_pass_part_2_of_8 if _part_passes("sentences", 1, 8)

test_the_sentences_cases_pass_part_3_of_8 if _part_passes("sentences", 2, 8)

test_the_sentences_cases_pass_part_4_of_8 if _part_passes("sentences", 3, 8)

test_the_sentences_cases_pass_part_5_of_8 if _part_passes("sentences", 4, 8)

test_the_sentences_cases_pass_part_6_of_8 if _part_passes("sentences", 5, 8)

test_the_sentences_cases_pass_part_7_of_8 if _part_passes("sentences", 6, 8)

test_the_sentences_cases_pass_part_8_of_8 if _part_passes("sentences", 7, 8)

test_the_sentences_cases_pass_compiled_part_1_of_8 if _differences_compiled("sentences", _part("sentences", 0, 8)) == set()

test_the_sentences_cases_pass_compiled_part_2_of_8 if _differences_compiled("sentences", _part("sentences", 1, 8)) == set()

test_the_sentences_cases_pass_compiled_part_3_of_8 if _differences_compiled("sentences", _part("sentences", 2, 8)) == set()

test_the_sentences_cases_pass_compiled_part_4_of_8 if _differences_compiled("sentences", _part("sentences", 3, 8)) == set()

test_the_sentences_cases_pass_compiled_part_5_of_8 if _differences_compiled("sentences", _part("sentences", 4, 8)) == set()

test_the_sentences_cases_pass_compiled_part_6_of_8 if _differences_compiled("sentences", _part("sentences", 5, 8)) == set()

test_the_sentences_cases_pass_compiled_part_7_of_8 if _differences_compiled("sentences", _part("sentences", 6, 8)) == set()

test_the_sentences_cases_pass_compiled_part_8_of_8 if _differences_compiled("sentences", _part("sentences", 7, 8)) == set()

test_the_subjects_cases_pass_part_1_of_6 if _part_passes("subjects", 0, 6)

test_the_subjects_cases_pass_part_2_of_6 if _part_passes("subjects", 1, 6)

test_the_subjects_cases_pass_part_3_of_6 if _part_passes("subjects", 2, 6)

test_the_subjects_cases_pass_part_4_of_6 if _part_passes("subjects", 3, 6)

test_the_subjects_cases_pass_part_5_of_6 if _part_passes("subjects", 4, 6)

test_the_subjects_cases_pass_part_6_of_6 if _part_passes("subjects", 5, 6)

test_the_subjects_cases_pass_compiled_part_1_of_6 if _differences_compiled("subjects", _part("subjects", 0, 6)) == set()

test_the_subjects_cases_pass_compiled_part_2_of_6 if _differences_compiled("subjects", _part("subjects", 1, 6)) == set()

test_the_subjects_cases_pass_compiled_part_3_of_6 if _differences_compiled("subjects", _part("subjects", 2, 6)) == set()

test_the_subjects_cases_pass_compiled_part_4_of_6 if _differences_compiled("subjects", _part("subjects", 3, 6)) == set()

test_the_subjects_cases_pass_compiled_part_5_of_6 if _differences_compiled("subjects", _part("subjects", 4, 6)) == set()

test_the_subjects_cases_pass_compiled_part_6_of_6 if _differences_compiled("subjects", _part("subjects", 5, 6)) == set()

test_the_derived_cases_pass_part_1_of_6 if _part_passes("derived", 0, 6)

test_the_derived_cases_pass_part_2_of_6 if _part_passes("derived", 1, 6)

test_the_derived_cases_pass_part_3_of_6 if _part_passes("derived", 2, 6)

test_the_derived_cases_pass_part_4_of_6 if _part_passes("derived", 3, 6)

test_the_derived_cases_pass_part_5_of_6 if _part_passes("derived", 4, 6)

test_the_derived_cases_pass_part_6_of_6 if _part_passes("derived", 5, 6)

test_the_derived_cases_pass_compiled_part_1_of_6 if _differences_compiled("derived", _part("derived", 0, 6)) == set()

test_the_derived_cases_pass_compiled_part_2_of_6 if _differences_compiled("derived", _part("derived", 1, 6)) == set()

test_the_derived_cases_pass_compiled_part_3_of_6 if _differences_compiled("derived", _part("derived", 2, 6)) == set()

test_the_derived_cases_pass_compiled_part_4_of_6 if _differences_compiled("derived", _part("derived", 3, 6)) == set()

test_the_derived_cases_pass_compiled_part_5_of_6 if _differences_compiled("derived", _part("derived", 4, 6)) == set()

test_the_derived_cases_pass_compiled_part_6_of_6 if _differences_compiled("derived", _part("derived", 5, 6)) == set()

test_the_for_cases_pass_part_1_of_4 if _part_passes("for", 0, 4)

test_the_for_cases_pass_part_2_of_4 if _part_passes("for", 1, 4)

test_the_for_cases_pass_part_3_of_4 if _part_passes("for", 2, 4)

test_the_for_cases_pass_part_4_of_4 if _part_passes("for", 3, 4)

test_the_for_cases_pass_compiled_part_1_of_4 if _differences_compiled("for", _part("for", 0, 4)) == set()

test_the_for_cases_pass_compiled_part_2_of_4 if _differences_compiled("for", _part("for", 1, 4)) == set()

test_the_for_cases_pass_compiled_part_3_of_4 if _differences_compiled("for", _part("for", 2, 4)) == set()

test_the_for_cases_pass_compiled_part_4_of_4 if _differences_compiled("for", _part("for", 3, 4)) == set()

test_the_walks_cases_pass if {
	_topic_failures("walks") == _known_in("walks")
	_compiled_differences("walks") == set()
}

test_a_case_with_the_wrong_rows_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": []}],
	}]}
}

test_a_case_with_the_wrong_status_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "status": {"s": "not_met"}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_expression_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "expressions": {"s": {"c": "y is present"}}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_refs_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
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
			"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
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
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "violations": [{}], "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_compliant_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "compliant": false, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1}],
		}]}],
	}]}
}

test_a_case_with_the_wrong_report_field_is_listed_by_name if {
	failures == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
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
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": [{
			"requirement": "s", "subject": {"type": "subject", "id": {"x": 1}}, "check": "c",
			"passed": true, "cause": "satisfied", "inputs": [{"name": "x", "value": 1, "locations": ["/x"]}],
		}]}],
	}]}
	_topic_failures("topic") == set() with data.spec.cases as cases
	_known_in("topic") == {"topic / group / case"} with data.spec.cases as cases with known_differences as {"topic / group / case", "other / g / c"}
}

_wrapped_compile(policy) := {"wrapped": policy}

test_a_case_whose_compiled_policy_gives_another_report_is_listed_by_name if {
	_compiled_differences("topic") == {"topic / group / case"} with data.spec.cases as {"topic": [{
		"description": "group",
		"policy": {"ergo_spec": "v0.6-dev", "subjects": {"subject": {"from": "$input"}}, "requirements": {"s": {"subject": "subject", "checks": {"c": "x exists"}}}},
		"cases": [{"description": "case", "input": {"x": 1}, "results": []}],
	}]}
		with data.ergo.compile as _wrapped_compile
}
