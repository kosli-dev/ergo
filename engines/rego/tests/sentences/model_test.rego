package ergo_test

import data.ergo
import rego.v1

test_requirements_and_checks_that_are_not_objects_are_left_to_the_other_rules if {
	ergo._s_requirements(null, {}) == null
	ergo._s_requirements({"r": 1}, {}) == {"r": 1}
	ergo._s_requirements({"r": {"checks": []}}, {}) == {"r": {"checks": []}}
	ergo._s_requirements({"r": {"checks": {"d": 1}}}, {}) == {"r": {"checks": {"d": 1}}}
}

test_a_check_is_read_as_a_sentence_only_where_the_policy_wrote_one if {
	not ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"}, false)
	ergo._s_read({"op": "present", "path": ["x"], "expression": "x exists"}, true)
	ergo._s_sentences({"r": {"checks": ["x exists"]}, "q": 1}, {"r": {"checks": ["x exists"]}, "q": 1}) == set()
	ergo._s_sentences(null, null) == set()
	ergo._s_written_here({}, "applies_to", "f") == false
}

test_a_sentence_that_reads_into_no_check_is_written_wrong_rather_than_run if {
	ergo._s_or_unrunnable(set()) == {"can't be run"}
	ergo._s_or_unrunnable({"x"}) == {"x"}
}

test_every_and_some_read_into_a_walk_with_its_conditions if {
	c := ergo._s_written_check(`every approvers.username whose state is "APPROVED", if any, is in $params.staff`)
	c.op == "every"
	c.path == ["approvers", "username"]
	c.whose == [{"op": "equals", "path": ["state"], "value": "APPROVED"}]
	c.check.op == "in"
	c.if_any == true
}
