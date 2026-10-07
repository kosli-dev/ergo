# ergo conformance suite

These tests say what ergo reports for a given input, requirements and params. They're plain JSON, so any implementation of ergo can run them, whatever language it's written in. `ergo.rego` runs them with `conformance_test.rego`.

## Layout

Each topic is a folder holding one `cases.json`, like `operators/equals/cases.json`. A topic has a folder of its own because OPA names the data it loads after the folder, not the file.

A `cases.json` holds a list of groups. A group shares its requirements, and params when it has any, across its cases:

```json
{
  "description": "equals a string",
  "requirements": {
    "merged": {
      "subject_type": "pull request",
      "from": ["pull_requests"],
      "id": ["id"],
      "checks": {"is_merged": {"op": "equals", "path": ["state"], "value": "MERGED"}}
    }
  },
  "cases": [...]
}
```

Each case has a `description`, an `input` and the `report` ergo must give. When it also has `violations`, those must match what ergo's violations function gives for that report. Here is one case from that group, without its report:

```json
{
  "description": "fails as absent when the field is missing",
  "input": {"pull_requests": [{"id": "p1"}]},
  "violations": [
    {
      "cause": "absent",
      "check": "is_merged",
      "description": "",
      "expression": "state == \"MERGED\"",
      "inputs": [{"name": "state", "value": null}],
      "requirement": "merged",
      "subject": {"id": "p1", "type": "pull request"}
    }
  ]
}
```

A group with no `params` key is a policy run without params. ergo reports that the same way as params that aren't an object, like `"params": null`: every `$$params` read fails as `absent`.

## Writing a runner

For every `cases.json`, every group in it and every case in the group:

1. Build the report from the case's `input`, the group's `requirements`, and the group's `params` when it has them.
2. Compare it with the case's `report`.
3. If the case has `violations`, build the violations from that report and compare them too.

Compare parsed values, not text. Key order in an object doesn't matter, but order in a list does, because ergo sorts every list in the report and the suite pins that order.

Print the descriptions of the group and the case when one fails. They say what should happen and why.

Read numbers without rounding them. A parser that reads every number as a 64-bit float, like JavaScript's or `serde_json` without `arbitrary_precision`, turns `9007199254740993` into `9007199254740992`, and ergo treats a number that doesn't fit a float differently from one that does.

## Values JSON can't hold

The suite only covers JSON, but the language that calls ergo can usually pass it other things:

- Rego: sets, objects with keys that aren't strings, numbers too big for a float.
- JavaScript: `undefined`, `NaN`, `Infinity`, `-0`, `BigInt`, `Map`, `Date`.
- Python: tuples, `datetime`, `Decimal`, `NaN`, dicts with keys that aren't strings.

An implementation tests these itself, in its own tests, because no shared file can hold them.

`ergo.rego` doesn't treat them all the same way yet. `equals` passes when a set is compared with the same set, `in` passes when its `values` are a set, a path can step into `{1: "a"}` with the number `1`, and `present` passes on a set. But `includes` on a set and `any` over a set both fail as `unusable`.
