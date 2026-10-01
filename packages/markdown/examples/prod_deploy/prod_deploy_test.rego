package prod_deploy_test

import data.ergo

compiled := data.prod_deploy.requirements

written_in_rego := {"prod_deploy": {
	"subject_type": "deployment",
	"from": ["deployments"],
	"id": ["name"],
	"applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
	"checks": {
		"approved": {
			"description": "A named approver signed off on the deployment",
			"op": "non_empty_string",
			"path": ["approved_by"],
		},
		"ci_green": {
			"description": "Every CI check on the deployment passed",
			"op": "all",
			"path": ["ci_checks"],
			"check": {"op": "equals", "path": ["conclusion"], "value": "success"},
		},
	},
}}

deployments := {"deployments": [
	{"name": "d-1", "environment": "prod", "approved_by": "alice", "ci_checks": [{"conclusion": "success"}]},
	{"name": "d-2", "environment": "prod", "ci_checks": [{"conclusion": "failure"}]},
	{"name": "d-3", "environment": "staging"},
]}

test_markdown_compiles_to_the_policy_written_in_rego if {
	compiled == written_in_rego
}

test_compiled_policy_gives_the_same_report_as_the_rego_one if {
	ergo.report(deployments, compiled) == ergo.report(deployments, written_in_rego)
}

test_compiled_policy_reports_what_went_wrong if {
	violations := ergo.violations(ergo.report(deployments, compiled))
	{[v.subject.id, v.check, v.cause] | some v in violations} == {
		["d-2", "approved", "absent"],
		["d-2", "ci_green", "value"],
	}
}
