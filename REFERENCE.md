# ergo reference

This page describes everything ergo accepts and everything it returns. If you haven't used ergo before, start with the [README](README.md).

- [Policies](#policies)
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

A policy is an object that maps requirement names to requirements. You pass it to `ergo.report` along with the input:

```rego
requirements := {
	"approved_deploy": { ... },
	"signed_commits": { ... },
}

report := ergo.report(input, requirements)
```

A policy is plain data, so it can also live in a YAML or JSON file that OPA loads. A file in the policy directory with a top-level `requirements` key is read as `data.requirements`:

```yaml
requirements:
  approved_deploy: { ... }
  signed_commits: { ... }
```

```rego
report := ergo.report(input, data.requirements)
```

Because each name is an object key, two requirements can't share a name, and every row in the report points back to exactly one requirement.

A policy with no requirements is never compliant: it doesn't check anything, so it can't vouch for anything either.

## Requirements

```rego
{
	"subject_type": "deployment",
	"from": ["deployments"],
	"id": ["id"],
	"require": "every",
	"min_subjects": 1,
	"applies_to": {"is_prod": { ... }},
	"checks": {"approved": { ... }},
}
```

| Field          | Meaning                                                                                               | Default           |
| -------------- | ----------------------------------------------------------------------------------------------------- | ----------------- |
| `subject_type` | A name for the kind of thing being checked. It appears in every row.                                  | `"subject"`       |
| `from`         | The [path](#paths) to the subjects in the input. It can end with a [naming step](#naming-subjects).   | the whole input   |
| `id`           | The path, inside one subject, to the value that identifies it.                                        | the whole subject |
| `require`      | `"every"`: every subject must pass every check. `"some"`: at least one subject must pass every check. | `"every"`         |
| `min_subjects` | How many subjects must be left after `applies_to` for the requirement to be met.                      | `1`               |
| `applies_to`   | Named checks that pick which subjects the requirement is about. A subject must pass all of them.      | no filter         |
| `checks`       | Named checks that each subject must pass.                                                             | required          |

A few details:

- If `from` leads to a list, each item is a subject. If it leads to a single object, that object is the only subject. Anything else (nothing, a string, a number) gives no subjects at all, and `$min_subjects` fails.
- If `id` doesn't lead anywhere, the subject's id is `null`. Its rows are still there.
- An item of the list that isn't an object, like a string or a `null`, is still a subject. Its id is the item itself, and its checks fail with cause `not_an_object`.
- Leaving out `from` or `id` is allowed, but rarely what you want. Without `from`, the whole input is checked as one subject. Without `id`, each row repeats the whole subject as its id.
- `min_subjects` defaults to 1 so that a typo in `from` fails the requirement instead of quietly passing it. Set it to `0` when you mean "if there are any, they must pass; if there are none, that's fine". It means the same under `every` and `some`.
- Under `some`, one subject has to pass all the checks by itself. Two subjects that each pass half of them don't count.
- A requirement with no checks, a `require` other than `every` or `some`, or a badly written [naming step](#naming-subjects), is never met. The `$well_formed` row says so.

## Paths

A path is a list of keys that ergo follows one step at a time. `["release", "approver", "email"]` reads `release.approver.email`.

In expressions and `inputs`, a key is quoted when it could be mistaken for something else: when it has a dot or any character other than letters, digits, `_`, `$` and `-`, when it starts with a digit, or when it's empty. So `["metadata", "labels", "app.kubernetes.io/name"]` is named `metadata.labels."app.kubernetes.io/name"`, and doesn't look like a path four keys deep. The string key `["xs", "0"]` is named `xs."0"`, unlike the list index `["xs", 0]`, named `xs.0`. A first step written as `{"literal": "$schema"}` is named `"$schema"`, so it doesn't look like a [name](#naming-subjects).

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

An empty path also reads a subject that isn't an object, like each string of `"from": ["branches"]`. There, the item is named after `from` (`branches[]`), or `input` when there's no `from`. Any other path on such a subject fails with cause `not_an_object`.

One step in a path can be a **selector** instead of a key. It picks the single item in a list (or an object's values) whose fields match:

```rego
"path": ["attestations", {"where": {"type": "pull_request"}}, "state"]
```

This reads the `state` of the attestation whose `type` is `pull_request`, and it works the same whether `attestations` is a list or an object keyed by name.

A selector must match exactly one item. If it matches none, or more than one, the check fails, and the row's cause says which (`unmatched` or `ambiguous`). An empty `where` matches nothing. A path can contain only one selector.

## Reading from the input

A path normally starts inside the subject. Two first steps start somewhere else:

- `$$input` starts at the top of the document given to `ergo.report`.
- `$$params` starts at the policy's params, read from `data.params`.

```rego
"path": ["$$input", "settings", "mode"]
"path": ["$$params", "level"]
```

Every subject reads the same value. These only mean this as the first step of a path, and any other first step starting with `$$` is reserved: it fails the check with cause `absent`. To read a key that really is called `$$input` or `$$params`, write it as `{"literal": "$$input"}`.

A check's fixed values can be read this way too. Write `{"ref": path}` in place of the value, where the path starts with `$$params` or `$$input`. This works for `value`, `values`, `patterns`, `min`, `max` and the values in a selector's `where`, and as a step of a path (see [Ref steps](#ref-steps)). It's how a policy takes params:

```rego
ergo.report({"packages": packages}, {"licences": {
	"subject_type": "package",
	"from": ["packages"],
	"id": ["name"],
	"checks": {"approved": {
		"op": "any",
		"path": ["licences"],
		"check": {"op": "in", "path": [], "values": {"ref": ["$$params", "allowed_licences"]}},
	}},
}})
```

With `data.params` set to `{"allowed_licences": ["MIT", "Apache-2.0"]}`, a package licensed `GPL-3.0` gives this violation:

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
  "cause": "value"
}
```

The expression says where the value comes from. What it was goes in the check's definition in the report, under `$refs`, once for the whole report and sorted by name, beside the literals the check compares against. The rows' `inputs` only hold what the check reads, like `licences[]` here, and `violations` adds the `$refs` back to each violation's `inputs`, as above. That keeps a record of what was compared, even when the params change between runs, without copying it into every row. A path that starts with `$$input` or `$$params` is something the check reads, so its value stays in the row.

### Params

`kosli evaluate --params @params.json` puts a control's params at `data.params`, and `opa eval -d params.json` does the same when the file holds `{"params": ...}`. In tests, write `with data.params as {...}`. To take params from somewhere else, pass them in yourself:

```rego
ergo.report_with_params(doc, params, requirements)
```

That works like `ergo.report`, except `$$params` reads `params` instead of `data.params`. If what you pass can be missing, give it a default first, with a rule like `default config := {}`. Rego doesn't call a function with an argument that isn't defined, so the whole report would be undefined, with no rows to say why. The same goes for the document given to `ergo.report`.

Params aren't part of the document, so `$$input.params` doesn't reach them, and `$$params` doesn't read the document. With no `data.params`, or one that isn't an object, every `$$params` read fails as `absent`. ergo has no defaults, so a control run without its params fails instead of checking something nobody configured.

A policy that calls `ergo.report` can't itself be in a package called `params` (or under one), because the report would then read its own rules. OPA rejects that as recursive when it loads the policy.

Some things worth knowing:

- A ref that leads nowhere, or to `null`, fails the check, with cause `absent` or `null`. That cause wins over anything the subject's own fields would give, because the check can't mean anything without the value. ergo has no defaults, so put the value in the params.
- A ref must be a list that starts with `$$params` or `$$input`, and it can't contain a selector or another ref. Anything else fails the check with cause `absent`, and the expression and `inputs` show `<invalid ref>`.
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

- The value must be a string, or a number to pick an item of a list. A ref that leads nowhere, to `null`, or to anything else, like a list, means the path can't be followed, so the check fails with cause `absent` or `null`.
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
"tests_passed": {
	"subject_type": "test run",
	"from": ["build", "test_runs", {"each_as": "run", "keys": ["unit-test", "integration-test", "system-test"]}],
	"checks": {"passed": {"description": "The tests passed", "op": "equals", "path": ["result"], "value": "passed"}},
}
```

Each key is a subject. A key the object doesn't have is still a subject, so its checks fail as `absent`, and the smoke test run isn't checked at all:

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
"peer_reviewed": {
	"subject_type": "pull request",
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
	"checks": {"peer": {
		"description": "Someone other than the author approved it",
		"op": "any",
		"path": ["approvers"],
		"check": {"op": "compare", "left": ["username"], "right": ["$pr", "author"], "cmp": "ne"},
	}},
}
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
  "cause": "value"
}
```

If `author` were missing, the cause would be `absent`.

Some things worth knowing:

- The step must be the last one in `from`, and there can only be one. The name must be a string that doesn't start with `$`. `keys` must be a list, a `literal` holding a list, or a [`ref`](#reading-from-the-input), and a key in the list can't be a ref with another key beside it. A step with any other field, or one that breaks these rules, fails `$well_formed` and gives no subjects, so the requirement is never met, even with `min_subjects: 0`.
- Any other object in `from`, like a selector or a `literal`, fails `$well_formed` the same way. `from` has never read them, so a requirement with `min_subjects: 0` used to find nothing and pass.
- Keys are sorted and duplicates dropped, so the order you list them in doesn't change the report. If `from` doesn't lead to an object, every key is still a subject, and its checks fail as `absent`. An empty `keys` list gives no subjects, so `$min_subjects` fails.
- `keys` can come from the params: `"keys": {"ref": ["$$params", "required_suites"]}`. The list it reads works exactly like one written in the policy. A single key can be a ref too: `[{"ref": ["$$params", "suite"]}, "unit-test"]`, as can a `literal` like `{"literal": "$x"}`. If a ref can't be read, or reads the wrong type (anything but a list for the whole of `keys`, or a string or number for one key), there are no subjects and `$min_subjects` fails as `absent` or `null`, even with `min_subjects: 0`. A key is never just left out. The definition of `$min_subjects` records the ref under `$refs`.
- A subject from an object is identified by its key, even if the requirement has an `id`. For a list, the `id` can start with the name, like `["$pr", "number"]`.
- An empty path is named after the subject's name (`$run`), not after `from`.
- A path that starts with a name nobody gave, like `["$runs", "result"]`, fails the check with cause `absent`. To read a key that really starts with `$`, write it as `{"literal": "$schema"}`.
- A `ref` can't start with a name yet, only with `$$input`. `{"ref": ["$pr", "author"]}` fails the check and shows `<invalid ref>`.

## Operators

Every check has an `op` and the parameters that operator needs.

### Basic operators

These read one or two fields of a subject.

| `op`               | Parameters             | Passes when                                                                                                          |
| ------------------ | ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `equals`           | `path`, `value`        | the field equals `value`. The type must match too, so `"1"` doesn't equal `1`.                                       |
| `in`               | `path`, `values`       | the field is one of `values`. The type must match too, as for `equals`.                                              |
| `present`          | `path`                 | the field exists and isn't `null`. An empty string or `false` still counts as present.                               |
| `non_empty_string` | `path`                 | the field is a string, and not `""`.                                                                                 |
| `matches_any`      | `path`, `patterns`     | the field is a string that matches at least one of the regular expressions.                                          |
| `not_matches_any`  | `path`, `patterns`     | the field is a string that matches none of them.                                                                     |
| `range`            | `path`, `min`, `max`   | the field is a number between `min` and `max`, both included.                                                        |
| `includes`         | `path`, `value`        | the field is a list that contains `value`.                                                                           |
| `excludes`         | `path`, `value`        | the field is a list that doesn't contain `value`.                                                                    |
| `compare`          | `left`, `right`, `cmp` | both fields exist, have the same type, and `left cmp right` is true.                                                 |
| `compare_time`     | `left`, `right`, `cmp` | both fields are timestamps in the same format (both RFC 3339 strings, or both numbers) and `left cmp right` is true. |

`cmp` is one of `eq`, `ne`, `gt`, `gte`, `lt` or `lte`.

Some things worth knowing:

- A check that's written wrong fails with cause `absent`, whatever the subject holds, so in `applies_to` it fails the requirement instead of ruling every subject out. Written wrong means:
  - an `op` ergo doesn't know, or a missing parameter
  - a `cmp` that isn't in the list above
  - `values` that isn't a list, a `min` or `max` that isn't a number, a `min` above `max`, or `patterns` that isn't a list of valid regular expressions, even when it's read with a [`ref`](#reading-from-the-input)
  - an `each` that isn't a path, or `as` or `each` on an operator other than `all` or `any`

  The expression says what's wrong: `<unknown op nope>`, `<missing op>`, `<invalid check>` for a check that isn't an object, or `<even can't go here>` for a check where it can't go, like a custom operator inside `all`.
- `equals` with `"value": null` only passes when the field is there and set to `null`. A missing field doesn't count.
- `range` needs `min` and `max` to be numbers. A string like `"3"` fails the check, because Rego puts every number before every string, so `5 <= "3"` would be true.
- `in` fails when the field is missing or `null`, even if `values` contains `null`. To check that a field is `null`, use `equals` with `"value": null`. `values` can be a list or, from Rego, a set. `in` also fails when `values` is empty, missing, or not a list or set. In those last two cases, the expression shows `id in <invalid values>` rather than a list.
- `compare` and `compare_time` compare two fields of the same subject. To compare a field with a fixed number, use `range`.
- `compare` with `lt`, `lte`, `gt` or `gte` needs both fields to be numbers or both to be strings. Ordering objects, lists or booleans fails with cause `absent`, because Rego's order for them means nothing in a policy: `{"name": "ann"}` comes before `{"owner": "bob"}` only because `name` sorts before `owner`. You'd usually hit this by leaving the field off the end of a path. `eq` and `ne` work on any type. A substitute that orders objects, lists or booleans gives its check the same cause. Inside `all` or `any`, the row's cause is about the list, so it shows `value`.
- `compare_time` never converts between formats, so a number against a string fails. With numbers, ergo can't tell seconds from milliseconds, so make sure both sides use the same unit.
- Patterns in `matches_any` and `not_matches_any` aren't anchored: `svc_` matches `my_svc_account`. Use `^` and `$` when you need a full match. A pattern that isn't a string, or isn't a valid regular expression, fails either operator, even when another pattern matches. With an empty `patterns` list, `matches_any` fails and `not_matches_any` passes.

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

An empty list fails. No commits isn't proof that every commit is signed.

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
"approved_after_last_commit": {
	"subject_type": "pull request",
	"from": ["pull_requests", {"each_as": "pr"}],
	"id": ["number"],
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
}
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
  "cause": "value"
}
```

The row shows the lists the check read, but not which approver failed or why. A commit with no timestamp fails the check too, because nothing proves the approval came after it.

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
- A name can only be given once along a chain of checks. `as` with a name that `from` or an outer check already gave fails the check with cause `absent`, and shows as `<name given twice>`. A badly written name fails the same way and shows as `<invalid name>`. The cause isn't `value`, so a filter written like this fails the requirement rather than ruling every subject out. Two separate checks can use the same name.
- A name given by `as` belongs to one item, so the row doesn't read it, and it doesn't decide the cause. Paths that start with it are shown as paths inside the item, like `approvers[].timestamp`. That only holds inside the list check that gives the name. Anywhere else, like a neighbouring `any_of` option, nothing gives it, so reading it fails as `absent`.
- Inner lists follow the same rules as outer ones. If an approver is tried against an empty or missing list of commits, that try fails.
- One level of nesting is as deep as it goes, because Rego doesn't allow recursion. An `any_of` doesn't count as a level, but an `all` or `any` in one of its options does. A third `all` or `any` fails the check with cause `absent`, and its expression shows `<nested too deep>`.

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
- An empty `options` fails with cause `absent`, and so does an empty option, an option written as an object instead of a list, or an `any_of` inside an option.
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

An `op` that isn't built in or declared fails with cause `absent`, even if an `op_passed` rule passes it. Its expression shows `<unknown op even>`, so the report points at the policy. So a misspelt operator in `applies_to` fails the requirement instead of ruling every subject out.

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

A custom operator works in `checks`, in `applies_to`, and on either side of a substitute. It doesn't work as the inner check of `all` or `any`, or inside an `any_of` option: there, it fails with cause `absent`.

Two rules:

- **Fail when you can't read the data.** Check that fields are there and have the right type before you compare them. A rule that doesn't hold fails the check, which is what you want. Be careful with `not`, which turns an error into a pass.
- **Read the document with `value_at` and `$$input`, and params with `$$params` or `arg`, not with `input` or `data.params`.** While ergo checks a subject, `input` holds ergo's own [names](#naming-subjects), not your input, and `data.params` may not be the params the report was given.
- **Only call ergo's lower-level rules**, like `value_at`, `arg` and `leaf_passed`. Calling `op_passed`, `check_passed` or `report` from your operator creates a loop, which Rego rejects, and the errors will point at `ergo.rego` rather than your file.

## The report

`ergo.report(input, requirements)` returns:

```json
{
  "compliant": false,
  "requirements": { ... },
  "results": [ ... ]
}
```

`compliant` is `true` only when every requirement is met.

`requirements` has an entry for each requirement:

```json
{
  "checks": {
    "$applies": {
      "description": "subject is in scope as a deployment under this requirement's applies_to filter; out-of-scope subjects are recorded but not evaluated, and a subject whose filter can't be read fails",
      "expression": "environment == \"prod\""
    },
    "$min_subjects": {
      "description": "at least 1 matching deployment subject(s) required",
      "expression": "count(matching(deployments)) >= 1"
    },
    "$well_formed": {
      "description": "the requirement declares at least one check and a recognised \"require\" value; lacking either, it asserts nothing that could ever be satisfied",
      "expression": "count(checks) >= 1 and require in [\"every\", \"some\"]"
    },
    "approved": {
      "description": "Someone approved the deployment",
      "expression": "approved_by is a non-empty string",
      "op": "non_empty_string",
      "path": ["approved_by"]
    }
  },
  "require": "every",
  "satisfied": false,
  "subjects": { "matching": 2, "total": 3 }
}
```

`subjects.total` counts every subject found at `from`, and `subjects.matching` counts the ones left after `applies_to`. `checks` holds each check as you wrote it, plus the `expression` ergo rendered from it. If you write your own `expression`, yours is used. A check that uses a [`ref`](#reading-from-the-input) also gets `$refs`: the name and value of each one, as read for this report. The `$` marks it as ergo's, so it can't be mixed up with a field of your own. It also holds the [checks ergo adds](#checks-ergo-adds), each with a `description` and an `expression`.

In an expression, a string written in the policy is shown as a JSON string, so it is always in quotes: `state == "MERGED"`, `n == "1"` and `x == ""` compare against strings, and `n == 1`, `ok == true` and `x == null` don't. A ref is shown without quotes, as `$$params.x`, so it can't be mistaken for the string `"$$params.x"`. Strings are escaped as in standard JSON: `"` becomes `\"`, `\` becomes `\\`, and control characters become `\n`, `\t` or `\u0001` and so on. Nothing else is escaped, so `"a<b"` stays as it is. Keys in paths are only quoted when needed, as described in [Paths](#paths), and quoting uses the same escapes.

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

Passing and failing rows have the same fields. To find a row's description and expression, look up `requirements[row.requirement].checks[row.check]`. Look it up through the requirement, because two requirements can use the same check name for different things.

### Checks ergo adds

ergo adds three checks of its own. They start with `$`, so they can't clash with yours.

| Check           | One row per | Passes when                                                                                                                            |
| --------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `$well_formed`  | requirement | the requirement has at least one check, a valid `require`, and a well written naming step if `from` has one. This depends only on how the requirement is written, never on the input. |
| `$min_subjects` | requirement | at least `min_subjects` subjects are left after `applies_to`.                                                                          |
| `$applies`      | subject     | the subject passes the `applies_to` filter. These rows only exist when the requirement has a filter.                                   |

A subject that fails `$applies` gets no other rows, since it was never checked. But its `$applies` row stays, so you can see what was left out and why.

A subject is only out of scope when ergo read a filter's fields and the values didn't match, so the row's cause is `value`. When a filter fails because a field it reads is missing, `null` or can't be found by a selector, ergo can't tell whether the subject is in scope. Its `$applies` row then fails with that cause, the requirement isn't met, and the row shows up in the violations. This holds with `min_subjects: 0` too, so a missing field can't quietly make a requirement pass.

`present` is the exception, because a missing or `null` field is exactly what it checks for. A `present` filter that finds one rules the subject out, so `{"op": "present", "path": ["lock_release"]}` leaves out a package with no `lock_release`. A selector in its path that matches nothing or more than one item still fails the requirement, as does a subject that isn't an object, or a path that starts with a name nothing gave, like `["$p", "author"]` when `from` gave `$pr`.

With several filters, one that clearly rules the subject out is enough, even if another can't be read. A substitute that isn't there doesn't count as unreadable, because substitutes are usually missing.

Together, these make sure that whenever a requirement isn't met, at least one row explains why.

### Row order

Rows always come in the same order, whatever order you wrote the policy in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$applies` rows, then your own checks
2. within each group, requirements in name order
3. within a requirement, subjects in the order they appear in the input, or in key order when a [naming step](#naming-subjects) reads an object
4. within a subject, checks in name order

Patterns, options and selector fields are sorted in rendered expressions too. So the same policy and the same input always produce exactly the same report, byte for byte, which means you can hash it and compare hashes.

## Causes

Every row has a `cause`. A missing field, a field set to `null`, and a selector that matched nothing all show up as `null` in `inputs`, but they're different problems with different fixes. The cause tells them apart.

| `cause`         | Meaning                                                             |
| --------------- | ------------------------------------------------------------------- |
| `satisfied`     | The check passed.                                                   |
| `substituted`   | The check failed, but its substitute passed.                        |
| `not_an_object` | The subject isn't an object, so it has no fields.                   |
| `ambiguous`     | A selector matched more than one item.                              |
| `unmatched`     | A selector matched nothing, although the list was there.            |
| `absent`        | A field the check reads isn't there, or the check is written wrong. |
| `null`          | A field the check reads is there, but `null`.                       |
| `value`         | Everything was read fine. The values just don't pass.               |

When a check reads several fields, the row shows the first cause in this table's order. An ambiguous selector matters more than any value, because it means the policy can't even tell what it's looking at.

- For `all` and `any`, the cause is about the list itself. A problem inside one item shows up as `value`. So does an empty list, since it was read fine and just has nothing in it.
- For a custom operator, the cause is worked out from its `inputs`, or from its `path` if it has no `inputs`. With neither, the cause is always `value`.
- `$well_formed` and `$min_subjects` don't read the subject, so their cause is `satisfied` or `value`. `$applies` reports the state of the fields read by the filters that failed. For example, a subject whose filter field is missing says `absent`, and that fails the requirement.

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

It leaves out:

- rows that passed
- `$applies` rows with the cause `value`, since being out of scope isn't a problem. An `$applies` row that failed because its filter couldn't be read is kept.
- every row of a requirement that was met. Under `require: "some"`, other subjects can fail while the requirement still passes, and those failures aren't problems.

It keeps `$min_subjects` failures, because finding nothing to check is a problem, and `$well_formed` failures, because they mean the policy itself is broken.

It only reads the report, never the input or the policy. It returns a list in the same order as `results`, so two failures that look the same are both kept. And it returns data, not text, so you decide how to word your messages. A missing `description` or `expression` comes back as `""`.

To decide whether to allow something, use `report.compliant`, not whether `violations` is empty. The two are worked out separately, so a mistake in how you use violations can't let something through.

## Failing closed

ergo fails a check whenever it can't be sure, instead of letting it pass. Rego doesn't do that by default in a few places, so these are handled on purpose:

- A missing, `null` or wrong-typed field fails every operator.
- `compare` needs both sides to exist and have the same type. In plain Rego, `null < 5` is true, so a missing field would otherwise pass a `lt` check. Ordering objects, lists or booleans fails too.
- `all`, `any` and `each` need non-empty lists, inner lists of nested checks included.
- A name given twice, or badly written, fails the check, so an inner name can't quietly hide an outer one.
- A check that's written wrong, like an unknown `op` or `cmp`, fails with cause `absent`, so a mistake in `applies_to` can't rule every subject out.
- `min_subjects` is 1 unless you say otherwise, so finding nothing fails.
- A key listed in `keys` that the input doesn't have is still a subject, so it fails instead of being skipped.
- A subject whose `applies_to` filter can't be read fails the requirement instead of being left out.
- A `ref` that can't be read fails the check, even for operators like `excludes` or `not_matches_any` that would pass on an empty value.
- A policy with no requirements, and a requirement with no checks, are never met.
- A malformed timestamp fails `compare_time` rather than stopping the whole evaluation with an error.
