# Markdown policies

Write an ergo policy as a Markdown document instead of Rego. The `ergo` command compiles it into the requirements object that `ergo.report` takes, so the people who own a control can write and review it as prose, while ergo still gets an exact policy.

Here's the `prod_deploy` example from [`examples/prod_deploy/policy.ergo.md`](examples/prod_deploy/policy.ergo.md), with its rationale paragraphs left out:

```markdown
A **deployment** is each of `deployments`, identified by its `name`.

| Property    | Path                     |
| ----------- | ------------------------ |
| environment | `environment`            |
| approver    | `approved_by`            |
| CI checks   | `ci_checks`              |
| conclusion  | `ci_checks[].conclusion` |

## Every production deployment `prod_deploy`

In scope:

- `is_prod` — the **environment** must be `prod`.

Must hold:

- `approved` — the **approver** must be a non-empty string.
  A named approver signed off on the deployment.

- `ci_green` — every **CI check** must have a **conclusion** of `success`.
  Every CI check on the deployment passed.
```

## Getting started

You'll need Node 24 and, for `ergo explain`, OPA. From the repository root:

```sh
cd packages
corepack enable
pnpm install
cd markdown
pnpm ergo compile examples/prod_deploy/policy.ergo.md
```

```yaml
requirements:
  prod_deploy:
    subject_type: deployment
    from:
      - deployments
    id:
      - name
    applies_to:
      is_prod:
        op: equals
        path:
          - environment
        value: prod
    checks:
      approved:
        op: non_empty_string
        path:
          - approved_by
        description: A named approver signed off on the deployment
      ci_green:
        op: all
        path:
          - ci_checks
        check:
          op: equals
          path:
            - conclusion
          value: success
        description: Every CI check on the deployment passed
```

Write it to a file named `data.yaml` next to `ergo.rego`, and OPA loads it as `data.requirements`:

```sh
pnpm ergo compile examples/prod_deploy/policy.ergo.md -o policy/data.yaml
opa eval -d policy -i deployments.json --format=pretty 'data.ergo.violations(data.ergo.report(input, data.requirements))'
```

