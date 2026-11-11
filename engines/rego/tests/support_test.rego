package ergo_test

import data.ergo
import rego.v1

report(doc, reqs) := ergo.report(doc, lifted(reqs), given_params)

subject_fields := ["from", "identified_by", "applies_to"]

lifted(reqs) := {
	"ergo_spec": ergo._spec,
	"subjects": {subject_name(reqs, name): subject_def(req) | some name, req in reqs; is_object(req)},
	"requirements": {name: lifted_req(reqs, name, req) | some name, req in reqs},
} if is_object(reqs)

lifted(reqs) := {"ergo_spec": ergo._spec, "requirements": reqs} if not is_object(reqs)

lifted_req(reqs, name, req) := object.union(object.remove(req, array.concat(subject_fields, ["subject_type"])), {"subject": subject_name(reqs, name)}) if is_object(req)

lifted_req(_, _, req) := req if not is_object(req)

subject_def(req) := object.union({"from": "$input"}, {f: req[f] | some f in subject_fields; f in object.keys(req)})

subject_type(req) := object.get(req, "subject_type", "subject")

subject_name(reqs, name) := subject_type(reqs[name]) if {
	count({subject_def(req) | some req in reqs; is_object(req); subject_type(req) == subject_type(reqs[name])}) == 1
} else := name

default given_params := {}

given_params := data.params

solo(subj, check) := report(
	{"items": [subj]},
	{"s": {
		"subject_type": "thing",
		"from": "items",
		"identified_by": "id",
		"checks": {"c": check},
	}},
)

verdict(subj, check) := row.passed if {
	some row in solo(subj, check).results
	row.check == "c"
}

inputs_of(subj, check) := row.inputs if {
	some row in solo(subj, check).results
	row.check == "c"
}

stopped(rep) if [[r.check, r.passed, r.cause] | some r in rep.results] == [["$well_formed", false, "value"]]

cause_of(subj, check) := row.cause if {
	some row in solo(subj, check).results
	row.check == "c"
}

rendered(subj, check) := solo(subj, check).requirements.s.checks.c.expression

rows_for(report, req_name, check_name) := [r |
	some r in report.results
	r.requirement == req_name
	r.check == check_name
]

id_req(from) := {"s": {
	"subject_type": "thing",
	"from": from,
	"identified_by": "id",
	"checks": {"c": "id exists"},
}}

subject_counts(doc, from) := report(doc, id_req(from)).requirements.s.subjects

mixed_subjects := {"items": [{"id": "x", "n": "a"}, "b", null, 3]}

mixed_req := {"s": {"from": "items", "identified_by": "id", "checks": {"c": "n exists"}}}

scoped_req(conditions) := {"s": {
	"subject_type": "thing",
	"from": whose_line("items", conditions),
	"identified_by": "id",
	"checks": {"c": "id exists"},
}}

whose_line(path, "") := path

whose_line(path, conditions) := concat(" whose ", [path, conditions]) if conditions != ""

merged_only := "state is \"MERGED\""

two_states := {"items": [
	{"id": "a", "state": "MERGED"},
	{"id": "b", "state": "CLOSED"},
]}

in_range := "temp_c is between 0 and 10"

no_wip := "labels does not contain \"wip\""

has_approved := "labels contains \"approved\""

is_merged := "state is \"MERGED\""

has_fingerprint := "fingerprint exists"

filled := "fingerprint is a non-empty string"

service_accounts := ["svc_.*", `.*\[bot\]`, `noreply@github\.com`]

matches(op) := concat(" ", ["author", {"matches_any": "matches", "not_matches_any": "does not match"}[op], concat(", ", [json.marshal(p) | some p in service_accounts])])

compare_time_span(op) := concat(" ", ["start", {"gt": "is after", "gte": "is on or after", "lt": "is before", "lte": "is on or before"}[op], "end"])

all_verified := "every commits.verified is true"

any_approved := `some approvers.state is "APPROVED"`

every_commit_signed := "every prs.commits.signed is true"

flavoured := {"any_of": {"standard": ["type matches \"^Story$\"", "state matches \"^CLOSED$\""], "safe": ["type matches \"^SAFe Story$\"", "state matches \"^DONE$\""]}}

two_check_req := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"checks": {
		"a": "id exists",
		"b": "state is \"MERGED\"",
	},
}}

min_subjects_req(n) := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"min_subjects": n,
	"checks": {"c": "id exists"},
}}

owner_req := {"s": {
	"subject_type": "repo",
	"from": "repos",
	"identified_by": "name",
	"checks": {"owned": "owner is a non-empty string"},
}}

unique_ids_row(doc, policy) := [r.inputs, r.passed, r.cause] if {
	some r in rows_for(report(doc, policy), "s", "$unique_ids")
}

_engine_policy := {"ergo_spec": ergo._spec, "subjects": {"x": {"from": "xs", "identified_by": "id"}}, "requirements": {"r": {"subject": "x", "checks": {"c": "id is 1"}}}}

_engine_doc := {"xs": [{"id": 1}, {"id": 2}]}

two_reqs_policy(extra) := object.union(lifted({"s": typed_req, "t": typed_req}), extra)

_spec_rows(policy) := [r.compliant, [[w.requirement, w.passed, problem_inputs_of(w)] | some w in r.results; w.check == "$well_formed"]] if {
	r := ergo.report({"items": [{"id": 1}]}, policy, {})
}

problem_inputs_of(row) := [i |
	some i in row.inputs
	not i.name in {"count(checks)", "require"}
]

badly_written_requirements := {
	"require_most": [{"require": "most"}, [{"name": "require", "value": ["neither every nor some"], "locations": []}]],
	"require_number": [{"require": 5}, [{"name": "require", "value": ["neither every nor some"], "locations": []}]],
	"checks_empty": [{"checks": {}}, [{"name": "require", "value": "every", "locations": []}, {"name": "checks", "value": ["empty"], "locations": []}]],
	"min_out_of_range": [{"min_subjects": 1e400}, [{"name": "require", "value": "every", "locations": []}, {"name": "min_subjects", "value": ["number out of range"], "locations": []}]],
}

typed_req := {"from": "items", "identified_by": "id", "min_subjects": 0, "checks": {"c": "id exists"}}

wrong_types := [
	["checks", 5],
	["checks", ["id exists"]],
	["checks", null],
	["from", 5],
	["from", {"a": 1}],
	["from", null],
	["identified_by", 5],
	["identified_by", null],
	["min_subjects", "0"],
	["min_subjects", null],
	["min_subjects", -1],
	["min_subjects", 0.5],
	["min_subjects", 1.5],
	["subject_type", 3],
	["subject_type", {"name": "x"}],
	["subject_type", null],
	["description", 5],
	["description", false],
	["description", ["d"]],
	["meta", "x"],
	["meta", 0],
	["meta", ["x"]],
]

problem_inputs(rep) := [i |
	some i in rows_for(rep, "s", "$well_formed")[0].inputs
	not i.name in {"count(checks)", "require"}
]

require_req(q) := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"require": q,
	"checks": {
		"signed": "signed is true",
		"reviewed": "reviewed is true",
	},
}}

both_ok := {"items": [{"id": "a", "signed": true, "reviewed": true}]}

