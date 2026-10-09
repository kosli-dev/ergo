# Checks as sentences: the corpus

Every check, filter and `from` in the policies [#174](https://github.com/kosli-dev/ergo/issues/174) asked to try, written today's way and as a sentence. The sentences follow [`sentences.md`](sentences.md), and every one of them parses exactly one way with the tokenizer described there. The tally, the misfits and the open questions are [at the end](#tally).

The sources, as of 9 October 2026:

- [kosli-dev/sdlc-policies](https://github.com/kosli-dev/sdlc-policies) `policies/*/policy.rego`
- [kosli-dev/server](https://github.com/kosli-dev/server) `demo/use_cases/policies/` and `flow-templates/policies/npm-bump/`. Seven of the demo policies are plain Rego, not ergo. Their conditions are written as the checks an ergo policy would have.
- [kosli-dev/pr-reviewer](https://github.com/kosli-dev/pr-reviewer) `kosli/policies/review-controls/`, custom operators included
- ergo's `examples/baking` and the README example
- Tore's DEV controls, all 36 of them, from [kosli-playground/dev-process-controls](https://github.com/kosli-playground/dev-process-controls). They're invented to exercise ergo, so a check only they need weighs less.

Paths are written as the sentence writes them. `$params.x` is today's `{ref: [$$params, x]}`, `$input` is `$$input`, and `named by $params.x` reads a key named by a param, a ref step today. Brackets are the other spelling, `artifacts_statuses[$params.artifact_name]`, and the corpus uses the word form, as the report prints it. The subject's `id` is one key in every policy here, so it's left out.

Notes in the last column:

- **widens** (52 checks): `non_empty_string` becomes `is not empty`, which also passes a list with items in it.
- **widens ""** (6): `empty` or `equals []` becomes `is empty`, which also passes `""`.
- **cause only** (4): the same values pass, and only the cause of a failure changes. `range` from 0 to 0 becomes `is 0`, so a value that isn't a number fails as `value` instead of `unusable`. `equals` with a ref becomes `equals $params.x`, so a value of another type fails as `unusable` instead of `value`.
- **no default** (37): a Rego variable with a default became `$params.x`, which ergo can't default.
- **Rego-shaped** (24): Rego works the value out before ergo sees it. The sentence covers what ergo checks afterwards.
- **narrows** (6): fails closed where today passes.

## sdlc-policies

### SDLC-CTRL-0002 binary provenance

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, {ref: [$$params, artifact_name]}]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` |  |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `name` | `{op: non_empty_string, path: [name]}` | `name is not empty` | widens |
| `commit` | `{op: non_empty_string, path: [git_commit_info, sha1]}` | `git_commit_info.sha1 is not empty` | widens |
| `repo_url` | `{op: non_empty_string, path: [git_commit_info, url]}` | `git_commit_info.url is not empty` | widens |
| `build_url` | `{op: non_empty_string, path: [origin_url]}` | `origin_url is not empty` | widens |

### SDLC-CTRL-0007 code review

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, {ref: [$$params, artifact_name]}]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` |  |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `pr_attestation` | `{op: equals, path: [attestations_statuses, {ref: [$$params, pr_attestation_name]}, status], value: COMPLETE}` | `attestations_statuses named by $params.pr_attestation_name.status is "COMPLETE"` |  |
| `from` of pull request | `[trail, compliance_status, artifacts_statuses, {ref: [$$params, artifact_name]}, attestations_statuses, {ref: [$$params, pr_attestation_name]}, pull_requests, {each_as: pr}]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name.attestations_statuses named by $params.pr_attestation_name.pull_requests` | The name `pr` goes: #174 now names things in a `for` line, and the subject's fields are bare there. |
| `merged` | `{op: equals, path: [state], value: MERGED}` | `state is "MERGED"` |  |
| `protected_branch` | `{op: equals, path: [base_ref], value: {ref: [$$params, protected_branch]}}` | `base_ref equals $params.protected_branch` | cause only. Today a branch name of another type fails as `value`. With a path on the right, the sentence fails it as `unusable`. The same values pass. |
| `signed_commits` | `{op: all, path: [commits], check: {op: equals, path: [verified], value: true}}` | `every commits.verified is true` |  |
| `peer_approval` | `{op: any, path: [approvers], as: approver, check: {op: any_of, options: {peer: [{op: equals, path: [state], value: APPROVED}, {op: compare, left: [username], right: [$pr, author], cmp: ne}, {op: all, path: [$pr, commits], check: {op: compare, left: [$approver, timestamp], right: [timestamp], cmp: gt}}]}}}` | — | **misfit**, see below |

### SDLC-CTRL-0008 quality assurance

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, {ref: [$$params, artifact_name]}]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` |  |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `from` of test suite | `[trail, compliance_status, artifacts_statuses, {ref: [$$params, artifact_name]}, attestations_statuses, {each_as: suite, keys: {ref: [$$params, test_attestation_names]}}]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name.attestations_statuses named by each of $params.test_attestation_names` | The name `suite` is never read, so it goes. |
| `recorded` | `{op: equals, path: [status], value: COMPLETE}` | `status is "COMPLETE"` |  |
| `passed` | `{op: equals, path: [is_compliant], value: true}` | `is_compliant is true` |  |
| `attached` | `{op: equals, path: [has_audit_package], value: true}` | `has_audit_package is true` |  |

### SDLC-CTRL-0004 dependencies

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[artifact]` | `artifact` | Rego-shaped. Every subject in this policy is built by Rego from the attested lockfile, Dockerfile and SBOM text. The sentences only cover what ergo checks after that. |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `lockfile_attested` | `{op: equals, path: [attestations_statuses, <lock_attestation_name>, status], value: COMPLETE}` | `attestations_statuses named by $params.lock_attestation_name.status is "COMPLETE"` | no default |
| `dockerfile_attested` | `{op: equals, path: [attestations_statuses, <dockerfile_attestation_name>, status], value: COMPLETE}` | `attestations_statuses named by $params.dockerfile_attestation_name.status is "COMPLETE"` | no default |
| `sbom_attested` | `{op: equals, path: [attestations_statuses, <sbom_attestation_name>, status], value: COMPLETE}` | `attestations_statuses named by $params.sbom_attestation_name.status is "COMPLETE"` | no default |
| `from` of lockfile | `[lockfile]` | `lockfile` | Rego-shaped |
| filter `recorded` | `{op: present, path: [status]}` | `status exists` |  |
| filter `attested` | `{op: equals, path: [status], value: COMPLETE}` | `status is "COMPLETE"` |  |
| `exact_pins` | `{op: range, path: [exact_pins], min: 1, max: 1000000}` | `exact_pins is between 1 and 1000000` | The 1000000 only stands in for "no upper bound". `exact_pins is at least 1` says what was meant, but passes above a million. |
| `hashes` | `{op: equals, path: [hashed], value: true}` | `hashed is true` |  |
| `from` of lockfile entry | `[lock_entries]` | `lock_entries` | Rego-shaped |
| `exact_pin` | `{op: not_matches_any, path: [entry], patterns: ['^[A-Za-z0-9._-]+\s*(>=\|<=\|~=\|!=\|<\|>)']}` | `entry does not match '^[A-Za-z0-9._-]+\s*(>=\|<=\|~=\|!=\|<\|>)'` | Single quotes keep the backslash as written. In double quotes, JSON escapes apply and `\s` would have to be `\\s`. |
| `from` of SBOM package | `[components]` | `components` | Rego-shaped |
| filter `locked` | `{op: present, path: [lock_release]}` | `lock_release exists` |  |
| `matches_lock` | `{op: compare, left: [sbom_release], right: [lock_release], cmp: eq}` | `sbom_release equals lock_release` |  |
| filter `not_exempt` | `{op: equals, path: [exempt], value: false}` | `exempt is false` |  |
| `licence_known` | `{op: any, path: [licences], check: {op: non_empty_string, path: []}}` | `some licences is not empty` | widens |
| `licence_approved` | `{op: any, path: [licences], check: {op: in, path: [], values: {ref: [$$params, allowed_licenses]}}}` | `some licences is in $params.allowed_licenses` |  |
| `from` of base image | `[base_images]` | `base_images` | Rego-shaped |
| `pinned` | `{op: equals, path: [pinned], value: true}` | `pinned is true` |  |

## server

### demo SDLC-CTRL-0002 binary provenance

Same as SDLC-CTRL-0002 binary provenance, except:

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, <artifact_name>]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |

### demo SDLC-CTRL-0003 controlled build (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `fingerprint` | `is_string(artifact.artifact_fingerprint); artifact.artifact_fingerprint != ""` | `artifact_fingerprint is not empty` | widens |
| `build_complete` | `artifact.attestations_statuses[build_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.build_attestation_name.status is "COMPLETE"` | no default |
| `build_compliant` | `artifact.attestations_statuses[build_attestation_name].is_compliant == true` | `attestations_statuses named by $params.build_attestation_name.is_compliant is true` | no default |
| `build_has_attachment` | `artifact.attestations_statuses[build_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.build_attestation_name.has_audit_package is true` | no default |

### demo SDLC-CTRL-0006 secrets scanning (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `scan_complete` | `artifact.attestations_statuses[scan_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.scan_attestation_name.status is "COMPLETE"` | no default |
| `scan_compliant` | `artifact.attestations_statuses[scan_attestation_name].is_compliant == true` | `attestations_statuses named by $params.scan_attestation_name.is_compliant is true` | no default |
| `scan_has_attachment` | `artifact.attestations_statuses[scan_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.scan_attestation_name.has_audit_package is true` | no default |

### demo SDLC-CTRL-0004 dependencies

Same as SDLC-CTRL-0004 dependencies, except:

| | today | sentence | notes |
| --- | --- | --- | --- |
| filter `attested` | `{op: equals, path: [status], value: COMPLETE}` | `status is "COMPLETE"` | This copy has no `recorded` filter, only `attested`. |
| `licence_known` | `{op: any, path: [licences], check: {op: non_empty_string, path: [id]}}` | `some licences.id is not empty` | widens |
| `licence_approved` | `{op: any, path: [licences], check: {op: equals, path: [allowed], value: true}}` | `some licences.allowed is true` | Rego-shaped. Rego works out `allowed` from the params before ergo sees it. |

### demo SDLC-CTRL-0007 code review

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, <artifact_name>]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `pr_attestation` | `{op: equals, path: [attestations_statuses, <pr_attestation_name>, status], value: COMPLETE}` | `attestations_statuses named by $params.pr_attestation_name.status is "COMPLETE"` | no default |
| `from` of pull request | `[pull_requests]` | `pull_requests` | Rego-shaped. Rego copies each pull request's author and last commit time onto every approver, so the check needs no `$pr` and no inner `all`. |
| `merged` | `{op: equals, path: [state], value: MERGED}` | `state is "MERGED"` |  |
| `protected_branch` | `{op: equals, path: [base_ref], value: <protected_branch>}` | `base_ref equals $params.protected_branch` | no default. cause only |
| `signed_commits` | `{op: all, path: [commits], check: {op: equals, path: [verified], value: true}}` | `every commits.verified is true` |  |
| `peer_approval` | `{op: any, path: [approvers], check: {op: any_of, options: {peer: [{op: equals, path: [state], value: APPROVED}, {op: compare, left: [username], right: [pr_author], cmp: ne}, {op: compare, left: [timestamp], right: [last_commit_timestamp], cmp: gt}]}}}` | `some approvers.timestamp where state is "APPROVED" and username is not pr_author is after last_commit_timestamp` | Rego-shaped. narrows. Today compares timestamps as text. `is after` compares them as times, so a timestamp that isn't RFC 3339 fails instead of being ordered as text. `is more than` keeps today's meaning and reads worse. |

