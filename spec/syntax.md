# How a policy is laid out

Draft 0.1. This file covers what a policy holds around its sentences: its sections and fields, its parts, what counts as written wrong, and how the report names paths and shows the checks Ergo adds. Checks and `from` lines are written as sentences, see [sentences.md](sentences.md). What a check means once it's read is in [semantics.md](semantics.md).

[`policy/schema.json`](policy/schema.json) describes this syntax as a JSON Schema.

## Policies

**[policy.shape]** A policy is an object with two sections. `subjects` maps each subject's name to its definition, with `from`, a `from` line, `identified_by`, a path in a string, `has` and `description`, or to `null` for a subject with none of them (see [subjects.no_from](semantics.md#requirements)). `requirements` maps each requirement's name to its definition, with `subject`, `checks`, `require`, `min_subjects`, `description` and `meta`. `subject` is the name of an entry in `subjects`, and each check in `checks` is a sentence, a list of them under `assert`, or an `any_of` of them (see [sentences.md](sentences.md#the-shape-of-a-sentence)). The policy also has `ergo_spec`, the version of the spec it's written for (see [policy.version](#policies)), and can have a `description` and a `meta` of its own, next to its sections.

**[policy.version]** A policy says which version of the spec it's written for in `ergo_spec`, at its top, like `ergo_spec: v0.1`. YAML reads `v0.1` as text, so it needs no quotes, but `ergo_spec: 0.1` is a number. It isn't called `ergo`, because OPA loads a policy written in YAML as data next to `ergo.rego`, and `data.ergo` is where `package ergo` lives, so `ergo: v0.1` would stop `ergo.rego` from compiling. A policy without `ergo_spec`, or with `null`, is written wrong, and so is one whose `ergo_spec` isn't a string or isn't the version the implementation follows. An implementation follows one version. That makes the `$well_formed` row of every requirement fail, with an input named `policy ergo_spec` holding `["missing"]` when it's missing or `null`, `["not a string"]`, `["not a version V0.1"]` for a string that isn't a version (a `v`, a number, a dot and a number, like `v0.1`), or `["unsupported version v0.2, expected v0.1"]` for a version the implementation doesn't follow. The spec has one version for the policy, the report and what one means for the other, see [Versions](README.md#versions).

**[policy.old_fields]** A requirement that has `from`, `identified_by`, `applies_to` or `subject_type`, or any other field it doesn't take, is written wrong, and the `$well_formed` row lists the field with `["unknown field"]`. A subject definition with a field it doesn't take is written wrong the same way, `applies_to` and `of` included, and so is one with `id`, the old name for `identified_by`. A `from` or an `identified_by` that isn't a string, like a list of steps, is written wrong with `["not a string"]`. A check written as an object with `op`, the syntax before 0.1, is written wrong too: an object with neither `assert` nor `any_of` is `missing assert`, and each field it doesn't take is an `unknown field`, like `unknown field op`. Its `expression` in the report is `<missing assert>`.

## Parts

A subject can have parts, named paths inside itself. What a part means is in [semantics.md](semantics.md#parts), and how a sentence reads one in [sentences.md](sentences.md#paths).

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

**[parts.path]** A part's path is written as a path in a `from` line is (see [sentence.path.string](sentences.md#paths)): keys joined by `.`, keys in double quotes, positions, and `named by` a key of `$params` or `$input`. It is a path inside the subject, so it can't start at `$params` or `$input`, and it has no `whose`, `count of` or `named by each of`. A part is as often a path to one value as to a whole attestation.

**[parts.alias]** An alias is a bare word that starts with an ASCII letter or `_` and goes on with ASCII letters, digits, `_` or `-`. It isn't a word of the grammar (see [sentence.words](sentences.md#words-a-field-cant-be-called)), `params` or `input`, or it's written wrong with `invalid alias`. Two aliases with the same name are written wrong with `alias given twice`: two parts of one subject, a part and one a subject keeps from a subject it narrows, a part and a `for` alias in a check of the subject, and a part and the name of the parent a child subject reads from.

**[parts.written_wrong]** A part written wrong makes its subject written wrong, so the `$well_formed` row of every requirement that uses the subject fails. It lists the problems under the part's alias, like `subjects.round.has.coverage`, and under `subjects.round.has` when `has` isn't an object, which is written `not an object`. A part that's neither a string nor an object is written `not a string or an object`, and an object without `from` `missing from`. A field other than `from` and `identified_by` is written `unknown field <name>`, and a `from` or `identified_by` that isn't a string `invalid from` or `invalid identified_by`. A path that can't be read is written `from: <problem>` or `identified_by: <problem>`, with the problems of a path in a `from` line, or `a part is a path: whose and named by each of can't go in it` and `a part reads inside its subject, so it can't start at $params or $input`. A bad alias is written `invalid alias` and a repeated one `alias given twice`. A part written wrong is never read as an alias, and the report still lists it, see [report.subjects](semantics.md#statuses).

## Paths

**[path.steps]** A path is written as a sentence writes it (see [sentence.path.string](sentences.md#paths)). A bare first key starts at the subject, `$input` starts the path at the input and `$params` at the params.


## Checks written wrong

**[written_wrong.row]** A check [written wrong](semantics.md#the-model-of-a-check) makes the `$well_formed` row list it in its `inputs`, after `count(checks)` and `require`, sorted by name, with the list of what's wrong, sorted. A check of the requirement is named `checks.<name>`, and a field of a subject definition `subjects.<subject>.<field>`, like `subjects.deployment.from`. An `ergo_spec`, `description` or `meta` of the policy that's written wrong comes last, named `policy ergo_spec`, `policy description` or `policy meta` and sorted by name, in words and not as a path, because a name that starts with `$` is one a check can read.

## Naming a path

A row's `inputs`, a ref's entry in `$refs`, an item in `failed_items` and a path in an `expression` name the paths they read the way a sentence writes them (see [sentences.md](sentences.md#paths)). A name made of keys, positions and `named by` one key, starting at the subject, `$params` or `$input`, can be pasted into a sentence. The `[]` of a list's items has no sentence spelling yet, so a name with it can't. The names `$well_formed` gives the policy's own fields, like `checks.c` or `subjects.deployment.from`, follow [written_wrong.row](#checks-written-wrong) instead.

**[name.keys]** Keys are joined with `.`. A key is written as it is when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_` or `-`, and in double quotes otherwise, so a key with a `$` in it is quoted, like `"$schema".x` or `x."$b"`. A first key that's a word of the sentence grammar (see [sentence.words](sentences.md#words-a-field-cant-be-called)) has a `.` in front, like `.empty` or `.a`. A path that starts at the input or the params starts with `$input` or `$params`, and one that starts at an alias keeps it, like `pr.author`.

**[name.index]** An index at the end of a path is written `item <n> of <path>`, counting from 1, so `["xs", 1]` is `item 2 of xs`, and so is a position in a list check's `failed_items` whose path is empty: `item 2 of xss[]`. An index with more steps after it, or with nothing before it, is written in brackets, counting from 0: `xs[1].k`, `[0]`.

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
