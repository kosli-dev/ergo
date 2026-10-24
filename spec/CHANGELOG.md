# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.1, not released yet

The first version. Policies need `ergo_spec: v0.1` at their top, and reports get `ergo` and `engine` there.

- One version for the policy, the report and what one means for the other. A policy names it in `ergo_spec`, and a report in `ergo`.
- A report says what made it in `engine`.
- A report's hash is the SHA-256 of the report without `engine`, written as RFC 8785 says.
- The schemas have `$id`s under `https://ergo.kosli.com/spec/0.1/`.
- Custom operators go, because a sentence can't call one. They come back once a definition format is built, see [OPEN.md](OPEN.md#custom-operators).
- Substitutes go, since an `any_of` of sentences says the same. Reports lose the `substituted` cause.