```json
[
  {
    "cause": "absent",
    "check": "approved",
    "description": "A named approver signed off on the deployment",
    "expression": "approved_by is a non-empty string",
    "inputs": [
      {
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

## Writing a policy

Most of the document is yours. Headings, paragraphs and lists are prose, and prose is never read as a rule. Only these shapes mean something:

| Written like this                                          | Becomes                         |
| ---------------------------------------------------------- | ------------------------------- |
| A **thing** is each of `path`, identified by its `id`.     | a subject: `subject_type`, `from`, `id` |
| a two-column table with paths in the second column         | the subject's properties        |
| a heading ending in a name in backticks                    | a requirement with that name    |
| In scope: followed by bullets                              | the requirement's `applies_to`  |
| Must hold: followed by bullets                             | the requirement's `checks`      |
| **Name** are …: followed by a list of patterns in backticks | a named list of patterns (a constant) |
| a named bullet outside any requirement                     | a substitute                    |

Bold means a declared property, constant or subject. Code means a path, a value or a name. A sentence only becomes a rule when it names a declared property, so rationale can say "must" as often as it likes.

### Properties

The table gives a path a name that reads well in a sentence. Paths are dotted, with two extras:

- `[]` marks a list. `ci_checks[].conclusion` is the `conclusion` of each CI check, so you can say "every **CI check**". Two `[]` give `all` with `each`.
- `[key=value]` picks one item from a list, like `attestations[type=pull_request].state`.

A rule that names a property the table doesn't declare is an error. Rules can use the singular when the table has the plural, and the other way round.

### Checks

Each bullet is one check: its name in backticks, a dash, the rule, then any number of sentences that become its `description`.

| The rule                                                  | `op`               |
| --------------------------------------------------------- | ------------------ |
| the **X** must be `value`                                 | `equals`           |
| the **X** must be present                                 | `present`          |
| the **X** must be a non-empty string                      | `non_empty_string` |
| the **X** must match one of `p`, `q` (or a **constant**)  | `matches_any`      |
| the **X** must match none of `p`, `q` (or a **constant**) | `not_matches_any`  |
| the **X** must be between `1` and `10`                    | `range`            |
| the **X** must include `value`                            | `includes`         |
| the **X** must not include `value`                        | `excludes`         |
| the **X** must be equal to / different from / greater than / at least / less than / at most the **Y** | `compare` |
| the **X** must be after / at or after / before / at or before the **Y** | `compare_time` |
| every **X** must …                                        | `all`              |
| at least one **X** must … (or some **X** must …)          | `any`              |

Inside `every` and `at least one`, say what each item must have: "every **CI check** must have a **conclusion** of `success`", or "… must have a **conclusion** that must match one of `^succ`".

`true`, `false`, `null` and numbers in backticks are read as those values, not as strings.

There's no sentence for `any_of` yet. A policy that needs it has to be written in Rego.

### Requirements

With one subject, every requirement is about it. With several, each requirement says which one: "For each **pull request**."

These lines change a requirement's defaults:

| Sentence                                     | Sets              |
| -------------------------------------------- | ----------------- |
| At least one **deployment** must be in scope. | `min_subjects: 1` |
| At least 3 **deployments** must be in scope.  | `min_subjects: 3` |
| No minimum.                                   | `min_subjects: 0` |
| One **deployment** must satisfy all of these. | `require: some`   |

### Substitutes, constants and extra inputs

- A named bullet outside any requirement declares a substitute. End a rule with "or else" and the substitute's name in backticks to use it.
- "**Bots** are authors matching any of:" followed by a list of patterns declares a constant, which a rule can name in place of its patterns.
- "Records the **pull requests**' `url`." adds an entry to the check's `inputs`, so its report row shows that field too.

### Custom operators

A custom operator gets a phrase of its own, described in a JSON file you pass with `--ops`:

```json
{
  "independently_approved": {
    "phrase": "be independently approved",
    "expression": "some approver is not an author",
    "inputs": [{"each": ["approvers"]}]
  }
}
```

Then "some **pull request** must be independently approved" compiles to that operator, with its `expression` and `inputs`. Add `, treating **constant** as explained` to pass a constant's patterns to it. The operator itself is Rego, as the [reference](../../REFERENCE.md#custom-operators) describes.

## Commands

| Command                                     | What it does                                                                 |
| ------------------------------------------- | ---------------------------------------------------------------------------- |
| `ergo compile <policy> [-o <file>]`         | Prints the requirements object, or writes it to a file.                      |
| `ergo check <policy> [<file>]`              | Fails if the committed object (by default `data.yaml` next to the policy) isn't what the policy compiles to. |
| `ergo explain <policy>`                     | Shows what each block of the document became, with the expression ergo will report. |
| `ergo lint <file>`                          | Checks any requirements object for unknown operators and missing or unexpected fields. |
| `ergo apply <policy> <file>`                | Writes an edited requirements object back into the Markdown.                 |

Run `ergo check` in CI. When someone edits the Markdown and forgets to recompile, or a change makes a check stop compiling, it says which check:

```
error: data.yaml: check "prod_deploy.ci_green" changed
```

An error in the document gives the line:

```
error: policy.ergo.md:29: approved: no operator matches "be signed"
```

### Editing the object instead

`ergo apply` takes an edited requirements object and rewrites only the bullets whose checks changed. Every paragraph around them is left exactly as it was.

```
  rewrote prod_deploy.ci_green
```

If a check uses a path the table doesn't name, it adds a row to the table. A renamed check keeps its place and its description. When an edit can't be written as prose, nothing is written:

```
error: policy.ergo.md: prod_deploy.approved: no prose writes the operator "any_of"
policy.ergo.md: not written
```

Some other things are refused for the same reason: a description ending in a full stop, a string like `"true"` that would read back as a boolean, and a path segment containing `.`, `[`, `]`, `|` or a backtick.

## Working on it

```sh
pnpm check
pnpm test
```

`pnpm check` type-checks the code and makes sure the examples' `data.yaml` files are up to date. `pnpm test` runs the TypeScript tests, fails if any line under `src` isn't reached, and runs the examples' Rego tests against `ergo.rego`.
