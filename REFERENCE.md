# ergo reference

This page describes everything ergo accepts and everything it returns. If you haven't used ergo before, start with the [README](README.md).

- [Policies](#policies)
- [Subjects](#subjects)
- [Requirements](#requirements)
- [Paths](#paths)
- [Reading from the input](#reading-from-the-input)
- [Naming subjects](#naming-subjects)
- [Operators](#operators)
- [Substitutes](#substitutes)
- [Custom operators](#custom-operators)
- [The report](#the-report)
- [Causes](#causes)
- [Violations](#violations)
- [Failing closed](#failing-closed)

## Policies

A policy is an object with two sections. `subjects` says what the policy checks and where to find it in the input, and `requirements` says what must be true of it. Each section maps names to definitions. You pass the policy to `ergo.report` along with the input and the [params](#params):

```rego
subjects := {
	"deployment": { ... },
	"commit": { ... },
}

requirements := {
	"approved_deploy": {"subject": "deployment", ... },
	"signed_commits": {"subject": "commit", ... },
}

report := ergo.report(input, {"subjects": subjects, "requirements": requirements}, {})
```

`ergo.report` reads only its three arguments, so the same arguments always give the same report.

A policy is plain data, so it can also live in a YAML or JSON file that OPA loads. A file in the policy directory with top-level `subjects` and `requirements` keys is read as `data.subjects` and `data.requirements`:

```yaml
subjects:
  deployment: { ... }
  commit: { ... }
requirements:
  approved_deploy: { subject: deployment, ... }
  signed_commits: { subject: commit, ... }
```

```rego
default subjects := {}

subjects := data.subjects

default requirements := {}

requirements := data.requirements

default params := {}

params := data.params

report := ergo.report(input, {"subjects": subjects, "requirements": requirements}, params)
```

Give each argument a default like this when it comes from `data`. Rego doesn't call a function with an argument that isn't defined, so a file without `requirements:`, or a run without params, would make the whole report undefined, with no rows to say why. The defaults still fail closed: with no subjects every requirement fails, because the subject it names isn't there, with no requirements the policy isn't compliant, and with no params every `$$params` read fails as `absent`. The same goes for the input: if it can be missing, give it a default too.

Because each name is an object key, two requirements can't share a name, and every row in the report points back to exactly one requirement.

A policy with no requirements is never compliant: it doesn't check anything, so it can't vouch for anything either. The same goes for a policy that isn't an object, or whose `requirements` isn't one. ergo leaves out any other section of the policy, so it changes nothing in the report.

From your own policies, call only `ergo.report` and `ergo.violations`. Rules whose names start with `_`, like `ergo._row_cause`, are ergo's own and can change or disappear in any release. If you lint with [Regal](https://www.openpolicyagent.org/projects/regal), its `leaked-internal-reference` rule flags a call to one.

## Subjects

A subject is the kind of thing a requirement checks, like a deployment or a pull request, and says where to find them in the input:

```rego
"deployment": {
	"description": "A deployment to production",
	"from": ["deployments"],
	"id": ["id"],
	"applies_to": {"is_prod": { ... }},
}
```

| Field         | Meaning                                                                                                | Default           |
| ------------- | ------------------------------------------------------------------------------------------------------ | ----------------- |
| `description` | What the subject is, in words anyone can read. ergo doesn't copy it into the report.                   | `""`              |
| `from`        | The [path](#paths) to the subjects in the input. It can end with a [naming step](#naming-subjects).    | the whole input   |
| `id`          | The path, inside one subject, to the value that identifies it.                                         | the whole subject |
| `applies_to`  | Named checks that pick which of them are in scope. A subject must pass all of them.                    | no filter         |
| `of`          | The name of another subject this one [builds on](#a-subject-built-on-another).                          | none              |

The subject's name is what the report calls each one, in every row, like `"subject": {"type": "deployment", "id": "d-2"}`, and in the descriptions of the [checks ergo adds](#checks-ergo-adds), like `The in-scope deployment count is at least 1`. So name it the way a reader would, like `deployment` or `pull request`.

A requirement names its subject with `subject`. Several requirements can name the same subject, and each one checks it on its own, with its own rows. A subject that no requirement names isn't read, so it changes nothing in the report.

A few details:

- If `from` leads to a list, each item is a subject. If it leads to a single object, that object is the only subject. If it leads nowhere, to `null`, or to anything else, like a string or a number, there are no subjects and `$min_subjects` fails with cause `absent`, `null` or `unusable`, even with `min_subjects: 0`, because that's what a typo in `from` looks like. A path through something that can't hold the next key, like `"build": "b1"` for `["build", "items"]`, gives `unusable`, and a missing or `null` parent gives `absent`, as they do in a [check](#paths). An empty list is different: it was read fine, so it fails `$min_subjects` as `value`, or passes with `min_subjects: 0`.
- The input has to be an object. A `null` input fails `$min_subjects` as `null` when `from` is empty or left out, and as `absent` when it has a step. Any other input that isn't an object, a list included, fails it as `unusable`.
- If `id` doesn't lead anywhere, the subject's id is `null`. Its rows are still there.
- No two subjects can share an id, or their rows could be identical and the report couldn't say which one failed. If two do, `$unique_ids` fails and so does the requirement. Every subject counts, even one that `applies_to` leaves out, and `null` is an id like any other, so two subjects without one clash.
- An item of the list that isn't an object, like a string or a `null`, is still a subject. Its id is the item itself, and its checks fail with cause `not_an_object`.
- Leaving out `from` or `id` is allowed, but rarely what you want. Without `from`, the whole input is checked as one subject. Without `id`, each row repeats the whole subject as its id, so two identical subjects clash.
- A subject that's written wrong fails `$well_formed` on every requirement that names it, so none of them is met. That's a subject that isn't an object, or that has a field that isn't in the table above, like `subject_type`, or whose `applies_to` isn't an object, whose `from` or `id` isn't a list, or whose `description` isn't a string, or a badly written [naming step](#naming-subjects), an `id` whose selector has a ref or `literal` deeper inside a `where` value than ergo reads, or a filter that's [written wrong](#basic-operators). The `$well_formed` row names each field with its subject, like `{"name": "subjects.deployment.from", "value": ["not a list"]}`. ergo then reads `applies_to` as a filter it can't read, so every subject fails `$applies` with cause `ill_formed`, shown as `<invalid applies_to>`, and gets no other rows. It reads a `from` as giving no subjects (shown as `<invalid from>`), so `$min_subjects` fails as `value`, even with `min_subjects: 0`, and an `id` as giving the id `null`.

### A subject built on another

When requirements check different parts of the same list, give each part its own subject, built on one that says where the list is. Say the SBOM lists components, some pinned by the lockfile and some exempt from the licence rules:

```yaml
subjects:
  SBOM package:
    from: [components]
    id: [name]
  locked SBOM package:
    of: SBOM package
    applies_to:
      locked: { op: present, path: [lock_release] }
  non-exempt SBOM package:
    of: SBOM package
    applies_to:
      not_exempt: { op: equals, path: [exempt], value: false }
requirements:
  versions:
    subject: locked SBOM package
    checks:
      matches_lock: { op: compare, left: [sbom_release], right: [lock_release], cmp: eq }
  licences:
    subject: non-exempt SBOM package
    checks:
      licence_known: { op: any, path: [licences], check: { op: non_empty_string, path: [] } }
```

A subject with `of` reads `from` and `id` from the subject it names, and keeps only the items that pass that subject's filters and its own. Everything else about it is its own: its rows and descriptions use its name, like `locked SBOM package`. It reports what the same subject written out in full would, except that `$well_formed` names a problem, or a `from` with a [naming step](#naming-subjects), after the subject it's written in.

- A subject can build on one that builds on another, and so on. The chain ends at the one subject without `of`, which gives `from` and `id`, and a subject keeps the items that pass the filters of every subject along its chain.
- A subject with `of` can't have its own `from` or `id`. They fail as `not allowed with of`.
- A chain that comes back to a subject already in it, like a subject whose `of` names itself, never reaches `from`. It fails as `leads to a loop`.
- A filter name can only be used once along a chain, because one filter would hide the other. Using it again fails as `also a filter of a subject it builds on`.
- An `of` that isn't a name in `subjects` fails as `not in subjects`, and one that names something other than an object fails the way a requirement's `subject` does.
- Any of these fails `$well_formed` on every requirement that names a subject whose chain has it, and the requirement finds no subjects. A problem is named after the subject it's in, like `subjects."SBOM package".from`.
- A requirement can name the subject others build on too, like `SBOM package` to check every component.

## Requirements

```rego
{
	"description": "Every production deployment is approved",
	"meta": {"control": "SDLC-CTRL-0007", "frameworks": ["SOC 2"]},
	"subject": "deployment",
	"require": "every",
	"min_subjects": 1,
	"checks": {"approved": { ... }},
}
```

| Field          | Meaning                                                                                               | Default   |
| -------------- | ----------------------------------------------------------------------------------------------------- | --------- |
| `description`  | What the requirement asks for, in words anyone can read. It's copied into the report.                 | `""`      |
| `meta`         | Anything else you want to keep with the requirement, like a control id or an owner. It's copied into the report. ergo never reads it. | `{}`      |
| `subject`      | The name of the [subject](#subjects) it checks.                                                       | required  |
| `require`      | `"every"`: every subject must pass every check. `"some"`: at least one subject must pass every check. | `"every"` |
| `min_subjects` | How many subjects must be left after the subject's `applies_to` for the requirement to be met.        | `1`       |
| `checks`       | Named checks that each subject must pass.                                                             | required  |

A few details:

- `meta` can hold anything JSON can, like `{"control": "SDLC-CTRL-0007", "frameworks": ["SOC 2", "ISO 27001"], "version": 3, "reviewed": true}`. Its numbers follow the same rule as numbers anywhere else in a policy: one a 64-bit float can't hold, like `1e400`, makes the requirement [written wrong](#basic-operators). So does a key that isn't a string, or a set, which a policy written in Rego can hold but JSON can't. In the report, a number is written in its plain form, so `1.50`, `1e2` and `-0` come out as `1.5`, `100` and `0`, and the same `meta` gives the same report however it was written.
- `min_subjects` defaults to 1 so that a typo in `from` fails the requirement instead of quietly passing it. Set it to `0` when you mean "if there are any, they must pass; if there are none, that's fine". It means the same under `every` and `some`. When none are left, the requirement is [not applicable](#the-report). That only holds for a list that's there: a `from` that leads nowhere still fails, as above. A `from` that ends with a [`keys` step](#naming-subjects) is the exception, because each key is a subject even when `from` leads nowhere.
- Under `some`, one subject has to pass all the checks by itself. Two subjects that each pass half of them don't count.
- A requirement with no checks, a `require` other than `every` or `some`, a check that's [written wrong](#basic-operators), or a [subject that's written wrong](#subjects), is never met. The `$well_formed` row says so, and says [what's wrong](#checks-ergo-adds), like `{"name": "require", "value": ["neither every nor some"]}`.
- So is a requirement without a `subject`, or whose `subject` isn't in `subjects`, like a typo for `deploymnt`. The `$well_formed` row says `{"name": "subject", "value": ["missing"]}` or `{"name": "subject", "value": ["not in subjects"]}`, and ergo reads it as having no subjects, so `$min_subjects` fails too. If `subjects` itself isn't an object, every requirement that names a subject fails with `{"name": "subjects", "value": ["not an object"]}`.
- So is a requirement with a field that isn't in the table above, like `from` or `requires`, because ergo would otherwise ignore it and check something you didn't mean. `from`, `id` and `applies_to` belong to the [subject](#subjects). The `$well_formed` row lists each one in order and says what's wrong with it, the way it does for a [check that's written wrong](#checks-ergo-adds), like `{"name": "from", "value": ["unknown field"]}`. Rows for the subjects are still there.
- So is a requirement that isn't an object, or whose `checks` isn't an object, whose `min_subjects` isn't a whole number of 0 or more, whose `subject` isn't a string with something besides whitespace in it, since rows and descriptions name the subject by it, whose `description` isn't a string, or whose `meta` isn't an object. `null` counts as the wrong type, except for `description` and `meta`: ergo only copies those, so a `null` one counts as not written, which is what YAML gives for an empty `description:`. `2.0` is a whole number, but `-1` and `0.5` aren't. It still has its entry in `requirements` and its `$well_formed` row, which shows each such field and what it should be, like `{"name": "checks", "value": ["not an object"]}`, or the whole requirement and its value, like `{"name": "requirement", "value": 5}`. ergo then reads `checks` as empty. A requirement that isn't an object gives no subjects. A `min_subjects` that isn't a number fails `$min_subjects` too.

### A requirement that only applies sometimes

Some controls only apply to some inputs, like "new features must be tested", which doesn't apply to a bug fix. Make the thing that decides it the subject, and filter it with `applies_to`. This one reads a [param and a ref](#reading-from-the-input):

```yaml
params:
  untested_change_types: [bug_fix, refactor]
subjects:
  deployment:
    from: []
    applies_to:
      needs_tests: { op: excludes, path: [$$params, untested_change_types], value: { ref: [$$input, deployment, change_type] } }
requirements:
  features_tested:
    subject: deployment
    min_subjects: 0
    checks:
      tested: { op: any, path: [test_runs], check: { op: present, path: [status] } }
      passed: { op: all, path: [test_runs], check: { op: equals, path: [status], value: passed } }
```

With `{"deployment": {"change_type": "bug_fix"}, "test_runs": []}`, the deployment is out of scope, and the report says so:

```json
"compliant": true,
"requirements": {
  "features_tested": {
    "status": "not_applicable",
    "subjects": { "matching": 0, "total": 1 },
    ...
```

The `$applies` entry in `checks` records the value the ref read, under `$refs`: `{"name": "$$input.deployment.change_type", "value": "bug_fix"}`. A new feature with no test runs fails `tested` and `passed`, and so does a change type that isn't listed, like `hotfix`, so a new or misspelt type has to be tested until someone adds it to the list. A deployment with no `change_type` fails the requirement, because ergo can't tell whether it applies.

The filter lists the types that don't need tests, rather than the ones that do. Listing `new_development` with `in` would also work, but then any other type, misspelt ones included, would quietly skip the tests.

Don't filter the test runs instead, with `from: [test_runs]` and `min_subjects: 0`. That lets a new feature with no test runs pass, because there's nothing to check.

### Picking the subject

The subject is what each row is about, so it's the first choice to make, and it changes more than the rows. Take "every commit was reviewed in an approved pull request", with this input:

```json
{"commits": [
  {"sha": "a1", "pull_requests": [{"number": 7, "approved_by": "bob"}, {"number": 8}]},
  {"sha": "a2", "pull_requests": []}
]}
```

With the commit as the subject, the check looks through its pull requests:

```yaml
subjects:
  commit:
    from: [commits]
    id: [sha]
requirements:
  reviewed:
    subject: commit
    checks:
      reviewed:
        description: Some pull request for the commit was approved
        op: any
        path: [pull_requests]
        check: { op: non_empty_string, path: [approved_by] }
```

| subject | check      | passed  | cause       |
| ------- | ---------- | ------- | ----------- |
| `a1`    | `reviewed` | `true`  | `satisfied` |
| `a2`    | `reviewed` | `false` | `value`     |

The requirement is `not_met`: `a2` has no pull request.

With the pull request as the subject, the same sentence turns into "some pull request was approved":

```yaml
subjects:
  pull request:
    from: [commits, 0, pull_requests]
    id: [number]
requirements:
  reviewed:
    subject: pull request
    require: some
    checks:
      approved:
        description: The pull request was approved
        op: non_empty_string
        path: [approved_by]
```

| subject | check      | passed  | cause       |
| ------- | ---------- | ------- | ----------- |
| `7`     | `approved` | `true`  | `satisfied` |
| `8`     | `approved` | `false` | `absent`    |

The requirement is `met`. Pull request 7 is approved, and `a2` is never looked at, because `from` reads one commit's pull requests. Same input, same words, opposite answers.

So before writing a check, decide:

- **What would the policy's owner list?** The report has one row per subject, so the subject is what it lists. A rule about commits should list commits, even when the evidence is organised by pull request.
- **What id would they cite?** `id` is how a row is found again, and how two reports are compared.
- **How many lists sit between the subject and the values compared?** Each one costs a level of `all` or `any`, and ergo allows [one level of nesting](#nesting). A check that needs more usually means the subject is one list too high, or the evidence was recorded at the wrong grain. Moving the subject down flattens the check, but then the report lists the smaller thing, as above.
- **Does `require` still say what the sentence says?** "Every commit has some approved pull request" is `every` over commits with `any` inside a check. With the pull request as the subject it becomes `some` over pull requests, which is only the same rule when there is one commit.

A policy can hold several requirements with different subjects over the same input, like a lockfile and each of its entries. Each requirement picks its own grain.

## Paths

A path is a list of keys that ergo follows one step at a time. `["release", "approver", "email"]` reads `release.approver.email`.

A key is a string, or a list index written as digits alone, like `0` or `12`. A string only picks a key of an object and a number only picks an item of a list, so `["a", "0"]` reads nothing when `a` is a list, and `["o", 0]` reads nothing when `o` is `{"0": "zero"}`. JavaScript reads both, so an implementation there has to check the type. A path that runs into something that can't hold its next key, like these, or a string, number or boolean where an object or list should be, fails its check with cause `unusable`, so `["pr", "state"]` on `"pr": "none"` isn't reported as a missing field. A parent that isn't there, or is `null`, is different: the field is just missing. A step that can't be a key, like `true`, `null`, a list, `-1`, `1.5`, or even `1.0`, which OPA doesn't read as `1` but JavaScript does, can never read anything. So a check with one is written wrong: it fails `$well_formed`, its rows fail with cause `ill_formed`, even as a `present` filter, and the step is shown as `<invalid step>`. The same goes for the paths in a check's `inputs`. One in `from` or `id` fails `$well_formed`.

In expressions and `inputs`, a key is written as it is when it starts with an ASCII letter (`a` to `z` or `A` to `Z`), `_` or `$`, and the rest is ASCII letters, digits, `_`, `$` and `-`. Any other key is quoted, so a key with a dot, a space or an accented letter, one that starts with a digit or `-`, and the empty key are all written in quotes. So `["metadata", "labels", "app.kubernetes.io/name"]` is named `metadata.labels."app.kubernetes.io/name"`, and doesn't look like a path four keys deep. The string key `["xs", "0"]` is named `xs."0"`, unlike the list index `["xs", 0]`, named `xs.0`. A first step written as `{"literal": "$schema"}` is named `"$schema"`, so it doesn't look like a [name](#naming-subjects). `from` takes no names and no `$$input`, so there a first key that starts with `$` is always quoted: `["$$input"]` is named `"$$input"`, and can't be mistaken for the whole input.

`from` is a path into the input. Every other path (`id`, a check's `path`, `left` and `right`) is a path into one subject, unless it starts with [`$$input`](#reading-from-the-input) or a [name](#naming-subjects).

An empty path, `[]`, reads the item itself. Use it inside `all` or `any` when the list holds plain values like strings, not objects:

```rego
"release_branches": {
	"op": "all",
	"path": ["branches"],
	"check": {"op": "matches_any", "path": [], "patterns": ["^main$", "^release/"]},
}
```

ergo names the item after its list, so this renders as `every branches: branches[] matches one of ["^main$", "^release/"]`, and the row's input is `branches[]`. An empty `each` works the same way, for a list of lists.

An empty path also reads a subject that isn't an object, like each string of `"from": ["branches"]`. There, the item is named after `from` (`branches[]`), or `$$input` when there's no `from`, because then the subject is the input and `["$$input"]` reads the same thing. That keeps it apart from a key called `input`. `$min_subjects` names it the same way, as `count(matching($$input))`, when `from` reads the whole input. Any other path on such a subject fails with cause `not_an_object`.

One step in a path can be a **selector** instead of a key. It picks the single item in a list (or an object's values) whose fields match:

```rego
"path": ["attestations", {"where": {"type": "pull_request"}}, "state"]
```

This reads the `state` of the attestation whose `type` is `pull_request`, and it works the same whether `attestations` is a list or an object keyed by name.

A selector must match exactly one item. If it matches none, or more than one, the check fails, and the row's cause says which (`unmatched` or `ambiguous`). An empty `where` matches nothing. A path can contain only one selector.

## Reading from the input

A path normally starts inside the subject. Two first steps start somewhere else:

- `$$input` starts at the top of the document given to `ergo.report`.
- `$$params` starts at the params given to `ergo.report`.

```rego
"path": ["$$input", "settings", "mode"]
"path": ["$$params", "level"]
```

Every subject reads the same value. These only mean this as the first step of a path, and any other first step starting with `$$` is reserved: it's written wrong, so it fails `$well_formed` and the check fails with cause `ill_formed`. To read a key that really is called `$$input` or `$$params`, write it as `{"literal": "$$input"}`.

A check's fixed values can be read this way too. Write `{"ref": path}` in place of the value, where the path starts with `$$params` or `$$input`. This works for `value`, `values`, `patterns`, `min`, `max`, each item in a `values` or `patterns` list, and the values in a selector's `where`, and as a step of a path (see [Ref steps](#ref-steps)). It's how a policy takes params:

```rego
ergo.report({"packages": packages}, {"subjects": {"package": {"from": ["packages"], "id": ["name"]}}, "requirements": {"licences": {
	"subject": "package",
	"checks": {"approved": {
		"op": "any",
		"path": ["licences"],
		"check": {"op": "in", "path": [], "values": {"ref": ["$$params", "allowed_licences"]}},
	}},
}}}, {"allowed_licences": ["MIT", "Apache-2.0"]})
```

With those params, a package licensed `GPL-3.0` gives this violation:

```json
{
  "requirement": "licences",
  "subject": { "type": "package", "id": "gpl-lib" },
  "check": "approved",
  "description": "",
  "expression": "some licences: licences[] in $$params.allowed_licences",
  "inputs": [
    { "name": "licences[]", "value": ["GPL-3.0"] },
    { "name": "$$params.allowed_licences", "value": ["MIT", "Apache-2.0"] }
  ],
  "cause": "value",
  "failed_items": [{ "path": "licences[0]", "value": "GPL-3.0", "cause": "value" }]
}
```

A ref or a `literal` anywhere deeper inside a value, like `"value": [{"ref": [...]}]` or `"where": {"k": [{"literal": "a"}]}`, is written wrong, because ergo wouldn't read it and would compare the object instead. To compare data that holds an object that only looks like a ref or a literal, wrap the whole value in a `literal`: `{"literal": [{"ref": [...]}]}`.

The expression says where the value comes from. What it was goes in the check's definition in the report, under `$refs`, once for the whole report and sorted by name, beside the literals the check compares against. The rows' `inputs` only hold what the check reads, like `licences[]` here, and `violations` adds the `$refs` back to each violation's `inputs`, as above. That keeps a record of what was compared, even when the params change between runs, without copying it into every row. A path that starts with `$$input` or `$$params` is something the check reads, so its value stays in the row.

### Params

Params are the third argument to `ergo.report`. ergo doesn't look for them anywhere else, so the policy that calls it picks where they come from. Reading them from `data.params`, as in [Policies](#policies), means `opa eval -d params.json` passes them in when the file holds `{"params": ...}`, and a test can write `with data.params as {...}`.

Params aren't part of the document, so `$$input.params` doesn't reach them, and `$$params` doesn't read the document. With params of `{}`, or params that aren't an object, every `$$params` read fails as `absent`. ergo has no defaults, so a policy run without its params fails instead of checking something nobody configured.

Some things worth knowing:

- A ref that leads nowhere, or to `null`, fails the check, with cause `absent` or `null`. That cause wins over anything the subject's own fields would give, because the check can't mean anything without the value. ergo has no defaults, so put the value in the params.
- A ref must be a list that starts with `$$params` or `$$input`, and it can't contain a selector or another ref. Anything else is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and the expression and `inputs` show `<invalid ref>`.
- An object with a `ref` or `literal` key and any other key is a mistake, not a value, so it fails the check the same way. Otherwise a typo like `{"ref": [...], "note": "..."}` would be compared as an object, and `excludes` would pass.
- A value that is an object with a single `ref` or `literal` key would be read as one. Wrap it in `{"literal": ...}` to take it as written. Nothing inside a `literal` is read, so `{"literal": {"literal": 1}}` is the object `{"literal": 1}`.
- `from` already starts at the top of the input, so it doesn't take `$$input` or `$$params`. `"from": ["$$input", "packages"]` looks for a key called `$$input`, finds no subjects, and fails `$min_subjects`. A [ref step](#ref-steps) works in `from`, though.

### Ref steps

A ref can also be one step of a path. It's replaced by the value it reads, which becomes the key for that step. This is how a key can come from the params:

```rego
"from": ["trail", "artifacts", {"ref": ["$$params", "artifact_name"]}],
"checks": {"attested": {
	"op": "equals",
	"path": ["attestations", {"ref": ["$$params", "attestation_name"]}, "status"],
	"value": "COMPLETE",
}},
```

With `artifact_name` set to `app` and `attestation_name` to `pull-request`, this reads `trail.artifacts.app.attestations.pull-request.status`. The expression shows where the key came from: `attestations.[$$params.attestation_name].status == "COMPLETE"`, and the value used is recorded under `$refs`, like any ref.

A ref step works anywhere in any path: first, in the middle or last, after a name or `$$input`, before a selector, and in `from`, `id`, `each`, `left` and `right`.

- The value must be a [key](#paths): a string, or a list index written as digits alone. A ref that leads nowhere, to `null`, or to anything else, like a list, means the path can't be followed, so the check fails with cause `absent`, `null` or, for anything that isn't a key, `unusable`.
- In `from`, a ref step that can't be read fails `$min_subjects`, even with `min_subjects: 0`, because ergo can't tell where the subjects would be. The `$min_subjects` row takes the ref's cause, and its definition records the ref under `$refs`, so the violation shows which param was missing.
- A `present` filter whose path has a ref step that can't be read doesn't rule subjects out. It fails the requirement, because the field it looked for is unknown, not missing.
- A ref step written with another key, like `{"ref": [...], "where": {...}}`, is a mistake, not a selector. It fails the check and shows as `[<invalid ref>]`. In `from`, it fails `$well_formed`.
- A ref's own path is read as written, so a ref inside a ref isn't followed.
- Some tools treat `$$` as an escape for `$`, like docker-compose and Make. A policy that passes through one of them reaches ergo as `$input`, which is read as a [name](#naming-subjects). No subject is called `input`, so the check fails with cause `absent`.

## Naming subjects

`from` can end with a step that names each subject: `{"each_as": "name"}`. A path that starts with `$name` then reads that subject.

If `from` leads to an object, the step makes every entry a subject, identified by its key and sorted by key. Without it, the whole object is one subject. If `from` leads to a list, every item is a subject, as without the step.

`keys` says which entries must be there. Say a build records each kind of test run it did:

```json
{
  "build": {
    "test_runs": {
      "unit-test": { "result": "passed", "report_url": "https://ci.example.com/r/101" },
      "integration-test": { "result": "failed", "report_url": "https://ci.example.com/r/102" },
      "smoke-test": { "result": "passed", "report_url": "https://ci.example.com/r/103" }
    }
  }
}
```

and you need a passing unit test, integration test and system test run:

```rego
"subjects": {"test run": {
	"from": ["build", "test_runs", {"each_as": "run", "keys": ["unit-test", "integration-test", "system-test"]}],
}},
"requirements": {"tests_passed": {
	"subject": "test run",
	"checks": {"passed": {"description": "The tests passed", "op": "equals", "path": ["result"], "value": "passed"}},
}}
```

Each key is a subject. A key the object doesn't have is still a subject, so its checks fail as `absent` (or `value`, for a `present` check), and the smoke test run isn't checked at all:

```json
[
  {
    "requirement": "tests_passed",
    "subject": { "type": "test run", "id": "integration-test" },
    "check": "passed",
    "description": "The tests passed",
    "expression": "result == \"passed\"",
    "inputs": [{ "name": "result", "value": "failed" }],
    "cause": "value"
  },
  {
    "requirement": "tests_passed",
    "subject": { "type": "test run", "id": "system-test" },
    "check": "passed",
    "description": "The tests passed",
    "expression": "result == \"passed\"",
    "inputs": [{ "name": "result", "value": null }],
    "cause": "absent"
  }
]
```

The name matters inside `all` and `any`, where paths start at each item of the list. `$name` reaches back to the subject, so an item can be compared with it. `as` names the items of a list the same way (see [Nesting](#nesting)):

```rego
"subjects": {"pull request": {
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
}},
"requirements": {"peer_reviewed": {
	"subject": "pull request",
	"checks": {"peer": {
		"description": "Someone other than the author approved it",
		"op": "any",
		"path": ["approvers"],
		"check": {"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "ne"},
	}},
}}
```

A pull request that only its author approved gives this violation. The row shows the value read through `$pr` beside the list:

```json
{
  "requirement": "peer_reviewed",
  "subject": { "type": "pull request", "id": 42 },
  "check": "peer",
  "description": "Someone other than the author approved it",
  "expression": "some approvers: username ne $pr.author",
  "inputs": [
    { "name": "approvers[]", "value": [{ "username": "ann" }] },
    { "name": "$pr.author", "value": "ann" }
  ],
  "cause": "value",
  "failed_items": [{ "path": "approvers[0]", "value": { "username": "ann" }, "cause": "value" }]
}
```

If `author` were missing, the cause would be `absent`.

Some things worth knowing:

- The step must be the last one in `from`, and there can only be one. The name must be a string that doesn't start with `$`. `keys` must be a list, a `literal` holding a list, or a [`ref`](#reading-from-the-input), and a key in the list can't be a ref with another key beside it. A step with any other field, or one that breaks these rules, fails `$well_formed` and gives no subjects, so the requirement is never met, even with `min_subjects: 0`.
- Any other object in `from`, like a selector or a `literal`, fails `$well_formed` the same way. `from` has never read them, so a requirement with `min_subjects: 0` used to find nothing and pass.
- Keys are sorted and duplicates dropped, so the order you list them in doesn't change the report. If `from` doesn't lead to an object, every key is still a subject, and its checks fail as `absent` (or `value`, for a `present` check). An empty `keys` list gives no subjects, so `$min_subjects` fails.
- `keys` can come from the params: `"keys": {"ref": ["$$params", "required_suites"]}`. The list it reads works exactly like one written in the policy. A single key can be a ref too: `[{"ref": ["$$params", "suite"]}, "unit-test"]`, as can a `literal` like `{"literal": "$x"}`. If a ref can't be read, or reads the wrong type (anything but a list for the whole of `keys`, or a string or number for one key), there are no subjects and `$min_subjects` fails as `absent`, `null` or, for the wrong type, `unusable`, even with `min_subjects: 0`. A key is never just left out. The definition of `$min_subjects` records the ref under `$refs`.
- A subject from an object is identified by its key, even if the subject has an `id`. For a list, the `id` can start with the name, like `["$pr", "number"]`.
- An empty path is named after the subject's name (`$run`), not after `from`.
- A path that starts with a name nobody gave, like `["$runs", "result"]`, is written wrong: it fails `$well_formed`, and the check fails with cause `ill_formed`. That holds even when no subject is found, so a requirement can't pass by never running the check. To read a key that really starts with `$`, write it as `{"literal": "$schema"}`.
- A `ref` can't start with a name yet, only with `$$input`. `{"ref": ["$pr", "author"]}` fails the check and shows `<invalid ref>`.

## Operators

Every check has an `op` and the parameters that operator needs. A field the operator doesn't use is a mistake, so a typo like `valeu` is caught instead of ignored.

### Basic operators

These read one or two fields of a subject.

| `op`               | Parameters                  | Passes when                                                                                                          |
| ------------------ | --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `equals`           | `path`, `value`             | the field equals `value`. The type must match too, so `"1"` doesn't equal `1`.                                       |
| `in`               | `path`, `values`            | the field is one of `values`. The type must match too, as for `equals`.                                              |
| `present`          | `path`                      | the field exists and isn't `null`. An empty string or `false` still counts as present.                               |
| `missing`          | `path`                      | the field isn't there, or is `null`.                                                                                 |
| `non_empty_string` | `path`                      | the field is a string, and not `""`.                                                                                 |
| `empty`            | `path`                      | the field is an empty list.                                                                                          |
| `matches_any`      | `path`, `patterns`          | the field is a string that matches at least one of the regular expressions.                                          |
| `not_matches_any`  | `path`, `patterns`          | the field is a string that matches none of them.                                                                     |
| `range`            | `path`, `min`, `max`        | the field is a number between `min` and `max`, both included.                                                        |
| `includes`         | `path`, `value` or `values` | the field is a list that contains `value`. With `values` in place of `value`, it contains every one of them.         |
| `excludes`         | `path`, `value` or `values` | the field is a list that doesn't contain `value`. With `values` in place of `value`, it contains none of them.       |
| `compare`          | `left`, `right`, `cmp`      | both fields exist, have the same type, and `left cmp right` is true.                                                 |
| `compare_time`     | `left`, `right`, `cmp`      | both fields are timestamps in the same format (both RFC 3339 strings, or both numbers) and `left cmp right` is true. |

`cmp` is one of `eq`, `ne`, `gt`, `gte`, `lt` or `lte`.

Some things worth knowing:

- A check that's written wrong fails `$well_formed`, and its rows fail with cause `ill_formed`, whatever the subject holds. So in `applies_to` it fails the requirement instead of ruling every subject out. Written wrong means:
  - an `op` ergo doesn't know, a missing `op`, or a missing parameter
  - a `cmp` that isn't in the list above
  - `values` that isn't a list, an empty `values` for `includes` or `excludes`, both `value` and `values`, a `min` or `max` that isn't a number, a `min` above `max`, or `patterns` that isn't a list of valid regular expressions
  - an `each` that isn't a path, or `as` or `each` on an operator other than `all` or `any`
  - a step that can't be a [key](#paths), a number out of range, a badly written [ref](#reading-from-the-input), a ref or `literal` deeper inside a value than ergo reads, or a path that starts with a [name](#naming-subjects) nothing gave
  - an `all` or `any` [nested](#nesting) too deep, or a name given twice or badly written
  - a check that isn't an object, or one where it can't go, like a custom operator inside `all`
  - a field its op doesn't use, like `valeu` or `descripton`. Besides its own parameters, any check can have `description`, `meta`, `expression`, `substitute` and `inputs`. A [custom operator](#custom-operators) can have any fields.
  - a set, or an object key that isn't a string, anywhere in the check or in a selector in `from` or `id`. Rego can write both, but JSON can't hold either. The `$well_formed` row shows `holds a set` or `holds a key that isn't a string`.
  - a `description` that isn't a string, or a `meta` that isn't an object or holds something JSON can't, as on a [requirement](#requirements). A `null` one counts as not written. This holds for a custom operator too, and for a check inside another one. The expression doesn't show it, but the `$well_formed` row does, as `invalid description`, `invalid meta`, `meta holds a set` or `meta holds a key that isn't a string`. A number in `meta` that's out of range shows as `number out of range`.

  The expression says what's wrong: `<unknown op nope>`, `<missing op>`, `<invalid check>` for a check that isn't an object, `<even can't go here>` for a check where it can't go, or `<missing value>` in place of a missing parameter, as in `state == <missing value>`. The [`$well_formed` row](#checks-ergo-adds) lists each check that's written wrong, and what's wrong with it.

  A [`ref`](#reading-from-the-input) that reads the wrong kind of value from the params, like `values` read from a param that holds `3`, or an empty list read as the `values` of `includes` or `excludes`, isn't a mistake in the policy, so it doesn't fail `$well_formed`. The check fails with cause `unusable`.
- A field with the wrong kind of value for the operator fails with cause `unusable`, not `value`: a field that isn't a number for `range`, isn't a string for `matches_any` or `not_matches_any`, or isn't a list for `includes`, `excludes`, `all` or `any`, two fields of different types for `compare`, or anything but two timestamps in the same format for `compare_time`. So a filter fails the requirement instead of quietly ruling the subject out. `equals` and `in` are different: `"5"` isn't `5`, which is a sound answer, so that fails with `value`. So does `non_empty_string` on a number, since checking the type is its job.
- `present` on a missing or `null` field fails with cause `value`, not `absent`: whether the field is there is the question it asks, so "it isn't" is a sound answer. A field whose parent isn't there, or is `null`, is missing too, so `build.fingerprint` is missing when there's no `build`, and so is a field under a [selector](#paths) when the list it selects from isn't there or is `null`. A parent that can't hold the field still fails with cause `unusable`, as for every [path](#paths). In an `any_of` option, a `present` check that finds its field missing settles the option as `value`, even when the option's other checks can't read that field.
- `missing` is the opposite of `present`: it passes where `present` fails with cause `value`, fails with `value` where `present` passes, and otherwise fails with the same cause as `present`. So a field that's there fails it whatever it holds, `false` and `""` included, and a selector that matches nothing in a list that's there fails it as `unmatched`. To let a missing field pass a check, or keep a subject with no such field in scope, put `missing` in its own [`any_of`](#any_of) option.
- `empty` only passes on an empty list. A missing list fails with cause `absent`, a `null` one with `null`, and anything else with `unusable`, an empty string or object included. It's for saying that no items is fine where [`all` or `any`](#all-and-any) would fail.
- `equals` with `"value": null` only passes when the field is there and set to `null`. A missing field doesn't count.
- `range` needs `min` and `max` to be numbers. A string like `"3"` fails the check, because Rego puts every number before every string, so `5 <= "3"` would be true.
- `in` fails when the field is missing or `null`, even if `values` contains `null`. To check that a field is `null`, use `equals` with `"value": null`. `in` also fails when `values` is empty, missing, or not a list. The expression then shows `id in <missing values>` or `id in <invalid values>` rather than a list.
- `includes` and `excludes` take `value` or `values`. Giving both, or neither, is written wrong, and the expression shows `not contains(xs, <both value and values>)` or `contains(xs, <missing value or values>)`. `values` works as one check per value: `"op": "excludes", "values": ["nuts", "garlic"]` passes when neither is in the list, and `includes` with the same `values` passes when both are. The expression shows `contains_none(allergens, ["garlic", "nuts"])` or `contains_all(allergens, ["garlic", "nuts"])`. An empty `values` would pass every list, so it's written wrong.
- Each item in `values`, for `in` too, and in `patterns` can be a [`ref`](#reading-from-the-input) or a `literal`, as `value` can, so `"values": [{"ref": ["$$params", "nut"]}, "garlic"]` reads the param, and a param that's missing or `null` fails the check instead of being skipped. A ref in `patterns` that reads something other than a valid regular expression fails the check with cause `unusable`. A list read through a `ref`, or wrapped in a `literal`, is data, so an item in it that looks like a ref is compared as it is. A `value` that's a list is still one value, so `"value": ["a", "b"]` looks for the list `["a", "b"]` inside the field. Write separate checks instead when you want a row and a description for each value.
- To check that a list holds at least one of several values, use [`any`](#all-and-any) with `in`: `{"op": "any", "path": ["allergens"], "check": {"op": "in", "path": [], "values": ["nuts", "garlic"]}}`. Its expression is `some allergens: allergens[] in ["garlic", "nuts"]`. Keep this in mind in `applies_to`, where `includes` with `values` only keeps subjects that have every one of them.
- `compare` and `compare_time` compare two fields of the same subject. To compare a field with a fixed number, use `range`.
- `compare` with `lt`, `lte`, `gt` or `gte` needs both fields to be numbers or both to be strings. Ordering objects, lists or booleans fails with cause `unusable`, because Rego's order for them means nothing in a policy: `{"name": "ann"}` comes before `{"owner": "bob"}` only because `name` sorts before `owner`. You'd usually hit this by leaving the field off the end of a path. `eq` and `ne` work on any type. A substitute that orders objects, lists or booleans gives its check the same cause, and so does an item inside `all` or `any`.
- `compare_time` never converts between formats, so a number against a string fails as `unusable`. With numbers, ergo can't tell seconds from milliseconds, so make sure both sides use the same unit.
- An RFC 3339 string needs an uppercase `T` and `Z`, a date that exists, and a year from 1678 to 2261, which keeps its nanoseconds since 1970 inside a 64-bit integer. Anything else fails `compare_time` as `unusable`, so `2024-02-30T00:00:00Z` isn't read as 1 March, and `2024-01-01t00:00:00z` isn't read at all.
- Patterns in `matches_any` and `not_matches_any` aren't anchored: `svc_` matches `my_svc_account`. Use `^` and `$` when you need a full match. A pattern that isn't a string, or isn't a valid regular expression, fails either operator, even when another pattern matches. With an empty `patterns` list, `matches_any` fails and `not_matches_any` passes. When `patterns` isn't a list, both fail and the expression shows `author matches one of <invalid patterns>` or `author matches none of <invalid patterns>`. When it's missing, the expression shows `<missing patterns>` instead.

These two are useful in `applies_to`, for example to leave bot accounts out of a review rule. If the author field is missing, ergo can't tell whether the subject is in scope, so the requirement fails. See [Checks ergo adds](#checks-ergo-adds).

### `all` and `any`

These apply a check to each item of a list inside the subject.

| `op`  | Parameters                                         | Passes when                                                |
| ----- | -------------------------------------------------- | ---------------------------------------------------------- |
| `all` | `path`, `check`, `each` (optional), `as` (optional) | the list isn't empty and every item passes `check`.        |
| `any` | `path`, `check`, `each` (optional), `as` (optional) | the list isn't empty and at least one item passes `check`. |

```rego
"signed": {
	"op": "all",
	"path": ["commits"],
	"check": {"op": "equals", "path": ["signed"], "value": true},
}
```

An empty list fails, with cause `value`. No commits isn't proof that every commit is signed. When no commits is fine, say so with `empty` in an `any_of`:

```rego
"signed": {
	"op": "any_of",
	"options": {
		"none": [{"op": "empty", "path": ["commits"]}],
		"signed": [{"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["signed"], "value": true}}],
	},
}
```

That renders as `one of: none(commits is empty) | signed(every commits: signed == true)`. A missing `commits` still fails, as `absent`.

Anything that isn't a list fails too, an object included, with cause `unusable`. The row's `inputs` then show `[]` for the list, because an object's values have no order of their own.

`each` goes one level deeper. The check then applies to every item of every inner list:

```rego
{
	"op": "all",
	"path": ["pull_requests"],
	"each": ["commits"],
	"check": {"op": "equals", "path": ["signed"], "value": true},
}
```

This reads as "every commit of every pull request is signed" (ergo renders it as `every pull_requests[].commits: signed == true`). Every inner list must exist and have at least one item. If one pull request has no `commits`, the check fails, rather than being decided by the other pull requests alone.

The inner `check` can be a basic operator, an `any_of`, or another `all` or `any`.

#### Nesting

An `all` or `any` inside another one checks a list for each item of the outer list. `as` names the outer item, so the inner check can still reach it once its paths start somewhere else. Say a pull request needs an approval given after its last commit:

```json
{
  "number": 42,
  "author": "ann",
  "commits": [
    { "sha": "c1", "timestamp": "2026-10-01T10:00:00Z" },
    { "sha": "c2", "timestamp": "2026-10-01T12:00:00Z" }
  ],
  "approvers": [{ "username": "bob", "timestamp": "2026-10-01T11:00:00Z" }]
}
```

That's "some approver, such that every commit is earlier than their approval":

```rego
"subjects": {"pull request": {
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
}},
"requirements": {"approved_after_last_commit": {
	"subject": "pull request",
	"checks": {"after_commits": {
		"description": "Someone approved it after its last commit",
		"op": "any",
		"path": ["approvers"],
		"as": "approver",
		"check": {
			"op": "all",
			"path": ["$pr", "commits"],
			"check": {"op": "compare_time", "left": ["$approver", "timestamp"], "right": ["timestamp"], "cmp": "gt"},
		},
	}},
}}
```

The inner paths start at each commit, so `["timestamp"]` is the commit's. `$approver` is the approver being tried, and `$pr` is the pull request. Bob approved before `c2`, so this fails:

```json
{
  "requirement": "approved_after_last_commit",
  "subject": { "type": "pull request", "id": 42 },
  "check": "after_commits",
  "description": "Someone approved it after its last commit",
  "expression": "some approvers as $approver: every $pr.commits: $approver.timestamp gt timestamp",
  "inputs": [
    { "name": "approvers[]", "value": [{ "username": "bob", "timestamp": "2026-10-01T11:00:00Z" }] },
    { "name": "$pr.commits", "value": [
      { "sha": "c1", "timestamp": "2026-10-01T10:00:00Z" },
      { "sha": "c2", "timestamp": "2026-10-01T12:00:00Z" }
    ] }
  ],
  "cause": "value",
  "failed_items": [{ "path": "approvers[0]", "value": { "username": "bob", "timestamp": "2026-10-01T11:00:00Z" }, "cause": "value" }]
}
```

The row shows the lists the check read, and `failed_items` names the approver who didn't count, but not which commit came after the approval. A commit with no timestamp fails the check too, with cause `absent`, because nothing proves the approval came after it.

To require several things of the same approver, put them in one [`any_of`](#any_of) option, list checks included. This one needs an approver who approved, isn't the author, and approved after every commit:

```rego
"op": "any",
"path": ["approvers"],
"as": "approver",
"check": {"op": "any_of", "options": {"peer": [
	{"op": "equals", "path": ["state"], "value": "APPROVED"},
	{"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "ne"},
	{"op": "all", "path": ["$pr", "commits"], "check": {"op": "compare_time", "left": ["$approver", "timestamp"], "right": ["timestamp"], "cmp": "gt"}},
]}},
```

It renders as `some approvers as $approver: one of: peer(state == "APPROVED" and username ne $pr.author and every $pr.commits: $approver.timestamp gt timestamp)`.

Some things worth knowing:

- `as` takes the same names as a [naming step](#naming-subjects): a string that doesn't start with `$`. Without `each`, `$approver` reads the same as a path inside the item, so `as` only matters for a check nested inside. With `each`, it names the inner item.
- A name can only be given once along a chain of checks. `as` with a name that `from` or an outer check already gave is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and it shows as `<name given twice>`. A badly written name fails the same way and shows as `<invalid name>`. The cause isn't `value`, so a filter written like this fails the requirement rather than ruling every subject out. Two separate checks can use the same name.
- A name given by `as` belongs to one item, so the row doesn't show it in its `inputs`. It still decides that item's cause, so an approver with no `timestamp` makes the check fail as `absent`. Paths that start with it are shown as paths inside the item, like `approvers[].timestamp`. That only holds inside the list check that gives the name. Anywhere else, like a neighbouring `any_of` option, nothing gives it, so reading it there is written wrong and fails as `ill_formed`.
- Inner lists follow the same rules as outer ones. If an approver is tried against an empty or missing list of commits, that try fails.
- One level of nesting is as deep as it goes, because Rego doesn't allow recursion. An `any_of` doesn't count as a level, but an `all` or `any` in one of its options does. A third `all` or `any` is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and its expression shows `<nested too deep>`.

#### Which items failed

A row of an `all` or `any` check also has `failed_items`: the items that made the check fail, in list order, each with its path, cause and value. With this input:

```json
{ "releases": [ { "id": "r-1", "pull_requests": [
  { "number": 7, "commits": [ { "sha": "a1", "signed": true }, { "sha": "a2", "signed": false } ] },
  { "number": 8 },
  { "number": 9, "commits": [ { "sha": "c1" } ] }
] } ] }
```

and the check from above, `every pull_requests[].commits: signed == true`, the row says:

```json
"cause": "absent",
"failed_items": [
  { "path": "pull_requests[0].commits[1]", "cause": "value", "value": { "sha": "a2", "signed": false } },
  { "path": "pull_requests[1].commits", "cause": "absent", "value": null },
  { "path": "pull_requests[2].commits[0]", "cause": "absent", "value": { "sha": "c1" } }
]
```

`inputs` still shows the whole list, so the row records what was checked as well as what failed.

- `path` is written like a path in an expression, with the item's position added: `pull_requests[0].commits[1]` is the second commit of the first pull request. A path that starts with a name keeps it, as in `$pr.commits[1]`.
- With `each`, an inner list that's missing, `null`, not a list or empty fails the check, so it's listed in place of its items, like `pull_requests[1].commits` above.
- An item whose field a `present` check finds missing or `null` is listed with cause `value`, the same as the row, because `present` read the field fine and found nothing there.
- When the check passes, it's `[]`. A passing `any` can have items that failed, but none of them is why the row came out the way it did.
- It's `[]` when the list itself can't be read, because there are no items to blame. The row's `cause` says what's wrong with the list.
- When the check is [written wrong](#basic-operators), every item, and every inner list that's missing, `null`, not a list or empty, is listed with cause `ill_formed`, because none of them could be checked. When a [`ref`](#reading-from-the-input) in it can't be read, every item that fails is listed with the ref's cause, as the row is.
- For a nested check, only the outer items are listed. An approver who approved before the last commit is listed with cause `value`, but not the commit.
- With a [substitute](#substitutes), it lists the items that failed the check itself, even when the substitute passed and the row with it.
- Only rows of `all` and `any` checks have it. Rows of `any_of` checks, `$applies` rows and rows of custom operators don't, even when an `all` or `any` sits inside them.

### `any_of`

`any_of` passes when at least one of its options passes. Each option is a list of checks that must all pass:

```rego
"permitted": {
	"op": "any_of",
	"options": {
		"standard": [
			{"op": "equals", "path": ["type"], "value": "Story"},
			{"op": "equals", "path": ["state"], "value": "Done"},
		],
		"safe": [{"op": "equals", "path": ["type"], "value": "Chore"}],
	},
}
```

This is the only way to say that two fields must agree with each other. Two separate checks, "type is Story or Chore" and "state is Done", would also accept a Chore that isn't Done. With `any_of` it must be a Done Story, or a Chore.

- Name your options. The names show up in the rendered expression: `one of: safe(type == "Chore") | standard(type == "Story" and state == "Done")`. A list of options works too, and they're shown by position.
- Options can hold basic checks and `all` or `any`, but not another `any_of`, because Rego doesn't allow recursion. An `all` or `any` in an option counts as being where the `any_of` is, so it can nest as deep as it could there (see [Nesting](#nesting)).
- An empty `options` is written wrong, and so is an empty option, an option written as an object instead of a list, or an `any_of` inside an option. Each fails `$well_formed`, and the check fails with cause `ill_formed`.
- To let a missing field pass, give `missing` an option of its own. "No label is `do-not-merge`" then passes on a pull request with no `labels`, and renders as `one of: clean(not contains(labels, "do-not-merge")) | no_labels(labels is missing)`:

  ```rego
  "mergeable": {
  	"op": "any_of",
  	"options": {
  		"no_labels": [{"op": "missing", "path": ["labels"]}],
  		"clean": [{"op": "excludes", "path": ["labels"], "value": "do-not-merge"}],
  	},
  }
  ```

  Inside `all`, this skips an item by letting it pass. Inside `any`, skip an item by making it fail instead, with `present` in the same option as the check: `present` on a missing field fails with cause `value`, so the item counts as a plain no.
- The row shows every field any option read, sorted by name. A field read by more than one option shows once. For an `all` or `any` in an option, that's its list and any names it reads.

## Substitutes

A check can name a `substitute`: another check that satisfies it when the first one fails.

```rego
"reviewed": {
	"description": "Reviewed in a pull request",
	"op": "present",
	"path": ["pull_request"],
	"substitute": {
		"description": "The first commit of a repository, attested by a verified committer",
		"op": "equals",
		"path": ["verified_initial_commit"],
		"value": true,
	},
}
```

This is for alternative evidence. The requirement still applies, and something else proves it was met. A repository's first commit can't have a pull request, so an attestation from a verified committer takes its place.

That's different from `applies_to`. A subject left out by `applies_to` isn't covered by the requirement at all. A subject that passes on its substitute is covered, and meets the requirement another way. Its row passes with the cause `substituted` and shows the values both checks read.

- Substitutes work on checks in `checks` and in `applies_to`. They're ignored on the inner check of `all` and `any`, and on the checks inside an `any_of` option.
- A substitute's own substitute is ignored.
- The rendered expression shows both: `reviewed == true, or substitute: verified == true`.
- When both fail, the row's cause is about the main check, not the substitute.

A substitute with a wrong path looks just like a substitute whose evidence is missing: it's never used, and the main check keeps failing. Test each substitute with an input that should pass on it.

## Custom operators

When the built-in operators can't express a check, you can write your own. Add an `op_passed` rule to the `ergo` package from a file of your own:

```rego
package ergo

op_passed(check, subj) if {
	check.op == "even"
	n := value_at(subj, check.path)
	is_number(n)
	n % 2 == 0
}
```

Declare its name in the same file, so ergo can tell it from a typo:

```rego
operators contains "even"
```

An `op` that isn't built in or declared is written wrong: it fails `$well_formed`, and the check fails with cause `ill_formed`, even if an `op_passed` rule passes it. Its expression shows `<unknown op even>`, so the report points at the policy. So a misspelt operator in `applies_to` fails the requirement instead of ruling every subject out.

Then use it like any other operator. ergo can't work out what your operator reads or how to describe it, so give the check an `expression` and a list of `inputs`:

```rego
"even": {"op": "even", "path": ["n"], "expression": "n is even", "inputs": [["n"]]}
```

Each entry in `inputs` is a path, or `{"path": [...], "each": [...]}` to read one field from every item of a list. The row shows those values, and its cause is worked out from them.

If your operator takes its own parameters, read each one with `arg`, so a policy can pass it a [`ref`](#reading-from-the-input) or a `literal`. `arg` gives back the value to use, and is undefined when a ref can't be read, so the check fails:

```rego
operators contains "multiple_of"

op_passed(check, subj) if {
	check.op == "multiple_of"
	n := value_at(subj, check.path)
	by := arg(check.by)
	is_number(n)
	is_number(by)
	n % by == 0
}
```

```rego
"even_batches": {"op": "multiple_of", "path": ["n"], "by": {"ref": ["$$params", "batch"]}, "expression": "n is a multiple of the batch size", "inputs": [["n"]]}
```

ergo finds the refs in your check by itself, so they appear under `$refs` and decide the cause when they can't be read, as for built-in operators.

A custom operator works in `checks`, in `applies_to`, and on either side of a substitute. It doesn't work as the inner check of `all` or `any`, or inside an `any_of` option: there, it's written wrong, so it fails `$well_formed` and the check fails with cause `ill_formed`.

Three rules:

- **Fail when you can't read the data.** Check that fields are there and have the right type before you compare them. A rule that doesn't hold fails the check, which is what you want. Be careful with `not`, which turns an error into a pass.
- **Read the document with `value_at` and `$$input`, and params with `$$params` or `arg`, not with `input` or `data`.** While ergo checks a subject, `input` holds ergo's own [names](#naming-subjects), not your input, and `data.params` may not be the params the report was given.
- **Only call `value_at`, `arg` and `leaf_passed`.** `value_at(subj, path)` reads a path, `arg(value)` reads one of your parameters, and `leaf_passed(check, subj)` runs a built-in check like `{"op": "present", "path": ["approved_by"]}` (but not `all`, `any` or `any_of`). Calling `op_passed` or `report` from your operator creates a loop, which Rego rejects, and the errors will point at `ergo.rego` rather than your file. Every other rule in `ergo.rego` starts with `_` and can change or disappear in any release.

## The report

`ergo.report(input, policy, params)` returns:

```json
{
  "compliant": false,
  "requirements": { ... },
  "results": [ ... ]
}
```

`compliant` is `true` when there's at least one requirement and none of them is `not_met`.

`requirements` has an entry for each requirement:

```json
{
  "checks": {
    "$applies": {
      "description": "The deployment is in scope",
      "expression": "environment == \"prod\"",
      "meta": {}
    },
    "$min_subjects": {
      "description": "The in-scope deployment count is at least 1",
      "expression": "count(matching(deployments)) >= 1",
      "meta": {}
    },
    "$unique_ids": {
      "description": "Every deployment id is unique",
      "expression": "count(repeated(ids(deployments))) == 0",
      "meta": {}
    },
    "$well_formed": {
      "description": "The requirement is written correctly",
      "expression": "subject in subjects and fields are known and have the right types and count(checks) >= 1 and require in [\"every\", \"some\"] and steps are keys and numbers fit a float and checks are written right",
      "meta": {}
    },
    "approved": {
      "description": "Someone approved the deployment",
      "expression": "approved_by is a non-empty string",
      "meta": {},
      "op": "non_empty_string",
      "path": ["approved_by"]
    }
  },
  "description": "Every production deployment is approved",
  "meta": {},
  "require": "every",
  "status": "not_met",
  "subjects": { "matching": 2, "total": 3 }
}
```

`status` is one of:

| `status`         | When                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------- |
| `met`            | the requirement passed, and at least one subject was left to check                                      |
| `not_met`        | anything else: a check failed, too few subjects were left, a filter couldn't be read, or the requirement is [written wrong](#basic-operators) |
| `not_applicable` | the requirement would have passed, but no subject was left after `applies_to`, which only happens with `min_subjects: 0` |

To tell whether a requirement passed, compare `status` with `"met"` (or `"not_applicable"`, if that counts as passing for you). Don't test for `"not_met"`, so a value you didn't expect counts as a failure.

`description` and `meta` are the requirement's, or `""` and `{}` when it has none. They're always there, so you can read `meta.control` without first checking that `meta` exists.

`subjects.total` counts every subject found at `from`, and `subjects.matching` counts the ones left after `applies_to`. `checks` holds each check as you wrote it, plus the `expression` ergo rendered from it. Each check has a `description` and a `meta` too, `""` and `{}` when you didn't write them. A filter in `applies_to` can have them as well, and they're checked the same way, but the report doesn't copy them: its filters all share the one `$applies` entry, with ergo's own description. A `description` or `meta` of the wrong type makes the requirement or the check [written wrong](#basic-operators), and the report shows `""` or `{}` in its place, so a tool always finds a string and an object there. If you write your own `expression`, yours is used, as long as it's a string. Any other value is ignored, and ergo renders the expression as if it weren't there. A check that uses a [`ref`](#reading-from-the-input) also gets `$refs`: the name and value of each one, as read for this report. The `$` marks it as ergo's, so it can't be mixed up with a field of your own. It also holds the [checks ergo adds](#checks-ergo-adds), each with a `description`, an `expression` and an empty `meta`.

In an expression, a value written in the policy is shown as JSON, written the same way whatever the policy looked like, so anyone can produce the same text:

- A string is always in quotes: `state == "MERGED"`, `n == "1"` and `x == ""` compare against strings, and `n == 1`, `ok == true` and `x == null` don't. Only `"`, `\` and control characters are escaped, as `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t` or `\u0001` and so on, so `"a<b"` stays as it is.
- A number is a plain decimal, with no exponent and no trailing zeros: `1.0`, `1.50`, `1e2` and `2.5e-3` are shown as `1`, `1.5`, `100` and `0.0025`, and `-0` as `0`. A number keeps every digit the policy wrote, so it's only shown the same by every implementation when it has at most 15 significant digits, which is as many as any language's 64-bit floating point number is sure to keep. The same goes for a number copied from the input into the report: a runtime that reads JSON into 64-bit numbers, like JavaScript, turns `12345678901234567890` into `12345678901234567000` before ergo sees it. A number in the policy has to be `0` or have a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, the range those numbers hold without losing digits. Elsewhere, a language like JavaScript turns `1e400` into `Infinity` and `1e-400` into `0`, so a check could pass there and fail here. A check holding such a number anywhere is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and the number is shown as `<number out of range>`. One in `from`, `id` or `min_subjects` fails `$well_formed`.
- A list or object has one space after each comma and colon, and its keys are sorted: `["a", 1.5, {"a": "x", "b": [true, null]}]`.
- A ref is shown without quotes, as `$$params.x`, so it can't be mistaken for the string `"$$params.x"`.
- Something that should be a string but isn't, like an `op` or `cmp` written as an object, is shown as JSON too: `<unknown op {"ref": ["a"]}>`. A string there is shown as it is, without quotes: `<unknown op nope>`.

Keys in paths are only quoted when needed, as described in [Paths](#paths), and are escaped the same way.

Several of these rules depend on how a number was written, not only on its value: `1.0` isn't a list index but `1` is, `1e-400` is out of range but `0` isn't, and a number is shown with every digit the policy gave. An implementation has to read each number of the policy as written. In JavaScript, `JSON.parse` loses that, so it needs a parser that keeps the text, like the `source` that newer versions pass to a `JSON.parse` reviver.

`results` has one row for each subject and check:

```json
{
  "requirement": "approved_deploy",
  "subject": { "type": "deployment", "id": "d-2" },
  "check": "approved",
  "inputs": [{ "name": "approved_by", "value": null }],
  "passed": false,
  "cause": "absent"
}
```

Passing and failing rows have the same fields. A row of an `all` or `any` check also has [`failed_items`](#which-items-failed). To find a row's description and expression, look up `requirements[row.requirement].checks[row.check]`. Look it up through the requirement, because two requirements can use the same check name for different things.

### Checks ergo adds

ergo adds four checks of its own. They start with `$`, so they can't clash with yours.

| Check           | One row per | Passes when                                                                                                                            |
| --------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `$well_formed`  | requirement | the requirement names a subject in `subjects`, the requirement and its subject have only the fields ergo knows and they have the right types, it has at least one check, a valid `require`, a well written naming step if `from` has one, no step in `from` or `id` that can't be a key, no number a 64-bit float can't hold in `from`, `id` or `min_subjects`, no set or key that isn't a string in `from` or `id` and no key that isn't a string in `checks` or `applies_to`, a name that's a string, and no check that's [written wrong](#basic-operators). This depends only on how the requirement and its subject are written, never on the input or the params. |
| `$min_subjects` | requirement | `from` leads to a list or an object, unless it ends with a `keys` step, and at least `min_subjects` subjects are left after `applies_to`. |
| `$unique_ids`   | requirement | no two subjects share an id, counting the ones `applies_to` leaves out.                                                                |
| `$applies`      | subject     | the subject passes the `applies_to` filter. These rows only exist when the subject has a filter.                                       |

When a check is [written wrong](#basic-operators), the `$well_formed` row gets an input for it, named after where the check sits in the policy, with the list of what's wrong. With a typo in each of a filter of the `deployment` subject and a check:

```json
"inputs": [
  { "name": "count(checks)", "value": 1 },
  { "name": "require", "value": "every" },
  { "name": "checks.approved", "value": ["unknown op non_emtpy_string"] },
  { "name": "subjects.deployment.applies_to.is_prod", "value": ["missing value", "unknown field valeu"] }
]
```

A check inside another one is named further in, like `checks.signed.check` for the inner check of an `all`, `checks.reviewed.substitute` for a substitute, or `checks.permitted.options.standard.1` for the second check of an `any_of` option. A name that needs quotes is quoted as in [paths](#paths): `checks."a.b"`.

The fields of the requirement and its subject get an input of the same form when something is wrong with them. The requirement's own fields come first, named after the field, and then the subject's, named after the subject and the field. Each group is sorted by field. `require` and a `from` with a [naming step](#naming-subjects) are shown with their value when they're fine, and with what's wrong instead when they aren't, so no name appears twice:

```json
"inputs": [
  { "name": "count(checks)", "value": 0 },
  { "name": "checks", "value": ["empty"] },
  { "name": "min_subjects", "value": ["not a whole number of 0 or more"] },
  { "name": "require", "value": ["neither every nor some"] },
  { "name": "zz", "value": ["unknown field"] },
  { "name": "subjects.deployment.from", "value": ["not a list"] }
]
```

| Field                                     | What's wrong                                                                                                                     |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| any field ergo doesn't know               | `unknown field`                                                                                                                  |
| `checks`                                  | `not an object`, `holds a key that isn't a string`, `missing`, `empty`                                                           |
| `require`                                 | `neither every nor some`                                                                                                         |
| `min_subjects`                            | `not a whole number of 0 or more`, `number out of range`                                                                         |
| `subject`                                 | `missing`, `empty or not a string`, `not in subjects`                                                                            |
| `subjects`                                | `not an object`                                                                                                                  |
| `subjects.deployment`                     | `not an object`                                                                                                                  |
| `subjects.deployment.applies_to`          | `not an object`, `holds a key that isn't a string`                                                                               |
| `subjects.deployment.from`, `...id`       | `not a list`, `step that can't be a key`, `number out of range`, `holds a set`, `holds a key that isn't a string`                |
| `subjects.deployment.from`                | `object step before the last`, `object step without each_as`, `invalid name`, `invalid keys`, `unknown field foo in naming step` |
| `subjects.deployment.id`                  | `ref inside where`, `literal inside where`                                                                                       |
| `subjects.deployment.description`         | `not a string`                                                                                                                   |
| `subjects.deployment.of`                  | `empty or not a string`, `not in subjects`, `leads to a loop`                                                                    |
| `subjects.deployment.from`, `...id`       | `not allowed with of`                                                                                                            |
| `subjects.deployment.applies_to.locked`   | `also a filter of a subject it builds on`                                                                                        |

A policy written in Rego can use a key that isn't a string, like `true` or `1.5`. ergo names it `<invalid key true>` or `<invalid key 1.5>`, so two such keys never share a name. A requirement whose own name isn't a string, like `1`, or every requirement of a policy written as a list, fails `$well_formed`, which then starts with `{"name": "requirement name", "value": ["not a string"]}`. The requirement is `not_met`, so the policy isn't compliant.

Their descriptions are plain sentences, like your own checks': `The requirement is written correctly`, `The in-scope deployment count is at least 1`, `Every deployment id is unique` and `The deployment is in scope`. The details are in `expression`, `inputs` and `cause`. `$min_subjects` names its input after what it counts, like `in-scope deployment count`: only the subjects left after `applies_to`. With `min_subjects: 0` the count can't fail, so `$min_subjects` only checks that `from` can be read, and says so: `The deployment list can be read`, with the expression `deployments can be read`. A `from` that ends with a `keys` step keeps the count, because `from` isn't read there. `$unique_ids` lists the ids that more than one subject has, once each, under `repeated deployment ids`, sorted by how they're written as JSON, so `"b"` comes before `10`, and `10` before `3`. They use the subject's name as it's written, so they read right whatever the word's plural would be.

A subject that fails `$applies` gets no other rows, since it was never checked. But its `$applies` row stays, so you can see what was left out and why.

A subject is only out of scope when ergo read a filter's fields and the values didn't match, so the row's cause is `value`. When a filter fails because a field it reads is missing, `null` or can't be found by a selector, ergo can't tell whether the subject is in scope. Its `$applies` row then fails with that cause, the requirement isn't met, and the row shows up in the violations. This holds with `min_subjects: 0` too, so a missing field can't quietly make a requirement pass.

`present` is the exception, because a missing or `null` field is exactly what it checks for. A `present` filter that finds one rules the subject out, so `{"op": "present", "path": ["lock_release"]}` leaves out a package with no `lock_release`. A selector in its path that matches nothing or more than one item in a list that's there still fails the requirement, as does a parent that can't hold the field, like `"build": "abc"` for `["build", "fingerprint"]`, a subject that isn't an object, or a path that starts with a name nothing gave, like `["$p", "author"]` when `from` gave `$pr`.

With several filters, the subject is only out of scope when every filter that failed did so with `value`. If one rules it out and another can't be read, the requirement fails, so missing data always shows. A `present` filter that finds its field missing is the exception: it says on purpose that a missing field means out of scope, so it rules the subject out whatever the other filters read. That lets a filter on the same field sit next to it:

```json
"applies_to": {
  "recorded": {"op": "present", "path": ["status"]},
  "attested": {"op": "equals", "path": ["status"], "value": "COMPLETE"}
}
```

A lockfile with no `status` is out of scope, although `attested` can't read it. To keep a subject with a missing field in scope instead, use `missing` in an `any_of` option, as in `one of: named(environment == "prod") | unset(environment is missing)`. A filter that's written wrong still fails the requirement. A substitute that isn't there doesn't count as unreadable, because substitutes are usually missing.

Together, these make sure that whenever a requirement isn't met, at least one row explains why.

### Row order

Rows always come in the same order, whatever order you wrote the policy in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then your own checks
2. within each group, requirements in name order
3. within a requirement, subjects in the order they appear in the input, or in key order when a [naming step](#naming-subjects) reads an object
4. within a subject, checks in name order

Patterns, options, selector fields and the keys of objects written in the policy are sorted in rendered expressions too. Names, keys and strings are sorted by Unicode code point, so `！` (U+FF01) comes before `😀` (U+1F600). JavaScript's default `sort()` puts them the other way round, so an implementation there needs to compare code points. So the same policy and the same input always produce exactly the same report, byte for byte once it's written as JSON the same way, which means you can hash it and compare hashes. Every number in the report is written in its plain form, as in expressions, wherever it came from: `1.50`, `-0.0` and `1e2` in the policy, the params or the input come out as `1.5`, `0` and `100`. Two things are left as they are. A number a 64-bit float can't hold, like `1e400` in the input, is copied as written. And a report holding something JSON can't, like a set from an input written in Rego or a requirement whose name isn't a string, is left as ergo built it, so that its rows still name their requirement. `opa eval` sorts the keys. OPA's JavaScript runtime for Wasm doesn't, and it reads the report into JavaScript numbers, which writes a very large or very small one with an exponent: `1e21` and `0.0000001` come out as `1e+21` and `1e-7`. So to compare reports across runtimes, write each one with the [JSON Canonicalization Scheme (RFC 8785)](https://www.rfc-editor.org/rfc/rfc8785) before hashing: it sorts keys and writes numbers the way JavaScript does.

## Causes

Every row has a `cause`. A missing field, a field set to `null`, and a selector that matched nothing all show up as `null` in `inputs`, but they're different problems with different fixes. The cause tells them apart.

| `cause`         | Meaning                                                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `satisfied`     | The check passed.                                                                                                                                                        |
| `substituted`   | The check failed, but its substitute passed.                                                                                                                             |
| `ill_formed`    | The check is written wrong, so it can't be run. `$well_formed` fails too.                                                                                                |
| `not_an_object` | The subject isn't an object, so it has no fields.                                                                                                                        |
| `ambiguous`     | A selector matched more than one item.                                                                                                                                   |
| `unmatched`     | A selector matched nothing, although the list was there.                                                                                                                 |
| `unusable`      | A value the check reads is there, but it's not the kind the check needs, like a string for `range`, a string where a path needs an object, or a param of the wrong type. |
| `absent`        | A field the check reads isn't there.                                                                                                                                     |
| `null`          | A field the check reads is there, but `null`.                                                                                                                            |
| `value`         | Everything was read fine. The values just don't pass.                                                                                                                    |

When the input or the params hold something JSON can't, every check on a subject, every `$applies` row and every `$min_subjects` row fails as `unusable` (see [Failing closed](#failing-closed)).

When a check reads several fields, the row shows the first cause in this table's order. An ambiguous selector matters more than any value, because it means the policy can't even tell what it's looking at.

- For `all` and `any`, a list that isn't there gives `absent`, and one that isn't a list gives `unusable`. An empty list gives `value`, since it was read fine and just has nothing in it. Otherwise the cause is the first, in this table's order, among the items that failed. So when one approver is a bot and another has no `username`, a check that some approver isn't a bot fails as `absent`, because the second one might not be. An `any_of` works the same way across its options, and so does `each` across its inner lists.
- For a custom operator, the cause is worked out from its `inputs`, or from its `path` if it has no `inputs`. With neither, the cause is always `value`.
- `$well_formed` and `$min_subjects` don't read the subject, so their cause is `satisfied` or `value`, except that `$min_subjects` fails as `absent`, `null` or `unusable` when a ref in `from` or `keys` can't be read, or when `from` doesn't lead to a list or an object. `$applies` reports the state of the fields read by the filters that failed. For example, a subject whose filter field is missing says `absent`, and that fails the requirement. A filter that's written wrong gives `ill_formed`, even when another filter rules the subject out, because the scope can't be trusted.

## Violations

`ergo.violations(report)` returns the rows that are real problems, each with its check's `description` and `expression` added, and its `$refs` added to the end of `inputs`:

```json
[
  {
    "requirement": "approved_deploy",
    "subject": { "type": "deployment", "id": "d-2" },
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [{ "name": "approved_by", "value": null }],
    "cause": "absent"
  }
]
```

A violation of an `all` or `any` check keeps its row's `failed_items`.

It leaves out:

- rows that passed
- `$applies` rows with the cause `value`, since being out of scope isn't a problem. An `$applies` row that failed because its filter couldn't be read is kept.
- every row of a requirement whose `status` is `met` or `not_applicable`. Under `require: "some"`, other subjects can fail while the requirement still passes, and those failures aren't problems.

It keeps the rows of a requirement with any other `status`, or none. It keeps `$min_subjects` failures, because finding nothing to check is a problem, and `$well_formed` failures, because they mean the policy itself is broken.

It only reads the report, never the input or the policy. It returns a list in the same order as `results`, so two failures that look the same are both kept. And it returns data, not text, so you decide how to word your messages. A missing `description` or `expression` comes back as `""`.

To decide whether to allow something, use `report.compliant`, not whether `violations` is empty. The two are worked out separately, so a mistake in how you use violations can't let something through.

## Compiling to Wasm

ergo runs in a policy compiled with `opa build -t wasm` and run with OPA's JavaScript runtime, `@open-policy-agent/opa-wasm`. One built-in is missing from that runtime: `time.parse_rfc3339_ns`, which `compare_time` uses on RFC 3339 strings. A policy with such a check fails with `not implemented: built-in function`, unless you pass the built-in in yourself, as the third argument to `loadPolicy`.

ergo only passes it a time it has already checked: an uppercase `T` and `Z`, a date that exists and a year from 1678 to 2261. So it only has to turn that into nanoseconds since 1970, exactly. A JavaScript number can't hold that: today's are about 1.76×10¹⁸, where a number can only step by 256. So return the digits with `JSON.rawJSON` (Node 21 and later). This is the version ergo's CI uses, and it gives the same nanoseconds as OPA on 16,922 generated timestamps, before and after 1970:

```js
const parseTime = (v) => {
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const policy = await loadPolicy(wasm, undefined, { "time.parse_rfc3339_ns": parseTime });
```

## Failing closed

ergo fails a check whenever it can't be sure, instead of letting it pass. Rego doesn't do that by default in a few places, so these are handled on purpose:

- A missing, `null` or wrong-typed field fails every operator, except `missing`, which passes on a missing or `null` field.
- `compare` needs both sides to exist and have the same type. In plain Rego, `null < 5` is true, so a missing field would otherwise pass a `lt` check. Ordering objects, lists or booleans fails too.
- `all`, `any` and `each` need non-empty lists, inner lists of nested checks included. A policy that's fine with no items says so with `empty`.
- A name given twice, or badly written, fails the check, so an inner name can't quietly hide an outer one.
- A check that's written wrong, like an unknown `op` or `cmp`, fails `$well_formed`, and its rows fail with cause `ill_formed`, so a mistake in `applies_to` can't rule every subject out.
- A value of the wrong kind, like a string where `range` needs a number, or a param of the wrong type, fails with cause `unusable`, so a filter can't rule a subject out on it.
- With several filters, one that can't be read fails the requirement, even when another rules the subject out. The only filter that can rule a subject out regardless is a `present` filter that found its field missing.
- `min_subjects` is 1 unless you say otherwise, so finding nothing fails. A `from` that leads nowhere, to `null` or to something that isn't a list or an object fails even with `min_subjects: 0`.
- A key listed in `keys` that the input doesn't have is still a subject, so it fails instead of being skipped.
- A subject whose `applies_to` filter can't be read fails the requirement instead of being left out.
- A `ref` that can't be read fails the check, even for operators like `excludes` or `not_matches_any` that would pass on an empty value.
- A policy with no requirements, and a requirement with no checks, are never met.
- ergo only reads what JSON can hold. Rego can build sets and object keys that aren't strings, but JSON and YAML can't, so ergo turns both down and gives the same report however it's run. A set or such a key anywhere in the input or the params fails every check on a subject, every `$applies` row and every `$min_subjects` row with cause `unusable`, so even a requirement with no subjects isn't met. `$min_subjects` says why in its inputs, like `{"name": "$$input", "value": ["holds a set"]}`, or `$$params` for the params. In a policy, a requirement or check holding either one is [written wrong](#checks-ergo-adds), and so is a requirement whose name isn't a string. So when you build the input in Rego, make lists, `[x | ...]`, not sets, `{x | ...}`.
- A requirement that isn't an object, a field of the wrong type, or a field ergo doesn't know, fails `$well_formed` and keeps its place in the report, so a typo in the policy can't make a requirement vanish.
- A malformed timestamp fails `compare_time` rather than stopping the whole evaluation with an error.
- Running OPA with `--strict-builtin-errors` gives the same report as running without it, because ergo checks a value's type before it passes it to a built-in like `object.get` or `count`. A [custom operator](#custom-operators) is your own Rego, so it needs the same care if you use the flag.