split_across_subjects := {"items": [
	{"id": "a", "signed": true, "reviewed": false},
	{"id": "b", "signed": false, "reviewed": true},
]}

some_req_zero := {"s": object.union(require_req("some").s, {"min_subjects": 0})}

prod_only := {"s": {
	"subject_type": "deployment",
	"from": "deployments whose env is \"prod\"",
	"identified_by": "id",
	"min_subjects": 0,
	"checks": {"approved": "approved_by exists"},
}}

violating_req := {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"checks": {
		"signed": {"assert": "signed is true", "description": "Signed"},
		"reviewed": {"assert": "reviewed is true", "description": "Reviewed"},
	},
}}

scan_mins := [0, 1, 2]

scan_checksets := [{}, {"c": "id exists"}]

scan_filters := ["", "state is \"MERGED\""]

scan_docs := [
	{"items": []},
	{"items": [{"id": "a", "state": "MERGED"}]},
	{"items": [{"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "MERGED"}, {"no_id": 1, "state": "MERGED"}]},
	{"items": [{"id": "a", "state": "CLOSED"}]},
]

scan_policy(rq, mn, cs, fl) := {"s": {
	"subject_type": "thing",
	"from": whose_line("items", fl),
	"identified_by": "id",
	"require": rq,
	"min_subjects": mn,
	"checks": cs,
}}

scan_reports(rq) := [report(d, scan_policy(rq, mn, cs, fl)) |
	some mn in scan_mins
	some cs in scan_checksets
	some fl in scan_filters
	some d in scan_docs
]

unexplained(rq) := [rep | some rep in scan_reports(rq); rep.compliant == false; count(ergo.violations(rep)) == 0]

malformed(rq) := [rep | some rep in scan_reports(rq); rows_for(rep, "s", "$well_formed")[0].passed == false]

malformed_ones_fail_and_say_why(rq) if {
	every rep in malformed(rq) {
		rep.requirements.s.status == "not_met"
		count([v |
			some v in ergo.violations(rep)
			v.check == "$well_formed"
		]) == 1
	}
}

degraded_only := "degraded is true"

degraded_req(req_kind) := degraded_req_whose(req_kind, degraded_only)

degraded_req_whose(req_kind, conditions) := {"s": {
	"subject_type": "round",
	"from": whose_line("rounds", conditions),
	"identified_by": "id",
	"require": req_kind,
	"min_subjects": 0,
	"checks": {"c": "signed is true"},
}}

locked_req(filter_path) := {"s": {
	"from": concat("", ["packages whose ", filter_path, " exists"]),
	"identified_by": "id",
	"min_subjects": 0,
	"checks": {"c": "signed is true"},
}}

in_doc(top, subj, check) := report(object.union(top, {"items": [subj]}), {"s": {
	"subject_type": "thing",
	"from": "items",
	"identified_by": "id",
	"checks": {"c": check},
}})

row_in(top, subj, check) := r if {
	some r in in_doc(top, subj, check).results
	r.check == "c"
}

params_req(check) := {"s": {"from": "items", "identified_by": "id", "checks": {"c": check}}}

params_rows(doc, check) := [[r.passed, r.cause, r.inputs] | some r in rows_for(report(doc, params_req(check)), "s", "c")]

empty_report := {"compliant": false, "description": "", "engine": {"name": "ergo-rego", "version": ergo.version}, "ergo": ergo._spec, "meta": {}, "subjects": {}}

has_only_the_policy_row(rep) if {
	object.remove(rep, ["requirements", "results"]) == empty_report
	object.keys(rep.requirements) == {"$policy"}
	count(rep.results) == 1
}

trail_doc := {"trail": {"artifacts": {"app": {
	"fingerprint": "abc",
	"attestations": {"pull-request": {"status": "COMPLETE"}, "junit": {"status": "FAILED"}},
	"tags": ["v1", "v2"],
}}}}

trail_req(check) := {"s": {
	"from": "trail.artifacts named by $params.artifact",
	"identified_by": "fingerprint",
	"checks": {"c": check},
}}

attested := "attestations named by $params.att.status is \"COMPLETE\""

typo_doc := {"params": {"word": "x", "none": null, "nine": 9}, "items": [{"id": 1, "n": 1, "s": "a", "xs": [1], "t": "2026-01-01T00:00:00Z"}]}

badly_written := [
	[`n is one of 1, "a"`, "", ["values of mixed types"]],
	["n is between 9 and 0", "", ["min above max"]],
	[`s matches "("`, "", [`invalid pattern "("`]],
	[`s does not match "b" or "("`, "", ["doesn't parse"]],
	["xs[9007199254740992] exists", "", ["9007199254740992 can't be a list position"]],
	["item 9007199254740992 of xs exists", "", ["9007199254740992 can't be a list position"]],
	["n is $foo", "", ["unknown name $foo"]],
	["n is", "", ["doesn't parse"]],
	["n is at least 1e400", "", ["number out of range: 1e400"]],
	["n is at least n", "", ["n is compared with itself"]],
	["empty is 1", "", ["empty is a word of the grammar: write .empty"]],
	["some xs, if any, exists", "", ["if any can't go with some"]],
	[`t is before "yesterday"`, "", [`"is before" takes a time or a number`]],
	[`every xs.v is one of 1, "a"`, "", ["values of mixed types"]],
	[`count of xs whose v is one of 1, "a" is 0`, "", ["values of mixed types"]],
	["count of xs whose v is between 9 and 0 is 0", "", ["min above max"]],
	[`count of xs whose v matches "(" is 0`, "", [`invalid pattern "("`]],
	["count of xs whose $foo exists is 0", "", ["unknown name $foo"]],
	["count of xs whose v[9007199254740992] exists is 0", "", ["9007199254740992 can't be a list position"]],
	[`every xs whose v is one of 1, "a" is 1`, "", ["values of mixed types"]],
	["n exists whose v is 1", "", ["doesn't parse"]],
	["every xs some ys is 1", "", ["two quantifiers in one sentence: put them on a for line"]],
	[{"assert": "n exists", "description": 5}, "", ["invalid description"]],
	[{"assert": "n exists", "meta": "high"}, "", ["invalid meta"]],
	[{"assert": "n exists", "meta": []}, "", ["invalid meta"]],
	[{"assert": "n exists", "zz": 1}, "", ["unknown field zz"]],
	[{"assert": 5}, "", ["invalid assert"]],
	[{"assert": []}, "", ["empty assert"]],
	[{"assert": ["n exists", "n is"]}, "", ["line 2: doesn't parse"]],
	[{"for": "every xs as x"}, "", ["missing assert"]],
	[{"assert": "x exists", "for": "every xs"}, "", [`for: an item ends with "as" and a name, like "every pull_requests as pr"`]],
	[{"assert": "x exists", "for": "every xs as x, every x.ys as x"}, "", ["for: x is given twice"]],
	[{"assert": "x exists", "for": `every xs whose v is one of 1, "a" as x`}, "", ["for: values of mixed types"]],
	[{"assert": `x is one of 1, "a"`, "for": "every xs as x"}, "", ["values of mixed types"]],
	[{"assert": ["n exists", "n is one of 1, \"a\""]}, "", ["line 2: values of mixed types"]],
	[{"assert": ["n is one of 1, \"a\"", "n is"]}, "", ["line 1: values of mixed types", "line 2: doesn't parse"]],
	[{"assert": "n exists", "for": 5}, "", ["invalid for"]],
	[{"any_of": {"o": "n is"}}, "", ["option o: doesn't parse"]],
	[{"any_of": {"o": ["n exists", "n is one of 1, \"a\""]}}, "", ["option o: line 2: values of mixed types"]],
	[{"any_of": {"a": ["n exists and n exists", "n exists"], "b": ["n exists and n exists", "n is one of 1, \"a\""]}}, "", ["option b: line 2: values of mixed types"]],
	[{"any_of": {"a": "n exists", "b": "n is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": "n exists and n exists", "b": "n is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": "n exists", "b": "n exists and every xs is one of 1, \"a\""}}, "", ["option b: values of mixed types"]],
	[{"any_of": {"a": ["n exists", "every xs is one of 1, \"a\""], "b": "n is one of 1, \"a\""}}, "", ["option a: line 2: values of mixed types", "option b: values of mixed types"]],
	[{"any_of": {}}, "", ["empty any_of"]],
	[{"any_of": {"o": []}}, "", ["empty option o"]],
	[{"any_of": "o"}, "", ["invalid any_of"]],
	[{"any_of": {"o": "n exists"}, "assert": "n exists"}, "", ["unknown field any_of"]],
	[5, "", ["invalid check"]],
	[null, "", ["invalid check"]],
]

filter_policy(subjects) := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": "b", "min_subjects": 0, "checks": {"c": "x exists"}}}}

position_child_policy(from) := {"ergo_spec": ergo._spec, "subjects": {"p": {"from": "ps"}, "k": {"from": from}}, "requirements": {"r": {"subject": "k", "checks": {"c": "x exists"}}}}

ordering_doc := {"id": 1, "a": {"name": "ann"}, "b": {"owner": "bob"}, "xs": [2], "ys": [1, 9], "f": false, "t": true, "n": 1, "m": 2, "s": "a", "z": "b"}

one_item := {"items": [{"id": 1}]}

json_only_req := {"s": {"subject_type": "thing", "from": "items", "identified_by": "id", "checks": {"c": "x is 1"}}}

row_verdicts(rep) := [[r.check, r.passed, r.cause] | some r in rep.results]

absent_lookalike := {"ergo/absent": true}

lookalike_req(from, checks) := {"s": {"from": from, "identified_by": "id", "checks": checks}}

deployments_doc := {"deployments": [
	{"id": "d-1", "environment": "prod", "approved_by": "alice", "tested": true},
	{"id": "d-2", "environment": "prod", "tested": false},
	{"id": "d-3", "environment": "staging"},
]}

prod_deployment := {"from": "deployments whose environment is \"prod\"", "identified_by": "id"}

subject_policy(subjects, reqs) := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": reqs}

approved_req(subject) := {"subject": subject, "checks": {"approved": "approved_by is a non-empty string"}}

tested_req(subject) := {"subject": subject, "checks": {"tested": "tested is true"}}

well_formed_problems(rep, name) := [i | some i in rows_for(rep, name, "$well_formed")[0].inputs; not i.name in {"count(checks)", "require"}]

sbom_doc := {"components": [
	{"name": "a", "lock_release": "1.0", "sbom_release": "1.0", "exempt": false},
	{"name": "b", "lock_release": "2.0", "sbom_release": "2.1", "exempt": true},
	{"name": "c", "sbom_release": "3.0", "exempt": false},
]}

sbom_subjects := {
	"SBOM package": {"from": "components", "identified_by": "name"},
	"locked SBOM package": {"from": "\"SBOM package\" whose lock_release exists"},
	"non-exempt SBOM package": {"from": "\"SBOM package\" whose exempt is false"},
}

causes_doc := {"deployments": [
	{"id": "d-1", "environment": "prod", "approved_by": "alice"},
	{"id": "d-2", "environment": "prod"},
	{"id": "d-3", "environment": "staging"},
	{"id": "d-4", "environment": "prod", "approved_by": ""},
	{"id": "d-5"},
]}

causes_policy(check) := {"ergo_spec": ergo._spec, "subjects": {"deployment": {"from": "deployments whose environment is \"prod\"", "identified_by": "id"}}, "requirements": {"r": {"subject": "deployment", "checks": {"approved": check}}}}

causes_of(deployments, check) := ergo.report({"deployments": deployments}, causes_policy(check), {}).requirements.r.causes

approved_check := "approved_by is a non-empty string"

_read(text) := ergo._sentence(text)

_printed(text) := ergo._s_check_text(ergo._sentence(text))

_sentence_policy(checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"thing": {"from": "things", "identified_by": "id"}},
	"requirements": {"s": {"subject": "thing", "checks": checks}},
}

_sentence_rows(checks, doc, params) := [[r.check, r.passed, r.cause, r.inputs] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

_sentence_problems(check) := [i.value | some i in ergo.report({"things": []}, _sentence_policy({"c": check}), {}).results[0].inputs; i.name == "checks.c"][0]

_walk_rows(checks, doc, params) := [[r.subject.id, r.check, r.cause, object.get(r, "failed_items", object.get(r, "failed_assertions", []))] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

_ten := "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10"

_eleven := "k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11"

_too_long := ["every and some over more than ten steps aren't supported yet"]

_for_too_long := "for: every and some over more than ten steps aren't supported yet"

_reads(check) if {
	some row in ergo.report({"things": []}, _sentence_policy({"c": check}), {}).results
	row.check == "$well_formed"
	row.passed
}

_nine := "k1.k2.k3.k4.k5.k6.k7.k8.k9"

_k9(v) := {"k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": v}}}}}}}}}

