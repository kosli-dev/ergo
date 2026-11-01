# Ergo with OPA

`ergo.rego` is Ergo for [Open Policy Agent](https://www.openpolicyagent.org/). It is one file with no dependencies, and it gives the report that [REFERENCE.md](REFERENCE.md) describes. This page is for running it: how to install it, how to hand it a policy, and what is particular to it, like the OPA version, Wasm and numbers. What a policy can say, and what a report holds, is the same for both engines, so it is in the [README](README.md) and the [reference](REFERENCE.md). To run Ergo without OPA, see [Ergo CLI](CLI.md).

This page follows the latest release of `ergo.rego`.

- [Install](#install)
- [Run a policy](#run-a-policy)
- [Calling ergo.rego from Rego](#calling-ergorego-from-rego)
- [Numbers](#numbers)
- [Compiling to Wasm](#compiling-to-wasm)
- [Compiling a policy](#compiling-a-policy)
- [Failing closed](#failing-closed)
- [Policies written before 0.1](#policies-written-before-01)
- [Updating](#updating)

## Install

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

## Run a policy

Write the policy of the [README](README.md#a-first-policy) in `policy/policy.yaml`, and its input in `deployments.json`. `ergo.rego` is a function, so a Rego file hands it the policy. OPA reads every YAML and JSON file in the directory you pass with `-d`, so the YAML file becomes `data.ergo_spec`, `data.subjects` and `data.requirements`.

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

Ask for the report:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.report'
```

The report is the one the [README](README.md#the-report) shows, and its `engine` says that `ergo.rego` made it:

```json
{
  "compliant": false,
  "engine": {
    "name": "ergo.rego",
    "version": "0.3.1"
  },
  "ergo": "v0.3",
  ...
}
```

To get only what went wrong, ask for the violations:

```sh
opa eval -d policy -i deployments.json --format=pretty 'data.deploy.violations'
```

They are the violations the README shows.

## Calling ergo.rego from Rego

You pass the policy to `ergo.report` along with the input and the [params](#params):

```rego
default ergo_spec := null

ergo_spec := data.ergo_spec

default subjects := {}

subjects := data.subjects

default requirements := {}

requirements := data.requirements

default params := {}

params := data.params

report := ergo.report(input, {"ergo_spec": ergo_spec, "subjects": subjects, "requirements": requirements}, params)
```

`ergo.report` reads only its three arguments, so the same arguments always give the same report. The policy can also be written in Rego, like `subjects := {"deployment": {"from": "deployments", "identified_by": "id"}}`.

Give each argument a default like this when it comes from `data`. Rego doesn't call a function with an argument that isn't defined, so a file without `requirements:`, or a run without params, would make the whole report undefined, with no rows to say why. The defaults still fail closed: without `ergo_spec` every requirement is written wrong, with no subjects every requirement fails, because the subject it names isn't there, with no requirements the policy isn't compliant, and with no params every `$params` read fails as `absent`. The same goes for the input: if it can be missing, give it a default too.

From your own policies, call only `ergo.report` and `ergo.violations`. Rules whose names start with `_`, like `ergo._row_cause`, are Ergo's own and can change or disappear in any release. If you lint with [Regal](https://www.openpolicyagent.org/projects/regal), its `leaked-internal-reference` rule flags a call to one.

### Describing a policy

A policy can have a `description` and a `meta` of its own, as [Describing a policy](REFERENCE.md#describing-a-policy) says. OPA reads them as `data.description` and `data.meta`, so pass them in with the sections:

```rego
default description := null

description := data.description

default meta := null

meta := data.meta

report := ergo.report(input, {"ergo_spec": ergo_spec, "description": description, "meta": meta, "subjects": subjects, "requirements": requirements}, params)
```

### Params

Params are the third argument to `ergo.report`. Ergo doesn't look for them anywhere else, so the policy that calls it picks where they come from. Reading them from `data.params`, as above, means `opa eval -d params.json` passes them in when the file holds `{"params": ...}`, and a test can write `with data.params as {...}`.

## Numbers

`ergo.rego` compares numbers with OPA, and OPA can treat two decimals as the same when they only differ after the 15th significant digit. Whole numbers are always compared exactly. With this policy and this input:

```yaml
ergo_spec: v0.4-dev
subjects:
  row:
    from: rows
    identified_by: id
requirements:
  r:
    subject: row
    checks:
      most: l is at most 1234567890.1209567890
      within: l equals r within 1234567889.6209567890
```

```json
{"rows": [{"id": "a", "l": 1234567890.1209567890, "r": 0.5}, {"id": "b", "l": 1234567890.1209567990, "r": 0.5}]}
```

`most` passes on `b`, even though its `l` is bigger than the limit. OPA also remembers the result of a comparison and reuses it for any number it treats as the same, so the answer can depend on the other rows: `within` fails on `b` when `b` is the only row, but passes on `b` when `a` is also in the input. The Rust engine, which the `ergo` CLI runs, compares every digit and fails both checks on `b`. So keep the decimals you compare to at most 15 significant digits, or use the Rust engine, for example with the `ergo` CLI. [#426](https://github.com/kosli-dev/ergo/issues/426) is about fixing `ergo.rego`.

## Compiling to Wasm

Ergo runs in a policy compiled with `opa build -t wasm` and run with OPA's JavaScript runtime, `@open-policy-agent/opa-wasm`. One built-in is missing from that runtime: `time.parse_rfc3339_ns`, which `compare_time` uses on RFC 3339 strings. A policy with such a check fails with `not implemented: built-in function`, unless you pass the built-in in yourself, as the third argument to `loadPolicy`.

Ergo only passes it a time it has already checked: an uppercase `T` and `Z`, a date that exists and a year from 1678 to 2261. So it only has to turn that into nanoseconds since 1970, exactly. A JavaScript number can't hold that: today's are about 1.76×10¹⁸, where a number can only step by 256. So return the digits with `JSON.rawJSON` (Node 21 and later). This is the version Ergo's CI uses, and it gives the same nanoseconds as OPA on 16,922 generated timestamps, before and after 1970:

```js
const parseTime = (v) => {
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const policy = await loadPolicy(wasm, undefined, { "time.parse_rfc3339_ns": parseTime });
```

## Compiling a policy

**Experimental:** `ergo.compile` may change or go away in any version of Ergo.

`ergo.report` reads every sentence of the policy each time it runs. When the same policy runs many times, like in a test suite, you can do that once with `ergo.compile(policy)`, save what it returns as JSON, and pass that to `ergo.report` in place of the policy. The report is the same. This is Ergo's own step, not OPA's: OPA still compiles `ergo.rego` as usual.

Treat a compiled policy like a compiler's object file. Make it in the build that uses it, don't commit it, and make it again whenever the policy or your copy of `ergo.rego` changes. Its shape is Ergo's own and changes between versions. A compiled policy holds the `engine` that compiled it, the same name and version a report gives. When it's missing or isn't the one running, `ergo.report` reads the policy the compiled one came from and fails every requirement's `$well_formed` row with an input like:

```json
{"name": "ergo/compiled engine", "value": ["compiled by another engine, expected ergo-rego 0.4.0-dev"], "locations": []}
```

or `["missing"]` when the compiled policy has no `engine`. That only tells released versions apart: every copy of `ergo.rego` between two releases has the same `-dev` version, so a compiled policy from an older copy of the same version still runs and can give a wrong report. Ergo doesn't check that nobody edited it either, so don't edit it. One with a field missing or of the wrong type fails like a policy Ergo can't read, and compiling a compiled policy gives it back unchanged, even one from another engine.

A `make` rule keeps it fresh, since it runs again when either file changes. With this `policy.yaml`:

```yaml
ergo_spec: v0.4-dev
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  approved_deploy:
    subject: deployment
    checks:
      approved: approved_by is not empty
```

this `Makefile` compiles it:

```make
compiled_policy.json: policy.yaml ergo.rego
	opa eval -d ergo.rego -d policy.yaml --format raw \
	  'json.marshal({"compiled_policy": data.ergo.compile({"ergo_spec": data.ergo_spec, "subjects": data.subjects, "requirements": data.requirements})})' > $@
```

and `policy.rego` runs it:

```rego
package policy

import data.ergo

report := ergo.report(input, data.compiled_policy, {})
```

On this `input.json`:

```json
{"deployments": [{"id": "d-1", "approved_by": "alice"}, {"id": "d-2", "approved_by": ""}]}
```

`make` and then `opa eval -d ergo.rego -d policy.rego -d compiled_policy.json -i input.json --format pretty 'data.ergo.violations(data.policy.report)'` give the same violation as the policy itself:

```json
[
  {
    "cause": "value",
    "check": "approved",
    "description": "",
    "expression": "approved_by is not empty",
    "inputs": [{ "name": "approved_by", "value": "", "locations": ["/deployments/1/approved_by"] }],
    "requirement": "approved_deploy",
    "subject": { "id": "d-2", "type": "deployment" }
  }
]
```

The input and the params are read on each run, so a compiled policy works with any of them. Put `compiled_policy.json` in `.gitignore`: a fresh clone gives files the time of checkout, so a committed one can look newer than an `ergo.rego` it doesn't match.

Compiling is part of `ergo.rego`, not of the [spec](spec/README.md), so other implementations of Ergo don't have it.

## Failing closed

Besides what the [reference](REFERENCE.md#failing-closed) lists, which both engines do:

- Running OPA with `--strict-builtin-errors` gives the same report as running without it, because Ergo checks a value's type before it passes it to a built-in like `object.get` or `count`.

## Policies written before 0.1

The [reference](REFERENCE.md#policies-written-before-01) says what spec 0.1 stopped reading. `ergo.rego` has a function that rewrites what it can.

### Moving a policy to sentences

`ergo.as_sentences(policy)` rewrites a policy written the old way into sentences, wherever a sentence reads back as exactly what was written. It always sets `ergo_spec: v0.4-dev` on what it returns. Anything it can't rewrite stays as it was, and under 0.1 that is written wrong, so you rewrite those parts by hand. With this `policy.yaml`:

```yaml
subjects:
  deployment:
    from: [deployments]
    identified_by: [id]
    applies_to:
      is_prod: {op: equals, path: [environment], value: prod}
requirements:
  approved:
    subject: deployment
    checks:
      approved:
        description: Someone approved the deployment
        op: non_empty_string
        path: [approved_by]
      region: {op: in, path: [region], values: [eu-west-1, us-east-1]}
      signed: {op: all, path: [commits], check: {op: equals, path: [signed], value: true}}
```

this command:

```sh
opa eval -d ergo.rego -d policy.yaml --format raw \
  'yaml.marshal(data.ergo.as_sentences({"subjects": data.subjects, "requirements": data.requirements}))'
```

prints:

```yaml
ergo_spec: v0.4-dev
requirements:
  approved:
    checks:
      approved:
        assert: approved_by is a non-empty string
        description: Someone approved the deployment
      region: region is one of "eu-west-1", "us-east-1"
      signed:
        check:
          op: equals
          path:
            - signed
          value: true
        op: all
        path:
          - commits
    subject: deployment
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
```

`signed` is still in the old form, so it is written wrong, with `["missing assert", "unknown field check", "unknown field op", "unknown field path"]`. To fix it, write `every commits.signed is true`.

These have no sentence form, so `as_sentences` leaves them as they are:

- `all` and `any`. They read one list, or two with `each`, where `every` and `some` walk every list along their path, so a policy could pass where it failed. Write the check with `every` or `some`, or with a `for` line.
- `any_of` options written with `op`. Write each option as a sentence, under `any_of`.
- A selector, like `{"where": {...}}`, in a path. Pick the item with a `for` line.
- A literal list of keys after `each_as`. `named by each of $params.x` reads the keys from the params.
- `inputs` on a check. A row shows the fields its sentence reads.
- A name, a `description` or a `meta` on an `applies_to` filter. A `whose` condition has none of them, so a subject with one keeps its `applies_to`, which is written wrong.
- A side written as `count`, `sum`, `add` or `literal`. Write it as `count of`, `sum of` or `plus`.
- A check that compares a field with itself, because that sentence is written wrong.
- A check of a subject read from or built on another subject, like `from: artifact.pull_requests` or an old `of`. A sentence there reads `artifact` as that subject.

The comments of a YAML file are lost, since OPA reads it as data.

## Updating

Download the new file over the old one and run your policy's tests. [`CHANGELOG.md`](CHANGELOG.md) says what each release changed, and which spec version it follows.