### demo SDLC-CTRL-0008 quality assurance

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[trail, compliance_status, artifacts_statuses, <artifact_name>]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `fingerprint` | `{op: non_empty_string, path: [artifact_fingerprint]}` | `artifact_fingerprint is not empty` | widens |
| `from` of test suite | `[suites, <name>], one requirement per name in Rego` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name.attestations_statuses named by each of $params.test_attestation_names` | Rego-shaped. no default. **misfit**, see below |
| `recorded` | `{op: equals, path: [attestation, status], value: COMPLETE}` | `status is "COMPLETE"` | Written against the sdlc-policies subject, where the suite is the attestation itself. |
| `passed` | `{op: equals, path: [attestation, is_compliant], value: true}` | `is_compliant is true` |  |
| `attached` | `{op: equals, path: [attestation, has_audit_package], value: true}` | `has_audit_package is true` |  |

### demo SDLC-CTRL-0010 deployment approval (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `approval_complete` | `artifact.attestations_statuses[approval_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.approval_attestation_name.status is "COMPLETE"` | no default |
| `approval_compliant` | `artifact.attestations_statuses[approval_attestation_name].is_compliant == true` | `attestations_statuses named by $params.approval_attestation_name.is_compliant is true` | no default |
| `approval_has_attachment` | `artifact.attestations_statuses[approval_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.approval_attestation_name.has_audit_package is true` | no default |
| `approved_by_non_author` | `some approver in attestation.approvers; approver != attestation.author` | `for: some attestations_statuses named by $params.approval_attestation_name.approvers as approver`<br>`assert: approver is not attestations_statuses named by $params.approval_attestation_name.author` | no default. narrows. `for` line. The approver is compared with a field of the attestation, so it takes a `for` line. Rego's `!=` passes when the types differ, `is not` fails as `unusable`. |

### demo SDLC-CTRL-0020 SAST (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `scan_complete` | `artifact.attestations_statuses[scan_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.scan_attestation_name.status is "COMPLETE"` | no default |
| `scan_compliant` | `artifact.attestations_statuses[scan_attestation_name].is_compliant == true` | `attestations_statuses named by $params.scan_attestation_name.is_compliant is true` | no default |
| `scan_has_attachment` | `artifact.attestations_statuses[scan_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.scan_attestation_name.has_audit_package is true` | no default |

### demo SDLC-CTRL-0021 SCA (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `scan_complete` | `artifact.attestations_statuses[scan_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.scan_attestation_name.status is "COMPLETE"` | no default |
| `scan_compliant` | `artifact.attestations_statuses[scan_attestation_name].is_compliant == true` | `attestations_statuses named by $params.scan_attestation_name.is_compliant is true` | no default |
| `scan_has_attachment` | `artifact.attestations_statuses[scan_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.scan_attestation_name.has_audit_package is true` | no default |

### demo SDLC-CTRL-0022 container scan (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `input.trail.compliance_status.artifacts_statuses[artifact_name]` | `trail.compliance_status.artifacts_statuses named by $params.artifact_name` | no default |
| `scan_complete` | `artifact.attestations_statuses[scan_attestation_name].status == "COMPLETE"` | `attestations_statuses named by $params.scan_attestation_name.status is "COMPLETE"` | no default |
| `scan_compliant` | `artifact.attestations_statuses[scan_attestation_name].is_compliant == true` | `attestations_statuses named by $params.scan_attestation_name.is_compliant is true` | no default |
| `scan_has_attachment` | `artifact.attestations_statuses[scan_attestation_name].has_audit_package == true` | `attestations_statuses named by $params.scan_attestation_name.has_audit_package is true` | no default |

### demo require-artifact-provenance (plain Rego)

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of compliance decision | `input` | — | No `from`: the whole input is the subject. |
| `fingerprint` | `input.artifact_fingerprint != null; input.artifact_fingerprint != ""` | `artifact_fingerprint is not empty` | narrows. Rego passes any value but `null` and `""`, a number included. `is not empty` fails a number as `unusable`. |
| `compliant` | `input.is_compliant == true` | `is_compliant is true` |  |

### flow-templates npm-bump

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of repository | `[trail, compliance_status, artifacts_statuses, artifact, attestations_statuses, npm-bump-prs, attestation_data]` | `trail.compliance_status.artifacts_statuses.artifact.attestations_statuses.npm-bump-prs.attestation_data` |  |
| `no_open_bump_pr` | `{op: equals, path: [open_bump_prs], value: []}` | `open_bump_prs is empty` | widens "". `must`: `open_bump_prs is empty` reads like a status. |

## pr-reviewer

### review-controls

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of review_round | `[trail]` | `trail` | Ten requirements read the same round. Every path below starts with `compliance_status.attestations_statuses`, because the subject is the whole trail. |
| `every_hunk_acknowledged` | `{op: compare, left: [compliance_status, attestations_statuses, coverage-verification, attestation_data, hunks_acknowledged], right: [compliance_status, attestations_statuses, coverage-verification, attestation_data, hunks_total], cmp: eq}` | `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_acknowledged equals compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_total` |  |
| `two_vendors` | `{op: compare, left: [compliance_status, attestations_statuses, claude-review, attestation_data, model_type], right: [compliance_status, attestations_statuses, gemini-review, attestation_data, model_type], cmp: ne}` | `compliance_status.attestations_statuses.claude-review.attestation_data.model_type is not compliance_status.attestations_statuses.gemini-review.attestation_data.model_type` |  |
| `both_models_contributed` | `{op: equals, path: [compliance_status, attestations_statuses, cross-model-comparison, attestation_data, both_models_ran], value: true}` | `compliance_status.attestations_statuses.cross-model-comparison.attestation_data.both_models_ran is true` |  |
| `personas_dispatched` | `{op: min_length, path: [compliance_status, attestations_statuses, classifier, attestation_data, personas_dispatched], min: 1, expression: ...}` | `count of compliance_status.attestations_statuses.classifier.attestation_data.personas_dispatched is at least 1` | replaces custom `min_length`. `is not empty` reads better, but also passes a non-empty string, where `min_length` fails. |
| `moderator_succeeded` | `{op: in, path: [compliance_status, attestations_statuses, verdict, attestation_data, moderator_status], values: [resolved, no_disagreements, single_reviewer]}` | `compliance_status.attestations_statuses.verdict.attestation_data.moderator_status is one of "resolved", "no_disagreements", "single_reviewer"` |  |
| `claude_degraded_recorded` | `{op: in, path: [compliance_status, attestations_statuses, claude-review, attestation_data, degraded], values: [true, false]}` | `compliance_status.attestations_statuses.claude-review.attestation_data.degraded is one of true, false` |  |
| `gemini_degraded_recorded` | `{op: in, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, degraded], values: [true, false]}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.degraded is one of true, false` |  |
| `verifier_degraded_recorded` | `{op: in, path: [compliance_status, attestations_statuses, finding-verifier, attestation_data, degraded], values: [true, false]}` | `compliance_status.attestations_statuses.finding-verifier.attestation_data.degraded is one of true, false` |  |
| `one_verifier_record_per_finding` | `{op: length_eq_difference, left: [compliance_status, attestations_statuses, finding-verifier, attestation_data, per_finding_records], right: [compliance_status, attestations_statuses, finding-verifier, attestation_data, findings_in], minus: [compliance_status, attestations_statuses, finding-verifier, attestation_data, findings_unverified_cost_cap], expression: ..., inputs: [...]}` | `count of compliance_status.attestations_statuses.finding-verifier.attestation_data.per_finding_records plus compliance_status.attestations_statuses.finding-verifier.attestation_data.findings_unverified_cost_cap equals compliance_status.attestations_statuses.finding-verifier.attestation_data.findings_in` | replaces custom `length_eq_difference`. The control says "minus". With only `plus`, the sentence moves the term across. Its custom `inputs` showed each record's `finding_id` rather than the records, and the sentence has no way to say that. |
| `verifier_degraded_input` | `{op: compare, left: [compliance_status, attestations_statuses, finding-verifier, attestation_data, degraded], right: [..., final-verdict, attestation_data, inputs, verifier_degraded], cmp: eq}` | `compliance_status.attestations_statuses.finding-verifier.attestation_data.degraded equals compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.verifier_degraded` |  |
| `final_verdict_rules_hold` | `{op: equals, path: [compliance_status, attestations_statuses, final-verdict, is_compliant], value: true}` | `compliance_status.attestations_statuses.final-verdict.is_compliant is true` |  |
| `verifier_enabled` | `{op: equals, path: [compliance_status, attestations_statuses, finding-verifier, attestation_data, verifier_enabled], value: true}` | `compliance_status.attestations_statuses.finding-verifier.attestation_data.verifier_enabled is true` |  |
| `context_recorded` | `{op: non_empty_string, path: [compliance_status, attestations_statuses, review-context-manifest, attestation_id]}` | `compliance_status.attestations_statuses.review-context-manifest.attestation_id is not empty` | widens |
| `reviewer_version_recorded` | `{op: matches_any, path: [compliance_status, attestations_statuses, preflight, attestation_data, reviewer_source_sha], patterns: ['^[0-9a-f]{7,40}$']}` | `compliance_status.attestations_statuses.preflight.attestation_data.reviewer_source_sha matches "^[0-9a-f]{7,40}$"` |  |
| `persona_config_recorded` | `{op: matches_any, path: [compliance_status, attestations_statuses, preflight, attestation_data, config_tree_sha], patterns: ['^[0-9a-f]{40}$']}` | `compliance_status.attestations_statuses.preflight.attestation_data.config_tree_sha matches "^[0-9a-f]{40}$"` |  |
| `uncovered_before_second_pass_recorded` | `{op: min_length, path: [..., coverage-verification, attestation_data, before_second_pass, uncovered], min: 0, expression: ...}` | `compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.uncovered is a list` | replaces custom `min_length` |
| `cost_cap_state_recorded` | `{op: in, path: [..., coverage-verification, attestation_data, before_second_pass, cost_capped], values: [true, false]}` | `compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.cost_capped is one of true, false` |  |
| `per_file_coverage_recorded` | `{op: min_length_at, path: [compliance_status, attestations_statuses, coverage-verification, attestation_data, files], min_path: [compliance_status, attestations_statuses, coverage-verification, attestation_data, total_files], expression: ..., inputs: [...]}` | `count of compliance_status.attestations_statuses.coverage-verification.attestation_data.files is at least compliance_status.attestations_statuses.coverage-verification.attestation_data.total_files` | replaces custom `min_length_at` |
| `first_pass_findings_recorded` | `{op: count_where_eq_sum, path: [compliance_status, attestations_statuses, findings, attestation_data, raw], field: source, value: first_pass, sum: [[compliance_status, attestations_statuses, claude-review, attestation_data, total_findings], [compliance_status, attestations_statuses, gemini-review, attestation_data, total_findings]], expression: ..., inputs: [...]}` | `count of compliance_status.attestations_statuses.findings.attestation_data.raw where source is "first_pass" equals compliance_status.attestations_statuses.claude-review.attestation_data.total_findings plus compliance_status.attestations_statuses.gemini-review.attestation_data.total_findings` | narrows. replaces custom `count_where_eq_sum`. A raw finding with no `source` is skipped by the custom operator and fails the sentence as `absent`, as #173 found on 12 of 800 inputs. |
| `findings_complete` | `{op: equals, path: [compliance_status, attestations_statuses, findings, attestation_data, truncated], value: false}` | `compliance_status.attestations_statuses.findings.attestation_data.truncated is false` | `must`: `truncated is false` reads like a status. |
| `round_cost_sums_its_stages` | `{op: sum_eq, path: [..., final-verdict, attestation_data, cost, by_stage], field: usd, only: {}, total: [..., cost, total_usd], tolerance: 0.000001, expression: ...}` | `sum of compliance_status.attestations_statuses.final-verdict.attestation_data.cost.by_stage.usd equals compliance_status.attestations_statuses.final-verdict.attestation_data.cost.total_usd within 0.000001` | replaces custom `sum_eq` |
| `verifier_cost_matches_its_stage` | `{op: sum_eq, path: [..., final-verdict, attestation_data, cost, by_stage], field: usd, only: {stage: verifier}, total: [compliance_status, attestations_statuses, finding-verifier, attestation_data, cost_usd], tolerance: 0.000001, expression: ...}` | `sum of compliance_status.attestations_statuses.final-verdict.attestation_data.cost.by_stage.usd where stage is "verifier" equals compliance_status.attestations_statuses.finding-verifier.attestation_data.cost_usd within 0.000001` | narrows. replaces custom `sum_eq`. A sum over no rows is 0, as the custom operator gives (checked on `main`). A stage row with no `stage` field is skipped by the custom operator and fails the sentence as `absent`. |
| `dispatched_personas_recorded` | `{op: keys_match, keys: [compliance_status, attestations_statuses, classifier, attestation_data, personas_dispatched], path: [compliance_status, attestations_statuses, preflight, attestation_data, persona_blob_shas], patterns: ['^[0-9a-f]{40}$'], expression: ..., inputs: [...]}` | `for: every compliance_status.attestations_statuses.classifier.attestation_data.personas_dispatched as persona`<br>`assert: compliance_status.attestations_statuses.preflight.attestation_data.persona_blob_shas named by persona matches "^[0-9a-f]{40}$"` | replaces custom `keys_match`. **misfit**, see below |
| `from` of finding (verifier_record, confirmed_finding) | `[trail, compliance_status, attestations_statuses, finding-verifier, attestation_data, per_finding_records]` | `trail.compliance_status.attestations_statuses.finding-verifier.attestation_data.per_finding_records` |  |
| `known_decision` | `{op: in, path: [decision], values: [CONFIRMED, UNSURE, SUGGESTION, REFUTED]}` | `decision is one of "CONFIRMED", "UNSURE", "SUGGESTION", "REFUTED"` |  |
| filter `confirmed` | `{op: equals, path: [decision], value: CONFIRMED}` | `decision is "CONFIRMED"` |  |
| `inspected` | `{op: any, path: [tools_called], check: {op: equals, path: [ok], value: true}}` | `some tools_called.ok is true` |  |
| filter `resolved` | `{op: equals, path: [compliance_status, attestations_statuses, verdict, attestation_data, moderator_status], value: resolved}` | `compliance_status.attestations_statuses.verdict.attestation_data.moderator_status is "resolved"` |  |
| `counted` | `{op: min_length_at, path: [compliance_status, attestations_statuses, verdict, attestation_data, debate_resolutions], min_path: [compliance_status, attestations_statuses, verdict, attestation_data, debate_disagreements_found], expression: ..., inputs: [...]}` | `count of compliance_status.attestations_statuses.verdict.attestation_data.debate_resolutions is at least compliance_status.attestations_statuses.verdict.attestation_data.debate_disagreements_found` | replaces custom `min_length_at` |
| filter `moderator_failed` | `{op: not_matches_any, path: [compliance_status, attestations_statuses, verdict, attestation_data, moderator_status], patterns: ['^(resolved\|no_disagreements\|single_reviewer\|disabled)$']}` | `compliance_status.attestations_statuses.verdict.attestation_data.moderator_status does not match "^(resolved\|no_disagreements\|single_reviewer\|disabled)$"` | `is not one of "resolved", "no_disagreements", "single_reviewer", "disabled"` reads better, but would put a status that isn't a string in scope, where today it fails the requirement as `unusable`. |
| `recorded (moderator failure)` | `{op: equals, path: [..., final-verdict, attestation_data, inputs, moderator_failed], value: true}` | `compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.moderator_failed is true` |  |
| `from` of resolution | `[trail, ..., verdict, attestation_data, debate_resolutions]` | `trail.compliance_status.attestations_statuses.verdict.attestation_data.debate_resolutions` |  |
| `reasoned` | `{op: non_empty_string, path: [reasoning]}` | `reasoning is not empty` | widens |
| filter `gap` | `{op: min_length, path: [..., before_second_pass, uncovered], min: 1}` | `count of compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.uncovered is at least 1` | replaces custom `min_length` |
| filter `not_capped` | `{op: equals, path: [..., before_second_pass, cost_capped], value: false}` | `compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.cost_capped is false` |  |
| `targeted` | `{op: contains_all, path: [compliance_status, attestations_statuses, second-pass, attestation_data, files_targeted], of: [..., before_second_pass, uncovered], expression: ..., inputs: [...]}` | `compliance_status.attestations_statuses.second-pass.attestation_data.files_targeted contains all of compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.uncovered` | replaces custom `contains_all`. The custom operator passes when the list it checks against is empty, and `includes` with `values` fails then. The `gap` filter keeps that list non-empty, so nothing in scope changes. |
| filter `gap` | `{op: min_length, path: [..., before_second_pass, uncovered], min: 1}` | `count of compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.uncovered is at least 1` | replaces custom `min_length` |
| filter `capped` | `{op: equals, path: [..., before_second_pass, cost_capped], value: true}` | `compliance_status.attestations_statuses.coverage-verification.attestation_data.before_second_pass.cost_capped is true` |  |
| `cap_recorded` | `{op: equals, path: [compliance_status, attestations_statuses, second-pass, attestation_data, skip_reason], value: cost_cap}` | `compliance_status.attestations_statuses.second-pass.attestation_data.skip_reason is "cost_cap"` |  |
| `from` of file | `[trail, ..., coverage-verification, attestation_data, files]` | `trail.compliance_status.attestations_statuses.coverage-verification.attestation_data.files` |  |
| `acknowledged` | `{op: equals, path: [status], value: reviewed_ok}` | `status is "reviewed_ok"` |  |
| filter `triggered` | `{op: equals, path: [compliance_status, attestations_statuses, second-pass, attestation_data, triggered], value: true}` | `compliance_status.attestations_statuses.second-pass.attestation_data.triggered is true` |  |
| `recorded (second pass findings)` | `{op: count_where_eq_sum, path: [compliance_status, attestations_statuses, findings, attestation_data, raw], field: source, value: second_pass, sum: [[compliance_status, attestations_statuses, second-pass, attestation_data, findings_added]], ...}` | `count of compliance_status.attestations_statuses.findings.attestation_data.raw where source is "second_pass" equals compliance_status.attestations_statuses.second-pass.attestation_data.findings_added` | narrows. replaces custom `count_where_eq_sum` |
| `from` of finding (raw_finding) | `[trail, ..., findings, attestation_data, raw]` | `trail.compliance_status.attestations_statuses.findings.attestation_data.raw` |  |
| `disposed` | `{op: in, path: [disposition], values: [posted, merged, refuted_by_codebase_check, suppressed_by_moderator, dropped_by_citation_check, dropped_out_of_diff, refuted_by_verifier, demoted_to_suggestion]}` | `disposition is one of "posted", "merged", "refuted_by_codebase_check", "suppressed_by_moderator", "dropped_by_citation_check", "dropped_out_of_diff", "refuted_by_verifier", "demoted_to_suggestion"` |  |
| `from` of finding (posted_finding) | `[trail, ..., findings, attestation_data, posted]` | `trail.compliance_status.attestations_statuses.findings.attestation_data.posted` |  |
| filter `from_a_model` | `{op: not_matches_any, path: [source], patterns: ['^empty_file$']}` | `source is not "empty_file"` | Same passes as the pattern: both fail a missing source as `absent` and one that isn't a string as `unusable`. |
| `in_file` | `{op: equals, path: [in_file], value: true}` | `in_file is true` |  |
| filter `claude-review_ran_some` | `{op: min_length, path: [compliance_status, attestations_statuses, claude-review, attestation_data, personas_ran], min: 1}` | `count of compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is at least 1` | replaces custom `min_length` |
| `personas_match (claude_ran_dispatched)` | `{op: compare, left: [compliance_status, attestations_statuses, classifier, attestation_data, personas_dispatched], right: [compliance_status, attestations_statuses, claude-review, attestation_data, personas_ran], cmp: eq}` | `compliance_status.attestations_statuses.classifier.attestation_data.personas_dispatched equals compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran` |  |
| filter `gemini-review_ran_some` | `{op: min_length, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, personas_ran], min: 1}` | `count of compliance_status.attestations_statuses.gemini-review.attestation_data.personas_ran is at least 1` | replaces custom `min_length` |
| `personas_match (gemini_ran_dispatched)` | `{op: compare, left: [compliance_status, attestations_statuses, classifier, attestation_data, personas_dispatched], right: [compliance_status, attestations_statuses, gemini-review, attestation_data, personas_ran], cmp: eq}` | `compliance_status.attestations_statuses.classifier.attestation_data.personas_dispatched equals compliance_status.attestations_statuses.gemini-review.attestation_data.personas_ran` |  |
| filter `claude-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, claude-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.claude-review.attestation_data.degraded is true` |  |
| filter `claude-review_ran_none` | `{op: equals, path: [compliance_status, attestations_statuses, claude-review, attestation_data, personas_ran], value: []}` | `compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is empty` | widens "" |
| `reason_recorded (claude_only_degraded)` | `{op: any_of, options: {single_model: [{op: includes, path: [..., final-verdict, attestation_data, inputs, degraded_reasons], value: single_model}], no_models: [{op: includes, path: [...], value: no_models}]}}` | `some compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.degraded_reasons is one of "single_model", "no_models"` | An `any_of` of two `includes` becomes `some` over the list. Both fail an empty list as `value` and a missing one as `absent`. The row loses the option names. |
| filter `gemini-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.degraded is true` |  |
| filter `gemini-review_ran_none` | `{op: equals, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, personas_ran], value: []}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.personas_ran is empty` | widens "" |
| `reason_recorded (gemini_only_degraded)` | `{op: any_of, options: {single_model: [{op: includes, path: [..., final-verdict, attestation_data, inputs, degraded_reasons], value: single_model}], no_models: [{op: includes, path: [...], value: no_models}]}}` | `some compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.degraded_reasons is one of "single_model", "no_models"` | An `any_of` of two `includes` becomes `some` over the list. Both fail an empty list as `value` and a missing one as `absent`. The row loses the option names. |
| filter `claude-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, claude-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.claude-review.attestation_data.degraded is true` |  |
| filter `gemini-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.degraded is true` |  |
| filter `claude-review_ran_none` | `{op: equals, path: [compliance_status, attestations_statuses, claude-review, attestation_data, personas_ran], value: []}` | `compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is empty` | widens "" |
| filter `gemini-review_ran_none` | `{op: equals, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, personas_ran], value: []}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.personas_ran is empty` | widens "" |
| `reason_recorded (both_models_degraded)` | `{op: any_of, options: {no_models: [{op: includes, path: [..., final-verdict, attestation_data, inputs, degraded_reasons], value: no_models}]}}` | `compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.degraded_reasons contains "no_models"` |  |
| filter `claude-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, claude-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.claude-review.attestation_data.degraded is true` |  |
| filter `claude-review_ran_some` | `{op: min_length, path: [compliance_status, attestations_statuses, claude-review, attestation_data, personas_ran], min: 1}` | `count of compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is at least 1` | replaces custom `min_length` |
| `reason_recorded (claude_persona_failed)` | `{op: any_of, options: {persona_failed: [{op: includes, path: [..., final-verdict, attestation_data, inputs, degraded_reasons], value: persona_failed}]}}` | `compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.degraded_reasons contains "persona_failed"` |  |
| filter `gemini-review_degraded_true` | `{op: equals, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, degraded], value: true}` | `compliance_status.attestations_statuses.gemini-review.attestation_data.degraded is true` |  |
| filter `gemini-review_ran_some` | `{op: min_length, path: [compliance_status, attestations_statuses, gemini-review, attestation_data, personas_ran], min: 1}` | `count of compliance_status.attestations_statuses.gemini-review.attestation_data.personas_ran is at least 1` | replaces custom `min_length` |
| `reason_recorded (gemini_persona_failed)` | `{op: any_of, options: {persona_failed: [{op: includes, path: [..., final-verdict, attestation_data, inputs, degraded_reasons], value: persona_failed}]}}` | `compliance_status.attestations_statuses.final-verdict.attestation_data.inputs.degraded_reasons contains "persona_failed"` |  |

## ergo

### examples/baking

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of batch | `[batches]` | `batches` |  |
| `nut_free` | `{op: excludes, path: [allergens], value: nuts}` | `allergens does not contain "nuts"` |  |
| `temp_ok` | `{op: range, path: [bake, temp_c], min: 175, max: 200}` | `bake.temp_c is between 175 and 200` |  |
| `time_ok` | `{op: range, path: [bake, minutes], min: 25, max: 40}` | `bake.minutes is between 25 and 40` |  |

### README

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of deployment | `[deployments]` | `deployments` |  |
| filter `is_prod` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `approved` | `{op: non_empty_string, path: [approved_by]}` | `approved_by is not empty` | widens |

## DEV controls

### DEV-0101 requirements approved

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of business requirement | `[release, requirements]` | `release.requirements` |  |
| `defined` | `{op: non_empty_string, path: [document_url]}` | `document_url is not empty` | widens |
| `security_considered` | `{op: includes, path: [assessed], values: [system_security, data_protection, privacy]}` | `assessed contains all of "system_security", "data_protection", "privacy"` |  |
| `approved` | `{op: non_empty_string, path: [approved_by]}` | `approved_by is not empty` | widens |
| `approved_before_production` | `{op: compare_time, left: [approved_at], right: [$$input, release, deployed_at], cmp: lt}` | `approved_at is before $input.release.deployed_at` |  |

### DEV-0102 impact analysis, new features

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `in_scope` | `{op: equals, path: [change_type], value: new_development}` | `change_type is "new_development"` |  |
| `performed` | `{op: non_empty_string, path: [impact_analysis, document_url]}` | `impact_analysis.document_url is not empty` | widens |
| `business_owner_approved` | `{op: equals, path: [impact_analysis, approved_by_role], value: business_owner}` | `impact_analysis.approved_by_role is "business_owner"` |  |
| `approved_before_production` | `{op: compare_time, left: [impact_analysis, approved_at], right: [started_at], cmp: lt}` | `impact_analysis.approved_at is before started_at` |  |

### DEV-0103 impact analysis, normal changes

Same as DEV-0102 impact analysis, new features, except:

| | today | sentence | notes |
| --- | --- | --- | --- |
| filter `in_scope` | `{op: equals, path: [change_type], value: normal}` | `change_type is "normal"` |  |

### DEV-0104 changes tracked

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `ticket_referenced` | `{op: all, path: [pull_requests], check: {op: matches_any, path: [ticket, key], patterns: ['^[A-Z][A-Z0-9]+-[0-9]+$']}}` | `every pull_requests.ticket.key matches "^[A-Z][A-Z0-9]+-[0-9]+$"` |  |
| `ticket_in_tracker` | `{op: all, path: [pull_requests], check: {op: present, path: [ticket, status]}}` | `every pull_requests.ticket.status exists` |  |

### DEV-0201 source managed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `approved_repository` | `{op: matches_any, path: [artifact, source, repo_url], patterns: {ref: [$$params, repository_patterns]}}` | `artifact.source.repo_url matches $params.repository_patterns` |  |
| `commit_in_repository` | `{op: non_empty_string, path: [artifact, source, commit_sha]}` | `artifact.source.commit_sha is not empty` | widens |
| `protected_branch` | `{op: equals, path: [artifact, source, branch_protected], value: true}` | `artifact.source.branch_protected is true` |  |

### DEV-0202 tamper protection

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `branch_protected` | `{op: equals, path: [source, branch_protection, enabled], value: true}` | `source.branch_protection.enabled is true` |  |
| `signed_commits_required` | `{op: equals, path: [source, branch_protection, require_signed_commits], value: true}` | `source.branch_protection.require_signed_commits is true` |  |
| `no_force_pushes` | `{op: equals, path: [source, branch_protection, allow_force_pushes], value: false}` | `source.branch_protection.allow_force_pushes is false` | `must`: `allow_force_pushes is false` reads like a description of the branch. `must be false` says it's the rule. |
| `commits_verified` | `{op: all, path: [source, commits], check: {op: equals, path: [verified], value: true}}` | `every source.commits.verified is true` |  |

### DEV-0203 secrets scanned

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `scanned` | `{op: equals, path: [artifact, attestations, secrets-scan, status], value: COMPLETE}` | `artifact.attestations.secrets-scan.status is "COMPLETE"` |  |
| `no_secrets` | `{op: equals, path: [artifact, attestations, secrets-scan, findings], value: 0}` | `artifact.attestations.secrets-scan.findings is 0` | `must`: `findings is 0` reads like a result. `findings must be 0` reads like the rule. |

### DEV-0301 build provenance

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[artifacts]` | `artifacts` |  |
| `trusted_builder` | `{op: in, path: [provenance, builder_id], values: {ref: [$$params, trusted_builders]}}` | `provenance.builder_id is in $params.trusted_builders` |  |
| `signature_verified` | `{op: equals, path: [signature, verified], value: true}` | `signature.verified is true` |  |
| `provenance_matches` | `{op: compare, left: [provenance, subject_digest], right: [fingerprint], cmp: eq}` | `provenance.subject_digest equals fingerprint` |  |

### DEV-0302 SBOM recorded

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of artifact | `[artifacts]` | `artifacts` |  |
| `standard_format` | `{op: in, path: [sbom, format], values: [spdx, cyclonedx]}` | `sbom.format is one of "spdx", "cyclonedx"` |  |
| `components_listed` | `{op: all, path: [sbom, components], check: {op: any_of, options: {identified: [{op: non_empty_string, path: [name]}, {op: non_empty_string, path: [version]}]}}}` | `every sbom.components.name is not empty`<br>`every sbom.components.version is not empty` | widens. **two lines**, see below |

### DEV-0303 configuration scanned

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `scanned` | `{op: equals, path: [iac_scan, status], value: COMPLETE}` | `iac_scan.status is "COMPLETE"` |  |
| `no_high_findings` | `{op: equals, path: [iac_scan, critical_or_high_findings], value: 0}` | `iac_scan.critical_or_high_findings is 0` | `must`: `critical_or_high_findings is 0` reads like a scan result. |

### DEV-0401 security testing

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of security scan | `[artifact, attestations, {each_as: scan, keys: {ref: [$$params, required_scans]}}]` | `artifact.attestations named by each of $params.required_scans` |  |
| `completed` | `{op: equals, path: [status], value: COMPLETE}` | `status is "COMPLETE"` |  |
| `passed` | `{op: equals, path: [is_compliant], value: true}` | `is_compliant is true` |  |
| `from` of pull request | `[artifact, attestations, pull-request, pull_requests, {each_as: pr}]` | `artifact.attestations.pull-request.pull_requests` | The name `pr` goes, as in DEV-0501. |
| `merged` | `{op: equals, path: [state], value: MERGED}` | `state is "MERGED"` |  |
| `peer_approved` | `{op: any, path: [approvers], check: {op: any_of, options: {peer: [{op: equals, path: [state], value: APPROVED}, {op: compare, left: [username], right: [$pr, author], cmp: ne}]}}}` | `for: some approvers where state is "APPROVED" as approver`<br>`assert: approver.username is not author` | `for` line |
| `from` of vulnerability | `[artifact, vulnerabilities]` | `artifact.vulnerabilities` | Rego-shaped |
| filter `open` | `{op: equals, path: [status], value: open}` | `status is "open"` |  |
| `within_sla` | `{op: compare_time, left: [remediate_by], right: [$$input, evaluated_at], cmp: gte}` | `remediate_by is on or after $input.evaluated_at` | Rego-shaped. Rego works out `remediate_by` as `first_seen` plus the params' days for the severity. Saying that in a sentence needs date arithmetic (#140) and a param key read from the subject, `$params.sla_days named by severity`. |

### DEV-0402 patches in time

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of missing patch | `[environment, missing_patches]` | `environment.missing_patches` | Rego-shaped |
| filter `critical_or_high` | `{op: in, path: [severity], values: [critical, high]}` | `severity is one of "critical", "high"` |  |
| `within_deadline` | `{op: compare_time, left: [install_by], right: [$$input, evaluated_at], cmp: gte}` | `install_by is on or after $input.evaluated_at` | Rego-shaped. Rego works out `install_by` as `released_at` plus `$params.patch_days`. |

### DEV-0403 features tested

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of test run | `[artifact, attestations, {each_as: run, keys: {ref: [$$params, required_tests]}}]` | `artifact.attestations named by each of $params.required_tests` |  |
| filter `new_development` | `{op: equals, path: [$$input, deployment, change_type], value: new_development}` | `$input.deployment.change_type is "new_development"` |  |
| `passed` | `{op: equals, path: [is_compliant], value: true}` | `is_compliant is true` |  |
| `before_production` | `{op: compare_time, left: [finished_at], right: [$$input, deployment, started_at], cmp: lt}` | `finished_at is before $input.deployment.started_at` |  |

### DEV-0404 normal changes tested

Same as DEV-0403 features tested, except:

| | today | sentence | notes |
| --- | --- | --- | --- |
| filter `new_development` | `{op: equals, path: [$$input, deployment, change_type], value: normal}` | `$input.deployment.change_type is "normal"` |  |

### DEV-0405 data migration

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `migrates_data` | `{op: equals, path: [includes_data_migration], value: true}` | `includes_data_migration is true` |  |
| `passed` | `{op: equals, path: [migration_test, is_compliant], value: true}` | `migration_test.is_compliant is true` |  |
| `complete` | `{op: compare, left: [migration_test, migrated_records], right: [migration_test, source_records], cmp: eq}` | `migration_test.migrated_records equals migration_test.source_records` |  |
| `accurate` | `{op: range, path: [migration_test, mismatched_records], min: 0, max: 0}` | `migration_test.mismatched_records is 0` | cause only. `must`: `mismatched_records is 0` reads like a test result. |
| `before_production` | `{op: compare_time, left: [migration_test, finished_at], right: [started_at], cmp: lt}` | `migration_test.finished_at is before started_at` |  |

### DEV-0406 acceptance testing, new features

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of user acceptance test | `[artifact, attestations, uat]` | `artifact.attestations.uat` | Rego-shaped. Rego adds `artifact.developers`, every author of a pull request or commit. |
| `passed` | `{op: equals, path: [result], value: passed}` | `result is "passed"` |  |
| `independent_tester` | `{op: excludes, path: [$$input, artifact, developers], value: {ref: [$$input, artifact, attestations, uat, tested_by]}}` | `tested_by is not in $input.artifact.developers` | Same passes and causes as `excludes` with a ref: missing, `null` and non-list cases fail the same way on both. |
| `documented` | `{op: non_empty_string, path: [report_url]}` | `report_url is not empty` | widens |
| `approved` | `{op: non_empty_string, path: [approved_by]}` | `approved_by is not empty` | widens |
| `approved_after_testing` | `{op: compare_time, left: [approved_at], right: [tested_at], cmp: gte}` | `approved_at is on or after tested_at` |  |
| `approved_before_production` | `{op: compare_time, left: [approved_at], right: [$$input, artifact, production_deployment, started_at], cmp: lt}` | `approved_at is before $input.artifact.production_deployment.started_at` |  |

### DEV-0407 acceptance testing, normal changes

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of user acceptance test | `[artifact, attestations, uat]` | `artifact.attestations.uat` | Rego-shaped. Rego adds `artifact.developers`, every author of a pull request or commit. |
| `passed` | `{op: equals, path: [result], value: passed}` | `result is "passed"` |  |
| `independent_tester` | `{op: all, path: [$$input, artifact, developers], check: {op: compare, left: [], right: [$$input, artifact, attestations, uat, tested_by], cmp: ne}}` | `for: every $input.artifact.developers as developer`<br>`assert: developer is not tested_by` | `for` line. Unlike DEV-0406, an empty developer list fails here, as `all` does. Today's policy reaches the tester through `$$input` because inside `all` paths start at the developer. With `for`, `tested_by` is the subject's. |
| `documented` | `{op: non_empty_string, path: [report_url]}` | `report_url is not empty` | widens |
| `approved` | `{op: non_empty_string, path: [approved_by]}` | `approved_by is not empty` | widens |
| `approved_after_testing` | `{op: compare_time, left: [approved_at], right: [tested_at], cmp: gte}` | `approved_at is on or after tested_at` |  |
| `approved_before_production` | `{op: compare_time, left: [approved_at], right: [$$input, artifact, production_deployment, started_at], cmp: lt}` | `approved_at is before $input.artifact.production_deployment.started_at` |  |

### DEV-0408 no production data in test

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of environment | `[environments]` | `environments` |  |
| filter `non_production` | `{op: in, path: [type], values: [development, test, staging]}` | `type is one of "development", "test", "staging"` |  |
| `safe_data_source` | `{op: in, path: [data_source], values: [synthetic, masked]}` | `data_source is one of "synthetic", "masked"` |  |
| `no_production_connection` | `{op: equals, path: [connects_to_production_data], value: false}` | `connects_to_production_data is false` | `must`: `connects_to_production_data is false` reads like a description of the environment. |

### DEV-0409 defects triaged, new features

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of defect | `[release, defects]` | `release.defects` |  |
| `from` of critical defect | `of: defect` | — | `of` names another subject. Nothing to write as a path. |
| filter `critical` | `{op: equals, path: [severity], value: critical}` | `severity is "critical"` |  |
| filter `unresolved` | `{op: in, path: [status], values: [open, in_progress]}` | `status is one of "open", "in_progress"` |  |
| `severity_set` | `{op: in, path: [severity], values: [critical, high, medium, low]}` | `severity is one of "critical", "high", "medium", "low"` |  |
| `assigned` | `{op: non_empty_string, path: [assignee]}` | `assignee is not empty` | widens |
| `impact_reviewed` | `{op: non_empty_string, path: [impact_review, reviewed_by]}` | `impact_review.reviewed_by is not empty` | widens |
| `reviewed_before_production` | `{op: compare_time, left: [impact_review, reviewed_at], right: [$$input, release, deployed_at], cmp: lt}` | `impact_review.reviewed_at is before $input.release.deployed_at` |  |

### DEV-0410 defects triaged, normal changes

Same as DEV-0409 defects triaged, new features.

### DEV-0501 segregation of duties

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments, {each_as: deploy}]` | `deployments` | The name `deploy` goes: the checks that used it have a `for` line, where the subject's fields are bare. |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `normal_change` | `{op: equals, path: [change_type], value: normal}` | `change_type is "normal"` |  |
| `installer_did_not_write_code` | `{op: all, path: [pull_requests], check: {op: all, path: [commits], check: {op: compare, left: [author], right: [$deploy, deployed_by], cmp: ne}}}` | `for: every pull_requests.commits as commit`<br>`assert: commit.author is not deployed_by` | `for` line |
| `peer_approved` | `{op: all, path: [pull_requests], as: pr, check: {op: any, path: [approvers], check: {op: any_of, options: {peer: [{op: equals, path: [state], value: APPROVED}, {op: compare, left: [username], right: [$pr, author], cmp: ne}]}}}}` | `for: every pull_requests as pr, some pr.approvers where state is "APPROVED" as approver`<br>`assert: approver.username is not pr.author` | `for` line. The example #174 gives for `for`. Rows stay one per deployment. |

### DEV-0502 sign-off, new features

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments, {each_as: deploy}]` | `deployments` | The name `deploy` goes: the checks that used it have a `for` line, where the subject's fields are bare. |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `new_development` | `{op: equals, path: [change_type], value: new_development}` | `change_type is "new_development"` |  |
| `business_owner_approved` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: business_owner}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "business_owner" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |
| `qa_signed_off` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: qa}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "qa" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |
| `development_signed_off` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: development}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "development" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |

