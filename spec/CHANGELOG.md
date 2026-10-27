# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.2

### New

- A `whose` in a subject's `from` line takes a one-line `some` or `every` as a condition ([sentence.subject.condition](syntax.md#subjects)), like `release whose some files.path does not match "^docs/"`. Its `$applies` row gives the inputs and the cause the same sentence gives as a check row. It doesn't change the report of a policy that was read before, and a `from` line that used to be written wrong is now read.
- `it` is the subject itself, for a subject of any type, so a list of plain values like ids, regions or tags can be checked: with `from: every deployment.regions`, `it is one of $params.allowed_regions` fails the region that isn't allowed. It starts an assertion, a `whose` condition of a `from` line, and the path after `every`, `some`, `count of` and `sum of`. A position works on a subject that is a list, written in words as for a field: `first of it`, `item 2 of it`. A row's `inputs` name it `it`, and a failed item `item 1 of it`. See [sentence.path.it](syntax.md#paths). Written anywhere else, `it` is written wrong ([sentence.path.it.step](syntax.md#paths), [sentence.path.it.place](syntax.md#paths)).
- Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`, where its value was read: JSON Pointers like `/deployments/3/approved_by`, or `$params:` and a pointer for the params ([location](semantics.md#where-a-value-was-read)). A read that stops early points at the last value it reached, and a worked-out number lists the locations of what it was worked out from.

### Changed

- A policy says `ergo_spec: v0.2`, and the report's `ergo` changes from `"ergo": "v0.1"` to `"ergo": "v0.2"`. A policy that says `v0.1` is written wrong, with `unsupported version v0.1, expected v0.2`. The schemas are under `https://ergo.kosli.com/spec/0.2/`.
- Reports change: `locations` is required on every entry of `inputs`, `$refs` and `failed_items`, and is `[]` on the entries of `$well_formed`. For the second deployment in `{"deployments": [...]}`, an input that was `{"name": "approved_by", "value": null}` is now `{"name": "approved_by", "value": null, "locations": ["/deployments/1"]}`. Two reads with the same name and value are merged into one entry only when their locations match too, so a report that listed one entry may list two.
- [policy.version](syntax.md#policies) takes an optional `-dev` after the version, which `main` uses until a version is released, like `v0.2-dev`. `v0.2-beta` is still not a version.
- An `$applies` row has the fields the row of a check would have if its conditions were the assertions of that check ([scope.failures](semantics.md#scope)). A subject's `from` line with one `some` or `every` condition gives a row `failed_items`, as a check does, and `[]` when it passes. One with two or more conditions gives it `failed_assertions`, with an entry for each condition that failed, in the order written, and `[]` when it passes. The violations keep them. A row of a single plain condition, like `environment is "prod"`, doesn't change. For `from: deployments whose environment is "prod" and change_type is "emergency"`, the row of `d-2` in `{"deployments": [{"id": "d-2", "environment": "prod", "change_type": "standard"}]}` was:

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

- A subject called `it` is written wrong ([sentence.path.it.name](syntax.md#paths)), for the requirements that use it.
- `it` is a word of the grammar ([sentence.words](syntax.md#words-a-field-cant-be-called)). A field called `it` is written `.it`, and the report prints `.it`. Reports reach this when a policy starts a path with a bare `it`, which now reads the subject itself instead of its field `it`, and when an alias or a part is called `it`, which is now written wrong.
- A sentence that failed on a `for` line gives the values it compared, in `inputs` ([for.failure_inputs](semantics.md#for)). Each entry of a failed sentence's `items` has them, and so does a failed sentence that has no `items`, because it doesn't read the second list's item. They are the entries the sentence would have in the `inputs` of a row of its own, with `name`, `value`, `locations` and `part`, and the names as the sentence writes them, like `approver.timestamp`. The report schema gains `inputs` on those entries. A tool can show "1792655359 is not after 1792656245" without reading the sentence. Every failure has them, so a report with many failed items is longer.

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

- A row shows each entry of its `inputs` once ([row.inputs_once](semantics.md#what-a-row-shows)). A check that reads the same value twice, like `count of approvals plus count of approvals is 4`, listed it twice, as [tally.inputs](semantics.md#counts-and-sums-in-sentences) said. Reports change for such a check.
- The row of a one-line `some` or `every`, of a `count of` or `sum of`, and an `$applies` row of a `from` condition list the value of each parent or `$input` path they compare with, as a plain check does ([walk.inputs](semantics.md#every-and-some), [tally.inputs](semantics.md#counts-and-sums-in-sentences)), and never the value of a `for` alias. They list the subject's own part they compare with too, with its `part` tag ([parts.tag](semantics.md#parts)). For the check `some commits.author is artifact.owner` the row's `inputs` held only `{"name": "commits[].author", "value": ["bob", "ann"], ...}`, and now `{"name": "artifact.owner", "value": "ann", ...}` comes before it. For `some commits.author is w` it now has `{"name": "w", "value": "ann", "part": {"id": null, "name": "w"}, ...}`. Under a `for` line, a `count of` or `sum of` lists the parent values its `whose` reads, and its own list when that list doesn't start at the alias ([for.inputs](semantics.md#for)). Reports change for such a check.
- A check can walk any number of lists: the limit of three list walks per check is gone. What's limited is the path after `every`, `some`, `count of` and `sum of`, which takes ten steps at most, wherever it stands ([sentence.walk.steps](syntax.md#every-some-and-whose)). Policies and reports that stay under it don't change.

### Fixed

- A `from: every $input...` line with ten steps after `$input` reads, because `$input` isn't a step ([sentence.walk.steps](syntax.md#every-some-and-whose)). It was written wrong, with `every over more than ten steps isn't supported yet`, because `ergo.rego` counted `$input` there but not in a check. Reports change for such a line.
- A `count of` or `sum of` over more than ten steps on the right of a phrase, like `n is count of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11`, or in a `whose`, an `any_of` option or after `plus`, is written wrong, as it is on the left. It was read, and failed every subject as `unusable` with a count of `null`. The report now has a failing `$well_formed` row in their place. One such check read correctly before: a `count of` or `sum of` on the right that starts at a `for` alias with ten names after it, like `x.n is count of x.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` with `for: every xs as x`. The alias is a step, as it already was on the left, so that's eleven, and it's now written wrong. Reports change for such a check.
- A walk through a part over ten steps in all, like `every x.z is 1` with the part `x` set to a path of ten names, is written wrong ([sentence.walk.steps](syntax.md#every-some-and-whose)), because the part's own path counts in place of its alias. It was read, and failed every subject as `unusable`. A part that isn't walked is not limited. Reports change for such a check.
- A walk that starts at a `for` alias holding `null` fails as `null`, as [walk.lists](semantics.md#every-and-some) says. `ergo.rego` failed it as `absent`. The new case in `cases/for` pins it. Reports change for such a walk.
- A position at the start of a path reads the subject or a `for` alias as a list ([path.not_an_object](semantics.md#reading-a-path)), so `first of b` on a `for` alias holding `["x", "y"]` reads `"x"`, where `ergo.rego` failed it as `not_an_object`. The new case in `cases/for` pins it. Reports change for such a check.

## 0.1

The first version. Policies need `ergo_spec: v0.1` at their top, and reports get `ergo` and `engine` there.

Before it, the spec had no version, and Ergo read policies written in an older shape: checks as objects with `op` and `path`, subjects with `applies_to` filters, custom operators added as Rego rules, and substitutes. The changes below are against that shape, for anyone with a policy or reports from before 0.1. `ergo.as_sentences` rewrites such a policy into sentences where it can.

- One version for the policy, the report and what one means for the other. A policy names it in `ergo_spec`, and a report in `ergo`.
- A report says what made it in `engine`.
- A report's hash is the SHA-256 of the report without `engine`, written as RFC 8785 says.
- The schemas have `$id`s under `https://ergo.kosli.com/spec/0.1/`.
- Custom operators, which a policy added as `op_passed` rules in the `ergo` package, go, because a sentence can't call one. They come back once a definition format is built, see [OPEN.md](OPEN.md#custom-operators).
- Substitutes, a `substitute` check that satisfied another when it failed, go, since an `any_of` of sentences says the same. Reports lose the `substituted` cause.
- Checks are sentences only. A check written as an object with `op` is written wrong, with `missing assert` and `unknown field op`, and so are `all`, `any`, `inputs`, `literal`, `ref` values, selectors and derived sides written by hand.
- Subjects are written with `from` lines only. A `from` or `identified_by` that isn't a string is written wrong with `not a string`, and `applies_to` and `of` are unknown fields. Literal key lists, selectors in `from` and `identified_by`, and filter names, descriptions and meta have no `from` line form and go with them.
- A requirement written wrong gets only its `$well_formed` row, and its `subjects` counts are 0. Reports lose the `ill_formed` cause, which only such a requirement's rows had. A filter written wrong on a parent subject now fails the `$well_formed` row of each requirement on its children too.
- Reports lose the `unmatched` cause, which only a selector gave, and a check's entry in `requirements` has only `description`, `meta`, `expression` and `$refs`. Its `expression` is always the sentence, printed as [sentence.print.canonical](syntax.md#printing-the-sentence) says.
- A position read from a param that holds a number above 9007199254740991 is `unusable`. It used to read nothing, so `does not exist` passed. A check on such a path fails as `unusable`, so does a check on a part whose path reads it, where it failed as `value`, and a `from` line like `ls[$params.big]` fails `$min_subjects` as `unusable`, where it failed as `absent`.
- `$well_formed`, `$min_subjects`, `$unique_ids` and `$applies` are reserved: a check with one of those names is written wrong with `name reserved`, where it used to add a second row of that name.
- A `from` line that loops through a child subject says `leads to a loop`, where it said `a chain of more than three subjects isn't supported yet`.
