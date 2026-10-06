# ergo

ergo is brand new and still changing a lot before its first alpha, so expect breaking changes.

## Getting started

ergo is a single Rego file, so using it is as simple as copying it into your project.

You'll need [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) to run it. We test ergo with OPA 1.19 and 1.20.2. Older versions may not load it: OPA 1.2, for example, stops with `rego_parse_error: unexpected as keyword`. Run `opa version` to see which one you have.

### 1. Copy the library

Copy `ergo.rego` into the directory that holds your policies:

```
policy/
  ergo.rego
```

### 2. Write a policy

Here is a policy that says "_every production deployment must have an approver_".

`policy/deploy.rego`:

```rego
package deploy

import data.ergo

requirements := {"prod_deploy": {
	"subject_type": "deployment",
	"from": ["deployments"],
	"id": ["id"],
	"applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
	"checks": {"approved": {
		"description": "Someone approved the deployment",
		"op": "non_empty_string",
		"path": ["approved_by"],
	}},
}}

report := ergo.report(input, requirements)

violations := ergo.violations(report)
```

A requirement describes what to check, not how to check it. It starts by saying what the policy is about, the things we call _subjects_:

- `subject_type` is a human-friendly name for them.
- `from` is the path to the subjects in the input. `["deployments"]` means `input.deployments`, and `["release", "deployments"]` would mean `input.release.deployments`.
- `id` is the field that uniquely identifies each subject.

Then we can optionally keep only the subjects that are relevant to this policy:

- `applies_to`: in this case, we define one filter that selects only the deployments whose `environment` is `prod`.

And finally we define the actual checks for this policy:

- `checks` are the rules each subject must pass. Here, `approved_by` must be a non-empty string.

#### Or write the requirements in YAML

Requirements are plain data, so you can keep them in a YAML file instead. OPA reads every YAML and JSON file in the directory you pass with `-d`, so this file becomes `data.requirements`.

`policy/requirements.yaml`:

```yaml
requirements:
  prod_deploy:
    subject_type: deployment
    from: [deployments]
    id: [id]
    applies_to:
      is_prod:
        op: equals
        path: [environment]
        value: prod
    checks:
      approved:
        description: Someone approved the deployment
        op: non_empty_string
        path: [approved_by]
```

The Rego file then only has to hand them to ergo:

`policy/deploy.rego`:

```rego
package deploy

import data.ergo

report := ergo.report(input, data.requirements)

violations := ergo.violations(report)
```

The report and the violations below come out the same either way.

### 3. Get the report

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

Let's ask for the report:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.report'
```

The report records every check ergo ran, including the ones that passed. It comes in three parts:

```json
{
  "compliant": false,
  "requirements": { ... },
  "results": [ ... ]
}
```

- `compliant` is the overall answer. When you need a plain yes or no to allow or block something, this is the one to use: `allow := report.compliant`.
- `requirements` has an entry for each requirement. Its `status` is `met`, `not_met`, or `not_applicable` when no subject was left to check. It also says how many subjects were found and kept, and lists every check with a readable `expression`, such as `approved_by is a non-empty string`.
- `results` has one row per subject and check, with the value ergo read, whether the check passed, and a `cause`.

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

You didn't write the checks starting with `$`. ergo adds them for you:

- `$well_formed` makes sure the requirement itself makes sense, for example that it has at least one check.
- `$min_subjects` makes sure at least one subject was found. If `from` points to nothing, this check fails, so the policy can't pass without checking anything.
- `$unique_ids` makes sure no two deployments share an id. Otherwise their rows could look the same, and you couldn't tell which one failed.
- `$applies` records whether each subject passed the `applies_to` filter. `d-3` didn't, and the report says so rather than leaving it out. A deployment with no `environment` at all would fail `$applies` with the cause `absent`, and the requirement would fail with it, because ergo can't tell whether it's a production deployment.

When a check fails, `cause` tells you why. `d-2` failed with `absent` because it has no `approved_by` field at all: no approval was ever recorded. Had `approved_by` been `""`, the cause would be `value` instead, since an approval was recorded but it's empty. Both fail, but they're different problems and you'd fix them differently.

Whatever the policy, the report always has the same shape. You can store it, compare it, or hand it to someone who doesn't read Rego, and they'll still see what was checked, what was found, and what passed.

### 4. Get the violations

Because the report has everything, it gets long. When all you want is to tell someone what went wrong, ask for the violations instead:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.violations'
```

```json
[
  {
    "requirement": "prod_deploy",
    "subject": { "type": "deployment", "id": "d-2" },
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [{ "name": "approved_by", "value": null }],
    "cause": "absent"
  }
]
```

`violations` is built from the report. It keeps only the failed rows that are real problems and adds each check's `description` and `expression`, so you have what you need to write a message. `d-3` isn't listed: it failed `$applies`, but being out of scope isn't a problem.

### Going further

The [reference](REFERENCE.md) covers every field, operator and cause, including the ones this example doesn't use.

### Updating

Copy the new `ergo.rego` over the old one and run your policy's tests.

## License

ergo is licensed under the [Apache License 2.0](LICENSE).