_k10(v) := {"k1": {"k2": {"k3": {"k4": {"k5": {"k6": {"k7": {"k8": {"k9": {"k10": v}}}}}}}}}}

_part_walk_policy(has, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"thing": {"from": "things", "identified_by": "id", "has": has}},
	"requirements": {"s": {"subject": "thing", "checks": checks}},
}

_part_walk_rows(has, checks, doc) := [[r.subject.id, r.check, r.cause] | some r in ergo.report(doc, _part_walk_policy(has, checks), {}).results; not startswith(r.check, "$")]

_part_walk_problems(has, check) := [i.value | some i in ergo.report({"things": []}, _part_walk_policy(has, {"c": check}), {}).results[0].inputs; i.name == "checks.c"][0]

_part_walk_reads(has, check) if {
	some row in ergo.report({"things": []}, _part_walk_policy(has, {"c": check}), {}).results
	row.check == "$well_formed"
	row.passed
}

_parent_part_policy(has, check) := {
	"ergo_spec": ergo._spec,
	"subjects": {"b": {"from": "bs", "identified_by": "id", "has": has}, "kid": {"from": "every b.kids", "identified_by": "id"}},
	"requirements": {"r": {"subject": "kid", "checks": {"c": check}}},
}

_parent_part_problems(has, check) := [i.value | some r in ergo.report({"bs": []}, _parent_part_policy(has, check), {}).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

_for_rows(check, things, params) := [[r.subject.id, r.cause, _bare_failed(r.failed_items), r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_for_rows_full(check, things, params) := [[r.subject.id, r.cause, r.failed_items, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_bare_failed(failed) := [_bare_item(f) | some f in failed]

_bare_item(f) := object.union(f, {"failed_assertions": [_bare_line(l) | some l in f.failed_assertions]})

_bare_line(l) := object.union(object.remove(l, ["inputs", "items"]), {"items": [object.remove(i, ["inputs"]) | some i in l.items]}) if "items" in object.keys(l)

_bare_line(l) := object.remove(l, ["inputs"]) if not "items" in object.keys(l)

_peer_approval := {
	"for": `some approvers whose state is "APPROVED" as approver, every commits as commit`,
	"assert": ["approver.username does not equal author", "approver.timestamp is after commit.timestamp"],
}

_peer_things := [
	{"id": "peer", "author": "ann", "commits": [{"timestamp": "2026-10-01T09:00:00Z"}], "approvers": [{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z"}]},
	{"id": "fails", "author": "ann", "commits": [{"timestamp": "2026-10-01T09:00:00Z"}, {"timestamp": "2026-10-01T11:00:00Z"}], "approvers": [
		{"username": "bob", "state": "APPROVED", "timestamp": "2026-10-01T10:00:00Z"},
		{"username": "ann", "state": "APPROVED", "timestamp": "2026-10-01T12:00:00Z"},
		{"username": "cat", "state": "COMMENTED", "timestamp": "2026-10-01T12:00:00Z"},
	]},
	{"id": "nostate", "author": "ann", "commits": [], "approvers": [{"username": "carl", "timestamp": "2026-10-01T12:00:00Z"}]},
]

_tally_rows(check, things, params) := [[r.subject.id, r.cause, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_review := {
	"id": "pr-7",
	"personas_ran": ["security"],
	"findings": [{"source": "claude"}, {"source": "gpt"}, {"source": "claude"}],
	"claude_found": 2,
	"stages": [{"kind": "model", "usd": 0.5}, {"kind": "model", "usd": 0.25}, {"kind": "tool", "usd": 0}],
	"total_usd": 0.76,
}

_from_report(doc, subjects, checks, params) := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": object.keys(subjects)[_], "checks": checks}}}, params) if count(subjects) == 1

_from_rows(rep) := [[r.subject.id, r.check, r.cause, r.inputs] | some r in rep.results; not r.check in {"$min_subjects", "$unique_ids", "$well_formed"}]

_from_problems(rep) := [i | some r in rep.results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

_releases := {"releases": [
	{"id": "mixed", "files": [{"path": "docs/upgrade.md"}, {"path": "src/api.go"}], "ticket": "ok"},
	{"id": "docs", "files": [{"path": "docs/upgrade.md"}], "ticket": "ok"},
	{"id": "none", "files": [], "ticket": "ok"},
	{"id": "unset", "ticket": "ok"},
	{"id": "null", "files": null, "ticket": "ok"},
	{"id": "text", "files": "docs/upgrade.md", "ticket": "ok"},
	{"id": "gap", "files": [{"path": "docs/upgrade.md"}, {"name": "x"}], "ticket": "ok"},
	{"id": "number", "files": [{"path": "docs/upgrade.md"}, {"path": 5}], "ticket": "ok"},
]}

_applies_failures_of(rep) := {r.subject.id: object.filter(r, ["failed_items", "failed_assertions"]) | some r in rep.results; r.check == "$applies"}

_check_failures_of(rep) := {r.subject.id: object.filter(r, ["failed_items", "failed_assertions"]) | some r in rep.results; r.check == "c"}

_as_condition_and_as_check(sentences) := [
	_from_report(_releases, {"release": {"from": concat(" whose ", ["releases", concat(" and whose ", sentences)]), "identified_by": "id"}}, {"c": "ticket exists"}, {}),
	_from_report(_releases, {"release": {"from": "releases", "identified_by": "id"}}, {"c": {"assert": sentences}}, {}),
]

_chain_doc := {"trail": {"artifacts": {
	"web": {"fingerprint": "sha-1", "name": "web", "pull_requests": [{"url": "pr/7", "approved": true}, {"url": "pr/8", "approved": false}]},
	"api": {"fingerprint": "sha-2", "name": "api", "pull_requests": []},
}}}

_chain_subjects := {
	"artifact": {"from": "trail.artifacts named by $params.name", "identified_by": "fingerprint"},
	"pull request": {"from": "every artifact.pull_requests", "identified_by": "url"},
}

_chain_report(doc, subjects, checks, params) := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pull request", "checks": checks}}}, params)

_owner_doc := {"artifact": {"name": "a1", "owner": "ann", "pull_requests": [{"id": 1, "commits": [{"author": "bob", "n": 1}, {"author": "ann", "n": 2}]}]}}

_owner_subjects := {"artifact": {"identified_by": "name"}, "pr": {"from": "every artifact.pull_requests", "identified_by": "id"}}

_owner_authors := {"name": "commits[].author", "value": ["bob", "ann"], "locations": ["/artifact/pull_requests/0/commits/0/author", "/artifact/pull_requests/0/commits/1/author"]}

_owner_rows(checks) := {r.check: r.inputs |
	some r in ergo.report(_owner_doc, {"ergo_spec": ergo._spec, "subjects": _owner_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, {}).results
	r.check in object.keys(checks)
}

_atts_doc := {"artifacts": [{"name": "a1", "owner": "ann", "team": {"lead": "ann"}, "atts": {"x": {"owner": "ann"}, "y": {"owner": "zed"}}, "pull_requests": [{"id": 1, "commits": [{"author": "bob", "k": "x"}, {"author": "zed", "k": "y"}], "files": [{"k": "x"}, {"k": "y"}]}]}]}

_atts_subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.pull_requests", "identified_by": "id"}}

_atts_rows(checks, params) := {r.check: [i.name | some i in r.inputs] |
	some r in ergo.report(_atts_doc, {"ergo_spec": ergo._spec, "subjects": _atts_subjects, "requirements": {"r": {"subject": "pr", "checks": checks}}}, params).results
	r.check in object.keys(checks)
}

_chain_min_cause(rep) := [[r.cause, object.keys(r.subject)] | some r in rep.results; r.check == "$min_subjects"]

_plain_chain := {"artifact": {"from": "every trail.artifacts", "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}

_kept_subjects := {"artifact": {"from": `every trail.artifacts whose env is "prod"`, "identified_by": "fingerprint"}, "pull request": {"from": "every artifact.pull_requests", "identified_by": "url"}}

_many_doc := {"trail": {"artifacts": [
	{"fingerprint": "a", "env": "prod", "pull_requests": [{"url": "pr/7", "ok": true}, {"url": "pr/8", "ok": false}]},
	{"fingerprint": "b", "env": "prod", "pull_requests": [{"url": "pr/7", "ok": true}]},
]}}

_rows_of(rep) := [[r.check, r.subject, r.cause] | some r in rep.results]

_defects := {"defects": [
	{"id": 1, "severity": "critical", "status": "open", "team": "a"},
	{"id": 2, "severity": "low", "status": "open", "team": "a"},
	{"id": 3, "severity": "critical", "status": "closed", "team": "b"},
	{"id": 4, "severity": "critical", "status": "open", "team": "b"},
]}

_narrow_report(subjects, name) := ergo.report(_defects, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": name, "checks": {"c": "id exists"}}}}, {})

_kept(rep) := [r.subject.id | some r in rep.results; r.check == "c"]

_persona_doc := {"things": [
	{"id": 1, "dispatched": ["security", "style"], "shas": {"security": "3f2a000000000000000000000000000000000000", "style": "9c1b000000000000000000000000000000000000"}},
	{"id": 2, "dispatched": ["security", "perf", 5], "shas": {"security": "x"}},
]}

_for_sentence_root_rows(checks, subject) := {r.check: [r.cause, r.message] |
	some r in ergo.report({"things": [object.union(subject, {"id": 1})]}, {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"r": {"subject": "thing", "checks": checks}}}, {}).results
	not startswith(r.check, "$")
}

_list_lefts := [
	{"id": "l00"},
	{"id": "l01", "x": null},
	{"id": "l02", "x": "a"},
	{"id": "l03", "x": "b"},
	{"id": "l04", "x": 3},
	{"id": "l05", "x": true},
	{"id": "l06", "x": []},
	{"id": "l07", "x": ["a"]},
	{"id": "l08", "x": ["a", "b"]},
	{"id": "l09", "x": ["b"]},
	{"id": "l10", "x": {"k": "a"}},
	{"id": "l11", "x": ""},
	{"id": "l12", "x": [1]},
	{"id": "l13", "x": [null]},
	{"id": "l14", "x": ["a", 1]},
	{"id": "l15", "x": [["a"]]},
]

_list_verdicts(check, things, params) := [[r.subject.id, r.passed, r.cause] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_list_with_field(things, right) := [object.union(t, {"y": right.v}) | some t in things] if "v" in object.keys(right)

_list_with_field(things, right) := things if not "v" in object.keys(right)

_list_params(right) := {"k": right.v} if "v" in object.keys(right)

_list_params(right) := {} if not "v" in object.keys(right)

_list_same_as_params(words, suffix, right) if {
	_list_verdicts(concat("", ["x ", words, " y", suffix]), _list_with_field(_list_lefts, right), {}) == _list_verdicts(concat("", ["x ", words, " $params.k", suffix]), _list_lefts, _list_params(right))
}

_snyk := {"id": "v1", "first_seen_ts": "2026-10-01T00:00:00Z", "now_ts": "2026-10-04T12:00:00Z", "severity": "high"}

_elapsed_rows(check, things, params) := [[r.subject.id, r.passed, r.cause, r.inputs] | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), params).results; r.check == "c"]

_elapsed_first(check, things, params) := [_elapsed_rows(check, things, params)[0][1], _elapsed_rows(check, things, params)[0][2]]

_elapsed_cause(check, thing, params) := _elapsed_rows(check, [thing], params)[0][2]

_listed_reqs(name) := {"r": {"subject": name, "checks": {"c": "id exists"}}}

_listed(subjects, name) := ergo.report({}, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": _listed_reqs(name)}, {}).subjects

_parts_policy(has, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"round": {"from": "trail", "identified_by": "name", "has": has}},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_parts_doc(d) := {"trail": {"name": "t1", "dd": d}}

_parts_report(has, checks, d) := ergo.report(_parts_doc(d), _parts_policy(has, checks), {})

_parts_rows(rep, check) := [r | some r in rep.results; r.check == check]

_parts_row(rep, check) := _parts_rows(rep, check)[0]

_parts_problems(rep) := {i.name: i.value | some r in rep.results; r.check == "$well_formed"; some i in r.inputs}

_parts_chain := {
	"ergo_spec": ergo._spec,
	"subjects": {
		"artifact": {"from": "trail.artifacts named by $params.art", "identified_by": "fingerprint", "has": {"pra": "attestations.pr"}},
		"pull request": {"from": "every artifact.pra.pull_requests", "identified_by": "url", "has": {"rev": "reviews"}},
	},
	"requirements": {"r": {"subject": "pull request", "checks": {
		"parent": "artifact.pra.name is \"w\"",
		"own": "rev.count is 2",
		"field": "pra is 1",
		"every": "every artifact.pra.pull_requests.url is not empty",
	}}},
}

_parts_chain_doc := {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "pra": 1, "attestations": {"pr": {"name": "w", "pull_requests": [
	{"url": "pr/7", "reviews": {"count": 2}},
	{"url": "pr/8", "reviews": {"count": 1}},
]}}}}}}

_swap_has := {
	"cov": "dd.b",
	"lst": "dd.items",
	"uno": "dd.b.x",
	"by": "dd.m named by $params.k",
	"pos": "dd.items[1]",
}

_swap_full := {
	"@cov": "dd.b",
	"@lst": "dd.items",
	"@uno": "dd.b.x",
	"@by": "dd.m named by $params.k",
	"@pos": "dd.items[1]",
}

_swap_alias := {
	"@cov": "cov",
	"@lst": "lst",
	"@uno": "uno",
	"@by": "by",
	"@pos": "pos",
}

_swap_lines := [
	"@cov.x is 1",
	"@cov.x is not 1",
	"@cov.x exists",
	"@cov.x does not exist",
	"@cov.s is a non-empty string",
	"@cov.x is one of 1, 2",
	"@cov.x is not one of 1, 2",
	"@cov.s matches \"^a\"",
	"@cov.s does not match \"^b\"",
	"@cov.s starts with \"a\"",
	"@cov.x is at least 2",
	"@cov.x is between 1 and 3",
	"@cov.x equals @cov.n",
	"@cov.x does not equal @cov.n",
	"@cov.t is before @cov.t2",
	"@cov.items is empty",
	"@cov.items is not empty",
	"@cov exists",
	"@cov.x is a number",
	"@cov.x is 1 and @cov.n is 2",
	"@uno is 1",
	"@uno exists",
	"@by.x is 1",
	"@by exists",
	"@pos.x is 1",
	"@pos exists",
]

_swap_walks := [
	"every @lst.x is 1",
	"some @lst.x is 1",
	"every @lst whose y is 2 is an object",
	"every @lst.x is at least 1",
	"every @lst, if any, is not empty",
	"some @lst whose y is 2 is a list",
	"every @lst.sub is not empty",
	"count of @lst is 2",
	"count of @lst whose y is 2 is 1",
	"sum of @lst.n is 5",
	"sum of @lst.n that is 2 is 2",
	"@cov.x plus @cov.n is 3",
	"count of @lst plus @cov.x is 3",
	"days elapsed from @cov.t to @cov.t2 is 1",
	"count of @lst is @cov.x",
	"sum of @lst.n equals @cov.n within 0.5",
]

_swap_fors := [
	{"for": "every @lst as entry", "assert": "entry.x is 1"},
	{"for": "every @lst as entry", "assert": ["entry.x is @cov.x", "@cov.s exists"]},
	{"for": "some @lst whose y is 2 as entry", "assert": ["entry.x is 1", "@cov.s exists"]},
	{"for": "every @lst as entry, every entry.sub as s", "assert": "s is @cov.x"},
	{"for": "every @lst as entry", "assert": "count of entry.sub is @cov.x"},
	{"for": "every @lst as entry", "assert": "entry.x is @uno"},
	{"for": "every @cov.items as entry", "assert": "entry.x is @uno"},
]

_swap_checks(replacements, lines, walks, fors) := object.union(
	{sprintf("l%02d", [i]): strings.replace_n(replacements, line) | some i, line in lines},
	object.union(
		{sprintf("w%02d", [i]): strings.replace_n(replacements, line) | some i, line in walks},
		{sprintf("f%02d", [i]): _swap_for(replacements, item) | some i, item in fors},
	),
)

_swap_for(replacements, item) := {"for": strings.replace_n(replacements, item.for), "assert": _swap_assert(replacements, item.assert)}

_swap_assert(replacements, a) := strings.replace_n(replacements, a) if is_string(a)

_swap_assert(replacements, a) := [strings.replace_n(replacements, line) | some line in a] if is_array(a)

_swap_policy(has, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"round": _swap_subject(has)},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_subject(has) := {"from": "trail", "identified_by": "name", "has": has} if count(has) > 0

_swap_subject(has) := {"from": "trail", "identified_by": "name"} if count(has) == 0

_swap_view(rep) := {
	"rows": [{
		"check": r.check,
		"subject": r.subject,
		"passed": r.passed,
		"cause": r.cause,
		"values": {i.value | some i in r.inputs},
		"failed": {[f.cause, f.value, [a.cause | some a in object.get(f, "failed_assertions", [])]] | some f in object.get(r, "failed_items", [])},
		"lines": [a.cause | some a in object.get(r, "failed_assertions", [])],
	} |
		some r in rep.results
	],
	"requirement": {c: {x.value | some x in object.get(d, "$refs", [])} | some c, d in rep.requirements.r.checks},
	"status": rep.requirements.r.status,
	"causes": rep.requirements.r.causes,
}

_swap_item(x, y, n, sub) := {"x": x, "y": y, "n": n, "sub": sub}

_swap_good := {
	"b": {"x": 1, "s": "abc", "n": 2, "t": "2026-01-01T00:00:00Z", "t2": "2026-01-02T00:00:00Z", "items": [1, 2]},
	"items": [_swap_item(1, 2, 2, [1]), _swap_item(1, 3, 3, [1, 1])],
	"m": {"m1": {"x": 1}},
}

_swap_group_checks("lines_a", replacements) := _swap_checks(replacements, array.slice(_swap_lines, 0, 13), [], [])

_swap_group_checks("lines_b", replacements) := _swap_checks(replacements, array.slice(_swap_lines, 13, count(_swap_lines)), [], [])

_swap_group_checks("walks", replacements) := _swap_checks(replacements, [], _swap_walks, [])

_swap_group_checks("fors", replacements) := _swap_checks(replacements, [], [], _swap_fors)

_swap_good_with(f, v) := {"trail": {"name": "t1", "dd": object.union(_swap_good, {f: v})}}

_swap_good_without(f) := {"trail": {"name": "t1", "dd": object.remove(_swap_good, [f])}}

_swap_scenarios := {
	"everything_is_there": {"doc": _parts_doc(_swap_good), "params": {"k": "m1"}},
	"everything_is_there_and_no_params": {"doc": _parts_doc(_swap_good), "params": {}},
	"the_named_by_param_is_a_number": {"doc": _parts_doc(_swap_good), "params": {"k": 1}},
	"the_named_by_param_is_null": {"doc": _parts_doc(_swap_good), "params": {"k": null}},
	"the_named_by_key_is_not_in_its_object": {"doc": _swap_good_with("m", {}), "params": {"k": "m1"}},
	"an_object_part_is_missing": {"doc": _swap_good_without("b"), "params": {"k": "m1"}},
	"an_object_part_is_null": {"doc": _swap_good_with("b", null), "params": {"k": "m1"}},
	"an_object_part_is_text": {"doc": _swap_good_with("b", "text"), "params": {"k": "m1"}},
	"an_object_part_is_a_list": {"doc": _swap_good_with("b", [1]), "params": {"k": "m1"}},
	"a_field_inside_a_part_is_null": {"doc": _swap_good_with("b", object.union(_swap_good.b, {"x": null})), "params": {"k": "m1"}},
	"the_fields_inside_a_part_have_the_wrong_types": {"doc": _swap_good_with("b", {"x": "1", "s": 5, "n": "2", "t": "nope", "t2": 3, "items": "s"}), "params": {"k": "m1"}},
	"the_list_is_missing": {"doc": _swap_good_without("items"), "params": {"k": "m1"}},
	"the_list_is_null": {"doc": _swap_good_with("items", null), "params": {"k": "m1"}},
	"the_list_is_empty": {"doc": _swap_good_with("items", []), "params": {"k": "m1"}},
	"the_list_is_a_string": {"doc": _swap_good_with("items", "str"), "params": {"k": "m1"}},
	"the_list_holds_a_number_and_a_null": {"doc": _swap_good_with("items", [_swap_item(1, 2, 2, [1]), 5, null]), "params": {"k": "m1"}},
	"the_list_holds_items_with_missing_and_wrong_fields": {"doc": _swap_good_with("items", [_swap_item(null, 2, "q", []), {"y": 2}]), "params": {"k": "m1"}},
	"the_named_by_part_is_null": {"doc": _swap_good_with("m", null), "params": {"k": "m1"}},
	"the_named_by_part_is_text": {"doc": _swap_good_with("m", "s"), "params": {"k": "m1"}},
	"the_named_by_part_is_missing": {"doc": _swap_good_without("m"), "params": {"k": "m1"}},
	"the_subject_has_no_part_field": {"doc": {"trail": {"name": "t1"}}, "params": {"k": "m1"}},
	"the_part_field_is_null": {"doc": {"trail": {"name": "t1", "dd": null}}, "params": {"k": "m1"}},
	"the_part_field_is_text": {"doc": {"trail": {"name": "t1", "dd": "s"}}, "params": {"k": "m1"}},
	"the_part_field_is_a_list": {"doc": {"trail": {"name": "t1", "dd": [1]}}, "params": {"k": "m1"}},
}

_swap_batch_policy(has, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"round": object.union(_swap_subject(has), {"from": "trails"})},
	"requirements": {"r": {"subject": "round", "checks": checks}},
}

_swap_scenario_rows(rep, n) := [r | some r in rep.results; r.subject.id in {n, null}]

_swap_scenario_view(rep, n) := _swap_view({"results": _swap_scenario_rows(rep, n), "requirements": rep.requirements})

_swap_differences(group) := {n |
	some params in {s.params | some s in _swap_scenarios}
	names := {m | some m, s in _swap_scenarios; s.params == params}
	doc := {"trails": [object.union(_swap_scenarios[m].doc.trail, {"name": m}) | some m in names]}
	checks := _swap_group_checks(group, _swap_alias)
	alias := ergo.report(doc, _swap_batch_policy(_swap_has, checks), params)
	full := ergo.report(doc, _swap_batch_policy({}, _swap_group_checks(group, _swap_full)), params)
	some n in names
	_swap_differs(alias, full, n, checks)
}

_swap_differs(alias, full, n, _) if _swap_scenario_view(alias, n) != _swap_scenario_view(full, n)

_swap_differs(alias, _, n, checks) if object.keys(checks) - {r.check | some r in _swap_scenario_rows(alias, n)} != set()

_untagged(inputs) := [object.remove(i, ["part"]) | some i in inputs]

_tag_has := {
	"coverage": {"from": "dd.cov", "identified_by": "attestation_id"},
	"lst": "dd.items",
	"nowhere": {"from": "dd.cov", "identified_by": "nope"},
	"nulled": {"from": "dd.cov", "identified_by": "nothing"},
	"obj": {"from": "dd.cov", "identified_by": "meta"},
}

_tag_doc := {"cov": {"attestation_id": "att-7", "hunks_total": 25, "hunks_acknowledged": 25, "nothing": null, "meta": {"k": [1, 2]}}, "items": [{"x": 1}, {"x": 2}]}

_every_prs := {"pull request": {"from": "every artifacts.pull_requests", "identified_by": "url"}}

_three_doc := {"artifacts": [
	{"fingerprint": "sha-1", "env": "prod", "atts": {"pr": {"id": "att-1", "pull_requests": [
		{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": true}, {"sha": "c2", "verified": false}]},
		{"url": "pr/8", "state": "MERGED", "commits": []},
		{"url": "pr/9", "state": "OPEN", "commits": [{"sha": "c9", "verified": false}, {"sha": "c9"}]},
	]}}},
	{"fingerprint": "sha-2", "env": "dev", "atts": {"pr": {"id": "att-2", "pull_requests": [{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": false}]}]}}},
	{"fingerprint": "sha-4", "env": "prod", "atts": {"pr": {"id": "att-4", "pull_requests": [{"url": "pr/7", "state": "MERGED", "commits": [{"sha": "c1", "verified": true}, {"sha": "c1", "verified": true}]}]}}},
]}

_three_subjects := {
	"artifact": {"from": `artifacts whose env is "prod"`, "identified_by": "fingerprint", "has": {"pr_att": {"from": "atts.pr", "identified_by": "id"}}},
	"pull request": {"from": `every artifact.pr_att.pull_requests whose state is "MERGED"`, "identified_by": "url"},
	"commit": {"from": `every "pull request".commits`, "identified_by": "sha"},
}

_named_params := {"lists": {"a": ["p", "q"], "b": "text", "c": null}, "pats": {"a": ["^a"], "bad": ["("]}, "k": "a", "kbad": "bad", "nk": null, "bk": {"x": 1}}

_named_things := {"things": [{"id": "t1", "x": "p", "kind": "a"}, {"id": "t2", "x": "z", "kind": "b"}, {"id": "t3", "x": "p", "kind": "c"}, {"id": "t4", "x": "p", "kind": "zz"}, {"id": "t5", "x": "p"}, {"id": "t6", "x": 3, "kind": "a"}]}

_commits(ts) := [{"author": a, "timestamp": t} | some i, t in ts; a := ["ada", "grace", "linus", "ken"][i]]

_picked(item, ts) := [row[1], row[2], row[3]] if {
	some row in _for_rows({"for": concat("", [item, " as c"]), "assert": `c.author is "x"`}, [{"id": 1, "commits": _commits(ts)}], {})
}

_picked_author(item, ts) := a if {
	[row[1] | some row in _for_rows({"for": concat("", [item, " as c"]), "assert": `c.author is "ada"`}, [{"id": 1, "commits": _commits(ts)}], {})] == ["satisfied"]
	a := "ada"
} else := a if {
	some a in ["grace", "linus", "ken"]
	[row[1] | some row in _for_rows({"for": concat("", [item, " as c"]), "assert": concat("", [`c.author is "`, a, `"`])}, [{"id": 1, "commits": _commits(ts)}], {})] == ["satisfied"]
}

_line_inputs(check, things) := [l.inputs | some r in ergo.report({"things": things}, _sentence_policy({"c": check}), {}).results; r.check == "c"; some f in r.failed_items; some l in f.failed_assertions]

reserved_check_rows(name) := report({"items": [{"id": 1}]}, {"s": object.union(object.remove(typed_req, ["checks"]), {"checks": {name: "id exists"}})})

subject_problems(subjects, subject, inp) := [i |
	some r in ergo.report(inp, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": "v exists"}}}}, {}).results
	r.check == "$well_formed"
	some i in r.inputs
	not i.name in {"count(checks)", "require"}
]

named_by_rows(subjects, subject, check, inp) := [[r.passed, r.inputs] |
	some r in ergo.report(inp, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"s": {"subject": subject, "checks": {"c": check}}}}, {"allowed": {"a": [1]}}).results
	r.check == "c"
]

_located_rows(checks, doc, params) := [[r.subject.id, r.check, [{"name": i.name, "locations": object.get(i, "locations", null)} | some i in r.inputs]] | some r in ergo.report(doc, _sentence_policy(checks), params).results; not startswith(r.check, "$")]

_subject_policy(from, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"s": {"from": from}},
	"requirements": {"r": {"subject": "s", "checks": checks}},
}

_subject_report(doc, from, checks, params) := ergo.report(doc, _subject_policy(from, checks), params)

_subject_rows(doc, from, check, params) := [[r.subject.id, r.passed, r.cause, r.inputs] | some r in _subject_report(doc, from, {"c": check}, params).results; r.check == "c"]

_subject_problems(from, checks) := [i.value | some i in _subject_report({"xs": []}, from, checks, {}).results[0].inputs; i.name == "checks.c"][0]

_named_read_cause(nums, keys, assertion) := [r.cause | some r in ergo.report(doc, policy, {}).results; r.check == "c"][0] if {
	prs := [{"id": 1, "keys": keys, "rows": [{"n": 1, "p": 7}, {"n": 2, "p": 8}]}]
	doc := {"artifacts": [object.union({"name": "x", "prs": prs}, {"nums": nums})]}
	subjects := {"artifact": {"from": "artifacts", "identified_by": "name"}, "pr": {"from": "every artifact.prs", "identified_by": "id"}}
	policy := {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": "pr", "checks": {"c": {"for": "every keys as k", "assert": assertion}}}}}
}

_named_read_walks := [
	"some rows.n is at least artifact.nums named by k",
	"some rows whose n is artifact.nums named by k and whose p is 7 exists",
	"count of rows whose n is artifact.nums named by k is at least 1",
]

_part_for_subjects(has) := {
	"artifact": {"from": "$input.artifact", "identified_by": "n", "has": has},
	"child": {"from": "every artifact.kids", "identified_by": "id"},
}

_part_for_row(doc, has, check, params) := [r | some r in ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": _part_for_subjects(has), "requirements": {"r": {"subject": "child", "checks": {"c": check}}}}, params).results; r.check == "c"][0]

_clash_doc := {"bs": [{"id": "b1", "k1": {"k2": {"k3": {"z": 2}}}, "kids": [{"id": "k1", "xs": [{"b": {"x": {"z": 1}}, "x": {"z": 7}, "v": 1}, {"b": {"x": {"z": 5}}, "x": {"z": 7}, "v": 9}]}]}]}

_clash_policy(has, extra, check) := {
	"ergo_spec": ergo._spec,
	"subjects": object.union({"b": {"from": "bs", "identified_by": "id", "has": has}, "kid": {"from": "every b.kids", "identified_by": "id"}}, extra),
	"requirements": {"r": {"subject": "kid", "checks": {"c": check}}},
}

_clash_report(has, extra, check) := ergo.report(_clash_doc, _clash_policy(has, extra, check), {})

_clash_problems(has, extra, check) := [i.value | some r in _clash_report(has, extra, check).results; r.check == "$well_formed"; some i in r.inputs; i.name == "checks.c"]

_clash_rows(has, extra, check) := [[r.cause, r.passed] | some r in _clash_report(has, extra, check).results; r.check == "c"]

_part_clash_problems(subjects) := _part_clash_problems_of(subjects, "kid")

_part_clash_problems_of(subjects, subject) := [i | some r in ergo.report(_clash_doc, {"ergo_spec": ergo._spec, "subjects": subjects, "requirements": {"r": {"subject": subject, "checks": {"c": "id exists"}}}}, {}).results; r.check == "$well_formed"; some i in r.inputs; startswith(i.name, "subjects.")]

_clash_b := {"from": "bs", "identified_by": "id", "has": {"x": "k1"}}

_row_of(assertion, thing, params) := row if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}}, "requirements": {"s": {"subject": "thing", "checks": {"c": assertion}}}}
	r := ergo.report({"things": [object.union({"id": "t"}, thing)]}, policy, params)
	some row in r.results
	row.check == "c"
}

_walk_right_rows(check, doc, params) := [[r.passed, r.cause, object.get(r, "message", "")] | some r in ergo.report(doc, _sentence_policy({"c": check}), params).results; r.check == "c"]

_walk_right_doc(components) := {"sbom": {"components": components}, "things": [{"id": "t1", "x": "click", "tags": ["click"]}, {"id": "t2", "x": "attrs", "tags": ["attrs"]}]}

_list_key_policy(subj, check) := {"ergo_spec": ergo._spec, "subjects": {"t": subj}, "requirements": {"r": {"description": "d", "subject": "t", "checks": {"c": {"description": "d", "assert": check}}}}}

_dot_summary(results) := [{"cause": r.cause, "message": object.get(r, "message", null), "names": [i.name | some i in r.inputs]} |
	some r in results
	r.check == "c"
]

_dot_plain_rows(check, doc) := _dot_summary(ergo.report(
	doc, {
		"ergo_spec": ergo._spec,
		"subjects": {"repo": {"from": "repos", "identified_by": "id"}},
		"requirements": {"s": {"subject": "repo", "checks": {"c": check}}},
	},
	{},
).results)

_each_start_report(doc, line) := ergo.report(doc, {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "things"}, "k": {"from": line}}, "requirements": {"r": {"subject": "k", "checks": {"c": "x exists"}}}}, {"keys": ["p"]})

_from_params_rows(line, params) := [[r.check, r.cause, r.message] |
	some r in ergo.report({"things": {"k": {"id": "t"}}}, {"ergo_spec": ergo._spec, "subjects": {"s": {"from": line}}, "requirements": {"r": {"subject": "s", "checks": {"c": "id exists"}}}}, params).results
	not r.check in {"$well_formed", "$unique_ids"}
]

params_position_messages := {row.check: row.message |
	some row in report(
		{"items": [{"id": 1, "zz": "a"}]},
		{"s": {
			"subject_type": "thing",
			"from": "items",
			"identified_by": "id",
			"checks": {
				"c": {"assert": "$params[0].a does not exist"},
				"d": {"assert": "$params[0].a exists"},
				"e": {"assert": "$params[0] named by zz does not exist"},
			},
		}},
	).results
	row.check != "$min_subjects"
}

params_key_messages := {row.check: row.message |
	some row in report(
		{"items": [{"id": 1, "zz": "a"}]},
		{"s": {
			"subject_type": "thing",
			"from": "items",
			"identified_by": "id",
			"checks": {
				"c": {"assert": "$params.a is 1"},
				"d": {"assert": "$params[0].a named by zz is 1"},
				"e": {"assert": "zz is in $params.a"},
				"f": {"assert": "zz is in $params[0].a"},
				"g": {"assert": "count of $params[0] is 1"},
			},
		}},
	).results
	row.check != "$min_subjects"
}

params_for_line_messages := {row.check: row.message |
	some row in report(
		{"items": [{"id": 1, "ws": [1]}]},
		{"s": {
			"subject_type": "thing",
			"from": "items",
			"identified_by": "id",
			"checks": {
				"c": {"for": "every $params as p", "assert": "p.v is 1"},
				"d": {"for": "every $params.v as p", "assert": "p is 1"},
				"e": {"for": "every ws as w", "assert": "w is in $params.v"},
				"f": {"assert": "sum of $params.v is 1"},
				"g": {"assert": "count of $params whose v is 1 is 1"},
			},
		}},
	).results
	not startswith(row.check, "$")
}

_root_rows(checks, item, params) := {r.check: [r.cause, r.message] |
	some r in ergo.report({"prs": [item]}, {"ergo_spec": ergo._spec, "subjects": {"pr": {"from": "prs", "identified_by": "id"}}, "requirements": {"r": {"subject": "pr", "checks": checks}}}, params).results
	not startswith(r.check, "$")
}

_params_not_object_policy := {
	"ergo_spec": ergo._spec,
	"subjects": {"pr": {"from": "prs", "identified_by": "id"}},
	"requirements": {"r": {"subject": "pr", "checks": {
		"least_z": {"for": "every xs as m", "assert": "m.v is at least z"},
		"least_q": {"for": "every xs as m", "assert": "m.v is at least $params.q"},
		"in_q": {"for": "every xs as m", "assert": "m.v is in $params.q"},
		"plain": {"for": "every xs as m", "assert": "z is 1"},
	}}},
}

_params_not_object_doc := {"prs": [{"id": "p0", "z": "s", "xs": [{"v": 1}, {"v": 2}]}]}

_params_not_object_rows(doc, params) := {r.check: [r.cause, r.message, count(r.failed_items)] |
	some r in ergo.report(doc, _params_not_object_policy, params).results
	not startswith(r.check, "$")
}

_item_policy(has, checks) := {
	"ergo_spec": ergo._spec,
	"subjects": {"pr": object.union({"from": "prs", "identified_by": "id"}, has)},
	"requirements": {"r": {"subject": "pr", "checks": checks}},
}

_item_rows(policy, doc, params) := {r.check: [r.cause, object.get(r, "message", null)] |
	some r in ergo.report(doc, policy, params).results
	not startswith(r.check, "$")
}

_named_by_policy := _item_policy({}, {
	"every": {"for": "every xs as m", "assert": "m.k named by m.k is 1"},
	"if_any": {"for": "every xs, if any, as m", "assert": "m.k named by m.k is 1"},
	"two": {"for": "every xs as m", "assert": ["m is $params.l", "m.v named by m.v is 1"]},
})

_params_cause_policy := _item_policy({}, {
	"plain": {"for": "every xs as m", "assert": "m.v is at least 1"},
	"reads": {"for": "every xs as m", "assert": "m.v is at least $params.n"},
	"some": {"for": "some xs as m", "assert": "m.v is 1"},
	"whose": {"for": "every xs whose k is 1 and whose v is in $params.l as m", "assert": "m.v is 1"},
})

_count_part_policy := _item_policy({"has": {"pl": "c"}}, {
	"xs": {"for": "every xs as m", "assert": "count of xs whose v is in pl.z is 0"},
	"ys": {"for": "every xs as m", "assert": "count of m.ys whose v is in pl.z is 0"},
	"at_least": {"for": "every xs as m", "assert": "count of xs whose v is in pl.z is at least 0"},
})
