# Ergo policies in Markdown

This package is an experiment, and its format may change.

An Ergo policy can be written as a Markdown document that people read like any other: a title, a few paragraphs, and lists of what must be true. A tool turns it into the same policy as a [YAML policy](../../README.md#2-write-a-policy), and `ergo.rego` runs that policy as it is.

The file's name ends in `.ergo.md`.

## A first policy

`cakes.ergo.md`:

````markdown
---
ergo_spec: v0.2
---

# Cake batches

Every batch that leaves the bakery is safe to eat and baked right.

## Subjects

### batch

A batch of cakes baked today.

- from: `batches`
- identified by: `id`

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- subject: `batch`

Checks:

- **Nut free**: Must not contain nut allergens.
  `allergens does not contain "nuts"`
- **Baked right**: Baked at 175–200°C for 25–40 minutes.
  `bake.temp_c is between 175 and 200`
  `bake.minutes is between 25 and 40`

We check the oven log rather than the recipe, because the recipe is what we
meant to do and the log is what happened.
````

With this input, `batches.json`:

```json
{
  "batches": [
    { "id": "cake-batch-2026-03-18-001", "allergens": ["milk", "eggs"], "bake": { "minutes": 32, "temp_c": 180 } },
    { "id": "cake-batch-2026-03-18-002", "allergens": ["nuts", "milk"], "bake": { "minutes": 32, "temp_c": 180 } },
    { "id": "cake-batch-2026-03-18-003", "allergens": "nuts", "bake": { "minutes": 32, "temp_c": 180 } },
    { "id": "cake-batch-2026-03-18-004", "bake": { "minutes": 32, "temp_c": 180 } }
  ]
}
```

the report isn't compliant, and its rows for the two checks are:

| batch                       | check         | passed  | cause       |
| --------------------------- | ------------- | ------- | ----------- |
| `cake-batch-2026-03-18-001` | `baked_right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-001` | `nut_free`    | `true`  | `satisfied` |
| `cake-batch-2026-03-18-002` | `baked_right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-002` | `nut_free`    | `false` | `value`     |
| `cake-batch-2026-03-18-003` | `baked_right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-003` | `nut_free`    | `false` | `unusable`  |
| `cake-batch-2026-03-18-004` | `baked_right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-004` | `nut_free`    | `false` | `absent`    |

Batch 2 contains nuts, batch 3 lists its allergens as a string instead of a list, so Ergo can't read it, and batch 4 has no allergens at all. The [reference](../../REFERENCE.md#causes) explains each cause.

## How the document is read

The tool reads the headings, the lists and the `code spans`. Everything else is for people, and the tool leaves it alone: the last paragraph above, but also quotes, tables, code blocks and headings below `###`.

### The front matter

The block between the two `---` lines at the top holds `ergo_spec`, the version of Ergo's [spec](../../spec/README.md#versions) the policy is written for, and nothing else.

Params aren't part of a policy: they're the third argument of `ergo.report`. A policy that reads [params](../../REFERENCE.md#params) can say which ones in its text, like [any-of-licences](cases/any-of-licences/policy.ergo.md) does.

### The title and descriptions

`# Cake batches` is the document's title. The first paragraph after it is the policy's `description`. The same goes for each subject and requirement: the first paragraph under its heading is its `description`.

### Subjects and requirements

Each `###` under `## Subjects` is a subject, and each `###` under `## Requirements` is a requirement. Their fields are bullets, each a name, a colon, and the value in a code span:

| under a subject      | under a requirement   |
| -------------------- | --------------------- |
| `from: ...`          | `subject: ...`        |
| `identified by: ...` | `require: ...`        |
|                      | `min subjects: ...`   |

`min subjects` is a number, still in a code span: ``min subjects: `1` ``. The [reference](../../REFERENCE.md) says what each field does.

### Names

You don't write names: the tool works them out from the headings and labels.

- A subject's name is its heading as written, spaces included: `### pull request` is `pull request`, and a requirement says ``subject: `pull request` ``.
- A requirement's name is its heading in lowercase, with every run of other characters than letters and digits turned into one `_`, and none at either end: `### Cake batch` is `cake_batch`, and `### Crème brûlée — the "recipe" check!` is `crème_brûlée_the_recipe_check`.
- A check's name is worked out the same way from its bold label: `**Nut free**` is `nut_free`, and `**Approved by 2+ people**` is `approved_by_2_people`.

The report uses these names. Two names that come out the same in one place, like `**Nut free**` and `**Nut-free!**` in one requirement, are a problem.

### Checks

After a paragraph that says `Checks:`, each item of the list is a check: a bold label, a colon, what the check means in words, then its [sentences](../../REFERENCE.md#checks), each in its own code span. The check passes when every sentence passes, like `baked_right` above. The words are the check's `description` and can be left out:

```markdown
- **Approved**: `approved_by is a non-empty string`
```

A code span that starts with `for ` is the check's `for` line, which names the items of a list so its sentences can read each one ([reference](../../REFERENCE.md#checks)):

```markdown
- **Peer approved**: Someone other than the author approved every pull request
  `for every pull_requests as pr, some pr.approvers as approver`
  `approver.state is "APPROVED"`
  `approver.username does not equal pr.author`
```

### Options

When a check can pass in more than one way, write a list of options under it in place of its sentences. The check passes when every sentence of one option passes. An option has a bold label, a colon and its sentences, without words of its own:

```markdown
- **Licence allowed**: The licence is allowed
  - **Declared**: `some licenses.license.id is in $params.allowed_licenses`
  - **Known**:
    `licenses does not exist`
    `$params.known_package_licenses named by name is in $params.allowed_licenses`
```

## Compile and check

<!-- rerun once packages/markdown/src exists: both outputs below are what the cases expect, not a real run yet -->

`ergo compile` prints the policy as YAML:

```sh
ergo compile cakes.ergo.md
```

```yaml
ergo_spec: v0.2
description: Every batch that leaves the bakery is safe to eat and baked right.
subjects:
  batch:
    description: A batch of cakes baked today.
    from: batches
    identified_by: id
requirements:
  cake_batch:
    description: Cakes are safe to eat and baked right.
    subject: batch
    checks:
      nut_free:
        description: Must not contain nut allergens.
        assert: allergens does not contain "nuts"
      baked_right:
        description: Baked at 175–200°C for 25–40 minutes.
        assert:
          - bake.temp_c is between 175 and 200
          - bake.minutes is between 25 and 40
```

Save it next to `ergo.rego` and run it as the [getting started](../../README.md#getting-started) guide shows.

`ergo check` lists what the tool can't place, with the line, and fails when there's any. A check written without a bold label gives:

```
line 21: a check needs a bold label
```

The tool doesn't read the sentences. Ergo does, and a sentence written wrong shows up in the report's `$well_formed` row.

## Cases

Each folder in [`cases`](cases) is one example the tool must get right. It holds a `policy.ergo.md` and either:

- `policy.yaml`, the policy it must give, and when there's an input, `input.json`, `report.json` (the report `ergo.rego` gives on that policy and input) and `params.json` if the policy reads params;
- or `problems.json`, the problems it must list.
