# Ergo reference

This page describes everything Ergo accepts and everything it returns. If you haven't used Ergo before, start with the [README](README.md).

- [Policies](#policies)
- [Subjects](#subjects)
- [Requirements](#requirements)
- [Checks](#checks)
- [The report](#the-report)
- [Causes](#causes)
- [Violations](#violations)
- [Compiling to Wasm](#compiling-to-wasm)
- [Compiling a policy](#compiling-a-policy)
- [Failing closed](#failing-closed)
- [Policies written before 0.1](#policies-written-before-01)

## Policies

A policy is an object with two sections and the version of the [spec](spec/README.md#versions) it's written for, and it can [describe itself](#describing-a-policy) too. `subjects` says what the policy checks and where to find it in the input, and `requirements` says what must be true of it. Each section maps names to definitions. A policy is plain data, so it usually lives in a YAML file that OPA loads. A file in the policy directory with top-level `ergo_spec`, `subjects` and `requirements` keys is read as `data.ergo_spec`, `data.subjects` and `data.requirements`:

```yaml
ergo_spec: v0.3
subjects:
  deployment: { ... }
  commit: { ... }
requirements:
  approved_deploy: { subject: deployment, ... }
  signed_commits: { subject: commit, ... }
```

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

`ergo_spec` is the version of the spec the policy is written for, and this copy of Ergo follows `v0.3`. A policy without it, or with `null`, a number like `0.1`, or another version, is written wrong, so every requirement's `$well_formed` row fails and lists it with the policy's other problems, as an input named `policy ergo_spec`. Its value says what's wrong: `missing`, `not a string`, `not a version V0.1` for a string that isn't shaped like a version, or `unsupported version v0.1, expected v0.3` for one this copy of Ergo doesn't follow. When the policy is in a file, pass `ergo_spec` from that file, like `data.ergo_spec` above, and don't write it in the Rego that hands the policy over: a fixed value there would say the file follows `v0.3` whatever it was written for. A policy written in Rego says it in the policy itself, like `{"ergo_spec": "v0.3", "subjects": ...}`.

Because each name is an object key, two requirements can't share a name, and every row in the report points back to exactly one requirement.

A policy with no requirements is never compliant: it doesn't check anything, so it can't vouch for anything either. The same goes for a policy that isn't an object, or whose `requirements` isn't one. Ergo leaves out any other section of the policy, so it changes nothing in the report.

From your own policies, call only `ergo.report` and `ergo.violations`. Rules whose names start with `_`, like `ergo._row_cause`, are Ergo's own and can change or disappear in any release. If you lint with [Regal](https://www.openpolicyagent.org/projects/regal), its `leaked-internal-reference` rule flags a call to one.

### Describing a policy

A policy can have a `description` and a `meta` of its own, next to its sections. They work like a [requirement's](#requirements): `description` says what the policy asks for, `meta` keeps anything else, like the id of the control the policy checks, and Ergo copies both to the top of the report and never reads them. This is where a control with several requirements keeps its text:

```yaml
ergo_spec: v0.3
description: Production changes are reviewed and approved
meta: {control: DEV-0401, title: Security testing and code review}
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
requirements:
  approved:
    subject: deployment
    checks:
      approved: approved_by is a non-empty string
  reviewed:
    subject: deployment
    checks:
      reviewed: reviewer is a non-empty string
```

OPA reads them as `data.description` and `data.meta`, so pass them in with the sections:

```rego
default description := null

description := data.description

default meta := null

meta := data.meta

report := ergo.report(input, {"ergo_spec": ergo_spec, "description": description, "meta": meta, "subjects": subjects, "requirements": requirements}, params)
```

With this input:

```json
{"deployments": [{"id": "d-1", "environment": "prod", "approved_by": "alice", "reviewer": "bob"}]}
```

the report starts with:

```json
{
  "compliant": true,
  "description": "Production changes are reviewed and approved",
  "engine": {
    "name": "ergo.rego",
    "version": "0.3.1-dev"
  },
  "ergo": "v0.3",
  "meta": {
    "control": "DEV-0401",
    "title": "Security testing and code review"
  },
  ...
}
```

`null` counts as not written, so the defaults above give `""` and `{}`. A `description` that isn't a string, or a `meta` that isn't an object or holds something JSON can't, belongs to every requirement, so every requirement's `$well_formed` row fails and lists it last, like `{"name": "policy meta", "value": ["not an object"], "locations": []}`. The report then shows `""` or `{}` in its place.

### Params

Params are the third argument to `ergo.report`. Ergo doesn't look for them anywhere else, so the policy that calls it picks where they come from. Reading them from `data.params`, as above, means `opa eval -d params.json` passes them in when the file holds `{"params": ...}`, and a test can write `with data.params as {...}`.

A sentence reads them with `$params`, like `region is in $params.regions`. Params aren't part of the input, so `$input.params` doesn't reach them, and `$params` doesn't read the input. With params of `{}`, a read of a field in them, like `$params.regions`, fails as `absent`, as any missing field does. With no params, `null`, it fails as `absent` too, and that includes `exists`, which otherwise fails a missing field as `value`, and `does not exist`, which otherwise passes. So a condition like that on a param fails the requirement instead of deciding the scope. Params that are anything else, like a string or a list, can only be a mistake, so they fail every check and every `$min_subjects` row as `unusable`, even in a policy that reads no params, and `$min_subjects` says why: `{"name": "$params", "value": ["not an object"], "locations": []}`. Ergo has no defaults, so a policy run without its params fails instead of checking something nobody configured.

## Subjects

A subject is the kind of thing a requirement checks, like a deployment or a pull request, and says where to find them in the input:

```yaml
deployment:
  description: A deployment to production
  from: deployments whose environment is "prod"
  identified_by: id
```

| Field           | Meaning                                                                                                                 | Default                                |
| --------------- | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `description`   | What the subject is, in words anyone can read. The report copies it into its [`subjects`](#subjects-in-the-report).     | `""`                                   |
| `from`          | Where the subjects are in the input, and which of them are in scope, written as a [from line](#from-lines).             | the input field named like the subject |
| `identified_by` | The path, inside one subject, to the value that identifies it.                                                          | the whole subject                      |
| `has`           | Names for paths inside the subject, so a check can write a short alias where a long path would go. See [Parts](#parts). | none                                   |

A `from` or `identified_by` that isn't a string, and the fields `applies_to` and `of`, are [written wrong](#policies-written-before-01).

The subject's name is what the report calls each one, in every row, like `"subject": {"type": "deployment", "id": "d-2"}`, and in the descriptions of the [checks Ergo adds](#checks-ergo-adds), like `The in-scope deployment count is at least 1`. So name it the way a reader would, like `deployment` or `pull request`.

A requirement names its subject with `subject`. Several requirements can name the same subject, and each one checks it on its own, with its own rows. A subject that no requirement names isn't read, so it changes nothing in the report.

A few details:

- If `from` leads to a list, each item is a subject. If it leads to a single object, that object is the only subject. If it leads nowhere, to `null`, or to anything else, like a string or a number, there are no subjects and `$min_subjects` fails with cause `absent`, `null` or `unusable`, even with `min_subjects: 0`, because that's what a typo in `from` looks like. A path through something that can't hold the next key, like `"build": "b1"` for `build.items`, gives `unusable`, and a missing or `null` value along the path gives `absent`, as they do in a [check](#checks). An empty list is different: it was read fine, so it fails `$min_subjects` as `value`, or passes with `min_subjects: 0`.
- The input has to be an object. A `null` input fails `$min_subjects` as `null` when `from` is empty or left out, and as `absent` when it has a step. Any other input that isn't an object, a list included, fails it as `unusable`.
- If `identified_by` doesn't lead anywhere, the subject's id is `null`. Its rows are still there. A subject whose `from` uses `named by each of` takes its key as its id, so it can't have an `identified_by`.
- No two subjects can share an id, or their rows could be identical and the report couldn't say which one failed. If two do, `$unique_ids` fails and so does the requirement. Every subject counts, even one that its conditions leave out, and `null` is an id like any other, so two subjects without one clash.
- An item of the list that isn't an object, like a string or a `null`, is still a subject. Its id is the item itself, and its checks fail with cause `not_an_object`.
- Without `from`, a subject reads the input field named like it, so `artifact` reads `artifact`. A subject with nothing under it, `artifact:` alone in YAML, does the same. To check the whole input as one subject, write `from: $input`. When the input is a list, `from: $input` and `from: every $input` make each item a subject, as `from: things` does on a list called `things`, with locations like `/0/x`. When a walk from the input breaks in one item, like `commits` being `5` in the second item for `from: every $input.commits`, `failed_items` names the place `$input[1].commits`. When the walk breaks on the input itself, like an object or `null` for `from: every $input`, the place is named `$input`. The expressions of `$min_subjects` and `$unique_ids` name a position on the input from `$input` too, like `count(matching(item 1 of $input)) >= 1` for `from: $input[0]`. A position, like `from: $input[0]` or `from: first of $input`, reads the item at it, and ends `absent` when the list has none. `from: every $input[0]` makes each item of that item a subject. Without `identified_by`, each row repeats the whole subject as its id, so two identical subjects clash.
- A subject that's written wrong fails `$well_formed` on every requirement that names it, so none of them is met. That's a subject that isn't an object, or that has a field that isn't in the table above, like `subject_type`, `applies_to` or `of`, or whose `from` or `identified_by` isn't a string or can't be read, or whose `description` isn't a string. The `$well_formed` row names each field with its subject, like `{"name": "subjects.deployment.from", "value": ["doesn't parse"], "locations": []}` or `{"name": "subjects.deployment.from", "value": ["not a string"], "locations": []}` for a list. Each of those requirements gets only its `$well_formed` row, as for a [requirement that's written wrong](#requirements), and a `from` that isn't a string or can't be read is shown as `<invalid from>` in expressions.

### From lines

A `from` line is a path, and `whose` with conditions joined by `and` keeps the subjects they hold for. Paths and conditions are written as in [checks](#checks). `identified_by` is a path written the same way:

```yaml
ergo_spec: v0.3
subjects:
  emergency change:
    from: deployments whose environment is "prod" and change_type is "emergency"
    identified_by: id
  artifact:
    identified_by: fingerprint
requirements:
  approved:
    subject: emergency change
    checks:
      approved: approved_by is a non-empty string
  signed:
    subject: artifact
    checks:
      signed: signed is true
```

With this input:

```json
{"deployments": [
  {"id": "d-1", "environment": "prod", "change_type": "emergency", "approved_by": "bob"},
  {"id": "d-2", "environment": "prod", "change_type": "standard"},
  {"id": "d-3", "environment": "prod"}
],
 "artifact": {"fingerprint": "sha256:abc", "signed": true}}
```

the `$applies` rows keep `d-1` and leave `d-2` out:

```json
{"check": "$applies", "subject": {"id": "d-1", "type": "emergency change"}, "passed": true, "cause": "satisfied",
 "inputs": [{"name": "change_type", "value": "emergency", "locations": ["/deployments/0/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/0/environment"]}], "failed_assertions": []}
{"check": "$applies", "subject": {"id": "d-2", "type": "emergency change"}, "passed": false, "cause": "value",
 "inputs": [{"name": "change_type", "value": "standard", "locations": ["/deployments/1/change_type"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/1/environment"]}],
 "failed_assertions": [{"assertion": "change_type is \"emergency\"", "cause": "value"}]}
{"check": "$applies", "subject": {"id": "d-3", "type": "emergency change"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "change_type", "value": null, "locations": ["/deployments/2"]}, {"name": "environment", "value": "prod", "locations": ["/deployments/2/environment"]}],
 "failed_assertions": [{"assertion": "change_type is \"emergency\"", "cause": "absent"}]}
```

and the `$applies` entry's `expression` is the conditions as written, `environment is "prod" and change_type is "emergency"`. With several conditions, each row has `failed_assertions`, the conditions that failed in the order written and `[]` when none did, as a check written as several sentences has. `d-3` has no `change_type`, so Ergo can't tell whether it's an emergency change, and `approved` isn't met. `artifact` has no `from`, so it reads the input field `artifact`, and `signed` is met.

- `named by $params.name` picks one key: `from: trail.artifacts named by $params.artifact_name`. When the param is missing, `null` or neither a string nor a whole number, there are no subjects and `$min_subjects` fails as `absent`, `null` or `unusable`, also with `every` in front of the line. A whole number reads that item of a list, so `x named by $params.k` with `{"k": 1}` reads `x[1]`.
- `named by each of $params.kinds` makes each key in the list a subject: `from: build.test_runs named by each of $params.kinds`. Each key is a subject, even one the object doesn't have, and the key is its id, so an `identified_by` on that subject is written wrong, with `not allowed with named by each of: the key is the id`. When the object itself is missing, `null` or not an object, a list included, each key is still a subject, but `$min_subjects` fails as `absent`, `null` or `unusable`, so the requirement is never met. A child subject whose parent isn't an object makes no subject of its keys, because nothing below that parent is read: its `$min_subjects` fails as `not_an_object`. When the list is missing, isn't a list, or holds anything but strings, there are no subjects and `$min_subjects` fails as `absent`, `null` or `unusable`.
- A condition can ask about the items of a list with a one-line `some` or `every`, written as in a [check](#checks). With this policy:

  ```yaml
  subjects:
    release:
      from: releases whose some files.path does not match "^docs/"
      identified_by: version
  requirements:
    ticketed:
      subject: release
      min_subjects: 0
      checks:
        approved: ticket.status is "approved"
  ```

  and this input:

  ```json
  {"releases": [
    {"version": "1.4.0", "files": [{"path": "docs/upgrade.md"}, {"path": "src/api.go"}], "ticket": {"status": "approved"}},
    {"version": "1.4.1", "files": [{"path": "docs/upgrade.md"}], "ticket": {"status": "open"}},
    {"version": "1.4.2", "files": [], "ticket": {"status": "open"}}
  ]}
  ```

  the `$applies` rows keep `1.4.0`, which changes a file outside `docs/`, and leave the other two out. They read, and list as `failed_items`, what the same sentence does as a check:

  ```json
  {"check": "$applies", "subject": {"id": "1.4.0", "type": "release"}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "files[].path", "value": ["docs/upgrade.md", "src/api.go"], "locations": ["/releases/0/files/0/path", "/releases/0/files/1/path"]}], "failed_items": []}
  {"check": "$applies", "subject": {"id": "1.4.1", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": ["docs/upgrade.md"], "locations": ["/releases/1/files/0/path"]}],
   "failed_items": [{"path": "files[0].path", "item": "item 1 of files", "cause": "value", "value": "docs/upgrade.md", "locations": ["/releases/1/files/0/path"]}]}
  {"check": "$applies", "subject": {"id": "1.4.2", "type": "release"}, "passed": false, "cause": "value",
   "inputs": [{"name": "files[].path", "value": [], "locations": []}],
   "failed_items": [{"path": "files", "item": "files", "cause": "value", "value": [], "locations": ["/releases/2/files"]}]}
  ```

  A release with no `files` field at all isn't out of scope: Ergo can't tell, so the row fails as `absent` (`null` and `unusable` for a `null` or a wrong type), with the input `{"name": "files.path", "value": [], "locations": []}`, and the requirement isn't met. `every files.path matches "^docs/"` keeps the releases that only change documentation, and `every files.path, if any, matches "^docs/"` keeps the ones with no files too. `some` takes no `, if any,`. A bare name after `some` or `every` is the item's, and a parent subject's name on the right is the parent. The condition can't have a `whose` of its own, and a `whose` in a check or on a `for` line takes no `some` or `every` condition.
- A subject's own name at the start of its `from` is the input field, so `lockfile` can have `from: lockfile whose status is "COMPLETE"`.
- A `from` line that's another subject's name, with or without a `whose`, narrows that subject (a position after the name, like `p[1]` or `first of p`, doesn't narrow it: the subject reads that position inside each `p`, and fails `$min_subjects` as `unusable` when a `p` is an object), as in [a subject built on another](#a-subject-built-on-another): `critical defect` with `from: defect whose severity is "critical"` keeps the defects that pass `defect`'s conditions and its own. A name with a space goes in quotes, so the whole line goes in single quotes in YAML: `from: '"critical defect" whose team is "b"'`. It takes its id from the subject it narrows, so an `identified_by` of its own is written wrong, with `not allowed on a subject that narrows another`.
- A `from` line that starts at another subject's name and goes on reads the rest of its path from that subject. With `{"params": {"artifact_name": "web"}}` and this input:

  ```json
  {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "pull_requests": [
    {"url": "pr/7", "approved_by": "bob"},
    {"url": "pr/8", "approved_by": ""}
  ]}}}}
  ```

  these subjects read the pull requests of the `web` artifact:

  ```yaml
  subjects:
    artifact:
      from: trail.artifacts named by $params.artifact_name
      identified_by: fingerprint
    pull request:
      from: artifact.pull_requests
      identified_by: url
  ```

  The pull requests are a **child subject** of `artifact`: they only exist under an artifact that's in scope, and each one belongs to one artifact. Every row of a requirement on `pull request` says which, under `in`, apart from `$well_formed`, which is about the requirement as written:

  ```json
  {"check": "approved", "subject": {"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "passed": false, "cause": "value",
   "inputs": [{"name": "approved_by", "value": "", "locations": ["/trail/artifacts/web/pull_requests/1/approved_by"]}]}
  ```

  A check reads the artifact by its name, like `artifact.name`. Only checks written as sentences can read it.

  So can a `whose` in the child's `from` line. With `{"params": {"artifact_name": "web"}}` and this input:

  ```json
  {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "branch": "main", "pull_requests": [
    {"url": "pr/7", "base": "main"},
    {"url": "pr/8", "base": "dev"}
  ]}}}}
  ```

  `from: artifact.pull_requests whose base is artifact.branch` keeps `pr/7` and leaves `pr/8` out of scope:

  ```json
  {"check": "$applies", "subject": {"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "passed": false, "cause": "value",
   "inputs": [{"name": "artifact.branch", "value": "main", "locations": ["/trail/artifacts/web/branch"]}, {"name": "base", "value": "dev", "locations": ["/trail/artifacts/web/pull_requests/1/base"]}]}
  ```

  On the left of a `whose`, `artifact.branch` is the pull request's own field, as in any `whose`.

  When the artifact is several subjects, the pull requests of each are read and checked in turn. With this input:

  ```json
  {"trail": {"artifacts": [
    {"fingerprint": "sha-1", "environment": "prod", "pull_requests": [{"url": "pr/7", "approvals": 2}, {"url": "pr/8", "approvals": 0}]},
    {"fingerprint": "sha-2", "environment": "prod", "pull_requests": []},
    {"fingerprint": "sha-3", "environment": "staging", "pull_requests": [{"url": "pr/9", "approvals": 0}]},
    {"fingerprint": "sha-4", "pull_requests": [{"url": "pr/10", "approvals": 1}]}
  ]}}
  ```

  and these subjects and requirement:

  ```yaml
  subjects:
    artifact:
      from: trail.artifacts whose environment is "prod"
      identified_by: fingerprint
    pull request:
      from: artifact.pull_requests
      identified_by: url
  requirements:
    reviewed:
      subject: pull request
      checks:
        approved: approvals is at least 1
  ```

  the report has these rows:

  ```json
  {"check": "$well_formed",  "subject": {"type": "pull request", "id": null}, "passed": true, "cause": "satisfied"}
  {"check": "$min_subjects", "subject": {"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "passed": true, "cause": "satisfied"}
  {"check": "$min_subjects", "subject": {"type": "pull request", "id": null, "in": {"artifact": "sha-2"}}, "passed": false, "cause": "value"}
  {"check": "$min_subjects", "subject": {"type": "pull request", "id": null, "in": {"artifact": "sha-4"}}, "passed": false, "cause": "absent"}
  {"check": "$unique_ids",   "subject": {"type": "pull request", "id": null, "in": {"artifact": "sha-1"}}, "passed": true, "cause": "satisfied"}
  {"check": "$unique_ids",   "subject": {"type": "pull request", "id": null, "in": {"artifact": "sha-2"}}, "passed": true, "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/7", "in": {"artifact": "sha-1"}}, "passed": true, "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/8", "in": {"artifact": "sha-1"}}, "passed": false, "cause": "value"}
  ```

  - Each artifact gets its own `$min_subjects` and `$unique_ids` rows. `sha-2` has no pull requests, so it fails on its own row, unless the requirement has `min_subjects: 0`. Ids only need to be unique within each artifact, so `pr/7` under two artifacts is fine.
  - `sha-3` is out of scope, so its pull requests aren't subjects at all and it has no rows. Nothing in them is read, so `pr/9` isn't checked.
  - `sha-4` has no `environment`, so Ergo can't tell whether it's in scope. Its `$min_subjects` row fails with the cause, even with `min_subjects: 0`, and its pull requests aren't checked.
  - When no artifact is in scope, there's one `$min_subjects` row with no `in`. It fails with `value`, or passes with `min_subjects: 0`, as for any subject that finds none.

  A child subject can have child subjects of its own, so a chain can be three subjects deep, like artifact, pull request and commit:

  ```yaml
  commit:
    from: '"pull request".commits'
    identified_by: sha
  ```

  Each commit row says which artifact and which pull request it belongs to, like `"in": {"artifact": "sha-1", "pull request": "pr/7"}`, and each pull request gets its own `$min_subjects` and `$unique_ids` rows. An artifact or a pull request that's out of scope leaves out everything below it. An artifact whose conditions can't be decided gets one failing `$min_subjects` row, with `"in": {"artifact": ...}`. A check reads any ancestor by its name, like `artifact.name` or `"pull request".title`, and its parts too. A fourth level is written wrong, with `a chain of more than three subjects isn't supported yet`, and so is a subject whose from line narrows a child subject. A chain that comes back to a subject already in it, like `b` with `from: kid.x` and `kid` with `from: b.kids`, is written wrong with `leads to a loop`, however many subjects it goes through.

  A parent that isn't an object, a string or a `null` for instance, can't hold the child's field, so its `$min_subjects` row fails as `not_an_object`, with `in` up to the parent, even with `min_subjects: 0`. A parent that's an object without the field still gives `absent`, and a `from` that starts with a position, like `artifact[0].commits`, keeps the cause it had.
- A `from` line that starts at another subject's name and ends with `named by each of`, like `artifact named by each of $params.keys`, is a child subject too: each key in the list is a subject read inside each parent, so the keys are looked up in the parent and not in an input field named like it, and every row carries the parent under `in`. `artifact.x named by each of $params.keys` reads the keys inside `x` of each parent. A parent that isn't an object fails `$min_subjects` as `not_an_object` and makes no subject of its keys. A missing, `null` or wrong-typed list fails `$min_subjects` of each parent as `absent`, `null` or `unusable`. A first key written with a dot, like `.artifact named by each of $params.keys` or `.artifact.pull_requests`, is always the input field, never the parent, so that line isn't a child subject. A position after the parent's name, like `artifact[0] named by each of $params.keys` or `first of artifact named by each of $params.keys`, reads the parent as a list: `$min_subjects` fails as `unusable` for each parent that's an object, and the keys are still subjects that fail their checks.
- `every` in front of the path walks every list along it, the last one included, as [`every`](#checks) does in a check, and each value it ends at is a subject. With this input:

  ```json
  {"artifacts": [
    {"fingerprint": "sha-1", "pull_requests": [{"url": "pr/7", "approvals": 2}, {"url": "pr/8", "approvals": 0}]},
    {"fingerprint": "sha-2", "pull_requests": []},
    {"fingerprint": "sha-3"}
  ]}
  ```

  and this policy:

  ```yaml
  subjects:
    pull request:
      from: every artifacts.pull_requests
      identified_by: url
  requirements:
    reviewed:
      subject: pull request
      checks:
        approved: approvals is at least 1
  ```

  the pull requests are one list, `pr/7` and `pr/8`, and the report has these rows after `$well_formed`:

  ```json
  {"check": "$min_subjects", "subject": {"type": "pull request", "id": null}, "passed": false, "cause": "absent",
   "inputs": [{"name": "in-scope pull request count", "value": 2, "locations": ["/artifacts/0/pull_requests/0", "/artifacts/0/pull_requests/1"]}],
   "failed_items": [{"path": "artifacts[2].pull_requests", "item": "artifacts[2].pull_requests", "cause": "absent", "value": null, "locations": ["/artifacts/2"]}]}
  {"check": "$unique_ids",   "subject": {"type": "pull request", "id": null}, "passed": true,  "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/7"}, "passed": true,  "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/8"}, "passed": false, "cause": "value"}
  ```

  - Unlike a [child subject](#from-lines), these pull requests don't belong to an artifact. Their rows have no `in`, they're counted once, and their ids must be unique across all of them. A check can't read the artifact.
  - An empty list, like `sha-2`'s, adds nothing and fails nothing.
  - A list that's missing, like `sha-3`'s, `null` or not a list fails `$min_subjects` with the worst cause found, even with `min_subjects: 0`. The row's `failed_items` says where, and the pull requests that could be read are still checked. So does a value at the end that isn't an object, and a path with no list along it, as `every` does in a check.
  - Without `every`, a path through a list reads nothing, and `$min_subjects` fails as `unusable`.
  - `every` can't go with a path that starts at another subject's name or with `named by each of`. Both are written wrong. A path that starts with a dot, like `every .artifact.p`, reads the input field and is fine. A child subject reads names one parent at a time.
- A `from` or `identified_by` that can't be read is written wrong, and the `$well_formed` row says why, like `{"name": "subjects.x.from", "value": ["doesn't parse"], "locations": []}`.

### A subject built on another

When requirements check different parts of the same list, give each part its own subject, built on one that says where the list is. Say the SBOM lists components, some pinned by the lockfile and some exempt from the licence rules:

```yaml
ergo_spec: v0.3
subjects:
  component:
    from: components
    identified_by: name
  locked component:
    from: component whose lock_release exists
  non-exempt component:
    from: component whose exempt is false
requirements:
  versions:
    subject: locked component
    checks:
      matches_lock: sbom_release equals lock_release
  licences:
    subject: non-exempt component
    checks:
      licence_known: some licences is a non-empty string
```

With this input:

```json
{"components": [
  {"name": "a", "sbom_release": "1.2", "lock_release": "1.2", "exempt": false, "licences": ["MIT"]},
  {"name": "b", "sbom_release": "2.0", "lock_release": "2.1", "exempt": true, "licences": []},
  {"name": "c", "sbom_release": "3.0", "exempt": false, "licences": [""]}
]}
```

`licences` checks `a` and `c`, and `versions` checks `a` and `b`. Both fail:

| requirement | subject | check           | passed  | cause       |
| ----------- | ------- | --------------- | ------- | ----------- |
| `licences`  | `a`     | `licence_known` | `true`  | `satisfied` |
| `licences`  | `c`     | `licence_known` | `false` | `value`     |
| `versions`  | `a`     | `matches_lock`  | `true`  | `satisfied` |
| `versions`  | `b`     | `matches_lock`  | `false` | `value`     |

A from line that's another subject's name reads that subject's `from` and `identified_by`, and keeps only the items that pass that subject's conditions and its own. Everything else about it is its own: its rows and descriptions use its name, like `locked component`.

- A subject can build on one that builds on another, and so on. A name with a space goes in quotes, so the whole line goes in single quotes in YAML: `from: '"locked component" whose exempt is false'`.
- A chain that comes back to a subject already in it never reaches a list. It fails as `leads to a loop`.
- A from line can't start at a subject whose name is blank, like `" "`, since no requirement can name it. It fails as `" " isn't a subject name`.
- A problem fails `$well_formed` on every requirement that names a subject whose chain has it, and that row is the requirement's only row.
- A requirement can name the subject others build on too, like `component` to check every component.

### Parts

Data often keeps what a check needs deep inside the subject. Kosli, for one, puts every attestation at `compliance_status.attestations_statuses.<name>.attestation_data`, so a policy that reads three attestations repeats that path in every check. A subject can give a path a name once, with `has`, and the checks use the name. Each entry of `has` is a **part**, and its key is the part's alias. An alias is a short word that stands for something longer, as `as pr` does on a `for` line.

```yaml
ergo_spec: v0.3
subjects:
  round:
    from: trail
    identified_by: name
    has:
      findings: compliance_status.attestations_statuses.findings.attestation_data
      coverage:
        from: compliance_status.attestations_statuses.coverage-verification
        identified_by: attestation_id
requirements:
  review_round:
    subject: round
    checks:
      complete: findings.truncated is false
      every_hunk_acknowledged: coverage.attestation_data.hunks_acknowledged equals coverage.attestation_data.hunks_total
```

With this input:

```json
{
  "trail": {
    "name": "round-1",
    "compliance_status": {
      "attestations_statuses": {
        "findings": { "attestation_data": { "truncated": false } },
        "coverage-verification": {
          "attestation_id": "cov-9",
          "attestation_data": { "hunks_acknowledged": 25, "hunks_total": 28 }
        }
      }
    }
  }
}
```

`complete` passes and `every_hunk_acknowledged` fails with cause `value`:

```json
{"check": "complete", "subject": {"type": "round", "id": "round-1"}, "passed": true, "cause": "satisfied",
 "inputs": [{"name": "findings.truncated", "value": false, "locations": ["/trail/compliance_status/attestations_statuses/findings/attestation_data/truncated"], "part": {"name": "findings", "id": null}}]}
{"check": "every_hunk_acknowledged", "subject": {"type": "round", "id": "round-1"}, "passed": false, "cause": "value",
 "inputs": [{"name": "coverage.attestation_data.hunks_acknowledged", "value": 25, "locations": ["/trail/compliance_status/attestations_statuses/coverage-verification/attestation_data/hunks_acknowledged"], "part": {"name": "coverage", "id": "cov-9"}},
            {"name": "coverage.attestation_data.hunks_total", "value": 28, "locations": ["/trail/compliance_status/attestations_statuses/coverage-verification/attestation_data/hunks_total"], "part": {"name": "coverage", "id": "cov-9"}}]}
```

Each input read through a part says which part, and which one of them: `part` has the alias as the check writes it, and the `id`, the value at the part's `identified_by` inside the part. That is how a reader tells one attestation from another when a subject has several of the same kind. A one-line part has no id, so its `id` is `null`, and so is the id of a part that is missing or has nothing at `identified_by`. An input that doesn't go through a part has no `part`.

A part is a short name for its path and nothing more. `coverage.attestation_data.hunks_total` gives exactly the rows that `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_total` gives: the same `passed`, the same `cause` and the same values. A part that is missing fails the check as `absent`, a `null` one as `absent` when a step follows it, and one of the wrong type as `unusable`, because the full path would. Only the names differ. With `coverage-verification` missing from the input, the row is

```json
{"check": "every_hunk_acknowledged", "subject": {"type": "round", "id": "round-1"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "coverage.attestation_data.hunks_acknowledged", "value": null, "locations": ["/trail/compliance_status/attestations_statuses"], "part": {"name": "coverage", "id": null}},
            {"name": "coverage.attestation_data.hunks_total", "value": null, "locations": ["/trail/compliance_status/attestations_statuses"], "part": {"name": "coverage", "id": null}}]}
```

and written out in full, its inputs are named `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_acknowledged` and `...hunks_total`, with the same `null`. The `expression` of a check and the names in its `inputs` and `failed_items` keep the alias, so a reader sees the words the policy was written in.

- A part is one line, a path, or an object with `from`, a path, and `identified_by`, a path read inside the part. The report shows it under [`parts`](#subjects-in-the-report), and tags each input read through the part with the id it leads to. A `count of` or `sum of` has the tag only when the list it counts or sums starts at the part: `count of items whose w is pa.w` counts the subject's `items`, so its number has no tag, while the entry for `pa.w`, which it reads, has.
- A path is written as in a [from line](#from-lines): keys joined by `.`, keys in quotes, positions, and `named by` a key of `$params` or `$input`. It is a path inside the subject, so it can't start at `$params` or `$input`, and it can't have `whose`, `count of` or `named by each of`.
- A part can be any path, even one that ends at a single value: `ratio: compliance_status.attestations_statuses.coverage.attestation_data.ratio` makes `ratio is at least 0.8` read the same.
- Keep the data's own names, as `findings` and `coverage` do, because a reader who knows the data finds `coverage.attestation_data.hunks_total` where they'd look for it.
- An alias is read wherever a bare first key reads the subject: in the subject's checks, in the assertions of a `for` line, and in the conditions of the subject's `from` line and of a subject that narrows it, where `.limit` reads the field instead. In a `whose` and after a one-line `every` or `some`, where a bare first key is a field of the item, it's read on the right side and never on the left of a `whose`, as a `for` line's name is: `every items.price is at most limit` reads the part `limit`, `whose limit is at least 4` reads the item's `limit`, and `.limit` on the right reads the item's. A term of a `plus` and the path of an elapsed time on the right read it the same way, so `whose lo is at least limit plus hi` reads the part `limit` and the item's `hi`. A `count of` or `sum of` is read the same way: in `every items.price whose n is count of limit.rows is 1` the right side counts the part's `limit.rows`, and in `count of items whose count of limit.rows is 1 is 3` the left side counts each item's own `limit.rows`. `named by` a part's alias is written wrong, with `named by coverage reads a part, which isn't supported yet`.
- An alias shadows a field of the subject with the same name. To read the field, put a dot in front: `.coverage` is the subject's field `coverage`, not the part.
- An alias is a bare word that isn't a word of the grammar, `params` or `input`, or it is written wrong with `invalid alias`. A part's alias named like a subject of the policy (its own, its parent or any other) is written wrong with `<alias> can't be an alias: it's a subject's name`, and one named like a part of a parent or grandparent subject, or like a part kept from a subject it narrows, with `<alias> can't be an alias: it's a part of <subject>`, which names the subject that declares the part and puts a name with a space in it in double quotes, like `"pull request"`. A name always means one thing, so nobody has to wonder whether it reads the subject or the alias. The problem is listed under the part, like `subjects.kid.has.x`.
- An alias of a `for` line can't be named like a subject, the check's own, a parent or any other in the policy, or like a part of the check's own subject, of a parent or grandparent subject, or of a subject they narrow. Either is written wrong, so that a name always means one thing and a bare name never reads the parent when the item lacks the field. The problem is under the check, as `<alias> can't be an alias: it's a subject's name` or `<alias> can't be an alias: it's a part of <subject>`, and both are listed when both apply. With this policy and this input:

  ```yaml
  subjects:
    b:
      from: bs
      identified_by: id
      has:
        cap: limit
    kid:
      from: b.kids
      identified_by: id
  requirements:
    r:
      subject: kid
      checks:
        c:
          for: every xs as b
          assert: b.v is 1
  ```

  ```json
  {"bs": [{"id": "b1", "limit": 2, "kids": [{"id": "k1", "xs": [{"v": 1}]}]}]}
  ```

  the `$well_formed` row fails with `{"name": "checks.c", "value": ["b can't be an alias: it's a subject's name"], "locations": []}`, and with `as cap` it fails with `["cap can't be an alias: it's a part of b"]`. A name that clashes with nothing, like `as entry`, reads the item.
- A subject that narrows another keeps its parts and can add its own. The report lists them all.
- A [child subject](#from-lines) reads its parent's parts through the parent's name, and its `from` line can start from one. With `{"params": {"artifact_name": "web"}}` and this input:

  ```json
  {"trail": {"artifacts": {"web": {"fingerprint": "sha-1", "attestations_statuses": {
    "pull-request": {"attestation_data": {"approvers": ["bob"], "pull_requests": [{"url": "pr/7"}, {"url": "pr/8"}]}}}}}}}
  ```

  this policy reads the pull requests of the attestation, and checks each of them against its approvers:

  ```yaml
  subjects:
    artifact:
      from: trail.artifacts named by $params.artifact_name
      identified_by: fingerprint
      has:
        pr_attestation: attestations_statuses.pull-request.attestation_data
    pull request:
      from: artifact.pr_attestation.pull_requests
      identified_by: url
  requirements:
    approved:
      subject: pull request
      checks:
        approved: artifact.pr_attestation.approvers is not empty
  ```

  ```json
  {"check": "approved", "subject": {"type": "pull request", "id": "pr/7", "in": {"artifact": "sha-1"}}, "passed": true, "cause": "satisfied",
   "inputs": [{"name": "artifact.pr_attestation.approvers", "value": ["bob"], "locations": ["/trail/artifacts/web/attestations_statuses/pull-request/attestation_data/approvers"], "part": {"name": "artifact.pr_attestation", "id": null}}]}
  ```

  A part is only reached through its subject, so a bare `pr_attestation` in a check of `pull request` is one of its own fields.
- A part that is written wrong fails `$well_formed` on every requirement that names the subject, with the problem under the part's alias, like `{"name": "subjects.round.has.coverage", "value": ["missing from"], "locations": []}`. That is a `has` that isn't an object (`not an object`), a part that isn't a string or an object (`not a string or an object`), an object without `from` (`missing from`), with a field other than `from` and `identified_by` (`unknown field <name>`), or with a `from` or `identified_by` that isn't a string (`invalid from`, `invalid identified_by`), and a path that can't be read (`from: a part is a path: whose and named by each of can't go in it`, `from: a part reads inside its subject, so it can't start at $params or $input`, or the problems a from line gives).
- The report lists every part under the subject's [`parts`](#subjects-in-the-report), including the ones it keeps from a subject it narrows.

## Requirements

```yaml
prod_deploy:
  description: Every production deployment is approved
  meta: {control: SDLC-CTRL-0007, frameworks: [SOC 2]}
  subject: deployment
  require: every
  min_subjects: 1
  checks:
    approved: approved_by is a non-empty string
```

| Field          | Meaning                                                                                                                               | Default   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `description`  | What the requirement asks for, in words anyone can read. It's copied into the report.                                                 | `""`      |
| `meta`         | Anything else you want to keep with the requirement, like a control id or an owner. It's copied into the report. Ergo never reads it. | `{}`      |
| `subject`      | The name of the [subject](#subjects) it checks.                                                                                       | required  |
| `require`      | `"every"`: every subject must pass every check. `"some"`: at least one subject must pass every check.                                 | `"every"` |
| `min_subjects` | How many subjects must be left after the subject's conditions for the requirement to be met, from 0 to 1,000,000.                     | `1`       |
| `checks`       | Named checks that each subject must pass.                                                                                             | required  |

A few details:

- `meta` can hold anything JSON can, like `{"control": "SDLC-CTRL-0007", "frameworks": ["SOC 2", "ISO 27001"], "version": 3, "reviewed": true}`. Its numbers follow the same rule as numbers anywhere else in a policy: one a 64-bit float can't hold, like `1e400`, makes the requirement [written wrong](#checks-ergo-adds). So does a key that isn't a string, or a set, which a policy written in Rego can hold but JSON can't. In the report, a number is written in its plain form, so `1.50`, `1e2` and `-0` come out as `1.5`, `100` and `0`, and the same `meta` gives the same report however it was written.
- `min_subjects` defaults to 1 so that a typo in `from` fails the requirement instead of quietly passing it. Set it to `0` when you mean "if there are any, they must pass; if there are none, that's fine". It means the same under `every` and `some`. When none are left, the requirement is [not applicable](#the-report). That only holds for a list that's there: a `from` that leads nowhere still fails, as above. A `from` that ends with `named by each of` is the exception, because each key is a subject even when `from` leads nowhere.
- Under `some`, one subject has to pass all the checks by itself. Two subjects that each pass half of them don't count.
- A requirement with no checks, a `require` other than `every` or `some`, a check that's [written wrong](#checks-ergo-adds), or a [subject that's written wrong](#subjects), is never met. The `$well_formed` row says so, and says [what's wrong](#checks-ergo-adds), like `{"name": "require", "value": ["neither every nor some"], "locations": []}`. That row is the requirement's only row: Ergo doesn't read its subjects, so it has no `$min_subjects`, `$unique_ids`, `$applies` or check rows, and its `subjects` counts are 0. Its entry in `requirements` still lists every check, the ones Ergo adds included, so the report shows what the policy wrote. Other requirements in the policy still get theirs.
- So is a requirement with a check named like one of Ergo's own rows, `$well_formed`, `$min_subjects`, `$unique_ids` or `$applies`, so no two rows share a check's name. The `$well_formed` row says `{"name": "checks.$applies", "value": ["name reserved"], "locations": []}`, and the requirement's entry in `requirements` lists Ergo's check of that name, not yours.
- So is a requirement without a `subject`, or whose `subject` isn't in `subjects`, like a typo for `deploymnt`. The `$well_formed` row says `{"name": "subject", "value": ["missing"], "locations": []}` or `{"name": "subject", "value": ["not in subjects"], "locations": []}`. If `subjects` itself isn't an object, every requirement that names a subject fails with `{"name": "subjects", "value": ["not an object"], "locations": []}`.
- So is a requirement with a field that isn't in the table above, like `from` or `requires`, because Ergo would otherwise ignore it and check something you didn't mean. `from` and `identified_by` belong to the [subject](#subjects). The `$well_formed` row lists each one in order and says what's wrong with it, the way it does for a [check that's written wrong](#checks-ergo-adds), like `{"name": "from", "value": ["unknown field"], "locations": []}`.
- So is a requirement that isn't an object, or whose `checks` isn't an object, whose `min_subjects` isn't a whole number from 0 to 1,000,000, whose `subject` isn't a string with something besides whitespace in it, since rows and descriptions name the subject by it, whose `description` isn't a string, or whose `meta` isn't an object. `null` counts as the wrong type, except for `description` and `meta`: Ergo only copies those, so a `null` one counts as not written, which is what YAML gives for an empty `description:`. `2.0` is a whole number, but `-1` and `0.5` aren't, and `1000001` is too big. It still has its entry in `requirements` and its `$well_formed` row, which shows each such field and what it should be, like `{"name": "checks", "value": ["not an object"], "locations": []}`, or the whole requirement and its value, like `{"name": "requirement", "value": 5, "locations": []}`.

### A requirement that only applies sometimes

Some controls only apply to some inputs, like "new features must be tested", which doesn't apply to a bug fix. Make the thing that decides it the subject, and keep it only when the control applies, with `whose`. This one reads a [param](#params):

```yaml
params:
  untested_change_types: [bug_fix, refactor]
subjects:
  deployment:
    from: $input whose deployment.change_type is not in $params.untested_change_types
requirements:
  features_tested:
    subject: deployment
    min_subjects: 0
    checks:
      tested: some test_runs.status exists
      passed: every test_runs.status is "passed"
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

The `$applies` row reads `{"name": "deployment.change_type", "value": "bug_fix", "locations": ["/deployment/change_type"]}`, and the `$applies` entry in `checks` records the list it was compared with, under `$refs`: `{"name": "$params.untested_change_types", "value": ["bug_fix", "refactor"], "locations": ["$params:/untested_change_types"]}`. A new feature with no test runs fails `tested` and `passed`, and so does a change type that isn't listed, like `hotfix`, so a new or misspelt type has to be tested until someone adds it to the list. A deployment with no `change_type` fails the requirement, because Ergo can't tell whether it applies.

The condition lists the types that don't need tests, rather than the ones that do. `deployment.change_type is "new_development"` would also work, but then any other type, misspelt ones included, would quietly skip the tests.

Don't make the test runs the subject instead, with `from: test_runs` and `min_subjects: 0`. That lets a new feature with no test runs pass, because there's nothing to check.

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
ergo_spec: v0.3
subjects:
  commit:
    from: commits
    identified_by: sha
requirements:
  reviewed:
    subject: commit
    checks:
      reviewed:
        description: Some pull request for the commit was approved
        assert: some pull_requests.approved_by is a non-empty string
```

| subject | check      | passed  | cause       |
| ------- | ---------- | ------- | ----------- |
| `a1`    | `reviewed` | `true`  | `satisfied` |
| `a2`    | `reviewed` | `false` | `value`     |

The requirement is `not_met`: `a2` has no pull request.

With the pull request as the subject, the same sentence turns into "some pull request was approved":

```yaml
ergo_spec: v0.3
subjects:
  pull request:
    from: commits[0].pull_requests
    identified_by: number
requirements:
  reviewed:
    subject: pull request
    require: some
    checks:
      approved:
        description: The pull request was approved
        assert: approved_by is a non-empty string
```

| subject | check      | passed  | cause       |
| ------- | ---------- | ------- | ----------- |
| `7`     | `approved` | `true`  | `satisfied` |
| `8`     | `approved` | `false` | `absent`    |

The requirement is `met`. Pull request 7 is approved, and `a2` is never looked at, because `from` reads one commit's pull requests. Same input, same words, opposite answers.

So before writing a check, decide:

- **What would the policy's owner list?** The report has one row per subject, so the subject is what it lists. A rule about commits should list commits, even when the evidence is organised by pull request.
- **What id would they cite?** The id that `identified_by` picks is how a row is found again, and how two reports are compared.
- **How many lists sit between the subject and the values compared?** `every` and `some` walk them all, but a check that compares fields at two levels needs a `for` line, which takes two lists at most. A check that needs more usually means the subject is one list too high, or the evidence was recorded at the wrong grain. Moving the subject down flattens the check, but then the report lists the smaller thing, as above.
- **Does `require` still say what the sentence says?** "Every commit has some approved pull request" is `every` over commits with `some` inside a check. With the pull request as the subject it becomes `some` over pull requests, which is only the same rule when there is one commit.

A policy can hold several requirements with different subjects over the same input, like a lockfile and each of its entries. Each requirement picks its own grain.

## Checks

A check is a sentence: one line of English. [spec/syntax.md](spec/syntax.md) has the full grammar. Write the sentence on its own, or under `assert` when the check has a `description` or `meta`:

```yaml
ergo_spec: v0.3
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  prod_deploy:
    subject: deployment
    checks:
      approver: approved_by is a non-empty string
      reviewed:
        description: The change was reviewed before it was deployed
        assert: reviewed_at is before deployed_at
      region: region is in $params.regions
      tickets: tickets contains all of 'OPS-1'
```

With the params `{"regions": ["eu-west-1"]}` and this input:

```json
{
  "deployments": [
    {"id": "d1", "approved_by": "ann", "reviewed_at": "2026-10-01T09:00:00Z", "deployed_at": "2026-10-01T10:00:00Z", "region": "eu-west-1", "tickets": ["OPS-1"]},
    {"id": "d2", "approved_by": "", "reviewed_at": "2026-10-02T11:00:00Z", "deployed_at": "2026-10-02T10:00:00Z", "region": "us-east-1", "tickets": []}
  ]
}
```

`d1` passes every check and `d2` fails every one. Each check's entry in the report has its `description`, `meta` and `expression`, and the `expression` is the sentence:

```json
"reviewed": {
  "description": "The change was reviewed before it was deployed",
  "expression": "reviewed_at is before deployed_at",
  "meta": {}
},
"tickets": {
  "description": "",
  "expression": "tickets contains all of \"OPS-1\"",
  "meta": {}
}
```

The report prints every sentence one way, so `'OPS-1'` shows as `"OPS-1"`, two spaces as one, `is equal to "a"` as `is "a"`, and `is` before a field as `equals`. The rows are the rows of the operator each sentence runs as, so `d2`'s `reviewed` row reads both fields:

```json
{
  "cause": "value",
  "check": "reviewed",
  "inputs": [
    {"locations": ["/deployments/1/reviewed_at"], "name": "reviewed_at", "value": "2026-10-02T11:00:00Z"},
    {"locations": ["/deployments/1/deployed_at"], "name": "deployed_at", "value": "2026-10-02T10:00:00Z"}
  ],
  "passed": false,
  "requirement": "prod_deploy",
  "subject": {"id": "d2", "type": "deployment"}
}
```

A sentence is a path, then a phrase, then what the phrase takes:

| Sentence                                                                             | Runs as                                                                  |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `env is "prod"`, also `equals` and `is equal to`                                     | `equals`                                                                 |
| `digest equals fingerprint`, a field on the right                                    | `compare` with `eq`                                                      |
| `cost is 2.5 within 0.01`, `cost equals total within 0.01`                           | `compare` with `eq` and `within`                                         |
| `env is not "prod"`, `author does not equal approver`                                | `compare` with `ne`, so two values of different types fail as `unusable` |
| `env is one of "dev", "test"`, `user is in $params.staff`                            | `in`                                                                     |
| `env is not one of "prod"`, `user is not in $params.bots`                            | `not_in`                                                                 |
| `ticket exists`, `ticket does not exist`                                             | `present`, `missing`                                                     |
| `approved_by is a non-empty string`                                                  | `non_empty_string`                                                       |
| `tags is a list`, `config is an object`                                              | `has_type`: `list`, `string`, `number`, `boolean` or `object`            |
| `findings is empty`, `tickets is not empty`                                          | `empty_string_or_list`, `not_empty_string_or_list`                       |
| `labels contains "bug"`, `labels does not contain "wip"`                             | `includes`, `excludes` with `value`                                      |
| `labels contains all of "a", "b"`, `labels contains none of ...`                     | `includes`, `excludes` with `values`                                     |
| `branch matches '^release/'`, `branch does not match ...`                            | `matches_any`, `not_matches_any`                                         |
| `branch starts with "release/"`, `file ends with suffix`                             | `compare` with `starts_with`, `ends_with`                                |
| `tested_by is in reviewers`, `files contains all of gap_files`                       | `compare` with `in`, `includes_all`, `matches_any`, ...                  |
| `score is at least 3`, `is at most`, `is more than`, `is less than`                  | `compare` with `gte`, `lte`, `gt`, `lt`, on numbers only                 |
| `name is alphabetically before "m"`, `is alphabetically after`                       | `compare` with `alphabetically_before`, `alphabetically_after`           |
| `score is between 1 and 5`                                                           | `range`                                                                  |
| `reviewed_at is before deployed_at`, `is after`, `is on or after`, `is on or before` | `compare_time` with `lt`, `gt`, `gte`, `lte`                             |

The time phrases can take a written time or number too, like `opened is before "2024-01-01T00:00:00Z"` or `opened is after 100`. The field and the written value must both be RFC 3339 times, both be dates like `"2026-10-01"`, or both be numbers, or the check fails as `unusable`. A date and an RFC 3339 time fail too, even one at midnight, because a date doesn't say in which time zone it starts. A written value that isn't a time, a date or a number, like `opened is before "yesterday"`, is written wrong, with `"is before" takes a time or a number`.

`within` works out the gap exactly on the decimals, so `0.3` and `0.1` are within `0.2`. That's promised for numbers with at most 15 significant digits. Longer ones, like `0.30000000000000004`, are compared on their digits too, but OPA can mix up two of them that differ only past those digits, so don't rely on it. The only numbers it can't compare are ones whose exponents, with the number after `within`, are more than 4096 apart, like `1e5000` and `1`. That check fails as `unusable`.

`is empty` passes on `""` or `[]` and `is not empty` on a string or a list with something in it. Anything else that's there, like a number or an object, fails both as `unusable`. Their operators only exist for sentences. `starts with` and `ends with` compare two strings: anything else, two numbers included, fails as `unusable`, and a written value after them that isn't text, like `x starts with 1`, is written wrong. `is alphabetically before` and `is alphabetically after` order two strings in the same way, code point by code point, so every uppercase letter comes first: `"Zoe"` is alphabetically before `"adam"`.

`is at least`, `is at most`, `is more than` and `is less than` only order numbers. Two strings fail as `unusable`, because a number held as a string would be ordered as text, and with this input:

```json
{"conditions": [{"metric": "coverage", "value": "9", "errorThreshold": "80"}]}
```

`every conditions.value is at least errorThreshold` would pass, since `"9"` comes after `"80"` as text. A written value that isn't a number, like `score is at least "3"`, is written wrong, with `"is at least" takes a number`.

`ergo.rego` compares numbers with OPA, and OPA can treat two decimals as the same when they only differ after the 15th significant digit. Whole numbers are always compared exactly. With this policy and this input:

```yaml
ergo_spec: v0.3
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

After `is in`, `is not in`, `contains`, `does not contain`, `contains all of`, `contains none of`, `matches` and `does not match`, the thing on the right can be a field too, read like the field after `is at least`: from the subject, from the name of a `for` line or from the item of a one-line `every` or `some` and a `whose`. With this policy and this input:

```yaml
ergo_spec: v0.3
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  prod_deploy:
    subject: deployment
    checks:
      reviewed_by_peer: tested_by is in reviewers
      tickets_covered: tickets contains all of required_tickets
```

```json
{
  "deployments": [
    {"id": "d1", "tested_by": "ann", "reviewers": ["ann", "bob"], "tickets": ["OPS-1", "OPS-2"], "required_tickets": ["OPS-1"]},
    {"id": "d2", "tested_by": "cy", "reviewers": ["ann", "bob"], "tickets": ["OPS-1"]}
  ]
}
```

`d1` passes both and `d2` fails both. Its `reviewed_by_peer` row fails as `value`, because `cy` isn't in the list, and its `tickets_covered` row fails as `absent`, because `required_tickets` is missing:

```json
{
  "cause": "absent",
  "check": "tickets_covered",
  "inputs": [
    {"locations": ["/deployments/1/tickets"], "name": "tickets", "value": ["OPS-1"]},
    {"locations": ["/deployments/1"], "name": "required_tickets", "value": null}
  ],
  "passed": false,
  "requirement": "prod_deploy",
  "subject": {"id": "d2", "type": "deployment"}
}
```

They run as `compare` with `in`, `not_in`, `includes`, `excludes`, `includes_all`, `excludes_all`, `matches_any` and `not_matches_any`, and only sentences can use those. The row has the same `passed` and `cause` as the sentence with `$params.required_tickets` holding that field's value, and the field is in the row's `inputs` after the left side instead of in `$refs`. A field on the right that's missing or `null` fails the row as `absent` or `null`, whatever the left side is. One that can't be used fails it as `unusable`: not a list after `is in`, `is not in`, `contains all of`, `contains none of`, `matches` and `does not match`, an empty list after `contains all of` and `contains none of`, and patterns that aren't all valid regular expressions. Only when the right side can be used does the left side's own cause count.

The thing on the right is a value when it's in quotes, a number, `true`, `false` or `null`, and a field otherwise. A list of values is separated by `, `. A string can be in single quotes, which keep backslashes as written, so `'^\s*FROM'` needs no doubled backslash.

A path is keys joined by `.`, like `build.commit.sha`. A key with anything but letters, digits, `_` and `-` goes in double quotes, like `labels."app.kubernetes.io/name"`. `$params.regions` reads the params and `$input.repo` the input. `artifacts named by $params.name` reads the key the param holds, and so does `artifacts[$params.name]`. `named by` a bare field reads the key the subject holds, as below. `item 2 of commits`, `first of commits` and `commits[1]` read one item of a list. A position above 9007199254740991, the largest whole number a 64-bit float holds exactly, is written wrong, with `9007199254740992 can't be a list position`, and one read from a param, like `commits[$params.n]`, fails the check as `unusable`. A path can't start with a word the sentences use, like `empty`, `count`, `true` or `it`. Put a dot in front, `.empty is 1`, to read a field with that name. `it` is the [subject itself](#the-subject-itself), so a field called `it` is `.it`.

`named by` a bare field picks the key from the subject, so a limit can depend on a field like the severity. With the params `{"max_days": {"critical": 1, "high": 5}}`, this policy:

```yaml
ergo_spec: v0.3
subjects:
  vuln:
    from: vulns
    identified_by: id
requirements:
  fixed_in_time:
    subject: vuln
    checks:
      within_limit: age_days is less than $params.max_days named by severity
```

and this input:

```json
{"vulns": [
  {"id": "v-1", "severity": "high", "age_days": 3},
  {"id": "v-2", "severity": "critical", "age_days": 2},
  {"id": "v-3", "severity": "unknown", "age_days": 0}
]}
```

`v-1` passes, `v-2` fails as `value`, and `v-3` fails as `absent`, because the params have no limit for `unknown`. Each row shows the field that picked the key after the check's own inputs:

```json
{"check": "within_limit", "subject": {"id": "v-2", "type": "vuln"}, "passed": false, "cause": "value",
 "inputs": [
   {"name": "age_days", "value": 2, "locations": ["/vulns/1/age_days"]},
   {"name": "$params.max_days named by severity", "value": 1, "locations": ["$params:/max_days/critical"]},
   {"name": "severity", "value": "critical", "locations": ["/vulns/1/severity"]}
 ]}
```

A field that's missing fails the check as `absent`, a `null` one as `null`, and one that isn't a string, a number included, as `unusable`. A name from a [`for` line](#checks) hides a field with the same name. Inside a `whose`, and in the phrase of a one-line `every` or `some`, the field is the item's, as a bare key is there. A `from` line and `identified_by` can't use it, because they don't have a subject yet.

In YAML, ` #` starts a comment, so `title does not match 'WIP' #, 'DRAFT'` loses everything after `'WIP'`. YAML also won't take a plain value that starts with a quote, or that has `: ` in it. Put the whole sentence in single quotes then, doubling any single quote inside: `'"$schema" exists'`.

A check can hold more than one sentence, joined with `and` on one line or listed under `assert`. Both mean the same, and every sentence has to pass. With the input above:

```yaml
reviewed:
  description: Someone approved and reviewed it before it was deployed
  assert:
    - approved_by is not empty
    - reviewed_at is before deployed_at
```

The check's `expression` is `approved_by is not empty and reviewed_at is before deployed_at`, and it still has one row per deployment. That row reads every field the sentences read, and says which sentences failed, each with its own cause:

```json
{
  "cause": "value",
  "check": "reviewed",
  "failed_assertions": [
    {"assertion": "approved_by is not empty", "cause": "value"},
    {"assertion": "reviewed_at is before deployed_at", "cause": "value"}
  ],
  "inputs": [
    {"locations": ["/deployments/1/approved_by"], "name": "approved_by", "value": ""},
    {"locations": ["/deployments/1/deployed_at"], "name": "deployed_at", "value": "2026-10-02T10:00:00Z"},
    {"locations": ["/deployments/1/reviewed_at"], "name": "reviewed_at", "value": "2026-10-02T11:00:00Z"}
  ],
  "passed": false,
  "requirement": "prod_deploy",
  "subject": {"id": "d2", "type": "deployment"}
}
```

`failed_assertions` is `[]` when the check passes. The row's cause is the first, in the order of [causes](#causes), among the sentences that failed. To get a row for each sentence, write them as separate checks. A problem with one line of a list starts with its number in the `$well_formed` row, like `line 2: unclosed quote at column 6`.

A sentence has no `or`. When a check can pass in more than one way, write the ways as named options under `any_of`, each one sentence or a list of them. The check passes when every sentence of one option passes. With this input:

```json
{"components": [
  {"name": "click", "licenses": [{"license": {"id": "BSD-3-Clause"}}]},
  {"name": "prometheus-client"},
  {"name": "leftpad", "licenses": [{"license": {"id": "WTFPL"}}]}
]}
```

and these params:

```json
{"allowed_licenses": ["BSD-3-Clause", "Apache-2.0"], "known_package_licenses": {"prometheus-client": "Apache-2.0"}}
```

this check, on a subject `component` with `from: components`, takes the licence the SBOM declares, or else the one the params give for the component's name:

```yaml
licence_allowed:
  description: The licence is allowed
  any_of:
    declared: some licenses.license.id is in $params.allowed_licenses
    known:
      - licenses does not exist
      - $params.known_package_licenses named by name is in $params.allowed_licenses
```

click passes on `declared` and prometheus-client on `known`. leftpad fails both, and its row is:

```json
{
  "cause": "absent",
  "check": "licence_allowed",
  "inputs": [
    {"locations": ["$params:/known_package_licenses"], "name": "$params.known_package_licenses named by name", "value": null},
    {"locations": ["/components/2/licenses"], "name": "licenses", "value": [{"license": {"id": "WTFPL"}}]},
    {"locations": ["/components/2/licenses/0/license/id"], "name": "licenses[].license.id", "value": ["WTFPL"]},
    {"locations": ["/components/2/name"], "name": "name", "value": "leftpad"}
  ],
  "passed": false,
  "requirement": "licences",
  "subject": {"id": "leftpad", "type": "component"}
}
```

The row reads every field the options read, once each. Its cause is the first, in the order of [causes](#causes), among the options, and an option's cause is the first among its sentences. Here `known` fails as `absent`, because the params have no licence for leftpad. An option with an `exists` sentence whose field is missing fails as `value` instead. The row has no `failed_assertions`. The check's `expression` is `one of: declared(some licenses.license.id is in $params.allowed_licenses) | known(licenses does not exist and $params.known_package_licenses named by name is in $params.allowed_licenses)`, with the options sorted by name.

An `any_of` takes `description` and `meta`, but not `for` or `assert`. An `any_of` that isn't an object, an empty one, an empty option, or an option that isn't a sentence or a list of them is written wrong, with `invalid any_of`, `empty any_of`, `empty option <name>` or `invalid option <name>`. A problem with a sentence starts with its option's name, and with the line's number when the option has more than one, like `option known: line 2: doesn't parse` or `option fast: values of mixed types`.

`every` and `some` check each item of the lists along a path. `every pull_requests.commits.signed is true` walks the pull requests, then the commits of each, and checks each commit's `signed`. It passes when every one does. `some` passes when at least one does. With this input:

```json
{"releases": [{"id": "r-1", "pull_requests": [
  {"number": 7, "author": "ann", "approvers": [{"username": "bob", "state": "APPROVED"}], "commits": [{"sha": "a1", "signed": true}, {"sha": "a2", "signed": false}]},
  {"number": 8, "author": "bob", "approvers": [{"username": "bob", "state": "COMMENTED"}]}
]}]}
```

`signed: every pull_requests.commits.signed is true` gives:

```json
{
  "cause": "absent",
  "check": "signed",
  "failed_items": [
    {"cause": "value", "item": "item 2 of pull_requests[0].commits", "locations": ["/releases/0/pull_requests/0/commits/1/signed"], "path": "pull_requests[0].commits[1].signed", "value": false},
    {"cause": "absent", "item": "pull_requests[1].commits", "locations": ["/releases/0/pull_requests/1"], "path": "pull_requests[1].commits", "value": null}
  ],
  "inputs": [{"locations": ["/releases/0/pull_requests/0/commits/0/signed", "/releases/0/pull_requests/0/commits/1/signed"], "name": "pull_requests[].commits[].signed", "value": [true, false]}],
  "passed": false,
  "requirement": "release",
  "subject": {"id": "r-1", "type": "release"}
}
```

- `inputs` names the path with `[]` after each list walked, and holds the value each item's path ended at.
- Each entry in `failed_items` gives the field that failed as `path`, and the item it belongs to as `item`, so a tool can show the item by reading the input there. A list that's missing, `null`, not a list or empty is listed in its items' place. When a `whose` that compares two fields can't decide for an item, the entry names the field it couldn't read, or the left one when it read neither or both, like `hi` for `whose lo is at least hi` on `{"lo": 1}`, with `value` `null`. A field that's `null` counts as not read, and so does the list of a `count of` that isn't a list.
- An empty list fails `every` as `value`, because no commits isn't proof that every commit is signed. Write `, if any,` after the path to let empty lists pass: `every review.incidents, if any, is not empty`. A missing list still fails.
- `whose` keeps the items that pass its conditions, read on each item: `some pull_requests.approvers whose state is "APPROVED" exists` passes above, with `bob`'s approval. An item a condition can't decide, because the field it reads is missing, fails the check rather than being left out.
- In a one-line `every` or `some`, a field on the right of the phrase is the item's too, so `some approvers.timestamp whose state is "APPROVED" is after last_commit` reads both from each approver. To compare with a field of the subject, use a `for` line, below. A `for` alias is read on the right of a `whose` too, `count of` and `sum of` included, so with `for: every groups as g`, `count of rows whose n is count of g is 1` counts the group `g`, and `.g` reads each row's own `g`. A child subject's parent works the same way: with the parent `fam`, `count of rows whose n is count of fam.z is 1` counts the parent's `z`, `count of rows whose count of fam.z is 1 is 3` counts each row's own `fam.z`, and `.fam.z` on the right reads the row's. A parent whose `z` is missing, `null` or not a list fails the check as `absent`, `null` or `unusable`.
- `every`, `some`, `count of` and `sum of` paths can be ten steps long, wherever they stand, on the right of a phrase too. A `for` alias and a position like `first of` each count as a step, and `$input` and `$params` don't. A walk that starts at a part counts the part's own path instead of its alias, so with `has: {"x": "k1.k2.k3.k4.k5.k6.k7.k8.k9"}`, `every x.z is 1` is ten steps, and a part of ten names makes it eleven. A part read without a walk, like `x.z is 1`, has no limit. An item picked on a `for` line, like `first of reviews as review`, takes ten names, not counting its position ([sentence.walk.steps](spec/syntax.md#every-some-and-whose)).
- `contains` and the other list phrases can't follow `every` or `some`, because the last list is walked too, so `every pull_requests.labels does not contain "hotfix"` would ask each label. It's written wrong, and the message says to put the walk on a `for` line.

A `for` line names the items of one or two lists, so the sentences under `assert` can read an item and the subject together. Each item is `every` or `some`, a path, an optional `whose`, and `as` an alias, or picks one item by its position, as below. The second item can walk a list inside the first, by its alias.

An alias is a short word that stands for something longer: `as pr` makes `pr` an alias for each pull request in turn. With the input above:

```yaml
peer_approved:
  description: Someone other than the author approved every pull request
  for: every pull_requests as pr, some pr.approvers as approver
  assert:
    - approver.state is "APPROVED"
    - approver.username does not equal pr.author
```

reads "for every pull request, some approver approved it and isn't its author". Both sentences have to hold for the same approver. The check's `expression` is `for every pull_requests as pr, some pr.approvers as approver: approver.state is "APPROVED" and approver.username does not equal pr.author`, and it gives:

```json
{
  "cause": "value",
  "check": "peer_approved",
  "failed_items": [
    {
      "cause": "value",
      "failed_assertions": [
        {"assertion": "approver.state is \"APPROVED\"", "cause": "value", "items": [
          {"cause": "value", "inputs": [{"locations": ["/releases/0/pull_requests/1/approvers/0/state"], "name": "approver.state", "value": "COMMENTED"}], "item": "item 1 of pr.approvers"}
        ]},
        {"assertion": "approver.username does not equal pr.author", "cause": "value", "items": [
          {"cause": "value", "inputs": [
            {"locations": ["/releases/0/pull_requests/1/approvers/0/username"], "name": "approver.username", "value": "bob"},
            {"locations": ["/releases/0/pull_requests/1/author"], "name": "pr.author", "value": "bob"}
          ], "item": "item 1 of pr.approvers"}
        ]}
      ],
      "item": "item 2 of pull_requests",
      "locations": ["/releases/0/pull_requests/1"],
      "path": "item 2 of pull_requests",
      "value": {"approvers": [{"state": "COMMENTED", "username": "bob"}], "author": "bob", "number": 8}
    }
  ],
  "inputs": [
    {"locations": ["/releases/0/pull_requests/0/approvers/0", "/releases/0/pull_requests/1/approvers/0"], "name": "pr.approvers[]", "value": [{"state": "APPROVED", "username": "bob"}, {"state": "COMMENTED", "username": "bob"}]},
    {"locations": ["/releases/0/pull_requests/0", "/releases/0/pull_requests/1"], "name": "pull_requests[]", "value": [
      {"approvers": [{"state": "APPROVED", "username": "bob"}], "author": "ann", "commits": [{"sha": "a1", "signed": true}, {"sha": "a2", "signed": false}], "number": 7},
      {"approvers": [{"state": "COMMENTED", "username": "bob"}], "author": "bob", "number": 8}
    ]}
  ],
  "passed": false,
  "requirement": "release",
  "subject": {"id": "r-1", "type": "release"}
}
```

- `failed_items` lists the items of the first list that failed, each with what its alias stands for as its `value`. Each one has `failed_assertions`: the sentences that failed for it, each with its cause. With two items, a sentence that failed for several items of the second list has the first of their causes in the order of [causes](#causes). Pull request 8 failed because its one approver commented, and is its author.
- With two items, a failed sentence that reads the second item's alias also has `items`: the items of the second list it failed for, in list order, each with the cause it failed with. Here `item 1 of pr.approvers` is pull request 8's first approver. With `for: some approvers as approver, every commits as commit`, an approver who approved before the last commit fails `approver.timestamp is after commit.timestamp` with `"items": [{"cause": "value", "inputs": [...], "item": "item 2 of commits"}]`, so you can see which commit came later. Each item has its own cause: a commit with no `timestamp` would be listed there with `"cause": "absent"`. A sentence that doesn't read `commit`, like `approver.username does not equal author`, has no `items`, because it fails the same way for every commit.
- Each failed sentence has `inputs`, the values it compared, so a tool can show "1792655359 is not after 1792656245" without reading the sentence. They are the entries the sentence would have in the `inputs` of a row of its own, with the names as the sentence writes them and where each value was read in `locations`, see [where a value was read](#where-a-value-was-read). An entry of `items` has the inputs for that pair of items. A sentence with no `items` has them on the sentence, as the sentence read them on the item of the first list it belongs to. They keep the order the sentence reads them, its left side and then its right side, and a value it reads twice is listed once. Above, the second sentence read `approver.username` and `pr.author`, both for pull request 8. Every failed sentence has them, however many items fail, so a report where many items fail is longer. A read that stops early, like a commit with no `timestamp`, shows `"value": null` and the location where it stopped, and a `count of` on an empty list gives the count `0`, the list `[]` and no locations. With this input:

  ```json
  {"pr": {"author": "ann",
    "approvers": [{"state": "APPROVED", "timestamp": 1792655359, "username": "bob"}, {"state": "APPROVED", "timestamp": 1792655761, "username": "cat"}],
    "commits": [{"sha": "a1", "timestamp": 1792590878}, {"sha": "a2", "timestamp": 1792656245}]}}
  ```

  and `for: some approvers as approver, every commits as commit` with `approver.timestamp is after commit.timestamp`, the first entry of `failed_items` is:

  ```json
  {"cause": "value", "failed_assertions": [
    {"assertion": "approver.timestamp is after commit.timestamp", "cause": "value", "items": [
      {"cause": "value", "inputs": [
        {"locations": ["/pr/approvers/0/timestamp"], "name": "approver.timestamp", "value": 1792655359},
        {"locations": ["/pr/commits/1/timestamp"], "name": "commit.timestamp", "value": 1792656245}
      ], "item": "item 2 of commits"}
    ]}
  ], "item": "item 1 of approvers", "locations": ["/pr/approvers/0"], "path": "item 1 of approvers", "value": {"state": "APPROVED", "timestamp": 1792655359, "username": "bob"}}
  ```

  A sentence that works out a number, like `count of commit.files is at least 1`, has the number and then the list it counted, with the locations of that list. A part's input has its `part`. Only the sentences of a `for` line have them: the `failed_assertions` of a check with several sentences and no `for` line have none, because its row's `inputs` already hold the values.
- `failed_assertions` is `[]` when no sentence was checked, like when `whose` leaves no approver, or a field a `whose` reads is missing.
- When the second item failed before any sentence was checked, the item of the first list has its own `failed_items`, saying where. With `for: some approvers as approver, every commits whose author does not equal approver.username as commit` and a commit with no `author`, `{"t": 2}`, the approver's entry has `"failed_assertions": []` and:

  ```json
  "failed_items": [{"cause": "absent", "item": "item 2 of commits", "locations": ["/releases/0/commits/1"], "path": "item 2 of commits", "value": {"t": 2}}]
  ```

  What fails the same way for every approver is listed once in the row's `failed_items` instead, in place of the approvers that failed only because of it. That's a missing `commits` list, `{"cause": "absent", "failed_assertions": [], "item": "commits", "locations": ["/releases/0"], "path": "commits", "value": null}`, or a commit that `whose kind is "code"` can't decide, because that `whose` doesn't read `approver`. An approver that's still listed has the cause of what's left under it. A list inside the first, like `pr.approvers`, is listed under each pull request, because each has its own.
- `inputs` holds each list the `for` line walked, with its items, and every field of the subject or of a parent the sentences read, like `t.x`. A second list that starts at the first item's alias, like `z.subs` in `every items whose k is 1 as z, every z.subs as y`, shows only the items under the first items that `whose` kept. The first list still shows every item, the ones `whose` left out too. A field read through a `for` alias, like `pr.author`, isn't listed on its own.
- In `assert`, a bare first key is the subject's field, and a name reaches its item. Inside an item's own `whose`, a bare key is that item's field. A name hides a field with the same name, the subject's or an item's, except on the left side of a `whose`: `whose env is "prod"` always reads the item's `env`, and so does `whose count of env is 2`. Write a dot in front to read the field a name hides: `.env`.
- Each list fails as a one-line `every` or `some` does: empty, missing, `null` or not a list, and `, if any,` lets an empty one pass.
- Two items at most.
- `named by` an alias from the `for` line reads the key its item holds. With `for: every personas_dispatched as persona`, `persona_blob_shas named by persona exists` reads `persona_blob_shas.security`, then `persona_blob_shas.style`, and so on. An item that's `null` fails as `null`, and any other item that isn't a string, a number included, as `unusable`, since it can't be a key. The row's inputs show `persona_blob_shas` itself.

With `for: some approvals.approver as approver`, where a commit also has an `approver` field:

| sentence                                         | compares                                         |
| ------------------------------------------------ | ------------------------------------------------ |
| `every commits.author does not equal approver`   | each commit's `author` with the name `approver`  |
| `every commits.author does not equal .approver`  | each commit's `author` with its own `approver`   |
| `.approver equals approver`                      | the subject's `approver` with the name           |

A `for` item can start with a position instead of `every` or `some`, and then its alias stands for that one item: `first of commits`, `item 2 of commits`, `last of commits`, or `item 2 from last of commits`. Positions count from 1. An index in brackets doesn't pick, so `commits[0] as c` is written wrong, with `for: an item starts with "every", "some" or a position, like "last of"`: write `first of commits as c`. Brackets after `every` or `some`, like `every commits[0].files as f`, are fine. Add `sorted by` and a field of each item to count in the order of that field rather than the order of the list. With this input:

```json
{"pull_requests": [{"number": 7,
  "approvers": [{"username": "ada"}],
  "commits": [
    {"sha": "a1", "author_username": "ada",   "timestamp": 1760000200},
    {"sha": "a2", "author_username": "grace", "timestamp": 1760000100}
  ]}]}
```

```yaml
not_last_author:
  description: The approver didn't push the last commit
  for: last of commits sorted by timestamp as last_commit, some approvers as approver
  assert: approver.username does not equal last_commit.author_username
```

picks `a1`, the commit with the latest `timestamp`, wherever it is in the list, and gives:

```json
{
  "cause": "value",
  "check": "not_last_author",
  "failed_items": [
    {
      "cause": "value",
      "failed_assertions": [
        {"assertion": "approver.username does not equal last_commit.author_username", "cause": "value", "items": [
          {"cause": "value", "inputs": [
            {"locations": ["/pull_requests/0/approvers/0/username"], "name": "approver.username", "value": "ada"},
            {"locations": ["/pull_requests/0/commits/0/author_username"], "name": "last_commit.author_username", "value": "ada"}
          ], "item": "item 1 of approvers"}
        ]}
      ],
      "item": "item 1 of commits",
      "locations": ["/pull_requests/0/commits/0"],
      "path": "item 1 of commits",
      "value": {"author_username": "ada", "sha": "a1", "timestamp": 1760000200}
    }
  ],
  "inputs": [
    {"locations": ["/pull_requests/0/approvers/0"], "name": "approvers[]", "value": [{"username": "ada"}]},
    {"locations": ["/pull_requests/0/commits/0"], "name": "item 1 of commits", "value": {"author_username": "ada", "sha": "a1", "timestamp": 1760000200}}
  ],
  "passed": false,
  "requirement": "review",
  "subject": {"id": 7, "type": "pull_request"}
}
```

- The `expression` says how the item was picked, `for last of commits sorted by timestamp as last_commit, …`, and `inputs` says which item that was in the input, `item 1 of commits`.
- `first of commits sorted by timestamp` is the earliest, `last of` the latest, and `item 2 from last of` the second latest.
- A `whose` goes before `sorted by`, and keeps the items to sort: `last of approvers whose state is "APPROVED" sorted by timestamp as approval` is the latest approval. An item the `whose` can't decide fails the check with its cause.
- `sorted by` sorts numbers, and [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) times by the moment they name, so `2026-10-02T01:00:00+02:00` comes before `2026-10-02T00:00:00Z`. Dates like `2026-10-02` are sorted by day. An item whose field is missing, `null` or anything else fails the check as `absent`, `null` or `unusable`, without picking, since the order can't be known. When the fields mix numbers, times and dates, the numbers are kept and the rest fail as `unusable`, and with times and dates the dates fail.
- `sorted by name alphabetically` sorts strings instead, code point by code point, so `"Zoe"` comes before `"adam"`. Every field has to be a string. There's no word for the reverse order: `last of` and `item 2 from last of` count from the end.
- When another item has the same value as the one picked, nothing is picked and the check fails as `ambiguous`, listing the items that tie. With both commits at `1760000200` above, `failed_items` holds `item 1 of commits` and `item 2 of commits`, each with the `timestamp` as `value`. A tie elsewhere in the list doesn't matter.
- A position past the end of the list, or an empty list, fails as `absent`.
- `sorted by` reads a field of the item, so it can't start with `$params` or `$input`. A field with the same name as a name from the `for` line needs a dot in front, `sorted by .c`. It can't go after `every` or `some`, and `, if any,` can't go with a position.
- A picked second item can read the first item's name in its `whose`, and is picked again for each item of the first list: `for: every xs as p, first of ys whose k is p.k as q` gives each `p` the first `y` with the same `k`. `inputs` lists each item picked, like `item 2 of ys`. A first item for which nothing is picked isn't listed in `failed_items`, and a `ys` that can't be walked is listed once.
- A field of the picked item is read through its name, `last_commit.author_username`. In a sentence, `last of commits.author_username` would be the last of a list at `commits.author_username`.

`count of`, `sum of` and `plus` work out a number to compare. With this input:

```json
{"reviews": [{"id": "pr-7", "personas_ran": ["security"], "findings": [{"source": "claude"}, {"source": "gpt"}, {"source": "claude"}], "claude_found": 2, "stages": [{"kind": "model", "usd": 0.5}, {"kind": "model", "usd": 0.25}, {"kind": "tool", "usd": 0}], "total_usd": 0.76}]}
```

and these checks on a `review` subject read from `reviews`:

```yaml
some_persona: count of personas_ran is at least 1
claude_findings: count of findings whose source is "claude" equals claude_found
costs_add_up: sum of stages.usd whose kind is "model" equals total_usd within 0.01
all_findings: count of findings equals claude_found plus 1
```

all four pass. Each row shows the number Ergo worked out, named after the words that asked for it as the report prints them, then the list it walked:

| check             | inputs                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------- |
| `some_persona`    | `count of personas_ran = 1`, `personas_ran[] = ["security"]`                                          |
| `claude_findings` | `count of findings whose source is "claude" = 2`, `findings[] = [...]`, `claude_found = 2`            |
| `costs_add_up`    | `sum of stages.usd whose kind is "model" = 0.75`, `stages[].usd = [0.5, 0.25, 0]`, `total_usd = 0.76` |
| `all_findings`    | `count of findings = 3`, `findings[] = [...]`, `claude_found plus 1 = 3`, `claude_found = 2`          |

Each entry also has `locations`. A number Ergo worked out lists where what it came from was read: `count of findings = 3` lists the three findings it walked, `sum of stages.usd whose kind is "model" = 0.75` the `usd` of each of the three stages, and `claude_found plus 1 = 3` lists `/reviews/0/claude_found`.

- `count of` walks every list along its path, as `every` does, so `count of pull_requests.commits` counts the commits of every pull request. An empty list adds nothing, so `count of approvers` is 0 when there are none.
- A list that's missing, `null` or not a list fails the check as `absent`, `null` or `unusable`, and so does a number to add that's missing, `null` or isn't a number.
- An item that `whose` can't decide about fails the check with the `whose`'s own cause, as with `every`, and the rest of its path isn't read: `sum of items.x whose k is "a"` on an item with `k: null` fails as `null`, whatever its `x` holds.
- `whose` goes after the last `count of` or `sum of`, and only on the left: `claude_found plus count of findings whose source is "gpt" is at least 3`.
- A row shows each input once, so `count of approvals plus count of approvals is 4` lists `count of approvals` and `approvals[]` one time each.
- Numbers are added as decimals, so `0.1` plus `0.2` is `0.3`. Take every number added, a count or a sum included, and the result, and let p be the most decimal places any of them has, counted on the value: `1.50` has 1, `1e2` has 0 and `1e-7` has 7. p has to be at most 15, and each of them times 10^p has to be a whole number below 10^15, or the check fails as `unusable` and the number is `null`. So the sum has to fit in 15 digits at one scale. That's stricter than 15 significant digits for big round numbers, because `1e20` plus `1e20` fails too. Every runtime can decide it exactly, so every runtime gives the same answer.

With `x plus y is at most 1` on `{"x": 0.1, "y": 0.2}`, the row is satisfied:

```json
{"check": "sum", "passed": true, "cause": "satisfied", "inputs": [
  {"name": "x plus y", "value": 0.3, "locations": ["/things/0/x", "/things/0/y"]},
  {"name": "x", "value": 0.1, "locations": ["/things/0/x"]},
  {"name": "y", "value": 0.2, "locations": ["/things/0/y"]}
]}
```

With `{"x": 0.123456789012345, "y": 100}`, the sum needs 18 digits at one scale, so the row fails as `unusable` and `x plus y` is `null`:

```json
{"check": "sum", "passed": false, "cause": "unusable", "inputs": [
  {"name": "x plus y", "value": null, "locations": ["/things/0/x", "/things/0/y"]},
  {"name": "x", "value": 0.123456789012345, "locations": ["/things/0/x"]},
  {"name": "y", "value": 100, "locations": ["/things/0/y"]}
]}
```

`sum of xs is at most 1` on `{"xs": [1e20]}` fails as `unusable` too, with `sum of xs` as `null` and `xs[]` as `[100000000000000000000]`. A sum of `[0.1, 0.2, 100]` is `100.3`, and `1.50` plus `1` is `2.5`, trailing zeros or not.
- A count goes with `is`, `equals`, `is not`, `does not equal`, `is at least`, `is at most`, `is more than`, `is less than` and `within`.

`seconds`, `minutes`, `hours`, `days` and `weeks` followed by `elapsed from` and two paths, like `days elapsed from first_seen_ts to now_ts`, work out the time between two fields. Take a requirement on `vulnerabilities`, with the policy's params `{"max_days": {"high": 7, "low": 30}}` and this input:

```json
{"vulnerabilities": [
  {"id": "CVE-1", "severity": "high", "first_seen_ts": "2026-10-01T00:00:00Z", "now_ts": "2026-10-04T12:00:00Z"},
  {"id": "CVE-2", "severity": "low", "first_seen_ts": "2026-08-01T00:00:00Z", "now_ts": "2026-10-04T12:00:00Z"}
]}
```

```yaml
fixed_in_time: days elapsed from first_seen_ts to now_ts is less than $params.max_days named by severity
```

`CVE-1` passes, with 3.5 days against a limit of 7. `CVE-2` fails as `value`, with 64.5 days against 30, and its row's `inputs` are:

```json
[
  {"name": "days elapsed from first_seen_ts to now_ts", "value": 64.5, "locations": ["/vulnerabilities/1/first_seen_ts", "/vulnerabilities/1/now_ts"]},
  {"name": "first_seen_ts", "value": "2026-08-01T00:00:00Z", "locations": ["/vulnerabilities/1/first_seen_ts"]},
  {"name": "now_ts", "value": "2026-10-04T12:00:00Z", "locations": ["/vulnerabilities/1/now_ts"]},
  {"name": "$params.max_days named by severity", "value": 30, "locations": ["$params:/max_days/low"]},
  {"name": "severity", "value": "low", "locations": ["/vulnerabilities/1/severity"]}
]
```

- A unit is a fixed length: a second, 60 seconds, 3600, 86400 and 604800. The result is rounded down to 6 decimal places, so 36 hours is `1.5` days and one second is `0.000011` days. That way every runtime gives the same number. There's no `months` or `years`, because they have no fixed length.
- Both fields must be RFC 3339 times, like `2026-10-01T00:00:00Z` (a capital `T` and `Z`, a real date, a year from 1678 to 2261), both dates, like `2026-10-01`, which are whole days apart, or both numbers, which are read as seconds, to the nearest microsecond. A number must be between -9000000000 and 9000000000, about the years 1684 to 2255, so a time in milliseconds fails as `unusable` instead of being read as seconds. A missing field fails the check as `absent`, a `null` one as `null`, and anything else, including one time and one number, as `unusable`.
- When the second time is before the first, the check fails as `value`, and the number in its first input is `null`.
- It goes where a count goes: at the start of a sentence with the phrases a count goes with, as a term of `plus` and on the right side of a phrase, where `is` prints as `equals`, as it does before a count. It also goes in the `whose` of a `count of`, a `sum of` or an `every`, where an item whose end is before its start is left out. `every`, `some` and a `from` line are written wrong with `isn't supported yet`. It works in each line under `assert`, and under a `for` line, where a path can start at a name, like `days elapsed from pr.opened_ts to pr.merged_ts is at most 2`.
- `seconds`, `minutes`, `hours`, `days`, `weeks` and `to` are words of the grammar, so a field with one of those names is written `.days`.

A sentence that can't be read is [written wrong](#checks-ergo-adds), and the `$well_formed` row says why, with the column when it can:

```json
{"name": "checks.prod", "value": ["unclosed quote at column 16"], "locations": []}
```

for `prod: environment is "prod`. `x is not null` is written wrong too, because it could only fail: write `x exists`. So is a value that isn't a number before `within`, like `x is "a" within 1`. A sentence that compares a path with itself, like `x is at least x`, is written wrong too, because it could only pass or only fail. That happens most often in a `whose`, or after `every` or `some`, where a bare name is the item's: `every conditions.type equals type` compares each condition's `type` with itself. To compare an item with the subject, use a [`for` line](#checks) and put the comparison under `assert`. An object with `op`, the old way of writing a check, has no `assert` and is [written wrong](#policies-written-before-01).

Ergo doesn't run every sentence the spec describes yet. These are written wrong for now, with `isn't supported yet` in the `$well_formed` row: `last of` and `item <n> from last of` anywhere but at the start of a `for` item, a `sum of` or a `plus` in the `whose` of a `count of` or a `sum of`, a `plus` in the phrase of an `every` or `some`, and an elapsed time after `every` or `some` or in a `from` line. So `last_signed: last of commits.signed is true` gives:

```json
{"name": "checks.last_signed", "value": ["last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""], "locations": []}
```

Pick the item on a `for` line instead, as the message says.

In a `from` line or an `identified_by`, `named by` a bare word is written wrong too, with `unknown name <word>`, because there's no subject to read it from yet.

Any other `$<word>`, like `$foo`, is written wrong with `unknown name $foo`, in a sentence, a `for` line, a `from` line or the `identified_by` of a part. A subject's `identified_by` is only a path, so `$foo` there says `identified_by is a path, like "id" or "build.number"`. The line is still read by its grammar first, so a syntax error in it is the problem you get, with `doesn't parse` or its own message, and an unknown name never hides it.

### The subject itself

A list of plain values, like ids, regions or tags, can be a subject, and `it` is how a check says something about the value. With these params:

```json
{"allowed_regions": ["eu-west-1"]}
```

this input:

```json
{"deployment": {"id": "d-17", "regions": ["eu-west-1", "us-east-1"]}}
```

and this policy:

```yaml
ergo_spec: v0.3
subjects:
  region:
    from: every deployment.regions
requirements:
  allowed:
    subject: region
    checks:
      allowed: it is one of $params.allowed_regions
```

each region is a subject, with the region as its id, and the one that isn't allowed fails. The check's `expression` is `it is in $params.allowed_regions`, and the rows are:

```json
{"check": "allowed", "subject": {"id": "eu-west-1", "type": "region"}, "passed": true, "cause": "satisfied",
 "inputs": [{"name": "it", "value": "eu-west-1", "locations": ["/deployment/regions/0"]}], "requirement": "allowed"}
{"check": "allowed", "subject": {"id": "us-east-1", "type": "region"}, "passed": false, "cause": "value",
 "inputs": [{"name": "it", "value": "us-east-1", "locations": ["/deployment/regions/1"]}], "requirement": "allowed"}
```

`it` is the whole subject, whatever it holds. `it is an object` passes for an object, and a subject that is `null` or the wrong type for the phrase fails the way the same phrase fails on a field holding that value: `it is a string` on `null` fails as `null`, on `3` as `value`, and `it is at least 2` on `"a"` as `unusable`. Two regions with the same name still fail `$unique_ids`, because ids are the values.

`it` is also the path after `every`, `some`, `count of` and `sum of`, so a subject that is a list can be checked item by item. With `from: every releases.tags` and the input `{"releases": {"tags": [["a", "b"], [1, "x"]]}}`, `every it is a string` passes the first tag list and fails the second, with the row:

```json
{"check": "c", "subject": {"id": [1, "x"], "type": "tags"}, "passed": false, "cause": "value",
 "failed_items": [{"cause": "value", "item": "item 1 of it", "path": "item 1 of it", "value": 1, "locations": ["/releases/tags/1/0"]}],
 "inputs": [{"name": "it[]", "value": [1, "x"], "locations": ["/releases/tags/1/0", "/releases/tags/1/1"]}], "requirement": "r"}
```

A position is written in words, as for a field. With the input `{"releases": {"tags": [["a", "b"], [1, "x"], []]}}` and the same `from`, `first of it is "a"` gives:

```json
{"check": "c", "subject": {"id": ["a", "b"], "type": "tags"}, "passed": true, "cause": "satisfied",
 "inputs": [{"name": "item 1 of it", "value": "a", "locations": ["/releases/tags/0/0"]}], "requirement": "r"}
{"check": "c", "subject": {"id": [1, "x"], "type": "tags"}, "passed": false, "cause": "unusable",
 "inputs": [{"name": "item 1 of it", "value": 1, "locations": ["/releases/tags/1/0"]}], "requirement": "r"}
{"check": "c", "subject": {"id": [], "type": "tags"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "item 1 of it", "value": null, "locations": ["/releases/tags/2"]}], "requirement": "r"}
```

`1` can't be compared with `"a"`, so the second list fails as `unusable`, and the empty one has no first item, so it fails as `absent`, as `first of v` does on a field. Brackets, like `it[0]`, are written wrong.

`it` goes where an assertion starts: the left side of a check, after `and`, in an `any_of` option, and in a `whose` condition of a `from` line, like `from: every ws whose it starts with "b"`, where it reads each value the `from` line finds. Its `$applies` row names it `it`. After a `for` line it's still the subject, not the item of the `for`. Everywhere else it's written wrong, and the `$well_formed` row says how:

| Sentence                     | `$well_formed` says                                                    |
| ---------------------------- | ---------------------------------------------------------------------- |
| `it.name is 1`               | `it is the whole subject: write name, not it.name`                     |
| `it[0] is 1`                 | `it is the whole subject: nothing can follow it`                       |
| `x is it`                    | `it can only start an assertion: write it first, like it is not empty` |
| `$params.m named by it is 1` | `it can't name a key`                                                  |

A subject can't be called `it`. A requirement that uses one is written wrong, and `$well_formed` says `it is a word of the grammar, so a subject can't be called it` under `subjects.it`.

Reading the subject from the right side of a phrase, like `x equals it`, is left out for now.

## The report

`ergo.report(input, policy, params)` returns:

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

`compliant` is `true` when there's at least one requirement and none of them is `not_met`.

`description` and `meta` are the [policy's](#describing-a-policy), or `""` and `{}` when it has none.

`ergo` is the version of the [spec](spec/README.md#versions) the report follows. `engine` says what made it: `ergo.rego` and its version, which a policy can read as `ergo.version`. It doesn't say which OPA ran it, because that would make the report depend on the machine and not only on the policy, the input and the params. If you need to know, record it next to the report.

`subjects` says where the subjects come from, as [Subjects in the report](#subjects-in-the-report) shows.

`requirements` has an entry for each requirement:

```json
{
  "checks": {
    "$applies": {
      "description": "The deployment is in scope",
      "expression": "environment is \"prod\"",
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
      "expression": "count(problems) == 0",
      "meta": {}
    },
    "approved": {
      "description": "Someone approved the deployment",
      "expression": "approved_by is a non-empty string",
      "meta": {}
    }
  },
  "description": "Every production deployment is approved",
  "meta": {},
  "require": "every",
  "status": "not_met",
  "causes": [{ "cause": "absent", "rows": 1 }],
  "subject": "deployment",
  "subjects": { "matching": 2, "total": 3 }
}
```

`status` is one of:

| `status`         | When                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `met`            | the requirement passed, and at least one subject was left to check                                                                                |
| `not_met`        | anything else: a check failed, too few subjects were left, a condition couldn't be read, or the requirement is [written wrong](#checks-ergo-adds) |
| `not_applicable` | the requirement would have passed, but no subject was left after the subject's conditions, which only happens with `min_subjects: 0`              |

To tell whether a requirement passed, compare `status` with `"met"` (or `"not_applicable"`, if that counts as passing for you). Don't test for `"not_met"`, so a value you didn't expect counts as a failure.

`causes` says why a requirement isn't met, so a tool can tell a breach from missing evidence or a policy that's written wrong without reading every row. It lists the [causes](#causes) of the rows [`violations`](#violations) would return for the requirement, each with how many rows have it, in the order of the cause table, so the first entry is the worst. It counts rows, not subjects, because one subject can fail several checks.

Take the [README](README.md)'s policy and this input:

```json
{
  "deployments": [
    { "id": "d-1", "environment": "prod", "approved_by": "alice" },
    { "id": "d-2", "environment": "prod" },
    { "id": "d-3", "environment": "staging" },
    { "id": "d-4", "environment": "prod", "approved_by": "" },
    { "id": "d-5" }
  ]
}
```

```json
"causes": [
  { "cause": "absent", "rows": 2 },
  { "cause": "value", "rows": 1 }
]
```

The two `absent` rows are `d-2`'s `approved`, because it has no `approved_by`, and `d-5`'s `$applies`, because its condition can't read `environment`. The `value` row is `d-4`'s `approved`, whose `approved_by` is empty. `d-3` is only out of scope, so it isn't counted. With the check misspelt as `approved_by is a non-empty strng`, the requirement is [written wrong](#checks-ergo-adds), so `$well_formed` is its only row and `causes` is `[{ "cause": "value", "rows": 1 }]`. A requirement that's `met` or `not_applicable` has `"causes": []`.

`description` and `meta` are the requirement's, or `""` and `{}` when it has none. They're always there, so you can read `meta.control` without first checking that `meta` exists.

`subject` is the name of the subject the requirement checks, which is also a key of the report's `subjects`. It's `null` when the requirement names no subject, or one that isn't in the policy's `subjects`. `subjects.total` counts every subject found at `from`, and `subjects.matching` counts the ones left after the subject's conditions. `checks` holds each check with its `description` and `meta`, `""` and `{}` when you didn't write them, and the `expression`, which is the sentence as Ergo prints it. Nothing else of the check is copied. A `description` or `meta` of the wrong type makes the requirement or the check [written wrong](#checks-ergo-adds), and the report shows `""` or `{}` in its place, so a tool always finds a string and an object there. An `expression` you write is a field Ergo doesn't know, so the check is written wrong. A check that reads a `$params` or `$input` path also gets `$refs`: the name, value and [locations](#where-a-value-was-read) of each one, as read for this report. The `$` marks it as Ergo's, so it can't be mixed up with a field of your own. It also holds the [checks Ergo adds](#checks-ergo-adds), each with a `description`, an `expression` and an empty `meta`.

In an expression, a value written in the policy is shown as JSON, written the same way whatever the policy looked like, so anyone can produce the same text:

- A string is always in quotes: `state == "MERGED"`, `n == "1"` and `x == ""` compare against strings, and `n == 1`, `ok == true` and `x == null` don't. Only `"`, `\` and control characters are escaped, as `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t` or `\u0001` and so on, so `"a<b"` stays as it is.
- A number is a plain decimal, with no exponent and no trailing zeros: `1.0`, `1.50`, `1e2` and `2.5e-3` are shown as `1`, `1.5`, `100` and `0.0025`, and `-0` as `0`. A number keeps every digit the policy wrote, so it's only shown the same by every implementation when it has at most 15 significant digits, which is as many as any language's 64-bit floating point number is sure to keep. The same goes for a number copied from the input into the report: a runtime that reads JSON into 64-bit numbers, like JavaScript, turns `12345678901234567890` into `12345678901234567000` before Ergo sees it. A number in the policy has to be `0` or have a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, the range those numbers hold without losing digits. Elsewhere, a language like JavaScript turns `1e400` into `Infinity` and `1e-400` into `0`, so a check could pass there and fail here. A check holding such a number anywhere is written wrong: it fails `$well_formed`, the requirement gets no other row, and the number is shown as `<number out of range>`. One in `from`, `identified_by` or `min_subjects` fails `$well_formed`. A number in the input or the params isn't held to that range, because whoever writes the policy doesn't control them. Ergo compares it exactly, so `1e400` equals `1e400` and `1e-400` doesn't equal `0`, and copies it into the report as written. An implementation that reads JSON into 64-bit numbers can't do the same, so reports only match across implementations when every number in the input and the params fits that range.
- A list or object has one space after each comma and colon, and its keys are sorted: `["a", 1.5, {"a": "x", "b": [true, null]}]`.
- A ref is shown without quotes, as `$params.x`, so it can't be mistaken for the string `"$params.x"`.

Keys in paths are only quoted when needed, as described in [Checks](#checks), and are escaped the same way.

Several of these rules depend on how a number was written, not only on its value: `1e-400` is out of range but `0` isn't, and a number is shown with every digit the policy gave. An implementation has to read each number of the policy as written. In JavaScript, `JSON.parse` loses that, so it needs a parser that keeps the text, like the `source` that newer versions pass to a `JSON.parse` reviver.

`results` has one row for each subject and check:

```json
{
  "requirement": "approved_deploy",
  "subject": { "type": "deployment", "id": "d-2" },
  "check": "approved",
  "inputs": [{ "name": "approved_by", "value": null, "locations": ["/deployments/1"] }],
  "passed": false,
  "cause": "absent"
}
```

Passing and failing rows have the same fields. A row of a check with `every`, `some` or a `for` line also has `failed_items`, and so does the `$min_subjects` row of a subject whose `from` line has [`every`](#from-lines). So does an `$applies` row of a subject whose `from` line has one `some` or `every` condition, and one with several conditions has `failed_assertions`, like a check written as several sentences. To find a row's description and expression, look up `requirements[row.requirement].checks[row.check]`. Look it up through the requirement, because two requirements can use the same check name for different things.

### Where a value was read

Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`: where Ergo read its value, so a tool can point at the spot in the input. A location is a [JSON Pointer](https://www.rfc-editor.org/rfc/rfc6901) from the root of the input, like `/deployments/3/approved_by`, and list positions count from 0. With the policy `region is in $params.regions` as the check `region` of `deployment`, the params `{"regions": ["eu-west-1"]}` and this input:

```json
{"deployments": [{"id": "d-1", "region": "us-east-1"}, {"id": "d-2"}]}
```

the two rows are:

```json
{"check": "region", "subject": {"id": "d-1", "type": "deployment"}, "passed": false, "cause": "value",
 "inputs": [{"name": "region", "value": "us-east-1", "locations": ["/deployments/0/region"]}]}
{"check": "region", "subject": {"id": "d-2", "type": "deployment"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "region", "value": null, "locations": ["/deployments/1"]}]}
```

and the check's `$refs` entry is `{"name": "$params.regions", "value": ["eu-west-1"], "locations": ["$params:/regions"]}`.

- A value read from the params has `$params:` in front of a pointer from the root of the params, as `$refs` shows.
- A read that stops early points at the last value it reached. `d-2` has no `region`, so its location is `/deployments/1`, the deployment that should have held it. A pointer never leads to a value Ergo didn't read.
- An entry that holds one value for each item of a list, like the `inputs` of an `every`, has one location for each, in the same order. An entry that holds a number Ergo worked out, like `count of findings`, lists the locations of what it was worked out from.
- A failed item points at where its `value` was read, in the `failed_items` of an `$applies` row as in those of a check. The `failed_assertions` of an `$applies` row or of a check without a `for` line hold no values, so they have no locations. Those of a `for` line have `inputs`, with locations of their own.
- The entries of `$well_formed` are about how the policy is written, not about the input, so their `locations` are `[]`. So is a list that's missing, where there was nothing to read.
- Two reads with the same name and value are one entry only when their locations match too. A parent's `b.x` and a child's own `.b.x` can print the same and be read from different places, so they stay two entries.

### Subjects in the report

`subjects` has an entry for each subject the requirements use, by name. That's the subject a requirement names, the subject it narrows or reads from, and so on all the way back. A subject no requirement uses isn't listed.

Take this policy:

```yaml
ergo_spec: v0.3
subjects:
  deployment:
    description: Something we ship
    from: deployments
    identified_by: id
  prod deployment:
    from: deployment whose environment is "prod"
  release:
    from: releases
requirements:
  approved:
    subject: prod deployment
    checks:
      approved: approved_by is a non-empty string
```

and this input:

```json
{
  "deployments": [
    { "id": "d-1", "environment": "prod", "approved_by": "alice" },
    { "id": "d-2", "environment": "staging" }
  ]
}
```

The requirement's entry has `"subject": "prod deployment"`, and `subjects` is:

```json
{
  "deployment": {
    "description": "Something we ship",
    "from": "deployments",
    "identified_by": "id",
    "parts": {}
  },
  "prod deployment": {
    "description": "",
    "from": "deployment whose environment is \"prod\"",
    "identified_by": "id",
    "parts": {}
  }
}
```

`release` isn't there, because no requirement uses it. `deployment` is, because `prod deployment` narrows it.

Each entry has:

- `description` is the subject's, or `""` when it has none. A `description` that isn't a string is [written wrong](#subjects) and shows as `""`.
- `from` says how the subject is found, as a [from line](#from-lines) is written. A `from` written as a line is printed the same way whatever spaces it had. A subject without `from` reads the input field named like it. A `from` that is written wrong, because it isn't a string or can't be read, shows as `<invalid from>`. So does one that reads but has a problem, like `values of mixed types`, and the `from` of a subject with `applies_to` or `of`, because those fields said how it was found.
- `identified_by` is the path of the subject's id, or `null` when it has none, and the whole subject is its id. A subject that narrows another has the id of the one it narrows, also when its `from` is written wrong. An id that is written wrong shows as `<invalid identified_by>`.
- `parts` lists every [part](#parts) the subject has, including the ones it keeps from a subject it narrows, by alias. Each is `{"from": ..., "identified_by": ...}`, with `from` written the way a sentence writes a path, so `"  dd.b "` is `dd.b` and `x[$params.k]` is `x named by $params.k`, and `identified_by` the path of the part's id or `null` when it has none. For the policy under [Parts](#parts) it is

  ```json
  {
    "coverage": {"from": "compliance_status.attestations_statuses.coverage-verification", "identified_by": "attestation_id"},
    "findings": {"from": "compliance_status.attestations_statuses.findings.attestation_data", "identified_by": null}
  }
  ```

  A part that is written wrong is listed as best it can be, with `<invalid from>` for a path that can't be read and `<invalid identified_by>` for an id that can't.

A subject that is written wrong still has its entry, so nothing disappears from the report. A subject whose `from` starts at another subject lists that subject even when the line is written wrong, like `every parent.items`, and a subject that narrows another has that subject's id then. A `from` that doesn't parse, or isn't a string, lists no other subject. An unknown name, like `$foo` in `parent.items whose zz is $foo`, only makes the line written wrong with `unknown name $foo`, so that line still lists `parent`. If the line has a syntax error too, like `parent.items whose zz is $foo foo bar`, it says `doesn't parse` and lists no other subject. With this policy and the same input, where `deployment` writes its `from` and `identified_by` as lists:

```yaml
ergo_spec: v0.3
subjects:
  deployment:
    from: [deployments]
    identified_by: [id]
  note: {}
requirements:
  approved:
    subject: deployment
    checks:
      approved: approved_by is a non-empty string
  noted:
    subject: note
    checks:
      text: text is a non-empty string
  other:
    checks:
      x: x exists
```

`subjects` is:

```json
{
  "deployment": {
    "description": "",
    "from": "<invalid from>",
    "identified_by": "<invalid identified_by>",
    "parts": {}
  },
  "note": {
    "description": "",
    "from": "note",
    "identified_by": null,
    "parts": {}
  }
}
```

and the three requirements' `subject` are `"deployment"`, `"note"` and `null`, because `other` names no subject.

### Checks Ergo adds

Ergo adds four checks of its own. They start with `$`, so they can't clash with yours.

| Check           | One row per | Passes when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `$well_formed`  | requirement | the requirement names a subject in `subjects`, the requirement and its subject have only the fields Ergo knows and they have the right types, it has at least one check, a valid `require`, a `from` and an `identified_by` that are strings Ergo can read, no number a 64-bit float can't hold in a sentence, in `meta` or in `min_subjects`, no set or key that isn't a string in `checks`, a name that's a string, and no check that's [written wrong](#checks-ergo-adds). This depends only on how the requirement and its subject are written, never on the input or the params. |
| `$min_subjects` | requirement | `from` leads to a list or an object, or to an object when it ends with `named by each of`, and at least `min_subjects` subjects are left after the subject's conditions.                                                                                                                                                                                                                                                                                                                                                                                                              |
| `$unique_ids`   | requirement | no two subjects share an id, counting the ones its conditions leave out.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `$applies`      | subject     | the subject passes its conditions, the `whose` of its from line. These rows only exist when the subject has conditions.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |

The `$well_formed` expression is `count(problems) == 0`. The problems are the inputs below, one for each check or field that's written wrong, so a requirement that's written correctly has none.

A check is written wrong when it isn't a sentence, an object with `assert`, or an `any_of` of sentences, when it has a field Ergo doesn't know, or when a sentence can't be read. The `$well_formed` row gets an input for it, named after where the check sits in the policy, with the list of what's wrong. With this input:

```json
{"deployments": [{"id": "d-1", "environment": "prod", "approved_by": "alice"}, {"id": "d-2", "environment": "staging"}]}
```

and a `deployment` subject read from `deployments`, whose `from` is the list `[deployments]`, with these checks:

```yaml
approved: {op: non_empty_string, path: [approved_by]}
reviewed: {assert: approved_by is a non-empty string, descripton: Someone approved it}
signed: signed is
```

the inputs are:

```json
"inputs": [
  { "name": "count(checks)", "value": 3, "locations": [] },
  { "name": "require", "value": "every", "locations": [] },
  { "name": "subjects.deployment.from", "value": ["not a string"], "locations": [] },
  { "name": "checks.approved", "value": ["missing assert", "unknown field op", "unknown field path"], "locations": [] },
  { "name": "checks.reviewed", "value": ["unknown field descripton"], "locations": [] },
  { "name": "checks.signed", "value": ["doesn't parse"], "locations": [] }
]
```

A problem with a sentence in an `any_of` option is listed under the check, with the option's name in front, like `option standard: line 2: doesn't parse` or `option standard: line 1: values of mixed types` under `checks.permitted`. A problem with one line of an `assert` list of two or more starts with the line's number, like `line 2: values of mixed types` under `checks.signed`, and a problem with the `for` line, its `whose` included, starts with `for: `, like `for: values of mixed types`. A problem with a sentence is listed under the check, never under a place inside it, and a sentence lists every problem it has, so `x is one of 1, 'a' and y is at least y` gives both `values of mixed types` and `y is compared with itself`. A name that needs quotes is quoted: `checks."a.b"`.

The fields of the requirement and its subject get an input of the same form when something is wrong with them. The requirement's own fields come first, named after the field, and then the subject's, named after the subject and the field. Each group is sorted by field. `require` is shown with its value when it's fine, and with what's wrong instead when it isn't, so no name appears twice. With a requirement like this on the same subject, with `from: deployments`:

```yaml
approved:
  subject: deployment
  checks: {}
  min_subjects: -1
  require: all
  zz: 1
```

the inputs are:

```json
"inputs": [
  { "name": "count(checks)", "value": 0, "locations": [] },
  { "name": "checks", "value": ["empty"], "locations": [] },
  { "name": "min_subjects", "value": ["not a whole number from 0 to 1000000"], "locations": [] },
  { "name": "require", "value": ["neither every nor some"], "locations": [] },
  { "name": "zz", "value": ["unknown field"], "locations": [] }
]
```

| Field                                          | What's wrong                                                                                                                                                                                                                                           |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| any field Ergo doesn't know                    | `unknown field`                                                                                                                                                                                                                                        |
| `checks`                                       | `not an object`, `holds a key that isn't a string`, `missing`, `empty`                                                                                                                                                                                 |
| `checks.$applies` and Ergo's other rows        | `name reserved`                                                                                                                                                                                                                                        |
| `require`                                      | `neither every nor some`                                                                                                                                                                                                                               |
| `min_subjects`                                 | `not a whole number from 0 to 1000000`, `number out of range`                                                                                                                                                                                          |
| `subject`                                      | `missing`, `empty or not a string`, `not in subjects`                                                                                                                                                                                                  |
| `subjects`                                     | `not an object`                                                                                                                                                                                                                                        |
| `subjects.deployment`                          | `not an object`                                                                                                                                                                                                                                        |
| `subjects.deployment.from`, `...identified_by` | `not a string`, `doesn't parse`, `number out of range: 1e400`, or the reason a line can't be read, like `unclosed quote at column 24`                                                                                                                  |
| `subjects.deployment.from`                     | `leads to a loop`, `" " isn't a subject name`                                                                                                                                                                                                          |
| `subjects.deployment.description`              | `not a string`                                                                                                                                                                                                                                         |
| `subjects.deployment.has`                      | `not an object`                                                                                                                                                                                                                                        |
| `subjects.deployment.has.coverage`             | `not a string or an object`, `missing from`, `unknown field foo`, `invalid from`, `invalid identified_by`, `from: ...`, `identified_by: ...`, `invalid alias`, `x can't be an alias: it's a subject's name`, `x can't be an alias: it's a part of ...` |

A policy written in Rego can use a key that isn't a string, like `true` or `1.5`. Ergo names it `<invalid key true>` or `<invalid key 1.5>`, so two such keys never share a name. A requirement whose own name isn't a string, like `1`, or every requirement of a policy written as a list, fails `$well_formed`, which then starts with `{"name": "requirement name", "value": ["not a string"], "locations": []}`. The requirement is `not_met`, so the policy isn't compliant.

Their descriptions are plain sentences, like your own checks': `The requirement is written correctly`, `The in-scope deployment count is at least 1`, `Every deployment id is unique` and `The deployment is in scope`. The details are in `expression`, `inputs` and `cause`. `$min_subjects` names its input after what it counts, like `in-scope deployment count`: only the subjects left after the subject's conditions. With `min_subjects: 0` the count can't fail, so `$min_subjects` only checks that `from` can be read, and says so: `The deployment list can be read`, with the expression `deployments can be read`. A `from` line with `named by each of` keeps the count, because its subjects are the keys in the params list, so there's no list to read. `$unique_ids` lists the ids that more than one subject has, once each, under `repeated deployment ids`, sorted by how they're written as JSON, so `"b"` comes before `10`, and `10` before `3`. They use the subject's name as it's written, so they read right whatever the word's plural would be.

A subject that fails `$applies` gets no other rows, since it was never checked. But its `$applies` row stays, so you can see what was left out and why.

An `$applies` row has the fields the row of a check would have if its conditions were the assertions of that check. One `some` or `every` condition gives `failed_items`, which is `[]` when it passes. Two or more conditions give `failed_assertions`, the conditions that failed in the order written with their own causes, and `[]` when they all pass, but no `failed_items`. A single condition that isn't a `some` or an `every`, like `environment is "prod"`, adds no field, as a plain check doesn't. An entry of `failed_assertions` can have a cause the row doesn't: when a `present` condition rules the subject out, the row's cause is `value` and the entry of another condition can be `absent`.

A subject is only out of scope when Ergo read a condition's fields and the values didn't match, so the row's cause is `value`. When a condition fails because a field it reads is missing, `null` or can't be found, Ergo can't tell whether the subject is in scope. Its `$applies` row then fails with that cause, the requirement isn't met, and the row shows up in the violations. This holds with `min_subjects: 0` too, so a missing field can't quietly make a requirement pass.

`exists` is the exception, because a missing or `null` field is exactly what it checks for. `whose lock_release exists` leaves out a package with no `lock_release`. A parent that can't hold the field, like `"build": "abc"` for `build.fingerprint`, or a subject that isn't an object, still fails the requirement.

With several conditions, the subject is only out of scope when every condition that failed did so with `value`. If one rules it out and another can't be read, the requirement fails, so missing data always shows. An `exists` that finds its field missing is the exception: it says on purpose that a missing field means out of scope, so it rules the subject out whatever the other conditions read. That lets a condition on the same field sit next to it. With this input:

```json
{"lockfiles": [{"name": "a", "status": "COMPLETE"}, {"name": "b"}, {"name": "c", "status": "PENDING"}]}
```

`from: lockfiles whose status exists and status is "COMPLETE"` keeps `a`, and leaves out `b` and `c`, both with cause `value`, although `status is "COMPLETE"` can't read `b`'s status.

A condition that's written wrong still fails the requirement.

Together, these make sure that whenever a requirement isn't met, at least one row explains why.

### Row order

Rows always come in the same order, whatever order you wrote the policy in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then your own checks
2. within each group, requirements in name order
3. within a requirement, subjects in the order they appear in the input, or in key order when `named by each of` reads an object
4. within a subject, checks in name order

Patterns, options and the keys of objects written in the policy are sorted in rendered expressions too. Names, keys and strings are sorted by Unicode code point, so `！` (U+FF01) comes before `😀` (U+1F600). JavaScript's default `sort()` puts them the other way round, so an implementation there needs to compare code points. So the same policy and the same input always produce exactly the same report, byte for byte once it's written as JSON the same way, which means you can hash it and compare hashes. Every number in the report is written in its plain form, as in expressions, wherever it came from: `1.50`, `-0.0` and `1e2` in the policy, the params or the input come out as `1.5`, `0` and `100`. Two things are left as they are. A number a 64-bit float can't hold, like `1e400` in the input, is copied as written. And a report holding something JSON can't, like a set from an input written in Rego or a requirement whose name isn't a string, is left as Ergo built it, so that its rows still name their requirement. `opa eval` sorts the keys. OPA's JavaScript runtime for Wasm doesn't, and it reads the report into JavaScript numbers, which writes a very large or very small one with an exponent: `1e21` and `0.0000001` come out as `1e+21` and `1e-7`. So to compare reports across runtimes, write each one with the [JSON Canonicalization Scheme (RFC 8785)](https://www.rfc-editor.org/rfc/rfc8785) before hashing: it sorts keys and writes numbers the way JavaScript does.

## Causes

Every row has a `cause`. A missing field and a field set to `null` both show up as `null` in `inputs`, but they're different problems with different fixes. The cause tells them apart.

| `cause`         | Meaning                                                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `satisfied`     | The check passed.                                                                                                                                                        |
| `not_an_object` | The subject isn't an object, so it has no fields.                                                                                                                        |
| `ambiguous`     | Another item ties with the one a `for` line picks `sorted by` a field.                                                                                                   |
| `unusable`      | A value the check reads is there, but it's not the kind the check needs, like a string for `range`, a string where a path needs an object, or a param of the wrong type. |
| `absent`        | A field the check reads isn't there.                                                                                                                                     |
| `null`          | A field the check reads is there, but `null`.                                                                                                                            |
| `value`         | Everything was read fine. The values just don't pass.                                                                                                                    |

When the input or the params hold something JSON can't, every check on a subject, every `$applies` row and every `$min_subjects` row fails as `unusable` (see [Failing closed](#failing-closed)).

When a check reads several fields, the row shows the first cause in this table's order. An ambiguous pick matters more than any value, because it means the policy can't even tell what it's looking at.

- For `every`, `some` and `for` lines, a list that isn't there gives `absent`, and one that isn't a list gives `unusable`. An empty list gives `value`, since it was read fine and just has nothing in it. An item that isn't an object, `null` included, fails as `not_an_object` when the path goes on into it: with `t` holding `["a"]` or `[null]`, `every t.k is 1` and a `for` line `every t.k as x` both fail `item 1 of t` that way, and so do `count of t.k` and `sum of t.k`. Otherwise the cause is the first, in this table's order, among the items that failed. So when one approver is a bot and another has no `username`, a check that some approver isn't a bot fails as `absent`, because the second one might not be. An `any_of` works the same way across its options, and so does a path through several lists.
- `$well_formed` and `$min_subjects` don't read the subject, so their cause is `satisfied` or `value`, except that `$min_subjects` fails as `absent`, `null` or `unusable` when a `$params` or `$input` path after `named by` in `from` can't be read, or when `from` doesn't lead to a list or an object. `$applies` reports the state of the fields read by the conditions that failed. Its `inputs` list each field its conditions read once, sorted by name, so two conditions on `status` show `status` once. For example, a subject whose condition field is missing says `absent`, and that fails the requirement. A condition that's written wrong makes the requirement written wrong, so it gets no `$applies` rows at all.

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
    "inputs": [{ "name": "approved_by", "value": null, "locations": ["/deployments/1"] }],
    "cause": "absent"
  }
]
```

A violation of a check with `every`, `some` or a `for` line, or of the `$min_subjects` row of a subject read with `every`, keeps its row's `failed_items`, and one of a check written as several sentences its `failed_assertions`. A violation that's an `$applies` row keeps the `failed_items` or `failed_assertions` of its row too.

It leaves out:

- rows that passed
- `$applies` rows with the cause `value`, since being out of scope isn't a problem. An `$applies` row that failed because a condition couldn't be read is kept.
- every row of a requirement whose `status` is `met` or `not_applicable`. Under `require: "some"`, other subjects can fail while the requirement still passes, and those failures aren't problems.

It keeps the rows of a requirement with any other `status`, or none. It keeps `$min_subjects` failures, because finding nothing to check is a problem, and `$well_formed` failures, because they mean the policy itself is broken.

It only reads the report, never the input or the policy. It returns a list in the same order as `results`, so two failures that look the same are both kept. And it returns data, not text, so you decide how to word your messages. A missing `description` or `expression` comes back as `""`.

To decide whether to allow something, use `report.compliant`, not whether `violations` is empty. The two are worked out separately, so a mistake in how you use violations can't let something through.

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
{"name": "ergo/compiled engine", "value": ["compiled by another engine, expected ergo.rego 0.3.1-dev"], "locations": []}
```

or `["missing"]` when the compiled policy has no `engine`. That only tells released versions apart: every copy of `ergo.rego` between two releases has the same `-dev` version, so a compiled policy from an older copy of the same version still runs and can give a wrong report. Ergo doesn't check that nobody edited it either, so don't edit it. One with a field missing or of the wrong type fails like a policy Ergo can't read, and compiling a compiled policy gives it back unchanged, even one from another engine.

A `make` rule keeps it fresh, since it runs again when either file changes. With this `policy.yaml`:

```yaml
ergo_spec: v0.3
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

Ergo fails a check whenever it can't be sure, instead of letting it pass. Rego doesn't do that by default in a few places, so these are handled on purpose. Some of them name the operators that sentences run as, as the table in [Checks](#checks) shows:

- A missing, `null` or wrong-typed field fails every operator, except `missing`, which passes on a missing or `null` field.
- `compare` needs both sides to exist and have the same type. In plain Rego, `null < 5` is true, so a missing field would otherwise pass a `lt` check. Ordering objects, lists or booleans fails too.
- `every`, `some` and `for` lines need non-empty lists, inner lists included. A policy that's fine with no items says so with `, if any,`.
- An alias that clashes with a subject or a part, or is badly written, fails the check, so an inner alias can't quietly hide an outer one.
- A [part](#parts) that is missing, `null` or the wrong type fails a check exactly as the full path it stands for would, and a part that is written wrong, or is named like a subject or a part of a parent (see [Parts](#parts)), fails `$well_formed` and is never read as an alias.
- A check that's written wrong, like a sentence that can't be read or an object with an `op`, fails `$well_formed`, and the requirement gets no other row, so a mistake in a subject's conditions can't rule every subject out.
- A value of the wrong kind, like a string where `range` needs a number, or a param of the wrong type, fails with cause `unusable`, so a condition can't rule a subject out on it.
- With several conditions, one that can't be read fails the requirement, even when another rules the subject out. The only condition that can rule a subject out regardless is an `exists` that found its field missing.
- `min_subjects` is 1 unless you say otherwise, so finding nothing fails. A `from` that leads nowhere, to `null` or to something that isn't a list or an object fails even with `min_subjects: 0`.
- A key after `named by each of` that the input doesn't have is still a subject, so it fails instead of being skipped.
- A subject whose conditions can't be read fails the requirement instead of being left out.
- A `$params` or `$input` path that can't be read fails the check, even for phrases like `does not contain` or `does not match` that would pass on an empty value.
- A policy with no requirements, and a requirement with no checks, are never met.
- Ergo only reads what JSON can hold. Rego can build sets and object keys that aren't strings, but JSON and YAML can't, so Ergo turns both down and gives the same report however it's run. A set or such a key anywhere in the input or the params fails every check on a subject, every `$applies` row and every `$min_subjects` row with cause `unusable`, so even a requirement with no subjects isn't met. `$min_subjects` says why in its inputs, like `{"name": "$input", "value": ["holds a set"], "locations": []}`, or `$params` for the params. In a policy, a requirement or check holding either one is [written wrong](#checks-ergo-adds), and so is a requirement whose name isn't a string. So when you build the input in Rego, make lists, `[x | ...]`, not sets, `{x | ...}`.
- A requirement that isn't an object, a field of the wrong type, or a field Ergo doesn't know, fails `$well_formed` and keeps its place in the report, so a typo in the policy can't make a requirement vanish.
- A malformed timestamp fails `compare_time` rather than stopping the whole evaluation with an error.
- Running OPA with `--strict-builtin-errors` gives the same report as running without it, because Ergo checks a value's type before it passes it to a built-in like `object.get` or `count`.

## Policies written before 0.1

Before 0.1, a check was an object with an `op` and the fields that operator takes, like `{op: non_empty_string, path: [approved_by]}`, and a path was a list of keys. A subject was found with a `from` list, like `[deployments]`, and could have `applies_to` filters. The old checks also had `all`, `any`, `inputs`, `literal`, `{"ref": ...}` values and selectors, and the old subjects had `of`, `as`, `each_as` and `keys`. Spec 0.1 doesn't read any of this.

A policy that still uses it is written wrong. Nothing is skipped, and the report says what is wrong. With this input:

```json
{"deployments": [{"id": "d-1", "environment": "prod", "approved_by": "alice"}]}
```

a check written as `{op: non_empty_string, path: [approved_by]}` has no `assert`, and `op` and `path` are fields Ergo doesn't know. Its `expression` is `<missing assert>`, the requirement gets no other row, and `$well_formed` has this input:

```json
{"name": "checks.approved", "value": ["missing assert", "unknown field op", "unknown field path"], "locations": []}
```

A `from` written as the list `[deployments]` isn't a string. The requirement is written wrong, the subject is listed with `<invalid from>`, and `$well_formed` has:

```json
{"name": "subjects.deployment.from", "value": ["not a string"], "locations": []}
```

`applies_to` and `of` are fields Ergo doesn't know, so each gets `["unknown field"]`, like `{"name": "subjects.deployment.applies_to", "value": ["unknown field"], "locations": []}`.

### Moving a policy to sentences

`ergo.as_sentences(policy)` rewrites a policy written the old way into sentences, wherever a sentence reads back as exactly what was written. It always sets `ergo_spec: v0.3` on what it returns. Anything it can't rewrite stays as it was, and under 0.1 that is written wrong, so you rewrite those parts by hand. With this `policy.yaml`:

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
ergo_spec: v0.3
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
