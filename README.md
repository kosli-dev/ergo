# Ergo

Ergo checks that your deployments, pull requests or expenses follow rules written as plain sentences, like `approved_by is a non-empty string`, and gives back a report that says what it checked, what it found and why each check passed or failed. Whoever owns a rule can write it, and whoever has to trust the result can read the report without knowing how it was computed.

Ergo is at 0.3. Any 0.x release may still change what a policy says or what a report shows, and [`CHANGELOG.md`](CHANGELOG.md) says when it does.

## What Ergo does

### Policies read like sentences

A check is one line: `approved_by is a non-empty string`, `every commits.verified is true`, `some licenses is in $params.allowed_licenses`. Sentences can also count, compare times, match patterns and allow a margin, as in `count of approvers is at least 2`, `reviewed_at is before deployed_at`, `branch matches '^release/'` or `cost is 2.5 within 0.01`. When a check can pass in more than one way, `any_of` names the ways.

### The policy says what it's about

`from: deployments whose environment is "prod"` picks the subjects, which is what Ergo calls the things a policy checks. When a rule only applies sometimes, `whose` says when, and a subject can be built on another, like the pull requests of each artifact. Values that change between runs, like `$params.allowed_licenses`, come from outside the policy. There are no defaults, so a policy run without its params fails instead of checking something nobody configured.

### Every run gives a report

The report has one row per subject and check, passed or failed alike, with the value Ergo read. A failed row also has a cause: `absent` when the field isn't there, `null` when it holds `null`, `value` when it was read fine and just doesn't pass, and `unusable` when it's the wrong kind of thing.

The report has the same shape whatever the policy, so you can keep reports and compare them, and a reporting tool can read all of them the same way. `compliant` gives the yes or no, and the violations are the failed rows that are problems, each with its description and its sentence, for whoever has to fix them.

### Ergo adds checks of its own

A subject the policy isn't about is recorded as out of scope and stays in the report. A policy that finds nothing to check fails, unless it says finding nothing is fine. Two subjects with the same id fail, and so does a policy that's written wrong, with a row that says what's wrong.

A missing field, a `null`, a wrong type or an empty list where a check expects items fails the check, unless the policy says it's fine, like `, if any,` or `does not exist`.

### The same input gives the same report

Ergo reads no clock and nothing random, and sorts everything it writes. The same policy, input and params give the same report, row for row, whatever order the policy was written in.

## Two engines, one spec

Two engines build Ergo reports, and you choose one:

