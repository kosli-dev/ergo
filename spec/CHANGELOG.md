# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.3

### Changed

- A policy says `ergo_spec: v0.3`, and the report's `ergo` changes from `"ergo": "v0.2"` to `"ergo": "v0.3"`. A policy that says `v0.2` is written wrong, with `unsupported version v0.2, expected v0.3`. The schemas are under `https://ergo.kosli.com/spec/0.3/`.
- An implementation may fail a check as `unusable` when it can't read or compare a number exactly, like one whose exponent is too long to hold ([Values](semantics.md#values)). It used to have to compare every number it was given. `ergo.rego` compares such numbers as before, so its reports don't change.
- Whitespace of any kind at either end of a sentence, a `for` line or a `from` line is dropped before it's read, not only spaces: every character with Unicode's `White_Space` property, like a tab, a newline or U+3000 ([sentence.ends](syntax.md#the-grammar)). So a YAML block like `assert: |`, which ends in a newline, reads as the sentence it holds. `ergo.rego` already read these lines, so no report changes. A byte order mark or a zero-width space at either end still makes a line not read. The same goes for the path of an `identified_by` or a part, which `ergo.rego` also trimmed already.
- [min_subjects](semantics.md#requirements) is now a whole number from 0 to 1,000,000. It used to say a whole number of 0 or more, so engines disagreed on big values. A requirement with a larger `min_subjects` is written wrong, and the message for every wrong `min_subjects` is `not a whole number from 0 to 1000000`, where it was `not a whole number of 0 or more`. A number a 64-bit float can't hold still says `number out of range`. The policy schema has `"maximum": 1000000` on `min_subjects`. Reports change for such policies: a requirement with a `min_subjects` over 1,000,000 fails `$well_formed` and gets no other row, and the `$well_formed` row of any wrong `min_subjects` shows the new message.

### Fixed

- [for.flaws](semantics.md#for) now says that an item of a `for` line that isn't an object, `null` included, fails as `not_an_object` when the item's path goes on into it, with `some` and a position too, as `every` does. It used to say so only for a second item that reads into the first, and the spec didn't say what the other items fail as. [for.walk](semantics.md#for) says it too. Reports change for such inputs: with `t` set to `["a"]`, `for: every t.k as x` failed `item 1 of t` as `unusable` and now fails it as `not_an_object`. `ergo.rego` also failed `null` items as `absent`, and `count of` and `sum of` on a `null` item as `absent` where [tally.walk](semantics.md#counts-and-sums-in-sentences) says `not_an_object`. Only the cause changes, not whether a check fails.
- [sentence.for.pick](syntax.md#the-for-line) now says that an index in brackets doesn't pick, so a `for` item like `t[0] as i` is written wrong, as the grammar already had it. `ergo.rego` read it as a position, so `t[0] as i` meant `first of t as i`, and a second item was read the same way. Reports change for such a policy: the check fails `$well_formed` and the requirement gets no other row.
- A child subject whose parent isn't an object, `null` included, fails `$min_subjects` as `not_an_object`, as [subjects.chain.not_an_object](semantics.md#requirements) now says. The spec didn't say, and `ergo.rego` gave `unusable` for a string, number, list or boolean parent and `absent` for a `null` one. Reports change for such inputs. A parent that is an object without the field still gives `absent`.
- The spec now says these things that `ergo.rego` already did, so no report changes:
  - the `expression` of a check written wrong ([sentence.print.written_wrong](syntax.md#printing-the-sentence))
  - how a number prints in a sentence ([sentence.print.numbers](syntax.md#printing-the-sentence))
  - that a subject that isn't an object is its own id ([subjects.id](semantics.md#requirements))
  - that `\d`, `\w`, `\s` and `\b` in a pattern only know ASCII ([patterns.syntax](semantics.md#matches_any-and-not_matches_any))
  - that the keys of every object in a report are sorted ([report.keys](semantics.md#statuses))
  - the order of the `inputs` of a failed sentence on a `for` line ([for.failure_inputs](semantics.md#for))
- [tally.sum](semantics.md#counts-and-sums-in-sentences) now says when a `sum_of` or an `add` fails as `unusable`: when a number added, or the result, isn't a whole number below 10^15 once scaled by 10^p, where p is the most decimal places any of them has, counted on the value, or when p is above 15. It used to say such sums are added as the runtime adds them, which gave different answers in different runtimes. Reports change for such inputs, like `0.123456789012345` plus `100`, which now fails as `unusable` with a `null` entry.
- A `from` line with `named by each of` fails `$min_subjects` when the path before it doesn't lead to an object, as [subjects.sentence](semantics.md#requirements) now says: as `absent` or `null` when the object is missing or `null`, and as `unusable` when it's a list, a string or a number. Each listed key is still a subject, as before, so its checks still show what's missing, but the requirement is never met. A list of keys that holds anything but strings makes no subjects and fails `$min_subjects` as `unusable`. The spec didn't say, and `ergo.rego` met the requirement whenever every check passed, so with `from: scans named by each of $params.required` and no `scans` in the input, `x does not exist` passed for every key and the policy was compliant. The same holds when a ref step before `named by each of` can't be used, like `named by $params.env` with `env` set to `5`, which was met too. Reports change for such inputs: `$min_subjects` fails and the requirement is `not_met`, a key list with a non-string key gives no subject rows, and a child subject of such a parent gets one `$min_subjects` row and one `$unique_ids` row with no `in`, as [subjects.chain.count](semantics.md#requirements) says, instead of a row per key.
- [report.subjects](semantics.md#statuses) now says what it lists for a subject written wrong. A `from` that reads but has a problem, like `values of mixed types`, is `<invalid from>`, and so is the `from` of a subject with `applies_to` or `of`, because those fields said how it was found. A subject whose `from` starts at another subject lists that subject even when the line is written wrong, and a subject that narrows another has that subject's id then, even with an `identified_by` of its own. A `from` that doesn't parse, or isn't a string, lists no other subject. Cases with `report.subjects` check each of these. `ergo.rego` gave the line itself for a `from` with a problem, listed only the last subject of a chain of more than three, and left out the subject a `from` with `every` starts at, so its reports change for such policies.
- [sentence.path.start](syntax.md#paths) now says that an unknown `$<word>` is read by the grammar like `$params`, and only makes the line written wrong with `unknown name`, next to any other problem the line has. A line that doesn't parse says why. Cases pin what `report.subjects` lists for a `from` with an unknown name, and the messages of a sentence and a `for` line with an unknown name and a syntax error.
- `sentences.abnf` now reads `$<name>` as a start, after `named by` and in brackets, where it read only `$params` and `$input`, so a line with an unknown name is one the grammar reads. A bare `$params` or `$input` after `named by` or in brackets is still not accepted.

## 0.2

### New

- A `whose` in a subject's `from` line takes a one-line `some` or `every` as a condition ([sentence.subject.condition](syntax.md#subjects)), like `release whose some files.path does not match "^docs/"`. Its `$applies` row gives the inputs and the cause the same sentence gives as a check row. It doesn't change the report of a policy that was read before, and a `from` line that used to be [written wrong](syntax.md#written-wrong) is now read. Its `$applies` row has `failed_items`, as a check's row does ([scope.failures](semantics.md#scope)), and `[]` when it passes. For `from: releases whose some files.path does not match "^docs/"`, the row of release `1.4.1` in `{"releases": [{"id": "1.4.1", "files": [{"path": "docs/typo.md"}]}]}`, which only changes `docs/typo.md`, is:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/typo.md"], "locations": ["/releases/0/files/0/path"]}],
   "failed_items": [{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/typo.md", "locations": ["/releases/0/files/0/path"]}]}
  ```
- `it` is the subject itself, for a subject of any type, so a list of plain values like ids, regions or tags can be checked: with `from: every deployments.regions`, `it is one of $params.allowed_regions` fails the region that isn't allowed. It starts an assertion, a `whose` condition of a `from` line, and the path after `every`, `some`, `count of` and `sum of`. A position works on a subject that is a list, written in words as for a field: `first of it`, `item 2 of it`. A row's `inputs` name it `it`, and a failed item `item 1 of it`. See [sentence.path.it](syntax.md#paths). Written anywhere else, `it` is written wrong ([sentence.path.it.step](syntax.md#paths), [sentence.path.it.place](syntax.md#paths)).
- Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`, where its value was read: JSON Pointers like `/deployments/3/approved_by`, or `$params:` and a pointer for the params ([location](semantics.md#where-a-value-was-read)). A read that stops early points at the last value it reached, and a worked-out number lists the locations of what it was worked out from.

### Changed

- A policy says `ergo_spec: v0.2`, and the report's `ergo` changes from `"ergo": "v0.1"` to `"ergo": "v0.2"`. A policy that says `v0.1` is written wrong, with `unsupported version v0.1, expected v0.2`. The schemas are under `https://ergo.kosli.com/spec/0.2/`. A policy moves to `v0.2` once the entries below don't affect it, or once it's changed to follow them.
- Reports change: `locations` is required on every entry of `inputs`, `$refs` and `failed_items`, and is `[]` on the entries of `$well_formed`. For the second deployment in `{"deployments": [...]}`, an input that was `{"name": "approved_by", "value": null}` is now `{"name": "approved_by", "value": null, "locations": ["/deployments/1"]}`. Two reads with the same name and value are merged into one entry only when their locations match too, so a report that listed one entry may list two.
- [policy.version](syntax.md#policies) takes an optional `-dev` after the version, which `main` uses until a version is released, like `v0.2-dev`. `v0.2-beta` is still not a version.
- The `$applies` row of a `from` line with two or more conditions has what a check's row would have if the conditions were its assertions ([scope.failures](semantics.md#scope)): `failed_assertions`, with an entry for each condition that failed, in the order written, and `[]` when it passes. The violations keep it. Apart from `locations`, the row of a single plain condition, like `environment is "prod"`, doesn't change. For `from: deployments whose environment is "prod" and change_type is "emergency"`, the row of `d-2` in `{"deployments": [{"id": "d-2", "environment": "prod", "change_type": "standard"}]}` was:

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

- `it` is a word of the grammar ([sentence.words](syntax.md#words-a-field-cant-be-called)). A subject called `it` is written wrong for the requirements that use it ([sentence.path.it.name](syntax.md#paths)), and so is a `for` [alias](syntax.md#the-for-line) or a [part](syntax.md#parts) called `it`: rename it. A field called `it` is written `.it`, and the report prints `.it`. A bare `it` at the start of a path now reads the subject itself instead of its field `it`, so the report changes for a policy that has one.
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

- A row shows each entry of its `inputs` once ([row.inputs_once](semantics.md#what-a-row-shows)). A check that reads the same value twice, like `count of approvals plus count of approvals is 4`, listed it twice, as [tally.inputs](semantics.md#counts-and-sums-in-sentences) said. Such a row's `inputs` is now shorter.
- The row of a one-line `some` or `every`, of a `count of` or `sum of`, and an `$applies` row of a `from` condition list the value of each parent or `$input` path they compare with, as a plain check does ([walk.inputs](semantics.md#every-and-some), [tally.inputs](semantics.md#counts-and-sums-in-sentences)), and never the value of a `for` alias. They list the subject's own part they compare with too, with its `part` tag ([parts.tag](semantics.md#parts)). For the check `some commits.author is artifact.owner` the row's `inputs` held only `{"name": "commits[].author", "value": ["bob", "ann"], ...}`, and now `{"name": "artifact.owner", "value": "ann", ...}` comes before it. For `some commits.author is w` it now has `{"name": "w", "value": "ann", "part": {"id": null, "name": "w"}, ...}`. Under a `for` line, a `count of` or `sum of` lists the parent values its `whose` reads, and its own list when that list doesn't start at the alias ([for.inputs](semantics.md#for)). Such rows' `inputs` gain those entries.

  Under a `for` line, a [walk](semantics.md#every-and-some), a `count of` or a `sum of` whose path reads through `named by` an alias also lists the part before the name, like `artifact.map` for `some artifact.map named by k is at least 1`, as [for.inputs](semantics.md#for) says, and its row's `inputs` gains that entry.

  A walk, `count of` or `sum of` whose right side or `whose` is named by a field of each item, like `some rows.n is at least artifact.nums named by key` or `count of rows whose n is at least artifact.nums named by key`, also lists the part before the name, `artifact.nums`, and never the path it names ([walk.inputs](semantics.md#every-and-some)), and its row's `inputs` gains that entry.
- A check can walk any number of lists: the limit of three list walks per check is gone. What's limited is the path after `every`, `some`, `count of` and `sum of`, which takes ten steps at most, wherever it stands ([sentence.walk.steps](syntax.md#every-some-and-whose)). Policies and reports that stay under it don't change.
- A `for` alias or a part can't be named like a subject or like a part ([sentence.for.alias](syntax.md#the-for-line), [parts.alias](syntax.md#parts)). It's written wrong with `<alias> can't be an alias: it's a subject's name` or `<alias> can't be an alias: it's a part of <subject>`, which names the subject that declares the part and quotes a name with a space in it. The new cases in `cases/parts` pin it.

  0.1 read these, so a policy that has one is now written wrong, and the alias or the part needs renaming:

  - an alias named like a subject, like `for: every commits as commit` in a policy that has a `commit` subject
  - an alias or a part named like a part of a parent or grandparent subject
  - a part named like a subject that isn't its parent or grandparent

  Some of them read the wrong value in `ergo.rego` 0.1.0, see "A `for` alias named like the parent subject…" under Fixed.

  0.1 already wrote these wrong, with `alias given twice`, and they only get the new message: an alias named like a part of the check's own subject, and a part named like its parent or grandparent subject or like a part kept from a subject it [narrows](syntax.md#subjects). The same alias on two items of a `for` line is still `for: <x> is given twice`.
- A `count of` or `sum of` on the right of a phrase that starts at a `for` alias with ten names after it, like `x.n is count of x.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` with `for: every xs as x`, is written wrong ([sentence.walk.steps](syntax.md#every-some-and-whose)), because the alias is a step, as it already was on the left. 0.1 read it correctly, so its path needs to be shorter. Its requirement now has only a failing `$well_formed` row.
- Under a `for` line, `named by <alias>` on the right of a walk reads the alias, even when each item has a field with the same name ([sentence.path.start](syntax.md#paths)). `ergo.rego` 0.1.0 read the item's field, so with `for: every keys as k`, `some rows.n is at least artifact.nums named by k` on the row `{"n": 1, "k": "k2"}` and the key `k1` failed as `value`, and now passes. `named by .k` doesn't parse, so the item's field can't be read there.

### Fixed

- A `from: every $input...` line with ten steps after `$input` reads, because `$input` isn't a step ([sentence.walk.steps](syntax.md#every-some-and-whose)). It was written wrong, with `every over more than ten steps isn't supported yet`, because `ergo.rego` counted `$input` there but not in a check. Such a line now gives rows in place of a failing `$well_formed` row.
- A `count of` or `sum of` over more than ten steps on the right of a phrase, like `n is count of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11`, or in a `whose`, an `any_of` option or after `plus`, is written wrong, as it is on the left. It was read, and failed every subject as `unusable` with a count of `null`. The report now has a failing `$well_formed` row in their place. The one such check that read correctly in 0.1 is under Changed.
- A walk through a part over ten steps in all, like `every x.z is 1` with the part `x` set to a path of ten names, is written wrong ([sentence.walk.steps](syntax.md#every-some-and-whose)), because the part's own path counts in place of its alias. It was read, and failed every subject as `unusable`. A part that isn't walked is not limited. Its requirement now has a failing `$well_formed` row in place of those rows.
- A walk that starts at a `for` alias holding `null` fails as `null`, as [walk.lists](semantics.md#every-and-some) says. `ergo.rego` failed it as `absent`. The new case in `cases/for` pins it. The row's `cause`, and its failed item's, change from `absent` to `null`, and the failed assertion lists what the walk read, like `c.files` as `[]` with no location.
- A position at the start of a path reads the subject or a `for` alias as a list ([path.not_an_object](semantics.md#reading-a-path)), so `first of b` on a `for` alias holding `["x", "y"]` reads `"x"`, where `ergo.rego` failed it as `not_an_object`. The new case in `cases/for` pins it. Such a check can now pass, and an empty list fails as `absent` where it failed as `not_an_object`.
- A walk reads a parent through a `for` alias on its right side, like `some rows.n is at least artifact.nums named by k`, as a `count of` does ([walk.some](semantics.md#every-and-some)). `ergo.rego` failed it as `absent` even when the parent had the name. The new cases in `cases/walks` pin it. Such a walk now passes or fails on the values it compares.
- A `for` alias named like the parent subject or like a parent's part read the parent where the item lacked the field, so a check could pass on an item that didn't have the value: with `kid` read from `b.kids` and `for: every xs as b`, `b.id is "b1"` passed on the item `{"v": 1}`. Such a policy is now written wrong, see "A `for` alias or a part can't be named…" under Changed.
- A second item of a `for` line that starts at a parent, like `every artifact.ps.w as x`, is named with the parent's whole name, `artifact.ps.w[]` ([for.inputs](semantics.md#for)), where `ergo.rego` cut off its first letter, `rtifact.ps.w[]`. When it starts at a parent's part, its entry has the part's tag ([parts.tag](semantics.md#parts)), like `"part": {"id": null, "name": "artifact.ps"}`, which `ergo.rego` left out.
- A second item of a `for` line that starts at a parent's part, like `every artifact.ap.w whose t is k as x` where `artifact` has `has: {ap: ps}`, named its failed items with an internal marker, like `item 2 of "{\"alias\":\"ap\",\"n\":1,\"of\":\"artifact\",\"old\":false}".ps.w`. They're named with the part's alias, `item 2 of artifact.ap.w`, as its entry `artifact.ap.w[]` in `inputs` is ([for.failed_items](semantics.md#for)). `ergo.rego` printed the marker. The new cases in `cases/for` pin it. The `item` and `path` of those failed items change.

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
