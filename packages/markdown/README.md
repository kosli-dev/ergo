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

- From `batches`
- Identified by `id`

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- Subject `batch`

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
| `cake-batch-2026-03-18-001` | `baked right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-001` | `nut free`    | `true`  | `satisfied` |
| `cake-batch-2026-03-18-002` | `baked right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-002` | `nut free`    | `false` | `value`     |
| `cake-batch-2026-03-18-003` | `baked right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-003` | `nut free`    | `false` | `unusable`  |
| `cake-batch-2026-03-18-004` | `baked right` | `true`  | `satisfied` |
| `cake-batch-2026-03-18-004` | `nut free`    | `false` | `absent`    |

Batch 2 contains nuts, batch 3 lists its allergens as a string instead of a list, so Ergo can't read it, and batch 4 has no allergens at all. The [reference](../../REFERENCE.md#causes) explains each cause.

## How the document is read

The tool reads the headings, the lists and the `code spans`. Everything else is for people, and the tool leaves it alone: the last paragraph above, but also quotes, tables, code blocks and headings below `###`.

### The front matter

The block between the two `---` lines at the top holds `ergo_spec`, the version of Ergo's [spec](../../spec/README.md#versions) the policy is written for, and nothing else.

Params aren't part of a policy: they're the third argument of `ergo.report`. A policy that reads [params](../../REFERENCE.md#params) can say which ones in its text, like [any-of-licences](cases/any-of-licences/policy.ergo.md) does.

### The title and descriptions

`# Cake batches` is the document's title. It's for people, and the policy doesn't keep it. The paragraphs after it, up to the first heading, list, table or other block, are the policy's `description`. A document without a title can start with its description instead: the paragraphs at the top, before the first heading. The same goes for each subject and requirement: the paragraphs under its heading, up to its fields or `Checks:`, are its `description`. The paragraphs are joined with a blank line, so

```markdown
### Cake batch

Cakes are safe to eat.

A batch that can't show its allergens fails.

- Subject `batch`
```

gives `description: "Cakes are safe to eat.\n\nA batch that can't show its allergens fails."`. A paragraph after the fields is for people again.

### Subjects and requirements

Each `###` under `## Subjects` is a subject, and each `###` under `## Requirements` is a requirement. Their fields are bullets, each a name and the value in a code span, like ``- From `batches` ``:

| under a subject | under a requirement |
| --------------- | ------------------- |
| `From`          | `Subject`           |
| `Identified by` | `Require`           |
|                 | `Min subjects`      |

The name can have any capitals and a colon after it, so ``- from: `batches` `` works too. Under a subject or requirement, any bullet of words and one code span is a field, so a misspelt name like ``- Frm `batches` `` is a problem rather than a field that goes missing. Put words with code in them in a paragraph instead. `Min subjects` is a number, still in a code span: ``- Min subjects `1` ``. The [reference](../../REFERENCE.md) says what each field does. A bullet that starts with a field's name but isn't written this way, like `- from batches`, is a problem, so a field can't go missing unnoticed.

### Names

You don't write names: a subject, requirement, check or option is named by its heading or bold label, in lowercase, with each run of spaces made one and none at either end. Punctuation stays. So `### Cake batch` is the requirement `cake batch`, and under it

```markdown
- **Nut free**: Must not contain nut allergens.
  `allergens does not contain "nuts"`
```

is the check `nut free`. The report names them as written, as in this part of batch 2's row:

```json
{"requirement":"cake batch","check":"nut free","subject":{"id":"cake-batch-2026-03-18-002","type":"batch"},"passed":false,"cause":"value"}
```

A requirement names its subject the same way: ``- Subject `batch` `` for `### Batch`. Two names that come out the same in one place, like `**Nut free**` and `**nut  FREE**`, are a problem, and so is a name that starts with `$`, because Ergo's own rows, like `$well_formed`, start with it.

### Checks

After a paragraph that says `Checks:`, each item of the list is a check: a bold label, a colon, what the check means in words, then its [sentences](../../REFERENCE.md#checks), each in its own code span. The check passes when every sentence passes, like `baked right` above. The words are the check's `description` and can be left out. They can also run over more paragraphs in the bullet, before its first code span, and are joined with a blank line the same way:

```markdown
- **Nut free**: Must not contain nut allergens.

  Nuts are the allergen customers ask about most.

  `allergens does not contain "nuts"`
```

Without words:

```markdown
- **Approved**: `approved_by is a non-empty string`
```

A check anywhere else, like after a paragraph that ends the list, is a problem, so no check drops out of the policy unnoticed.

A code span that starts with `for ` is the check's `for` line, which names the items of a list so its sentences can read each one ([reference](../../REFERENCE.md#checks)):

```markdown
- **Peer approved**: Someone other than the author approved every pull request
  `for every pull_requests as pr, some pr.approvers as approver`
  `approver.state is "APPROVED"`
  `approver.username does not equal pr.author`
```

So a sentence that reads a field named `for` puts a dot in front of it: `.for is 1`.

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

The tool isn't published. Run `pnpm install` in `packages/`, then `node packages/markdown/src/cli.ts` in place of `ergo` below.

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
  cake batch:
    description: Cakes are safe to eat and baked right.
    subject: batch
    checks:
      nut free:
        description: Must not contain nut allergens.
        assert: allergens does not contain "nuts"
      baked right:
        description: Baked at 175–200°C for 25–40 minutes.
        assert:
          - bake.temp_c is between 175 and 200
          - bake.minutes is between 25 and 40
```

Save it next to `ergo.rego` and run it as the [getting started](../../README.md#getting-started) guide shows.

`ergo check` lists what the tool can't place, with the line, and fails when there's any. A check written without a bold label gives:

```sh
ergo check cakes.ergo.md
```

```
cakes.ergo.md:21: a check needs a bold label
```

The tool doesn't read the sentences. Ergo does, and a sentence written wrong shows up in the report's `$well_formed` row.

## Editing the policy instead

Someone who'd rather edit YAML can change the policy and write the change back into the document. `ergo apply` rewrites only what changed and leaves the rest of the file as it was, prose included.

Compile `cakes.ergo.md` from above to `policy.yaml`, then change `from: batches` to `from: today.batches` and add a check:

```yaml
      sealed:
        description: The box is sealed.
        assert: box.sealed is true
```

```sh
ergo apply cakes.ergo.md policy.yaml
```

```
rewrote batch.from
added check cake batch.sealed
```

and `cakes.ergo.md` now has:

```diff
-- From `batches`
+- From `today.batches`
```

```diff
 - **Baked right**: Baked at 175–200°C for 25–40 minutes.
   `bake.temp_c is between 175 and 200`
   `bake.minutes is between 25 and 40`
+- **Sealed**: The box is sealed.
+  `box.sealed is true`
```

A changed field keeps its place, and so does a changed check. When only a sentence changed, only its code span is rewritten, and a label or heading whose name didn't change stays as you wrote it. A new check goes at the end of its list, and a new subject or requirement at the end of its section. A check, subject or requirement that disappears with a new one in its place is renamed there.

When the document can't say what the policy says, `ergo apply` writes nothing and says why, with the path in the policy. With a part under `batch` and a check named `Sealed`:

```
subjects.batch.has: the Markdown can't hold parts yet: write this policy in YAML
requirements.cake batch.checks.Sealed: has upper case
not written
```

Before it writes, it compiles the new document and checks it gives back the policy you asked for. When it doesn't, it says `the Markdown wouldn't compile back to this policy` and writes nothing. That happens when removing a requirement's fields and checks would leave a paragraph of prose right under its heading, where it would become the requirement's description.

`ergo render` writes a new document from a policy that has none:

```sh
ergo render policy.yaml
```

```markdown
---
ergo_spec: v0.2
---

## Subjects

### Deployment

- From `deployments whose environment is "prod"`
- Identified by `id`

## Requirements

### Prod_deploy

Every production deployment is approved

- Subject `deployment`

Checks:

- **Approved**: Someone approved the deployment
  `approved_by is a non-empty string`
```

That's README's first policy, where `prod_deploy` is written with `_`, so its heading is too.

## Cases

Each folder in [`cases`](cases) is one example the tool must get right. It holds a `policy.ergo.md` and either:

- `policy.yaml`, the policy it must give, and when there's an input, `input.json`, `report.json` (the report `ergo.rego` gives on that policy and input) and `params.json` if the policy reads params;
- or `problems.json`, the problems it must list.