### DEV-0503 sign-off, normal changes

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments, {each_as: deploy}]` | `deployments` | The name `deploy` goes: the checks that used it have a `for` line, where the subject's fields are bare. |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `normal` | `{op: equals, path: [change_type], value: normal}` | `change_type is "normal"` |  |
| `business_owner_approved` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: business_owner}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "business_owner" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |
| `qa_signed_off` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: qa}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "qa" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |
| `development_signed_off` | `{op: any, path: [approvals], check: {op: any_of, options: {before_deploy: [{op: equals, path: [role], value: development}, {op: equals, path: [decision], value: approved}, {op: compare_time, left: [approved_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some approvals where role is "development" and decision is "approved" as approval`<br>`assert: approval.approved_at is before started_at` | `for` line |

### DEV-0504 roll-back ready, new features

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `in_scope` | `{op: equals, path: [change_type], value: new_development}` | `change_type is "new_development"` |  |
| `documented` | `{op: non_empty_string, path: [rollback_plan, document_url]}` | `rollback_plan.document_url is not empty` | widens |
| `approved_before_production` | `{op: compare_time, left: [rollback_plan, approved_at], right: [started_at], cmp: lt}` | `rollback_plan.approved_at is before started_at` |  |
| `previous_version_kept` | `{op: non_empty_string, path: [previous_artifact, fingerprint]}` | `previous_artifact.fingerprint is not empty` | widens |
| `backed_up` | `{op: compare_time, left: [backup, taken_at], right: [started_at], cmp: lt}` | `backup.taken_at is before started_at` |  |

### DEV-0505 roll-back ready, normal changes

Same as DEV-0504 roll-back ready, new features, except:

| | today | sentence | notes |
| --- | --- | --- | --- |
| filter `in_scope` | `{op: equals, path: [change_type], value: normal}` | `change_type is "normal"` |  |

### DEV-0601 environments segregated

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments, {each_as: deploy}]` | `deployments` | The name `deploy` goes: the checks that used it have a `for` line, where the subject's fields are bare. |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| `promoted_through_staging` | `{op: any, path: [artifact, environment_history], check: {op: any_of, options: {staging_first: [{op: equals, path: [environment], value: staging}, {op: compare_time, left: [deployed_at], right: [$deploy, started_at], cmp: lt}]}}}` | `for: some artifact.environment_history where environment is "staging" as run`<br>`assert: run.deployed_at is before started_at` | `for` line |
| `production_identity` | `{op: in, path: [deployed_with_identity], values: {ref: [$$params, production_identities]}}` | `deployed_with_identity is in $params.production_identities` |  |

### DEV-0602 no drift

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of running artifact | `[snapshot, running]` | `snapshot.running` |  |
| `approved` | `{op: in, path: [fingerprint], values: {ref: [$$input, approved_fingerprints]}}` | `fingerprint is in $input.approved_fingerprints` |  |
| `deployed_by_pipeline` | `{op: non_empty_string, path: [deployment_id]}` | `deployment_id is not empty` | widens |

### DEV-0603 current version

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of environment | `[environments]` | `environments` |  |
| filter `user_facing` | `{op: equals, path: [user_facing], value: true}` | `user_facing is true` |  |
| `from` of release | `[latest_release]` | `latest_release` |  |
| `latest_version` | `{op: compare, left: [running_version], right: [$$input, latest_release, version], cmp: eq}` | `running_version equals $input.latest_release.version` |  |
| `release_notes` | `{op: non_empty_string, path: [release_notes_url]}` | `release_notes_url is not empty` | widens |
| `announced` | `{op: non_empty_string, path: [announcement_url]}` | `announcement_url is not empty` | widens |

### DEV-0701 emergency approved after

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `emergency` | `{op: equals, path: [change_type], value: emergency}` | `change_type is "emergency"` |  |
| `approved` | `{op: non_empty_string, path: [retro_approval, approved_by]}` | `retro_approval.approved_by is not empty` | widens |
| `independent` | `{op: compare, left: [retro_approval, approved_by], right: [deployed_by], cmp: ne}` | `retro_approval.approved_by is not deployed_by` |  |
| `after_deployment` | `{op: compare_time, left: [retro_approval, approved_at], right: [started_at], cmp: gt}` | `retro_approval.approved_at is after started_at` |  |

### DEV-0702 emergency change reviewed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `emergency` | `{op: equals, path: [change_type], value: emergency}` | `change_type is "emergency"` |  |
| `lessons_learned` | `{op: non_empty_string, path: [review, lessons_learned]}` | `review.lessons_learned is not empty` | widens |
| `incidents_have_actions` | `{op: any_of, options: {no_incidents: [{op: empty, path: [review, incidents]}], all_actioned: [{op: all, path: [review, incidents], check: {op: non_empty_string, path: [action_ticket]}}]}}` | `every review.incidents.action_ticket, if any, is not empty` | widens |
| `business_owner_approved` | `{op: equals, path: [review, approved_by_role], value: business_owner}` | `review.approved_by_role is "business_owner"` |  |
| `reviewed_after_change` | `{op: compare_time, left: [review, approved_at], right: [started_at], cmp: gt}` | `review.approved_at is after started_at` |  |

### DEV-0703 new features reviewed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `in_scope` | `{op: equals, path: [change_type], value: new_development}` | `change_type is "new_development"` |  |
| `lessons_learned` | `{op: non_empty_string, path: [review, lessons_learned]}` | `review.lessons_learned is not empty` | widens |
| `incidents_have_actions` | `{op: any_of, options: {no_incidents: [{op: empty, path: [review, incidents]}], all_actioned: [{op: all, path: [review, incidents], check: {op: non_empty_string, path: [action_ticket]}}]}}` | `every review.incidents.action_ticket, if any, is not empty` | widens |
| `business_owner_approved` | `{op: equals, path: [review, approved_by_role], value: business_owner}` | `review.approved_by_role is "business_owner"` |  |
| `reviewed_after_change` | `{op: compare_time, left: [review, approved_at], right: [started_at], cmp: gt}` | `review.approved_at is after started_at` |  |

### DEV-0704 normal changes reviewed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of production deployment | `[deployments]` | `deployments` |  |
| filter `production` | `{op: equals, path: [environment], value: prod}` | `environment is "prod"` |  |
| filter `in_scope` | `{op: equals, path: [change_type], value: normal}` | `change_type is "normal"` |  |
| `lessons_learned` | `{op: non_empty_string, path: [review, lessons_learned]}` | `review.lessons_learned is not empty` | widens |
| `incidents_have_actions` | `{op: any_of, options: {no_incidents: [{op: empty, path: [review, incidents]}], all_actioned: [{op: all, path: [review, incidents], check: {op: non_empty_string, path: [action_ticket]}}]}}` | `every review.incidents.action_ticket, if any, is not empty` | widens |
| `test_accounts_removed` | `{op: empty, path: [review, test_accounts_in_production]}` | `review.test_accounts_in_production is empty` | widens "". `must`: `test_accounts_in_production is empty` reads like a finding of the review. |
| `reviewed_after_change` | `{op: compare_time, left: [review, completed_at], right: [started_at], cmp: gt}` | `review.completed_at is after started_at` |  |

### DEV-0705 periodic security testing

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of security test | `[application, security_tests, {each_as: test, keys: {ref: [$$params, required_tests]}}]` | `application.security_tests named by each of $params.required_tests` | Rego-shaped |
| `run_recently` | `{op: compare_time, left: [due_by], right: [$$input, evaluated_at], cmp: gte}` | `due_by is on or after $input.evaluated_at` | Rego-shaped. Rego works out `due_by` as `last_run` plus `$params.interval_days` for the test, keyed by the test's name. |
| `production_like` | `{op: in, path: [environment], values: [prod, prod-equivalent]}` | `environment is one of "prod", "prod-equivalent"` |  |
| `findings_remediated` | `{op: range, path: [open_critical_or_high_findings], min: 0, max: 0}` | `open_critical_or_high_findings is 0` | cause only. `must`: `open_critical_or_high_findings is 0` reads like a report. |

### DEV-0706 root cause analysed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of vulnerability | `[vulnerabilities]` | `vulnerabilities` |  |
| filter `critical` | `{op: equals, path: [severity], value: critical}` | `severity is "critical"` |  |
| filter `fixed` | `{op: equals, path: [status], value: fixed}` | `status is "fixed"` |  |
| `analysed` | `{op: non_empty_string, path: [root_cause_analysis, document_url]}` | `root_cause_analysis.document_url is not empty` | widens |
| `fed_back` | `{op: all, path: [root_cause_analysis, actions], check: {op: non_empty_string, path: [ticket]}}` | `every root_cause_analysis.actions.ticket is not empty` | widens |

### DEV-0801 outsourced work reviewed

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of pull request | `[pull_requests]` | `pull_requests` |  |
| filter `external_author` | `{op: in, path: [author], values: {ref: [$$params, external_contributors]}}` | `author is in $params.external_contributors` |  |
| `internal_review` | `{op: any, path: [approvers], check: {op: any_of, options: {internal: [{op: equals, path: [state], value: APPROVED}, {op: in, path: [username], values: {ref: [$$params, internal_staff]}}]}}}` | `some approvers.username where state is "APPROVED" is in $params.internal_staff` |  |

### DEV-0802 security training

| | today | sentence | notes |
| --- | --- | --- | --- |
| `from` of developer | `[developers]` | `developers` | Rego-shaped |
| `training_current` | `{op: compare_time, left: [training_valid_until], right: [$$input, evaluated_at], cmp: gte}` | `training_valid_until is on or after $input.evaluated_at` | Rego-shaped. Rego builds a developer per commit author, with `training_valid_until` as completion plus `$params.training_valid_days`. |

## Tally

Every phrase, counted from the parses, twins included: 228 checks and 74 filters, 13 of the checks with a `for` line, plus 74 `from` lines. That's 390 lines in all.

| phrase | sdlc-policies | server | pr-reviewer | ergo | DEV controls | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `is` | 13 | 34 | 23 | 1 | 79 | 150 |
| `$params` | 13 | 36 |  |  | 9 | 58 |
| `is not empty` | 9 | 11 | 2 | 1 | 31 | 54 |
| `named by $params.x` | 10 | 34 |  |  |  | 44 |
| `is before` |  |  |  |  | 21 | 21 |
| `some` | 2 | 4 | 3 |  | 10 | 19 |
| `is one of` |  |  | 9 |  | 9 | 18 |
| `$input` |  |  |  |  | 17 | 17 |
| `every` | 1 | 1 | 1 |  | 12 | 15 |
| `as` |  | 1 | 1 |  | 12 | 14 |
| `equals` | 2 | 2 | 7 |  | 3 | 14 |
| `where` |  | 1 | 3 |  | 10 | 14 |
| `for` line |  | 1 | 1 |  | 11 | 13 |
| `count of` |  |  | 12 |  |  | 12 |
| `is at least` |  |  | 9 |  |  | 9 |
| `is not` |  | 2 | 2 |  | 5 | 9 |
| `and` (in `where`) |  | 1 |  |  | 6 | 7 |
| `is empty` |  | 1 | 4 |  | 1 | 6 |
| `is in` | 1 |  |  |  | 5 | 6 |
| `is on or after` |  |  |  |  | 6 | 6 |
| `named by each of` | 1 | 1 |  |  | 4 | 6 |
| `is after` |  | 1 |  |  | 4 | 5 |
| `matches` |  |  | 3 |  | 2 | 5 |
| `exists` | 2 | 1 |  |  | 1 | 4 |
| `is between` | 1 | 1 |  | 2 |  | 4 |
| `, if any,` |  |  |  |  | 3 | 3 |
| `contains` |  |  | 3 |  |  | 3 |
| `does not match` | 1 | 1 | 1 |  |  | 3 |
| `contains all of` |  |  | 1 |  | 1 | 2 |
| `equals ... within` |  |  | 2 |  |  | 2 |
| `plus` |  |  | 2 |  |  | 2 |
| `sum of` |  |  | 2 |  |  | 2 |
| `does not contain` |  |  |  | 1 |  | 1 |
| `is a` |  |  | 1 |  |  | 1 |
| `is not in` |  |  |  |  | 1 | 1 |
| `named by <name>` |  |  | 1 |  |  | 1 |

Not used anywhere: `is not one of`, `does not exist`, `contains none of`, `starts with`, `ends with`, `is at most`, `is more than`, `is less than`, `is on or before`, `is ... within`, `is not one of`, `ignoring case`, `first of`, `item 3 of` and `items[2]`.

## pr-reviewer's custom operators

| operator | uses | written as |
| --- | ---: | --- |
| `min_length` | 8 | with `min: 1`, `count of x is at least 1`. With `min: 0`, `x is a list` |
| `min_length_at` | 2 | `count of x is at least y` |
| `length_eq_difference` | 1 | `count of x plus z is y`, moving the minus across |
| `count_where_eq_sum` | 2 | `count of x where field is "v" is a plus b` |
| `sum_eq` | 2 | `sum of x.usd where stage is "v" is total within 0.000001` |
| `contains_all` | 1 | `x contains all of y` |
| `keys_match` | 1 | nothing: it stays custom, see below |

Six of the seven go, as #173 found for the five numeric ones. The sentences also drop the `expression` and `inputs` each custom check had to carry.

## Misfits

Checks that don't fit on one line, or fit only by changing what passes. This is the grammar's edge.

- **SDLC-CTRL-0007 code review `peer_approval`** (sdlc-policies, misfit). Three conditions on the same approver: approved, not the author, and after every commit. A `for` line gets the two quantifiers, `for: some approvers where state is "APPROVED" as approver, every commits as commit` with `assert: approver.timestamp is after commit.timestamp`, but that leaves "not the author" with nowhere to go: a `where` reads the approver, so it can't reach the pull request's `author`, and there's one `assert`. Smallest addition: a list of assertions under one `for`, all holding for the same items, which is what today's `any_of` option with three checks means: `for: some approvers where state is "APPROVED" as approver, every commits as commit`, then `approver.username is not author` and `approver.timestamp is after commit.timestamp` under `assert`. The second also turns today's text comparison of timestamps into a time comparison, which fails a timestamp that isn't RFC 3339.
- **demo SDLC-CTRL-0008 quality assurance `test suite`** (server, misfit). Rego writes one requirement per suite name. The sentence form can't loop over names to make requirements. Smallest addition: none, because sdlc-policies 0008 already says the same with `at each of`, one requirement whose subjects are the suites. This one should move to that shape.
- **review-controls `dispatched_personas_recorded`** (pr-reviewer, misfit). Each dispatched persona's name is a key to look up in another object, so the key comes from the item being checked. Smallest addition: none any more: #174 has `named by persona`, a key read from a name the `for` line gave. Today a ref can't start with a name, so until ergo has it this stays custom.
- **DEV-0302 SBOM recorded `components_listed`** (DEV controls, two lines). Two assertions about each component. Two checks pass and fail together exactly as the one `all` does, but the report has two rows.

Fits on one line, but changes what passes:

- **`is not empty` widens `non_empty_string`** (52 checks, in every source). It passes a non-empty list too. No input in these repos has a list where a name or URL should be, but strictly that's a change. The exact fix is a phrase per type, `is a non-empty string`, which reads worse in all 52.
- **`is empty` widens `empty` and `equals []`** (6 checks: npm-bump, pr-reviewer's `ran_none` filters, DEV-0704). It passes `""` too, which a "no test accounts left" check shouldn't. The fix is to make `is empty` mean the empty list only, at the cost of `is empty` and `is not empty` not being opposites on strings.
- **Timestamps compared as text** (sdlc-policies 0007 and server 0007 `peer_approval`). Today's `compare` with `gt` orders them as text. `is after` reads them as times and fails one that isn't RFC 3339. That's a fix, but it is a change.
- **Custom operators that skipped items** (pr-reviewer `first_pass_findings_recorded`, `second_pass_findings_recorded`, `verifier_cost_matches_its_stage`). A finding with no `source`, or a stage row with no `stage`, was skipped and could pass. The sentence fails it as `absent`, as #173 meant.
- **Rego's `!=` and `!= ""`** (server 0010 `approved_by_non_author`, require-artifact-provenance `fingerprint`). Rego passes values of another type, the sentence fails them as `unusable`.
- **Rego defaults** (37 paths in the server demos and sdlc-policies 0004). A Rego variable like `artifact_name` with a default of `"artifact"` becomes `$params.artifact_name`, which fails without the param. sdlc-policies already made that choice.

Fits, but only after Rego reshapes the input (24 entries): sdlc-policies 0004 builds every subject from attested text, the server demos copy fields between objects, and DEV-0401, 0402, 0705 and 0802 compute deadlines with date arithmetic (#140). Sentences don't change that. A deadline as a sentence would need date arithmetic and a param key read from the subject, `$params.sla_days at severity`.

## `is` or `must`

The corpus is written with `is`. 74 filters and 21 `where` conditions are conditions, not rules, so they need `is` whatever checks use: `where state is "APPROVED"` can't be `where state must be "APPROVED"`. With `must` in checks, the grammar has two verbs for the same phrases, and the same leaf reads differently in a filter and in a check. 228 checks could take `must`. Most read the same either way, like `signature.verified is true` or `state is "MERGED"`. The ones where `must` reads better all say that something bad is absent: a zero, a `false` or an empty list. With `is`, they read like a result rather than a rule:

- flow-templates npm-bump `no_open_bump_pr`: `open_bump_prs is empty` reads like a status.
- review-controls `findings_complete`: `truncated is false` reads like a status.
- DEV-0202 tamper protection `no_force_pushes`: `allow_force_pushes is false` reads like a description of the branch. `must be false` says it's the rule.
- DEV-0203 secrets scanned `no_secrets`: `findings is 0` reads like a result. `findings must be 0` reads like the rule.
- DEV-0303 configuration scanned `no_high_findings`: `critical_or_high_findings is 0` reads like a scan result.
- DEV-0405 data migration `accurate`: `mismatched_records is 0` reads like a test result.
- DEV-0408 no production data in test `no_production_connection`: `connects_to_production_data is false` reads like a description of the environment.
- DEV-0704 normal changes reviewed `test_accounts_removed`: `test_accounts_in_production is empty` reads like a finding of the review.
- DEV-0705 periodic security testing `findings_remediated`: `open_critical_or_high_findings is 0` reads like a report.

## Open questions

What the corpus says about each decision the brief left open.

**`is` or `must`.** See above. 74 filters and 21 `where` conditions need `is`. 9 checks read better with `must`, and all of them say something bad is absent. The others read the same either way. Inside an `assert:` key, even those 9 are clear, so the case for `must` is a sentence quoted on its own, in a report or a markdown policy (#18).

**Looking up by key.** #174 settled it as `named by`, with brackets as the other spelling. It appears 44 times, all in sdlc-policies and the server demos, and 32 of those have more path after the key, like `artifacts_statuses named by $params.artifact_name.attestations_statuses`. Every reference after `named by` in the corpus is `$params` plus one key, or a name from a `for` line, so the issue's rule takes nothing away. Whether the report prints the word form or brackets waits for the readability test.

**`where` in `from` or `applies_to`.** 74 filters on 32 policies, and every one sits on the subject or in a requirement's scope. No policy filters inside `from`, and nothing in the corpus needs `from: deployments where environment is "prod"` that `applies_to` can't say. The grammar can say either, so it's #113's call.

**Two quantifiers and a subject with a parent.** The `for` line #174 added while this was written does the job Tore's subject move for DEV-0501 was for. 13 checks use one: DEV-0501 `peer_approved`, every comparison of an item with its subject (DEV-0401, 0407, 0502, 0503, 0601 and server 0010), and pr-reviewer `dispatched_personas_recorded`. None of them needs a subject that starts at another subject, so #52 isn't on this path any more. What `for` can't do is hold two assertions about the same items, which is sdlc-policies 0007's misfit.

**One-line `every` and `some`, or always `for`.** #174 asks whether the one-line form earns its second scoping rule. 20 checks use a one-line `every` or `some` (11 `every`, 9 `some`) and 13 need a `for` line, so most walks don't need one. 18 of the 20 read nothing after the path but a value or `$params`, like `every commits.verified is true` or `some licences is in $params.allowed_licenses`, so for them the second rule never comes up. It only matters for a bare field read on the item, which happens in 2: DEV-0801's `where state is "APPROVED"`, and server 0007, whose `where` and argument read fields Rego copied onto each approver. A one-line form without `where` and without bare fields in its argument would keep the 18 on one line and move those 2 to `for`. But `count of ... where` and `sum of ... where` (3 checks, all pr-reviewer) read the item in their `where` whatever happens, because a `for` line can't produce a number, so the item-scoped `where` stays in the grammar either way.

**Time phrases.** Settled in #174 as `is before`, `is after`, `is on or after` and `is on or before`. The corpus has 32 time comparisons: 21 `is before`, 5 `is after` and 6 `is on or after`, which were `is not before` before. 4 of the `is on or after` compare a deadline Rego worked out with `$input.evaluated_at` (#140). Two checks compare timestamps as text today, and the time phrases fail a timestamp that isn't RFC 3339.
