# Changes to ergo.rego

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](spec/CHANGELOG.md).

## 0.2.0

### New

- A subject's `from` line can ask about the items of a list with a one-line `some` or `every`, like `release whose some files.path does not match "^docs/"` or `release whose every files.path, if any, matches "^docs/"`. It works in plain subjects, in `every` lines, in child subjects and in subjects that narrow another. The `$applies` row reads the same inputs and gives the same cause as the sentence does as a check. A subject whose list is missing, `null` or not a list fails the requirement as `absent`, `null` or `unusable`, as any condition that can't be decided does. A `whose` in a check or on a `for` line still takes no `some` or `every`, and a `some` or `every` condition with a `whose` of its own is written wrong with `a condition after whose can't have a whose of its own`.

### Changed

- This version follows spec 0.2, so a policy says `ergo_spec: v0.2`. One that says `v0.1` is written wrong, with `unsupported version v0.1, expected v0.2`, and still works with 0.1.0. The report's `ergo` changes with it, from `"ergo": "v0.1"` to `"ergo": "v0.2"`.
- An `$applies` row has the fields the row of a check would have if its conditions were its assertions. A subject's `from` line with one `some` or `every` condition gives a row `failed_items`, as a check does, and `[]` when it passes. One with two or more conditions gives it `failed_assertions`, with an entry for each condition that failed, in the order written, and `[]` when it passes. A violation that's an `$applies` row keeps them. A row of a single plain condition, like `environment is "prod"`, doesn't change. For `from: deployments whose environment is "prod" and change_type is "emergency"`, the row of a deployment with `change_type` set to `standard` was:

  ```json
  {"check": "$applies", "subject": {"id": "d-2", "type": "deployment"}, "passed": false, "cause": "value",
   "inputs": [{"name": "change_type", "value": "standard"}, {"name": "environment", "value": "prod"}]}
  ```

  and is now:

  ```json
  {"check": "$applies", "subject": {"id": "d-2", "type": "deployment"}, "passed": false, "cause": "value",
   "inputs": [{"name": "change_type", "value": "standard"}, {"name": "environment", "value": "prod"}],
   "failed_assertions": [{"assertion": "change_type is \"emergency\"", "cause": "value"}]}
  ```

  For `from: releases whose some files.path does not match "^docs/"`, the row of release `1.4.1`, which only changes `docs/typo.md`, was:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/typo.md"]}]}
  ```

  and is now:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/typo.md"]}],
   "failed_items": [{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/typo.md"}]}
  ```

## 0.1.0

The first release. It follows spec 0.1.

