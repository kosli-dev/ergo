package multi_subject_test

import data.ergo

reqs := data.multi_subject.requirements

test_each_requirement_keeps_its_own_subject if {
	reqs.artifact_identified.subject_type == "artifact"
	reqs.artifact_identified.from == ["artifacts"]
	reqs.artifact_identified.id == ["fingerprint"]

	reqs.change_reviewed.subject_type == "pull request"
	reqs.change_reviewed.from == ["pull_requests"]
	reqs.change_reviewed.id == ["url"]
}

test_properties_resolve_against_their_own_subject if {
	reqs.artifact_identified.checks.fingerprint_recorded.path == ["fingerprint"]
	reqs.change_reviewed.checks.protected_branch.path == ["base_ref"]
}

test_a_collection_check_survives_subject_scoping if {
	check := reqs.change_reviewed.checks.commits_signed
	check.op == "all"
	check.path == ["commits"]
	check.check == {"op": "equals", "path": ["verified"], "value": true}
}

test_scope_and_minimum_are_per_requirement if {
	reqs.change_reviewed.applies_to.merged.value == "MERGED"
	reqs.change_reviewed.min_subjects == 1
	not reqs.artifact_identified.min_subjects
}

test_compiled_policy_checks_both_subjects if {
	release := {
		"artifacts": [{"fingerprint": "abc", "build_url": "https://ci/1"}],
		"pull_requests": [{
			"url": "https://git/pr/1",
			"state": "MERGED",
			"base_ref": "main",
			"commits": [{"verified": true}, {"verified": false}],
		}],
	}
	violations := ergo.violations(ergo.report(release, reqs))
	{[v.requirement, v.check, v.cause] | some v in violations} == {["change_reviewed", "commits_signed", "value"]}
}
