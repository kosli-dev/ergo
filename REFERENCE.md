# Ergo reference

This page describes everything Ergo accepts and everything it returns. If you haven't used Ergo before, start with the [README](README.md).

- [Policies](#policies)
- [Subjects](#subjects)
- [Requirements](#requirements)
- [Checks](#checks)
- [Custom operators](#custom-operators)
- [The report](#the-report)
- [Causes](#causes)
- [Violations](#violations)
- [Compiling to Wasm](#compiling-to-wasm)
- [Compiling a policy](#compiling-a-policy)
- [Failing closed](#failing-closed)
- [The old syntax](#the-old-syntax)

## Policies

A policy is an object with two sections, and it can [describe itself](#describing-a-policy) too. `subjects` says what the policy checks and where to find it in the input, and `requirements` says what must be true of it. Each section maps names to definitions. A policy is plain data, so it usually lives in a YAML file that OPA loads. A file in the policy directory with top-level `subjects` and `requirements` keys is read as `data.subjects` and `data.requirements`:

```yaml
subjects:
  deployment: { ... }
  commit: { ... }
requirements:
  approved_deploy: { subject: deployment, ... }
  signed_commits: { subject: commit, ... }
```

You pass the policy to `ergo.report` along with the input and the [params](#params):

```rego
default subjects := {}

subjects := data.subjects

default requirements := {}

requirements := data.requirements

default params := {}

params := data.params

report := ergo.report(input, {"subjects": subjects, "requirements": requirements}, params)
```

`ergo.report` reads only its three arguments, so the same arguments always give the same report. The policy can also be written in Rego, like `subjects := {"deployment": {"from": "deployments", "identified_by": "id"}}`.

Give each argument a default like this when it comes from `data`. Rego doesn't call a function with an argument that isn't defined, so a file without `requirements:`, or a run without params, would make the whole report undefined, with no rows to say why. The defaults still fail closed: with no subjects every requirement fails, because the subject it names isn't there, with no requirements the policy isn't compliant, and with no params every `$params` read fails as `absent`. The same goes for the input: if it can be missing, give it a default too.

Because each name is an object key, two requirements can't share a name, and every row in the report points back to exactly one requirement.

A policy with no requirements is never compliant: it doesn't check anything, so it can't vouch for anything either. The same goes for a policy that isn't an object, or whose `requirements` isn't one. Ergo leaves out any other section of the policy, so it changes nothing in the report.

From your own policies, call only `ergo.report` and `ergo.violations`. Rules whose names start with `_`, like `ergo._row_cause`, are Ergo's own and can change or disappear in any release. If you lint with [Regal](https://www.openpolicyagent.org/projects/regal), its `leaked-internal-reference` rule flags a call to one.

### Describing a policy

A policy can have a `description` and a `meta` of its own, next to its sections. They work like a [requirement's](#requirements): `description` says what the policy asks for, `meta` keeps anything else, like the id of the control the policy checks, and Ergo copies both to the top of the report and never reads them. This is where a control with several requirements keeps its text:

```yaml
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

report := ergo.report(input, {"description": description, "meta": meta, "subjects": subjects, "requirements": requirements}, params)
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
    "runtime": {
      "name": "opa",
      "version": "1.20.2"
    },
    "version": "0.1.0-dev"
  },
  "ergo": "v0.1",
  "meta": {
    "control": "DEV-0401",
    "title": "Security testing and code review"
  },
  ...
}
```

`null` counts as not written, so the defaults above give `""` and `{}`. A `description` that isn't a string, or a `meta` that isn't an object or holds something JSON can't, belongs to every requirement, so every requirement's `$well_formed` row fails and lists it last, like `{"name": "policy meta", "value": ["not an object"]}`. The report then shows `""` or `{}` in its place.

### Params

Params are the third argument to `ergo.report`. Ergo doesn't look for them anywhere else, so the policy that calls it picks where they come from. Reading them from `data.params`, as above, means `opa eval -d params.json` passes them in when the file holds `{"params": ...}`, and a test can write `with data.params as {...}`.

A sentence reads them with `$params`, like `region is in $params.regions`. Params aren't part of the input, so `$input.params` doesn't reach them, and `$params` doesn't read the input. With params of `{}`, a read of a field in them, like `$params.regions`, fails as `absent`, as any missing field does. With no params, `null`, it fails as `absent` too, and that includes `exists`, which otherwise fails a missing field as `value`, and `does not exist`, which otherwise passes. So a condition like that on a param fails the requirement instead of deciding the scope. Params that are anything else, like a string or a list, can only be a mistake, so they fail every check and every `$min_subjects` row as `unusable`, even in a policy that reads no params, and `$min_subjects` says why: `{"name": "$params", "value": ["not an object"]}`. Ergo has no defaults, so a policy run without its params fails instead of checking something nobody configured.

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

`applies_to` and `of`, and a `from` or `identified_by` written as a list, are the [old syntax](#subjects-in-the-old-syntax).

The subject's name is what the report calls each one, in every row, like `"subject": {"type": "deployment", "id": "d-2"}`, and in the descriptions of the [checks Ergo adds](#checks-ergo-adds), like `The in-scope deployment count is at least 1`. So name it the way a reader would, like `deployment` or `pull request`.

A requirement names its subject with `subject`. Several requirements can name the same subject, and each one checks it on its own, with its own rows. A subject that no requirement names isn't read, so it changes nothing in the report.

A few details:

- If `from` leads to a list, each item is a subject. If it leads to a single object, that object is the only subject. If it leads nowhere, to `null`, or to anything else, like a string or a number, there are no subjects and `$min_subjects` fails with cause `absent`, `null` or `unusable`, even with `min_subjects: 0`, because that's what a typo in `from` looks like. A path through something that can't hold the next key, like `"build": "b1"` for `build.items`, gives `unusable`, and a missing or `null` parent gives `absent`, as they do in a [check](#paths). An empty list is different: it was read fine, so it fails `$min_subjects` as `value`, or passes with `min_subjects: 0`.
- The input has to be an object. A `null` input fails `$min_subjects` as `null` when `from` is empty or left out, and as `absent` when it has a step. Any other input that isn't an object, a list included, fails it as `unusable`.
- If `identified_by` doesn't lead anywhere, the subject's id is `null`. Its rows are still there.
- No two subjects can share an id, or their rows could be identical and the report couldn't say which one failed. If two do, `$unique_ids` fails and so does the requirement. Every subject counts, even one that its conditions leave out, and `null` is an id like any other, so two subjects without one clash.
- An item of the list that isn't an object, like a string or a `null`, is still a subject. Its id is the item itself, and its checks fail with cause `not_an_object`.
- Without `from`, a subject reads the input field named like it, so `artifact` reads `artifact`. A subject with nothing under it, `artifact:` alone in YAML, does the same. To check the whole input as one subject, write `from: $input`. Without `id`, each row repeats the whole subject as its id, so two identical subjects clash.
- A subject that's written wrong fails `$well_formed` on every requirement that names it, so none of them is met. That's a subject that isn't an object, or that has a field that isn't in the table above or in the [old syntax](#subjects-in-the-old-syntax), like `subject_type`, or whose `from` or `id` can't be read, or whose `description` isn't a string. The `$well_formed` row names each field with its subject, like `{"name": "subjects.deployment.from", "value": ["doesn't parse"]}`. Ergo reads such a `from` as giving no subjects (shown as `<invalid from>`), so `$min_subjects` fails as `value`, even with `min_subjects: 0`, and an `id` as giving the id `null`. The [old syntax](#subjects-in-the-old-syntax) has more ways to go wrong.

### From lines

A `from` line is a path, and `whose` with conditions joined by `and` keeps the subjects they hold for. Paths and conditions are written as in [checks](#checks). `identified_by` is a path written the same way:

```yaml
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
 "inputs": [{"name": "change_type", "value": "emergency"}, {"name": "environment", "value": "prod"}]}
{"check": "$applies", "subject": {"id": "d-2", "type": "emergency change"}, "passed": false, "cause": "value",
 "inputs": [{"name": "change_type", "value": "standard"}, {"name": "environment", "value": "prod"}]}
{"check": "$applies", "subject": {"id": "d-3", "type": "emergency change"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "change_type", "value": null}, {"name": "environment", "value": "prod"}]}
```

and the `$applies` entry's `expression` is the conditions as written, `environment is "prod" and change_type is "emergency"`. `d-3` has no `change_type`, so Ergo can't tell whether it's an emergency change, and `approved` isn't met. `artifact` has no `from`, so it reads the input field `artifact`, and `signed` is met.

- `named by $params.name` picks one key, as a [ref step](#ref-steps) does: `from: trail.artifacts named by $params.artifact_name`.
- `named by each of $params.kinds` makes each key in the list a subject, as a [naming step](#naming-subjects) with `keys` does: `from: build.test_runs named by each of $params.kinds`.
- A subject's own name at the start of its `from` is the input field, so `lockfile` can have `from: lockfile whose status is "COMPLETE"`.
- A `from` line that's another subject's name, with or without a `whose`, narrows that subject, as in [a subject built on another](#a-subject-built-on-another): `critical defect` with `from: defect whose severity is "critical"` keeps the defects that pass `defect`'s conditions and its own. A name with a space goes in quotes, so the whole line goes in single quotes in YAML: `from: '"critical defect" whose team is "b"'`. It takes its `id` from the subject it narrows, so an `id` of its own is written wrong.
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
   "inputs": [{"name": "approved_by", "value": ""}]}
  ```

  A check reads the artifact by its name, like `artifact.name`. Only checks written as sentences can read it.

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

  Each commit row says which artifact and which pull request it belongs to, like `"in": {"artifact": "sha-1", "pull request": "pr/7"}`, and each pull request gets its own `$min_subjects` and `$unique_ids` rows. An artifact or a pull request that's out of scope leaves out everything below it. An artifact whose conditions can't be decided gets one failing `$min_subjects` row, with `"in": {"artifact": ...}`. A check reads any ancestor by its name, like `artifact.name` or `"pull request".title`, and its parts too. A fourth level is written wrong, with `a chain of more than three subjects isn't supported yet`, and so is a subject that builds on a child subject with `of` or a from line that narrows it.
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
   "inputs": [{"name": "in-scope pull request count", "value": 2}],
   "failed_items": [{"path": "artifacts[2].pull_requests", "item": "artifacts[2].pull_requests", "cause": "absent", "value": null}]}
  {"check": "$unique_ids",   "subject": {"type": "pull request", "id": null}, "passed": true,  "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/7"}, "passed": true,  "cause": "satisfied"}
  {"check": "approved",      "subject": {"type": "pull request", "id": "pr/8"}, "passed": false, "cause": "value"}
  ```

  - Unlike a [child subject](#from-lines), these pull requests don't belong to an artifact. Their rows have no `in`, they're counted once, and their ids must be unique across all of them. A check can't read the artifact.
  - An empty list, like `sha-2`'s, adds nothing and fails nothing.
  - A list that's missing, like `sha-3`'s, `null` or not a list fails `$min_subjects` with the worst cause found, even with `min_subjects: 0`. The row's `failed_items` says where, and the pull requests that could be read are still checked. So does a value at the end that isn't an object, and a path with no list along it, as `every` does in a check.
  - Without `every`, a path through a list reads nothing, and `$min_subjects` fails as `unusable`.
  - `every` can't go with a path that starts at another subject's name or with `named by each of`. Both are written wrong. A child subject reads names one parent at a time.
- A `from` line can't go with `applies_to`. A `from` or `identified_by` that can't be read is written wrong, and the `$well_formed` row says why, like `{"name": "subjects.x.from", "value": ["doesn't parse"]}`.

### A subject built on another

When requirements check different parts of the same list, give each part its own subject, built on one that says where the list is. Say the SBOM lists components, some pinned by the lockfile and some exempt from the licence rules:

```yaml
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
- A problem fails `$well_formed` on every requirement that names a subject whose chain has it, and the requirement finds no subjects.
- A requirement can name the subject others build on too, like `component` to check every component.

### Parts

Data often keeps what a check needs deep inside the subject. Kosli, for one, puts every attestation at `compliance_status.attestations_statuses.<name>.attestation_data`, so a policy that reads three attestations repeats that path in every check. A subject can give a path a name once, with `has`, and the checks use the name. Each entry of `has` is a **part**, and its key is the part's alias. An alias is a short word that stands for something longer, as `as pr` does on a `for` line.

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
 "inputs": [{"name": "findings.truncated", "value": false, "part": {"name": "findings", "id": null}}]}
{"check": "every_hunk_acknowledged", "subject": {"type": "round", "id": "round-1"}, "passed": false, "cause": "value",
 "inputs": [{"name": "coverage.attestation_data.hunks_acknowledged", "value": 25, "part": {"name": "coverage", "id": "cov-9"}},
            {"name": "coverage.attestation_data.hunks_total", "value": 28, "part": {"name": "coverage", "id": "cov-9"}}]}
```

Each input read through a part says which part, and which one of them: `part` has the alias as the check writes it, and the `id`, the value at the part's `identified_by` inside the part. That is how a reader tells one attestation from another when a subject has several of the same kind. A one-line part has no id, so its `id` is `null`, and so is the id of a part that is missing or has nothing at `identified_by`. An input that doesn't go through a part has no `part`.

A part is a short name for its path and nothing more. `coverage.attestation_data.hunks_total` gives exactly the rows that `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_total` gives: the same `passed`, the same `cause` and the same values. A part that is missing fails the check as `absent`, a `null` one as `absent` when a step follows it, and one of the wrong type as `unusable`, because the full path would. Only the names differ. With `coverage-verification` missing from the input, the row is

```json
{"check": "every_hunk_acknowledged", "subject": {"type": "round", "id": "round-1"}, "passed": false, "cause": "absent",
 "inputs": [{"name": "coverage.attestation_data.hunks_acknowledged", "value": null, "part": {"name": "coverage", "id": null}},
            {"name": "coverage.attestation_data.hunks_total", "value": null, "part": {"name": "coverage", "id": null}}]}
```

and written out in full, its inputs are named `compliance_status.attestations_statuses.coverage-verification.attestation_data.hunks_acknowledged` and `...hunks_total`, with the same `null`. The `expression` of a check and the names in its `inputs` and `failed_items` keep the alias, so a reader sees the words the policy was written in.

- A part is one line, a path, or an object with `from`, a path, and `identified_by`, a path read inside the part. The report shows it under [`parts`](#subjects-in-the-report), and tags each input read through the part with the id it leads to.
- A path is written as in a [from line](#from-lines): keys joined by `.`, keys in quotes, positions, and `named by` a key of `$params` or `$input`. It is a path inside the subject, so it can't start at `$params` or `$input`, and it can't have `whose`, `count of` or `named by each of`.
- A part can be any path, even one that ends at a single value: `ratio: compliance_status.attestations_statuses.coverage.attestation_data.ratio` makes `ratio is at least 0.8` read the same.
- Keep the data's own names, as `findings` and `coverage` do, because a reader who knows the data finds `coverage.attestation_data.hunks_total` where they'd look for it.
- An alias is read wherever a bare first key reads the subject: in the subject's checks, in the assertions of a `for` line, and in the conditions of the subject's `from` line and of a subject that narrows it. In a `whose` and after a one-line `every` or `some`, where a bare first key is a field of the item, it's read on the right side and never on the left of a `whose`, as a `for` line's name is: `every items.price is at most limit` reads the part `limit`, `whose limit is at least 4` reads the item's `limit`, and `.limit` on the right reads the item's. `named by` a part's alias is written wrong, with `named by coverage reads a part, which isn't supported yet`.
- An alias shadows a field of the subject with the same name. To read the field, put a dot in front: `.coverage` is the subject's field `coverage`, not the part.
- An alias is a bare word that isn't a word of the grammar, `params` or `input`, or it is written wrong with `invalid alias`. Two aliases with the same name are written wrong with `alias given twice`: two parts of a subject, a part and one a subject keeps from a subject it narrows, a part and an alias of a `for` line in a check of the subject, a part and the name of the parent a child subject reads from, and in the [old syntax](#subjects-in-the-old-syntax) a part and an `as` or `each_as` alias.
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
   "inputs": [{"name": "artifact.pr_attestation.approvers", "value": ["bob"], "part": {"name": "artifact.pr_attestation", "id": null}}]}
  ```

  A part is only reached through its subject, so a bare `pr_attestation` in a check of `pull request` is one of its own fields.
- In the old syntax, a check reads a part as `$alias` in the first step of a path, like `{"op": "equals", "path": ["$coverage", "attestation_data", "hunks_total"], "value": 28}`, and the name keeps the dollar: `$coverage.attestation_data.hunks_total`. The same rules apply, and a part's path is written as above whichever syntax the subject uses.
- A part that is written wrong fails `$well_formed` on every requirement that names the subject, with the problem under the part's alias, like `{"name": "subjects.round.has.coverage", "value": ["missing from"]}`. That is a `has` that isn't an object (`not an object`), a part that isn't a string or an object (`not a string or an object`), an object without `from` (`missing from`), with a field other than `from` and `identified_by` (`unknown field <name>`), or with a `from` or `identified_by` that isn't a string (`invalid from`, `invalid identified_by`), and a path that can't be read (`from: a part is a path: whose and named by each of can't go in it`, `from: a part reads inside its subject, so it can't start at $params or $input`, or the problems a from line gives).
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
| `min_subjects` | How many subjects must be left after the subject's conditions for the requirement to be met.                                          | `1`       |
| `checks`       | Named checks that each subject must pass.                                                                                             | required  |

A few details:

- `meta` can hold anything JSON can, like `{"control": "SDLC-CTRL-0007", "frameworks": ["SOC 2", "ISO 27001"], "version": 3, "reviewed": true}`. Its numbers follow the same rule as numbers anywhere else in a policy: one a 64-bit float can't hold, like `1e400`, makes the requirement [written wrong](#basic-operators). So does a key that isn't a string, or a set, which a policy written in Rego can hold but JSON can't. In the report, a number is written in its plain form, so `1.50`, `1e2` and `-0` come out as `1.5`, `100` and `0`, and the same `meta` gives the same report however it was written.
- `min_subjects` defaults to 1 so that a typo in `from` fails the requirement instead of quietly passing it. Set it to `0` when you mean "if there are any, they must pass; if there are none, that's fine". It means the same under `every` and `some`. When none are left, the requirement is [not applicable](#the-report). That only holds for a list that's there: a `from` that leads nowhere still fails, as above. A `from` that ends with a [`keys` step](#naming-subjects) is the exception, because each key is a subject even when `from` leads nowhere.
- Under `some`, one subject has to pass all the checks by itself. Two subjects that each pass half of them don't count.
- A requirement with no checks, a `require` other than `every` or `some`, a check that's [written wrong](#basic-operators), or a [subject that's written wrong](#subjects), is never met. The `$well_formed` row says so, and says [what's wrong](#checks-ergo-adds), like `{"name": "require", "value": ["neither every nor some"]}`.
- So is a requirement without a `subject`, or whose `subject` isn't in `subjects`, like a typo for `deploymnt`. The `$well_formed` row says `{"name": "subject", "value": ["missing"]}` or `{"name": "subject", "value": ["not in subjects"]}`, and Ergo reads it as having no subjects, so `$min_subjects` fails too. If `subjects` itself isn't an object, every requirement that names a subject fails with `{"name": "subjects", "value": ["not an object"]}`.
- So is a requirement with a field that isn't in the table above, like `from` or `requires`, because Ergo would otherwise ignore it and check something you didn't mean. `from`, `identified_by` and `applies_to` belong to the [subject](#subjects). The `$well_formed` row lists each one in order and says what's wrong with it, the way it does for a [check that's written wrong](#checks-ergo-adds), like `{"name": "from", "value": ["unknown field"]}`. Rows for the subjects are still there.
- So is a requirement that isn't an object, or whose `checks` isn't an object, whose `min_subjects` isn't a whole number of 0 or more, whose `subject` isn't a string with something besides whitespace in it, since rows and descriptions name the subject by it, whose `description` isn't a string, or whose `meta` isn't an object. `null` counts as the wrong type, except for `description` and `meta`: Ergo only copies those, so a `null` one counts as not written, which is what YAML gives for an empty `description:`. `2.0` is a whole number, but `-1` and `0.5` aren't. It still has its entry in `requirements` and its `$well_formed` row, which shows each such field and what it should be, like `{"name": "checks", "value": ["not an object"]}`, or the whole requirement and its value, like `{"name": "requirement", "value": 5}`. Ergo then reads `checks` as empty. A requirement that isn't an object gives no subjects. A `min_subjects` that isn't a number fails `$min_subjects` too.

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

The `$applies` row reads `{"name": "deployment.change_type", "value": "bug_fix"}`, and the `$applies` entry in `checks` records the list it was compared with, under `$refs`: `{"name": "$params.untested_change_types", "value": ["bug_fix", "refactor"]}`. A new feature with no test runs fails `tested` and `passed`, and so does a change type that isn't listed, like `hotfix`, so a new or misspelt type has to be tested until someone adds it to the list. A deployment with no `change_type` fails the requirement, because Ergo can't tell whether it applies.

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

A check is a sentence: one line of English. [spec/sentences.md](spec/sentences.md) has the full grammar. Write the sentence on its own, or under `assert` when the check has a `description` or `meta`:

```yaml
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
    {"name": "reviewed_at", "value": "2026-10-02T11:00:00Z"},
    {"name": "deployed_at", "value": "2026-10-02T10:00:00Z"}
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

`is empty` passes on `""` or `[]` and `is not empty` on a string or a list with something in it. Anything else that's there, like a number or an object, fails both as `unusable`. Their operators only exist for sentences. `starts with` and `ends with` compare two strings: anything else, two numbers included, fails as `unusable`, and a written value after them that isn't text, like `x starts with 1`, is written wrong. `is alphabetically before` and `is alphabetically after` order two strings in the same way, code point by code point, so every uppercase letter comes first: `"Zoe"` is alphabetically before `"adam"`.

`is at least`, `is at most`, `is more than` and `is less than` only order numbers. Two strings fail as `unusable`, because a number held as a string would be ordered as text, and with this input:

```json
{"conditions": [{"metric": "coverage", "value": "9", "errorThreshold": "80"}]}
```

`every conditions.value is at least errorThreshold` would pass, since `"9"` comes after `"80"` as text. A written value that isn't a number, like `score is at least "3"`, is written wrong, with `"is at least" takes a number`.

After `is in`, `is not in`, `contains`, `does not contain`, `contains all of`, `contains none of`, `matches` and `does not match`, the thing on the right can be a field too, read like the field after `is at least`: from the subject, from the name of a `for` line or from the item of a one-line `every` or `some` and a `whose`. With this policy and this input:

```yaml
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
    {"name": "tickets", "value": ["OPS-1"]},
    {"name": "required_tickets", "value": null}
  ],
  "passed": false,
  "requirement": "prod_deploy",
  "subject": {"id": "d2", "type": "deployment"}
}
```

They run as `compare` with `in`, `not_in`, `includes`, `excludes`, `includes_all`, `excludes_all`, `matches_any` and `not_matches_any`, and only sentences can use those. The row has the same `passed` and `cause` as the sentence with `$params.required_tickets` holding that field's value, and the field is in the row's `inputs` after the left side instead of in `$refs`. A field on the right that's missing or `null` fails the row as `absent` or `null`, whatever the left side is. One that can't be used fails it as `unusable`: not a list after `is in`, `is not in`, `contains all of`, `contains none of`, `matches` and `does not match`, an empty list after `contains all of` and `contains none of`, and patterns that aren't all valid regular expressions. Only when the right side can be used does the left side's own cause count.

The thing on the right is a value when it's in quotes, a number, `true`, `false` or `null`, and a field otherwise. A list of values is separated by `, `. A string can be in single quotes, which keep backslashes as written, so `'^\s*FROM'` needs no doubled backslash.

A path is keys joined by `.`, like `build.commit.sha`. A key with anything but letters, digits, `_` and `-` goes in double quotes, like `labels."app.kubernetes.io/name"`. `$params.regions` reads the params and `$input.repo` the input. `artifacts named by $params.name` reads the key the param holds, as a [ref step](#ref-steps) does, and so does `artifacts[$params.name]`. `named by` a bare field reads the key the subject holds, as below. `item 2 of commits`, `first of commits` and `commits[1]` read one item of a list. A path can't start with a word the sentences use, like `empty`, `count` or `true`. Put a dot in front, `.empty is 1`, to read a field with that name.

`named by` a bare field picks the key from the subject, so a limit can depend on a field like the severity. With the params `{"max_days": {"critical": 1, "high": 5}}`, this policy:

```yaml
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
   {"name": "age_days", "value": 2},
   {"name": "$params.max_days named by severity", "value": 1},
   {"name": "severity", "value": "critical"}
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
    {"name": "approved_by", "value": ""},
    {"name": "deployed_at", "value": "2026-10-02T10:00:00Z"},
    {"name": "reviewed_at", "value": "2026-10-02T11:00:00Z"}
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
    {"name": "$params.known_package_licenses named by name", "value": null},
    {"name": "licenses", "value": [{"license": {"id": "WTFPL"}}]},
    {"name": "licenses[].license.id", "value": ["WTFPL"]},
    {"name": "name", "value": "leftpad"}
  ],
  "passed": false,
  "requirement": "licences",
  "subject": {"id": "leftpad", "type": "component"}
}
```

The row reads every field the options read, once each. Its cause is the first, in the order of [causes](#causes), among the options, and an option's cause is the first among its sentences. Here `known` fails as `absent`, because the params have no licence for leftpad. An option with an `exists` sentence whose field is missing fails as `value` instead, as an [old-syntax `any_of`](#any_of) does. The row has no `failed_assertions`. The check's `expression` is `one of: declared(some licenses.license.id is in $params.allowed_licenses) | known(licenses does not exist and $params.known_package_licenses named by name is in $params.allowed_licenses)`, with the options sorted by name.

An `any_of` takes `description` and `meta`, but not `for` or `assert`. An `any_of` that isn't an object, an empty one, an empty option, or an option that isn't a sentence or a list of them is written wrong, with `invalid any_of`, `empty any_of`, `empty option <name>` or `invalid option <name>`. A problem with a sentence starts with its option's name, like `option known: line 2: doesn't parse`.

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
    {"cause": "value", "item": "item 2 of pull_requests[0].commits", "path": "pull_requests[0].commits[1].signed", "value": false},
    {"cause": "absent", "item": "pull_requests[1].commits", "path": "pull_requests[1].commits", "value": null}
  ],
  "inputs": [{"name": "pull_requests[].commits[].signed", "value": [true, false]}],
  "passed": false,
  "requirement": "release",
  "subject": {"id": "r-1", "type": "release"}
}
```

- `inputs` names the path with `[]` after each list walked, and holds the value each item's path ended at.
- Each entry in `failed_items` gives the field that failed as `path`, and the item it belongs to as `item`, so a tool can show the item by reading the input there. A list that's missing, `null`, not a list or empty is listed in its items' place.
- An empty list fails `every` as `value`, because no commits isn't proof that every commit is signed. Write `, if any,` after the path to let empty lists pass: `every review.incidents, if any, is not empty`. A missing list still fails.
- `whose` keeps the items that pass its conditions, read on each item: `some pull_requests.approvers whose state is "APPROVED" exists` passes above, with `bob`'s approval. An item a condition can't decide, because the field it reads is missing, fails the check rather than being left out.
- In a one-line `every` or `some`, a field on the right of the phrase is the item's too, so `some approvers.timestamp whose state is "APPROVED" is after last_commit` reads both from each approver. To compare with a field of the subject, use a `for` line, below.
- `every` and `some` paths can be ten steps long.
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
        {"assertion": "approver.state is \"APPROVED\"", "cause": "value", "items": [{"cause": "value", "item": "item 1 of pr.approvers"}]},
        {"assertion": "approver.username does not equal pr.author", "cause": "value", "items": [{"cause": "value", "item": "item 1 of pr.approvers"}]}
      ],
      "item": "item 2 of pull_requests",
      "path": "item 2 of pull_requests",
      "value": {"approvers": [{"state": "COMMENTED", "username": "bob"}], "author": "bob", "number": 8}
    }
  ],
  "inputs": [
    {"name": "pr.approvers[]", "value": [{"state": "APPROVED", "username": "bob"}, {"state": "COMMENTED", "username": "bob"}]},
    {"name": "pull_requests[]", "value": [
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
- With two items, a failed sentence that reads the second item's alias also has `items`: the items of the second list it failed for, in list order, each with the cause it failed with. Here `item 1 of pr.approvers` is pull request 8's first approver. With `for: some approvers as approver, every commits as commit`, an approver who approved before the last commit fails `approver.timestamp is after commit.timestamp` with `"items": [{"cause": "value", "item": "item 2 of commits"}]`, so you can see which commit came later. Each item has its own cause: a commit with no `timestamp` would be listed there with `"cause": "absent"`. A sentence that doesn't read `commit`, like `approver.username does not equal author`, has no `items`, because it fails the same way for every commit.
- `failed_assertions` is `[]` when no sentence was checked, like when `whose` leaves no approver, or a field a `whose` reads is missing.
- When the second item failed before any sentence was checked, the item of the first list has its own `failed_items`, saying where. With `for: some approvers as approver, every commits whose author does not equal approver.username as commit` and a commit with no `author`, `{"t": 2}`, the approver's entry has `"failed_assertions": []` and:

  ```json
  "failed_items": [{"cause": "absent", "item": "item 2 of commits", "path": "item 2 of commits", "value": {"t": 2}}]
  ```

  What fails the same way for every approver is listed once in the row's `failed_items` instead, in place of the approvers that failed only because of it. That's a missing `commits` list, `{"cause": "absent", "failed_assertions": [], "item": "commits", "path": "commits", "value": null}`, or a commit that `whose kind is "code"` can't decide, because that `whose` doesn't read `approver`. An approver that's still listed has the cause of what's left under it. A list inside the first, like `pr.approvers`, is listed under each pull request, because each has its own.
- `inputs` holds each list the `for` line walked, with its items, and every field of the subject the sentences read. A field read through a name, like `pr.author`, isn't listed on its own.
- In `assert`, a bare first key is the subject's field, and a name reaches its item. Inside an item's own `whose`, a bare key is that item's field. A name hides a field with the same name, the subject's or an item's, except on the left side of a `whose`: `whose env is "prod"` always reads the item's `env`. Write a dot in front to read the field a name hides: `.env`.
- Each list fails as a one-line `every` or `some` does: empty, missing, `null` or not a list, and `, if any,` lets an empty one pass.
- Two items at most.
- `named by` an alias from the `for` line reads the key its item holds. With `for: every personas_dispatched as persona`, `persona_blob_shas named by persona exists` reads `persona_blob_shas.security`, then `persona_blob_shas.style`, and so on. An item that's `null` fails as `null`, and any other item that isn't a string, a number included, as `unusable`, since it can't be a key. The row's inputs show `persona_blob_shas` itself.

With `for: some approvals.approver as approver`, where a commit also has an `approver` field:

| sentence                                         | compares                                         |
| ------------------------------------------------ | ------------------------------------------------ |
| `every commits.author does not equal approver`   | each commit's `author` with the name `approver`  |
| `every commits.author does not equal .approver`  | each commit's `author` with its own `approver`   |
| `.approver equals approver`                      | the subject's `approver` with the name           |

A `for` item can start with a position instead of `every` or `some`, and then its alias stands for that one item: `first of commits`, `item 2 of commits`, `last of commits`, or `item 2 from last of commits`. Positions count from 1. Add `sorted by` and a field of each item to count in the order of that field rather than the order of the list. With this input:

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
        {"assertion": "approver.username does not equal last_commit.author_username", "cause": "value", "items": [{"cause": "value", "item": "item 1 of approvers"}]}
      ],
      "item": "item 1 of commits",
      "path": "item 1 of commits",
      "value": {"author_username": "ada", "sha": "a1", "timestamp": 1760000200}
    }
  ],
  "inputs": [
    {"name": "approvers[]", "value": [{"username": "ada"}]},
    {"name": "item 1 of commits", "value": {"author_username": "ada", "sha": "a1", "timestamp": 1760000200}}
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
- A field of the picked item is read through its name, `last_commit.author_username`. In a sentence, `last of commits.author_username` would be the last of a list at `commits.author_username`.

`count of`, `sum of` and `plus` work out a number to compare, as the [derived values](#derived-values) of `compare` do. With the input of [derived values](#derived-values):

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

- `count of` walks every list along its path, as `every` does, so `count of pull_requests.commits` counts the commits of every pull request. An empty list adds nothing, so `count of approvers` is 0 when there are none.
- A list that's missing, `null` or not a list fails the check as `absent`, `null` or `unusable`, and so does a number to add that's missing, `null` or isn't a number.
- An item that `whose` can't decide about fails the check, as with `every`.
- `whose` goes after the last `count of` or `sum of`, and only on the left: `claude_found plus count of findings whose source is "gpt" is at least 3`.
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
  {"name": "days elapsed from first_seen_ts to now_ts", "value": 64.5},
  {"name": "first_seen_ts", "value": "2026-08-01T00:00:00Z"},
  {"name": "now_ts", "value": "2026-10-04T12:00:00Z"},
  {"name": "$params.max_days named by severity", "value": 30},
  {"name": "severity", "value": "low"}
]
```

- A unit is a fixed length: a second, 60 seconds, 3600, 86400 and 604800. The result is rounded down to 6 decimal places, so 36 hours is `1.5` days and one second is `0.000011` days. That way every runtime gives the same number. There's no `months` or `years`, because they have no fixed length.
- Both fields must be RFC 3339 times, like `2026-10-01T00:00:00Z` (a capital `T` and `Z`, a real date, a year from 1678 to 2261), both dates, like `2026-10-01`, which are whole days apart, or both numbers, which are read as seconds, to the nearest microsecond. A number must be between -9000000000 and 9000000000, about the years 1684 to 2255, so a time in milliseconds fails as `unusable` instead of being read as seconds. A missing field fails the check as `absent`, a `null` one as `null`, and anything else, including one time and one number, as `unusable`.
- When the second time is before the first, the check fails as `value`, and the number in its first input is `null`.
- It goes where a count goes: at the start of a sentence with the phrases a count goes with, as a term of `plus` and on the right side of a phrase, where `is` prints as `equals`, as it does before a count. It also goes in the `whose` of a `count of`, a `sum of` or an `every`, where an item whose end is before its start is left out. `every`, `some` and a `from` line are written wrong with `isn't supported yet`. It works in each line under `assert`, and under a `for` line, where a path can start at a name, like `days elapsed from pr.opened_ts to pr.merged_ts is at most 2`.
- `seconds`, `minutes`, `hours`, `days`, `weeks` and `to` are words of the grammar, so a field with one of those names is written `.days`.

A sentence that can't be read is [written wrong](#basic-operators), and the `$well_formed` row says why, with the column when it can:

```json
{"name": "checks.prod", "value": ["unclosed quote at column 16"]}
```

for `prod: environment is "prod`. `x is not null` is written wrong too, because it could only fail: write `x exists`. So is a value that isn't a number before `within`, like `x is "a" within 1`. A sentence that compares a path with itself, like `x is at least x`, is written wrong too, because it could only pass or only fail. That happens most often in a `whose`, or after `every` or `some`, where a bare name is the item's: `every conditions.type equals type` compares each condition's `type` with itself. To compare an item with the subject, use a [`for` line](#checks) and put the comparison under `assert`. An object with both `assert` and `op` is read as a check with an `op`, so a [custom operator](#custom-operators) can still take `assert`.

Ergo doesn't run every sentence the spec describes yet. These are written wrong for now, with `isn't supported yet` in the `$well_formed` row: `last of` and `item <n> from last of` anywhere but at the start of a `for` item, a `sum of` or a `plus` in the `whose` of a `count of` or a `sum of`, a `plus` in the phrase of an `every` or `some`, and an elapsed time after `every` or `some` or in a `from` line. A sentence can't be a [substitute](#substitutes) either, or a check in an option of an [`any_of`](#any_of) written with `op`, and fails there as `invalid check`. So `last_signed: last of commits.signed is true` gives:

```json
{"name": "checks.last_signed", "value": ["last of isn't supported yet here: pick the item on a for line, like \"for: last of commits as commit\""]}
```

Until then, write those checks with an [`op`](#operators).

## Custom operators

When the built-in checks can't say what you need, you can write your own operator. Sentences can't name one yet, so a check that uses one is written with `op`, as in the [old syntax](#operators). Don't name one after a built-in operator, or after `empty_string_or_list`, `not_empty_string_or_list`, `not_in` or `has_type`, which Ergo keeps for [sentences](#checks). Add an `op_passed` rule to the `ergo` package from a file of your own:

```rego
package ergo

op_passed(check, subj) if {
	check.op == "even"
	n := value_at(subj, check.path)
	is_number(n)
	n % 2 == 0
}
```

Declare its name in the same file, so Ergo can tell it from a typo:

```rego
operators contains "even"
```

An `op` that isn't built in or declared is written wrong: it fails `$well_formed`, and the check fails with cause `ill_formed`, even if an `op_passed` rule passes it. Its expression shows `<unknown op even>`, so the report points at the policy. So a misspelt operator in `applies_to` fails the requirement instead of ruling every subject out.

Then use it like any other operator. Ergo can't work out what your operator reads or how to describe it, so give the check an `expression` and a list of `inputs`:

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

Ergo finds the refs in your check by itself, so they appear under `$refs` and decide the cause when they can't be read, as for built-in operators.

A custom operator works in `checks`, in `applies_to`, and on either side of a substitute. It doesn't work as the inner check of `all` or `any`, or inside an `any_of` option: there, it's written wrong, so it fails `$well_formed` and the check fails with cause `ill_formed`.

Three rules:

- **Fail when you can't read the data.** Check that fields are there and have the right type before you compare them. A rule that doesn't hold fails the check, which is what you want. Be careful with `not`, which turns an error into a pass.
- **Read the document with `value_at` and `$$input`, and params with `$$params` or `arg`, not with `input` or `data`.** While Ergo checks a subject, `input` holds Ergo's own [names](#naming-subjects), not your input, and `data.params` may not be the params the report was given.
- **Only call `value_at`, `arg` and `leaf_passed`.** `value_at(subj, path)` reads a path, `arg(value)` reads one of your parameters, and `leaf_passed(check, subj)` runs a built-in check like `{"op": "present", "path": ["approved_by"]}` (but not `all`, `any` or `any_of`). Calling `op_passed` or `report` from your operator creates a loop, which Rego rejects, and the errors will point at `ergo.rego` rather than your file. Every other rule in `ergo.rego` starts with `_` and can change or disappear in any release.

## The report

`ergo.report(input, policy, params)` returns:

```json
{
  "compliant": false,
  "description": "",
  "engine": {
    "name": "ergo.rego",
    "runtime": {
      "name": "opa",
      "version": "1.20.2"
    },
    "version": "0.1.0-dev"
  },
  "ergo": "v0.1",
  "meta": {},
  "requirements": { ... },
  "results": [ ... ],
  "subjects": { ... }
}
```

`compliant` is `true` when there's at least one requirement and none of them is `not_met`.

`description` and `meta` are the [policy's](#describing-a-policy), or `""` and `{}` when it has none.

`ergo` is the version of the [spec](spec/README.md#versions) the report follows. `engine` says what made it: `ergo.rego`, its version, which a policy can read as `ergo.version`, and as `runtime` what it ran on. Ergo reads that from `opa.runtime()` and copies only `name`, `version` and `compiled_by`, and only when they're strings, never the rest, which also holds every environment variable. OPA gives a version and no name, so the name is `opa`. `runtime` is `null` when Ergo can't tell what ran it: OPA used as a Go library gives nothing unless the program sets its runtime with `rego.Runtime`, and on [Wasm](#compiling-to-wasm) it's what the host passes in.

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

| `status`         | When                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `met`            | the requirement passed, and at least one subject was left to check                                                                               |
| `not_met`        | anything else: a check failed, too few subjects were left, a condition couldn't be read, or the requirement is [written wrong](#basic-operators) |
| `not_applicable` | the requirement would have passed, but no subject was left after the subject's conditions, which only happens with `min_subjects: 0`             |

To tell whether a requirement passed, compare `status` with `"met"` (or `"not_applicable"`, if that counts as passing for you). Don't test for `"not_met"`, so a value you didn't expect counts as a failure.

`causes` says why a requirement isn't met, so a tool can tell a breach from missing evidence or a policy that's written wrong without reading every row. It lists the [causes](#causes) of the rows [`violations`](#violations) would return for the requirement, each with how many rows have it, in the order of the cause table, so the first entry is the worst. It counts rows, not subjects, because one subject can fail several checks.

Take the [README](README.md)'s policy with its check misspelt as `approved_by is a non-empty strng`, and this input:

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
  { "cause": "ill_formed", "rows": 3 },
  { "cause": "absent", "rows": 1 },
  { "cause": "value", "rows": 1 }
]
```

The three `ill_formed` rows are the misspelt check on `d-1`, `d-2` and `d-4`. The `absent` row is `d-5`'s `$applies`, because its condition can't read `environment`, and the `value` row is `$well_formed`, which fails with `value` like any check that read what it needed. `d-3` is only out of scope, so it isn't counted. A requirement that's `met` or `not_applicable` has `"causes": []`.

`description` and `meta` are the requirement's, or `""` and `{}` when it has none. They're always there, so you can read `meta.control` without first checking that `meta` exists.

`subject` is the name of the subject the requirement checks, which is also a key of the report's `subjects`. It's `null` when the requirement names no subject, or one that isn't in the policy's `subjects`. `subjects.total` counts every subject found at `from`, and `subjects.matching` counts the ones left after the subject's conditions. `checks` holds each check as you wrote it, plus the `expression` Ergo rendered from it. Each check has a `description` and a `meta` too, `""` and `{}` when you didn't write them. A filter in `applies_to`, in the [old syntax](#subjects-in-the-old-syntax), can have them as well, and they're checked the same way, but the report doesn't copy them: its filters all share the one `$applies` entry, with Ergo's own description. A `description` or `meta` of the wrong type makes the requirement or the check [written wrong](#basic-operators), and the report shows `""` or `{}` in its place, so a tool always finds a string and an object there. If you write your own `expression`, yours is used, as long as it's a string. Any other value is ignored, and Ergo renders the expression as if it weren't there. A check that uses a [`ref`](#reading-from-the-input) also gets `$refs`: the name and value of each one, as read for this report. The `$` marks it as Ergo's, so it can't be mixed up with a field of your own. It also holds the [checks Ergo adds](#checks-ergo-adds), each with a `description`, an `expression` and an empty `meta`.

In an expression, a value written in the policy is shown as JSON, written the same way whatever the policy looked like, so anyone can produce the same text:

- A string is always in quotes: `state == "MERGED"`, `n == "1"` and `x == ""` compare against strings, and `n == 1`, `ok == true` and `x == null` don't. Only `"`, `\` and control characters are escaped, as `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t` or `\u0001` and so on, so `"a<b"` stays as it is.
- A number is a plain decimal, with no exponent and no trailing zeros: `1.0`, `1.50`, `1e2` and `2.5e-3` are shown as `1`, `1.5`, `100` and `0.0025`, and `-0` as `0`. A number keeps every digit the policy wrote, so it's only shown the same by every implementation when it has at most 15 significant digits, which is as many as any language's 64-bit floating point number is sure to keep. The same goes for a number copied from the input into the report: a runtime that reads JSON into 64-bit numbers, like JavaScript, turns `12345678901234567890` into `12345678901234567000` before Ergo sees it. A number in the policy has to be `0` or have a magnitude between `2.2250738585072014e-308` and `1.7976931348623157e308`, the range those numbers hold without losing digits. Elsewhere, a language like JavaScript turns `1e400` into `Infinity` and `1e-400` into `0`, so a check could pass there and fail here. A check holding such a number anywhere is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and the number is shown as `<number out of range>`. One in `from`, `id` or `min_subjects` fails `$well_formed`. A number in the input or the params isn't held to that range, because whoever writes the policy doesn't control them. Ergo compares it exactly, so `1e400` equals `1e400` and `1e-400` doesn't equal `0`, and copies it into the report as written. An implementation that reads JSON into 64-bit numbers can't do the same, so reports only match across implementations when every number in the input and the params fits that range.
- A list or object has one space after each comma and colon, and its keys are sorted: `["a", 1.5, {"a": "x", "b": [true, null]}]`.
- A ref is shown without quotes, as `$params.x`, so it can't be mistaken for the string `"$params.x"`.
- Something that should be a string but isn't, like an `op` or `cmp` written as an object, is shown as JSON too: `<unknown op {"ref": ["a"]}>`. A string there is shown as it is, without quotes: `<unknown op nope>`.

Keys in paths are only quoted when needed, as described in [Paths](#paths), and are escaped the same way.

Several of these rules depend on how a number was written, not only on its value: `1e-400` is out of range but `0` isn't, and a number is shown with every digit the policy gave. An implementation has to read each number of the policy as written. In JavaScript, `JSON.parse` loses that, so it needs a parser that keeps the text, like the `source` that newer versions pass to a `JSON.parse` reviver.

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

Passing and failing rows have the same fields. A row of an `all` or `any` check also has [`failed_items`](#which-items-failed), and so does the `$min_subjects` row of a subject whose `from` line has [`every`](#from-lines). To find a row's description and expression, look up `requirements[row.requirement].checks[row.check]`. Look it up through the requirement, because two requirements can use the same check name for different things.

### Subjects in the report

`subjects` has an entry for each subject the requirements use, by name. That's the subject a requirement names, the subject it narrows or reads from, and so on all the way back. A subject no requirement uses isn't listed.

Take this policy:

```yaml
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
- `from` says how the subject is found, as a [from line](#from-lines) is written. A `from` written as a line is printed the same way whatever spaces it had. One written as a list, in the [old syntax](#subjects-in-the-old-syntax), is printed as a sentence too: its path, then ` whose ` and its `applies_to` filters, sorted by name and joined with `and`. A [naming step](#naming-subjects) at the end of the path shows as `named by each of $params.suites` when its keys come from a ref, as `<each of "unit", "lint">` when they're listed, and as `<each as suite>` when it has none, since a `from` line has no way to write those two. A filter that can't be written as a sentence, like one with a custom operator or a substitute, shows as `<condition name>` so it's never left out, and an `applies_to` that isn't an object shows as `<invalid applies_to>`. A subject built on another with `of` starts with that subject's name. A subject without `from` reads the input field named like it. A `from` that is written wrong shows as `<invalid from>`.
- `identified_by` is the path of the subject's id, or `null` when it has none, and the whole subject is its id. A subject that narrows another has the id of the one it narrows. An id that is written wrong shows as `<invalid identified_by>`.
- `parts` lists every [part](#parts) the subject has, including the ones it keeps from a subject it narrows, by alias. Each is `{"from": ..., "identified_by": ...}`, with `from` written the way a sentence writes a path, so `"  dd.b "` is `dd.b` and `x[$params.k]` is `x named by $params.k`, and `identified_by` the path of the part's id or `null` when it has none. For the policy under [Parts](#parts) it is

  ```json
  {
    "coverage": {"from": "compliance_status.attestations_statuses.coverage-verification", "identified_by": "attestation_id"},
    "findings": {"from": "compliance_status.attestations_statuses.findings.attestation_data", "identified_by": null}
  }
  ```

  A part that is written wrong is listed as best it can be, with `<invalid from>` for a path that can't be read and `<invalid identified_by>` for an id that can't.

A subject that is written wrong still has its entry, so nothing disappears from the report. With this policy and the same input:

```yaml
subjects:
  deployment:
    from: [deployments]
    identified_by: [id]
    applies_to:
      is_prod: {op: equals, path: [environment], value: prod}
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
    "from": "deployments whose environment is \"prod\"",
    "identified_by": "id",
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

| Check           | One row per | Passes when                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `$well_formed`  | requirement | the requirement names a subject in `subjects`, the requirement and its subject have only the fields Ergo knows and they have the right types, it has at least one check, a valid `require`, a well written naming step if `from` has one, a `from` or `id` written as a sentence that can be read, no step in `from` or `id` that can't be a key, no number a 64-bit float can't hold in `from`, `id` or `min_subjects`, no set or key that isn't a string in `from` or `id` and no key that isn't a string in `checks` or `applies_to`, a name that's a string, and no check that's [written wrong](#basic-operators). This depends only on how the requirement and its subject are written, never on the input or the params. |
| `$min_subjects` | requirement | `from` leads to a list or an object, unless it ends with a `keys` step, and at least `min_subjects` subjects are left after the subject's conditions.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `$unique_ids`   | requirement | no two subjects share an id, counting the ones its conditions leave out.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `$applies`      | subject     | the subject passes its conditions, the `whose` of its from line or its `applies_to`. These rows only exist when the subject has conditions.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

The `$well_formed` expression is `count(problems) == 0`. The problems are the inputs below, one for each check or field that's written wrong, so a requirement that's written correctly has none.

The examples below use the [old syntax](#the-old-syntax), which can go wrong in more ways. A sentence that can't be read gets an input the same way, like `{"name": "checks.approved", "value": ["doesn't parse"]}`.

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
  { "name": "subjects.deployment.from", "value": ["not a list or a string"] }
]
```

| Field                                          | What's wrong                                                                                                                                                                       |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| any field Ergo doesn't know                    | `unknown field`                                                                                                                                                                    |
| `checks`                                       | `not an object`, `holds a key that isn't a string`, `missing`, `empty`                                                                                                             |
| `require`                                      | `neither every nor some`                                                                                                                                                           |
| `min_subjects`                                 | `not a whole number of 0 or more`, `number out of range`                                                                                                                           |
| `subject`                                      | `missing`, `empty or not a string`, `not in subjects`                                                                                                                              |
| `subjects`                                     | `not an object`                                                                                                                                                                    |
| `subjects.deployment`                          | `not an object`                                                                                                                                                                    |
| `subjects.deployment.applies_to`               | `not an object`, `holds a key that isn't a string`                                                                                                                                 |
| `subjects.deployment.from`, `...identified_by` | `not a list`, `step that can't be a key`, `number out of range`, `holds a set`, `holds a key that isn't a string`                                                                  |
| `subjects.deployment.from`                     | `object step before the last`, `object step without each_as`, `invalid alias`, `invalid keys`, `unknown field foo in naming step`                                                  |
| `subjects.deployment.identified_by`            | `ref inside where`, `literal inside where`                                                                                                                                         |
| `subjects.deployment.description`              | `not a string`                                                                                                                                                                     |
| `subjects.deployment.of`                       | `empty or not a string`, `not in subjects`, `leads to a loop`                                                                                                                      |
| `subjects.deployment.from`, `...identified_by` | `not allowed with of`                                                                                                                                                              |
| `subjects.deployment.applies_to.locked`        | `also a filter of a subject it builds on`                                                                                                                                          |
| `subjects.deployment.has`                      | `not an object`                                                                                                                                                                    |
| `subjects.deployment.has.coverage`             | `not a string or an object`, `missing from`, `unknown field foo`, `invalid from`, `invalid identified_by`, `from: ...`, `identified_by: ...`, `invalid alias`, `alias given twice` |

A policy written in Rego can use a key that isn't a string, like `true` or `1.5`. Ergo names it `<invalid key true>` or `<invalid key 1.5>`, so two such keys never share a name. A requirement whose own name isn't a string, like `1`, or every requirement of a policy written as a list, fails `$well_formed`, which then starts with `{"name": "requirement name", "value": ["not a string"]}`. The requirement is `not_met`, so the policy isn't compliant.

Their descriptions are plain sentences, like your own checks': `The requirement is written correctly`, `The in-scope deployment count is at least 1`, `Every deployment id is unique` and `The deployment is in scope`. The details are in `expression`, `inputs` and `cause`. `$min_subjects` names its input after what it counts, like `in-scope deployment count`: only the subjects left after the subject's conditions. With `min_subjects: 0` the count can't fail, so `$min_subjects` only checks that `from` can be read, and says so: `The deployment list can be read`, with the expression `deployments can be read`. A `from` that ends with a `keys` step keeps the count, because `from` isn't read there. `$unique_ids` lists the ids that more than one subject has, once each, under `repeated deployment ids`, sorted by how they're written as JSON, so `"b"` comes before `10`, and `10` before `3`. They use the subject's name as it's written, so they read right whatever the word's plural would be.

A subject that fails `$applies` gets no other rows, since it was never checked. But its `$applies` row stays, so you can see what was left out and why.

A subject is only out of scope when Ergo read a condition's fields and the values didn't match, so the row's cause is `value`. When a condition fails because a field it reads is missing, `null` or can't be found, Ergo can't tell whether the subject is in scope. Its `$applies` row then fails with that cause, the requirement isn't met, and the row shows up in the violations. This holds with `min_subjects: 0` too, so a missing field can't quietly make a requirement pass.

`exists` is the exception, because a missing or `null` field is exactly what it checks for. `whose lock_release exists` leaves out a package with no `lock_release`. A parent that can't hold the field, like `"build": "abc"` for `build.fingerprint`, or a subject that isn't an object, still fails the requirement.

With several conditions, the subject is only out of scope when every condition that failed did so with `value`. If one rules it out and another can't be read, the requirement fails, so missing data always shows. An `exists` that finds its field missing is the exception: it says on purpose that a missing field means out of scope, so it rules the subject out whatever the other conditions read. That lets a condition on the same field sit next to it. With this input:

```json
{"lockfiles": [{"name": "a", "status": "COMPLETE"}, {"name": "b"}, {"name": "c", "status": "PENDING"}]}
```

`from: lockfiles whose status exists and status is "COMPLETE"` keeps `a`, and leaves out `b` and `c`, both with cause `value`, although `status is "COMPLETE"` can't read `b`'s status.

The same holds for `applies_to` filters in the old syntax, with `present` in place of `exists`. A filter or a condition that's written wrong still fails the requirement. A substitute that isn't there doesn't count as unreadable, because substitutes are usually missing.

Together, these make sure that whenever a requirement isn't met, at least one row explains why.

### Row order

Rows always come in the same order, whatever order you wrote the policy in:

1. all the `$well_formed` rows, then all the `$min_subjects` rows, then all the `$unique_ids` rows, then all the `$applies` rows, then your own checks
2. within each group, requirements in name order
3. within a requirement, subjects in the order they appear in the input, or in key order when a [naming step](#naming-subjects) reads an object
4. within a subject, checks in name order

Patterns, options, selector fields and the keys of objects written in the policy are sorted in rendered expressions too. Names, keys and strings are sorted by Unicode code point, so `！` (U+FF01) comes before `😀` (U+1F600). JavaScript's default `sort()` puts them the other way round, so an implementation there needs to compare code points. So the same policy and the same input always produce exactly the same report, byte for byte once it's written as JSON the same way, which means you can hash it and compare hashes. Every number in the report is written in its plain form, as in expressions, wherever it came from: `1.50`, `-0.0` and `1e2` in the policy, the params or the input come out as `1.5`, `0` and `100`. Two things are left as they are. A number a 64-bit float can't hold, like `1e400` in the input, is copied as written. And a report holding something JSON can't, like a set from an input written in Rego or a requirement whose name isn't a string, is left as Ergo built it, so that its rows still name their requirement. `opa eval` sorts the keys. OPA's JavaScript runtime for Wasm doesn't, and it reads the report into JavaScript numbers, which writes a very large or very small one with an exponent: `1e21` and `0.0000001` come out as `1e+21` and `1e-7`. So to compare reports across runtimes, write each one with the [JSON Canonicalization Scheme (RFC 8785)](https://www.rfc-editor.org/rfc/rfc8785) before hashing: it sorts keys and writes numbers the way JavaScript does.

## Causes

Every row has a `cause`. A missing field, a field set to `null`, and a selector that matched nothing all show up as `null` in `inputs`, but they're different problems with different fixes. The cause tells them apart.

| `cause`         | Meaning                                                                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `satisfied`     | The check passed.                                                                                                                                                        |
| `substituted`   | The check failed, but its substitute passed.                                                                                                                             |
| `ill_formed`    | The check is written wrong, so it can't be run. `$well_formed` fails too.                                                                                                |
| `not_an_object` | The subject isn't an object, so it has no fields.                                                                                                                        |
| `ambiguous`     | A selector matched more than one item, or another item ties with the one a `for` line picks `sorted by` a field.                                                         |
| `unmatched`     | A selector matched nothing, although the list was there.                                                                                                                 |
| `unusable`      | A value the check reads is there, but it's not the kind the check needs, like a string for `range`, a string where a path needs an object, or a param of the wrong type. |
| `absent`        | A field the check reads isn't there.                                                                                                                                     |
| `null`          | A field the check reads is there, but `null`.                                                                                                                            |
| `value`         | Everything was read fine. The values just don't pass.                                                                                                                    |

When the input or the params hold something JSON can't, every check on a subject, every `$applies` row and every `$min_subjects` row fails as `unusable` (see [Failing closed](#failing-closed)).

When a check reads several fields, the row shows the first cause in this table's order. An ambiguous selector matters more than any value, because it means the policy can't even tell what it's looking at.

- For `every` and `some`, and `all` and `any`, a list that isn't there gives `absent`, and one that isn't a list gives `unusable`. An empty list gives `value`, since it was read fine and just has nothing in it. Otherwise the cause is the first, in this table's order, among the items that failed. So when one approver is a bot and another has no `username`, a check that some approver isn't a bot fails as `absent`, because the second one might not be. An `any_of` works the same way across its options, and so does `each` across its inner lists.
- For a custom operator, the cause is worked out from its `inputs`, or from its `path` if it has no `inputs`. With neither, the cause is always `value`.
- A built-in operator can have `inputs` too, to choose what its row shows, but its cause still comes from what the check reads. So `{"op": "equals", "path": ["a"], "value": 1, "inputs": [["b"]]}` fails as `absent` when `a` is missing, whatever `b` holds.
- `$well_formed` and `$min_subjects` don't read the subject, so their cause is `satisfied` or `value`, except that `$min_subjects` fails as `absent`, `null` or `unusable` when a ref in `from` or `keys` can't be read, or when `from` doesn't lead to a list or an object. `$applies` reports the state of the fields read by the conditions that failed. Its `inputs` list each field its conditions read once, sorted by name, so two filters on `status` show `status` once. For example, a subject whose filter field is missing says `absent`, and that fails the requirement. A filter that's written wrong gives `ill_formed`, even when another filter rules the subject out, because the scope can't be trusted.

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

A violation of an `all` or `any` check, or of the `$min_subjects` row of a subject read with `every`, keeps its row's `failed_items`, and one of a check written as several sentences its `failed_assertions`.

It leaves out:

- rows that passed
- `$applies` rows with the cause `value`, since being out of scope isn't a problem. An `$applies` row that failed because a condition couldn't be read is kept.
- every row of a requirement whose `status` is `met` or `not_applicable`. Under `require: "some"`, other subjects can fail while the requirement still passes, and those failures aren't problems.

It keeps the rows of a requirement with any other `status`, or none. It keeps `$min_subjects` failures, because finding nothing to check is a problem, and `$well_formed` failures, because they mean the policy itself is broken.

It only reads the report, never the input or the policy. It returns a list in the same order as `results`, so two failures that look the same are both kept. And it returns data, not text, so you decide how to word your messages. A missing `description` or `expression` comes back as `""`.

To decide whether to allow something, use `report.compliant`, not whether `violations` is empty. The two are worked out separately, so a mistake in how you use violations can't let something through.

## Compiling to Wasm

Ergo runs in a policy compiled with `opa build -t wasm` and run with OPA's JavaScript runtime, `@open-policy-agent/opa-wasm`. Two built-ins are missing from that runtime, and you pass them in yourself, as the third argument to `loadPolicy`:

- `opa.runtime`, which every report reads for its `engine`. Without it, every report fails with `not implemented: built-in function`. Return what runs the policy, with the opa-wasm version you installed and, under `compiled_by`, the OPA that built the module, so the report can say so. `version` can be left out of either. `() => ({})` works too, and gives `runtime: null`.
- `time.parse_rfc3339_ns`, which `compare_time` uses on RFC 3339 strings. Without it, only a policy with such a check fails.

Ergo only passes it a time it has already checked: an uppercase `T` and `Z`, a date that exists and a year from 1678 to 2261. So it only has to turn that into nanoseconds since 1970, exactly. A JavaScript number can't hold that: today's are about 1.76×10¹⁸, where a number can only step by 256. So return the digits with `JSON.rawJSON` (Node 21 and later). This is the version Ergo's CI uses, and it gives the same nanoseconds as OPA on 16,922 generated timestamps, before and after 1970:

```js
const parseTime = (v) => {
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const runtime = () => ({ name: "opa-wasm", version: "1.10.0", compiled_by: { name: "opa", version: "1.20.2" } });

const policy = await loadPolicy(wasm, undefined, { "time.parse_rfc3339_ns": parseTime, "opa.runtime": runtime });
```

## Compiling a policy

**Experimental:** `ergo.compile` may change or go away in any version of Ergo.

`ergo.report` reads every sentence of the policy each time it runs. When the same policy runs many times, like in a test suite, you can do that once with `ergo.compile(policy)`, save what it returns as JSON, and pass that to `ergo.report` in place of the policy. The report is the same. This is Ergo's own step, not OPA's: OPA still compiles `ergo.rego` as usual.

Treat a compiled policy like a compiler's object file. Make it in the build that uses it, don't commit it, and make it again whenever the policy or your copy of `ergo.rego` changes. Its shape is Ergo's own and changes between versions, and Ergo doesn't check that a compiled policy matches the `ergo.rego` running it, or that nobody edited it, so a stale or edited one can give a wrong report. Don't edit it. One with a field missing or of the wrong type fails like a policy Ergo can't read, and compiling a compiled policy gives it back unchanged.

A `make` rule keeps it fresh, since it runs again when either file changes. With this `policy.yaml`:

```yaml
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
	  'json.marshal({"compiled_policy": data.ergo.compile({"subjects": data.subjects, "requirements": data.requirements})})' > $@
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
    "inputs": [{ "name": "approved_by", "value": "" }],
    "requirement": "approved_deploy",
    "subject": { "id": "d-2", "type": "deployment" }
  }
]
```

The input and the params are read on each run, so a compiled policy works with any of them. Put `compiled_policy.json` in `.gitignore`: a fresh clone gives files the time of checkout, so a committed one can look newer than an `ergo.rego` it doesn't match.

Compiling is part of `ergo.rego`, not of the [spec](spec/README.md), so other implementations of Ergo don't have it.

## Failing closed

Ergo fails a check whenever it can't be sure, instead of letting it pass. Rego doesn't do that by default in a few places, so these are handled on purpose. Some of them name the [operators](#operators) that sentences run as:

- A missing, `null` or wrong-typed field fails every operator, except `missing`, which passes on a missing or `null` field.
- `compare` needs both sides to exist and have the same type. In plain Rego, `null < 5` is true, so a missing field would otherwise pass a `lt` check. Ordering objects, lists or booleans fails too.
- `every`, `some` and `for` lines need non-empty lists, inner lists included. A policy that's fine with no items says so with `, if any,`.
- An alias given twice, or badly written, fails the check, so an inner alias can't quietly hide an outer one.
- A [part](#parts) that is missing, `null` or the wrong type fails a check exactly as the full path it stands for would, and a part that is written wrong, or has an alias another one has, fails `$well_formed` and is never read as an alias.
- A check that's written wrong, like an unknown `op` or `cmp`, fails `$well_formed`, and its rows fail with cause `ill_formed`, so a mistake in a subject's conditions can't rule every subject out.
- A value of the wrong kind, like a string where `range` needs a number, or a param of the wrong type, fails with cause `unusable`, so a condition can't rule a subject out on it.
- With several conditions, one that can't be read fails the requirement, even when another rules the subject out. The only condition that can rule a subject out regardless is an `exists` that found its field missing.
- `min_subjects` is 1 unless you say otherwise, so finding nothing fails. A `from` that leads nowhere, to `null` or to something that isn't a list or an object fails even with `min_subjects: 0`.
- A key listed in `keys` that the input doesn't have is still a subject, so it fails instead of being skipped.
- A subject whose conditions can't be read fails the requirement instead of being left out.
- A `ref` that can't be read fails the check, even for operators like `excludes` or `not_matches_any` that would pass on an empty value.
- A policy with no requirements, and a requirement with no checks, are never met.
- Ergo only reads what JSON can hold. Rego can build sets and object keys that aren't strings, but JSON and YAML can't, so Ergo turns both down and gives the same report however it's run. A set or such a key anywhere in the input or the params fails every check on a subject, every `$applies` row and every `$min_subjects` row with cause `unusable`, so even a requirement with no subjects isn't met. `$min_subjects` says why in its inputs, like `{"name": "$$input", "value": ["holds a set"]}`, or `$$params` for the params. In a policy, a requirement or check holding either one is [written wrong](#checks-ergo-adds), and so is a requirement whose name isn't a string. So when you build the input in Rego, make lists, `[x | ...]`, not sets, `{x | ...}`.
- A requirement that isn't an object, a field of the wrong type, or a field Ergo doesn't know, fails `$well_formed` and keeps its place in the report, so a typo in the policy can't make a requirement vanish.
- A malformed timestamp fails `compare_time` rather than stopping the whole evaluation with an error.
- Running OPA with `--strict-builtin-errors` gives the same report as running without it, because Ergo checks a value's type before it passes it to a built-in like `object.get` or `count`. A [custom operator](#custom-operators) is your own Rego, so it needs the same care if you use the flag.

## The old syntax

Before sentences, a check was an object with an `op` and the parameters that operator takes, and a path was a list of keys, like `{op: non_empty_string, path: [approved_by]}`. That still works, and the rest of this page describes it. But it's going away, on a date we'll announce well in advance. Move your policies to sentences before then.

Most sentences run as one of these operators, as the table in [Checks](#checks) shows, so the [operators](#operators) below also say exactly what those sentences check, and the report's rows for such a sentence are that operator's rows.

### Moving a policy to sentences

`ergo.as_sentences(policy)` rewrites a policy written with `op` as sentences, wherever a sentence says exactly the same. With this `policy.yaml`:

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

- A check or a subject is only rewritten when Ergo reads the sentence back into what was written, so the policy gives the same report verdicts. Anything else stays as it was, and still works.
- `all` and `any` stay, because `every` and `some` walk every list along their path where `all` and `any` read one, so a policy could pass where it failed. Custom operators, `any_of`, substitutes, `count`, `sum` and `add`, and checks with their own `expression` stay too.
- A subject's `applies_to` filters become its `whose` conditions only when they all can and none has a `description` or `meta`, which a condition has nowhere to keep. Their names are lost, since a condition has none.
- The checks of a subject read from another subject, like `from: artifact.pull_requests`, stay as they are, since a sentence there reads `artifact` as that subject.
- The comments of a YAML file are lost, since OPA reads it as data.

### Subjects in the old syntax

A subject can also use these fields:

| Field           | Meaning                                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------------------------ |
| `from`          | A [path](#paths) written as a list, like `[deployments]`. It can end with a [naming step](#naming-subjects). |
| `identified_by` | A path written as a list, like `[id]`.                                                                       |
| `applies_to`    | Named checks that pick which subjects are in scope. A subject must pass all of them.                         |
| `of`            | The name of another subject this one builds on.                                                              |

A subject with `applies_to` is written like this:

```yaml
deployment:
  from: [deployments]
  identified_by: [id]
  applies_to:
    is_prod: { op: equals, path: [environment], value: prod }
```

and gives the same report as `from: deployments whose environment is "prod"`, except that the `$applies` entry's `expression` is `environment == "prod"`. A filter that's [written wrong](#basic-operators) fails `$well_formed` on every requirement that names the subject, and every subject fails `$applies` with cause `ill_formed`, shown as `<invalid applies_to>`, and gets no other rows. So does an `applies_to` that isn't an object. A `from` or `id` written as a list is written wrong when a step can't be a key, when it has a badly written [naming step](#naming-subjects), or when a selector in `id` has a ref or `literal` deeper inside a `where` value than Ergo reads. `from: []` reads the whole input.

A subject with `of` reads `from` and `identified_by` from the subject it names, and keeps only the items that pass that subject's filters and its own. Everything else about it is its own: its rows and descriptions use its name. It reports what the same subject written out in full would, except that `$well_formed` names a problem, or a `from` with a [naming step](#naming-subjects), after the subject it's written in.

- A subject can build on one that builds on another, and so on. The chain ends at the one subject without `of`, which gives `from` and `identified_by`, and a subject keeps the items that pass the filters of every subject along its chain.
- A subject with `of` can't have its own `from` or `identified_by`. They fail as `not allowed with of`.
- A chain that comes back to a subject already in it, like a subject whose `of` names itself, never reaches `from`. It fails as `leads to a loop`.
- A filter name can only be used once along a chain, because one filter would hide the other. Using it again fails as `also a filter of a subject it builds on`.
- An `of` that isn't a name in `subjects` fails as `not in subjects`, and one that names something other than an object fails the way a requirement's `subject` does.
- Any of these fails `$well_formed` on every requirement that names a subject whose chain has it, and the requirement finds no subjects. A problem is named after the subject it's in, like `subjects.component.from`.
- A requirement can name the subject others build on too, like `component` to check every component.

### Paths

A path is a list of keys that Ergo follows one step at a time. `["release", "approver", "email"]` reads `release.approver.email`.

A key is a string, or a list index, which is a whole number of 0 or more, like `0` or `12`. Write an index as digits alone. `1.0` and `1e0` read the same item as `1`, because OPA and JavaScript can't always tell them apart, but they're harder to read. A string only picks a key of an object and a number only picks an item of a list, so `["a", "0"]` reads nothing when `a` is a list, and `["o", 0]` reads nothing when `o` is `{"0": "zero"}`. JavaScript reads both, so an implementation there has to check the type. A path that runs into something that can't hold its next key, like these, or a string, number or boolean where an object or list should be, fails its check with cause `unusable`, so `["pr", "state"]` on `"pr": "none"` isn't reported as a missing field. A parent that isn't there, or is `null`, is different: the field is just missing. A step that can't be a key, like `true`, `null`, a list, `-1` or `1.5`, can never read anything. So a check with one is written wrong: it fails `$well_formed`, its rows fail with cause `ill_formed`, even as a `present` filter, and the step is shown as `<invalid step>`. The same goes for the paths in a check's `inputs`. One in `from` or `id` fails `$well_formed`.

In expressions, `inputs`, `$refs` and `failed_items`, a path is named the way a [sentence](#checks) writes it. A name made of keys, positions and `named by` one key can be pasted into a sentence. Aliases from `each_as` or `as`, like `$pr.author`, selectors, `[]` lists and refs of more than one key can't, because sentences don't have those yet. A key is written as it is when it starts with an ASCII letter (`a` to `z` or `A` to `Z`) or `_`, and the rest is ASCII letters, digits, `_` and `-`. Any other key is quoted, so a key with a dot, a space, a `$` or an accented letter, one that starts with a digit or `-`, and the empty key are all written in quotes. So `["metadata", "labels", "app.kubernetes.io/name"]` is named `metadata.labels."app.kubernetes.io/name"`, and doesn't look like a path four keys deep, and `["x", "$b"]` is named `x."$b"`. A first key that's a word the sentences use, like `empty` or `a`, gets a dot in front: `.empty`. A path into the params or the input starts with `$params` or `$input`, like `$params.allowed`. A list index at the end of a path is written `item <n> of`, counting from 1, and one with more after it in brackets, counting from 0: `["xs", 1]` is `item 2 of xs`, `["xs", 1, "k"]` is `xs[1].k`, and the string key `["xs", "0"]` is `xs."0"`. A first step written as `{"literal": "$schema"}` is named `"$schema"`, so it doesn't look like an [alias](#naming-subjects). `from` takes no names and no `$$input`, so there a first key that starts with `$` is always quoted: `["$$input"]` is named `"$$input"`, and can't be mistaken for the whole input.

`from` is a path into the input. Every other path (`identified_by`, a check's `path`, `left` and `right`) is a path into one subject, unless it starts with [`$$input`](#reading-from-the-input) or an [alias](#naming-subjects).

An empty path, `[]`, reads the item itself. Use it inside `all` or `any` when the list holds plain values like strings, not objects:

```rego
"release_branches": {
	"op": "all",
	"path": ["branches"],
	"check": {"op": "matches_any", "path": [], "patterns": ["^main$", "^release/"]},
}
```

Ergo names the item after its list, so this renders as `every branches: branches[] matches one of ["^main$", "^release/"]`, and the row's input is `branches[]`. An empty `each` works the same way, for a list of lists.

An empty path also reads a subject that isn't an object, like each string of `"from": ["branches"]`. There, the item is named after `from` (`branches[]`), or `$input` when `from` is `[]`, because then the subject is the input and `["$$input"]` reads the same thing. That keeps it apart from a key called `input`, which is named `input`. `$min_subjects` names it the same way, as `count(matching($input))`, when `from` reads the whole input. Any other path on such a subject fails with cause `not_an_object`.

One step in a path can be a **selector** instead of a key. It picks the single item in a list (or an object's values) whose fields match:

```rego
"path": ["attestations", {"where": {"type": "pull_request"}}, "state"]
```

This reads the `state` of the attestation whose `type` is `pull_request`, and it works the same whether `attestations` is a list or an object keyed by name.

A selector must match exactly one item. If it matches none, or more than one, the check fails, and the row's cause says which (`unmatched` or `ambiguous`). An empty `where` matches nothing. A path can contain only one selector.

### Reading from the input

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
ergo.report({"packages": packages}, {"subjects": {"package": {"from": ["packages"], "identified_by": ["name"]}}, "requirements": {"licences": {
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
  "expression": "some licences: licences[] in $params.allowed_licences",
  "inputs": [
    { "name": "licences[]", "value": ["GPL-3.0"] },
    { "name": "$params.allowed_licences", "value": ["MIT", "Apache-2.0"] }
  ],
  "cause": "value",
  "failed_items": [{ "path": "item 1 of licences", "item": "item 1 of licences", "value": "GPL-3.0", "cause": "value" }]
}
```

A ref or a `literal` anywhere deeper inside a value, like `"value": [{"ref": [...]}]` or `"where": {"k": [{"literal": "a"}]}`, is written wrong, because Ergo wouldn't read it and would compare the object instead. To compare data that holds an object that only looks like a ref or a literal, wrap the whole value in a `literal`: `{"literal": [{"ref": [...]}]}`.

The expression says where the value comes from. What it was goes in the check's definition in the report, under `$refs`, once for the whole report and sorted by name, beside the literals the check compares against. The rows' `inputs` only hold what the check reads, like `licences[]` here, and `violations` adds the `$refs` back to each violation's `inputs`, as above. That keeps a record of what was compared, even when the params change between runs, without copying it into every row. A path that starts with `$$input` or `$$params` is something the check reads, so its value stays in the row.

#### Params in a path

In the old syntax, a path that starts with `$$params` reads the params, as `$params` does in a sentence, and `{"ref": ["$$params", ...]}` puts a param in place of a value. A `present` or `missing` check on a param works as `exists` and `does not exist` do in [Params](#params).

Some things worth knowing:

- A ref that leads nowhere, or to `null`, fails the check, with cause `absent` or `null`. That cause wins over anything the subject's own fields would give, because the check can't mean anything without the value. Ergo has no defaults, so put the value in the params.
- A ref must be a list that starts with `$$params` or `$$input`, and it can't contain a selector or another ref. Anything else is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and the expression and `inputs` show `<invalid ref>`.
- An object with a `ref` or `literal` key and any other key is a mistake, not a value, so it fails the check the same way. Otherwise a typo like `{"ref": [...], "note": "..."}` would be compared as an object, and `excludes` would pass.
- A value that is an object with a single `ref` or `literal` key would be read as one. Wrap it in `{"literal": ...}` to take it as written. Nothing inside a `literal` is read, so `{"literal": {"literal": 1}}` is the object `{"literal": 1}`.
- `from` already starts at the top of the input, so it doesn't take `$$input` or `$$params`. `"from": ["$$input", "packages"]` looks for a key called `$$input`, finds no subjects, and fails `$min_subjects`. A [ref step](#ref-steps) works in `from`, though.

#### Ref steps

A ref can also be one step of a path. It's replaced by the value it reads, which becomes the key for that step. This is how a key can come from the params:

```rego
"from": ["trail", "artifacts", {"ref": ["$$params", "artifact_name"]}],
"checks": {"attested": {
	"op": "equals",
	"path": ["attestations", {"ref": ["$$params", "attestation_name"]}, "status"],
	"value": "COMPLETE",
}},
```

With `artifact_name` set to `app` and `attestation_name` to `pull-request`, this reads `trail.artifacts.app.attestations.pull-request.status`. The expression shows where the key came from: `attestations named by $params.attestation_name.status == "COMPLETE"`, and the value used is recorded under `$refs`, like any ref.

A ref step works anywhere in any path: first, in the middle or last, after a name or `$$input`, before a selector, and in `from`, `identified_by`, `each`, `left` and `right`.

- The value must be a [key](#paths): a string, or a list index, which is a whole number of 0 or more. A ref that leads nowhere, to `null`, or to anything else, like a list, means the path can't be followed, so the check fails with cause `absent`, `null` or, for anything that isn't a key, `unusable`.
- In `from`, a ref step that can't be read fails `$min_subjects`, even with `min_subjects: 0`, because Ergo can't tell where the subjects would be. The `$min_subjects` row takes the ref's cause, and its definition records the ref under `$refs`, so the violation shows which param was missing.
- A `present` filter whose path has a ref step that can't be read doesn't rule subjects out. It fails the requirement, because the field it looked for is unknown, not missing.
- A ref step written with another key, like `{"ref": [...], "where": {...}}`, is a mistake, not a selector. It fails the check and shows as `[<invalid ref>]`. In `from`, it fails `$well_formed`.
- A ref's own path is read as written, so a ref inside a ref isn't followed.
- Some tools treat `$$` as an escape for `$`, like docker-compose and Make. A policy that passes through one of them reaches Ergo as `$input`, which is read as a [name](#naming-subjects). No subject is called `input`, so the check fails with cause `absent`.

### Naming subjects

`from` can end with a step that names each subject: `{"each_as": "name"}`, where `name` is an alias for the subject. A path that starts with `$name` then reads that subject.

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

The alias matters inside `all` and `any`, where paths start at each item of the list. `$name` reaches back to the subject, so an item can be compared with it. `as` gives the items of a list an alias the same way (see [Nesting](#nesting)):

```rego
"subjects": {"pull request": {
	"from": ["pull_requests", {"each_as": "pr"}],
	"identified_by": ["number"],
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
  "failed_items": [{ "path": "item 1 of approvers", "item": "item 1 of approvers", "value": { "username": "ann" }, "cause": "value" }]
}
```

If `author` were missing, the cause would be `absent`.

Some things worth knowing:

- The step must be the last one in `from`, and there can only be one. The name must be a string that doesn't start with `$` and isn't `params` or `input`, which would look like the params and the input in the report. `keys` must be a list, a `literal` holding a list, or a [`ref`](#reading-from-the-input), and a key in the list can't be a ref with another key beside it. A step with any other field, or one that breaks these rules, fails `$well_formed` and gives no subjects, so the requirement is never met, even with `min_subjects: 0`.
- Any other object in `from`, like a selector or a `literal`, fails `$well_formed` the same way. `from` has never read them, so a requirement with `min_subjects: 0` used to find nothing and pass.
- Keys are sorted and duplicates dropped, so the order you list them in doesn't change the report. If `from` doesn't lead to an object, every key is still a subject, and its checks fail as `absent` (or `value`, for a `present` check). An empty `keys` list gives no subjects, so `$min_subjects` fails.
- `keys` can come from the params: `"keys": {"ref": ["$$params", "required_suites"]}`. The list it reads works exactly like one written in the policy. A single key can be a ref too: `[{"ref": ["$$params", "suite"]}, "unit-test"]`, as can a `literal` like `{"literal": "$x"}`. If a ref can't be read, or reads the wrong type (anything but a list for the whole of `keys`, or a string or number for one key), there are no subjects and `$min_subjects` fails as `absent`, `null` or, for the wrong type, `unusable`, even with `min_subjects: 0`. A key is never just left out. The definition of `$min_subjects` records the ref under `$refs`.
- A subject from an object is identified by its key, even if the subject has `identified_by`. For a list, `identified_by` can start with the name, like `["$pr", "number"]`.
- An empty path is named after the subject's name (`$run`), not after `from`.
- A path that starts with a name nobody gave, like `["$runs", "result"]`, is written wrong: it fails `$well_formed`, and the check fails with cause `ill_formed`. That holds even when no subject is found, so a requirement can't pass by never running the check. To read a key that really starts with `$`, write it as `{"literal": "$schema"}`.
- A `ref` can't start with a name yet, only with `$$input`. `{"ref": ["$pr", "author"]}` fails the check and shows `<invalid ref>`.

### Operators

Every check has an `op` and the parameters that operator needs. A field the operator doesn't use is a mistake, so a typo like `valeu` is caught instead of ignored.

#### Basic operators

These read one or two fields of a subject.

| `op`               | Parameters                  | Passes when                                                                                                                                       |
| ------------------ | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `equals`           | `path`, `value`             | the field equals `value`. A field of another type fails as `unusable`, so `"1"` against `1` does.                                                 |
| `in`               | `path`, `values`            | the field is one of `values`, which all have one type, `null` aside. A field of another type fails as `unusable`, as for `equals`.                |
| `present`          | `path`                      | the field exists and isn't `null`. An empty string or `false` still counts as present.                                                            |
| `missing`          | `path`                      | the field isn't there, or is `null`.                                                                                                              |
| `non_empty_string` | `path`                      | the field is a string, and not `""`.                                                                                                              |
| `empty`            | `path`                      | the field is an empty list.                                                                                                                       |
| `matches_any`      | `path`, `patterns`          | the field is a string that matches at least one of the regular expressions.                                                                       |
| `not_matches_any`  | `path`, `patterns`          | the field is a string that matches none of them.                                                                                                  |
| `range`            | `path`, `min`, `max`        | the field is a number between `min` and `max`, both included.                                                                                     |
| `includes`         | `path`, `value` or `values` | the field is a list that contains `value`. With `values` in place of `value`, it contains every one of them.                                      |
| `excludes`         | `path`, `value` or `values` | the field is a list that doesn't contain `value`. With `values` in place of `value`, it contains none of them.                                    |
| `compare`          | `left`, `right`, `cmp`      | both sides can be read, have the same type, and `left cmp right` is true. A side is a field, a fixed value or a [derived value](#derived-values). |
| `compare_time`     | `left`, `right`, `cmp`      | both fields are timestamps in the same format (both RFC 3339 strings, both dates, or both numbers) and `left cmp right` is true.                  |

`cmp` is one of `eq`, `ne`, `gt`, `gte`, `lt` or `lte`.

Some things worth knowing:

- A check that's written wrong fails `$well_formed`, and its rows fail with cause `ill_formed`, whatever the subject holds. So in `applies_to` it fails the requirement instead of ruling every subject out. Written wrong means:
  - an `op` Ergo doesn't know, a missing `op`, or a missing parameter
  - a `cmp` that isn't in the list above
  - a `compare` side that isn't a path, a `literal` or a [derived value](#derived-values) written as below, or a `compare_time` side that isn't a path. The `$well_formed` row says `invalid left` or `invalid right`
  - a `within` that isn't a number of 0 or more, or that's on a `cmp` other than `eq`
  - `values` that isn't a list, an empty `values` for `includes` or `excludes`, both `value` and `values`, a `min` or `max` that isn't a number, a `min` above `max`, or `patterns` that isn't a list of valid regular expressions
  - a `path`, an `each` or, on other operators than `compare` and `compare_time`, a `left` or `right` that isn't a list, even a string like `"state"` that names one key, or `as` or `each` on an operator other than `all` or `any`. The `$well_formed` row says `path not a list` (or `each not a list`), and the check's row has no `inputs`
  - a step that can't be a [key](#paths), a number out of range, a badly written [ref](#reading-from-the-input), a ref or `literal` deeper inside a value than Ergo reads, or a path that starts with a [name](#naming-subjects) nothing gave
  - an `all` or `any` [nested](#nesting) too deep, or an alias given twice or badly written
  - a check that isn't an object, or one where it can't go, like a custom operator inside `all`
  - a field its op doesn't use, like `valeu` or `descripton`. Besides its own parameters, any check can have `description`, `meta`, `expression`, `substitute` and `inputs`. A [custom operator](#custom-operators) can have any fields.
  - a set, or an object key that isn't a string, anywhere in the check or in a selector in `from` or `identified_by`. Rego can write both, but JSON can't hold either. The `$well_formed` row shows `holds a set` or `holds a key that isn't a string`. The expression writes such a key as `"<invalid key>"`, so `"value": {10: "a", "10": "b"}` on `x` shows as `x == {"10": "b", "<invalid key>": "a"}`, the same in every runtime.
  - a `description` that isn't a string, or a `meta` that isn't an object or holds something JSON can't, as on a [requirement](#requirements). A `null` one counts as not written. This holds for a custom operator too, and for a check inside another one. The expression doesn't show it, but the `$well_formed` row does, as `invalid description`, `invalid meta`, `meta holds a set` or `meta holds a key that isn't a string`. A number in `meta` that's out of range shows as `number out of range`.

  The expression says what's wrong: `<unknown op nope>`, `<missing op>`, `<invalid check>` for a check that isn't an object, `<even can't go here>` for a check where it can't go, `<missing value>` in place of a missing parameter, as in `state == <missing value>`, or `<invalid path>` in place of a `path`, `left` or `right` that isn't a list, as in `<invalid path> is present`. A `compare` or `compare_time` side that isn't valid shows as `<invalid left>` or `<invalid right>` in its place, as in `<invalid left> lt b`. A check that's written wrong reads nothing, so its `inputs` are empty. The [`$well_formed` row](#checks-ergo-adds) lists each check that's written wrong, and what's wrong with it.

  A [`ref`](#reading-from-the-input) that reads the wrong kind of value from the params, like `values` read from a param that holds `3`, or an empty list read as the `values` of `includes` or `excludes`, isn't a mistake in the policy, so it doesn't fail `$well_formed`. The check fails with cause `unusable`.
- A field with the wrong kind of value for the operator fails with cause `unusable`, not `value`: a field that isn't a number for `range`, isn't a string for `matches_any` or `not_matches_any`, or isn't a list for `includes`, `excludes`, `all` or `any`, two fields of different types for `compare`, a field of another type than the value for `equals` or the values for `in` and `not_in`, a list whose items have another type than the value or values for `includes` and `excludes`, or anything but two timestamps in the same format for `compare_time`. So a filter fails the requirement instead of quietly ruling the subject out: with `ignore_expires_exists: "false"`, `vuln whose ignore_expires_exists is false` fails it, where a string that isn't `false` would have left the vuln out. `non_empty_string` is different, and fails with `value` on a number, since checking the type is its job.
- `present` on a missing or `null` field fails with cause `value`, not `absent`: whether the field is there is the question it asks, so "it isn't" is a sound answer. A field whose parent isn't there, or is `null`, is missing too, so `build.fingerprint` is missing when there's no `build`, and so is a field under a [selector](#paths) when the list it selects from isn't there or is `null`. A parent that can't hold the field still fails with cause `unusable`, as for every [path](#paths). In an `any_of` option, a `present` check that finds its field missing settles the option as `value`, even when the option's other checks can't read that field.
- `missing` is the opposite of `present`: it passes where `present` fails with cause `value`, fails with `value` where `present` passes, and otherwise fails with the same cause as `present`. So a field that's there fails it whatever it holds, `false` and `""` included, and a selector that matches nothing in a list that's there fails it as `unmatched`. To let a missing field pass a check, or keep a subject with no such field in scope, put `missing` in its own [`any_of`](#any_of) option.
- `empty` only passes on an empty list. A missing list fails with cause `absent`, a `null` one with `null`, and anything else with `unusable`, an empty string or object included. It's for saying that no items is fine where [`all` or `any`](#all-and-any) would fail.
- `equals` with `"value": null` only passes when the field is there and set to `null`. A missing field doesn't count.
- `range` needs `min` and `max` to be numbers. A string like `"3"` fails the check, because Rego puts every number before every string, so `5 <= "3"` would be true.
- `in` fails when the field is missing or `null`, even if `values` contains `null`. To check that a field is `null`, use `equals` with `"value": null`. `in` also fails when `values` is empty, missing, or not a list. The expression then shows `id in <missing values>` or `id in <invalid values>` rather than a list.
- `includes` and `excludes` take `value` or `values`. Giving both, or neither, is written wrong, and the expression shows `not contains(xs, <both value and values>)` or `contains(xs, <missing value or values>)`. `values` works as one check per value: `"op": "excludes", "values": ["nuts", "garlic"]` passes when neither is in the list, and `includes` with the same `values` passes when both are. The expression shows `contains_none(allergens, ["garlic", "nuts"])` or `contains_all(allergens, ["garlic", "nuts"])`. An empty `values` would pass every list, so it's written wrong.
- Each item in `values`, for `in` too, and in `patterns` can be a [`ref`](#reading-from-the-input) or a `literal`, as `value` can, so `"values": [{"ref": ["$$params", "nut"]}, "garlic"]` reads the param, and a param that's missing or `null` fails the check instead of being skipped. A ref in `patterns` that reads something other than a valid regular expression fails the check with cause `unusable`. A list read through a `ref`, or wrapped in a `literal`, is data, so an item in it that looks like a ref is compared as it is. A `value` that's a list is still one value, so `"value": ["a", "b"]` looks for the list `["a", "b"]` inside the field. Write separate checks instead when you want a row and a description for each value.
- To check that a list holds at least one of several values, use [`any`](#all-and-any) with `in`: `{"op": "any", "path": ["allergens"], "check": {"op": "in", "path": [], "values": ["nuts", "garlic"]}}`. Its expression is `some allergens: allergens[] in ["garlic", "nuts"]`. Keep this in mind in `applies_to`, where `includes` with `values` only keeps subjects that have every one of them.
- `compare` and `compare_time` compare two fields of the same subject. A `compare` side can also be a fixed value, written `{"literal": 1}`, or a [derived value](#derived-values), like the length of a list.
- `compare` with `lt`, `lte`, `gt` or `gte` needs both fields to be numbers. Ordering strings, objects, lists or booleans fails with cause `unusable`. Strings aren't ordered because a number held as a string, like `"9"`, would come after `"80"`, and to order times use `compare_time`. Objects, lists and booleans aren't because Rego's order for them means nothing in a policy: `{"name": "ann"}` comes before `{"owner": "bob"}` only because `name` sorts before `owner`. You'd usually hit this by leaving the field off the end of a path. `eq` and `ne` work on any type. A substitute that orders strings, objects, lists or booleans gives its check the same cause, and so does an item inside `all` or `any`.
- `compare_time` never converts between formats, so a number against a string fails as `unusable`. With numbers, Ergo can't tell seconds from milliseconds, so make sure both sides use the same unit.
- An RFC 3339 string needs an uppercase `T` and `Z`, a date that exists, and a year from 1678 to 2261, which keeps its nanoseconds since 1970 inside a 64-bit integer. Anything else fails `compare_time` as `unusable`, so `2024-02-30T00:00:00Z` isn't read as 1 March, and `2024-01-01t00:00:00z` isn't read at all.
- Patterns in `matches_any` and `not_matches_any` aren't anchored: `svc_` matches `my_svc_account`. Use `^` and `$` when you need a full match. A pattern that isn't a string, or isn't a valid regular expression, fails either operator, even when another pattern matches. With an empty `patterns` list, `matches_any` fails and `not_matches_any` passes. When `patterns` isn't a list, both fail and the expression shows `author matches one of <invalid patterns>` or `author matches none of <invalid patterns>`. When it's missing, the expression shows `<missing patterns>` instead.

These two are useful in `applies_to`, for example to leave bot accounts out of a review rule. If the author field is missing, Ergo can't tell whether the subject is in scope, so the requirement fails. See [Checks Ergo adds](#checks-ergo-adds).

#### Derived values

A side of `compare` can be worked out from the subject instead of read from one field. That's how a check says "at least one persona ran", "the findings from Claude match the number it reported" or "the stage costs add up to the total":

| Side                              | Value                                                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `{"literal": 1}`                  | the value as written                                                                                            |
| `{"count": path}`                 | the number of items in the list at `path`                                                                       |
| `{"count": path, "where": check}` | the number of those items that pass `check`                                                                     |
| `{"sum": path, "each": path}`     | the numbers at `each` in every item of the list at `path`, added up. With `where`, only the items that pass it. |
| `{"add": [side, ...]}`            | the sides added up. Each one is a path, a number written as a `literal`, a `count` or a `sum`.                  |

`compare` also takes `within` with `cmp: eq`, so two numbers pass when they're at most that far apart. Money and durations rarely add up to the exact cent.

With this input:

```json
{
  "reviews": [
    {
      "id": "pr-7",
      "personas_ran": ["security"],
      "findings": [{ "source": "claude" }, { "source": "gpt" }, { "source": "claude" }],
      "claude_found": 2,
      "stages": [{ "kind": "model", "usd": 0.5 }, { "kind": "model", "usd": 0.25 }, { "kind": "tool", "usd": 0 }],
      "total_usd": 0.76
    }
  ]
}
```

and these checks on a `review` subject read from `reviews`:

```yaml
some_persona:
  op: compare
  left: { count: [personas_ran] }
  right: { literal: 1 }
  cmp: gte
claude_findings:
  op: compare
  left: { count: [findings], where: { op: equals, path: [source], value: claude } }
  right: [claude_found]
  cmp: eq
costs_add_up:
  op: compare
  left: { sum: [stages], each: [usd], where: { op: equals, path: [kind], value: model } }
  right: [total_usd]
  cmp: eq
  within: 0.01
```

all three pass. Each row shows the value Ergo worked out, named after the side, beside the list it came from:

| check             | expression                                                          | inputs                                                                                                |
| ----------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `some_persona`    | `count(personas_ran) gte 1`                                         | `count(personas_ran) = 1`, `personas_ran = ["security"]`                                              |
| `claude_findings` | `count(findings where source == "claude") eq claude_found`          | `count(findings where source == "claude") = 2`, `findings = [...]`, `claude_found = 2`                |
| `costs_add_up`    | `sum(stages[].usd where kind == "model") eq total_usd, within 0.01` | `sum(stages[].usd where kind == "model") = 0.75`, `stages[].usd = [0.5, 0.25, 0]`, `total_usd = 0.76` |

Some things worth knowing:

- A list that isn't there fails the check as `absent`, a `null` one as `null`, and anything that isn't a list as `unusable`. A number to add that isn't a number, like `"0.5"`, fails it as `unusable` too, and so does a `within` comparison where either side isn't a number.
- An item that `where` can't decide about doesn't just go uncounted. If the second finding above had no `source`, Ergo couldn't tell whether it came from Claude, so the check would fail as `absent`, with `count(findings where source == "claude") = null`. A `present` condition is the exception, as everywhere: a missing field is its answer.
- `where` is one [basic operator](#basic-operators), without a substitute. Its paths start at each item, like the inner check of `all`. It can't be `all`, `any` or `any_of`, and a check inside it that's written wrong makes the whole check written wrong.
- Derived values only go in a check of their own, a filter or a substitute, not inside `all`, `any` or `any_of`. A `literal` side can go anywhere a `compare` can.
- Paths in a derived value read like any other: they can start with `$$input`, `$$params` or an [alias](#naming-subjects).

#### `all` and `any`

These apply a check to each item of a list inside the subject.

| `op`  | Parameters                                          | Passes when                                                |
| ----- | --------------------------------------------------- | ---------------------------------------------------------- |
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

This reads as "every commit of every pull request is signed" (Ergo renders it as `every pull_requests[].commits: signed == true`). Every inner list must exist and have at least one item. If one pull request has no `commits`, the check fails, rather than being decided by the other pull requests alone.

The inner `check` can be a basic operator, an `any_of`, or another `all` or `any`.

##### Nesting

An `all` or `any` inside another one checks a list for each item of the outer list. `as` gives the outer item an alias, so the inner check can still reach it once its paths start somewhere else. Say a pull request needs an approval given after its last commit:

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
	"identified_by": ["number"],
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
  "failed_items": [{ "path": "item 1 of approvers", "item": "item 1 of approvers", "value": { "username": "bob", "timestamp": "2026-10-01T11:00:00Z" }, "cause": "value" }]
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

- `as` takes the same aliases as a [naming step](#naming-subjects): a string that doesn't start with `$` and isn't `params` or `input`. Without `each`, `$approver` reads the same as a path inside the item, so `as` only matters for a check nested inside. With `each`, it names the inner item.
- An alias can only be given once along a chain of checks. `as` with an alias that `from` or an outer check already gave is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and it shows as `<alias given twice>`. A badly written alias fails the same way and shows as `<invalid alias>`. The cause isn't `value`, so a filter written like this fails the requirement rather than ruling every subject out. Two separate checks can use the same alias.
- An alias given by `as` belongs to one item, so the row doesn't show it in its `inputs`. It still decides that item's cause, so an approver with no `timestamp` makes the check fail as `absent`. Paths that start with it are shown as paths inside the item, like `approvers[].timestamp`. That only holds inside the list check that gives the alias. Anywhere else, like a neighbouring `any_of` option, nothing gives it, so reading it there is written wrong and fails as `ill_formed`.
- Inner lists follow the same rules as outer ones. If an approver is tried against an empty or missing list of commits, that try fails.
- One level of nesting is as deep as it goes, because Rego doesn't allow recursion. An `any_of` doesn't count as a level, but an `all` or `any` in one of its options does. A third `all` or `any` is written wrong: it fails `$well_formed`, the check fails with cause `ill_formed`, and its expression shows `<nested too deep>`.

##### Which items failed

A row of an `all` or `any` check also has `failed_items`: the items that made the check fail, in list order, each with its path, item, cause and value. With this input:

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
  { "path": "item 2 of pull_requests[0].commits", "item": "item 2 of pull_requests[0].commits", "cause": "value", "value": { "sha": "a2", "signed": false } },
  { "path": "pull_requests[1].commits", "item": "pull_requests[1].commits", "cause": "absent", "value": null },
  { "path": "item 1 of pull_requests[2].commits", "item": "item 1 of pull_requests[2].commits", "cause": "absent", "value": { "sha": "c1" } }
]
```

`inputs` still shows the whole list, so the row records what was checked as well as what failed.

- `path` is written like a path in an expression, with the item's position added: `item 2 of pull_requests[0].commits` is the second commit of the first pull request. The last position is written `item <n> of`, counting from 1, and one further in is in brackets, counting from 0, as in [sentences](#checks). A path that starts with a name keeps it, as in `item 2 of $pr.commits`.
- `item` is the path of the list item the entry belongs to. Here every entry is a list item, so it's the same as `path`. It's there so a tool can find the item to show for any check, including [sentences](#checks), where an entry can point at a field inside the item.
- With `each`, an inner list that's missing, `null`, not a list or empty fails the check, so it's listed in place of its items, like `pull_requests[1].commits` above.
- An item whose field a `present` check finds missing or `null` is listed with cause `value`, the same as the row, because `present` read the field fine and found nothing there.
- When the check passes, it's `[]`. A passing `any` can have items that failed, but none of them is why the row came out the way it did.
- It's `[]` when the list itself can't be read, because there are no items to blame. The row's `cause` says what's wrong with the list.
- When the check is [written wrong](#basic-operators), every item, and every inner list that's missing, `null`, not a list or empty, is listed with cause `ill_formed`, because none of them could be checked. When a [`ref`](#reading-from-the-input) in it can't be read, every item that fails is listed with the ref's cause, as the row is.
- For a nested check, only the outer items are listed. An approver who approved before the last commit is listed with cause `value`, but not the commit.
- With a [substitute](#substitutes), it lists the items that failed the check itself, even when the substitute passed and the row with it.
- Only rows of `all` and `any` checks have it. Rows of `any_of` checks, `$applies` rows and rows of custom operators don't, even when an `all` or `any` sits inside them.

#### `any_of`

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
- An empty `options` is written wrong, and so is an empty option, an option written as an object instead of a list, or an `any_of` inside an option. Each fails `$well_formed`, and the check fails with cause `ill_formed`. The expression shows `one of: <empty options>`, `standard(<empty option>)` or `standard(<invalid option>)`, and `$well_formed` says `empty options`, `empty option standard` or `option standard not a list`.
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

### Substitutes

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
- When both fail, the row takes the worse of the two causes, except that the substitute's `absent`, `null` and `value` don't count, because substitutes are usually missing. So a substitute whose selector matches nothing or several items, whose path runs into the wrong kind of value, or that compares values of the wrong kind gives the row its cause, and in `applies_to` it stops the filter ruling the subject out.
- The row shows the check's inputs, then the substitute's, leaving out a path already shown.

A substitute with a wrong path looks just like a substitute whose evidence is missing: it's never used, and the main check keeps failing. Test each substitute with an input that should pass on it.
