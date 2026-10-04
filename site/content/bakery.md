---
title: "The bakery example"
layout: bakery
robots: "noindex, nofollow"
sitemap:
  disable: true
---

In this introduction to ergo, we'll show how to define control decisions with rego and ergo through the example of a bakery allergen requirements (hat tip to Toby Weston for the original example). You'll learn how to validate cake batches against three compliance rules, produce explanatory reports of decisions.  No deep technical expertise or prior experience with rego is required.

We will look at the same policy written two ways, in plain Rego and with ergo, and compare thre results. You can follow along, the files are in [`examples/baking`](https://github.com/kosli-dev/ergo/tree/main/examples/baking).

## The policy

1. Must not contain nut allergens
2. Bake temperature 175–200°C inclusive
3. Bake time 25–40 minutes inclusive
4. Compliant only if all clauses pass

## The input file

Our input, [`batches.json`](https://github.com/kosli-dev/ergo/blob/main/examples/baking/batches.json) describes four batches of cake baking:

<div class="annotated">

{{< example "baking/batches.json" "json" "cake-batch-2026-03-18-001|A good batch" "cake-batch-2026-03-18-002|Nuts in the list" "cake-batch-2026-03-18-003|Nuts as a string" "cake-batch-2026-03-18-004|No allergen record" >}}

<ol class="notes">
<li><span class="notes__n mono">1</span><div><h4>A good batch</h4><p>Milk and eggs, baked at 180°C for 32 minutes. It passes every clause.</p></div></li>
<li><span class="notes__n mono">2</span><div><h4>Nuts in the list</h4><p>The allergens are a list, and <code>"nuts"</code> is in it. It should fail the nut check.</p></div></li>
<li><span class="notes__n mono">3</span><div><h4>Nuts as a string</h4><p>The allergens were recorded as the string <code>"nuts"</code> instead of a list. It contains nuts, so it should fail too.</p></div></li>
<li><span class="notes__n mono">4</span><div><h4>No allergen record</h4><p>There's no <code>allergens</code> field at all, so nobody knows whether it has nuts. It shouldn't pass either.</p></div></li>
</ol>

</div>

Only batch 001 should pass.

## The same policy in rego and <span class="ergo-mark">ergo</span>

<div class="side">
<div>

<p class="compare__label mono">In Rego</p>

[`plain-rego/baking.rego`](https://github.com/kosli-dev/ergo/blob/main/examples/baking/plain-rego/baking.rego)

{{< example "baking/plain-rego/baking.rego" "rego" >}}

This is the example's policy with three changes. It reads every batch in the list instead of a single one, so it can say which batch each result is about. The rules need `if`, because OPA 1.19 won't load them without it. And the `contains` helper is renamed `has`, because it clashes with a function OPA now has built in.

</div>
<div class="side--ergo">

<p class="compare__label mono">with <span class="ergo-mark">ergo</span></p>

[`ergo/baking.yaml`](https://github.com/kosli-dev/ergo/blob/main/examples/baking/ergo/baking.yaml)

{{< example "baking/ergo/baking.yaml" "yaml" >}}

[`ergo/baking.rego`](https://github.com/kosli-dev/ergo/blob/main/examples/baking/ergo/baking.rego), which runs it:

{{< example "baking/ergo/baking.rego" "rego" >}}

The requirements are plain data, so they can live in YAML. Each clause becomes a check, with the clause's own words as its `description`. Clause 4 needs nothing: a requirement passes only when every check passes, unless you say otherwise.

</div>
</div>

## What plain Rego outputs

```sh
opa eval -d examples/baking/plain-rego -i examples/baking/batches.json -f pretty 'data.baking.batches'
```

<div class="annotated">

{{< code "json" "cake-batch-2026-03-18-001|passes, but says nothing more" "cake-batch-2026-03-18-002|fails, but not why" "cake-batch-2026-03-18-003|has nuts, but passes" "cake-batch-2026-03-18-004|looks just like 002" >}}
{
  "cake-batch-2026-03-18-001": {
    "compliant": true,
    "nut_free": true,
    "temp_ok": true,
    "time_ok": true
  },
  "cake-batch-2026-03-18-002": {
    "compliant": false,
    "nut_free": false,
    "temp_ok": true,
    "time_ok": true
  },
  "cake-batch-2026-03-18-003": {
    "compliant": true,
    "nut_free": true,
    "temp_ok": true,
    "time_ok": true
  },
  "cake-batch-2026-03-18-004": {
    "compliant": false,
    "nut_free": false,
    "temp_ok": true,
    "time_ok": true
  }
}
{{< /code >}}

<ol class="notes">
<li><span class="notes__n mono">1</span><div><h4>Passes, but no workings</h4><p>The result returns<code>true</code>, but nothing else. The output doesn't say what was evaluated, so there's nothing to inspect about the decision.</p></div></li>
<li><span class="notes__n mono">2</span><div><h4>Fails, but no reason</h4><p>It has nuts, and <code>nut_free</code> is <code>false</code>. That's the right answer, but there's no explanation it's because <code>"nuts"</code> was found in the list.</p></div></li>
<li><span class="notes__n mono">3</span><div><h4>Passes, but shouldn't</h4><p>Its allergens were recorded as the string <code>"nuts"</code> rather than a list. <code>arr[_]</code> finds nothing inside a string, so <code>has</code> never matches, and <code>not</code> turns that into a pass. A batch with nuts is declared nut-free.</p></div></li>
<li><span class="notes__n mono">4</span><div><h4>Fails, but input invalid</h4><p>There's no allergen record at all, so nobody knows whether it has nuts. But its result is exactly the same as batch 002, so a missing record looks like a batch with nuts - although it needs a different fix.</p></div></li>
</ol>

</div>

## What ergo outputs

```sh
opa eval -d ergo.rego -d examples/baking/ergo -i examples/baking/batches.json -f pretty 'data.baking.report'
```

The report has a row for every check it ran on every batch, with the value it read:

| batch | check           | value read                               | passed  | cause       |
| ----- | --------------- | ---------------------------------------- | ------- | ----------- |
|       | `$well_formed`  | `count(checks) = 3`, `require = "every"` | `true`  | `satisfied` |
|       | `$min_subjects` | `count(matching(batches)) = 4`           | `true`  | `satisfied` |
| 001   | `nut_free`      | `allergens = ["milk","eggs"]`            | `true`  | `satisfied` |
| 001   | `temp_ok`       | `bake.temp_c = 180`                      | `true`  | `satisfied` |
| 001   | `time_ok`       | `bake.minutes = 32`                      | `true`  | `satisfied` |
| 002   | `nut_free`      | `allergens = ["nuts","milk"]`            | `false` | `value`     |
| 002   | `temp_ok`       | `bake.temp_c = 180`                      | `true`  | `satisfied` |
| 002   | `time_ok`       | `bake.minutes = 32`                      | `true`  | `satisfied` |
| 003   | `nut_free`      | `allergens = "nuts"`                     | `false` | `unusable`  |
| 003   | `temp_ok`       | `bake.temp_c = 180`                      | `true`  | `satisfied` |
| 003   | `time_ok`       | `bake.minutes = 32`                      | `true`  | `satisfied` |
| 004   | `nut_free`      | `allergens = null`                       | `false` | `absent`    |
| 004   | `temp_ok`       | `bake.temp_c = 180`                      | `true`  | `satisfied` |
| 004   | `time_ok`       | `bake.minutes = 32`                      | `true`  | `satisfied` |

An ergo report, some checks are reported by default (those starting with `$`). They tell you if requirements are well formed, and that there was at least one input subject to check.

In this example, Batch 003 fails because ergo's `excludes` needs a list, and `"nuts"` isn't one. All three batches fail, but you can see the different reasons. `cause: value` means ergo read the value and it didn't pass (allergens contain nuts), `cause: unusable` means the value was there but not the kind the check needs, and `cause: absent` means there was no value at all.

The report also writes each check as an expression, so the table comes straight out of it. [`ergo/workings.rego`](https://github.com/kosli-dev/ergo/blob/main/examples/baking/ergo/workings.rego) builds it from the report, and the policy exposes it as `workings_table`:

```sh
opa eval -d ergo.rego -d examples/baking/ergo -i examples/baking/batches.json -f pretty 'data.baking.workings_table'
```

Here are the rows for batch 001:

| Policy clause (`description`)        | Predicate (`check`) | Inputs used (`inputs`)        | Evaluated expression (`expression`)         | Result (`passed`) |
| ------------------------------------ | ------------------- | ----------------------------- | ------------------------------------------- | ----------------- |
| Must not contain nut allergens       | `nut_free`          | `allergens = ["milk","eggs"]` | `not contains(allergens, "nuts")`           | `true`            |
| Bake temperature 175–200°C inclusive | `temp_ok`           | `bake.temp_c = 180`           | `bake.temp_c >= 175 and bake.temp_c <= 200` | `true`            |
| Bake time 25–40 minutes inclusive    | `time_ok`           | `bake.minutes = 32`           | `bake.minutes >= 25 and bake.minutes <= 40` | `true`            |

When you only want to know what to fix, ask for the violations. There's one for each of the three failing batches. Here's the one for batch 004:

```sh
opa eval -d ergo.rego -d examples/baking/ergo -i examples/baking/batches.json -f pretty 'data.baking.violations'
```

```json
{
  "cause": "absent",
  "check": "nut_free",
  "description": "Must not contain nut allergens",
  "expression": "not contains(allergens, \"nuts\")",
  "inputs": [
    {
      "name": "allergens",
      "value": null
    }
  ],
  "requirement": "cake_batch",
  "subject": {
    "id": "cake-batch-2026-03-18-004",
    "type": "batch"
  }
}
```

## Learn more...

This example showed you how to build to rego policies with ergo to meet two ket requirements in compliance decisions: being able to inspect what was checked, and to explain why it passed or failed. To continue learning, [dive into the docs](../docs/getting-started/).
