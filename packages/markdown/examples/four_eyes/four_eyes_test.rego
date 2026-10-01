package four_eyes_test

import data.ergo

reqs := data.four_eyes.requirements

trail(sha, prs) := {
	"name": sha,
	"compliance_status": {"attestations_statuses": {"pr-review": {
		"attestation_type": "pull_request",
		"pull_requests": prs,
	}}},
}

pr(merge_sha, author, commits, approvers) := {
	"url": "https://github.com/owner/repo/pull/42",
	"merge_commit": merge_sha,
	"author": author,
	"commits": commits,
	"approvers": approvers,
}

commit(username) := {"author_username": username, "timestamp": 1000000}

web_flow_commit := {"author": "GitHub <noreply@github.com>", "timestamp": 1000000}

approval(username, ts) := {"username": username, "timestamp": ts, "state": "APPROVED"}

report(trails) := ergo.report({"trails": trails}, reqs)

failed(trails) := {[v.subject.id, v.check] | some v in ergo.violations(report(trails))}

passes(trails) if {
	report(trails).compliant
	failed(trails) == set()
}

reviewed_by_bob := pr("abc1234", "alice", [commit("alice")], [approval("bob", 1000001)])

test_a_commit_approved_by_someone_else_passes if {
	passes([trail("abc1234", [reviewed_by_bob])])
}

test_a_self_approved_commit_fails if {
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [approval("alice", 1000001)])])])
}

test_a_commit_with_no_attestation_fails if {
	["abc1234", "pr_attestation_present"] in failed([{"name": "abc1234", "compliance_status": {"attestations_statuses": {}}}])
}

test_a_commit_with_no_pull_request_fails if {
	["abc1234", "pull_request_found"] in failed([trail("abc1234", [])])
}

test_a_bot_commit_still_needs_a_reviewed_pull_request if {
	bot := object.union(trail("abc1234", []), {"git_commit_info": {"author": "dependabot[bot] <bot@users.noreply.github.com>"}})
	["abc1234", "pull_request_found"] in failed([bot])
}

test_the_pr_author_needs_approval_when_the_commit_is_not_the_merge_commit if {
	passes([trail("abc1234", [pr("def5678", "alice", [commit("alice")], [approval("bob", 1000001)])])])
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("def5678", "carol", [commit("alice")], [approval("carol", 1000001)])])])
}

test_an_approval_before_the_latest_commit_does_not_count if {
	late := {"author_username": "alice", "timestamp": 1000010}
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice"), late], [approval("bob", 1000005)])])])
}

test_a_pull_request_with_no_approvals_fails if {
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [])])])
}

test_two_authors_who_approve_each_other_pass if {
	both := pr("abc1234", "sami", [commit("sami"), commit("faye")], [approval("faye", 1000001), approval("sami", 1000002)])
	passes([trail("abc1234", [both])])
}

test_two_authors_with_only_one_approving_fail if {
	one := pr("abc1234", "sami", [commit("sami"), commit("faye")], [approval("faye", 1000001)])
	["abc1234", "independently_approved"] in failed([trail("abc1234", [one])])
}

test_an_unlinked_author_passes_only_when_every_approver_is_linked if {
	every unlinked in [{"author_username": null, "timestamp": 1000000}, {"timestamp": 1000000}, commit("ghost")] {
		passes([trail("abc1234", [pr("abc1234", "alice", [unlinked], [approval("bob", 1000001)])])])
		["abc1234", "identities_resolved"] in failed([trail("abc1234", [pr("abc1234", "alice", [unlinked], [approval("", 1000001)])])])
	}
}

test_a_deleted_account_cannot_approve if {
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [approval("ghost", 1000001)])])])
}

