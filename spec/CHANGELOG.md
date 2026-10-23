# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.1, not released yet

The first version. Policies need `ergo: v0.1` at their top, and reports get `ergo` and `engine` there.

- One version for the policy, the report and what one means for the other. A policy names it in `ergo`, and a report in `ergo` too.
- A report says what made it in `engine`.
- A report's hash is the SHA-256 of the report without `engine`, written as RFC 8785 says.
- The schemas have `$id`s under `https://ergo.kosli.com/spec/0.1/`.
