# How a policy is written

Draft 0.3. This file says how a policy is written: its sections and fields, its parts, the sentences its checks and `from` lines are written as, what counts as written wrong, and how the report names paths and shows the checks Ergo adds. What a check means once it's read is in [semantics.md](semantics.md).

[`policy/schema.json`](policy/schema.json) describes a policy as a JSON Schema, [`sentences.abnf`](sentences.abnf) is the grammar of the sentences, [`sentences-corpus.md`](sentences-corpus.md) has every real check written as one, and [`sentences-findings.md`](sentences-findings.md) what writing them found. The forms of a sentence no implementation runs yet are listed in [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet).

## Policies

**[policy.shape]** A policy is an object with two sections. `subjects` maps each subject's name to its definition, with `from`, a `from` line, `identified_by`, a path in a string, `has` and `description`, or to `null` for a subject with none of them (see [subjects.no_from](semantics.md#requirements)). `requirements` maps each requirement's name to its definition, with `subject`, `checks`, `require`, `min_subjects`, `description` and `meta`. `subject` is the name of an entry in `subjects`, and each check in `checks` is a sentence, a list of them under `assert`, or an `any_of` of them (see [The shape of a sentence](#the-shape-of-a-sentence)). The policy also has `ergo_spec`, the version of the spec it's written for (see [policy.version](#policies)), and can have a `description` and a `meta` of its own, next to its sections.

**[policy.version]** A policy says which version of the spec it's written for in `ergo_spec`, at its top, like `ergo_spec: v0.7-dev`. YAML reads `v0.7-dev` as text, so it needs no quotes, but `ergo_spec: 0.1` is a number. It isn't called `ergo`, because OPA loads a policy written in YAML as data next to `ergo.rego`, and `data.ergo` is where `package ergo` lives, so `ergo: v0.7-dev` would stop `ergo.rego` from compiling. A policy without `ergo_spec`, or with `null`, is written wrong, and so is one whose `ergo_spec` isn't a string or isn't the version the implementation follows. An implementation follows one version. That makes the `$well_formed` row of every requirement fail, with an input named `policy ergo_spec` holding `["missing"]` when it's missing or `null`, `["not a string"]`, `["not a version V0.1"]` for a string that isn't a version (a `v`, a number, a dot and a number, and optionally `-dev`, like `v0.5` or `v0.7-dev`), or `["unsupported version v0.1, expected v0.7-dev"]` for a version the implementation doesn't follow. The spec has one version for the policy, the report and what one means for the other, see [Versions](README.md#versions).

**[policy.no_requirements]** A policy with no requirement to hold the `$well_formed` row, because `requirements` is missing, `null`, not an object or empty, gets a requirement of Ergo's own, `$policy`, so the report says what is wrong. The requirement has no `description` or `meta` of its own (`""` and `{}`), `require` `every`, `subject` `"$policy"`, `status` `not_met`, `subjects` with `total` and `matching` 0, `causes` of `[{"cause": "value", "rows": 1}]`, and one check, `$well_formed`, with the description `The policy is written correctly` and the expression `count(problems) == 0`. Its one row has the subject `{"type": "$policy", "id": "$policy"}`, fails with `value`, and its `inputs` hold `requirements`, with `["missing"]` when it's missing or `null`, `["not an object"]` or `["empty"]`, and the policy's own problems, like `policy ergo_spec` ([policy.version](#policy-version)), all sorted by name. A policy that isn't an object has `policy` with `["not an object"]` in place of `requirements`. A `requirements` that isn't an object has no requirement, a list with items included. The report's `subjects` stays empty, and its `compliant` is `false`. A policy with a requirement is reported as before, and its policy problems stay on each requirement's `$well_formed` row. The violations list the row, as they list any row that failed.

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

An object with `assert` and any other field is written wrong, with `unknown field <name>`, and an `assert` that isn't a string or a list of strings is written wrong, with `invalid assert`, or with `empty assert` for an empty list. A problem with one line of a list of two or more starts with the line's number, like `line 2: unclosed quote at column 6`. An object with neither `assert` nor `any_of` is written wrong with `missing assert`, see [policy.old_fields](#policies). The report's entry for a sentence check has its `description`, its `meta` and its `expression`, and `$refs` for each `$params` or `$input` path it reads after `named by`, after a phrase that takes a list, or after `contains` or `does not contain`. The `$applies` check of a requirement has `$refs` for each `$params` or `$input` path the conditions of its subject's `from` line read.

**[sentence.line]** A check, a filter, or one condition of a `whose`, is one line. It holds one assertion: a thing, then a phrase, then the phrase's arguments.

```
approved_by is not empty
environment is "prod"
every commits.verified is true
every review.incidents.action_ticket, if any, is not empty
some approvers whose state is "APPROVED" exists
count of findings whose source is "claude" is claude_found
sum of stages.usd equals total_usd within 0.01
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
- `whose` holds one or more conditions joined by `and`, and each condition starts with its own `whose` or `that` (see [sentence.condition.word](#every-some-and-whose)): a path and a phrase after `whose`, a phrase after `that`, never another `every` or `whose`. The `whose` of a subject's `from` line is the one exception: its conditions can also be a one-line `every` or `some`, see [sentence.subject.condition](#subjects). A condition can start with `count of` or `sum of`, like `whose count of findings is at least 1`, because that's still one condition with a phrase. Its path has no `whose` of its own
- `and` does two jobs and nothing else: it joins conditions, each with its own `whose` or `that`, and it joins whole assertions, see [sentence.assert.list](#the-shape-of-a-sentence). Each side of an `and` is a whole condition or a whole assertion, so the result is a flat list, not a tree. An `and` followed by a path starts a new assertion, and an `and` followed by `whose` or `that` adds a condition. An `and` never joins a `whose` to its assertion
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

**[sentence.assert.and]** An `and` between assertions means exactly what a new line under `assert` means. A one-line `every` or `some` ends at the `and`, and the assertion after it starts from the subject again, or from the `for` names. So in `every items.price is at least 2 and owner is "x"`, `price` is read on each item and `owner` on the subject. Any assertion can start with `every`, `some`, `count of` or `sum of`, so `state is "MERGED" and every commits.verified is true` is two assertions on one line. A list and the joined line never read differently, so the report's `expression`, which joins the list with `and`, is always a sentence the policy could have written. The `and` between assertions can't be confused with the `and` of `whose` or of `between`: the tokenizer reads `every items.price whose kind is "a" and qty is 1 is at least 2 and owner is "x"` one way.

## Paths

**[path.steps]** A path is written as a sentence writes it (see [sentence.path.string](#paths)). A bare first key starts at the subject, `$input` starts the path at the input and `$params` at the params.

**[sentence.path.string]** A path is keys joined by `.`, like `git_commit_info.sha1`. A key is written bare when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` and `-`, so Kosli's `secrets-scan`, `pull-request` and `coverage-verification` need no quotes. Any other key is quoted as a JSON string, like `metadata.labels."app.kubernetes.io/name"`, and so is any key with a `$` in it, like `"$schema"` or `"foo$bar"`. The report prints keys by the same rule, so `$` only ever starts `$params` or `$input`, and a path from a row can be pasted into a policy.

**[sentence.path.start]** A bare first key is a field of the subject, except the subject's own name, which is the subject itself (see [sentence.path.subject](#paths)). Right after `whose` and after `sorted by`, the subject's own name is a field of the focus like any other key, and so is a name in double quotes, even one that is a word of the grammar. Inside a relative clause, a bare first key is a field of the focus instead (see [sentence.resolve.clause](#where-a-name-resolves)). An alias given by `as` on a `for` line is a bare word too, and so is a part's alias (see [parts.shadow](semantics.md#parts)). Either shadows a field with the same name, the subject's or an item's, except right after `whose`, a `count of` or `sum of` there included (see [sentence.for.scope](#the-for-line) and [parts.where](semantics.md#parts)). A first key written with a dot, like `.approver` or `.region`, is always the field: never a word of the grammar, never the subject's own name, and never an alias, whether a `for` alias, a part's or a parent subject's name. `$params` starts at the params and `$input` at the input. Any other `$<word>` is read by the grammar the same way, as a start, after `named by` or in brackets, and the line is written wrong with `unknown name $<word>`, next to any other problem it has. A line that doesn't parse says why, and an unknown name doesn't hide that.

**[sentence.path.subject]** The name of the subject, as the requirement's `subject` gives it, is the subject itself, whatever it holds: an object, a string, a number, a list or `null`. It's a whole path, written where an assertion starts: on the left of a check, after an `and` between assertions, at the start of an `any_of` option, and after `every`, `some`, `count of` and `sum of`. On the left of a `whose` and after `sorted by`, in a check, a `for` line or a `from` line, it is the item's field instead: with subject `s`, `count of xs whose s is 1` counts the items whose own `s` is 1, and so does `from: every xs whose s is 1` for the subject `s` itself. After a `for` line it's still the subject, not the item of the `for`. With subject `region` from `every deployment.regions`, `allowed: region is one of $params.allowed_regions` checks each region string. A check on the name reads the subject as a check on a field would read a value there, so `region is a string` on `null` fails with `null`, on `3` with `value`, and `region is an object` passes for an object. A row's `inputs` name it by the subject's name, like `region`, and a failed item `item 1 of region`, as it would name `item 1 of v`, and so does an `$applies` row. A name with a space, like `production deployment`, is written in double quotes where an assertion starts, and a quoted name that is a word of the grammar reads the subject too. The name wins over a field of the same name: a field called like the subject is written `.region` (see [sentence.words](#words-a-field-cant-be-called)), and the report prints `.region` for it.

**[sentence.path.subject.name]** A subject can have any name. A subject called `it`, `It` or `items` is an ordinary subject, and `it` is an ordinary word: a field, an alias and a part can all be called `it`, and a `for` alias called `it` is fine.

**[sentence.path.subject.step]** The subject's name followed by a step, a position or `named by`, like `pr.author`, `pr[0].y` or `pr named by k`, is allowed only inside a relative clause, and `pr` alone is allowed everywhere. Inside one, where a bare name reads the focus, it reads the subject: with subject `pr`, `count of approvers whose username does not equal pr.author is 1` reads the pull request's `author`. The key of `pr named by k` is a bare name there, so it is each approver's `k`, and the item is named in the message: an approver without `k` fails as `absent`, with `item 1 of approvers: k is missing`, and one whose `k` names a field the subject doesn't have fails as `absent` too, with `item 2 of approvers: pr named by k is missing`. To take the key from the subject, write it with the subject's name, after any path: `count of xs whose v equals pr named by pr.k is 1` reads the subject's field named by the subject's `k`, and `count of xs whose v equals $params.m named by pr.k is 1` reads the param named by the subject's `k`, whether the path starts at `$params`, `$input`, an alias, a part, a parent or the item. A step after the key belongs to the path, so `pr named by pr.k.d` reads `d` of the subject's field named by `pr.k`. A `k` that's missing, `null` or not text fails the row as a plain check does, with `pr.k is missing`, `pr.k is null` or `pr.k is 3, which isn't text`. Elsewhere, with subject `s`, `s.name`, `s."x"`, `s[0]`, `s[0].x`, `s named by $params.k` and `first of s.name` are written wrong with `<path>: nothing can follow s, which means the subject: for a field called s, write .s.name`, where the path is the line as written and the field is the steps that followed. The name is the subject in an `any_of` option, in a `for` line, after it and on the right side too, so `pr.author is "ann"` and `every approvers.username does not equal pr.author` are written wrong. `named by s`, with the subject's name as the key, is written wrong with `named by s: s is the whole subject, so it can't name a key`. A position is written in words before the name, as for a field: `first of s` and `item 2 of s` read one item of a subject that is a list, and give what the same position gives on a field's list (`absent` on an empty list, `unusable` on something that isn't a list), wherever a position is allowed for a field. Brackets straight after the name, like `s[0]`, are not a position: they are written wrong like any other step, and the problem says to write `.s[0]` for a field called `s`.

**[sentence.path.subject.right]** The name of the subject reads the subject on the right side of a phrase too, like `$params.wanted equals region` and `region is $params.wanted`, as a term of `plus`, after a `count of` or a `sum of` there, and on the right of a `whose`: `every items whose owner is region` compares each item's `owner` with the subject, and `every items whose owner is .region` compares it with the item's own `region`. A name in double quotes is a value there, as any quoted string is, so it never reads the subject on the right side. The key of a `named by` is the one place the name isn't read ([sentence.path.subject.step](#paths)).

**[sentence.path.part]** A part of the subject, declared with `has` (see [parts.syntax](#parts)), is read by its alias as a bare first key, wherever a bare first key reads the subject ([parts.where](semantics.md#parts)), and gives the rows of the path it stands for ([parts.swap](semantics.md#parts)). Inside a relative clause, it's read on the right side and never right after `whose`, as a `for` alias is ([parts.where](semantics.md#parts)). `named by` a bare word that is a part's alias is written wrong, with `named by <alias> reads a part, which isn't supported yet`, because it would otherwise read the subject's field of that name. A part's own path is written as a `from` line's path is, so it never starts with an alias.

**[sentence.path.index]** `item 3 of items` reads the third item of `items`, counting from 1, `item 2 from last of items` the second from the end, and `first of items` and `last of items` read the ends. The path after `of` is the whole rest of the path, so `item 3 of pull_request.commits` picks the third commit, and a field of that item has no word form in the sentence: name the item on a `for` line ([sentence.for.pick](#the-for-line)), or write `pull_request.commits[2].sha` with brackets, which count from 0 as [sentence.path.brackets](#paths) says. `item 0 of items` is written wrong. The report prints the word form when the position ends the path, so `commits[2]` prints as `item 3 of commits`, and prints the brackets when a key follows them. No policy in the corpus needs a position.

**[sentence.path.argument]** The left side of a sentence is always a path. The right side can be a value or a path, and these rules decide which:

- A quoted string on the right side is text. `is "prod"` compares with the text prod, never with a field called `"prod"`.
- A word of the grammar on the right side is never a field name (see [sentence.words](#words-a-field-cant-be-called)). `is empty` is the phrase, `is true` is the value.
- A field with one of those names is written with a dot in front: `is .empty`, `is .true`. The dot is allowed on any field, so `equals .total_usd` means `equals total_usd` when no alias is called `total_usd`, and the report prints it only where it's needed. Where an alias has the same name, the dot is how to read the field (see [sentence.for.alias](#the-for-line)).
- A key that has to be quoted, like `$schema`, is written with the dot too: `is ."$schema"`.

**[sentence.path.dynamic]** `<path> named by <reference>` reads the key that the reference holds, as a ref step in the [model](semantics.md#the-model-of-a-check) does, and the path can go on after it: `artifacts_statuses named by $params.artifact_name.attestations_statuses`. The reference is `$params` or `$input` plus one key, or one bare key. A bare key is an alias from a `for` line, like `persona_blob_shas named by persona`, or else a field, read where a bare first key would be read (see [sentence.path.start](#paths)): `$params.max_days_by_severity named by severity` reads the subject's `severity`, and inside a relative clause the focus's. Without that limit, `named by $params.a.b` could end the reference after `a` or after `b`, and the tokenizer found 24 lines in the corpus that read two ways because of it.

**[sentence.path.brackets]** Brackets are the other spelling: `artifacts_statuses[$params.artifact_name]`, `persona_blob_shas[persona]`, and `items[2]` for a position. A written number in brackets picks a position and a written string picks a key. A reference in brackets reads a key, as `named by` does, so it has to hold a string, and a number it holds never picks a position. The report prints the word form. A position above 9007199254740991, the largest whole number a 64-bit float holds exactly, is written wrong, in brackets or after `item`, with `<number> can't be a list position`.

**[sentence.path.keys]** In `from`, `<path> named by each of <list>` makes each listed key a subject: `artifact.attestations named by each of $params.required_scans`. The list is read from `$params` or `$input`, and a path that starts anywhere else is written wrong ([subjects.keyed.list](semantics.md#requirements)). There is no bracket form for it, because `a[x]` picks one thing in every language, and a parameter meant to be one name that arrives as a list would turn one subject into several instead of failing. `from` doesn't name its subjects: a check that needs a name for an item puts the walk on a `for` line, and the subject's fields are bare.

## Where a name resolves

A sentence decides what each name reads, never the data. These rules use four words. The **root** is where a path starts. The **focus** is what a name resolves against inside a relative clause, like each approver. A **relative clause** starts at `whose` or `that` and ends where its condition ends, and each `and whose …` or `and that …` starts a new one about the same focus. To **resolve** a name is to work out what it reads.

**[sentence.resolve.root]** Every path starts at a root: the subject, unless its first name is `$input`, `$params`, a `for` alias, a part, a parent subject's name or the subject's own name, which choose their own root. Outside a relative clause, a name resolves from its root: at the start of an assertion, in the path after `every`, `some`, `count of` and `sum of`, on the right side of their phrase, after an `and` that starts a new assertion, in an `any_of` option, and on the lines under a `for` line. So a bare name there is the subject's field. With the subject `pr` on `{"author": "ann", "approvers": [{"username": "bob"}, {"username": "ann"}]}`, `every approvers.username does not equal author` compares each username with the pull request's `author`: `bob` passes and `ann` fails with `value`. A `named by` field there is read on the subject too, so `every rows.n is at least m named by k` reads the subject's `m` and `k`. Comparing two fields of one item takes a `for` line: `for: every approvers as approver` with `assert: approver.approved_at is after approver.assigned_at`.

**[sentence.resolve.focus]** `every`, `some`, `count of` and `sum of` put each value their path ends at in focus, and so does an item of a `for` line and a `from` line. The path is taken as written: in `count of approvers.username whose state is "APPROVED"`, the focus is each username, so `state` resolves at `approvers[i].username.state`. A focus that isn't an object, `null` included, can't hold a field, so a condition that reads one fails as `not_an_object`, and the message names the value after its item: `item 1 of approvers: username is "ann", which isn't an object`. A focus that is missing fails a condition that reads it as `absent`, like `item 2 of approvers: username is missing`, and one the path couldn't reach fails as the path does. To count approvers, write `count of approvers whose state is "APPROVED"`. With `{"xs": [{"b": 5}, {"b": 6}]}`, `count of xs.b that is 5 is 1` puts each `b` in focus and passes.

**[sentence.resolve.clause]** A relative clause resolves both sides of its condition against the focus: `deployments whose finished_at is after started_at` compares two fields of each deployment. `that` is the focus itself. The name right after `whose` is always a field of the focus, whatever else it is called, an alias, a part, a parent's name or the subject's own name included, because `whose x` means "with its x": with `for: every environments as env`, `deployments whose env is "prod"` reads each deployment's `env`. The field after `sorted by` resolves against the focus the same way. Elsewhere in a relative clause, a name that chooses its own root ([sentence.resolve.root](#where-a-name-resolves)) reads that root: `approvers whose username does not equal pr.author` reads the subject's `author`, and `approvers whose username is in $params.staff` the params. The conditions of a `from` line are relative clauses about each candidate subject, and so is a `for` item's `whose`.

**[sentence.resolve.nested]** Everywhere else, a name resolves from its root: the phrase after `every`, `some`, `count of` or `sum of` and its right side, a new assertion after `and`, and the lines under a `for`, outside a relative clause. Inside one, the clause's focus takes the place of the root: a nested `every`, `some`, `count of` or `sum of` reads its path and its right side against that focus, and its own `whose` against its own new focus. In `xs whose count of ys.k is 1`, `ys` is each x's, and the focus of the `count of` is each `k`. In a `from` line, `releases whose some files.owner is steward` reads each release's `files` and `steward`, because the condition is about the release.

**[sentence.resolve.dot]** A leading dot only escapes a first name that clashes with a word of the grammar, an alias, a part, a parent's name or the subject's own name, and resolves exactly where the bare name would: `every approvers.username is .pr`, with the subject `pr`, reads the subject's field `pr`, and `approvers whose username is .pr` reads each approver's.

The words that put something in focus:

| word                                       | example                            | in focus                                    |
| ------------------------------------------ | ---------------------------------- | ------------------------------------------- |
| `every`, `some`                            | `every approvers.username …`       | each username                               |
| `count of`, `sum of`                       | `count of approvers …`             | each approver                               |
| `distinct` after one of those              | `every distinct xs.b …`            | each different `b`                          |
| a `for` item (`every`, `some`, a position) | `for: every approvers as approver` | each approver, named `approver`             |
| a `from` line                              | `from: deployments whose …`        | each deployment (each candidate subject)    |
| one of these inside a relative clause      | `xs whose count of ys.k is 1`      | each `k` of each x's `ys`, inside the focus |

Relative clauses, where names resolve against the focus:

| word                                | example                                             | resolves                          |
| ----------------------------------- | --------------------------------------------------- | --------------------------------- |
| `whose`                             | `approvers whose state is "APPROVED"`               | `state`: each approver's          |
| its right side                      | `deployments whose finished_at is after started_at` | `started_at`: each deployment's   |
| `that`                              | `ws that starts with "b"`                           | each w itself                     |
| `and whose`, `and that`             | `… and whose username …`                            | a new relative clause, same focus |
| `named by <key>` inside one         | `xs whose t named by k is 1`                        | `k`: each x's                     |
| `sorted by` (not a relative clause) | `last of commits sorted by timestamp`               | `timestamp`: each commit's        |

Everywhere else, names resolve from their root:

| place                                                     | example                                          | resolves                                                                                   |
| --------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| the start of an assertion                                 | `author is "ann"`                                | the subject's `author`                                                                     |
| the phrase after `every`, `count of` …                    | `every approvers.username does not equal author` | `author`: the subject's                                                                    |
| `and` followed by a path or `every` …                     | `… and author is "ann"`                          | a new assertion from the root                                                              |
| lines under a `for`                                       | `approver.username is in $params.staff`          | `approver`: the alias; bare names: the subject's                                           |
| `plus` terms, `followed by` pieces, `elapsed from … to …` | `x is "v" followed by tag`                       | wherever they stand: from the root outside a relative clause, against the focus inside one |

Names that choose their own root, anywhere but right after `whose` or `sorted by`:

| name                    | set up by                                                                     | example                                                                    | root                                                                           |
| ----------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `$input`, `$params`     | nothing: always there                                                         | `author is in $params.staff`                                               | the input, the params                                                          |
| a `for` alias           | `for: every approvers as approver`                                            | `approver.username is in $params.staff`                                    | each approver of the subject                                                   |
| a part                  | subject `pr` with `has: {coverage: attestations.coverage}`                    | `coverage.pct is at least 80`                                              | the subject's `attestations.coverage`, so it reads `attestations.coverage.pct` |
| a parent subject's name | subject `pr` with `from: artifact.pull_requests`, so `artifact` is its parent | `base equals artifact.branch`                                              | the artifact this pull request was read from                                   |
| the subject's name      | the requirement's `subject: pr`                                               | `pr is an object`, and `approvers whose username does not equal pr.author` | the subject itself. `pr.author` only inside a relative clause                  |
| a leading dot           | a field named like a grammar word or the subject, like `empty` or `pr`        | `.empty is true`, `.pr is "x"`                                             | no new root: escapes the clash and resolves where the bare name would          |

## Subjects

**[sentence.subject.from]** A subject's `from` takes the shape of a `for` item without `as`, and with `every` when its path has more than one name and reads a list ([sentence.subject.every](#subjects)): a path, optionally `named by each of` a list, optionally conditions joined by `and`, each starting with `whose` or `that`. The conditions read the subject, as a `whose` reads its item:

```yaml
subjects:
  emergency change:
    from: deployments whose environment is "prod" and whose change_type is "emergency"
    identified_by: id
```

**[sentence.subject.every]** `every` in front of a `from` line's path reads one list at each name of the path and one at the value it starts at, the last name included, and each value it ends at is a subject: `from: every artifacts.pull_requests` makes every pull request of every artifact a subject. They're one flat list, independent of the artifacts: their rows have no `in`, and they're counted once ([subjects.every](semantics.md#requirements)). A line with more than one name needs `every` to read a list, wherever it is, and without it fails when the report runs ([subjects.from.list](semantics.md#requirements)). A line with one name, like `deployments`, gives each item of a list without `every`, and `every deployments` gives the same subjects but fails when `deployments` isn't a list. A line that starts at another subject's name reads it one subject at a time, so `every deployment.monitors` reads the monitors of each deployment, with the deployment under `in`. `every` never applies to the subject's name itself: `every deployment` and `every deployment whose env is "prod"` are written wrong with `deployment is a subject: write deployment whose … to narrow it, without every`. A path that starts with a dot reads the input field, so `every .artifact.p` walks the top-level `artifact`. `every` with `named by each of` is written wrong, because the names would be read under every list item with no `in` to tell them apart. A child subject does that one parent at a time. Like a check's walk, it takes ten steps at most, and an eleventh is written wrong.

**[sentence.subject.condition]** A condition in that `whose` is a one-line check that has no `whose` of its own: a path and a phrase, a phrase about the item itself after `that`, a `count of` or `sum of` and a comparison, or a one-line `some` or `every`. pr-reviewer has six with `count of`, like `whose count of compliance_status.attestations_statuses.claude-review.attestation_data.personas_ran is at least 1`. A `some` or `every` condition asks about the items of a list, so a release can be in scope when some file in it isn't documentation:

```yaml
subjects:
  release:
    from: release whose some files.path does not match "^docs/"
  docs_release:
    from: release whose every files.path, if any, matches "^docs/"
```

The condition is a relative clause about the subject, so both its sides resolve against the subject ([sentence.resolve.clause](#where-a-name-resolves)): its path starts at the subject, a bare name in its phrase is the subject's field too, and a parent subject's name on the right side is the parent, as in the other conditions. So `release whose some files.owner is steward` keeps a release when one of its files is owned by the release's `steward`. `every` takes `, if any,` and `some` doesn't, so `some files.path, if any, matches "x"` is written wrong with `if any can't go with some`. A `some` or `every` condition with a `whose` of its own, like `release whose some files whose kind is "src" matches "x"`, is written wrong with `a condition after whose can't have a whose of its own`, and so is a `count of` or `sum of` with one. A `whose` in a check or on a `for` line takes no `some` or `every` condition.

**[sentence.subject.applies]** A subject with conditions gets an `$applies` row. Its `expression` is the conditions in the order written, each in the report's spelling and without its `whose` or `that`, joined with ` and `, like `environment is "prod" and change_type is "emergency"`, and its `inputs` hold each path they read. A `that` condition is about the item the subject is, so the report names the item by the subject's name. The entry for the item holds the plain name and a message that starts with `<name> is`, never quoted and never with a dot, because they are labels: with the subject `w` and `from: every ws that starts with "b"`, the name is `w` and the message starts with `w is`, and with the subject `my w`, `item` or `that` they start with `my w`, `item` or `that`. The `expression` is a sentence, so it spells the name the way a check has to write it, in quotes when the name has a space or is a word of the grammar and bare otherwise: `w starts with "b"`, `"my w" starts with "b"`, `"item" starts with "b"`, `"that" starts with "b"`. The entries of `inputs` stay sorted by name. A `some` or `every` condition gives the `inputs` and the cause that the same sentence gives as a check row, like `files[].path` with the list of paths, and `artifact.owner` too in `some files.owner is artifact.owner`. The row also has what that check row has: `failed_items` for one `some` or `every` condition, and `failed_assertions` for several conditions, see [scope.failures](semantics.md#scope). A subject where it passes is in scope, and one where it fails with `value`, because no item passes `some` or an item fails `every`, is out of scope. A subject a condition can't decide about, like a deployment with no `change_type`, or a `some` or `every` whose list is missing, `null` or not a list, or whose items have no usable field, fails the requirement as `absent`, `null` or `unusable` rather than dropping out of it. An `every` over an empty list gives `value` and is out of scope, unless it has `, if any,`, see [sentence.whose.every](#every-some-and-whose).

**[sentence.subject.chain]** A subject can start from another subject, by that subject's name, and is then a child subject of it: `from: artifact.attestations_statuses named by $params.pr_attestation_name.pull_requests`, where `artifact` is a subject of the same policy. Its rows carry the parent's id under `in`, like `{"type": "pull request", "id": "…/pull/8", "in": {"artifact": "sha256:…"}}`, `min_subjects` counts per parent (see [subjects.chain.count](semantics.md#requirements)), and a check reads the parent by its name, like `artifact.name`. So does the right side of a `whose` in the child's own `from` line, like `from: artifact.pull_requests whose base is artifact.branch`, and a grandchild's `from` line reads every ancestor the same way. The parent's name reads like an alias ([sentence.path.start](#paths)): on the right side inside an item's scope, never on the left of a `whose`, and `.artifact` is the field. In the corpus, four `from` lines descend this way, all from an `artifact` subject: sdlc-policies 0007 and 0008, the server's copy of 0008, and server 0010.

**[sentence.subject.quoted]** A subject whose name has a space starts a chain with the name quoted, like any key with a space: `from: "production deployment".pull_requests`. YAML won't take a plain value that starts with a quote and goes on after it, so the whole line goes in single quotes: `from: '"production deployment".pull_requests'`. The same goes for any sentence that starts with a quoted key. A subject named like a word of the grammar (see [sentence.words](#words-a-field-cant-be-called)) starts a chain quoted the same way, like `from: '"empty".items'`, because bare it would read a field, and the report prints it so, `"empty".items`, and so does a sentence that starts with it. A subject can't be named `$input` or `$params`, because those start a path at the input and at the params, so a requirement that uses one, directly or through a chain, is written wrong and `$well_formed` says `a subject can't be named $input` (or `$params`) under `subjects.$input` (or `subjects.$params`). No policy in the corpus needs it, though 19 of its subject names have a space. The tokenizer reads `"production deployment".pull_requests` one way, as a chain from that subject.

**[sentence.subject.narrow]** A chain can narrow instead of descending: `from: defect whose severity is "critical" and whose status is one of "open", "in_progress"` is a `defect` with two more conditions. Its rows are rows of the parent, with the same id and no `in`. DEV-0409 and DEV-0410 use it.

**[sentence.subject.depth]** A chain can be three subjects deep, one more than the corpus needs, see [subjects.chain.levels](semantics.md#requirements). No chain in the corpus is more than two subjects deep.

**[sentence.subject.own]** A subject's own name at the start of its own `from` path is the input field, so sdlc-policies 0004's `lockfile` subject can have `from: lockfile whose status is "COMPLETE"`, and so is the name right after `whose` there, the candidate's field, as [sentence.resolve.clause](#where-a-name-resolves) says. Anywhere else on that line, like the right side of a `whose`, it is the candidate itself, as it is in a check: with subject `d`, `from: every ds whose x equals d` compares each candidate's `x` with the whole candidate, and `from: every ds whose x equals .d` with its field `d`. Any other subject's name starts a chain. `$input.artifact` reaches the input field `artifact` even when a subject named `artifact` exists. The tokenizer applied these two rules to every `from` line in the corpus and found exactly the six chains it has.

**[sentence.subject.short]** A subject with no `from` reads the input field of its own name. It can still have `identified_by`:

```yaml
subjects:
  artifact:
    identified_by: artifact_fingerprint
  lockfile:
    from: lockfile whose status exists and whose status is "COMPLETE"
    identified_by: name
```

The map is the only way to write `subjects`, and a simple subject is a name with nothing under it.

## Values

**[sentence.value.scalar]** A value is written as JSON writes a scalar: a string in double quotes, a number, `true`, `false` or `null`. A string can also be in single quotes, which keeps backslashes as written, so a regular expression doesn't need them doubled: `'^\s*FROM'` is `"^\\s*FROM"`. Inside single quotes, `\'` is a quote and `\\` a backslash. A number has to be `0` or have a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, as a number in a policy does, so `x is at least 1e400` is written wrong. It also has at most 15 significant digits, counted on the value without leading or trailing zeros, so `1.50` has 2 and `1e20` has 1, while `l equals 1234567890.1209567890` is written wrong with `number with more than 15 significant digits: 1234567890.1209567890`. A longer number can only come from the input or the params, and [value.number](semantics.md#values) compares it on every digit.

**[sentence.value.list]** A list of values is the values separated by `, `, with no brackets: `is one of "staging", "prod"`. A value can hold a comma, `matches "^fix(, |: )"`, because commas inside quotes don't separate.

**[sentence.value.path]** An argument that isn't a value is a path. So `is "prod"` compares with text and `equals total_usd` with a field, which is what the model's `equals` and `compare` split is for. `is` before a field is read the same, and printed as `equals`.

## Words a field can't be called

**[sentence.words]** These words are read as part of a phrase, a quantifier, a position or a value, never as the first key of a path written bare: `a`, `after`, `alphabetically`, `an`, `and`, `as`, `at`, `before`, `between`, `count`, `days`, `distinct`, `each`, `empty`, `equal`, `every`, `false`, `first`, `hours`, `in`, `item`, `last`, `less`, `minutes`, `more`, `named`, `not`, `null`, `of`, `on`, `one`, `or`, `plus`, `seconds`, `some`, `sorted`, `sum`, `that`, `to`, `true`, `weeks`, `whose`, `within`. Without this, `x is empty` could also compare `x` with a field called `empty`, `x is true` with a field called `true`, and `count of x is 1` could start from a field called `count`. `that` is the word for a condition about the item itself (see [sentence.condition.word](#every-some-and-whose)), so a field called `that` is written `.that`, and `distinct` drops copies of an item (see [sentence.distinct](#every-some-and-whose)), so a field called `distinct` is written `.distinct`. A field with one of these names is written `.empty`, on either side of the sentence. The rule is the same on both sides so that it's one rule, and so that a parser never has to know which side it's on to read a key. Keys after the first are never words of the grammar, so `review.count` needs no dot.

## `every`, `some` and `whose`

**[sentence.every.walk]** `every <path>` walks into every list along the path, the first and the last included, and the assertion applies to each value it ends at. The first is the value the path starts at, so on a subject that is a list, `every name is "a"` reads the `name` of each item ([walk.start](semantics.md#every-and-some)). `every pull_requests.commits.author` reads the author of every commit of every pull request, and `every branches matches "^release/"` reads each branch of a list of strings. It passes when every value passes. Because the last list is walked too, `every pull_requests.labels is not empty` checks each label, not that each pull request has labels. So `contains`, `does not contain`, `contains all of` and `contains none of` after `every` or `some` would ask each label whether it holds a value, which a string never does, and they're written wrong, with a message that says to put the walk on a `for` line. No policy in the corpus puts them there. A bare name on the right of the phrase is the subject's field ([sentence.resolve.root](#where-a-name-resolves)), so `every $input.artifact.developers does not equal tested_by` compares each developer with the subject's `tested_by`. `$input.artifact.developers does not contain tested_by` looks like the same check, but it isn't: it passes an empty list, which `every` fails.

**[sentence.every.empty]** `every` over an empty list fails with cause `value`, because no commits isn't proof that every commit is signed. Over nested lists, each inner list must have an item too.

**[sentence.every.if_any]** `every <path>, if any, <assertion>` passes over empty lists, at every level it walks. A list that's missing, `null` or not a list still fails as `absent`, `null` or `unusable`. `if any` goes after the path and its `whose`, between commas, right before the phrase: `every items whose kind is "a", if any, is at least 2`. That's where it reads as "every item, if there are any left", and a parser can't take it for a value, because a value is never `if any`. On a `for` line it goes before `as`: `every commits, if any, as commit`. With `some`, it's written wrong, with `if any can't go with some`, since "some approver, if any" would let an empty list pass a check that asks for at least one.

**[sentence.some.walk]** `some <path>` walks the same way, and passes when at least one value passes. An empty list fails with `value`.

**[sentence.distinct]** `distinct` goes right after `every`, `some`, `count of` or `sum of`, before the path, wherever they stand: in a check, in a `whose`, on the right side, after `plus`, on a `for` line and on a `from` line. `every distinct commits.author is "ann"`, `count of distinct commits.author is at least 2`, `for: every distinct deployments as d` and `from: every distinct sbom.components` each drop the items that are exactly the same as an earlier one, see [walk.distinct](semantics.md#every-and-some), [tally.distinct](semantics.md#counts-and-sums-in-sentences), [for.distinct](semantics.md#for) and [subjects.distinct](semantics.md#requirements). A row names the check by its text, as for any walk, so `count of distinct commits.author` lists `count of distinct commits.author` and `commits[].author` in its `inputs`. There is no `distinct by` a field: items that share an id but differ in anything else are evidence that disagrees, and Ergo keeps them all.

**[sentence.distinct.place]** `distinct` anywhere else is written wrong. After a position or in the middle of a sentence, like `for: every xs as x, distinct first of ys as y` or `every xs whose distinct y is 1`, the message is `distinct goes after every, some, count of or sum of`. On a `from` line it goes after `every`, so `from: distinct sbom.components` is written wrong with `on a from line, distinct goes after every, like "every distinct sbom.components"`. A sentence that starts with `distinct`, like `distinct commits.author is "ann"`, doesn't parse, and a `for` line that starts with it says that an item starts with `every`, `some` or a position. `distinct` has a scope: the value its path points at. A phrase after `every distinct` or `some distinct` can read anything: a bare name or a name written with a dot resolves from the subject ([sentence.resolve.root](#where-a-name-resolves)), so it reads the same for every copy. With `{"lo": 3, "items": [{"b": 5, "lo": 1}, {"b": 5, "lo": 9}]}`, `every distinct items.b is at least lo` passes, with `lo` read as the subject's 3. `distinct` being a word of the grammar, a bare field called `distinct`, like `distinct is 1`, `x is distinct`, `distinct.a is 1` or `from: every xs whose distinct is 1`, is written wrong too, as [sentence.words](#words-a-field-cant-be-called) says.

**[sentence.walk.steps]** The path after `every`, `some`, `count of` or `sum of` takes ten steps at most, and an eleventh is written wrong. The limit holds wherever the path stands: in a check, on a `for` line, in a `whose`, in an `any_of` option, on either side of a phrase (`n is count of <path>` as much as `count of <path> is n`), after `plus`, and in a `from` line's `every` and `whose`, see [sentence.subject.every](#subjects). The message is `every and some over more than ten steps aren't supported yet`, or `every over more than ten steps isn't supported yet` for a `from` line's `every`. Each name in the path is a step, whether or not it walks a list, and so is a `for` alias it starts at, so with `for: every pull_requests as pr`, `every pr.commits.author` is three steps. A position like `first of` or `item 2 of` is a step too, so `every first of k1.k2.k3.k4.k5.k6.k7.k8.k9` reads and `every first of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` is written wrong. `$input` and `$params` aren't steps, in a check or in a `from` line, so `from: every $input.k1.k2.k3.k4.k5.k6.k7.k8.k9.k10` reads. A walk that starts at a part counts the part's own path in place of its alias ([sentence.path.part](#paths)): with the part `x` set to `k1.k2.k3.k4.k5.k6.k7.k8.k9`, `every x.z is 1` is ten steps and reads, and with a part of ten names it is eleven and is written wrong. A part's position counts as a step of its path, and a part of a parent subject counts in place of the parent's name and the alias. A part counts only where the path reads the part: on the left side of a `whose`, a name like `b.x.z` in `count of xs whose count of b.x.z is 1` is read on the item, so no part is counted there, and a name written with a dot is read on the item too. On the right side the part counts, a parent's part included, as it does in a `whose` of `every` and `some`. A part that isn't walked, like `x.z is 1`, has no limit. An item picked on a `for` line, like `first of reviews as review`, isn't a walk: its path takes ten names at most, and its position isn't counted.

**[sentence.condition.word]** Every condition of a `whose` chain starts with its own word, and the word is required after each `and`. After `whose` comes the path of a field and a phrase, like `whose state is "APPROVED"`. After `that` comes only a phrase, and it is about the item itself, whatever the item holds, like `every ws that starts with "b"` for a list of strings. The two mix: `every ws that starts with "b" and that ends with "y"`, and `deployments whose environment is "prod" and whose change_type is "emergency"`. An `and` followed by `whose` or `that` adds a condition, and an `and` followed by a path starts a new assertion. An `and` followed by a bare phrase, like `whose a is 1 and b is 2`, is written wrong, and so is a `whose` or `that` that has no phrase after it. A `that` goes everywhere a `whose` goes: a `from` line, a check with `every`, `some`, `count of` or `sum of`, and a `for` line.

**[sentence.that.name]** In a check, a `that` names a list it walks as a `whose` does: `count of ws that starts with "b" is 2` lists `count of ws that starts with "b"` and `ws[]` in its `inputs`.

**[sentence.whose.item]** `whose` keeps the items that pass every one of its conditions. Its paths start at the focus, the value the quantified path ends at ([sentence.resolve.focus](#where-a-name-resolves)), and the assertion is about that value too. In `some approvers whose state is "APPROVED" is in $params.staff`, `state` is read on each approver and the approver is what's checked. To filter on one field and check another, put the item on a `for` line: `for: some approvers whose state is "APPROVED" as approver` with `assert: approver.username is in $params.internal_staff`.

**[sentence.whose.undecided]** An item that a condition can't decide, because a field it reads is missing, `null` or the wrong type, isn't left out. Under `every`, `count of` and `sum of`, the check fails with that item's cause. Under `some`, it counts as an item that failed: another item can still pass the check, and if none does, the check fails with the first cause among the items. `exists` and `does not exist` are the exception, because a missing field is their answer.

**[sentence.whose.every]** Under `every`, an item that `whose` leaves out isn't checked. When `whose` leaves no items, the check fails with `value`, unless it has `if any`. No policy in the corpus uses `every ... whose` yet.

**[sentence.argument.subject]** After `count of` and `sum of`, the assertion is about one number for the subject, so a path in the argument starts at the subject: in `sum of stages.usd equals total_usd`, `total_usd` is the subject's.

## Derived values

**[sentence.derived.count]** `count of <path>` walks the path as `every` does and counts the values it ends at, so `count of findings` is the number of findings. With `whose`, it counts the items that pass.

**[sentence.derived.sum]** `sum of <list>.<field>` adds the field up across the items. With `whose` or `that`, only the values that pass. The value in focus is the number it adds, which has no fields, so a `whose` that reads a name against the focus, on either side, is written wrong, naming the first such name: `sum of xs.v whose k is 1 is 3` and `sum of xs whose k is 1 is 3` say `whose k: sum of adds up numbers, which have no fields: to keep numbers by their value, write that instead of whose`. A `whose` that reads only roots, like `$params`, an alias, a part or a parent, is fine. `that` compares the number itself, so a name on its right that would be read against the focus, a `named by` key included, is written wrong in the same way: with subject `pr`, `sum of xs.n that equals k is 1` says `that k: sum of adds up numbers, which have no fields, so k can't be read from one: to read the subject's k, write pr.k`. When the subject's name would need double quotes, or the requirement has no subject, the message stops before `: to read`. `sum of xs.n that equals $params.m named by k is 1` says the same, naming `k`, and so does a `whose` with such a key, with the message above. A `that` with a written value or a root on its right is fine: `sum of xs.v that is at least 2 is 3`, `sum of xs.v that is at least $params.lo is 3`, and `pr.lo` in place of `lo`. `count of` is left alone, because its focus can be an object. A sum over no items is 0. Numbers are added as decimals, so `0.1 plus 0.2` is `0.3`.

**[sentence.derived.plus]** `<term> plus <term>` adds numbers. A term is a path, a number, a `count of` or a `sum of`. A `whose` ends the terms, so `count of x whose n is m plus k is t` reads one way: `m plus k` is the condition's right side, and nothing is added to the count. To add to a count that has a `whose`, put the `count of` last: `k plus count of x whose n is m is t`. On the right side of a phrase, a `count of` or `sum of` takes no `whose` at all, because `x is count of y whose a is 1 and b is 2` could be one assertion with two conditions or two assertions. Count on the left and compare on the right.

**[sentence.derived.elapsed]** `<unit> elapsed from <path> to <path>` is a number: the time from the first path to the second, in `seconds`, `minutes`, `hours`, `days` or `weeks`, which are 1, 60, 3600, 86400 and 604800 seconds. It's rounded down to 6 decimal places, so 36 hours is `1.5` days and one second is `0.000011` days, and every runtime prints the same digits. Each path is read as any other path in the sentence is, and `to` between them is a word of the grammar, so a field called `to` is written `.to`. Both values must be times as [time.format](semantics.md#compare_time) says, both RFC 3339 strings, both dates, which are whole days apart, or both numbers, read as seconds to the nearest microsecond. A number must be from -9000000000 to 9000000000, about the years 1684 to 2255, so a time in milliseconds fails instead of being read as seconds. Anything else, and one string with one number, fails as `unusable`, a missing path as `absent` and a `null` one as `null`, and the worst of the two wins, as for `is before`. If the second time is before the first there is no sensible number, so the check fails as `value`. Two equal times are 0. The phrases that follow are the ones [sentence.derived.compare](#derived-values) lists:

```yaml
within_limit: days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity
```

It's a number like a `count of`, so it goes where one does: at the start of an assertion, on its own line of a list under `assert` or after the `for` line, as a term of `plus`, as the right side of a phrase, in the `whose` of a `count of`, a `sum of` or an `every`, and before `is between`. In a `whose`, an item whose end is before its start has no number, so it's left out, as any item whose condition fails with `value` is. After `every` or `some` and in a `from` line, the spec doesn't say yet, see [OPEN.md](OPEN.md#sentences-the-spec-doesnt-say-enough-about-yet). Months and years have no fixed length, so `months elapsed from` and `years elapsed from` don't read as this phrase.

**[sentence.derived.compare]** A derived value only goes with `is`, `equals`, `is not`, `does not equal`, `is ... within`, `equals ... within`, `is not ... within`, `does not equal ... within`, `is at least`, `is at most`, `is more than`, `is less than`, `is between` and `is not between`. `count of approvers is empty` is written wrong, and so is `days elapsed from a to b is empty`.

## The `for` line

**[sentence.for.line]** A check can have a `for` line before its `assert`. It holds one or two items separated by `, `, and each item is `every` or `some`, a path, an optional `whose` with `and`, and `as` an alias, or picks one item as [sentence.for.pick](#the-for-line) says:

```yaml
peer_approved:
  description: Someone other than the author approved every pull request
  for: every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver
  assert: approver.username does not equal pr.author
```

Items nest left to right, so a later one can use an earlier alias, as `pr.approvers` does. A third item is written wrong, because two is the one level of nesting Rego gives. A problem with the `for` line, its `whose` included, is listed under the check with `for: ` in front, like `for: doesn't parse` or `for: values of mixed types`.

**[sentence.for.scope]** In `assert` and in a later item, a bare first key is the subject's field and an item is reached by its alias. Inside an item's own `whose`, a bare key is that item's field. So in `for: some approvals whose role is "qa" as approval` with `assert: approval.approved_at is before started_at`, `role` is the approval's and `started_at` the subject's.

The name right after `whose` is the item's field even when an alias has the same name, because "deployments whose env is prod" can only mean the deployment's `env`. On the right side of a `whose`, and on the right side after a one-line `every` or `some`, a bare name that's an alias is the alias, and a field with that name is written with a dot: the item's in a `whose`, and the subject's after `every` or `some` ([sentence.resolve.dot](#where-a-name-resolves)). With `for: every environments as env, …`:

| sentence                                             | reads                                              |
| ---------------------------------------------------- | -------------------------------------------------- |
| `some deployments whose env is "prod"`               | the deployment's `env`                             |
| `some deployments whose environment equals env.name` | the deployment's `environment`, the alias's `name` |
| `every deployments.region does not equal env`        | each deployment's `region`, the alias `env`        |
| `every deployments.region does not equal .env`       | each deployment's `region`, the subject's `env`    |

**[sentence.for.alias]** An alias is a bare word that isn't `params`, `input` or a word of the grammar, like `every`, `as` or `empty`. For the rest of the check it shadows a field with the same name, the subject's or an item's, everywhere but on the left side of a `whose` ([sentence.for.scope](#the-for-line)). A dot in front, like `.env`, reads the field. The same alias on two items of the line is written wrong with `for: <x> is given twice`. An alias named like a subject, the check's own, a parent or any other in the policy, is written wrong with `<alias> can't be an alias: it's a subject's name`, and one named like a part of the check's own subject, of a parent or grandparent subject, or of a subject they narrow, with `<alias> can't be an alias: it's a part of <subject>`, naming the subject that declares the part. A name always means one thing, so nobody has to wonder whether it reads the subject or the alias, and a bare name never reads the parent when the item lacks the field. A bare word after `named by` that no `for` line gives is also written wrong, with `unknown alias <word>`.

**[sentence.for.fail]** Each item fails closed as a one-line `every` or `some` does: `some` over an empty list fails, `every` over one fails unless the item says `if any`, a missing or non-list path fails as `absent`, `null` or `unusable`, and an item a `whose` can't decide fails the try with its cause.

**[sentence.for.pick]** An item can start with a position instead of `every` or `some`, as [sentence.path.index](#paths) writes it, and then its alias stands for one item: `for: last of commits as last_commit`. An index in brackets doesn't pick, so `t[0] as i` is written wrong: write `first of t as i`. After the path and an optional `whose`, `sorted by` and a field counts the position in the order of that field instead of the list's:

```yaml
not_last_author:
  for: last of commits sorted by timestamp as last_commit, some approvers as approver
  assert: approver.username does not equal last_commit.author_username
```

`first of commits sorted by timestamp` is the earliest commit, `last of` the latest, and `item 2 from last of` the second latest. The field can hold numbers, RFC 3339 times or dates. `alphabetically` after the field orders strings instead, code point by code point as [sentence.phrase.alphabetical](#phrases) says, so `first of owners sorted by name alphabetically` is the first name and `last of` the last. There's no word for the reverse order, because `last of` and `item 2 from last of` count from the other end. The field is the item's, even when it's named like the subject or a parent subject, so with a parent `s`, `sorted by s` sorts by each item's `s`. It can't start with `$params`, `$input` or a position, and brackets after it pick a position in the field, as in `sorted by ts[0]`. A field with the same name as a `for` alias is written with a dot, `sorted by .c`, and without one it's written wrong, with `"sorted by" reads a field of the item, not c: write .c`, so that it can't be read as the alias. `sorted by` after `every` or `some` is written wrong, since they read every item, and so is `, if any,` with a position, since an empty list has nothing to pick. A field of the picked item is read through its alias, `last_commit.author_username`. SDLC-CTRL-0007 needs it: the approver can't be whoever pushed the last commit, though they may have pushed earlier ones while pairing. When the picked item is the second, its `whose` can read the first item's alias, and the pick is made again for each item of the first list: with `every xs as p, first of ys whose k is p.k as q`, each `p` gets the first `y` whose `k` is its own. `sorted` is the word spreadsheets use, so control owners know it, and no field in the corpus has that name. `latest` and `earliest` could come later as shorter words for times, if control owners ask for them.

**[sentence.for.comma]** The `, ` between items can't be confused with the `, ` between values, because the next item starts with `every`, `some` or a position and a value can't. The tokenizer reads `for: some approvals whose role is one of "qa", "dev" as approval, every commits as commit` one way.

**[sentence.for.assert]** A `for` line can have several assertions under `assert`, as [sentence.assert.list](#the-shape-of-a-sentence) says. sdlc-policies 0007's peer approval needs that: an approver who approved, isn't the author and approved after every commit.

## The grammar

**[sentence.grammar]** [`sentences.abnf`](sentences.abnf) is the grammar, in ABNF as RFC 5234 writes it. It says which strings are a check (`check`), a `for` line (`for-line`) and a `from` line (`from-line`), and it's what an implementation parses. The phrases below say what each form means. When the two disagree, the grammar is the syntax and the phrase is wrong.

Some rules can't be said in ABNF, so they're here:

- A bare first key is never a word of the grammar, see [sentence.words](#words-a-field-cant-be-called). A `for` alias isn't one either, nor `params` or `input`. The subject's name is a bare key like any other, so the grammar can't tell it from a field, and [sentence.path.subject](#paths) says what follows it.
- Which bare first key is a subject's field, an item's field, a `for` alias or a subject's name depends on where the sentence is, see [sentence.path.start](#paths), [sentence.for.scope](#the-for-line) and [sentence.subject.own](#subjects).
- A `for` line has two items at most, see [sentence.for.line](#the-for-line).
- `is`, `equals` and `is equal to` read the same, as do `is one of` and `is in`, and the report picks the spelling, see [sentence.print.canonical](#printing-the-sentence).
- A run of spaces between two words reads as one, and a list of values can be written with or without a space after each comma. The report prints one space and `, `.

**[sentence.ends]** Whitespace at either end of a sentence, a `for` line, a `from` line, or the path of an `identified_by` or a part, is dropped before it's read, so a YAML block like `assert: |`, which ends in a newline, reads as the sentence it holds. Whitespace is every character Unicode gives the `White_Space` property: tab, line feed, vertical tab, form feed, carriage return and space (U+0009 to U+000D and U+0020), next line (U+0085), no-break space (U+00A0), ogham space mark (U+1680), the spaces from en quad to hair space (U+2000 to U+200A), line separator (U+2028), paragraph separator (U+2029), narrow no-break space (U+202F), medium mathematical space (U+205F) and ideographic space (U+3000). A byte order mark (U+FEFF) and a zero-width space (U+200B) aren't whitespace, so a sentence that starts with one doesn't read. Inside a sentence only spaces separate words, so `x\tis 1`, with a tab after `x`, doesn't read either.
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
<path> is not <value> within <number>
<path> does not equal <field> within <number>
```

Two numbers at most that far apart, or, with `is not` and `does not equal`, more than that far apart. The gap is worked out exactly on the decimals, at any number of digits, so `0.3` and `0.1` are within `0.2`, and `1234567890.1209567990` and `1234567889.1209567890` aren't within `1`, as [value.number](semantics.md#values) says. An implementation that can't compare the numbers exactly fails the check as `unusable`, as [Values](semantics.md#values) says. `ergo.rego` and the Rust engine do when the exponents of the two sides and the number after `within` are more than 4096 apart, counted on the value, so `1e5000` and `1` within `1` fails as `unusable`. The number is 0 or more. A value before `within` that isn't a number is written wrong, with `"within" only compares numbers`, because the check could only fail. Missing: `absent`. `null`: `null`. Wrong type: `unusable`, for both forms, so `is not 3 within 1` never passes on a string or on a field that isn't there.

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
<path> is not a <type>
<path> is not an <type>
<path> is not a non-empty string
```

The field has that JSON type, or, after `is not`, has another one. Either article is accepted, and the report prints `an` before `object` and `a` before the rest. `is a non-empty string` reads into [`non_empty_string`](semantics.md#non_empty_string): a string with at least one character. `is not a <type>` reads into [`lacks_type`](semantics.md#lacks_type) and `is not a non-empty string` into [`not_non_empty_string`](semantics.md#not_non_empty_string), which passes on `""` and on any other value that isn't a string with a character in it. Missing: `absent`. `null`: `null`, for both forms, so `x is not a string` doesn't pass on a field that isn't there or is `null`. Wrong type: `value`, because checking the type is the phrase's job.

**[sentence.phrase.contains]**
```
<path> contains <value or field>
<path> does not contain <value or field>
```

The field is a list that holds the value, or doesn't. The value is one value and a path to it never walks a list, so a list it reads is looked for as one item: `pairs contains pair` passes when `pair` is `["a", "b"]` and `pairs` holds `["a", "b"]` ([contains.value](semantics.md#includes-and-excludes)). To look for each value of a list, write `contains all of`, `contains some of` or `contains none of`. Missing: `absent`. `null`: `null`. Not a list: `unusable`. Wrong type: `unusable`, when the list's items and the value have more than one type, leaving `null` aside, so `labels contains 1` on `["1"]` can't rule a subject out. `does not contain` passes on an empty list.

**[sentence.phrase.contains_all]**
```
<path> contains all of <list>
<path> contains none of <list>
<path> contains some of <list>
<path> does not contain all of <list>
```

The field is a list that holds every value, or none of them, or at least one of them, or lacks at least one of them. `contains some of` is the opposite of `contains none of`, and `does not contain all of` of `contains all of`, but each fails as the others do, so a missing, `null` or wrong-typed field never passes one by being the opposite of another. Missing, `null`, not a list and wrong type as `contains`. Values of more than one type are written wrong, with `values of mixed types`, and a list read from a path whose values have more than one type fails as `unusable`. An empty list written in the sentence can't be written, and one read from a path fails as `unusable`, because it would pass every list. `contains "a", "b"` on its own is written wrong, because it could mean all of them or any of them, so a list always takes `all of`, `none of` or `some of`.

**[sentence.phrase.matches]**
```
<path> matches <list>
<path> does not match <list>
```

The field is a string that matches at least one of the regular expressions, or none of them. They aren't anchored. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A pattern that isn't a valid regular expression is written wrong when it's in the sentence, with `invalid pattern <pattern>`, and fails as `unusable` when it's read from a path.

**[sentence.phrase.field]** The thing after `is one of`, `is in`, `contains`, `does not contain`, `contains all of`, `contains none of`, `contains some of`, `does not contain all of`, `matches` and `does not match` can be a field as well as written values or a `$params` or `$input` path: `files contains all of gap_files`, `tested_by is in reviewers`, `$input.artifact.developers does not contain tested_by`. A field here is read like any field on the right of `is at least`: from the subject, from a name of a `for` line, or from the item in a one-line `every` or `some` and in a `whose`. The row's `passed` and `cause` are what the same sentence gives with the list read from `$params` holding the same value, whatever that value and the field are, and [compare.list](semantics.md#compare) says how. The field is read for each row, so it's in the row's `inputs` after the left side, as the right side of a `compare` is, and not in `$refs`.

**[sentence.operand.followed_by]**
```
<path> is <piece> followed by <piece>
<path> starts with <piece> followed by <piece> followed by <piece>
```

Text can be joined from pieces on the right side. A piece is a written string or a field, and `followed by` goes between two of them, as many times as needed: `rego.version is tag.version followed by "-dev"` and `rego.spec is "v" followed by tag.version`. The pieces are joined in the order written, with nothing between them, and the sentence asks what the phrase asks of the joined text, so `x is "a" followed by y` equals the string `"a"` and the value of `y` put together. A right side of one piece is what it was, and there is no `preceded by`, because `"v" followed by x` says it already. The phrases that take it are `is`, `equals`, `is not`, `does not equal`, `starts with`, `ends with`, `does not start with`, `does not end with`, `contains`, `does not contain`, `is alphabetically before`, `is alphabetically after`, `is alphabetically on or before` and `is alphabetically on or after`. A written piece that isn't a string is written wrong, with `"followed by" takes text`, because the check could only fail. After `within`, the order phrases and the time phrases it is written wrong, with `"within" can't take followed by` or `"<phrase>" can't take followed by`, and after a `count of`, a `sum of`, a `plus` or an elapsed time with `"followed by" can't follow a count of, a sum of or a plus`. A piece can't hold a `plus` or a `count of`, which is written wrong with `"followed by" can't take a count of, a sum of or a plus`. Where `plus` isn't run yet, after `every` or `some`, in a `whose` and in a `from` line, `followed by` is written wrong with `"followed by" isn't supported yet after every or some, or in a whose`. It runs in an assertion and in an assertion under a `for` line, where a piece can be the alias. Text that spells the words, like `"a followed by b"`, is one string. What each piece reads is in [compare.join](semantics.md#compare). Every piece is in the row's `inputs` after the left side, in order, and the joined text isn't, as the written pieces aren't. The report prints it as written: `rego.spec is "v" followed by tag.version`.

**[sentence.phrase.starts]**
```
<path> starts with <value or field>
<path> ends with <value or field>
<path> does not start with <value or field>
<path> does not end with <value or field>
```

New, and unused in the corpus. Both sides are strings, and a written value that isn't one is written wrong, with `"starts with" takes text`, because the check could only fail. Missing: `absent`. `null`: `null`. Not a string: `unusable`. The negative forms fail the same way, so `x does not start with "a"` doesn't pass on a number or on a field that isn't there, and fails with `value` only when `x` is a string that starts with it.

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
<path> is alphabetically on or before <value or field>
<path> is alphabetically on or after <value or field>
```

New, and unused in the corpus. Both sides are strings, compared code point by code point, so every uppercase letter comes before every lowercase one: `"Zoe"` is alphabetically before `"adam"`. A string isn't alphabetically before or after itself, and it is on or before and on or after itself. A written value that isn't a string is written wrong, with `"is alphabetically before" takes text`. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A locale's order, where `"adam"` comes first, isn't the same in every runtime, so it isn't offered.

**[sentence.phrase.between]**
```
<path> is between <value> and <value>
<path> is not between <value> and <value>
```

A number from the first to the second, both included. The bounds are numbers, and the first isn't above the second, or it's written wrong. `is not between` passes on a number below the first or above the second. Missing: `absent`. `null`: `null`. Not a number: `unusable`, for both. After a `count of`, a `sum of`, a `plus` or an elapsed time, it reads the number they work out, as [tally.between](semantics.md#counts-and-sums-in-sentences) says. Its `and` belongs to `between`, so `whose qty is between 1 and 5 and kind is "a"` has two conditions. An implementation that splits `whose` on ` and ` has to skip the one after `between <value>`.

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
| `l equals 1234567890.1209567890`                         | `number with more than 15 significant digits: 1234567890.1209567890`            |
| `items[9007199254740992] does not exist`                 | `9007199254740992 can't be a list position`                                     |

**[sentence.written_wrong.self]** A sentence that compares a path with itself is written wrong, because it could only pass or only fail. That's `is`, `equals`, `is not` or `does not equal` a field, with or without `within`, the order and time phrases, `starts with`, `ends with`, `does not start with`, `does not end with` and the alphabetical phrases, when the field on the right is read from the same place as the path:

- the same path, in an assertion or a `whose`, like `x is at least x` or `whose type equals type`

After `every` or `some`, the right side resolves from the subject ([sentence.resolve.root](#where-a-name-resolves)), so `every conditions.type equals type` compares each condition's `type` with the subject's, and isn't written wrong, and neither is `every conditions.type equals .type`.

The sentence lists this problem when it has no other, or when its other problems are all `unknown name $<word>`, like `x is x and y is $foo`. With any other problem, this one is left out.

Most often the writer meant the subject's field. In a `whose` the message says how to read it, with the subject's name followed by the whole path: `to read the subject's m.b, write pr.m.b`. It says the same after `every`, `some`, `count of` and `sum of`, in an `any_of` option and on a `for` item. When the subject's name would need double quotes, like `my pr` or `empty`, or the requirement has no subject, there's no way to write it, so the message ends after `because in a whose it's read from the item`. In a `from` line's conditions it says `whose: x is compared with itself` and nothing more:

| sentence                                                   | `$well_formed` says                                                                                                        |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `x is at least x`                                          | `x is compared with itself`                                                                                                |
| `for: some conditions whose type equals type as condition` | `for: type is compared with itself, because in a whose it's read from the item: to read the subject's type, write pr.type` |
| `count of xs whose x equals x is 2`                        | `x is compared with itself, because in a whose it's read from the item: to read the subject's x, write pr.x`               |
| `count of xs whose x equals x is 2`, subject `my pr`       | `x is compared with itself, because in a whose it's read from the item`                                                    |

`contains`, `is in` and a right side with `plus` can go either way, so they're left alone.

`environment is prod` and `approved_by is empy` parse, as comparisons with a field called `prod` or `empy`, unless the subject has no such field. That's the one mistake the grammar can't catch, so the message for a missing field in an `is` argument should suggest quotes.

**[written_wrong.row]** A check [written wrong](semantics.md#the-model-of-a-check) makes the `$well_formed` row list it in its `inputs`, after `count(checks)` and `require`, in three groups: the requirement's own fields first, then the fields of its subjects, named `subjects.<subject>.<field>` like `subjects.deployment.from`, then its checks, named `checks.<name>`. Each group is sorted by name as the report writes it, quotes and escapes included, by code point, with the list of what's wrong, sorted. An `ergo_spec`, `description` or `meta` of the policy that's written wrong comes last, named `policy ergo_spec`, `policy description` or `policy meta` and sorted by name, in words and not as a path, because a name that starts with `$` is one a check can read.

## Printing the sentence

**[sentence.print.canonical]** The report's `expression` is the sentence printed from its parse in one spelling: single spaces, `is` and `is not` before a value and `equals` and `does not equal` before a field, `is one of` before written values and `is in` before a path, no alias, a string in single quotes when it holds a backslash but no single quote, no two backslashes in a row, no backslash at the end and no control character, and in double quotes with JSON escapes otherwise, a dot in front of a field only where [sentence.path.argument](#paths) needs one or where an alias has the same name, and the same where the name of another subject of the policy starts a `from` line written with a dot, like `.artifact.p` (the line without the dot is a child subject of `artifact`), numbers in their plain form ([sentence.print.numbers](#printing-the-sentence)), and values separated by `, `. Parsing the printed sentence reads the same check.

**[sentence.print.order]** `whose` conditions and assertions joined with `and` print in the order the author wrote them. The report stays byte for byte the same when the same policy runs again on the same input. That rule is for the same policy, not for two policies that mean the same: `A and B` and `B and A` print differently, because the order changes neither what passes nor the cause, and sorting would have to reach `assert` lists too, and could never reach `for` items, whose order is their nesting. A row's `inputs` stay sorted by name, because they're values that were read, not a sentence.

**[sentence.print.same]** For a sentence written that way, the printed form is byte for byte what the author wrote. Every line in the corpus prints back unchanged, the regular expression `entry does not match '^[A-Za-z0-9._-]+\s*(>=|<=|~=|!=|<|>)'` included, because its single quotes are the canonical spelling.

**[sentence.print.numbers]** A number prints as its exact value in decimal, with every digit, no exponent, no zero at the end of a fraction and no `.` when it's whole. A `-` is only printed for a value below zero. So `1e-7` prints `0.0000001`, `0.10e1` and `1.0` print `1`, `-1.2500E+2` prints `-125`, `-0` prints `0`, and `900719925474099` stays as written.

**[sentence.print.written_wrong]** A check that isn't a string or an object, or whose `assert`, `any_of`, `for` line or sentences are [written wrong](#written-wrong), still has an `expression`. It's printed from what was written instead of from a parse, so the reader sees the mistake. Each sentence and the `for` line are printed as written, with the whitespace at either end dropped ([sentence.ends](#the-grammar)), in the shape a check written right has: `for <line>: ` in front, lines joined with ` and `, and an `any_of` as [sentence.any_of.expression](#the-shape-of-a-sentence) says. A `description` or `meta` written wrong doesn't change it, so a check that's right apart from those prints from its parse. What can't be printed that way is written in angle brackets:

- a check that's neither a string nor an object: `<invalid check>`
- an object with neither `assert` nor `any_of`: `<missing assert>`, without its `for` line
- a line of `assert` that isn't a string: `<invalid assert>`, in the line's place
- an `any_of` that isn't an object: `<invalid any_of>`, and an empty one: `one of: <empty options>`
- an option that's an empty list: `<name>(<empty option>)`, and an option that isn't a string or a list of strings: `<name>(<invalid option>)`

A `for` that isn't a string, or that sits next to `any_of`, is left out, and an empty `assert` list prints as `""`. So `{"for": " every  xs ", "assert": [" x  is ", 3]}` prints `for every  xs: x  is and <invalid assert>`. One case is [still open](OPEN.md#where-ergorego-and-the-rust-engine-differ): sentences that read next to a field the check doesn't take or a `for` that isn't a string.

## Naming a path

A row's `inputs`, a ref's entry in `$refs`, an item in `failed_items` and a path in an `expression` name the paths they read the way a sentence writes them (see [Paths](#paths)). A name made of keys, positions and `named by` one key, starting at the subject, `$params` or `$input`, can be pasted into a sentence. The `[]` of a list's items has no sentence spelling yet, so a name with it can't. The names `$well_formed` gives the policy's own fields, like `checks.c` or `subjects.deployment.from`, follow [written_wrong.row](#written-wrong) instead.

**[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` or `-`, and in double quotes otherwise, so a key with a `$` in it is quoted, like `"$schema".x` or `x."$b"`. A first key that's a word of the sentence grammar (see [sentence.words](#words-a-field-cant-be-called)) has a `.` in front, like `.empty` or `.a`, and so does a field called like the subject, like `.region` (see [sentence.path.subject](#paths)). The subject itself is named by its name, and a name that starts at it follows the rules below as a field's does, so with subject `region`, `first of region` is `item 1 of region`, as `first of xs` is `item 1 of xs`. A path that starts at the input or the params starts with `$input` or `$params`, and one that starts at an alias keeps it, like `pr.author`.

**[name.dot]** Where a check, a `for` line or the `whose` of a `from` line reads the item's own field and the field is named like the subject, a parent subject, a part of the subject or an alias of a `for` line, the name has a `.` in front of the path, like `.s`, `.art.k`, `.cov.pct`, or `."$x".k` for a parent called `$x`, so it isn't taken for the subject, the parent, the part or the alias that `s`, `art.k` or `cov.pct` would read. That holds in a row's `inputs`, in its message, in the `item` and `path` of its `failed_items`, and in the `from` the report gives for the subject. It holds whether the line wrote the `.` or, on the left of a `whose`, left it out, because that side reads the item's own field anyway, but a `from` the report gives is written as it was, so there only a `.` that was written stays. A position goes after the dot: `item 1 of .art.xs`, for `.art.xs[0]`, `item 1 of .art.xs` or `first of .art.xs`. The name of the list a `count of` or `sum of` reads, and of a list a walk names with `[]`, keeps the dot too, like `.art.xs[]`. A path to a field that no subject, parent, part or alias is called has none, and neither has the read of the subject, the parent, the part or the alias itself. A name that a subject declares as a part but that is refused, like `cov` in a child subject when its parent has a part `cov`, or a part whose value isn't a path, still counts as one, so a `.cov` written in that subject's `whose` or checks is printed with its dot. A part of the parent alone doesn't: in a child with no part of its own, `.cov` is printed `cov`. The failed items nested in the failed assertions of a `for` line keep the dot as well. A check whose `for` isn't a string is printed as it was written, with the dots it had.

**[name.index]** An index at the end of a path is written `item <n> of <path>`, counting from 1, so `["xs", 1]` is `item 2 of xs`, and so is a position in a list check's `failed_items` whose path is empty: `item 2 of xss[]`. An index with more steps after it, or with nothing before it, is written in brackets, counting from 0: `xs[1].k`, `[0]`. For a subject that is a list, `it` is the thing before, so an item of it is `item 1 of it`.

**[name.ref_step]** A ref step whose ref reads one string key of the input or the params is written ` named by $params.key`, like `obj named by $params.k.v`. Any other ref step, and one that starts the path, is written in brackets, like `k[$params.a.b]` or `[$params.key]`.

**[name.part]** A path that starts with a part's alias is named with the alias, and the steps the alias stands for aren't named, so the full path `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_total` is `coverage.attestation_data.hunks_total` when it was written with the alias. A path read through a child subject's parent, like `artifact.pr_attestation.approvers`, is named the same way, and a list the alias stands for is `coverage[]` when it's walked. A path written in full is named in full, whether or not a part stands for it. A position is never hidden: when a walk (`every`, `some`, `count of`, `sum of`, a `for` line) goes through a list inside a part's path, not at its end, every name from that walk uses the full path, like `pull_requests[2].reviews[0].state` for a part `reviews` that stands for `pull_requests.reviews`. Only the names differ: a row's `expression`, `inputs` and the paths of its `failed_items` use the alias, and the values in them are the same.

## Expressions

Each check's definition in the report has an `expression` that says what it checks.

## Checks Ergo adds

**[added.text]** The checks Ergo adds have these descriptions and expressions, where `<type>` is the name of the requirement's subject, and `<from>` is the name of the subject's `from`, or `$input` when it has no steps. When `from` starts with a position on the input, `<from>` starts at `$input`, like `item 1 of $input` for `$input[0]` or `every $input[1].commits`. A `from` that starts at the input with a `named by` step, like `every $input named by $params.k`, is `<from>` as written, whatever steps follow: `count(matching(every $input named by $params.k)) >= 1`, `every $input named by $params.k named by $params.j`, `every $input named by $params.k.x` and `item 1 of $input named by $params.k` for `$input named by $params.k[0]`. For a subject that goes on into another subject, `<from>` is its `from` as written, starting with that subject's name: `artifact.pull_requests`, or, read from a part of it, `artifact.pr_attestation.pull_requests`.

| Check                  | Description                                                                                                          | Expression                                                                                             |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `$well_formed`         | `The requirement is written correctly`                                                                               | `count(problems) == 0`                                                                                 |
| `$min_subjects`        | `The in-scope <type> count is at least <n>`, or with `min_subjects: 0`, `The <type> list can be read`                | `count(matching(<from>)) >= <n>`, or `<from> can be read`                                              |
| `$unique_ids`          | `Every <type> id is unique`                                                                                          | `count(repeated(ids(<from>))) == 0`                                                                    |
| `$unique_ancestor_ids` | `Every <ancestor> id is unique` for each ancestor, outermost first, joined with ` and `, and `every` after the first | `count(repeated(ids(<ancestor's from>))) == 0` for each ancestor, outermost first, joined with ` and ` |
| `$applies`             | `The <type> is in scope`                                                                                             | the `from` line's filters in the order written, joined with ` and `                                    |

**[added.inputs]** `$min_subjects` names its input `in-scope <type> count`, `$unique_ids` names its input `repeated <type> ids`, and `$unique_ancestor_ids` names its input `repeated <ancestor> ids`, where `<ancestor>` is the subject's parent or grandparent, outermost first ([unique_ids.ancestors](semantics.md#requirements)). `$well_formed` names its first two `count(checks)` and `require`, and when `require` is written wrong, its value is `["neither every nor some"]`. A field Ergo doesn't know is listed with `["unknown field"]`, and `checks: {}` with `["empty"]`. A requirement without a `subject` has `{"name": "subject", "value": ["missing"]}`, and one whose `subject` isn't in `subjects` has `["not in subjects"]`.

**[added.causes]** The `causes` of a requirement entry is a list of `{"cause": <cause>, "rows": <number>}`, as in `[{"cause": "value", "rows": 2}]`.
