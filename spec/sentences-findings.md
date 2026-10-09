# Sentence corpus and grammar: findings

This file goes with [`sentences-corpus.md`](sentences-corpus.md) and [`sentences.md`](sentences.md). Both now follow [#174](https://github.com/kosli-dev/ergo/issues/174) as its body stood on 9 October 2026 at 11:43 UTC. The issue had changed in sixteen places since the first version of these files. Step 2 of the plan, the readability test with someone who hasn't seen ergo, still isn't done.

## What changed

Each numbered change from the issue is its own commit on this branch.

1. **Right side.** A quoted string on the right side is text. A grammar word is never a field there, and a field with such a name is written `.empty`, not `."empty"`. The corpus had no such field, so only the draft changed.
2. **No Cucumber Expressions.** The draft lists each phrase as a plain pattern, one line per form, like `<path> is not empty`, with a table of what each gap holds.
3. **`assert` as a list.** sdlc-policies 0007 `peer_approval` is no longer a misfit. It has a `for` line with two items and two assertions. DEV-0302 is now one check with two assertions instead of two checks, so it keeps its one row.
4. **Bare names in a one-line `every` or `some` are the item's.** The draft already said so. The corpus agrees: its only one-line check with a bare field on the right is server 0007, where Rego copied the fields onto each approver.
5. **Time phrases.** The six `is not before` became `is on or after`. Nothing used `is not after`.
6. **`named by`.** 37 lookups by a param, 6 by `named by each of`, and 1 by a name (`persona_blob_shas named by persona`). There were 44 lookups by a param before item 11 turned some of them into chains.
7. **`is empty` on strings and lists.** None of the 52 `is not empty` checks needs `is a non-empty string`. The 6 `is empty` checks pass `""` too. To keep today's meaning, each would need `is a list` beside it. The corpus marks them and leaves them.
8. **`is` everywhere.** The `is` or `must` section is one line now.
9. **Printing strings.** Single quotes when a string holds a backslash and no single quote. Every line in the corpus now prints back exactly as written.
12. **Hyphens.** The corpus already wrote `secrets-scan` bare. The draft had also allowed `$` after the first character, as the report's path names do today. It now follows the issue: letters, digits, `_` and `-`.
13. **`contains all of` and `contains none of`.** The corpus already used `contains all of`. `contains "a", "b"` on its own doesn't parse.
14. **`every` over strings.** DEV-0406 now reads `$input.artifact.developers does not contain tested_by`, as the issue and Tore write it. DEV-0407 keeps a `for` line, because `does not contain` would pass an empty developer list, which fails today.
15. **Narrowing.** DEV-0409 and DEV-0410's `critical defect` is `from: defect where severity is "critical" and status is one of "open", "in_progress"`.
16. **`equals` before a field.** 16 lines changed from `is <field>` to `equals <field>`. The two that compare `base_ref` with a param now fail a value of another type as `unusable`, not `value`. The same values pass.
10. **`from` with `where`.** The 74 filters became 80 `where` conditions on 49 `from` lines. 15 of those lines are new, counting the server's copy of sdlc-policies 0004: in pr-reviewer and sdlc-policies 0004, requirements that shared a subject with different filters now each have their own. The `$applies` text for each is [below](#what-applies-prints).
11. **Chains.** See [Chains](#chains).

## Parse counts

The tokenizer was updated for every rule above and run over the whole corpus: 337 lines, made of 231 assertions, 14 `for` lines and 92 `from` lines. All 337 parse. With the issue's rules, none parses more than one way. Without them, 196 do:

| what reads two ways | lines | rule that removes it |
| --- | ---: | --- |
| `is "prod"`: text, or a quoted key | 84 | a quoted string on the right side is text |
| `is not empty`: a phrase, or `is not` and a field called `empty` | 65 | grammar words are never a field on the right side |
| `is true`: a value, or a field called `true` | 46 | the same two rules |
| `named by $params.artifact_name.attestations_statuses`: where does the reference end? | 24 | the reference after `named by` is `$params` or `$input` plus one key |

Some lines have two causes. Of 15 made-up lines, `count of x where n is m plus k is t` reads three ways, which is why `plus` can't follow `where`. The `and` between assertions never clashes with the `and` of `where` or of `between`.

## Chains

6 `from` lines chain, twins included:

- 4 descend from an `artifact` subject instead of repeating its lookup: sdlc-policies 0007's pull requests and 0008's test suites, the server's copy of 0008, and server 0010's approval attestation.
- 2 narrow: DEV-0409's `critical defect` and its twin in DEV-0410.

No `for` line existed only to reach a parent. Each one compares an item with its subject, or walks two lists. Server 0010's `for` line stays after the chain, but its assertion shrinks from a path with two lookups to `approver is not author`.

Depth: no chain is more than two subjects deep. The deepest check is sdlc-policies 0007 `peer_approval`. It has two chained subjects, `artifact` then `pull request`, then two `for` items, `approvers` and `commits`. That's four levels and three list walks. Today the same check walks the same three lists, one in `from` and two in the check. So the ceiling the spec has to name can stay at three list walks, if it counts list walks rather than subjects.

## What `$applies` prints

The `$applies` row's `expression` is the `where` conditions as written, joined with ` and `. Its `inputs` hold each path they read. `…` stands for `compliance_status.attestations_statuses.`. Twins are left out.

| repo | policy | subject | `$applies` |
| --- | --- | --- | --- |
| sdlc-policies | SDLC-CTRL-0004 dependencies | lockfile | `status exists and status is "COMPLETE"` |
| sdlc-policies | SDLC-CTRL-0004 dependencies | SBOM package | `lock_release exists` |
| sdlc-policies | SDLC-CTRL-0004 dependencies | non-exempt SBOM package | `exempt is false` |
| pr-reviewer | review-controls | confirmed finding | `decision is "CONFIRMED"` |
| pr-reviewer | review-controls | review round (resolution_per_disagreement) | `…verdict.attestation_data.moderator_status is "resolved"` |
| pr-reviewer | review-controls | review round (moderator_failure_recorded) | `…verdict.attestation_data.moderator_status does not match "^(resolved\|no_disagreements\|single_reviewer\|disabled)$"` |
| pr-reviewer | review-controls | review round (coverage_gap_rereviewed) | `…coverage-verification.attestation_data.before_second_pass.uncovered is a list and …coverage-verification.attestation_data.before_second_pass.uncovered is not empty and …coverage-verification.attestation_data.before_second_pass.cost_capped is false` |
| pr-reviewer | review-controls | review round (coverage_gap_cost_capped) | `…coverage-verification.attestation_data.before_second_pass.uncovered is a list and …coverage-verification.attestation_data.before_second_pass.uncovered is not empty and …coverage-verification.attestation_data.before_second_pass.cost_capped is true` |
| pr-reviewer | review-controls | review round (second_pass_findings_recorded) | `…second-pass.attestation_data.triggered is true` |
| pr-reviewer | review-controls | finding (posted_finding) | `source is not "empty_file"` |
| pr-reviewer | review-controls | review round (claude_ran_dispatched) | `…claude-review.attestation_data.personas_ran is a list and …claude-review.attestation_data.personas_ran is not empty` |
| pr-reviewer | review-controls | review round (gemini_ran_dispatched) | `…gemini-review.attestation_data.personas_ran is a list and …gemini-review.attestation_data.personas_ran is not empty` |
| pr-reviewer | review-controls | review round (claude_only_degraded) | `…claude-review.attestation_data.degraded is true and …claude-review.attestation_data.personas_ran is empty` |
| pr-reviewer | review-controls | review round (gemini_only_degraded) | `…gemini-review.attestation_data.degraded is true and …gemini-review.attestation_data.personas_ran is empty` |
| pr-reviewer | review-controls | review round (both_models_degraded) | `…claude-review.attestation_data.degraded is true and …gemini-review.attestation_data.degraded is true and …claude-review.attestation_data.personas_ran is empty and …gemini-review.attestation_data.personas_ran is empty` |
| pr-reviewer | review-controls | review round (claude_persona_failed) | `…claude-review.attestation_data.degraded is true and …claude-review.attestation_data.personas_ran is a list and …claude-review.attestation_data.personas_ran is not empty` |
| pr-reviewer | review-controls | review round (gemini_persona_failed) | `…gemini-review.attestation_data.degraded is true and …gemini-review.attestation_data.personas_ran is a list and …gemini-review.attestation_data.personas_ran is not empty` |
| ergo | README | deployment | `environment is "prod"` |
| DEV controls | DEV-0102 impact analysis, new features | production deployment | `environment is "prod" and change_type is "new_development"` |
| DEV controls | DEV-0104 changes tracked | production deployment | `environment is "prod"` |
| DEV controls | DEV-0201 source managed | production deployment | `environment is "prod"` |
| DEV controls | DEV-0202 tamper protection | production deployment | `environment is "prod"` |
| DEV controls | DEV-0203 secrets scanned | production deployment | `environment is "prod"` |
| DEV controls | DEV-0303 configuration scanned | production deployment | `environment is "prod"` |
| DEV controls | DEV-0401 security testing | vulnerability | `status is "open"` |
| DEV controls | DEV-0402 patches in time | missing patch | `severity is one of "critical", "high"` |
| DEV controls | DEV-0403 features tested | test run | `$input.deployment.change_type is "new_development"` |
| DEV controls | DEV-0405 data migration | production deployment | `environment is "prod" and includes_data_migration is true` |
| DEV controls | DEV-0408 no production data in test | environment | `type is one of "development", "test", "staging"` |
| DEV controls | DEV-0409 defects triaged, new features | critical defect | `severity is "critical" and status is one of "open", "in_progress"` |
| DEV controls | DEV-0501 segregation of duties | production deployment | `environment is "prod" and change_type is "normal"` |
| DEV controls | DEV-0502 sign-off, new features | production deployment | `environment is "prod" and change_type is "new_development"` |
| DEV controls | DEV-0503 sign-off, normal changes | production deployment | `environment is "prod" and change_type is "normal"` |
| DEV controls | DEV-0504 roll-back ready, new features | production deployment | `environment is "prod" and change_type is "new_development"` |
| DEV controls | DEV-0601 environments segregated | production deployment | `environment is "prod"` |
| DEV controls | DEV-0603 current version | environment | `user_facing is true` |
| DEV controls | DEV-0701 emergency approved after | production deployment | `environment is "prod" and change_type is "emergency"` |
| DEV controls | DEV-0702 emergency change reviewed | production deployment | `environment is "prod" and change_type is "emergency"` |
| DEV controls | DEV-0703 new features reviewed | production deployment | `environment is "prod" and change_type is "new_development"` |
| DEV controls | DEV-0704 normal changes reviewed | production deployment | `environment is "prod" and change_type is "normal"` |
| DEV controls | DEV-0706 root cause analysed | vulnerability | `severity is "critical" and status is "fixed"` |
| DEV controls | DEV-0801 outsourced work reviewed | pull request | `author is in $params.external_contributors` |

## Where Tore's rewrite and the corpus differ

Tore's rewrite of the 36 DEV controls is on the `174-feedback` branch of kosli-playground/dev-process-controls, in `issue-174-findings`. The issue decides each difference:

- **Lists of values.** Tore writes `is in "spdx", "cyclonedx"`. The corpus writes `is one of`, as the issue's Literal or field section does, and keeps `is in` for a list read from a path. The issue itself uses both, see below.
- **Keys from a param.** Tore writes `artifact.attestations at $params.required_scans as scan`. The corpus writes `named by each of $params.required_scans`, as the issue now does (DEV-0401, 0403, 0404, 0705).
- **Time.** Tore's `is not before` is `is on or after` in the corpus (DEV-0401, 0402, 0406, 0407, 0705, 0802).
- **Names.** Tore writes `$deploy.started_at` and `$pr.author` in one-line checks, with `from: deployments as deploy`. The issue has no `$` names and names things on a `for` line, so DEV-0401, 0501, 0502, 0503 and 0601 have `for` lines in the corpus.
- **DEV-0501 `peer_approved`.** Tore makes the pull request a subject, with `from: $deploy.pull_requests as pr`. The corpus uses the issue's own example, a `for` line with two items, which keeps one row per deployment.
- **DEV-0407.** Tore writes `every $input.artifact.developers is not tested_by`. The issue rules that out, and its suggestion `does not contain` passes an empty developer list. The corpus keeps today's meaning with a `for` line.
- **DEV-0302.** Tore writes two checks. The corpus has one check with two assertions, which the issue now allows.
- **Filters.** Tore keeps `applies_to` and `of`. The corpus puts the conditions in `from`, and DEV-0409's `critical defect` narrows `defect`.

The rest of Tore's sentences match the corpus word for word, `equals` before a field included.

## Where the corpus and #174 disagree

- **`is in` with values.** The Subjects section writes `status is in "open", "in_progress"`. The Literal or field section writes `is one of "staging", "prod"`, and keeps `is in` for a path. The corpus follows Literal or field.
- **`is` before a field.** The Report section prints `equals` when the right side is a field. But the issue's own examples write `sum of stages.usd where kind is "model" is total_usd within 0.01` in The proposal and `... is total_usd within` under Errors. Printed, those are `equals total_usd within 0.01`.
- **`and` at the top of a sentence.** The grammar stays flat says `and` never joins `where` to the assertion and never sits at the top of a sentence. Two quantifiers then allows one `assert` line with `and` between assertions. The draft says `and` joins `where` conditions and whole assertions, nothing else.
- **A bare name after that `and`.** In `every items.price where kind is "a" is at least 2 and owner is "x"`, the issue doesn't say whether `owner` is the item's, as in the `where`, or the subject's. The draft reads it as the subject's, because the `every` belongs to the first assertion only.
- **`count of` in `from`.** A `from` takes the shape of a `for` item, whose `where` holds a path and a phrase. Six pr-reviewer filters are `count of x is at least 1`. Each became `x is a list and x is not empty`, which keeps the meaning but isn't what the issue shows.
- **What `$applies` shows.** The issue says the row "says which condition failed, like `change_type is \"bug_fix\"`". That reads like the value that was read, not a condition the policy wrote. The draft prints the conditions as written, with values in `inputs`, as today. The issue should say which one it means.
- **The order of conditions.** Today filters are named, so `$applies` lists them sorted by name and the report is the same whatever order they were written in. A `where` is a sentence, so it keeps the order written, and two policies that differ only in that order give different reports. Either the printed form sorts conditions, or the spec accepts this.
- **A subject's name or an input field.** sdlc-policies 0004 has subjects `artifact` and `lockfile` whose `from` is `artifact` and `lockfile`, input fields with the same names. Chaining by name could read those as a subject starting from itself. The draft reads a subject's own name in its own `from` as the input field.
- **Subject names with spaces.** 19 subject names in the corpus have a space, like `production deployment`, so they can't start a chain without quotes. The issue's example uses `deployment`. No chain in the corpus needs quotes.
- **Bare keys and the report.** The issue allows letters, digits, `_` and `-` in a bare key. Today's report also allows `$` after the first character (`syntax.md`, [name.keys]). The two should agree, or a path from a report row may not paste back into a policy.
- **`is not` before a field.** The issue says how `is` and `equals` print, but not how the negated form prints before a field. The draft prints `is not` either way.

## Misfits left

One: server demo 0008 builds one requirement per suite in Rego. sdlc-policies 0008 already says the same thing with `named by each of`.

pr-reviewer's `keys_match` is now a sentence, `persona_blob_shas named by persona`, but ergo can't run it until a ref can start with a name, so the policy keeps its custom operator until then. Its other six custom operators become sentences that run today.

## Changes in what passes

The corpus marks each one:

- `is not empty` passes a non-empty list where `non_empty_string` fails: 52 checks.
- `is empty` passes `""` where `empty` and `equals []` fail: 6 checks.
- Timestamps compared as text today fail when they aren't RFC 3339: sdlc-policies and server 0007 `peer_approval`.
- Three pr-reviewer custom operators skipped items with a missing field. The sentences fail them as `absent`.
- Rego's `!=` and `!= ""` pass values of another type, and the sentences don't: server 0010, require-artifact-provenance.
- 34 paths lose a Rego default, like `artifact_name` defaulting to `"artifact"`.
- Server 0010 now has one row per approval attestation instead of per artifact. It allows the same inputs.

Cause only, with the same values passing: `range` from 0 to 0 as `is 0` (2 checks), and `base_ref equals $params.protected_branch` (2 checks).

## Rego spike

Not run again: the grammar's size didn't change much. The numbers from the first run still stand: sentences parsed once per check cost what today's objects cost, and parsing per subject took 739 MB of Wasm memory on 3,000 subjects.
