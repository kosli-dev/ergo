This is the status of the two engines against the spec and against each other. A workflow rewrites everything below the line every night, so edit nothing here by hand.

`spec/OPEN.md` is the one list of the differences, with what differs, an example, its type and the step that fixes it. Each difference is sorted by what differs:

- type 1: a verdict differs, which means a check passes in one place and fails in another, `compliant` or a requirement's `status` differs, or a row is missing or extra. This is not acceptable. The nightly run fails on it.
- type 2: only a row's `cause` differs. Fix it as soon as possible.
- type 3: anything else, like a message, an entry or a location. Fix it when it's cheap.

The counts come from `.github/diff-types.py` (the engines against the spec cases) and `spec/sweep.py` (the Rego engine against the Rust engine over a grid and a list of pairs).

---
