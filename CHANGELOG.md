# Changes to ergo.rego

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](spec/CHANGELOG.md).

## 0.2.0

### New

- A subject's `from` line can ask about the items of a list with a one-line `some` or `every`, like `release whose some files.path does not match "^docs/"` or `release whose every files.path, if any, matches "^docs/"`. It works in plain subjects, in `every` lines, in child subjects and in subjects that narrow another. The `$applies` row reads the same inputs and gives the same cause as the sentence does as a check. A subject whose list is missing, `null` or not a list fails the requirement as `absent`, `null` or `unusable`, as any condition that can't be decided does. A `whose` in a check or on a `for` line still takes no `some` or `every`, and a `some` or `every` condition with a `whose` of its own is written wrong with `a condition after whose can't have a whose of its own`.
- `it` is the subject itself. A list of plain values, like ids, regions or tags, can now be checked: with a subject read from `every deployment.regions`, `it is one of $params.allowed_regions` fails the region that isn't allowed. `it` works for any subject (a string, a number, a list, an object, `null`) and fails the way the same phrase fails on a field holding that value. It starts a check, an assertion after `and`, an `any_of` option, a `whose` condition in a `from` line, and the path after `every`, `some`, `count of` and `sum of`, so `every it is a string` and `count of it is 2` check a subject that is a list. A position works on a subject that is a list, written in words as for a field: `first of it`, `item 2 of it`. A row's `inputs` name it `it`, and a failed item `item 1 of it`. Anywhere else `it` is written wrong, with a message that says why, like `it is the whole subject: write name, not it.name`. See [REFERENCE.md](REFERENCE.md#the-subject-itself).
- `ergo.as_sentences` rewrites a check from before 0.1 whose path is empty, `[]`, with `it`, so `{op: equals, path: [], value: "x"}` becomes `it is "x"`, where it was left as it was. A path that starts at a field called `it` is written `.it`.
- Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` says where Ergo read its value, in `locations`: JSON Pointers like `/deployments/3/approved_by`, or `$params:` and a pointer for a value read from the params. A tool can use them to show the spot in the input for a row. A list read with `every` or `some` has one for each item, and a number worked out with `count of`, `sum of`, `plus` or `days elapsed from` lists where it came from. A read that stops early points at the last value it reached, so a pointer never leads to a value Ergo didn't read. [Where a value was read](REFERENCE.md#where-a-value-was-read) shows it.

### Changed

- This version follows spec 0.2, so a policy says `ergo_spec: v0.2`. One that says `v0.1` is written wrong, with `unsupported version v0.1, expected v0.2`, and still works with 0.1.0. The report's `ergo` changes with it, from `"ergo": "v0.1"` to `"ergo": "v0.2"`.
- An `$applies` row has the fields the row of a check would have if its conditions were its assertions. A subject's `from` line with one `some` or `every` condition gives a row `failed_items`, as a check does, and `[]` when it passes. One with two or more conditions gives it `failed_assertions`, with an entry for each condition that failed, in the order written, and `[]` when it passes. A violation that's an `$applies` row keeps them. A row of a single plain condition, like `environment is "prod"`, doesn't change. For `from: deployments whose environment is "prod" and change_type is "emergency"`, the row of `d-2` in `{"deployments": [{"id": "d-2", "environment": "prod", "change_type": "standard"}]}` was:

  ```json
  {"check": "$applies", "subject": {"id": "d-2", "type": "deployment"}, "passed": false, "cause": "value",
   "inputs": [{"name": "change_type", "value": "standard"}, {"name": "environment", "value": "prod"}]}
  ```

  and is now:

  ```json
  {"check": "$applies", "subject": {"id": "d-2", "type": "deployment"}, "passed": false, "cause": "value",
   "inputs": [{"name": "change_type", "value": "standard", "locations": ["/deployments/0/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/0/environment"]}],
   "failed_assertions": [{"assertion": "change_type is \"emergency\"", "cause": "value"}]}
  ```

  For `from: releases whose some files.path does not match "^docs/"`, the row of release `1.4.1` in `{"releases": [{"id": "1.4.1", "files": [{"path": "docs/typo.md"}]}]}`, which only changes `docs/typo.md`, was:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/typo.md"]}]}
  ```

  and is now:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/typo.md"], "locations": ["/releases/0/files/0/path"]}],
   "failed_items": [{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/typo.md", "locations": ["/releases/0/files/0/path"]}]}
  ```
- Every entry of `inputs`, `$refs` and `failed_items` in a report gains `locations`, and the entries of `$well_formed` have `[]`. For the second deployment in `{"deployments": [...]}`, an input that was `{"name": "approved_by", "value": null}` is now `{"name": "approved_by", "value": null, "locations": ["/deployments/1"]}`. Two reads with the same name and value used to be one entry. They are now one only when their locations match too, so a parent's `b.x` and a child's own `.b.x` that print the same and are read from different places each keep an entry.

- A subject called `it` is written wrong, for each requirement that uses it. Rename it.
- `it` is a word of the grammar, like `empty` and `count`. A bare `it` at the start of a path now reads the subject, where it read the field `it`, and a field called `it` is written `.it`, in a policy and in the report. A `for` alias or a part called `it` is now written wrong, so rename it. The report changes for a policy that has a bare `it` in a check or a subject, or a field called `it`. With `from: every xs` on `{"xs": [{"id": "a", "it": 1}]}`, `it is 1` used to read the field and pass:

  ```json
  {"check": "c", "passed": true, "cause": "satisfied", "inputs": [{"name": "it", "value": 1}]}
  ```

  Now it reads the whole subject and fails:

  ```json
  {"check": "c", "passed": false, "cause": "unusable", "inputs": [{"name": "it", "value": {"id": "a", "it": 1}, "locations": ["/xs/0"]}]}
  ```

  Write `.it is 1` to read the field, and the input is named `.it`:

  ```json
  {"check": "c", "passed": true, "cause": "satisfied", "inputs": [{"name": ".it", "value": 1, "locations": ["/xs/0/it"]}]}
  ```

- A row shows each input once. A check that reads the same value twice listed it twice. With the requirement `r` on the subject `deployment`, the check `c: count of approvals plus count of approvals is 4` and the deployment `{"id": "d1", "approvals": ["a", "b"]}`, the row was:

  ```json
  {"check": "c", "subject": {"id": "d1", "type": "deployment"}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "count of approvals plus count of approvals", "value": 4, "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "count of approvals", "value": 2, "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "count of approvals", "value": 2, "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "approvals[]", "value": ["a", "b"], "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "approvals[]", "value": ["a", "b"], "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]}]}
  ```

  and is now:

  ```json
  {"check": "c", "subject": {"id": "d1", "type": "deployment"}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "count of approvals plus count of approvals", "value": 4, "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "count of approvals", "value": 2, "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]},
              {"name": "approvals[]", "value": ["a", "b"], "locations": ["/deployments/0/approvals/0", "/deployments/0/approvals/1"]}]}
  ```
- A one-line `some` or `every`, a `count of` or `sum of`, and the `$applies` row of a `from` condition now list the parent or `$input` value they compare with in `inputs`, as a plain check does. They list the subject's own part they compare with too, with its `part` tag. With the subject `pr`, read from `artifact.pull_requests`, with the part `w: info.who`, the requirement `r` and the input `{"artifacts": [{"id": "a1", "owner": "ann", "pull_requests": [{"id": "p1", "info": {"who": "ann"}, "commits": [{"author": "bob"}, {"author": "ann"}]}]}]}`, the check `owner: some commits.author is artifact.owner` had the row:

  ```json
  {"check": "owner", "subject": {"id": "p1", "type": "pr", "in": {"artifact": "a1"}}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "commits[].author", "value": ["bob", "ann"], "locations": ["/artifacts/0/pull_requests/0/commits/0/author", "/artifacts/0/pull_requests/0/commits/1/author"]}]}
  ```

  and now has:

  ```json
  {"check": "owner", "subject": {"id": "p1", "type": "pr", "in": {"artifact": "a1"}}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "artifact.owner", "value": "ann", "locations": ["/artifacts/0/owner"]},
              {"name": "commits[].author", "value": ["bob", "ann"], "locations": ["/artifacts/0/pull_requests/0/commits/0/author", "/artifacts/0/pull_requests/0/commits/1/author"]}]}
  ```

  The check `who: some commits.author is w` now also lists `{"name": "w", "value": "ann", "part": {"id": null, "name": "w"}, "locations": ["/artifacts/0/pull_requests/0/info/who"]}`, after `commits[].author`.

  Under a `for` line, a `count of` or `sum of` now lists the parent values its `whose` reads, and its own list when that list doesn't start at the alias, like `artifact.tags[]` and `count of artifact.tags` for `count of artifact.tags is at least 1`. A value read through the alias is still never listed.

  A walk, count or sum whose path reads through `named by` an alias now lists the part before the name, as a plain check does. With `for: every keys as k`, `some artifact.map named by k is at least 1` and `count of artifact.map named by k is at least 1` list `artifact.map`, the whole object, next to `keys[]`, where they listed only `keys[]`. A walk or a count whose `whose` reads a parent through the alias lists it too, like `artifact.nums` in `count of rows whose n is artifact.nums named by k is at least 1`.

  A walk, `count of` or `sum of` whose right side or `whose` is named by a field of each item, like `some rows.n is at least artifact.nums named by key` or `count of rows whose n is at least artifact.nums named by key`, lists the part before the name too, `artifact.nums`, in a check, on a `for` line and in a `from` condition. It never lists `artifact.nums named by key`, because that value is different for each item. With `{"artifacts": [{"id": "a1", "nums": {"a": 1, "b": 2}, "prs": [{"id": "p1", "rows": [{"key": "a", "n": 1}, {"key": "b", "n": 2}]}]}]}`, the row's `inputs` held only `rows[].n`, and now it also has `{"name": "artifact.nums", "value": {"a": 1, "b": 2}, ...}`.

- A sentence that failed on a `for` line gives the values it compared, in `inputs`. Each entry of a failed sentence's `items` has them, and so does a failed sentence that has no `items`, because it doesn't read the second list's item. They are the entries the sentence would have in the `inputs` of a row of its own, with `name`, `value`, `locations` and `part`, and the names as the sentence writes them, like `approver.timestamp`. A tool can show "1792655359 is not after 1792656245" without reading the sentence. Every failure has them, so a report with many failed items is longer.

  With this input:

  ```json
  {"pull_requests": [{"id": "pr-8",
                      "approvers": [{"username": "bob", "timestamp": 1792655359}],
                      "commits": [{"sha": "a1", "timestamp": 1792656245}]}]}
  ```

  and this check:

  ```yaml
  peer_approval:
    for: some approvers as approver, every commits as commit
    assert: approver.timestamp is after commit.timestamp
  ```

  the first entry of `failed_items` was:

  ```json
  {"cause": "value",
   "failed_assertions": [{"assertion": "approver.timestamp is after commit.timestamp", "cause": "value",
                          "items": [{"cause": "value", "item": "item 1 of commits"}]}],
   "item": "item 1 of approvers", "locations": ["/pull_requests/0/approvers/0"], "path": "item 1 of approvers",
   "value": {"timestamp": 1792655359, "username": "bob"}}
  ```

  and is now:

  ```json
  {"cause": "value",
   "failed_assertions": [{"assertion": "approver.timestamp is after commit.timestamp", "cause": "value",
                          "items": [{"cause": "value",
                                     "inputs": [{"locations": ["/pull_requests/0/approvers/0/timestamp"],
                                                 "name": "approver.timestamp", "value": 1792655359},
                                                {"locations": ["/pull_requests/0/commits/0/timestamp"],
                                                 "name": "commit.timestamp", "value": 1792656245}],
                                     "item": "item 1 of commits"}]}],
   "item": "item 1 of approvers", "locations": ["/pull_requests/0/approvers/0"], "path": "item 1 of approvers",
   "value": {"timestamp": 1792655359, "username": "bob"}}
  ```

### Fixed

- A `from` line with `every $input` and ten steps after it reads. It was written wrong, with `every over more than ten steps isn't supported yet`, because `$input` counted as a step there and not in a check. A check, a `for` line and a `from` line now count the same way.
- A `count of` or `sum of` over more than ten steps on the right of a phrase, in a `whose`, in an `any_of` option or after `plus`, is written wrong with `every and some over more than ten steps aren't supported yet`, as it already was on the left. It used to read, and failed every subject as `unusable` with a count of `null`. The exception is a path that starts at a `for` alias with ten names after it, like `x.n is count of x.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` with `for: every xs as x`: it read correctly, and it's now written wrong too, because the alias is a step, as it already was on the left.
- A walk through a part over ten steps in all, like `every x.z is 1` with the part `x` set to a path of ten names, is written wrong with `every and some over more than ten steps aren't supported yet`, because the part's own path counts in place of its alias. It was read, and failed every subject as `unusable`. A part that isn't walked is not limited. Reports change for such a check.
- A walk that starts at a `for` alias holding `null` fails as `null`, as [walk.lists](spec/semantics.md#every-and-some) says and as a field holding `null` does. It failed as `absent`. With `for: every commits as c` and `assert: every c.files is a string`, on the release `{"id": "r1", "commits": [null]}`, the row was:

  ```json
  {"check": "c", "passed": false, "cause": "absent", "failed_items": [{"cause": "absent", "failed_assertions": [{"assertion": "every c.files is a string", "cause": "absent"}], "item": "item 1 of commits", "path": "item 1 of commits", "value": null}]}
  ```

  Now it fails as `null`:

  ```json
  {"check": "c", "passed": false, "cause": "null", "failed_items": [{"cause": "null", "failed_assertions": [{"assertion": "every c.files is a string", "cause": "null"}], "item": "item 1 of commits", "path": "item 1 of commits", "value": null, "locations": ["/releases/0/commits/0"]}]}
  ```

- A position at the start of a path from a `for` alias reads the alias as a list, as it does on a field, where it failed as `not_an_object`. With `for: every batches as b` and `assert: first of b is "x"`, on the release `{"id": "r1", "batches": [["x", "y"], []]}`, the row was:

  ```json
  {"check": "c", "passed": false, "cause": "not_an_object", "failed_items": [{"cause": "not_an_object", "item": "item 1 of batches", "value": ["x", "y"], ...}, {"cause": "not_an_object", "item": "item 2 of batches", "value": [], ...}]}
  ```

  Now the first batch passes and the empty one fails as `absent`:

  ```json
  {"check": "c", "passed": false, "cause": "absent", "failed_items": [{"cause": "absent", "item": "item 2 of batches", "value": [], ...}]}
  ```

- A walk can read a parent through a `for` alias on its right side, like `named by k` in `some rows.n is at least artifact.nums named by k`. It failed as `absent` even when the parent had the name, so a check that should pass failed. With `for: every keys as k`, on `{"artifacts": [{"id": "a1", "nums": {"k1": 1, "k2": 2}, "prs": [{"id": "p1", "keys": ["k1", "k2"], "rows": [{"n": 1}, {"n": 2}]}]}]}`, the row was `{"check": "c", "passed": false, "cause": "absent", ...}`, and now it's `{"check": "c", "passed": true, "cause": "satisfied", ...}`. A name the parent doesn't have still fails as `absent`, a `null` alias as `null`, and a value of the wrong type as `unusable`, as a `count of` does.

- A second item of a `for` line that starts at a parent and goes through `named by`, like `every artifact.map named by k as x`, was listed with the first letter of the parent cut off, as `rtifact.map named by k[]`. It's `artifact.map named by k[]` now.

  A second item that starts at a parent's part, like `every artifact.ap.w whose t is k as x` where `artifact` has `has: {ap: ps}`, named its items that failed before any sentence was checked, and the items a failed sentence lists, with an internal marker in it, `item 2 of "{\"alias\":\"ap\",\"n\":1,\"of\":\"artifact\",\"old\":false}".ps.w`. It's `item 2 of artifact.ap.w` now, as the entry `artifact.ap.w[]` in `inputs` is. One that reads the part through `named by`, like `every artifact.ap named by k as x`, is `item 2 of artifact.ap.k1` when `k` is `k1`, and still names the key it read, as a walk does.

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