Ergo went public on 6 October 2026. This is what changed since, for anyone who tried it then, and what you need to know to use it now. A policy written before 0.1 needs the changes under [Moving a policy from before 0.1](#moving-a-policy-from-before-01) before 0.1 reads it.

### Checks are sentences

A check used to be an object, like `{op: non_empty_string, path: [approved_by]}`. Now it's a sentence: `approved_by is a non-empty string`. Sentences cover lists (`every`, `some`, `whose`), counts and sums (`count of`, `sum of`, `plus`), text (`starts with`, `matches`), times and plain dates (`is before`, `days elapsed from`), one item of a list (`item 1 of`, `last of commits sorted by timestamp`) and a list read by a key (`named by`). The report shows each check as the sentence you wrote, so whoever reads the report reads the rule.

The old shape isn't read any more. A policy written that way is written wrong, and the report says so. `ergo.as_sentences(policy)` rewrites what it can as sentences and leaves the rest as it was, like `all`, `any`, `any_of` and `count` checks, for you to rewrite by hand. [Moving a policy to sentences](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/REFERENCE.md#moving-a-policy-to-sentences) shows what it leaves. Custom operators and substitutes went with the old shape, because a sentence can't call an operator, and an `any_of` of sentences says what a substitute did. A file of custom operators next to `ergo.rego` no longer compiles, so it fails loudly rather than being ignored.

### Subjects are defined once

A policy lists its subjects, the deployments or artifacts or expenses it checks, under `subjects`, each with a `from` line like `deployments whose environment is "prod"` and an `identified_by` field, and each requirement names the one it checks. A subject can be found inside another, like the artifacts of each deployment, up to three levels, and can name parts with `has`. The report lists the subjects and where each one came from, and a row that read a part says which part and which id.

### Reports say more

A failed `every` or `some` lists the items that failed. An unmet requirement says why, worst cause first, with how many rows each. A policy, a requirement and a check can carry a `description` and `meta`. A policy with a field Ergo doesn't know, or without `ergo_spec: v0.1` at its top, is written wrong, with a row that says what's wrong, and a requirement written wrong gets only that row. Every report says what made it, under `engine`, and which spec version it follows, under `ergo`.

Rows name what they read the way sentences write it: `$params.allowed` where it was `$$params.allowed`, and `item 2 of xs` where it was `xs.1`. Numbers are written in their plain form, so `1.50` in the input is `1.5` in the report. The causes `substituted`, `unmatched` and `ill_formed` are gone with what produced them.

### Verdicts that changed

Some checks that passed at the launch fail now, because Ergo could not tell whether they held:

- A `from` that leads nowhere, to `null` or to something that isn't a list or an object, fails `$min_subjects` as `absent`, `null` or `unusable`, even with `min_subjects: 0`. It used to count as nothing to check.
- A comparison on a field of the wrong type fails as `unusable`. `is not one of` and `does not contain` used to pass on one, and `is at least` used to order two strings, so `"9"` was at least `"80"`.
- A `whose` on a field of the wrong type fails the requirement. The subject used to be left out quietly.
- Params that aren't an object, like a string, fail every check as `unusable`. `null` still means no params.

### A written spec

Ergo has a spec that doesn't depend on Rego: a grammar for the sentences, JSON Schemas for a policy and a report, and cases that pin what each check means. CI runs every case against `ergo.rego`. The schemas are at [ergo.kosli.com/spec/0.1/policy.schema.json](https://ergo.kosli.com/spec/0.1/policy.schema.json) and [ergo.kosli.com/spec/0.1/report.schema.json](https://ergo.kosli.com/spec/0.1/report.schema.json), and [spec/CHANGELOG.md](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/spec/CHANGELOG.md) lists what the spec changed against the old shape.

### Faster and lighter

A report takes about two thirds of the time it took at the launch, and `ergo.compile`, which reads a policy once and reuses it for many reports, cuts it further. It's experimental and may change. A report on 100 deployments compiled to Wasm used 264 MB of memory at the launch and uses under 20 MB now, and CI keeps a budget on it. Ergo reads nothing from the machine, so it compiles on a host that leaves out the built-ins that read the clock or the network, and a host that checks `input` against a closed JSON Schema can publish an Ergo policy.

### Moving a policy from before 0.1

- Call `ergo.report(input, policy, params)`. It was `ergo.report(input, requirements)`, with `report_with_params` for params. The policy is one object with `ergo_spec`, `subjects` and `requirements`, and params are `{}` when there are none. [Getting started](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/README.md#2-write-a-policy) shows the Rego that hands a YAML file over.
- Put `ergo_spec: v0.1` at the top of the policy file. From Rego, pass it as `"ergo_spec": data.ergo_spec`. Without it, every requirement is written wrong.
- Move `subject_type`, `from`, `id` and `applies_to` out of each requirement into one entry under `subjects`, with a `from` line that holds the `applies_to` conditions after `whose`, and `identified_by` where `id` was. Each requirement then says `subject: <name>`. Those four fields on a requirement are unknown now.
- Rewrite each check as a sentence, with `ergo.as_sentences` for the first pass.
- Anything that matched on row `inputs`, `$refs` or `failed_items` by name needs the new names above.

### What to call

`ergo.report(input, policy, params)` gives the report.

`ergo.violations(report)` gives the rows that failed and leaves out the ones that aren't problems, like a subject that was out of scope.

Ergo is one file, `ergo.rego`, with no dependencies. It needs OPA 1.20.1 or later: OPA 1.19 compares some numbers wrong, and OPA 1.20.0 stops on some of them. [What Ergo does](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/README.md#what-ergo-does) in the README says the rest, and the [tutorial](https://ergo.kosli.com/tutorial/) teaches the sentences with a bakery.