- [Ergo with OPA](OPA.md): `ergo.rego` runs on [Open Policy Agent](https://www.openpolicyagent.org/). It is one file with no dependencies.
- [Ergo CLI](CLI.md): the `ergo` command runs the Rust engine. It is experimental.

Both run every case in [`spec/cases`](spec/cases) and give the same report, apart from `engine`, which says which one made it. Every rule Ergo follows is written down in the [spec](spec/README.md), with cases that pin it, and both the policy and the report have a JSON Schema. A policy says which spec version it's written for, and a report says which engine made it and which version it follows, so other tools can read the reports.

## A first policy

Here is a policy that says "_every production deployment must have an approver_". It goes in a YAML file.

`policy.yaml`:

```yaml
ergo_spec: v0.3
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
requirements:
  prod_deploy:
    description: Every production deployment is approved
    subject: deployment
    checks:
      approved:
        description: Someone approved the deployment
        assert: approved_by is a non-empty string
```

`ergo_spec` says which version of Ergo's [spec](spec/README.md#versions) the policy is written for. Ergo reads only the version it follows, so a policy without it, or written for another version, fails.

A policy says what to check. First it says what it's about, the things we call _subjects_. Each kind of subject gets a name, here `deployment`, that the report uses for each one, and says where to find them:

- `from` says where the subjects are in the input. `deployments` means `input.deployments`, and `release.deployments` would mean `input.release.deployments`. `whose` keeps only the ones this policy is about, here the deployments whose `environment` is `prod`.
- `identified_by` names the field that tells the subjects apart, here `id`. No two subjects can share one.

Then the requirement says what must be true of them. Its `description` says what it requires, in words anyone can read, and `subject` names the subject it checks:

- `checks` are the rules each subject must pass, each one written as a sentence. Here, `approved_by` must be a non-empty string. A check with nothing to add can be the sentence alone: `approved: approved_by is a non-empty string`.

Several requirements can check the same subject. Each one gets its own rows in the report.

### The report

With the following `deployments.json` input:

```json
{
  "deployments": [
    { "id": "d-1", "environment": "prod", "approved_by": "alice" },
    { "id": "d-2", "environment": "prod" },
    { "id": "d-3", "environment": "staging" }
  ]
}
```

Run it with one of the two engines: [Ergo with OPA](OPA.md) or [Ergo CLI](CLI.md). Both give the same report, apart from `engine`, which says which one made it.

The report records every check Ergo ran, including the ones that passed. It comes in four parts, after the policy's own `description` and `meta`, which this one doesn't have, and `engine` and `ergo`, which say what made the report and which version of the [spec](spec/README.md#versions) it follows:

```json
{
  "compliant": false,
  "description": "",
  "engine": { ... },
  "ergo": "v0.3",
  "meta": {},
  "requirements": { ... },
  "results": [ ... ],
  "subjects": { ... }
}
```

- `compliant` is the overall answer. When you need a plain yes or no to allow or block something, this is the one to use: `allow := report.compliant`.
- `requirements` has an entry for each requirement. It repeats the requirement's `description`, and its `status` is `met`, `not_met`, or `not_applicable` when no subject was left to check. When it's `not_met`, `causes` says why, worst first, with how many rows each: here `[{"cause": "absent", "rows": 1}]`. It also says how many subjects were found and kept, and lists every check with a readable `expression`, which is the sentence as you wrote it.
- `results` has one row per subject and check, with the value Ergo read, whether the check passed, and a `cause`.
- `subjects` says where each subject the requirements use comes from. Here it holds one entry, and the requirement's own entry has `"subject": "deployment"` to point at it:

  ```json
  "subjects": {
    "deployment": {
      "description": "",
      "from": "deployments whose environment is \"prod\"",
      "identified_by": "id",
      "parts": {}
    }
  }
  ```

Here's what those rows look like for our example:

| subject | check           | value read                               | passed  | cause       |
| ------- | --------------- | ---------------------------------------- | ------- | ----------- |
|         | `$well_formed`  | `count(checks) = 1`, `require = "every"` | `true`  | `satisfied` |
|         | `$min_subjects` | `in-scope deployment count = 2`          | `true`  | `satisfied` |
|         | `$unique_ids`   | `repeated deployment ids = []`           | `true`  | `satisfied` |
| `d-1`   | `$applies`      | `environment = "prod"`                   | `true`  | `satisfied` |
| `d-2`   | `$applies`      | `environment = "prod"`                   | `true`  | `satisfied` |
| `d-3`   | `$applies`      | `environment = "staging"`                | `false` | `value`     |
| `d-1`   | `approved`      | `approved_by = "alice"`                  | `true`  | `satisfied` |
| `d-2`   | `approved`      | `approved_by = null`                     | `false` | `absent`    |

You didn't write the checks starting with `$`. Ergo adds them, as [Checks Ergo adds](REFERENCE.md#checks-ergo-adds) says: `$well_formed` makes sure the requirement makes sense, `$min_subjects` that at least one subject was found, `$unique_ids` that no two subjects share an id, and `$applies` records whether each subject passed the `whose` conditions. `d-3` didn't, and the report says so rather than leaving it out.

When a check fails, `cause` tells you why. `d-2` failed with `absent` because it has no `approved_by` field at all: no approval was ever recorded. Had `approved_by` been `""`, the cause would be `value` instead, since an approval was recorded but it's empty. Both fail, but they're different problems and you'd fix them differently.

### Violations

The report holds every row, passed or failed. To tell someone only what went wrong, ask for the violations, with `ergo violations` or `ergo.violations`. They are:

```json
[
  {
    "cause": "absent",
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [
      {
        "locations": [
          "/deployments/1"
        ],
        "name": "approved_by",
        "value": null
      }
    ],
    "requirement": "prod_deploy",
    "subject": {
      "id": "d-2",
      "type": "deployment"
    }
  }
]
```

`violations` is built from the report. It keeps only the failed rows that are real problems and adds each check's `description` and `expression`, so you have what you need to write a message. `d-3` isn't listed: it failed `$applies`, but being out of scope isn't a problem.

## Going further

Install an engine and run the policy: [Ergo with OPA](OPA.md) or [Ergo CLI](CLI.md). The [reference](REFERENCE.md) covers every field, operator and cause, including the ones this example doesn't use.

## Contributing

Bug reports, ideas and pull requests are welcome. [`CONTRIBUTING.md`](https://github.com/kosli-dev/ergo/blob/main/CONTRIBUTING.md) explains how, and everyone taking part follows the [code of conduct](https://github.com/kosli-dev/ergo/blob/main/CODE_OF_CONDUCT.md).

## License

Ergo is licensed under the [Apache License 2.0](LICENSE).
