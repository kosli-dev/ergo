# How checks are written as sentences

Draft 0.1, a proposal from [#174](https://github.com/kosli-dev/ergo/issues/174). This file says how a check written as a one-line sentence, like `approved_by is not empty`, reads into the [model](semantics.md#the-model-of-a-check), what counts as written wrong, and how the report prints it. What a check means once it's read is in [semantics.md](semantics.md), as for today's syntax in [syntax.md](syntax.md).

[`sentences-corpus.md`](sentences-corpus.md) has every check from sdlc-policies, the server's demo and npm-bump policies, pr-reviewer, ergo's examples and Tore's DEV controls written both ways. Every sentence in it parses exactly one way with the phrases below. The phrases, the tally and the misfits come from it.

`ergo.rego` runs a check written as one or more sentences that start with a path, for every phrase, joined with `and` or listed under `assert`. It runs a `for` line before them too, but doesn't check the limit of three list walks in [sentence.for.depth](#the-for-line) yet. It runs `from` lines and string `id`s too, and chains up to three subjects deep. It runs every case in `spec/cases`, and `known_differences` in `spec_test.rego`, which lists the cases it fails, is empty. It doesn't run every form of a sentence, though: not `last of`, and not a `count of`, `sum of` or `plus` or an elapsed time in the phrase of an `every` or `some`, and no case pins them yet, see [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet). Where the spec says a form runs, `ergo.rego` reports it as written wrong, with `isn't supported yet` in its message. In a `from` line or an `id`, `named by` a bare word is written wrong, with `unknown name <word>`, because there's no subject to read it from yet, and so is a `for` name used before its item gives it. A sentence can't be an `any_of` option or a substitute yet, and is written wrong there with `invalid check`.

## The shape of a sentence

**[sentence.check]** A check in a requirement's `checks` can be a sentence, or an object with the sentence under `assert` and optionally `description` and `meta`, which the report copies as it does for any check:

```yaml
checks:
  approved: approved_by is not empty
  signed:
    description: Every commit is signed
    assert: every commits.signed is true
```

An object with `assert` and any other field but `op` is written wrong, with `unknown field <name>`, and an `assert` that isn't a string or a list of strings is written wrong, with `invalid assert`, or with `empty assert` for an empty list. A problem with one line of a list of two or more starts with the line's number, like `line 2: unclosed quote at column 6`. An object without `assert`, or with `op`, is a check in the syntax of [syntax.md](syntax.md), so a custom operator can still take a parameter called `assert`. The report's entry for a sentence check has its `description`, its `meta` and its `expression`, and `$refs` for each `$params` or `$input` path it reads after `named by`, after a phrase that takes a list, or after `contains` or `does not contain`.

**[sentence.line]** A check, a filter, or one condition of a `whose`, is one line. It holds one assertion: a thing, then a phrase, then the phrase's arguments.

```
approved_by is not empty
environment is "prod"
every commits.verified is true
every review.incidents.action_ticket, if any, is not empty
some approvers.username whose state is "APPROVED" is in $params.internal_staff
count of findings whose source is "claude" is claude_found
sum of stages.usd whose kind is "model" equals total_usd within 0.01
```

**[sentence.forms]** The thing is one of:

- a path, as in `approved_by is not empty`
- `every <path>` or `some <path>`, optionally with `whose`, and the assertion is about each item the path ends at
- `count of <path>` or `sum of <path>`, optionally with `whose`, and the assertion is about the number
- a path, a `count of` or a `sum of` joined to more terms with `plus`, as in `count of records plus capped is findings_in`
- `<unit> elapsed from <path> to <path>`, alone, and the assertion is about the number of units between the two times

A check that walks two lists, or compares an item with its subject, puts the walking on a [`for` line](#the-for-line) and keeps the assertion flat.

**[sentence.flat]** The grammar is flat, because Rego can't recurse. So:

- one assertion per sentence
- one `every`, `some`, `count of` or `sum of` per assertion, and only at its start. A second one in the same assertion goes on a `for` line
- `whose` holds one or more conditions joined by `and`, and each condition is a path and a phrase, never another `every` or `whose`. A condition can start with `count of` or `sum of`, like `whose count of findings is at least 1`, because that's still one condition with a phrase. Its path has no `whose` of its own
- `and` does two jobs and nothing else: it joins the conditions of a `whose`, and it joins whole assertions, see [sentence.assert.list](#the-shape-of-a-sentence). Each side of an `and` is a whole condition or a whole assertion, so the result is a flat list, not a tree. An `and` never joins a `whose` to its assertion
- no `or`, and no brackets except the lookups in [sentence.path.brackets](#paths)

"Or" is an `any_of` in the policy around the sentence, because each option has a name and the report says which one passed. Every expression language gets asked for `or` and brackets, and the answer here is no.

**[sentence.assert.list]** `assert` can be a list, or one line with `and` between assertions. Both mean the same: each assertion starts from the subject, or from the `for` names, whether it's on its own line or after an `and`, see [sentence.assert.and](#the-shape-of-a-sentence). The report shows the list form whichever was written, and its `expression` joins the lines with `and`, so a failed row can say which line failed. Its row is one row for the check, and says which ones failed in `failed_assertions`, see [all_of.failed_assertions](semantics.md#all_of):

```yaml
peer_approval:
  description: A peer approved the pull request after its last commit
  for: some approvers whose state is "APPROVED" as approver, every commits as commit
  assert:
    - approver.username does not equal author
    - approver.timestamp is after commit.timestamp
```

**[sentence.assert.and]** An `and` between assertions means exactly what a new line under `assert` means. A one-line `every` or `some` ends at the `and`, and the assertion after it starts from the subject again, or from the `for` names. So in `every items.price whose kind is "a" is at least 2 and owner is "x"`, `price` is read on each item and `owner` on the subject. Any assertion can start with `every`, `some`, `count of` or `sum of`, so `state is "MERGED" and every commits.verified is true` is two assertions on one line. A list and the joined line never read differently, so the report's `expression`, which joins the list with `and`, is always a sentence the policy could have written. The `and` between assertions can't be confused with the `and` of `whose` or of `between`: the tokenizer reads `every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"` one way.

## Paths

**[sentence.path.string]** A path is keys joined by `.`, like `git_commit_info.sha1`. A key is written bare when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` and `-`, so Kosli's `secrets-scan`, `pull-request` and `coverage-verification` need no quotes. Any other key is quoted as a JSON string, like `metadata.labels."app.kubernetes.io/name"`, and so is any key with a `$` in it, like `"$schema"` or `"foo$bar"`. The report prints keys by the same rule, so `$` only ever starts `$params` or `$input`, and a path from a row can be pasted into a policy.

**[sentence.path.start]** A bare first key is a field of the subject. Inside `whose`, and in the argument of a one-line `every` or `some`, it's a field of the item instead (see [sentence.argument.item](#every-some-and-whose)). An alias given by `as` on a `for` line is a bare word too, and it shadows a field with the same name, the subject's or an item's, except on the left side of a `whose` (see [sentence.for.scope](#the-for-line)). A part's alias shadows a field of the subject (see [parts.shadow](semantics.md#parts)). A first key written with a dot, like `.approver`, is always the field, never an alias. `$params` starts at the params and `$input` at the input. Any other `$<word>` is written wrong, with `unknown name $<word>`.

**[sentence.path.part]** A part of the subject, declared with `has` (see [parts.syntax](syntax.md#parts)), is read by its alias as a bare first key, wherever a bare first key reads the subject ([parts.where](semantics.md#parts)), and gives the rows of the path it stands for ([parts.swap](semantics.md#parts)). Inside `whose` and in the argument of a one-line `every` or `some` it isn't read, because there the first key is the item's. `named by` a bare word that is a part's alias is written wrong, with `named by <alias> reads a part, which isn't supported yet`, because it would otherwise read the subject's field of that name. A part's own path is written as a `from` line's path is, so it never starts with an alias.

**[sentence.path.index]** `item 3 of items` reads the third item of `items`, counting from 1, and `first of items` and `last of items` read the ends. The path after `of` is the whole rest of the path, so `item 3 of pull_request.commits` picks the third commit, and a field of that item has no word form: write `pull_request.commits[2].sha` with brackets, which count from 0 as [sentence.path.brackets](#paths) says. `item 0 of items` is written wrong. The report prints the word form when the position ends the path, so `commits[2]` prints as `item 3 of commits`, and prints the brackets when a key follows them. No policy in the corpus needs a position.

**[sentence.path.argument]** The left side of a sentence is always a path. The right side can be a value or a path, and these rules decide which:

- A quoted string on the right side is text. `is "prod"` compares with the text prod, never with a field called `"prod"`.
- A word of the grammar on the right side is never a field name (see [sentence.words](#words-a-field-cant-be-called)). `is empty` is the phrase, `is true` is the value.
- A field with one of those names is written with a dot in front: `is .empty`, `is .true`. The dot is allowed on any field, so `equals .total_usd` means `equals total_usd` when no alias is called `total_usd`, and the report prints it only where it's needed. Where an alias has the same name, the dot is how to read the field (see [sentence.for.alias](#the-for-line)).
- A key that has to be quoted, like `$schema`, is written with the dot too: `is ."$schema"`.

**[sentence.path.dynamic]** `<path> named by <reference>` reads the key that the reference holds, as a ref step does today, and the path can go on after it: `artifacts_statuses named by $params.artifact_name.attestations_statuses`. The reference is `$params` or `$input` plus one key, or one bare key. A bare key is an alias from a `for` line, like `persona_blob_shas named by persona`, or else a field, read where a bare first key would be read (see [sentence.path.start](#paths)): `$params.max_days_by_severity named by severity` reads the subject's `severity`, and inside a `whose` the item's. Without that limit, `named by $params.a.b` could end the reference after `a` or after `b`, and the tokenizer found 24 lines in the corpus that read two ways because of it.

**[sentence.path.brackets]** Brackets are the other spelling: `artifacts_statuses[$params.artifact_name]`, `persona_blob_shas[persona]`, and `items[2]` for a position. In brackets the type decides, as in JSON: a string picks a key and a number picks a position. The report prints the word form.

**[sentence.path.keys]** In `from`, `<path> named by each of <list>` makes each listed key a subject, as `keys` does today: `artifact.attestations named by each of $params.required_scans`. There is no bracket form for it, because `a[x]` picks one thing in every language, and a parameter meant to be one name that arrives as a list would turn one subject into several instead of failing. `from` doesn't name its subjects: the checks that used `each_as` names have a `for` line, where the subject's fields are bare.

## Subjects

**[sentence.subject.from]** A subject's `from` takes the shape of a `for` item without `as`, and without `every` unless it reads every list along its path ([sentence.subject.every](#subjects)): a path, optionally `named by each of` a list, optionally `whose` with conditions joined by `and`. `applies_to` goes. The conditions read the subject, as a `whose` reads its item:

```yaml
subjects:
  emergency change:
    from: deployments whose environment is "prod" and change_type is "emergency"
    identified_by: id
```

**[sentence.subject.every]** `every` in front of a `from` line's path walks every list along the path, the last one included, as `every` does in a check ([sentence.every.walk](#every-some-and-whose)), and each value it ends at is a subject: `from: every artifacts.pull_requests` makes every pull request of every artifact a subject. They're one flat list, independent of the artifacts: their rows have no `in`, and they're counted once ([subjects.every](semantics.md#requirements)). Without `every`, a path through a list reads nothing, as before. `every` can't go with a path that starts at another subject's name, which is written wrong with `every can't go with a from line that starts at another subject yet`, or with `named by each of`, which is written wrong too, because the names would be read under every list item with no `in` to tell them apart. A child subject does that one parent at a time. Like a check's walk, it takes ten steps at most, and an eleventh is written wrong.

**[sentence.subject.condition]** A condition in that `whose` is like any `whose` condition: a path and a phrase, or a `count of` or `sum of` and a comparison. pr-reviewer has six, like `whose count of compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is at least 1`.

**[sentence.subject.applies]** The `$applies` row stays. Its `expression` is the conditions in the order written, each in the report's spelling, joined with ` and `, like `environment is "prod" and change_type is "emergency"`, and its `inputs` hold each path they read. A subject a condition can't decide about, like a deployment with no `change_type`, fails the requirement as `absent` rather than dropping out of it. The filter's name and its description go.

**[sentence.subject.chain]** A subject can start from another subject, by that subject's name, and is then a child subject of it: `from: artifact.attestations_statuses named by $params.pr_attestation_name.pull_requests`, where `artifact` is a subject of the same policy. Its rows carry the parent's id under `in`, like `{"type": "pull request", "id": "…/pull/8", "in": {"artifact": "sha256:…"}}`, `min_subjects` counts per parent (see [subjects.chain.count](semantics.md#requirements)), and a check reads the parent by its name, like `artifact.name`. In the corpus, four `from` lines descend this way, all from an `artifact` subject: sdlc-policies 0007 and 0008, the server's copy of 0008, and server 0010.

**[sentence.subject.quoted]** A subject whose name has a space starts a chain with the name quoted, like any key with a space: `from: "production deployment".pull_requests`. YAML won't take a plain value that starts with a quote and goes on after it, so the whole line goes in single quotes: `from: '"production deployment".pull_requests'`. The same goes for any sentence that starts with a quoted key. No policy in the corpus needs it, though 19 of its subject names have a space. The tokenizer reads `"production deployment".pull_requests` one way, as a chain from that subject.

**[sentence.subject.narrow]** A chain can narrow instead of descending: `from: defect whose severity is "critical" and status is one of "open", "in_progress"` is a `defect` with two more conditions. Its rows are rows of the parent, with the same id and no `in`. This is today's `of`. DEV-0409 and DEV-0410 use it.

**[sentence.subject.depth]** Each level of walking is written out in Rego, not recursion, so the levels from the input to the assertion have a fixed ceiling: three list walks, see [sentence.for.depth](#the-for-line). That's today's too, one in `from` and two in a check. A chain can be three subjects deep, one more than the corpus needs, see [subjects.chain.levels](semantics.md#requirements). No chain in the corpus is more than two subjects deep, and no check in it walks more than three lists.

**[sentence.subject.own]** A subject's own name in its own `from` is the input field, never the subject, so sdlc-policies 0004's `lockfile` subject can have `from: lockfile whose status is "COMPLETE"`. Any other subject's name starts a chain. `$input.artifact` reaches the input field `artifact` even when a subject named `artifact` exists. The tokenizer applied these two rules to every `from` line in the corpus and found exactly the six chains it has.

**[sentence.subject.short]** A subject with no `from` reads the input field of its own name. It can still have `identified_by`:

```yaml
subjects:
  artifact:
    identified_by: artifact_fingerprint
  lockfile:
    from: lockfile whose status exists and status is "COMPLETE"
    identified_by: name
```

The map is the only way to write `subjects`, and a simple subject is a name with nothing under it.

## Values

**[sentence.value.scalar]** A value is written as JSON writes a scalar: a string in double quotes, a number, `true`, `false` or `null`. A string can also be in single quotes, which keeps backslashes as written, so a regular expression doesn't need them doubled: `'^\s*FROM'` is `"^\\s*FROM"`. Inside single quotes, `\'` is a quote and `\\` a backslash. A number has to be `0` or have a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, as a number in a policy does, so `x is at least 1e400` is written wrong.

**[sentence.value.list]** A list of values is the values separated by `, `, with no brackets: `is one of "staging", "prod"`. A value can hold a comma, `matches "^fix(, |: )"`, because commas inside quotes don't separate.

**[sentence.value.path]** An argument that isn't a value is a path. So `is "prod"` compares with text and `equals total_usd` with a field, which is what today's `equals` and `compare` split was for. `is` before a field is read the same, and printed as `equals`.

## Words a field can't be called

**[sentence.words]** These words are read as part of a phrase, a quantifier, a position or a value, never as the first key of a path written bare: `a`, `after`, `an`, `and`, `as`, `at`, `before`, `between`, `count`, `days`, `each`, `empty`, `equal`, `every`, `false`, `first`, `hours`, `in`, `item`, `last`, `less`, `minutes`, `more`, `named`, `not`, `null`, `of`, `on`, `one`, `or`, `plus`, `seconds`, `some`, `sum`, `to`, `true`, `weeks`, `whose`, `within`. Without this, `x is empty` could also compare `x` with a field called `empty`, `x is true` with a field called `true`, and `count of x is 1` could start from a field called `count`. A field with one of these names is written `.empty`, on either side of the sentence. The rule is the same on both sides so that it's one rule, and so that a parser never has to know which side it's on to read a key. Keys after the first are never words of the grammar, so `review.count` needs no dot.

## `every`, `some` and `whose`

**[sentence.every.walk]** `every <path>` walks into every list along the path, the last one included, and the assertion applies to each value it ends at. `every pull_requests.commits.author` reads the author of every commit of every pull request, and `every branches matches "^release/"` reads each branch of a list of strings. It passes when every value passes. Because the last list is walked too, `every pull_requests.labels is not empty` checks each label, not that each pull request has labels. So `contains`, `does not contain`, `contains all of` and `contains none of` after `every` or `some` would ask each label whether it holds a value, which a string never does, and they're written wrong, with a message that says to put the walk on a `for` line. No policy in the corpus puts them there. And because a bare name on the right of a one-line `every` is the item's, `every $input.artifact.developers does not equal tested_by` reads `tested_by` on each developer string, which isn't what it means. To compare each string with a field of the subject, use a `for` line: `for: every $input.artifact.developers as developer` with `assert: developer does not equal tested_by`. `$input.artifact.developers does not contain tested_by` looks like the same check without the `for`, but it isn't: it passes an empty list, which `every` fails. That's why DEV-0407 keeps its `for` line.

**[sentence.every.empty]** `every` over an empty list fails with cause `value`, because no commits isn't proof that every commit is signed. Over nested lists, each inner list must have an item too, as `each` does today.

**[sentence.every.if_any]** `every <path>, if any, <assertion>` passes over empty lists, at every level it walks. A list that's missing, `null` or not a list still fails as `absent`, `null` or `unusable`. `if any` goes after the path and its `whose`, between commas, right before the phrase: `every items whose kind is "a", if any, is at least 2`. That's where it reads as "every item, if there are any left", and a parser can't take it for a value, because a value is never `if any`. On a `for` line it goes before `as`: `every commits, if any, as commit`. With `some`, it's written wrong, with `if any can't go with some`, since "some approver, if any" would let an empty list pass a check that asks for at least one.

**[sentence.some.walk]** `some <path>` walks the same way, and passes when at least one value passes. An empty list fails with `value`.

**[sentence.whose.item]** `whose` keeps the items that pass every one of its conditions. Its paths start at the innermost item the quantified path walks, the one that holds the field the path ends at, and the assertion is about the value the path ends at. In `some approvers.username whose state is "APPROVED" is in $params.internal_staff`, `state` is read on each approver and `username` is what's checked.

**[sentence.whose.undecided]** An item that a condition can't decide, because a field it reads is missing, `null` or the wrong type, isn't left out. Under `every`, `count of` and `sum of`, the check fails with that item's cause, as `count ... whose` does today. Under `some`, it counts as an item that failed: another item can still pass the check, and if none does, the check fails with the first cause among the items, as `any` does today. `exists` and `does not exist` are the exception, because a missing field is their answer.

**[sentence.whose.every]** Under `every`, an item that `whose` leaves out isn't checked. When `whose` leaves no items, the check fails with `value`, unless it has `if any`. No policy in the corpus uses `every ... whose` yet.

**[sentence.argument.item]** In a one-line `every` or `some`, a path in the argument starts at the item too, so the item can be compared with its own fields: server 0007's `some approvers.timestamp whose state is "APPROVED" and username does not equal pr_author is after last_commit_timestamp` reads both from each approver. #174 says the same: in a one-line `every` or `some`, every bare name is the item's, in `whose` and on the right side alike, except a `for` alias on the right side, which is the alias (see [sentence.for.scope](#the-for-line)). It ends at an `and`, see [sentence.assert.and](#the-shape-of-a-sentence). To compare an item with the subject, use a `for` line. To reach the input, start with `$input`.

**[sentence.argument.subject]** After `count of` and `sum of`, the assertion is about one number for the subject, so a path in the argument starts at the subject: in `sum of stages.usd equals total_usd`, `total_usd` is the subject's.

## Derived values

**[sentence.derived.count]** `count of <path>` walks the path as `every` does and counts the values it ends at, so `count of findings` is the number of findings. With `whose`, it counts the items that pass.

**[sentence.derived.sum]** `sum of <list>.<field>` adds the field up across the items. With `whose`, only the items that pass. A sum over no items is 0. Numbers are added as decimals, so `0.1 plus 0.2` is `0.3`.

**[sentence.derived.plus]** `<term> plus <term>` adds numbers. A term is a path, a number, a `count of` or a `sum of`. A `whose` ends the terms, so `count of x whose n is m plus k is t` reads one way: `m plus k` is the condition's right side, and nothing is added to the count. To add to a count that has a `whose`, put the `count of` last: `k plus count of x whose n is m is t`. On the right side of a phrase, a `count of` or `sum of` takes no `whose` at all, because `x is count of y whose a is 1 and b is 2` could be one assertion with two conditions or two assertions. Count on the left and compare on the right.

**[sentence.derived.elapsed]** `<unit> elapsed from <path> to <path>` is a number: the time from the first path to the second, in `seconds`, `minutes`, `hours`, `days` or `weeks`, which are 1, 60, 3600, 86400 and 604800 seconds. It's rounded down to 6 decimal places, so 36 hours is `1.5` days and one second is `0.000011` days, and every runtime prints the same digits. Each path is read as any other path in the sentence is, and `to` between them is a word of the grammar, so a field called `to` is written `.to`. Both values must be times as [time.format](semantics.md#compare_time) says, both RFC 3339 strings or both numbers, read as seconds to the nearest microsecond. A number must be from -9000000000 to 9000000000, about the years 1684 to 2255, so a time in milliseconds fails instead of being read as seconds. Anything else, and one string with one number, fails as `unusable`, a missing path as `absent` and a `null` one as `null`, and the worst of the two wins, as for `is before`. If the second time is before the first there is no sensible number, so the check fails as `value`. Two equal times are 0. The phrases that follow are the ones [sentence.derived.compare](#derived-values) lists:

```yaml
within_limit: days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity
```

It's a number like a `count of`, so it goes where one does: at the start of an assertion, on its own line of a list under `assert` or after the `for` line, as a term of `plus`, as the right side of a phrase, in the `whose` of a `count of`, a `sum of` or an `every`, and before `is between`. In a `whose`, an item whose end is before its start has no number, so it's left out, as any item whose condition fails with `value` is. After `every` or `some` and in a `from` line, the spec doesn't say yet, see [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet). Months and years have no fixed length, so `months elapsed from` and `years elapsed from` don't read as this phrase.

**[sentence.derived.compare]** A derived value only goes with `is`, `equals`, `is not`, `does not equal`, `is ... within`, `equals ... within`, `is at least`, `is at most`, `is more than`, `is less than` and `is between`. `count of approvers is empty` is written wrong, and so is `days elapsed from a to b is empty`.

## The `for` line

**[sentence.for.line]** A check can have a `for` line before its `assert`. It holds one or two items separated by `, `, and each item is `every` or `some`, a path, an optional `whose` with `and`, and `as` an alias:

```yaml
peer_approved:
  description: Someone other than the author approved every pull request
  for: every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver
  assert: approver.username does not equal pr.author
```

Items nest left to right, so a later one can use an earlier alias, as `pr.approvers` does. A third item is written wrong, because two is the one level of nesting Rego gives today.

**[sentence.for.depth]** A check walks three lists at most, from the input to its assertion, counted as list walks and not as subjects. Walks in `from`, in a parent subject's `from`, on the `for` line, in a one-line `every` or `some`, and in a `count of` or `sum of`, in a `whose` too, all count, and a fourth is written wrong. A `count of` or `sum of` counts because it reads every item of its list, as `every` does, so `for: every pull_requests as pr` with `assert: count of pr.reviews is at least 2` walks two lists. sdlc-policies 0007's peer approval reaches the limit: pull requests in its `from`, then approvers and commits on its `for` line. Its `artifact` parent picks one artifact by name and walks no list.

**[sentence.for.scope]** In `assert` and in a later item, a bare first key is the subject's field and an item is reached by its alias. Inside an item's own `whose`, a bare key is that item's field. So in `for: some approvals whose role is "qa" as approval` with `assert: approval.approved_at is before started_at`, `role` is the approval's and `started_at` the subject's.

The left side of a `whose` is the item's field even when an alias has the same name, because "deployments whose env is prod" can only mean the deployment's `env`. On the right side of a `whose`, and on the right side after a one-line `every` or `some`, a bare name that's an alias is the alias, and the item's field with that name is written with a dot. With `for: every environments as env, …`:

| sentence                                             | reads                                              |
| ---------------------------------------------------- | -------------------------------------------------- |
| `some deployments whose env is "prod"`               | the deployment's `env`                             |
| `some deployments whose environment equals env.name` | the deployment's `environment`, the alias's `name` |
| `every deployments.region does not equal env`        | each deployment's `region`, the alias `env`        |
| `every deployments.region does not equal .env`       | each deployment's `region`, the deployment's `env` |

**[sentence.for.alias]** An alias is a bare word that isn't `params`, `input` or a word of the grammar, like `every`, `as` or `empty`. For the rest of the check it shadows a field with the same name, the subject's or an item's, everywhere but on the left side of a `whose` ([sentence.for.scope](#the-for-line)). A dot in front, like `.env`, reads the field. An alias given twice is written wrong. So is one that is also the alias of a part of the subject, with `alias given twice`, and so is a bare word after `named by` that no `for` line gives, with `unknown alias <word>`.

**[sentence.for.fail]** Each item fails closed as a one-line `every` or `some` does: `some` over an empty list fails, `every` over one fails unless the item says `if any`, a missing or non-list path fails as `absent`, `null` or `unusable`, and an item a `whose` can't decide fails the try with its cause.

**[sentence.for.comma]** The `, ` between items can't be confused with the `, ` between values, because the next item starts with `every` or `some` and a value can't. The tokenizer reads `for: some approvals whose role is one of "qa", "dev" as approval, every commits as commit` one way.

**[sentence.for.assert]** A `for` line can have several assertions under `assert`, as [sentence.assert.list](#the-shape-of-a-sentence) says. sdlc-policies 0007's peer approval needs that: an approver who approved, isn't the author and approved after every commit.

## The grammar

**[sentence.grammar]** [`sentences.abnf`](sentences.abnf) is the grammar, in ABNF as RFC 5234 writes it. It says which strings are a check (`check`), a `for` line (`for-line`) and a `from` line (`from-line`), and it's what an implementation parses. The phrases below say what each form means. When the two disagree, the grammar is the syntax and the phrase is wrong.

Some rules can't be said in ABNF, so they're here:

- A bare first key is never a word of the grammar, see [sentence.words](#words-a-field-cant-be-called). A `for` alias isn't one either, nor `params` or `input`.
- Which bare first key is a subject's field, an item's field, a `for` alias or a subject's name depends on where the sentence is, see [sentence.path.start](#paths), [sentence.for.scope](#the-for-line) and [sentence.subject.own](#subjects).
- A `for` line has two items at most, and a check walks three lists at most, see [sentence.for.depth](#the-for-line).
- `is`, `equals` and `is equal to` read the same, as do `is one of` and `is in`, and the report picks the spelling, see [sentence.print.canonical](#printing-the-sentence).
- A run of spaces between two words reads as one, and a list of values can be written with or without a space after each comma. The report prints one space and `, `.
- The bounds of `is between` are in order, a string in `matches` is a valid regular expression, and a `for` alias is given once, or the sentence is written wrong.

A grammar word only needs quoting or a dot when it's the first key, so `a`, `an`, `in`, `on` and `of` cost nothing in ordinary paths.

## Phrases

Each phrase is a plain pattern: fixed words with gaps. One line is one form, and a negated form is a line of its own. An implementation matches them its own way. In Rego that's one regular expression per line, matched with `regex.find_all_string_submatch_n`, as ergo does today. No library or notation is needed.

The gaps:

| gap                | holds                                                                                                          |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| `<path>`           | a path. On the left of a comparison, also a `count of`, a `sum of` or terms joined with `plus`                 |
| `<value>`          | one value: text in quotes, a number, `true`, `false` or `null`                                                 |
| `<values>`         | one or more values separated by `, `                                                                           |
| `<value or field>` | a value, or a path, or terms joined with `plus`. See [sentence.value.path](#values) for how to tell them apart |
| `<list>`           | values separated by `, `, or a path to a list                                                                  |
| `<number>`         | a number                                                                                                       |
| `<type>`           | `list`, `string`, `number`, `boolean` or `object`                                                              |

"Missing", "`null`" and "wrong type" say what a check does when a value it reads is in that state. Everything a phrase reads fails that way, the path on the right and any reference included. Every failure that isn't `value` makes a filter fail the requirement instead of ruling the subject out.

**[sentence.phrase.is]**
```
<path> is <value>
<path> equals <field>
<path> is not <value>
<path> does not equal <field>
```

The field equals, or doesn't equal, what's on the right, as [value.equal](semantics.md#values) says. `is not null` is written wrong, with `"is not null" is written "exists"`, because it could only fail: a field that's there and isn't `null` is a different type from `null`. `is`, `equals` and `is equal to` mean the same, and so do `is not` and `does not equal`. The report prints `is` and `is not` before a value, and `equals` and `does not equal` before a field, so a field on the right side shows as one: `environment is "prod"`, `subject_digest equals fingerprint`, `approver.username does not equal author`. Missing: `absent`. `null`: passes `is null`, otherwise fails as `null`. Wrong type: `unusable`, whatever is on the right, so a `whose` can't rule a subject out on a field of the wrong type. `is null` on a field that's there fails as `value`, because nothing else has the type of `null`.

**[sentence.phrase.within]**
```
<path> is <value> within <number>
<path> equals <field> within <number>
```

Two numbers at most that far apart. The number is 0 or more. A value before `within` that isn't a number is written wrong, with `"within" only compares numbers`, because the check could only fail. Missing: `absent`. `null`: `null`. Wrong type: `unusable`.

**[sentence.phrase.one_of]**
```
<path> is one of <values>
<path> is not one of <values>
<path> is in <path>
<path> is not in <path>
```

The field equals one of the values, or none of them. `is one of` and `is in` mean the same, and so do their negated forms, so either can take written values or a path. The report prints `is one of` before written values and `is in` before a path, usually `$params`: `type is one of "development", "test"`, `author is in $params.external_contributors`. Missing: `absent`. `null`: `null`, even when the values include `null`. Wrong type: `unusable`, for both. The values have one type, leaving `null` aside, so values of more than one type are written wrong, with `values of mixed types`, and a list read from a path whose values have more than one type fails as `unusable`. An empty list can't be written. A list read from a path that isn't a list fails as `unusable`, and an empty one fails `is in` as `value` and passes `is not in`.

**[sentence.phrase.exists]**
```
<path> exists
<path> does not exist
```

These are [`present`](semantics.md#present) and [`missing`](semantics.md#missing), and fail as those rules say. Mostly, a field that's missing or `null` fails `exists` with `value` and passes `does not exist`, and any value that's there passes `exists`, whatever its type. A path into params that weren't given fails both as `absent`, and a parent that can't hold the field fails both with the cause the path gives, like `unusable`.

**[sentence.phrase.empty]**
```
<path> is empty
<path> is not empty
```

`is empty` passes on `[]` and `""`. `is not empty` passes on a list with an item or a string with a character. Missing: `absent`. `null`: `null`. Wrong type, a number, a boolean or an object: `unusable`. This is wider than today's `empty` and `non_empty_string`, which each took one type. When the type matters, say it with [sentence.phrase.type](#phrases): `is a non-empty string`, or `is a list` as a second check.

**[sentence.phrase.type]**
```
<path> is a <type>
<path> is an <type>
<path> is a non-empty string
```

The field has that JSON type. Either article is accepted, and the report prints `an` before `object` and `a` before the rest. `is a non-empty string` is today's `non_empty_string`: a string with at least one character. Missing: `absent`. `null`: `null`. Wrong type: `value`, because checking the type is the phrase's job.

**[sentence.phrase.contains]**
```
<path> contains <value or field>
<path> does not contain <value or field>
```

The field is a list that holds the value, or doesn't. Missing: `absent`. `null`: `null`. Not a list: `unusable`. Wrong type: `unusable`, when the list's items and the value have more than one type, leaving `null` aside, so `labels contains 1` on `["1"]` can't rule a subject out. `does not contain` passes on an empty list.

**[sentence.phrase.contains_all]**
```
<path> contains all of <list>
<path> contains none of <list>
```

The field is a list that holds every value, or none of them. Missing, `null`, not a list and wrong type as `contains`. Values of more than one type are written wrong, with `values of mixed types`, and a list read from a path whose values have more than one type fails as `unusable`. An empty list written in the sentence can't be written, and one read from a path fails as `unusable`, because it would pass every list. `contains "a", "b"` on its own is written wrong, because it could mean all of them or any of them, so a list always takes `all of` or `none of`.

**[sentence.phrase.matches]**
```
<path> matches <list>
<path> does not match <list>
```

The field is a string that matches at least one of the regular expressions, or none of them. They aren't anchored. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A pattern that isn't a valid regular expression is written wrong when it's in the sentence, with `invalid pattern <pattern>`, and fails as `unusable` when it's read from a path.

**[sentence.phrase.field]** The thing after `is one of`, `is in`, `contains`, `does not contain`, `contains all of`, `contains none of`, `matches` and `does not match` can be a field as well as written values or a `$params` or `$input` path: `files contains all of gap_files`, `tested_by is in reviewers`, `$input.artifact.developers does not contain tested_by`. A field here is read like any field on the right of `is at least`: from the subject, from a name of a `for` line, or from the item in a one-line `every` or `some` and in a `whose`. The row's `passed` and `cause` are what the same sentence gives with the list read from `$params` holding the same value, whatever that value and the field are, and [compare.list](semantics.md#compare) says how. The field is read for each row, so it's in the row's `inputs` after the left side, as the right side of a `compare` is, and not in `$refs`.

**[sentence.phrase.starts]**
```
<path> starts with <value or field>
<path> ends with <value or field>
```

New, and unused in the corpus. Both sides are strings, and a written value that isn't one is written wrong, with `"starts with" takes text`, because the check could only fail. Missing: `absent`. `null`: `null`. Not a string: `unusable`.

**[sentence.phrase.order]**
```
<path> is at least <value or field>
<path> is at most <value or field>
<path> is more than <value or field>
<path> is less than <value or field>
```

Both sides are numbers, or both are strings. Missing: `absent`. `null`: `null`. Anything else, two types that differ included: `unusable`.

**[sentence.phrase.between]**
```
<path> is between <value> and <value>
```

A number from the first to the second, both included. The bounds are numbers, and the first isn't above the second, or it's written wrong. Missing: `absent`. `null`: `null`. Not a number: `unusable`. After a `count of`, a `sum of`, a `plus` or an elapsed time, it reads the number they work out, as [tally.between](semantics.md#counts-and-sums-in-sentences) says. Its `and` belongs to `between`, so `whose qty is between 1 and 5 and kind is "a"` has two conditions. An implementation that splits `whose` on ` and ` has to skip the one after `between <value>`.

**[sentence.phrase.time]**
```
<path> is before <value or field>
<path> is after <value or field>
<path> is on or after <value or field>
<path> is on or before <value or field>
```

Both sides are timestamps in the same format, both RFC 3339 strings or both numbers, as today's `compare_time`. A timestamp that isn't RFC 3339 fails the check rather than being compared as text. Missing: `absent`. `null`: `null`. Wrong type or format: `unusable`. A written value that isn't a time as [time.format](semantics.md#compare_time) says, like `"yesterday"` or `null`, is written wrong, with `"is before" takes a time or a number`, because the check could only fail. `is on or after` replaces `is not before`, a double negative the corpus used six times.

**[sentence.phrase.aliases]**
```
<path> is equal to <value or field>
```

Read as `is` or `equals`, and printed as one of them. With it in the grammar, every sentence in the corpus still has exactly one reading.

**[sentence.derived.fail]** `count of` and `sum of` over a list that's missing, `null` or not a list fail as `absent`, `null` or `unusable`. A number to add that's missing fails as `absent`, `null` as `null`, and anything else that isn't a number as `unusable`. `every` and `some` fail the same way on the list they walk.

## Written wrong

**[sentence.written_wrong.slot]** A sentence that doesn't parse is written wrong, as a check that can't be read into the model is today. Its rows fail with `ill_formed` and `$well_formed` lists it. Because the grammar is flat, the message can name the slot, what it expected and the column:

| sentence                                                 | `$well_formed` says                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `environment is "prod`                                   | `unclosed quote at column 16`                                                   |
| `every commits.signed`                                   | `nothing after the path at column 21: expected a phrase, like "is" or "exists"` |
| `sum of stages.usd equals total within`                  | `"within" needs a number after it`                                              |
| `some approvers, if any, is not empty`                   | `if any can't go with some`                                                     |
| `every pull_requests some approvers.state is "APPROVED"` | `two quantifiers in one sentence: put them on a for line`                       |
| `x is at least 1e400`                                    | `number out of range: 1e400`                                                    |

**[sentence.written_wrong.self]** A sentence that compares a path with itself is written wrong, because it could only pass or only fail. That's `is`, `equals`, `is not` or `does not equal` a field, with or without `within`, the order and time phrases, `starts with` and `ends with`, when the field on the right is read from the same place as the path:

- the same path, in an assertion or a `whose`, like `x is at least x` or `whose type equals type`
- after `every` or `some`, the end of the path walked, because the right side starts at the item ([sentence.argument.item](#every-some-and-whose)), like `every conditions.type equals type`

A name on the right that's a `for` alias reads the alias ([sentence.for.scope](#the-for-line)), so with `for: every zones as type`, `every conditions.type equals type` compares each condition's `type` with the zone, and isn't written wrong. `every conditions.type equals .type` is.

Most often the writer meant the subject's field. In a `whose` and after `every` or `some` it can't be reached, so the message says where to compare it:

| sentence                                                   | `$well_formed` says                                                                                                         |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `x is at least x`                                          | `x is compared with itself`                                                                                                 |
| `every conditions.type equals type`                        | `type is compared with itself: after every or some, a bare name is the item's, so compare with the subject's on a for line` |
| `for: some conditions whose type equals type as condition` | `for: type is compared with itself: in a whose, a bare name is the item's, so compare with the subject's under assert`      |

`contains`, `is in` and a right side with `plus` can go either way, so they're left alone.

`environment is prod` and `approved_by is empy` parse, as comparisons with a field called `prod` or `empy`, unless the subject has no such field. That's the one mistake the grammar can't catch, so the message for a missing field in an `is` argument should suggest quotes.

## Printing the sentence

**[sentence.print.canonical]** The report's `expression` is the sentence printed from its parse in one spelling: single spaces, `is` and `is not` before a value and `equals` and `does not equal` before a field, `is one of` before written values and `is in` before a path, no alias, a string in single quotes when it holds a backslash but no single quote, no two backslashes in a row, no backslash at the end and no control character, and in double quotes with JSON escapes otherwise, a dot in front of a field only where [sentence.path.argument](#paths) needs one or where an alias has the same name, numbers in their plain form, and values separated by `, `. Parsing the printed sentence reads the same check.

**[sentence.print.order]** `whose` conditions and assertions joined with `and` print in the order the author wrote them. The report stays byte for byte the same when the same policy runs again on the same input. That rule is for the same policy, not for two policies that mean the same: `A and B` and `B and A` print differently, because the order changes neither what passes nor the cause, and sorting would have to reach `assert` lists too, and could never reach `for` items, whose order is their nesting. A row's `inputs` stay sorted by name, as today, because they're values that were read, not a sentence.

**[sentence.print.same]** For a sentence written that way, the printed form is byte for byte what the author wrote. Every line in the corpus prints back unchanged, the regular expression `entry does not match '^[A-Za-z0-9._-]+\s*(>=|<=|~=|!=|<|>)'` included, because its single quotes are the canonical spelling.

## How this was checked

A throwaway tokenizer in JavaScript, outside the repo, turned each phrase above into a regular expression and tried every way to cut each line into a quantifier, a path, `whose` conditions, assertions joined with `and`, and a phrase. It counted every reading.

The corpus has 336 lines: 231 assertions, 14 `for` lines and 91 `from` lines. sdlc-policies 0004's `artifact` and its server copy have no `from` any more. With the rules in this file, which are the rules #174 now states, every line parses exactly one way. Without them, 194 lines parse more than one way:

| cause                                                                  | lines | rule that removes it                            |
| ---------------------------------------------------------------------- | ----: | ----------------------------------------------- |
| a quoted string could be text or a quoted key, `is "prod"`             | 84    | [sentence.path.argument](#paths)                |
| a grammar word could be a field, `is empty` against `is <field empty>` | 59    | [sentence.words](#words-a-field-cant-be-called) |
| `true`, `false` or `null` could be a field                             | 50    | both of the above                               |
| the reference after `named by` could end at more than one key          | 24    | [sentence.path.dynamic](#paths)                 |

Some lines have two causes. The tokenizer also applied [sentence.subject.own](#subjects) to every `from` line, and found the same six chains the corpus marks.

28 made-up lines test what the corpus doesn't reach:

- `count of x whose n is m plus k is t` read three ways until [sentence.derived.plus](#derived-values) was written. Under the grammar it reads one way, with `m plus k` inside the condition. A `for` item named `every` reads one way until [sentence.for.alias](#the-for-line) forbids it.
- `if any` with `some`, two quantifiers in one sentence, `count of ... is empty`, `whose count of reviews is empty` and the bare key `foo$bar` parse no way, as they should.
- `whose count of reviews is at least 1 and state is "open"` and `some orders.id whose sum of items.price is more than 100 is not empty` read one way.
- `every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"` reads one way, with `owner` on the subject. So do `state is "MERGED" and every commits.verified is true` and `every items.price whose kind is "a" is at least 2 and some items.owner is "x"`, two quantified assertions on one line.
- `format is in "spdx", "cyclonedx"` prints as `is one of`, `username is one of $params.internal_staff` as `is in`, `approved_by is not author` as `does not equal`, and `environment does not equal "prod"` as `is not`.
- `"production deployment".pull_requests` reads one way, as a chain from that subject.

Every line also prints back exactly as written, `from` lines included.

The ABNF came later, from these rules, and was checked the same way. A script turned it into a grammar for Lark, a Python parser whose Earley mode keeps every reading, and counted the readings of each of the corpus's 306 sentences, `for` lines and `from` lines. One made-up line that used a field called `a` was changed first, since `a` is a grammar word. Two rules can't be written in ABNF and were applied after parsing: a bare first key is never a grammar word, and a `for` name is never one nor `params` or `input`. With the grammar alone, 95 lines read more than one way, every one of them because a grammar word could be a field, as in `is not empty` read as `is not .empty` and `is true` as `equals .true`. With the word rule, every line reads exactly one way. The first version of the ABNF also let a quoted string on the right side be a key, so `state is "MERGED"` read twice and 80 lines read two or four ways. That rule is in the grammar now, as `right-path`, so a parser gets it without reading this file. The made-up lines above were counted too, with the same results. `every commits, if any, as commit`, `x is ."$schema"`, `item 3 of commits is not empty`, `x equals last of items` and `commits[2].sha is "x"` each read one way, and `item 0 of items is 1` and `first is 1` read no way.
