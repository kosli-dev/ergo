# The ergo spec

Draft 0.1. ergo is three specs, and `ergo.rego` and the Rust port in `ports/rust` are implementations of them:

- [`policy/schema.json`](policy/schema.json) says what a policy looks like, as a JSON Schema.
- [`report/schema.json`](report/schema.json) says what a report looks like, as a JSON Schema.
- [`semantics.md`](semantics.md) says how a policy and an input give a report, as named rules.
- [`cases/`](cases) holds the cases that pin the rules down, one folder per topic.

When an implementation and the spec disagree, the implementation is wrong. A change to ergo's behaviour starts here, with the rule and its cases, and then goes into each implementation.

The spec only covers reading values, causes, expressions and the operators `present`, `missing`, `equals`, `in`, `non_empty_string`, `empty`, `range`, `matches_any`, `not_matches_any`, `includes`, `excludes`, `compare`, `compare_time`, `all`, `any` and `any_of` so far. [REFERENCE.md](../REFERENCE.md) still describes everything else. The spec will change while it's 0.x.

## Cases

A topic's `cases.json` holds a list of groups. A group has a `description`, a `policy`, `params` when the policy takes any, and its `cases`. Each case has:

- `description`: what should happen and why
- `rules`: the rules in `semantics.md` it tests
- `input`: the input to check
- `results`: the rows the report must have
- `status` (optional): the `status` some requirements must have, like `{"s": "not_applicable"}`
- `compliant` (optional): what `compliant` must be
- `expressions` (optional): the `expression` some checks must have, like `{"s": {"c": "x is present"}}`
- `refs` (optional): the `$refs` some checks must have, `[]` for none

Here is one case, from `cases/present`, whose group checks `{"op": "present", "path": ["x"]}`:

```json
{
  "description": "fails as value, not absent, when the field is missing",
  "rules": ["present.missing", "path.absent"],
  "input": {"things": [{"id": "t1"}]},
  "results": [
    {"requirement": "s", "subject": {"type": "thing", "id": "t1"}, "check": "c", "passed": false, "cause": "value", "inputs": [{"name": "x", "value": null}]}
  ]
}
```

`results` doesn't list every row, so a case only says what it's about. It's compared with the report's rows for the policy's own checks and `$applies`. The rows of `$well_formed`, `$min_subjects` and `$unique_ids` are only compared when `results` has a row for that check. Order matters, and key order in an object doesn't.

## Running the cases

`spec_test.rego` runs them against `ergo.rego`, and `ports/rust/tests/spec.rs` against the Rust port. Each has a list of the cases it's known to fail, which is where the implementation still differs from the spec. The test fails when another case fails, and also when a listed case passes, so the list stays true.

To list the cases `ergo.rego` fails:

```sh
opa eval -d . --ignore .github --format pretty 'data.spec_test.failures'
```

## How this differs from `conformance/`

`conformance/` holds whole reports, made by running `ergo.rego` and pulled out of its tests, so it says what `ergo.rego` does today, and catches changes to it. These cases are written by hand from the rules, so they say what ergo should do.
