# ergo reference

This page describes everything ergo accepts and everything it returns. If you haven't used ergo before, start with the [README](README.md).

- [Policies](#policies)
- [Requirements](#requirements)
- [Paths](#paths)
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
| `from`         | The [path](#paths) to the subjects in the input.                                                      | the whole input   |
| `id`           | The path, inside one subject, to the value that identifies it.                                        | the whole subject |
| `require`      | `"every"`: every subject must pass every check. `"some"`: at least one subject must pass every check. | `"every"`         |
| `min_subjects` | How many subjects must be left after `applies_to` for the requirement to be met.                      | `1`               |
| `applies_to`   | Named checks that pick which subjects the requirement is about. A subject must pass all of them.      | no filter         |
| `checks`       | Named checks that each subject must pass.                                                             | required          |

A few details:

- If `from` leads to a list, each item is a subject. If it leads to a single object, that object is the only subject. Anything else (nothing, a string, a number) gives no subjects at all, and `$min_subjects` fails.
- If `id` doesn't lead anywhere, the subject's id is `null`. Its rows are still there.
- Leaving out `from` or `id` is allowed, but rarely what you want. Without `from`, the whole input is checked as one subject. Without `id`, each row repeats the whole subject as its id.
- `min_subjects` defaults to 1 so that a typo in `from` fails the requirement instead of quietly passing it. Set it to `0` when you mean "if there are any, they must pass; if there are none, that's fine". It means the same under `every` and `some`.
- Under `some`, one subject has to pass all the checks by itself. Two subjects that each pass half of them don't count.
- A requirement with no checks, or with a `require` other than `every` or `some`, is never met. The `$well_formed` row says so.

## Paths

A path is a list of keys that ergo follows one step at a time. `["release", "approver", "email"]` reads `release.approver.email`.

`from` is a path into the input. Every other path (`id`, a check's `path`, `left` and `right`) is a path into one subject.

One step in a path can be a **selector** instead of a key. It picks the single item in a list (or an object's values) whose fields match:

```rego
"path": ["attestations", {"where": {"type": "pull_request"}}, "state"]
```

This reads the `state` of the attestation whose `type` is `pull_request`, and it works the same whether `attestations` is a list or an object keyed by name.

A selector must match exactly one item. If it matches none, or more than one, the check fails, and the row's cause says which (`unmatched` or `ambiguous`). An empty `where` matches nothing. A path can contain only one selector.

## Operators

Every check has an `op` and the parameters that operator needs.

### Basic operators

These read one or two fields of a subject.

| `op`               | Parameters             | Passes when                                                                                                          |
| ------------------ | ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `equals`           | `path`, `value`        | the field equals `value`. The type must match too, so `"1"` doesn't equal `1`.                                       |
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

- `equals` with `"value": null` only passes when the field is there and set to `null`. A missing field doesn't count.
- `compare` and `compare_time` compare two fields of the same subject. To compare a field with a fixed number, use `range`.
- `compare_time` never converts between formats, so a number against a string fails. With numbers, ergo can't tell seconds from milliseconds, so make sure both sides use the same unit.
- Patterns in `matches_any` and `not_matches_any` aren't anchored: `svc_` matches `my_svc_account`. Use `^` and `$` when you need a full match. A pattern that isn't a string makes `not_matches_any` fail, and `matches_any` ignores it. With an empty `patterns` list, `matches_any` fails and `not_matches_any` passes.

These two are useful in `applies_to`, for example to leave bot accounts out of a review rule. If the author field is missing, ergo can't tell whether the subject is in scope, so the requirement fails. See [Checks ergo adds](#checks-ergo-adds).

### `all` and `any`

These apply a check to each item of a list inside the subject.

| `op`  | Parameters                         | Passes when                                                |
| ----- | ---------------------------------- | ---------------------------------------------------------- |
| `all` | `path`, `check`, `each` (optional) | the list isn't empty and every item passes `check`.        |
| `any` | `path`, `check`, `each` (optional) | the list isn't empty and at least one item passes `check`. |

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

Two levels is as deep as it goes, because Rego doesn't allow recursion.

The inner `check` can be a basic operator or an `any_of`.

### `any_of`

`any_of` passes when at least one of its options passes. Each option is a list of basic checks that must all pass:

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

- Name your options. The names show up in the rendered expression: `one of: safe(type == Chore) | standard(type == Story and state == Done)`. A list of options works too, and they're shown by position.
- Options can only hold basic checks. You can't put `all`, `any` or another `any_of` inside one. Again, this is because Rego doesn't allow recursion.
- An empty `options` fails, and so does an empty option. An option written as an object instead of a list also fails.
- The row shows every field any option read, once each, sorted by name.

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

Then use it like any other operator. ergo can't work out what your operator reads or how to describe it, so give the check an `expression` and a list of `inputs`:

```rego
"even": {"op": "even", "path": ["n"], "expression": "n is even", "inputs": [["n"]]}
```

Each entry in `inputs` is a path, or `{"path": [...], "each": [...]}` to read one field from every item of a list. The row shows those values, and its cause is worked out from them.

A custom operator works in `checks`, in `applies_to`, and on either side of a substitute. It doesn't work as the inner check of `all` or `any`, or inside an `any_of` option: there, it fails.

Two rules:

- **Fail when you can't read the data.** Check that fields are there and have the right type before you compare them. A rule that doesn't hold fails the check, which is what you want. Be careful with `not`, which turns an error into a pass.
- **Only call ergo's lower-level rules**, like `value_at` and `leaf_passed`. Calling `op_passed`, `check_passed` or `report` from your operator creates a loop, which Rego rejects, and the errors will point at `ergo.rego` rather than your file.

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
      "expression": "environment == prod"
    },
    "$min_subjects": {
      "description": "at least 1 matching deployment subject(s) required",
      "expression": "count(matching(deployments)) >= 1"
    },
    "$well_formed": {
      "description": "the requirement declares at least one check and a recognised \"require\" value; lacking either, it asserts nothing that could ever be satisfied",
      "expression": "count(checks) >= 1 and require in {every, some}"
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

`subjects.total` counts every subject found at `from`, and `subjects.matching` counts the ones left after `applies_to`. `checks` holds each check as you wrote it, plus the `expression` ergo rendered from it. If you write your own `expression`, yours is used. It also holds the [checks ergo adds](#checks-ergo-adds), each with a `description` and an `expression`.

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
| `$well_formed`  | requirement | the requirement has at least one check and a valid `require`. This depends only on how the requirement is written, never on the input. |
| `$min_subjects` | requirement | at least `min_subjects` subjects are left after `applies_to`.                                                                          |
| `$applies`      | subject     | the subject passes the `applies_to` filter. These rows only exist when the requirement has a filter.                                   |

A subject that fails `$applies` gets no other rows, since it was never checked. But its `$applies` row stays, so you can see what was left out and why.

A subject is only out of scope when ergo read a filter's fields and the values didn't match, so the row's cause is `value`. When a filter fails because a field it reads is missing, `null` or can't be found by a selector, ergo can't tell whether the subject is in scope. Its `$applies` row then fails with that cause, the requirement isn't met, and the row shows up in the violations. This holds with `min_subjects: 0` too, so a missing field can't quietly make a requirement pass.

With several filters, one that clearly rules the subject out is enough, even if another can't be read. A substitute that isn't there doesn't count as unreadable, because substitutes are usually missing.

Together, these make sure that whenever a requirement isn't met, at least one row explains why.

### Row order

Rows always come in the same order, whatever order you wrote the policy in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$applies` rows, then your own checks
2. within each group, requirements in name order
3. within a requirement, subjects in the order they appear in the input
4. within a subject, checks in name order

Patterns, options and selector fields are sorted in rendered expressions too. So the same policy and the same input always produce exactly the same report, byte for byte, which means you can hash it and compare hashes.

## Causes

Every row has a `cause`. A missing field, a field set to `null`, and a selector that matched nothing all show up as `null` in `inputs`, but they're different problems with different fixes. The cause tells them apart.

| `cause`       | Meaning                                                  |
| ------------- | -------------------------------------------------------- |
| `satisfied`   | The check passed.                                        |
| `substituted` | The check failed, but its substitute passed.             |
| `ambiguous`   | A selector matched more than one item.                   |
| `unmatched`   | A selector matched nothing, although the list was there. |
| `absent`      | A field the check reads isn't there.                     |
| `null`        | A field the check reads is there, but `null`.            |
| `value`       | Everything was read fine. The values just don't pass.    |

When a check reads several fields, the row shows the first cause in this table's order. An ambiguous selector matters more than any value, because it means the policy can't even tell what it's looking at.

- For `all` and `any`, the cause is about the list itself. A problem inside one item shows up as `value`. So does an empty list, since it was read fine and just has nothing in it.
- For a custom operator, the cause is worked out from its `inputs`, or from its `path` if it has no `inputs`. With neither, the cause is always `value`.
- `$well_formed` and `$min_subjects` don't read the subject, so their cause is `satisfied` or `value`. `$applies` reports the state of the fields read by the filters that failed. For example, a subject whose filter field is missing says `absent`, and that fails the requirement.

## Violations

`ergo.violations(report)` returns the rows that are real problems, each with its check's `description` and `expression` added:

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
- `compare` needs both sides to exist and have the same type. In plain Rego, `null < 5` is true, so a missing field would otherwise pass a `lt` check.
- `all`, `any` and `each` need non-empty lists.
- `min_subjects` is 1 unless you say otherwise, so finding nothing fails.
- A subject whose `applies_to` filter can't be read fails the requirement instead of being left out.
- A policy with no requirements, and a requirement with no checks, are never met.
- A malformed timestamp fails `compare_time` rather than stopping the whole evaluation with an error.
