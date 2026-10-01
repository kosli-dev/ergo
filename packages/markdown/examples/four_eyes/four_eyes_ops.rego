package ergo

op_passed(check, subj) if {
	check.op == "identities_resolved"
	prs := value_at(subj, check.path)
	is_array(prs)
	some pr in prs
	four_eyes_identities_ok(pr, check.patterns)
}

op_passed(check, subj) if {
	check.op == "independently_approved"
	prs := value_at(subj, check.path)
	is_array(prs)
	some pr in prs
	four_eyes_identities_ok(pr, check.patterns)
	four_eyes_independent(subj, pr)
}

four_eyes_resolved(username) if {
	is_string(username)
	username != ""
	username != "ghost"
}

four_eyes_author_known(commit, _) if four_eyes_resolved(commit.author_username)

four_eyes_author_known(commit, patterns) if {
	some pattern in patterns
	is_string(pattern)
	regex.match(pattern, object.get(commit, "author", ""))
}

four_eyes_identities_ok(pr, patterns) if {
	is_array(pr.commits)
	every commit in pr.commits {
		four_eyes_author_known(commit, patterns)
	}
}

four_eyes_identities_ok(pr, _) if {
	is_array(pr.approvers)
	count(pr.approvers) > 0
	every approver in pr.approvers {
		four_eyes_resolved(approver.username)
	}
}

four_eyes_independent(commit, pr) if {
	commit.name != pr.merge_commit
	four_eyes_each_author_approved(pr, four_eyes_commit_authors(pr) | {pr.author})
}

four_eyes_independent(commit, pr) if {
	commit.name == pr.merge_commit
	four_eyes_each_author_approved(pr, four_eyes_commit_authors(pr))
}

four_eyes_independent(commit, pr) if {
	commit.name == pr.merge_commit
	count(four_eyes_commit_authors(pr)) == 0
	four_eyes_resolved(pr.author)
	four_eyes_each_author_approved(pr, {pr.author})
}

four_eyes_each_author_approved(pr, authors) if {
	count(authors) > 0
	eligible := four_eyes_eligible_approvers(pr, four_eyes_cutoff(pr))
	every author in authors {
		some approver in eligible
		approver != author
	}
}

four_eyes_commit_authors(pr) := {commit.author_username |
	some commit in pr.commits
	four_eyes_resolved(commit.author_username)
}

four_eyes_cutoff(pr) := max({commit.timestamp | some commit in pr.commits}) if {
	count(pr.commits) > 0
	every commit in pr.commits {
		is_number(commit.timestamp)
	}
}

four_eyes_eligible_approvers(pr, cutoff) := {approver.username |
	some approver in pr.approvers
	approver.state == "APPROVED"
	four_eyes_resolved(approver.username)
	is_number(approver.timestamp)
	approver.timestamp > cutoff
}
