# Changes to ergo.rego

Each release names the version of the spec it follows. The spec's own changes are in [spec/CHANGELOG.md](spec/CHANGELOG.md).

## 0.1.0

The first release. It follows spec 0.1.

Ergo turns a policy into a report. A policy is written in YAML, or in JSON or Rego if you prefer, and its checks are sentences, like `approved_by is a non-empty string`, and every run gives back one row per check, with what Ergo read and why it passed or failed. [What Ergo does](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/README.md#what-ergo-does) in the README lists the rest, and [Getting started](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/README.md#getting-started) runs a first policy.

- Policies are written as sentences, with `ergo_spec: v0.1` at their top. Ergo reads only that version, so a policy written for another one fails and says so.
- `ergo.report(input, policy, params)` gives the report, `ergo.violations(report)` gives the rows that failed and leaves out the ones that aren't problems, like a subject that was out of scope, and `ergo.as_sentences(policy)` rewrites a policy with checks written as `op` objects, the way Ergo read them before sentences, into sentences where it can. `ergo.compile` is there too, but experimental.
- Every report says which engine made it, under `engine`, and which spec version it follows, under `ergo`.
- The spec's JSON Schemas for a policy and a report are at `https://ergo.kosli.com/spec/0.1/policy.schema.json` and `https://ergo.kosli.com/spec/0.1/report.schema.json`.
- Ergo is one file, `ergo.rego`, with no dependencies. It needs OPA 1.20.1 or later.

If you used Ergo before this release, your policies are in an older shape that 0.1 doesn't read. [spec/CHANGELOG.md](https://github.com/kosli-dev/ergo/blob/rego-v0.1.0/spec/CHANGELOG.md) says what changed from that shape, and `ergo.as_sentences` rewrites what it can.
