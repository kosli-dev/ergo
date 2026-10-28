# Sentence corpus and grammar: findings

This file goes with [`sentences-corpus.md`](sentences-corpus.md) and [`syntax.md`](syntax.md). Both now follow [#174](https://github.com/kosli-dev/ergo/issues/174) as its body stood on 9 October 2026 at 15:22 UTC. This is the fourth pass. The third pass left one disagreement with the issue and filled three gaps. The issue now decides them, and this pass applies that. Step 2 of the plan, the readability test with someone who hasn't seen Ergo, still isn't done.

## What changed in this pass

Each numbered item is its own commit on this branch.

1. **`and` means what a new line under `assert` means.** Each assertion starts from the subject, or from the `for` names, whether it's on its own line or after an `and`. A one-line `every` or `some` ends at the `and`, so in `every items.price is at least 2 and owner is "x"`, `owner` is the subject's. This reverses item 4 of the third pass. Any assertion can now start with a quantifier, so `state is "MERGED" and every commits.verified is true` is two assertions on one line, and `and` after `count of` or `sum of` needs no rule of its own. The report shows the list form whichever was written, and its joined `expression` is always a sentence the policy could have written. No line in the corpus joins assertions with `and`, so no policy changes.
2. **`count of` and `sum of` are list walks**, in a `whose` too. The draft already said so. It now also gives the issue's example: `for: every pull_requests as pr` with `assert: count of pr.reviews is at least 2` walks two lists.
3. **The one-line `subjects` is gone.** The map is the only spelling, and a simple subject is a name with nothing under it. The corpus note on sdlc-policies 0004 and the grammar no longer mention it. What the third pass found still holds: a subject with no `from` reads the input field of its name, and every subject in the corpus has an `id`.

## What changed in the third pass

1. **`is one of` and `is in` mean the same.** Either takes written values or a path. The report prints `is one of` before written values and `is in` before a path. Nothing in the corpus needed to change. Tore's `is in "spdx", "cyclonedx"` now parses, and prints as `is one of`.
2. **`equals` before a field.** The corpus had no `is <field>` left. Five examples in the draft and three in the corpus's table of custom operators did, like `sum of stages.usd whose kind is "model" is total_usd within 0.01`. They now say `equals`.
3. **`and` does two jobs.** The flat section says `and` joins the conditions of a `whose` and joins whole assertions, nothing else.
4. **Assertions joined with `and` after a one-line `every` or `some` were about the item.** Reversed in this pass, see item 1 above.
5. **`count of` and `sum of` in a `whose`.** The six pr-reviewer filters are `whose count of x is at least 1` again. One thing changes: a value that isn't a list now fails the requirement as `unusable`, where today's custom `min_length` rules the subject out. The corpus marks the six as narrowing.
6. **`$applies`.** It prints the conditions as written, with the values read in `inputs`. The table [below](#what-applies-prints) is regenerated from the corpus, and the six filters from item 5 now print as `count of`.
7. **Order as written.** `whose` conditions and joined assertions print in the order the author wrote them, and `inputs` stay sorted by name. The draft says that the byte-for-byte rule is for the same policy run again, not for two policies that mean the same.
8. **Subjects.** A subject's own name in its own `from` is the input field, and any other subject's name starts a chain. Run over every `from` line, those two rules find exactly the six chains the corpus marks. sdlc-policies 0004's `artifact` now has no `from`, and the corpus shows the policy's whole `subjects` section. Every subject in the corpus has an `id`.
9. **Quoted subject names.** The draft gives the rule, `from: '"production deployment".pull_requests'`, and the tokenizer reads it one way. No policy needs it.
10. **Bare keys.** The draft now quotes any key with a `$` in it, and says the report prints keys by the same rule. When this is built, `syntax.md` ([name.keys]) needs the same change, because today it allows `$` after the first character.
11. **`does not equal` before a field.** Nine lines changed from `is not <field>` to `does not equal <field>`, twins included, like `approver.username does not equal author`. `is not` stays before a value.
12. **DEV-0407.** It keeps its `for` line. Its note and the draft now say why: `does not contain` passes an empty list, and `every` fails one.
13. **Depth.** The draft names three list walks as the limit, counted as walks, not subjects, next to the `for` limit. sdlc-policies 0007's peer approval reaches it. The draft also counts a `count of` or `sum of` as a walk, including one in a `whose`, since it walks a list.

## Parse counts

The tokenizer was updated for item 1 of this pass, and for items 1, 3, 5, 8, 9, 10 and 11 of the third, and run over the whole corpus: 335 lines, made of 231 assertions, 14 `for` lines and 90 `from` lines. That's two `from` lines fewer than before, because sdlc-policies 0004's `artifact` and its server copy have none now. All 335 parse. With the issue's rules, **no line reads two ways**, and every line, `from` lines included, prints back exactly as written. Without those rules, 194 lines read more than one way:

| what reads two ways                                                                   | lines | rule that removes it                                                 |
| ------------------------------------------------------------------------------------- | ----: | -------------------------------------------------------------------- |
| `is "prod"`: text, or a quoted key                                                    | 84    | a quoted string on the right side is text                            |
| `is not empty`: a phrase, or `is not` and a field called `empty`                      | 59    | grammar words are never a field on the right side                    |
| `is true`: a value, or a field called `true`                                          | 50    | the same two rules                                                   |
| `named by $params.artifact_name.attestations_statuses`: where does the reference end? | 24    | the reference after `named by` is `$params` or `$input` plus one key |

Some lines have two causes. The grammar-word row went down by 6 and the `true` row up by 4, because the six pr-reviewer filters no longer say `is a list and ... is not empty`.

The counts are the same as in the third pass, because no line in the corpus joins assertions with `and`, so item 1 changes no line's reading.

28 made-up lines test what the corpus doesn't reach. The ones this pass changed: `state is "MERGED" and every commits.verified is true` now reads one way, as two assertions, and so does `every items.price whose kind is "a" is at least 2 and some items.owner is "x"`, which is new. `every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"` still reads one way, now with `owner` on the subject. The others: `count of` and `sum of` in a `whose` read one way, `whose count of x is empty` reads no way, and so does the bare key `foo$bar`. `is in` with values prints `is one of`, `is one of` with a path prints `is in`, `is not author` prints `does not equal author`, and `does not equal "prod"` prints `is not "prod"`. `"production deployment".pull_requests` reads one way.

## Chains

Unchanged: 6 `from` lines chain, twins included. 4 descend from an `artifact` subject: sdlc-policies 0007's pull requests and 0008's test suites, the server's copy of 0008, and server 0010's approval attestation. 2 narrow, DEV-0409's `critical defect` and its twin in DEV-0410. No chain is more than two subjects deep, and no check walks more than three lists.

## What `$applies` prints

The `$applies` row's `expression` is the `whose` conditions as written, joined with ` and `, in the order written. Its `inputs` hold each path they read. `…` stands for `compliance_status.attestations_statuses.`. Twins are left out.

| repo          | policy                                 | subject                                      | `$applies`                                                                                                                                                                                                                  |
| ------------- | -------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| sdlc-policies | SDLC-CTRL-0004 dependencies            | lockfile                                     | `status exists and status is "COMPLETE"`                                                                                                                                                                                    |
| sdlc-policies | SDLC-CTRL-0004 dependencies            | SBOM package                                 | `lock_release exists`                                                                                                                                                                                                       |
| sdlc-policies | SDLC-CTRL-0004 dependencies            | non-exempt SBOM package                      | `exempt is false`                                                                                                                                                                                                           |
| pr-reviewer   | review-controls                        | confirmed finding                            | `decision is "CONFIRMED"`                                                                                                                                                                                                   |
| pr-reviewer   | review-controls                        | review round (resolution_per_disagreement)   | `…verdict.attestation_data.moderator_status is "resolved"`                                                                                                                                                                  |
| pr-reviewer   | review-controls                        | review round (moderator_failure_recorded)    | `…verdict.attestation_data.moderator_status does not match "^(resolved\|no_disagreements\|single_reviewer\|disabled)$"`                                                                                                     |
| pr-reviewer   | review-controls                        | review round (coverage_gap_rereviewed)       | `count of …coverage-verification.attestation_data.before_second_pass.uncovered is at least 1 and …coverage-verification.attestation_data.before_second_pass.cost_capped is false`                                           |
| pr-reviewer   | review-controls                        | review round (coverage_gap_cost_capped)      | `count of …coverage-verification.attestation_data.before_second_pass.uncovered is at least 1 and …coverage-verification.attestation_data.before_second_pass.cost_capped is true`                                            |
| pr-reviewer   | review-controls                        | review round (second_pass_findings_recorded) | `…second-pass.attestation_data.triggered is true`                                                                                                                                                                           |
| pr-reviewer   | review-controls                        | finding (posted_finding)                     | `source is not "empty_file"`                                                                                                                                                                                                |
| pr-reviewer   | review-controls                        | review round (claude_ran_dispatched)         | `count of …claude-review.attestation_data.personas_ran is at least 1`                                                                                                                                                       |
| pr-reviewer   | review-controls                        | review round (gemini_ran_dispatched)         | `count of …gemini-review.attestation_data.personas_ran is at least 1`                                                                                                                                                       |
| pr-reviewer   | review-controls                        | review round (claude_only_degraded)          | `…claude-review.attestation_data.degraded is true and …claude-review.attestation_data.personas_ran is empty`                                                                                                                |
| pr-reviewer   | review-controls                        | review round (gemini_only_degraded)          | `…gemini-review.attestation_data.degraded is true and …gemini-review.attestation_data.personas_ran is empty`                                                                                                                |
| pr-reviewer   | review-controls                        | review round (both_models_degraded)          | `…claude-review.attestation_data.degraded is true and …gemini-review.attestation_data.degraded is true and …claude-review.attestation_data.personas_ran is empty and …gemini-review.attestation_data.personas_ran is empty` |
| pr-reviewer   | review-controls                        | review round (claude_persona_failed)         | `…claude-review.attestation_data.degraded is true and count of …claude-review.attestation_data.personas_ran is at least 1`                                                                                                  |
| pr-reviewer   | review-controls                        | review round (gemini_persona_failed)         | `…gemini-review.attestation_data.degraded is true and count of …gemini-review.attestation_data.personas_ran is at least 1`                                                                                                  |
| Ergo          | README                                 | deployment                                   | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0102 impact analysis, new features | production deployment                        | `environment is "prod" and change_type is "new_development"`                                                                                                                                                                |
| DEV controls  | DEV-0104 changes tracked               | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0201 source managed                | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0202 tamper protection             | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0203 secrets scanned               | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0303 configuration scanned         | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0401 security testing              | vulnerability                                | `status is "open"`                                                                                                                                                                                                          |
| DEV controls  | DEV-0402 patches in time               | missing patch                                | `severity is one of "critical", "high"`                                                                                                                                                                                     |
| DEV controls  | DEV-0403 features tested               | test run                                     | `$input.deployment.change_type is "new_development"`                                                                                                                                                                        |
| DEV controls  | DEV-0405 data migration                | production deployment                        | `environment is "prod" and includes_data_migration is true`                                                                                                                                                                 |
| DEV controls  | DEV-0408 no production data in test    | environment                                  | `type is one of "development", "test", "staging"`                                                                                                                                                                           |
| DEV controls  | DEV-0409 defects triaged, new features | critical defect                              | `severity is "critical" and status is one of "open", "in_progress"`                                                                                                                                                         |
| DEV controls  | DEV-0501 segregation of duties         | production deployment                        | `environment is "prod" and change_type is "normal"`                                                                                                                                                                         |
| DEV controls  | DEV-0502 sign-off, new features        | production deployment                        | `environment is "prod" and change_type is "new_development"`                                                                                                                                                                |
| DEV controls  | DEV-0503 sign-off, normal changes      | production deployment                        | `environment is "prod" and change_type is "normal"`                                                                                                                                                                         |
| DEV controls  | DEV-0504 roll-back ready, new features | production deployment                        | `environment is "prod" and change_type is "new_development"`                                                                                                                                                                |
| DEV controls  | DEV-0601 environments segregated       | production deployment                        | `environment is "prod"`                                                                                                                                                                                                     |
| DEV controls  | DEV-0603 current version               | environment                                  | `user_facing is true`                                                                                                                                                                                                       |
| DEV controls  | DEV-0701 emergency approved after      | production deployment                        | `environment is "prod" and change_type is "emergency"`                                                                                                                                                                      |
| DEV controls  | DEV-0702 emergency change reviewed     | production deployment                        | `environment is "prod" and change_type is "emergency"`                                                                                                                                                                      |
| DEV controls  | DEV-0703 new features reviewed         | production deployment                        | `environment is "prod" and change_type is "new_development"`                                                                                                                                                                |
| DEV controls  | DEV-0704 normal changes reviewed       | production deployment                        | `environment is "prod" and change_type is "normal"`                                                                                                                                                                         |
| DEV controls  | DEV-0706 root cause analysed           | vulnerability                                | `severity is "critical" and status is "fixed"`                                                                                                                                                                              |
| DEV controls  | DEV-0801 outsourced work reviewed      | pull request                                 | `author is in $params.external_contributors`                                                                                                                                                                                |

## Where Tore's rewrite and the corpus differ

Tore's rewrite of the 36 DEV controls is on the `174-feedback` branch of kosli-playground/dev-process-controls, in `issue-174-findings`. The issue decides each difference:

- **Lists of values.** Tore writes `is in "spdx", "cyclonedx"`. That parses now, and the report prints `is one of "spdx", "cyclonedx"`, which the corpus writes.
- **`is not` before a field.** Tore writes `retro_approval.approved_by is not deployed_by` (DEV-0701). That parses, and the report prints `does not equal deployed_by`, which the corpus writes.
- **Keys from a param.** Tore writes `artifact.attestations at $params.required_scans as scan`. The corpus writes `named by each of $params.required_scans`, as the issue does (DEV-0401, 0403, 0404, 0705).
- **Time.** Tore's `is not before` is `is on or after` in the corpus (DEV-0401, 0402, 0406, 0407, 0705, 0802).
- **Names.** Tore writes `$deploy.started_at` and `$pr.author` in one-line checks, with `from: deployments as deploy`. The issue has no `$` names and names things on a `for` line, so DEV-0401, 0501, 0502, 0503 and 0601 have `for` lines in the corpus.
- **DEV-0501 `peer_approved`.** Tore makes the pull request a subject. The corpus uses the issue's own example, a `for` line with two items, which keeps one row per deployment.
- **DEV-0407.** Tore writes `every $input.artifact.developers is not tested_by`. The issue rules that out, and says why `does not contain` isn't the same check. The corpus keeps a `for` line.
- **DEV-0302.** Tore writes two checks. The corpus has one check with two assertions.
- **Filters.** Tore keeps `applies_to` and `of`. The corpus puts the conditions in `from`, and DEV-0409's `critical defect` narrows `defect`.

## Where the corpus and #174 disagree

Nothing is left. The issue now decides the one disagreement and the three gaps the third pass listed: an `and` line and a list mean the same, a quantifier after `and` is allowed, `and` after `count of` or `sum of` needs no rule, and `count of` and `sum of` are walks.

One small thing: the issue says one of 56 corpus subjects would fit the one-line `subjects`. The corpus has 93 subjects counting twins, 81 without them, and 67 without the subjects added when filters became `where`, so it's unclear which count 56 is. It doesn't change the decision.

One change is still needed outside these files when this is built: `syntax.md` ([name.keys]) allows `$` after the first character of a bare key, and has to quote such keys, as the draft now does.

## Misfits left

One: server demo 0008 builds one requirement per suite in Rego. sdlc-policies 0008 already says the same thing with `named by each of`.

pr-reviewer's seven custom operators all become sentences that Ergo runs: `keys_match`, `persona_blob_shas named by persona`, since #213, `contains_all`, `x contains all of y`, since #224, and the other five since #173.

## Changes in what passes

The corpus marks each one:

- `is not empty` passes a non-empty list where `non_empty_string` fails: 52 checks.
- `is empty` passes `""` where `empty` and `equals []` fail: 6 checks.
- Six pr-reviewer `whose count of` filters fail the requirement as `unusable` on a value that isn't a list. Today's custom operator rules the subject out.
- Timestamps compared as text today fail when they aren't RFC 3339: sdlc-policies and server 0007 `peer_approval`.
- Three pr-reviewer custom operators skipped items with a missing field. The sentences fail them as `absent`.
- Rego's `!=` and `!= ""` pass values of another type, and the sentences don't: server 0010, require-artifact-provenance.
- 34 paths lose a Rego default, like `artifact_name` defaulting to `"artifact"`.
- Server 0010 now has one row per approval attestation instead of per artifact. It allows the same inputs.

Cause only, with the same values passing: `range` from 0 to 0 as `is 0` (2 checks), and `base_ref equals $params.protected_branch` (2 checks).

## Rego spike

Not run again. This pass adds `count of` and `sum of` to a `whose` and changes how two phrases print, which doesn't change how sentences are parsed or how often. The numbers from the first run still stand: sentences parsed once per check cost what today's objects cost, and parsing per subject took 739 MB of Wasm memory on 3,000 subjects.

## What writing the ABNF settled

The grammar in [`sentences.abnf`](sentences.abnf) had to pick where the prose left room. Each of these is now in [`syntax.md`](syntax.md), and each can be undone before anything implements it:

- A grammar word can't be a bare first key on the left side either, not only on the right. `count is at least 1` would otherwise read as a field called `count` or the start of `count of`. Write `.count is at least 1`. One rule for both sides.
- `, if any,` goes after the `whose`, not before it: `every items whose kind is "a", if any, is at least 2`. On a `for` line it goes before `as`.
- A `count of` or `sum of` on the right side of a phrase takes no `whose`, because `x is count of y whose a is 1 and b is 2` could be one assertion or two.
- A position has both spellings: `item 3 of items`, `first of items` and `last of items` count from 1, and `items[2]` from 0. The word form takes the whole rest of the path after `of`, so a field of the picked item needs the brackets, `commits[2].sha`, and the report prints brackets only then. `first`, `item` and `last` join the grammar words.
- `is a list` and `is an object` take either article, and the report prints `an` before `object` and `a` before the rest.
- Spaces: any run of spaces between two words reads as one, and a comma between values can have any number of spaces after it. The report prints one space and `, `.
- The made-up corpus line `count of x whose field is "v" equals a plus b` became `equals y plus z`, because `a` is a grammar word.
- `count of x whose n is m plus k is t` is no longer written wrong. It reads one way, with `m plus k` as the condition's right side. The prose had forbidden it because a tokenizer without a grammar found three readings.
- A quoted string on the right side is a value, never a key, and that's in the grammar itself as `right-path`, not only in the prose. A field whose key needs quotes is written `."$schema"` on the right, as the prose already said.

The count against the grammar is done, with Lark's Earley parser: all 306 corpus lines read exactly one way once the two rules the ABNF can't hold are applied, the grammar words and the `for` names. The scripts are outside the repo, like the tokenizer before them.

On 2026-10-14 the word that filters items changed from `where` to `whose`: `deployments whose environment is "prod"`. In the readability test, both readers who don't program read `deployments where environment is "prod"` as all the deployments with a remark about them, and listed every one, while every engineer read it as a filter. A `whose` clause in English can only narrow.

## How the prose was checked

A throwaway tokenizer in JavaScript, outside the repo, turned each phrase of [syntax.md](syntax.md#phrases) into a regular expression and tried every way to cut each line into a quantifier, a path, `whose` conditions, assertions joined with `and`, and a phrase. It counted every reading.

The corpus has 336 lines: 231 assertions, 14 `for` lines and 91 `from` lines. sdlc-policies 0004's `artifact` and its server copy have no `from` any more. With the rules now in [syntax.md](syntax.md), which are the rules #174 states, every line parses exactly one way. Without them, 194 lines parse more than one way:

| cause                                                                  | lines | rule that removes it                                     |
| ---------------------------------------------------------------------- | ----: | -------------------------------------------------------- |
| a quoted string could be text or a quoted key, `is "prod"`             | 84    | [sentence.path.argument](syntax.md#paths)                |
| a grammar word could be a field, `is empty` against `is <field empty>` | 59    | [sentence.words](syntax.md#words-a-field-cant-be-called) |
| `true`, `false` or `null` could be a field                             | 50    | both of the above                                        |
| the reference after `named by` could end at more than one key          | 24    | [sentence.path.dynamic](syntax.md#paths)                 |

Some lines have two causes. The tokenizer also applied [sentence.subject.own](syntax.md#subjects) to every `from` line, and found the same six chains the corpus marks.

28 made-up lines test what the corpus doesn't reach:

- `count of x whose n is m plus k is t` read three ways until [sentence.derived.plus](syntax.md#derived-values) was written. Under the grammar it reads one way, with `m plus k` inside the condition. A `for` item named `every` reads one way until [sentence.for.alias](syntax.md#the-for-line) forbids it.
- `if any` with `some`, two quantifiers in one sentence, `count of ... is empty`, `whose count of reviews is empty` and the bare key `foo$bar` parse no way, as they should.
- `whose count of reviews is at least 1 and state is "open"` and `some orders.id whose sum of items.price is more than 100 is not empty` read one way.
- `every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"` reads one way, with `owner` on the subject. So do `state is "MERGED" and every commits.verified is true` and `every items.price whose kind is "a" is at least 2 and some items.owner is "x"`, two quantified assertions on one line.
- `format is in "spdx", "cyclonedx"` prints as `is one of`, `username is one of $params.internal_staff` as `is in`, `approved_by is not author` as `does not equal`, and `environment does not equal "prod"` as `is not`.
- `"production deployment".pull_requests` reads one way, as a chain from that subject.

Every line also prints back exactly as written, `from` lines included.

The ABNF came later, from these rules, and was checked the same way. A script turned it into a grammar for Lark, a Python parser whose Earley mode keeps every reading, and counted the readings of each of the corpus's 306 sentences, `for` lines and `from` lines. One made-up line that used a field called `a` was changed first, since `a` is a grammar word. Two rules can't be written in ABNF and were applied after parsing: a bare first key is never a grammar word, and a `for` name is never one nor `params` or `input`. With the grammar alone, 95 lines read more than one way, every one of them because a grammar word could be a field, as in `is not empty` read as `is not .empty` and `is true` as `equals .true`. With the word rule, every line reads exactly one way. The first version of the ABNF also let a quoted string on the right side be a key, so `state is "MERGED"` read twice and 80 lines read two or four ways. That rule is in the grammar now, as `right-path`, so a parser gets it without reading this file. The made-up lines above were counted too, with the same results. `every commits, if any, as commit`, `x is ."$schema"`, `item 3 of commits is not empty`, `x equals last of items` and `commits[2].sha is "x"` each read one way, and `item 0 of items is 1` and `first is 1` read no way.
