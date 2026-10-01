# Release evidence

Two different kinds of thing are judged here, and conflating them is how a
policy ends up asserting something it cannot mean. An artifact is not a pull
request: they live at different paths, are identified differently, and a rule
about one says nothing about the other.

This file exists to hold that apart. Each requirement names the subject it is
about, and a rule can only reach the properties of its own subject — so a
misplaced field is an error at authoring time rather than a check that quietly
never passes.

## What gets judged

Nothing below is keyed to these heading names. A subject is recognised by the
shape of its own sentence, so call this section whatever your organisation calls
it, at whatever heading level suits the document.

### The artifact

An **artifact** is each of `artifacts`, identified by its `fingerprint`.

| Property    | Path          |
| ----------- | ------------- |
| fingerprint | `fingerprint` |
| build       | `build_url`   |

### The pull request

A **pull request** is each of `pull_requests`, identified by its `url`.

| Property    | Path                 |
| ----------- | -------------------- |
| state       | `state`              |
| base branch | `base_ref`           |
| commits     | `commits`            |
| verified    | `commits[].verified` |

Both declare a property called `state` in the real world; only one declares it
here, and that is the point — the names are scoped to their subject.

## The artifact is identifiable `artifact_identified`

For each **artifact**.

Must hold:

- `fingerprint_recorded` — the **fingerprint** must be a non-empty string.
  The artifact carries a fingerprint that review can be linked to

- `build_recorded` — the **build** must be a non-empty string.
  The build that produced the artifact is recorded

## The change was reviewed `change_reviewed`

For each **pull request**.

At least one **pull request** must be in scope.

In scope:

- `merged` — the **state** must be `MERGED`.

Must hold:

- `protected_branch` — the **base branch** must be `main`.
  Merged into the protected branch

- `commits_signed` — every **commit** must have a **verified** of `true`.
  Every commit in the pull request carries a verified signature
