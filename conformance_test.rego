package conformance_test

import data.ergo

generated := {area: _generated_topics(topics) | some area, topics in data.conformance}

_generated_topics(topics) := {topic: [_generated_group(group) | some group in groups] | some topic, groups in topics}

failures contains concat(" / ", [area, topic, group.description, c.description]) if {
	some area, topic
	some i, group in data.conformance[area][topic]
	some j, c in group.cases
	not generated[area][topic][i].cases[j] == c
}

test_every_conformance_case_gives_its_expected_report if generated == data.conformance

test_a_case_with_the_wrong_report_is_listed_by_name if {
	failures == {"area / topic / group / case"} with data.conformance as {"area": {"topic": [{
		"description": "group",
		"requirements": {},
		"cases": [{"description": "case", "input": {}, "report": {}}],
	}]}}
}

_generated_group(group) := object.union(group, {"cases": [_generated_case(group, c) | some c in group.cases]})

_generated_case(group, c) := object.union(c, object.union(
	{"report": _report(group, c)},
	{"violations": ergo.violations(_report(group, c)) | "violations" in object.keys(c)},
))

_report(group, c) := ergo.report(c.input, group.requirements) if not "params" in object.keys(group)

_report(group, c) := r if {
	"params" in object.keys(group)
	r := ergo.report(c.input, group.requirements) with data.params as group.params
}
