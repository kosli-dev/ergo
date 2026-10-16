# ergo

ergo is brand new and still changing a lot before its first alpha, so expect breaking changes.

## Getting started

ergo is a single Rego file, so using it is as simple as copying it into your project.

You'll need [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) 1.20.1 or later to run it, and we test ergo with OPA 1.20.2. Older versions give wrong results or don't load it: OPA 1.19 says `1 >= 100.0` is true, so a check can pass when it should fail, OPA 1.20.0 stops with `panic: illegal value` on `0.0 == 1.5`, and OPA 1.2 stops with `rego_parse_error: unexpected as keyword`. Run `opa version` to see which one you have.

### 1. Copy the library

Copy `ergo.rego` into the directory that holds your policies:

```
policy/
  ergo.rego
```

### 2. Write a policy

Here is a policy that says "_every production deployment must have an approver_". It goes in a YAML file next to `ergo.rego`.

`policy/policy.yaml`:

```yaml
subjects:
  deployment:
    from: deployments whose environment is "prod"
    id: id
requirements:
  prod_deploy:
    description: Every production deployment is approved
    subject: deployment
    checks:
      approved:
        description: Someone approved the deployment
        assert: approved_by is a non-empty string
```

A policy describes what to check, not how to check it. First it says what it's about, the things we call _subjects_. Each kind of subject gets a name, here `deployment`, that the report uses for each one, and says where to find them:

- `from` says where the subjects are in the input. `deployments` means `input.deployments`, and `release.deployments` would mean `input.release.deployments`. `whose` keeps only the ones this policy is about, here the deployments whose `environment` is `prod`.
- `id` is the field that uniquely identifies each subject.

Then the requirement says what must be true of them. Its `description` says what it requires, in words anyone can read, and `subject` names the subject it checks:

- `checks` are the rules each subject must pass, each one written as a sentence. Here, `approved_by` must be a non-empty string. A check with nothing to add can be the sentence alone: `approved: approved_by is a non-empty string`.

Several requirements can check the same subject. Each one gets its own rows in the report.

Then a Rego file hands the policy to ergo. OPA reads every YAML and JSON file in the directory you pass with `-d`, so the YAML file becomes `data.subjects` and `data.requirements`.

`policy/deploy.rego`:

```rego
package deploy

import data.ergo

default subjects := {}

subjects := data.subjects

default requirements := {}

requirements := data.requirements

report := ergo.report(input, {"subjects": subjects, "requirements": requirements}, {})

violations := ergo.violations(report)
```

`ergo.report` takes the input, the policy and the params. The policy holds the subjects and the requirements, and this one has no params, so they're `{}`.

The defaults keep the report defined when the file leaves out `subjects:` or `requirements:`, or spells one wrong. That report still fails: with no requirements it isn't compliant, and with no subjects the requirement names one that isn't there.

#### The old way of writing checks

Before sentences, a check was an object with an `op` and a `path`, like `{op: non_empty_string, path: [approved_by]}`, and a subject used `applies_to` filters written the same way. That still works, but it's going away. We'll say when, well in advance. `ergo.as_sentences` rewrites a policy written that way as sentences, as "Moving a policy to sentences" in the [reference](REFERENCE.md) shows.

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

The report records every check ergo ran, including the ones that passed. It comes in three parts, after the policy's own `description` and `meta`, which this one doesn't have:

```json
{
  "compliant": false,
  "description": "",
  "meta": {},
  "requirements": { ... },
  "results": [ ... ]
}
```

- `compliant` is the overall answer. When you need a plain yes or no to allow or block something, this is the one to use: `allow := report.compliant`.
- `requirements` has an entry for each requirement. It repeats the requirement's `description`, and its `status` is `met`, `not_met`, or `not_applicable` when no subject was left to check. When it's `not_met`, `causes` says why, worst first, with how many rows each: here `[{"cause": "absent", "rows": 1}]`. It also says how many subjects were found and kept, and lists every check with a readable `expression`, which is the sentence as you wrote it.
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
- `$applies` records whether each subject passed the `whose` conditions. `d-3` didn't, and the report says so rather than leaving it out. A deployment with no `environment` at all would fail `$applies` with the cause `absent`, and the requirement would fail with it, because ergo can't tell whether it's a production deployment.

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
    "cause": "absent",
    "check": "approved",
    "description": "Someone approved the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [{ "name": "approved_by", "value": null }],
    "requirement": "prod_deploy",
    "subject": { "id": "d-2", "type": "deployment" }
  }
]
```

`violations` is built from the report. It keeps only the failed rows that are real problems and adds each check's `description` and `expression`, so you have what you need to write a message. `d-3` isn't listed: it failed `$applies`, but being out of scope isn't a problem.

### Going further

The [reference](REFERENCE.md) covers every field, operator and cause, including the ones this example doesn't use.

### Updating

Copy the new `ergo.rego` over the old one and run your policy's tests.

## Contributing

Bug reports, ideas and pull requests are welcome. [`CONTRIBUTING.md`](https://github.com/kosli-dev/ergo/blob/main/CONTRIBUTING.md) explains how, and everyone taking part follows the [code of conduct](https://github.com/kosli-dev/ergo/blob/main/CODE_OF_CONDUCT.md).

## License

ergo is licensed under the [Apache License 2.0](LICENSE).
