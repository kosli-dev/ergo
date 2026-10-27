# How a policy is written

Draft 0.2. This file says how a policy is written: its sections and fields, its parts, the sentences its checks and `from` lines are written as, what counts as written wrong, and how the report names paths and shows the checks Ergo adds. What a check means once it's read is in [semantics.md](semantics.md).

[`policy/schema.json`](policy/schema.json) describes a policy as a JSON Schema, [`sentences.abnf`](sentences.abnf) is the grammar of the sentences, [`sentences-corpus.md`](sentences-corpus.md) has every real check written as one, and [`sentences-findings.md`](sentences-findings.md) what writing them found. The forms of a sentence no implementation runs yet are listed in [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet).

## Policies

**[policy.shape]** A policy is an object with two sections. `subjects` maps each subject's name to its definition, with `from`, a `from` line, `identified_by`, a path in a string, `has` and `description`, or to `null` for a subject with none of them (see [subjects.no_from](semantics.md#requirements)). `requirements` maps each requirement's name to its definition, with `subject`, `checks`, `require`, `min_subjects`, `description` and `meta`. `subject` is the name of an entry in `subjects`, and each check in `checks` is a sentence, a list of them under `assert`, or an `any_of` of them (see [The shape of a sentence](#the-shape-of-a-sentence)). The policy also has `ergo_spec`, the version of the spec it's written for (see [policy.version](#policies)), and can have a `description` and a `meta` of its own, next to its sections.

**[policy.version]** A policy says which version of the spec it's written for in `ergo_spec`, at its top, like `ergo_spec: v0.2`. YAML reads `v0.2` as text, so it needs no quotes, but `ergo_spec: 0.1` is a number. It isn't called `ergo`, because OPA loads a policy written in YAML as data next to `ergo.rego`, and `data.ergo` is where `package ergo` lives, so `ergo: v0.2` would stop `ergo.rego` from compiling. A policy without `ergo_spec`, or with `null`, is written wrong, and so is one whose `ergo_spec` isn't a string or isn't the version the implementation follows. An implementation follows one version. That makes the `$well_formed` row of every requirement fail, with an input named `policy ergo_spec` holding `["missing"]` when it's missing or `null`, `["not a string"]`, `["not a version V0.1"]` for a string that isn't a version (a `v`, a number, a dot and a number, and optionally `-dev`, like `v0.2` or `v0.3-dev`), or `["unsupported version v0.1, expected v0.2"]` for a version the implementation doesn't follow. The spec has one version for the policy, the report and what one means for the other, see [Versions](README.md#versions).

**[policy.old_fields]** A requirement that has `from`, `identified_by`, `applies_to` or `subject_type`, or any other field it doesn't take, is written wrong, and the `$well_formed` row lists the field with `["unknown field"]`. A subject definition with a field it doesn't take is written wrong the same way, `applies_to` and `of` included, and so is one with `id`, the old name for `identified_by`. A `from` or an `identified_by` that isn't a string, like a list of steps, is written wrong with `["not a string"]`. A check written as an object with `op`, the syntax before 0.1, is written wrong too: an object with neither `assert` nor `any_of` is `missing assert`, and each field it doesn't take is an `unknown field`, like `unknown field op`. Its `expression` in the report is `<missing assert>`.

## Parts

A subject can have parts, named paths inside itself. What a part means is in [semantics.md](semantics.md#parts), and how a sentence reads one in [Paths](#paths).

**[parts.syntax]** `has` on a subject definition is an object. Each key is a part's alias, and each value is the part: a path in a string, or an object with `from`, a path in a string, and optionally `identified_by`, a path in a string that is read inside the part. The report shows `identified_by`, and tags the inputs read through the part with the id it leads to, see [parts.tag](semantics.md#parts). A part is written the same way whichever syntax the subject's checks use. A subject whose from line narrows another can have `has` too.

```yaml
subjects:
  round:
    from: trail
    identified_by: name
    has:
      findings: compliance_status.attestations_statuses.findings.attestation_data
      coverage:
        from: compliance_status.attestations_statuses.coverage-verification
        identified_by: attestation_id
```

**[parts.path]** A part's path is written as a path in a `from` line is (see [sentence.path.string](#paths)): keys joined by `.`, keys in double quotes, positions, and `named by` a key of `$params` or `$input`. It is a path inside the subject, so it can't start at `$params` or `$input`, and it has no `whose`, `count of` or `named by each of`. A part is as often a path to one value as to a whole attestation.

**[parts.alias]** An alias is a bare word that starts with an ASCII letter or `_` and goes on with ASCII letters, digits, `_` or `-`. It isn't a word of the grammar (see [sentence.words](#words-a-field-cant-be-called)), `params` or `input`, or it's written wrong with `invalid alias`. A part's alias is also written wrong when it is named like a subject of the policy, its own, its parent or any other, with `<alias> can't be an alias: it's a subject's name`, like a part of a parent or grandparent subject, or like a part the subject keeps from a subject it narrows, with `<alias> can't be an alias: it's a part of <subject>`. The message names each subject that declares the part, and puts a name that isn't a bare word, like `pull request`, in double quotes. A name always means one thing, so nobody has to wonder whether it reads the subject or the alias. A `for` alias in a check follows the same rule ([sentence.for.alias](#the-for-line)).

**[parts.written_wrong]** A part written wrong makes its subject written wrong, so the `$well_formed` row of every requirement that uses the subject fails. It lists the problems under the part's alias, like `subjects.round.has.coverage`, and under `subjects.round.has` when `has` isn't an object, which is written `not an object`. A part that's neither a string nor an object is written `not a string or an object`, and an object without `from` `missing from`. A field other than `from` and `identified_by` is written `unknown field <name>`, and a `from` or `identified_by` that isn't a string `invalid from` or `invalid identified_by`. A path that can't be read is written `from: <problem>` or `identified_by: <problem>`, with the problems of a path in a `from` line, or `a part is a path: whose and named by each of can't go in it` and `a part reads inside its subject, so it can't start at $params or $input`. A bad alias is written `invalid alias`, and one named like a subject, or like a part of a parent, a grandparent or a subject it narrows, is written as [parts.alias] says. A part written wrong is never read as an alias, and the report still lists it, see [report.subjects](semantics.md#statuses).

## The shape of a sentence

**[sentence.check]** A check in a requirement's `checks` can be a sentence, or an object with the sentence under `assert` and optionally `description` and `meta`, which the report copies as it does for any check:

```yaml
checks:
  approved: approved_by is not empty
  signed:
    description: Every commit is signed
    assert: every commits.signed is true
```

An object with `assert` and any other field is written wrong, with `unknown field <name>`, and an `assert` that isn't a string or a list of strings is written wrong, with `invalid assert`, or with `empty assert` for an empty list. A problem with one line of a list of two or more starts with the line's number, like `line 2: unclosed quote at column 6`. An object with neither `assert` nor `any_of` is written wrong with `missing assert`, see [policy.old_fields](#policies). The report's entry for a sentence check has its `description`, its `meta` and its `expression`, and `$refs` for each `$params` or `$input` path it reads after `named by`, after a phrase that takes a list, or after `contains` or `does not contain`.

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
- `whose` holds one or more conditions joined by `and`, and each condition is a path and a phrase, never another `every` or `whose`. The `whose` of a subject's `from` line is the one exception: its conditions can also be a one-line `every` or `some`, see [sentence.subject.condition](#subjects). A condition can start with `count of` or `sum of`, like `whose count of findings is at least 1`, because that's still one condition with a phrase. Its path has no `whose` of its own
- `and` does two jobs and nothing else: it joins the conditions of a `whose`, and it joins whole assertions, see [sentence.assert.list](#the-shape-of-a-sentence). Each side of an `and` is a whole condition or a whole assertion, so the result is a flat list, not a tree. An `and` never joins a `whose` to its assertion
- no `or`, and no brackets except the lookups in [sentence.path.brackets](#paths)

"Or" is an `any_of` in the policy around the sentences, see [sentence.any_of](#the-shape-of-a-sentence), because each option has a name the report can show. Every expression language gets asked for `or` and brackets, and the answer here is no.

**[sentence.any_of]** A check can be an object with `any_of` and optionally `description` and `meta`. `any_of` holds named options, and each option is a sentence or a list of sentences:

```yaml
licence_allowed:
  description: The licence is allowed
  any_of:
    declared: some licenses.license.id is in $params.allowed_licenses
    known:
      - licenses does not exist
      - $params.known_package_licenses named by name is in $params.allowed_licenses
```

It reads into an [`any_of`](semantics.md#any_of) whose options hold what their sentences read into, one check for each assertion, so an option written `x is 1 and y is 2` holds two. It passes as [any_of.pass](semantics.md#any_of) says, and its cause, as [any_of.cause](semantics.md#any_of) says, takes each assertion's own cause, whether it walks a list with `every` or `some` or works out a `count of`. Its row shows every path its assertions read, once each, sorted by name, and has no `failed_items` and no `failed_assertions`. A ref works as [any_of.refs](semantics.md#any_of) says: one of the wrong type fails the row as `unusable`, even when another option passes, while a missing one only fails the options that read it.

**[sentence.any_of.written_wrong]** An `any_of` that isn't an object is written wrong with `invalid any_of`, an empty one with `empty any_of`, an empty option with `empty option <name>`, and an option that isn't a string or a list of strings with `invalid option <name>`. Any field besides `any_of`, `description` and `meta`, `for` included, is written wrong with `unknown field <name>`, and an object with both `assert` and `any_of` is a check with `assert` and an `unknown field any_of`. Every problem with a sentence, one that doesn't parse or one like `values of mixed types`, is listed under the check and starts with its option's name, then with the line's number, from 1, when the option has more than one line: `option known: line 2: doesn't parse`, `option fast: values of mixed types`.

**[sentence.any_of.expression]** Its `expression` is `one of: ` and the options, sorted by name as text and joined with ` | `, each written `<name>(<assertion> and <assertion>)`, like `one of: declared(some licenses.license.id is in $params.allowed_licenses) | known(licenses does not exist and $params.known_package_licenses named by name is in $params.allowed_licenses)`.

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

**[path.steps]** A path is written as a sentence writes it (see [sentence.path.string](#paths)). A bare first key starts at the subject, `$input` starts the path at the input and `$params` at the params.

**[sentence.path.string]** A path is keys joined by `.`, like `git_commit_info.sha1`. A key is written bare when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` and `-`, so Kosli's `secrets-scan`, `pull-request` and `coverage-verification` need no quotes. Any other key is quoted as a JSON string, like `metadata.labels."app.kubernetes.io/name"`, and so is any key with a `$` in it, like `"$schema"` or `"foo$bar"`. The report prints keys by the same rule, so `$` only ever starts `$params` or `$input`, and a path from a row can be pasted into a policy.

**[sentence.path.start]** A bare first key is a field of the subject, except `it`, which is the subject itself (see [sentence.path.it](#paths)). Inside `whose`, and in the argument of a one-line `every` or `some`, it's a field of the item instead (see [sentence.argument.item](#every-some-and-whose)). An alias given by `as` on a `for` line is a bare word too, and so is a part's alias (see [parts.shadow](semantics.md#parts)). Either shadows a field with the same name, the subject's or an item's, except on the left side of a `whose`, a `count of` or `sum of` there included (see [sentence.for.scope](#the-for-line) and [parts.where](semantics.md#parts)). A first key written with a dot, like `.approver` or `.it`, is always the field: never a word of the grammar, and never an alias, whether a `for` alias, a part's or a parent subject's name. `$params` starts at the params and `$input` at the input. Any other `$<word>` is written wrong, with `unknown name $<word>`.

**[sentence.path.it]** `it` is the subject itself, whatever it holds: an object, a string, a number, a list or `null`. It's a whole path, written where an assertion starts: on the left of a check, after an `and` between assertions, at the start of an `any_of` option, after `every`, `some`, `count of` and `sum of`, and on the left of a `whose` condition in a `from` line, after its `some` or `every` too, where the condition reads the subject (see [subjects.sentence](semantics.md#subjects)). After a `for` line it's still the subject, not the item of the `for`. With subject `region` from `every deployment.regions`, `allowed: it is one of $params.allowed_regions` checks each region string. A check on `it` reads the subject as a check on a field would read a value there, so `it is a string` on `null` fails with `null`, on `3` with `value`, and `it is an object` passes for an object. A row's `inputs` name it `it`, and a failed item `item 1 of it`, as it would name `item 1 of v`, and so does an `$applies` row. A field called `it` is written `.it` (see [sentence.words](#words-a-field-cant-be-called)), and the report prints `.it` for it.

**[sentence.path.it.name]** A subject can't be called `it`. A requirement that uses a subject called `it` is written wrong, and `$well_formed` lists `it is a word of the grammar, so a subject can't be called it` under `subjects.it`. `it` always means the subject itself, so no `from` line or check could name a subject called `it`. `It` and `items` are fine.

**[sentence.path.it.step]** `it` is never followed by a step or a `named by`, because the subject's fields are bare already. `it.name`, `it."x"`, `it[0]`, `it named by $params.k` and `first of it.name` are written wrong. `it.name` says `it is the whole subject: write name, not it.name`, and the others `it is the whole subject: nothing can follow it`. A position is written in words before it, as for a field: `first of it` and `item 2 of it` read one item of a subject that is a list, and give what the same position gives on a field's list (`absent` on an empty list, `unusable` on something that isn't a list), wherever a position is allowed for a field. Only the brackets, `it[0]`, are written wrong.

**[sentence.path.it.place]** `it` is written wrong anywhere else: on the right side of a phrase, a term of `plus` there included, inside the `whose` of a check or of a `for` line, as the path of a `for` item or of a `sorted by`, or as the path of a `from` line or a part. All of them say `it can only start an assertion: write it first, like it is not empty`. `it` as the key of a `named by` is written wrong with `it can't name a key`. Reading the subject from the right side of a phrase is left out for now (see [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet)).

**[sentence.path.part]** A part of the subject, declared with `has` (see [parts.syntax](#parts)), is read by its alias as a bare first key, wherever a bare first key reads the subject ([parts.where](semantics.md#parts)), and gives the rows of the path it stands for ([parts.swap](semantics.md#parts)). Inside `whose` and in the argument of a one-line `every` or `some`, it's read on the right side and never on the left of a `whose`, as a `for` alias is ([parts.where](semantics.md#parts)). `named by` a bare word that is a part's alias is written wrong, with `named by <alias> reads a part, which isn't supported yet`, because it would otherwise read the subject's field of that name. A part's own path is written as a `from` line's path is, so it never starts with an alias.

**[sentence.path.index]** `item 3 of items` reads the third item of `items`, counting from 1, `item 2 from last of items` the second from the end, and `first of items` and `last of items` read the ends. The path after `of` is the whole rest of the path, so `item 3 of pull_request.commits` picks the third commit, and a field of that item has no word form in the sentence: name the item on a `for` line ([sentence.for.pick](#the-for-line)), or write `pull_request.commits[2].sha` with brackets, which count from 0 as [sentence.path.brackets](#paths) says. `item 0 of items` is written wrong. The report prints the word form when the position ends the path, so `commits[2]` prints as `item 3 of commits`, and prints the brackets when a key follows them. No policy in the corpus needs a position.

**[sentence.path.argument]** The left side of a sentence is always a path. The right side can be a value or a path, and these rules decide which:

- A quoted string on the right side is text. `is "prod"` compares with the text prod, never with a field called `"prod"`.
- A word of the grammar on the right side is never a field name (see [sentence.words](#words-a-field-cant-be-called)). `is empty` is the phrase, `is true` is the value.
- A field with one of those names is written with a dot in front: `is .empty`, `is .true`. The dot is allowed on any field, so `equals .total_usd` means `equals total_usd` when no alias is called `total_usd`, and the report prints it only where it's needed. Where an alias has the same name, the dot is how to read the field (see [sentence.for.alias](#the-for-line)).
- A key that has to be quoted, like `$schema`, is written with the dot too: `is ."$schema"`.

**[sentence.path.dynamic]** `<path> named by <reference>` reads the key that the reference holds, as a ref step in the [model](semantics.md#the-model-of-a-check) does, and the path can go on after it: `artifacts_statuses named by $params.artifact_name.attestations_statuses`. The reference is `$params` or `$input` plus one key, or one bare key. A bare key is an alias from a `for` line, like `persona_blob_shas named by persona`, or else a field, read where a bare first key would be read (see [sentence.path.start](#paths)): `$params.max_days_by_severity named by severity` reads the subject's `severity`, and inside a `whose` the item's. Without that limit, `named by $params.a.b` could end the reference after `a` or after `b`, and the tokenizer found 24 lines in the corpus that read two ways because of it.

**[sentence.path.brackets]** Brackets are the other spelling: `artifacts_statuses[$params.artifact_name]`, `persona_blob_shas[persona]`, and `items[2]` for a position. In brackets the type decides, as in JSON: a string picks a key and a number picks a position. The report prints the word form. A position above 9007199254740991, the largest whole number a 64-bit float holds exactly, is written wrong, in brackets or after `item`, with `<number> can't be a list position`.

**[sentence.path.keys]** In `from`, `<path> named by each of <list>` makes each listed key a subject: `artifact.attestations named by each of $params.required_scans`. There is no bracket form for it, because `a[x]` picks one thing in every language, and a parameter meant to be one name that arrives as a list would turn one subject into several instead of failing. `from` doesn't name its subjects: a check that needs a name for an item puts the walk on a `for` line, and the subject's fields are bare.

## Subjects

**[sentence.subject.from]** A subject's `from` takes the shape of a `for` item without `as`, and without `every` unless it reads every list along its path ([sentence.subject.every](#subjects)): a path, optionally `named by each of` a list, optionally `whose` with conditions joined by `and`. The conditions read the subject, as a `whose` reads its item:

```yaml
subjects:
  emergency change:
    from: deployments whose environment is "prod" and change_type is "emergency"
    identified_by: id
```

**[sentence.subject.every]** `every` in front of a `from` line's path walks every list along the path, the last one included, as `every` does in a check ([sentence.every.walk](#every-some-and-whose)), and each value it ends at is a subject: `from: every artifacts.pull_requests` makes every pull request of every artifact a subject. They're one flat list, independent of the artifacts: their rows have no `in`, and they're counted once ([subjects.every](semantics.md#requirements)). Without `every`, a path through a list reads nothing. `every` can't go with a path that starts at another subject's name, which is written wrong with `every can't go with a from line that starts at another subject yet`, or with `named by each of`, which is written wrong too, because the names would be read under every list item with no `in` to tell them apart. A child subject does that one parent at a time. Like a check's walk, it takes ten steps at most, and an eleventh is written wrong.

**[sentence.subject.condition]** A condition in that `whose` is a one-line check that has no `whose` of its own: a path and a phrase, a `count of` or `sum of` and a comparison, or a one-line `some` or `every`. pr-reviewer has six with `count of`, like `whose count of compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is at least 1`. A `some` or `every` condition asks about the items of a list, so a release can be in scope when some file in it isn't documentation:

```yaml
subjects:
  release:
    from: release whose some files.path does not match "^docs/"
  docs_release:
    from: release whose every files.path, if any, matches "^docs/"
```

It reads like the same sentence as a check: its path starts at the subject, a bare name in its phrase is the item's ([sentence.argument.item](#every-some-and-whose)), and a parent subject's name on the right side is the parent, as in the other conditions. `every` takes `, if any,` and `some` doesn't, so `some files.path, if any, matches "x"` is written wrong with `if any can't go with some`. A `some` or `every` condition with a `whose` of its own, like `release whose some files whose kind is "src" matches "x"`, is written wrong with `a condition after whose can't have a whose of its own`, and so is a `count of` or `sum of` with one. A `whose` in a check or on a `for` line takes no `some` or `every` condition.

**[sentence.subject.applies]** A subject with conditions gets an `$applies` row. Its `expression` is the conditions in the order written, each in the report's spelling, joined with ` and `, like `environment is "prod" and change_type is "emergency"`, and its `inputs` hold each path they read. A `some` or `every` condition gives the `inputs` and the cause that the same sentence gives as a check row, like `files[].path` with the list of paths, and `artifact.owner` too in `some files.owner is artifact.owner`. The row also has what that check row has: `failed_items` for one `some` or `every` condition, and `failed_assertions` for several conditions, see [scope.failures](semantics.md#scope). A subject where it passes is in scope, and one where it fails with `value`, because no item passes `some` or an item fails `every`, is out of scope. A subject a condition can't decide about, like a deployment with no `change_type`, or a `some` or `every` whose list is missing, `null` or not a list, or whose items have no usable field, fails the requirement as `absent`, `null` or `unusable` rather than dropping out of it. An `every` over an empty list gives `value` and is out of scope, unless it has `, if any,`, see [sentence.whose.every](#every-some-and-whose).

**[sentence.subject.chain]** A subject can start from another subject, by that subject's name, and is then a child subject of it: `from: artifact.attestations_statuses named by $params.pr_attestation_name.pull_requests`, where `artifact` is a subject of the same policy. Its rows carry the parent's id under `in`, like `{"type": "pull request", "id": "…/pull/8", "in": {"artifact": "sha256:…"}}`, `min_subjects` counts per parent (see [subjects.chain.count](semantics.md#requirements)), and a check reads the parent by its name, like `artifact.name`. So does the right side of a `whose` in the child's own `from` line, like `from: artifact.pull_requests whose base is artifact.branch`, and a grandchild's `from` line reads every ancestor the same way. The parent's name reads like an alias ([sentence.path.start](#paths)): on the right side inside an item's scope, never on the left of a `whose`, and `.artifact` is the field. In the corpus, four `from` lines descend this way, all from an `artifact` subject: sdlc-policies 0007 and 0008, the server's copy of 0008, and server 0010.

**[sentence.subject.quoted]** A subject whose name has a space starts a chain with the name quoted, like any key with a space: `from: "production deployment".pull_requests`. YAML won't take a plain value that starts with a quote and goes on after it, so the whole line goes in single quotes: `from: '"production deployment".pull_requests'`. The same goes for any sentence that starts with a quoted key. No policy in the corpus needs it, though 19 of its subject names have a space. The tokenizer reads `"production deployment".pull_requests` one way, as a chain from that subject.

**[sentence.subject.narrow]** A chain can narrow instead of descending: `from: defect whose severity is "critical" and status is one of "open", "in_progress"` is a `defect` with two more conditions. Its rows are rows of the parent, with the same id and no `in`. DEV-0409 and DEV-0410 use it.

**[sentence.subject.depth]** A chain can be three subjects deep, one more than the corpus needs, see [subjects.chain.levels](semantics.md#requirements). No chain in the corpus is more than two subjects deep.

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

**[sentence.value.path]** An argument that isn't a value is a path. So `is "prod"` compares with text and `equals total_usd` with a field, which is what the model's `equals` and `compare` split is for. `is` before a field is read the same, and printed as `equals`.

## Words a field can't be called

**[sentence.words]** These words are read as part of a phrase, a quantifier, a position or a value, never as the first key of a path written bare: `a`, `after`, `alphabetically`, `an`, `and`, `as`, `at`, `before`, `between`, `count`, `days`, `each`, `empty`, `equal`, `every`, `false`, `first`, `hours`, `in`, `it`, `item`, `last`, `less`, `minutes`, `more`, `named`, `not`, `null`, `of`, `on`, `one`, `or`, `plus`, `seconds`, `some`, `sorted`, `sum`, `to`, `true`, `weeks`, `whose`, `within`. Without this, `x is empty` could also compare `x` with a field called `empty`, `x is true` with a field called `true`, and `count of x is 1` could start from a field called `count`. `it` is the word for the subject itself (see [sentence.path.it](#paths)), and a field called `it` would be a second reading of it. A field with one of these names is written `.empty`, on either side of the sentence. The rule is the same on both sides so that it's one rule, and so that a parser never has to know which side it's on to read a key. Keys after the first are never words of the grammar, so `review.count` needs no dot.

## `every`, `some` and `whose`

**[sentence.every.walk]** `every <path>` walks into every list along the path, the last one included, and the assertion applies to each value it ends at. `every pull_requests.commits.author` reads the author of every commit of every pull request, and `every branches matches "^release/"` reads each branch of a list of strings. It passes when every value passes. Because the last list is walked too, `every pull_requests.labels is not empty` checks each label, not that each pull request has labels. So `contains`, `does not contain`, `contains all of` and `contains none of` after `every` or `some` would ask each label whether it holds a value, which a string never does, and they're written wrong, with a message that says to put the walk on a `for` line. No policy in the corpus puts them there. And because a bare name on the right of a one-line `every` is the item's, `every $input.artifact.developers does not equal tested_by` reads `tested_by` on each developer string, which isn't what it means. To compare each string with a field of the subject, use a `for` line: `for: every $input.artifact.developers as developer` with `assert: developer does not equal tested_by`. `$input.artifact.developers does not contain tested_by` looks like the same check without the `for`, but it isn't: it passes an empty list, which `every` fails. That's why DEV-0407 keeps its `for` line.

**[sentence.every.empty]** `every` over an empty list fails with cause `value`, because no commits isn't proof that every commit is signed. Over nested lists, each inner list must have an item too.

**[sentence.every.if_any]** `every <path>, if any, <assertion>` passes over empty lists, at every level it walks. A list that's missing, `null` or not a list still fails as `absent`, `null` or `unusable`. `if any` goes after the path and its `whose`, between commas, right before the phrase: `every items whose kind is "a", if any, is at least 2`. That's where it reads as "every item, if there are any left", and a parser can't take it for a value, because a value is never `if any`. On a `for` line it goes before `as`: `every commits, if any, as commit`. With `some`, it's written wrong, with `if any can't go with some`, since "some approver, if any" would let an empty list pass a check that asks for at least one.

**[sentence.some.walk]** `some <path>` walks the same way, and passes when at least one value passes. An empty list fails with `value`.

**[sentence.walk.steps]** The path after `every`, `some`, `count of` or `sum of` takes ten steps at most, and an eleventh is written wrong. The limit holds wherever the path stands: in a check, on a `for` line, in a `whose`, in an `any_of` option, on either side of a phrase (`n is count of <path>` as much as `count of <path> is n`), after `plus`, and in a `from` line's `every` and `whose`, see [sentence.subject.every](#subjects). The message is `every and some over more than ten steps aren't supported yet`, or `every over more than ten steps isn't supported yet` for a `from` line's `every`. Each name in the path is a step, whether or not it walks a list, and so is a `for` alias it starts at, so with `for: every pull_requests as pr`, `every pr.commits.author` is three steps. A position like `first of` or `item 2 of` is a step too, so `every first of k1.k2.k3.k4.k5.k6.k7.k8.k9` reads and `every first of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` is written wrong. `$input` and `$params` aren't steps, in a check or in a `from` line, so `from: every $input.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` reads. A walk that starts at a part counts the part's own path in place of its alias ([sentence.path.part](#paths)): with the part `x` set to `k1.k2.k3.k4.k5.k6.k7.k8.k9`, `every x.z is 1` is ten steps and reads, and with a part of ten names it is eleven and is written wrong. A part's position counts as a step of its path, and a part of a parent subject counts in place of the parent's name and the alias. A part counts only where the path reads the part: in the `whose` of a `count of` or a `sum of`, a name like `b.x.z` is read on the item, so no part is counted there. A part that isn't walked, like `x.z is 1`, has no limit. An item picked on a `for` line, like `first of reviews as review`, isn't a walk: its path takes ten names at most, and its position isn't counted.

**[sentence.whose.item]** `whose` keeps the items that pass every one of its conditions. Its paths start at the innermost item the quantified path walks, the one that holds the field the path ends at, and the assertion is about the value the path ends at. In `some approvers.username whose state is "APPROVED" is in $params.internal_staff`, `state` is read on each approver and `username` is what's checked.

**[sentence.whose.undecided]** An item that a condition can't decide, because a field it reads is missing, `null` or the wrong type, isn't left out. Under `every`, `count of` and `sum of`, the check fails with that item's cause. Under `some`, it counts as an item that failed: another item can still pass the check, and if none does, the check fails with the first cause among the items. `exists` and `does not exist` are the exception, because a missing field is their answer.

**[sentence.whose.every]** Under `every`, an item that `whose` leaves out isn't checked. When `whose` leaves no items, the check fails with `value`, unless it has `if any`. No policy in the corpus uses `every ... whose` yet.

**[sentence.argument.item]** In a one-line `every` or `some`, a path in the argument starts at the item too, so the item can be compared with its own fields: server 0007's `some approvers.timestamp whose state is "APPROVED" and username does not equal pr_author is after last_commit_timestamp` reads both from each approver. In a one-line `every` or `some`, every bare name is the item's, in `whose` and on the right side alike, except a `for` alias on the right side, which is the alias (see [sentence.for.scope](#the-for-line)). It ends at an `and`, see [sentence.assert.and](#the-shape-of-a-sentence). To compare an item with the subject, use a `for` line. To reach the input, start with `$input`.

**[sentence.argument.subject]** After `count of` and `sum of`, the assertion is about one number for the subject, so a path in the argument starts at the subject: in `sum of stages.usd equals total_usd`, `total_usd` is the subject's.

## Derived values

**[sentence.derived.count]** `count of <path>` walks the path as `every` does and counts the values it ends at, so `count of findings` is the number of findings. With `whose`, it counts the items that pass.

**[sentence.derived.sum]** `sum of <list>.<field>` adds the field up across the items. With `whose`, only the items that pass. A sum over no items is 0. Numbers are added as decimals, so `0.1 plus 0.2` is `0.3`.

**[sentence.derived.plus]** `<term> plus <term>` adds numbers. A term is a path, a number, a `count of` or a `sum of`. A `whose` ends the terms, so `count of x whose n is m plus k is t` reads one way: `m plus k` is the condition's right side, and nothing is added to the count. To add to a count that has a `whose`, put the `count of` last: `k plus count of x whose n is m is t`. On the right side of a phrase, a `count of` or `sum of` takes no `whose` at all, because `x is count of y whose a is 1 and b is 2` could be one assertion with two conditions or two assertions. Count on the left and compare on the right.

**[sentence.derived.elapsed]** `<unit> elapsed from <path> to <path>` is a number: the time from the first path to the second, in `seconds`, `minutes`, `hours`, `days` or `weeks`, which are 1, 60, 3600, 86400 and 604800 seconds. It's rounded down to 6 decimal places, so 36 hours is `1.5` days and one second is `0.000011` days, and every runtime prints the same digits. Each path is read as any other path in the sentence is, and `to` between them is a word of the grammar, so a field called `to` is written `.to`. Both values must be times as [time.format](semantics.md#compare_time) says, both RFC 3339 strings, both dates, which are whole days apart, or both numbers, read as seconds to the nearest microsecond. A number must be from -9000000000 to 9000000000, about the years 1684 to 2255, so a time in milliseconds fails instead of being read as seconds. Anything else, and one string with one number, fails as `unusable`, a missing path as `absent` and a `null` one as `null`, and the worst of the two wins, as for `is before`. If the second time is before the first there is no sensible number, so the check fails as `value`. Two equal times are 0. The phrases that follow are the ones [sentence.derived.compare](#derived-values) lists:

```yaml
within_limit: days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity
```

It's a number like a `count of`, so it goes where one does: at the start of an assertion, on its own line of a list under `assert` or after the `for` line, as a term of `plus`, as the right side of a phrase, in the `whose` of a `count of`, a `sum of` or an `every`, and before `is between`. In a `whose`, an item whose end is before its start has no number, so it's left out, as any item whose condition fails with `value` is. After `every` or `some` and in a `from` line, the spec doesn't say yet, see [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet). Months and years have no fixed length, so `months elapsed from` and `years elapsed from` don't read as this phrase.

**[sentence.derived.compare]** A derived value only goes with `is`, `equals`, `is not`, `does not equal`, `is ... within`, `equals ... within`, `is at least`, `is at most`, `is more than`, `is less than` and `is between`. `count of approvers is empty` is written wrong, and so is `days elapsed from a to b is empty`.

## The `for` line

**[sentence.for.line]** A check can have a `for` line before its `assert`. It holds one or two items separated by `, `, and each item is `every` or `some`, a path, an optional `whose` with `and`, and `as` an alias, or picks one item as [sentence.for.pick](#the-for-line) says:

```yaml
peer_approved:
  description: Someone other than the author approved every pull request
  for: every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver
  assert: approver.username does not equal pr.author
```

Items nest left to right, so a later one can use an earlier alias, as `pr.approvers` does. A third item is written wrong, because two is the one level of nesting Rego gives.

**[sentence.for.scope]** In `assert` and in a later item, a bare first key is the subject's field and an item is reached by its alias. Inside an item's own `whose`, a bare key is that item's field. So in `for: some approvals whose role is "qa" as approval` with `assert: approval.approved_at is before started_at`, `role` is the approval's and `started_at` the subject's.

The left side of a `whose` is the item's field even when an alias has the same name, because "deployments whose env is prod" can only mean the deployment's `env`. On the right side of a `whose`, and on the right side after a one-line `every` or `some`, a bare name that's an alias is the alias, and the item's field with that name is written with a dot. With `for: every environments as env, …`:

| sentence                                             | reads                                              |
| ---------------------------------------------------- | -------------------------------------------------- |
| `some deployments whose env is "prod"`               | the deployment's `env`                             |
| `some deployments whose environment equals env.name` | the deployment's `environment`, the alias's `name` |
| `every deployments.region does not equal env`        | each deployment's `region`, the alias `env`        |
| `every deployments.region does not equal .env`       | each deployment's `region`, the deployment's `env` |

**[sentence.for.alias]** An alias is a bare word that isn't `params`, `input` or a word of the grammar, like `every`, `as` or `empty`. For the rest of the check it shadows a field with the same name, the subject's or an item's, everywhere but on the left side of a `whose` ([sentence.for.scope](#the-for-line)). A dot in front, like `.env`, reads the field. The same alias on two items of the line is written wrong with `for: <x> is given twice`. An alias named like a subject, the check's own, a parent or any other in the policy, is written wrong with `<alias> can't be an alias: it's a subject's name`, and one named like a part of the check's own subject, of a parent or grandparent subject, or of a subject they narrow, with `<alias> can't be an alias: it's a part of <subject>`, naming the subject that declares the part. A name always means one thing, so nobody has to wonder whether it reads the subject or the alias, and a bare name never reads the parent when the item lacks the field. A bare word after `named by` that no `for` line gives is also written wrong, with `unknown alias <word>`.

**[sentence.for.fail]** Each item fails closed as a one-line `every` or `some` does: `some` over an empty list fails, `every` over one fails unless the item says `if any`, a missing or non-list path fails as `absent`, `null` or `unusable`, and an item a `whose` can't decide fails the try with its cause.

**[sentence.for.pick]** An item can start with a position instead of `every` or `some`, as [sentence.path.index](#paths) writes it, and then its alias stands for one item: `for: last of commits as last_commit`. After the path and an optional `whose`, `sorted by` and a field counts the position in the order of that field instead of the list's:

```yaml
not_last_author:
  for: last of commits sorted by timestamp as last_commit, some approvers as approver
  assert: approver.username does not equal last_commit.author_username
```

`first of commits sorted by timestamp` is the earliest commit, `last of` the latest, and `item 2 from last of` the second latest. The field can hold numbers, RFC 3339 times or dates. `alphabetically` after the field orders strings instead, code point by code point as [sentence.phrase.alphabetical](#phrases) says, so `first of owners sorted by name alphabetically` is the first name and `last of` the last. There's no word for the reverse order, because `last of` and `item 2 from last of` count from the other end. The field is the item's, so it can't start with `$params`, `$input` or a position, and brackets after it pick a position in the field, as in `sorted by ts[0]`. A field with the same name as a `for` alias is written with a dot, `sorted by .c`, and without one it's written wrong, with `"sorted by" reads a field of the item, not c: write .c`, so that it can't be read as the alias. `sorted by` after `every` or `some` is written wrong, since they read every item, and so is `, if any,` with a position, since an empty list has nothing to pick. A field of the picked item is read through its alias, `last_commit.author_username`. SDLC-CTRL-0007 needs it: the approver can't be whoever pushed the last commit, though they may have pushed earlier ones while pairing. `sorted` is the word spreadsheets use, so control owners know it, and no field in the corpus has that name. `latest` and `earliest` could come later as shorter words for times, if control owners ask for them.

**[sentence.for.comma]** The `, ` between items can't be confused with the `, ` between values, because the next item starts with `every`, `some` or a position and a value can't. The tokenizer reads `for: some approvals whose role is one of "qa", "dev" as approval, every commits as commit` one way.

**[sentence.for.assert]** A `for` line can have several assertions under `assert`, as [sentence.assert.list](#the-shape-of-a-sentence) says. sdlc-policies 0007's peer approval needs that: an approver who approved, isn't the author and approved after every commit.

## The grammar

**[sentence.grammar]** [`sentences.abnf`](sentences.abnf) is the grammar, in ABNF as RFC 5234 writes it. It says which strings are a check (`check`), a `for` line (`for-line`) and a `from` line (`from-line`), and it's what an implementation parses. The phrases below say what each form means. When the two disagree, the grammar is the syntax and the phrase is wrong.

Some rules can't be said in ABNF, so they're here:

- A bare first key is never a word of the grammar, see [sentence.words](#words-a-field-cant-be-called). A `for` alias isn't one either, nor `params` or `input`. `it` is the subject itself and only goes where [sentence.path.it](#paths) says, so the grammar lets it stand in more places than a check can use.
- Which bare first key is a subject's field, an item's field, a `for` alias or a subject's name depends on where the sentence is, see [sentence.path.start](#paths), [sentence.for.scope](#the-for-line) and [sentence.subject.own](#subjects).
- A `for` line has two items at most, see [sentence.for.line](#the-for-line).
- `is`, `equals` and `is equal to` read the same, as do `is one of` and `is in`, and the report picks the spelling, see [sentence.print.canonical](#printing-the-sentence).
- A run of spaces between two words reads as one, and a list of values can be written with or without a space after each comma. The report prints one space and `, `.
- The bounds of `is between` are in order, a string in `matches` is a valid regular expression, and a `for` alias is given once, or the sentence is written wrong.

A grammar word only needs quoting or a dot when it's the first key, so `a`, `an`, `in`, `on` and `of` cost nothing in ordinary paths.

## Phrases

Each phrase is a plain pattern: fixed words with gaps. One line is one form, and a negated form is a line of its own. An implementation matches them its own way. In Rego that's one regular expression per line, matched with `regex.find_all_string_submatch_n`, as `ergo.rego` does. No library or notation is needed.

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

`is empty` passes on `[]` and `""`. `is not empty` passes on a list with an item or a string with a character. Missing: `absent`. `null`: `null`. Wrong type, a number, a boolean or an object: `unusable`. It reads into `empty_string_or_list` (see [semantics.md](semantics.md#empty_string_or_list-and-not_empty_string_or_list)), which takes both types. When the type matters, say it with [sentence.phrase.type](#phrases): `is a non-empty string`, or `is a list` as a second check.

**[sentence.phrase.type]**
```
<path> is a <type>
<path> is an <type>
<path> is a non-empty string
```

The field has that JSON type. Either article is accepted, and the report prints `an` before `object` and `a` before the rest. `is a non-empty string` reads into [`non_empty_string`](semantics.md#non_empty_string): a string with at least one character. Missing: `absent`. `null`: `null`. Wrong type: `value`, because checking the type is the phrase's job.

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

Both sides are numbers. Two strings fail as `unusable`, even when they hold numbers, because `"9"` would come after `"80"` as text: [sentence.phrase.alphabetical](#phrases) compares text, and [sentence.phrase.time](#phrases) compares times. A written value that isn't a number is written wrong, with `"is at least" takes a number`, because the check could only fail. Missing: `absent`. `null`: `null`. Anything else: `unusable`.

**[sentence.phrase.alphabetical]**
```
<path> is alphabetically before <value or field>
<path> is alphabetically after <value or field>
```

New, and unused in the corpus. Both sides are strings, compared code point by code point, so every uppercase letter comes before every lowercase one: `"Zoe"` is alphabetically before `"adam"`. A string isn't alphabetically before or after itself. A written value that isn't a string is written wrong, with `"is alphabetically before" takes text`. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A locale's order, where `"adam"` comes first, isn't the same in every runtime, so it isn't offered.

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

Both sides are timestamps in the same format, both RFC 3339 strings, both dates like `"2026-10-01"` or both numbers, as [`compare_time`](semantics.md#compare_time) does. A date and an RFC 3339 string fail as `unusable`, because a date doesn't say in which time zone it starts. A timestamp that isn't RFC 3339 fails the check rather than being compared as text. Missing: `absent`. `null`: `null`. Wrong type or format: `unusable`. A written value that isn't a time as [time.format](semantics.md#compare_time) says, like `"yesterday"` or `null`, is written wrong, with `"is before" takes a time or a number`, because the check could only fail. `is on or after` replaces `is not before`, a double negative the corpus used six times.

**[sentence.phrase.aliases]**
```
<path> is equal to <value or field>
```

Read as `is` or `equals`, and printed as one of them. With it in the grammar, every sentence in the corpus still has exactly one reading.

**[sentence.derived.fail]** `count of` and `sum of` over a list that's missing, `null` or not a list fail as `absent`, `null` or `unusable`. A number to add that's missing fails as `absent`, `null` as `null`, and anything else that isn't a number as `unusable`. `every` and `some` fail the same way on the list they walk.

## Written wrong

**[sentence.written_wrong.slot]** A sentence that doesn't parse is written wrong, as any check that can't be read into the model is (see [written_wrong](semantics.md#the-model-of-a-check)). `$well_formed` lists it, and the requirement gets no other row. Because the grammar is flat, the message can name the slot, what it expected and the column:

| sentence                                                 | `$well_formed` says                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `environment is "prod`                                   | `unclosed quote at column 16`                                                   |
| `every commits.signed`                                   | `nothing after the path at column 21: expected a phrase, like "is" or "exists"` |
| `sum of stages.usd equals total within`                  | `"within" needs a number after it`                                              |
| `some approvers, if any, is not empty`                   | `if any can't go with some`                                                     |
| `every pull_requests some approvers.state is "APPROVED"` | `two quantifiers in one sentence: put them on a for line`                       |
| `x is at least 1e400`                                    | `number out of range: 1e400`                                                    |
| `items[9007199254740992] does not exist`                 | `9007199254740992 can't be a list position`                                     |
| `it.name is 1`                                           | `it is the whole subject: write name, not it.name`                              |
| `it[0] is 1`                                             | `it is the whole subject: nothing can follow it`                                |
| `x is it`                                                | `it can only start an assertion: write it first, like it is not empty`          |
| `$params.m named by it is 1`                             | `it can't name a key`                                                           |

**[sentence.written_wrong.self]** A sentence that compares a path with itself is written wrong, because it could only pass or only fail. That's `is`, `equals`, `is not` or `does not equal` a field, with or without `within`, the order and time phrases, `starts with` and `ends with`, when the field on the right is read from the same place as the path:

- the same path, in an assertion or a `whose`, like `x is at least x` or `whose type equals type`
- after `every` or `some`, the end of the path walked, because the right side starts at the item ([sentence.argument.item](#every-some-and-whose)), like `every conditions.type equals type`

A name on the right that's a `for` alias reads the alias ([sentence.for.scope](#the-for-line)), so with `for: every zones as type`, `every conditions.type equals type` compares each condition's `type` with the zone, and isn't written wrong. `every conditions.type equals .type` is.

Most often the writer meant the subject's field. In a `whose` and after `every` or `some` it can't be reached, so the message says where to compare it:

| sentence                                                   | `$well_formed` says                                                                                                                                                    |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `x is at least x`                                          | `x is compared with itself`                                                                                                                                            |
| `every conditions.type equals type`                        | `type is compared with itself, because after every or some it's read from the item: to read the subject's type, put the list on the for line and compare under assert` |
| `for: some conditions whose type equals type as condition` | `for: type is compared with itself, because in a whose it's read from the item: to read the subject's type, compare under assert`                                      |
| `count of xs whose x equals x is 2`                        | `x is compared with itself, because in a whose it's read from the item, and a count or a sum can't read the subject's field there yet`                                 |

`contains`, `is in` and a right side with `plus` can go either way, so they're left alone.

`environment is prod` and `approved_by is empy` parse, as comparisons with a field called `prod` or `empy`, unless the subject has no such field. That's the one mistake the grammar can't catch, so the message for a missing field in an `is` argument should suggest quotes.

**[written_wrong.row]** A check [written wrong](semantics.md#the-model-of-a-check) makes the `$well_formed` row list it in its `inputs`, after `count(checks)` and `require`, sorted by name, with the list of what's wrong, sorted. A check of the requirement is named `checks.<name>`, and a field of a subject definition `subjects.<subject>.<field>`, like `subjects.deployment.from`. An `ergo_spec`, `description` or `meta` of the policy that's written wrong comes last, named `policy ergo_spec`, `policy description` or `policy meta` and sorted by name, in words and not as a path, because a name that starts with `$` is one a check can read.

## Printing the sentence

**[sentence.print.canonical]** The report's `expression` is the sentence printed from its parse in one spelling: single spaces, `is` and `is not` before a value and `equals` and `does not equal` before a field, `is one of` before written values and `is in` before a path, no alias, a string in single quotes when it holds a backslash but no single quote, no two backslashes in a row, no backslash at the end and no control character, and in double quotes with JSON escapes otherwise, a dot in front of a field only where [sentence.path.argument](#paths) needs one or where an alias has the same name, numbers in their plain form, and values separated by `, `. Parsing the printed sentence reads the same check.

**[sentence.print.order]** `whose` conditions and assertions joined with `and` print in the order the author wrote them. The report stays byte for byte the same when the same policy runs again on the same input. That rule is for the same policy, not for two policies that mean the same: `A and B` and `B and A` print differently, because the order changes neither what passes nor the cause, and sorting would have to reach `assert` lists too, and could never reach `for` items, whose order is their nesting. A row's `inputs` stay sorted by name, because they're values that were read, not a sentence.

**[sentence.print.same]** For a sentence written that way, the printed form is byte for byte what the author wrote. Every line in the corpus prints back unchanged, the regular expression `entry does not match '^[A-Za-z0-9._-]+\s*(>=|<=|~=|!=|<|>)'` included, because its single quotes are the canonical spelling.

## Naming a path

A row's `inputs`, a ref's entry in `$refs`, an item in `failed_items` and a path in an `expression` name the paths they read the way a sentence writes them (see [Paths](#paths)). A name made of keys, positions and `named by` one key, starting at the subject, `$params` or `$input`, can be pasted into a sentence. The `[]` of a list's items has no sentence spelling yet, so a name with it can't. The names `$well_formed` gives the policy's own fields, like `checks.c` or `subjects.deployment.from`, follow [written_wrong.row](#written-wrong) instead.

**[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` or `-`, and in double quotes otherwise, so a key with a `$` in it is quoted, like `"$schema".x` or `x."$b"`. A first key that's a word of the sentence grammar (see [sentence.words](#words-a-field-cant-be-called)) has a `.` in front, like `.empty` or `.a` or `.it`. The subject itself is `it` (see [sentence.path.it](#paths)), and a name that starts at it follows the rules below as a field's does, so `first of it` is `item 1 of it`, as `first of xs` is `item 1 of xs`. A path that starts at the input or the params starts with `$input` or `$params`, and one that starts at an alias keeps it, like `pr.author`.

**[name.index]** An index at the end of a path is written `item <n> of <path>`, counting from 1, so `["xs", 1]` is `item 2 of xs`, and so is a position in a list check's `failed_items` whose path is empty: `item 2 of xss[]`. An index with more steps after it, or with nothing before it, is written in brackets, counting from 0: `xs[1].k`, `[0]`. For a subject that is a list, `it` is the thing before, so an item of it is `item 1 of it`.

**[name.ref_step]** A ref step whose ref reads one string key of the input or the params is written ` named by $params.key`, like `obj named by $params.k.v`. Any other ref step, and one that starts the path, is written in brackets, like `k[$params.a.b]` or `[$params.key]`.

**[name.part]** A path that starts with a part's alias is named with the alias, and the steps the alias stands for aren't named, so the full path `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_total` is `coverage.attestation_data.hunks_total` when it was written with the alias. A path read through a child subject's parent, like `artifact.pr_attestation.approvers`, is named the same way, and a list the alias stands for is `coverage[]` when it's walked. A path written in full is named in full, whether or not a part stands for it. A position is never hidden: when a walk (`every`, `some`, `count of`, `sum of`, a `for` line) goes through a list inside a part's path, not at its end, every name from that walk uses the full path, like `pull_requests[2].reviews[0].state` for a part `reviews` that stands for `pull_requests.reviews`. Only the names differ: a row's `expression`, `inputs` and the paths of its `failed_items` use the alias, and the values in them are the same.

## Expressions

Each check's definition in the report has an `expression` that says what it checks.

## Checks Ergo adds

**[added.text]** The checks Ergo adds have these descriptions and expressions, where `<type>` is the name of the requirement's subject, and `<from>` is the name of the subject's `from`, or `$input` when it has no steps. For a subject that goes on into another subject, `<from>` is its `from` as written, starting with that subject's name: `artifact.pull_requests`, or, read from a part of it, `artifact.pr_attestation.pull_requests`.

| Check           | Description                                                                                           | Expression                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `$well_formed`  | `The requirement is written correctly`                                                                | `count(problems) == 0`                                              |
| `$min_subjects` | `The in-scope <type> count is at least <n>`, or with `min_subjects: 0`, `The <type> list can be read` | `count(matching(<from>)) >= <n>`, or `<from> can be read`           |
| `$unique_ids`   | `Every <type> id is unique`                                                                           | `count(repeated(ids(<from>))) == 0`                                 |
| `$applies`      | `The <type> is in scope`                                                                              | the `from` line's filters in the order written, joined with ` and ` |

**[added.inputs]** `$min_subjects` names its input `in-scope <type> count`, and `$unique_ids` names its input `repeated <type> ids`. `$well_formed` names its first two `count(checks)` and `require`, and when `require` is written wrong, its value is `["neither every nor some"]`. A field Ergo doesn't know is listed with `["unknown field"]`, and `checks: {}` with `["empty"]`. A requirement without a `subject` has `{"name": "subject", "value": ["missing"]}`, and one whose `subject` isn't in `subjects` has `["not in subjects"]`.

**[added.causes]** The `causes` of a requirement entry is a list of `{"cause": <cause>, "rows": <number>}`, as in `[{"cause": "value", "rows": 2}]`.
