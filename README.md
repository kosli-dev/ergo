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

### One spec, two engines

Two engines build Ergo reports, and you choose one:

- `ergo.rego` runs on [Open Policy Agent](https://www.openpolicyagent.org/). It is one file with no dependencies. Run it with `opa eval`, or compile it to Wasm and run it with OPA's JavaScript runtime, as [REFERENCE.md](REFERENCE.md#compiling-to-wasm) shows.
- The Rust engine is experimental. It runs as the `ergo` CLI, or in a browser through Wasm, and its sentence reader works alone, for editors and linters. See [`engines/rust/README.md`](engines/rust/README.md).

Both run every case in [`spec/cases`](spec/cases) and give the same report, apart from `engine`, which says which one made it.

Every rule Ergo follows is written down in the [spec](spec/README.md), with cases that pin it, and both the policy and the report have a JSON Schema. A policy says which spec version it's written for, and a report says which engine made it and which version it follows, so other tools can read the reports.

## Getting started

### 1. Pick an engine

#### ergo.rego

`ergo.rego` is a single file. Download it into your project and write a policy next to it.

You'll need [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) 1.20.1 or later to run it, and we test Ergo with OPA 1.20.2. Older versions give wrong results or don't load it: OPA 1.19 says `1 >= 100.0` is true, so a check can pass when it should fail, OPA 1.20.0 stops with `panic: illegal value` on `0.0 == 1.5`, and OPA 1.2 stops with `rego_parse_error: unexpected as keyword`. Run `opa version` to see which one you have.

Download `ergo.rego` from the [latest release](https://github.com/kosli-dev/ergo/releases/latest) into the directory that holds your policies:

```sh
curl -L --create-dirs -o policy/ergo.rego https://github.com/kosli-dev/ergo/releases/latest/download/ergo.rego
```

```
policy/
  ergo.rego
```

Each release has a version, like `0.2.0`, and the file says which one it is. To stay on one, download it from that release instead of the latest, like `https://github.com/kosli-dev/ergo/releases/download/rego-v0.2.0/ergo.rego`.

#### The `ergo` CLI (experimental)

Install the `ergo` CLI from crates.io. You need Rust, which [rustup](https://rustup.rs/) installs:

```sh
cargo install --locked ergo-policy-cli
```

Or download it, without Rust, for Linux (x86_64) or macOS (arm64) from the [latest release of the CLI](https://github.com/kosli-dev/ergo/releases?q=rust&expanded=true), unpack it and put `ergo` on your `PATH`:

```sh
curl -L https://github.com/kosli-dev/ergo/releases/download/rust-v0.1.0/ergo-0.1.0-macos-arm64.tar.gz | tar xz
./ergo --version
```

On Linux, the file is `ergo-0.1.0-linux-x86_64.tar.gz`.

To build it from this repo with Docker instead, see [`engines/rust/README.md`](engines/rust/README.md#running-from-the-command-line).

### 2. Write a policy

Here is a policy that says "_every production deployment must have an approver_". It goes in a YAML file in `policy/`, next to `ergo.rego` if that's your engine.

`policy/policy.yaml`:

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

Only `ergo.rego` needs the next file. A Rego file hands the policy to Ergo. OPA reads every YAML and JSON file in the directory you pass with `-d`, so the YAML file becomes `data.ergo_spec`, `data.subjects` and `data.requirements`.

`policy/deploy.rego`:

```rego
package deploy

import data.ergo

default ergo_spec := null

ergo_spec := data.ergo_spec

default subjects := {}

subjects := data.subjects

default requirements := {}

requirements := data.requirements

report := ergo.report(input, {"ergo_spec": ergo_spec, "subjects": subjects, "requirements": requirements}, {})

violations := ergo.violations(report)
```

`ergo.report` takes the input, the policy and the params. The policy holds its version, the subjects and the requirements, and this one has no params, so they're `{}`. The version comes from the YAML file and isn't written in the Rego, so that it always says what the file was written for.

The defaults keep the report defined when the file leaves out `ergo_spec:`, `subjects:` or `requirements:`, or spells one wrong. That report still fails: without `ergo_spec` every requirement is written wrong, with no requirements it isn't compliant, and with no subjects the requirement names one that isn't there.

#### The old way of writing checks

This part is about `ergo.as_sentences`, a function of `ergo.rego`. Before 0.1, a check was an object with an `op` and a `path`, like `{op: non_empty_string, path: [approved_by]}`, and a subject used `applies_to` filters written the same way. Spec 0.1 stopped reading that syntax, and later versions don't read it either. A policy written that way is written wrong, and the report says so. `ergo.as_sentences` rewrites what it can as sentences, and [Moving a policy to sentences](REFERENCE.md#moving-a-policy-to-sentences) in the reference shows what it leaves for you to rewrite.

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

Ask for the report. With `ergo.rego`:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.report'
```

With the `ergo` CLI:

```sh
ergo report --policy policy/policy.yaml --input deployments.json
```

The report records every check Ergo ran, including the ones that passed. It comes in four parts, after the policy's own `description` and `meta`, which this one doesn't have, and `engine` and `ergo`, which say what made the report and which version of the [spec](spec/README.md#versions) it follows:

```json
{
  "compliant": false,
  "description": "",
  "engine": {
    "name": "ergo.rego",
    "version": "0.3.1-dev"
  },
  "ergo": "v0.3",
  "meta": {},
  "requirements": { ... },
  "results": [ ... ],
  "subjects": { ... }
}
```

That is the report from `ergo.rego`. The `ergo` CLI gives the same report, except that `engine` names the Rust engine: `{"name": "ergo-policy-engine", "version": "0.2.0-dev"}`.

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

You didn't write the checks starting with `$`. Ergo adds them for you:

- `$well_formed` makes sure the requirement itself makes sense, for example that it has at least one check.
- `$min_subjects` makes sure at least one subject was found. If `from` points to nothing, this check fails, so the policy can't pass without checking anything.
- `$unique_ids` makes sure no two deployments share an id. Otherwise their rows could look the same, and you couldn't tell which one failed.
- `$applies` records whether each subject passed the `whose` conditions. `d-3` didn't, and the report says so rather than leaving it out. A deployment with no `environment` at all would fail `$applies` with the cause `absent`, and the requirement would fail with it, because Ergo can't tell whether it's a production deployment.

When a check fails, `cause` tells you why. `d-2` failed with `absent` because it has no `approved_by` field at all: no approval was ever recorded. Had `approved_by` been `""`, the cause would be `value` instead, since an approval was recorded but it's empty. Both fail, but they're different problems and you'd fix them differently.

### 4. Get the violations

The report holds every row, passed or failed. To tell someone only what went wrong, ask for the violations. With `ergo.rego`:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.violations'
```

With the `ergo` CLI:

```sh
ergo violations --policy policy/policy.yaml --input deployments.json
```

Both print:

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

### Going further

The [reference](REFERENCE.md) covers every field, operator and cause, including the ones this example doesn't use. For the `ergo` CLI and the Rust engine, read [`engines/rust/README.md`](engines/rust/README.md).

### Updating

With `ergo.rego`, download the new file over the old one and run your policy's tests. [`CHANGELOG.md`](CHANGELOG.md) says what each release changed, and which spec version it follows.

With the `ergo` CLI, run `cargo install --locked ergo-policy-cli` again, or download it from the newest release of the CLI.

## Contributing

Bug reports, ideas and pull requests are welcome. [`CONTRIBUTING.md`](https://github.com/kosli-dev/ergo/blob/main/CONTRIBUTING.md) explains how, and everyone taking part follows the [code of conduct](https://github.com/kosli-dev/ergo/blob/main/CODE_OF_CONDUCT.md).

## License

Ergo is licensed under the [Apache License 2.0](LICENSE).
