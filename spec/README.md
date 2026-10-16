# The ergo spec

Draft 0.1. ergo is three specs, and `ergo.rego` is an implementation of them:

- [`semantics.md`](semantics.md) says what a check means, as named rules about a model of checks that doesn't depend on how they're written.
- [`syntax.md`](syntax.md) says how today's policies write checks, how they can be written wrong, and how the report shows paths and checks. A new way of writing checks would get a file like it, reading into the same model.
- [`sentences.md`](sentences.md) is a draft of the next way, from [#174](https://github.com/kosli-dev/ergo/issues/174): every check a one-line sentence like `approved_by is not empty`. [`sentences.abnf`](sentences.abnf) is its grammar, [`sentences-corpus.md`](sentences-corpus.md) every real check written that way, and [`sentences-findings.md`](sentences-findings.md) what writing them found. `ergo.rego` runs checks written as sentences, apart from the forms `sentences.md` lists as not run yet.
- [`policy/schema.json`](policy/schema.json) describes today's syntax as a JSON Schema.
- [`report/schema.json`](report/schema.json) says what a report looks like, as a JSON Schema.
- [`cases/`](cases) holds the cases that pin the rules down, one folder per topic.

When an implementation and the spec disagree, the implementation is wrong. A change to ergo's behaviour starts here, with the rule and its cases, and then goes into each implementation.

The spec covers reading values, causes, expressions, every built-in operator, requirements, scope, substitutes, statuses, row order and violations. How a subject's `from` names subjects (`each_as` and `keys`), subjects built on another with `of`, params passed in and values JSON can't hold are still described only in [REFERENCE.md](../REFERENCE.md). [OPEN.md](OPEN.md) lists the questions the spec hasn't settled. A subject's `from` waits for [#174](https://github.com/kosli-dev/ergo/issues/174) and [#113](https://github.com/kosli-dev/ergo/issues/113), which may change how it's written. The spec will change while it's 0.x.

## Cases

A topic's `cases.json` holds a list of groups. A group has a `description`, a `policy` with its `subjects` and `requirements`, `params` when the policy takes any, and its `cases`. Each case has:

- `description`: what should happen and why
- `rules`: the rules in `semantics.md` and `syntax.md` it tests
- `input`: the input to check
- `results`: the rows the report must have
- `status` (optional): the `status` some requirements must have, like `{"s": "not_applicable"}`
- `compliant` (optional): what `compliant` must be
- `expressions` (optional): the `expression` some checks must have, like `{"s": {"c": "x is present"}}`
- `refs` (optional): the `$refs` some checks must have, `[]` for none
- `requirements` (optional): fields some requirement entries must have, like `{"s": {"subjects": {"matching": 1, "total": 2}}}`. Only the fields listed are compared, and under `checks`, only the listed fields of the listed checks.
- `violations` (optional): the violations the report must give, all of them, in order
- `report` (optional): fields the report must have at its top, like `{"description": "", "meta": {}}`

Here is one case, from `cases/present`. Its group's policy has a `thing` subject read from `things`, and a requirement `s` that checks `{"op": "present", "path": ["x"]}`:

```json
{
  "subjects": {"thing": {"from": ["things"], "identified_by": ["id"]}},
  "requirements": {"s": {"subject": "thing", "checks": {"c": {"op": "present", "path": ["x"]}}}}
}
```

and this is the case:

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

## Checking the rules

`python3 spec/check_rules.py` fails when a case cites a rule that doesn't exist, or when no case cites a rule. A rule can go without cases only while it's listed under [Rules without cases](OPEN.md#rules-without-cases) in `OPEN.md`, and the script also fails when a rule on that list has a case or doesn't exist.

`spec/sentences-corpus.json` holds every sentence, `for` line and `from` line of `sentences-corpus.md` as a list, so that `ergo_test.rego` can parse each one. `python3 spec/sentences_corpus.py` writes it from the markdown, and `python3 spec/sentences_corpus.py --check` fails when it's out of date.

## Running the cases

`spec_test.rego` runs every case against `ergo.rego`, with one test for each folder of cases, so no test runs long enough to hit the timeout. A new folder needs its test added there too, and a test fails until it is. Its `known_differences` lists the cases an implementation is known to fail, which is where it still differs from the spec. A folder's test fails when another case in it fails, and also when a listed case passes, so the list stays true.

The cases in `cases/custom` use three custom operators that a runner has to supply, each failing when a field it reads isn't found:

- `even`, which reads `path` and passes when it holds an even whole number
- `multiple_of`, which reads `path` and takes `by`, and passes when the field is a whole multiple of `by`
- `both_present`, which reads every path in `paths` and passes when they're all found

`custom_op_test.rego` defines them for `ergo.rego`.

To list the cases `ergo.rego` fails:

```sh
opa eval -d . --ignore .github --format pretty 'data.spec_test.failures'
```