test_an_approver_with_no_username_cannot_approve if {
	every approver in [{"username": null, "timestamp": 1000001, "state": "APPROVED"}, {"timestamp": 1000001, "state": "APPROVED"}] {
		["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [approver])])])
	}
}

test_a_web_flow_commit_is_explained if {
	passes([trail("abc1234", [pr("abc1234", "alice", [commit("alice"), web_flow_commit], [approval("bob", 1000001)])])])
}

test_a_merge_commit_with_only_web_flow_commits_needs_the_pr_author_approved if {
	passes([trail("abc1234", [pr("abc1234", "alice", [web_flow_commit], [approval("bob", 1000001)])])])
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [web_flow_commit], [approval("alice", 1000001)])])])
}

test_one_approved_pull_request_is_enough if {
	unapproved := pr("abc1234", "alice", [commit("alice")], [])
	passes([trail("abc1234", [unapproved, reviewed_by_bob])])
	["abc1234", "independently_approved"] in failed([trail("abc1234", [unapproved, unapproved])])
}

test_only_the_failing_commit_is_reported if {
	failed([trail("abc1234", [reviewed_by_bob]), trail("bbb2222", [])]) == {
		["bbb2222", "pull_request_found"],
		["bbb2222", "identities_resolved"],
		["bbb2222", "independently_approved"],
	}
}

test_dismissed_and_change_requests_are_not_approvals if {
	every state in ["DISMISSED", "CHANGES_REQUESTED"] {
		review := {"username": "bob", "timestamp": 1000001, "state": state}
		["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [review])])])
	}
	dismissed := {"username": "bob", "timestamp": 1000001, "state": "DISMISSED"}
	passes([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [dismissed, approval("carol", 1000002)])])])
}

test_an_approval_with_a_string_timestamp_does_not_count if {
	review := {"username": "bob", "timestamp": "1000005", "state": "APPROVED"}
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice")], [review])])])
}

test_a_commit_with_no_timestamp_makes_the_approval_uncheckable if {
	untimed := {"author_username": "alice"}
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [commit("alice"), untimed], [approval("bob", 1000001)])])])
}

test_a_pull_request_with_no_commits_fails if {
	["abc1234", "independently_approved"] in failed([trail("abc1234", [pr("abc1234", "alice", [], [approval("bob", 1000001)])])])
}

test_two_pull_request_attestations_fail_as_ambiguous if {
	two := {"name": "abc1234", "compliance_status": {"attestations_statuses": {
		"pr-a": {"attestation_type": "pull_request", "pull_requests": [reviewed_by_bob]},
		"pr-b": {"attestation_type": "pull_request", "pull_requests": []},
	}}}
	some row in report([two]).results
	row.check == "pr_attestation_present"
	row.cause == "ambiguous"
	not report([two]).compliant
}

initial_commit(type, compliant) := {"name": "0000001", "compliance_status": {"attestations_statuses": {"initial-commit": {
	"attestation_type": type,
	"is_compliant": compliant,
}}}}

test_a_first_commit_passes_on_its_initial_commit_attestation if {
	passes([initial_commit("custom:initial-commit", true)])
	some row in report([initial_commit("custom:initial-commit", true)]).results
	row.check == "pr_attestation_present"
	row.cause == "substituted"
}

test_a_non_compliant_initial_commit_attestation_does_not_stand_in if {
	["0000001", "pr_attestation_present"] in failed([initial_commit("custom:initial-commit", false)])
}

test_the_initial_commit_attestation_is_matched_by_its_full_type if {
	every type in ["custom", "initial-commit"] {
		["0000001", "pr_attestation_present"] in failed([initial_commit(type, true)])
	}
}

test_a_trail_that_names_no_commit_fails if {
	["", "commit_identified"] in failed([trail("", [reviewed_by_bob])])
}

test_missing_or_wrong_trails_fail if {
	every doc in [{}, {"trails": "not-a-list"}] {
		not ergo.report(doc, reqs).compliant
	}
}

test_the_report_has_a_row_for_every_check_of_a_passing_commit if {
	{r.check | some r in report([trail("abc1234", [reviewed_by_bob])]).results; r.subject.id == "abc1234"; r.passed} == {
		"commit_identified",
		"pr_attestation_present",
		"pull_request_found",
		"identities_resolved",
		"independently_approved",
	}
}
