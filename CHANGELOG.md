# Changes to ergo.rego

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](spec/CHANGELOG.md).

## 0.1.0

The first release. It follows spec 0.1.

- Policies are written as sentences, with `ergo_spec: v0.1` at their top.
- `ergo.report`, `ergo.violations` and `ergo.as_sentences` are the functions to call, and `ergo.compile` is there too, but experimental.
