---
title: "The bakery example"
layout: bakery
robots: "noindex, nofollow"
sitemap:
  disable: true
---

ergo started with a one-page bakery example. It checks a cake batch against three rules, then shows its workings, clause by clause, so someone who doesn't read Rego can see why the batch passed.

Here is the same policy written two ways, in plain Rego and with ergo, and run on the same batches with OPA 1.19.

## The policy

1. Must not contain nut allergens
2. Bake temperature 175–200°C inclusive
3. Bake time 25–40 minutes inclusive
4. Compliant only if all clauses pass

## The same policy, twice

<div class="side">
<div>

<p class="compare__label mono">Rego</p>

```rego
package bakery

default compliant := false

nut_free if {
	not has(input.allergens, "nuts")
}

temp_ok if {
	input.bake.temp_c >= 175
	input.bake.temp_c <= 200
}

time_ok if {
	input.bake.minutes >= 25
	input.bake.minutes <= 40
}

compliant if {
	nut_free
	temp_ok
	time_ok
}

has(arr, x) if {
	arr[_] == x
}
```

This is the example's policy with two changes, because OPA 1.19 won't load it as written: the rules need `if`, and the `contains` helper clashes with a function OPA now has built in, so it's renamed `has`.

</div>
<div class="side--ergo">

<p class="compare__label mono">with <span class="ergo-mark">ergo</span></p>

`policy/bakery.yaml`

```yaml
bakery:
  requirements:
    cake_batch:
      subject_type: batch
      from: [batches]
      id: [id]
      checks:
        nut_free:
          description: Must not contain nut allergens
          op: excludes
          path: [allergens]
          value: nuts
        temp_ok:
          description: Bake temperature 175–200°C inclusive
          op: range
          path: [bake, temp_c]
          min: 175
          max: 200
        time_ok:
          description: Bake time 25–40 minutes inclusive
          op: range
          path: [bake, minutes]
          min: 25
          max: 40
```

`policy/bakery.rego`, which runs it:

```rego
package bakery

import data.ergo

report := ergo.report(input, data.bakery.requirements)

violations := ergo.violations(report)
```

The requirements are plain data, so they can live in YAML. Each clause becomes a check, with the clause's own words as its `description`. Clause 4 needs nothing: a requirement passes only when every check passes, unless you say otherwise.

</div>
</div>

The input differs a little. The Rego policy reads one batch. ergo reads a list of batches, each with an `id`, so it can say which batch each result is about:

<div class="side">
<div>

<p class="compare__label mono">Rego input</p>

```json
{
  "allergens": ["milk", "eggs"],
  "bake": { "minutes": 32, "temp_c": 180 }
}
```

</div>
<div class="side--ergo">

<p class="compare__label mono"><span class="ergo-mark">ergo</span> input</p>

```json
{
  "batches": [
    {
      "id": "cake-batch-2026-03-18-001",
      "allergens": ["milk", "eggs"],
      "bake": { "minutes": 32, "temp_c": 180 }
    }
  ]
}
```

</div>
</div>

## A good batch

Batch 001 is the one from the example. Both versions say it's compliant.

<div class="side">
<div>

<p class="compare__label mono">Rego</p>

```sh
opa eval -d policy -i batch.json -f raw 'data.bakery'
```

```json
{"compliant":true,"nut_free":true,"temp_ok":true,"time_ok":true}
```

That's the whole answer. The example's "showing your workings" table had to be written by hand next to it.

</div>
<div class="side--ergo">

<p class="compare__label mono">with <span class="ergo-mark">ergo</span></p>

```sh
opa eval -d policy -i batches.json -f pretty 'data.bakery.report'
```

The report has a row for every check it ran, with the value it read:

| check           | value read                          | passed | cause       |
| --------------- | ----------------------------------- | ------ | ----------- |
| `$well_formed`  | `count(checks) = 3`                 | `true` | `satisfied` |
| `$min_subjects` | `count(matching(batches)) = 1`      | `true` | `satisfied` |
| `nut_free`      | `allergens = ["milk","eggs"]`       | `true` | `satisfied` |
| `temp_ok`       | `bake.temp_c = 180`                 | `true` | `satisfied` |
| `time_ok`       | `bake.minutes = 32`                 | `true` | `satisfied` |

ergo adds the `$` checks itself. They make sure the requirement has checks, and that there was at least one batch to check.

</div>
</div>

The report also spells out each check as an expression, so the workings table comes straight out of it:

| Policy clause (`description`)        | Predicate (`check`) | Inputs used (`inputs`)        | Evaluated expression (`expression`)            | Result (`passed`) |
| ------------------------------------ | ------------------- | ----------------------------- | ---------------------------------------------- | ----------------- |
| Must not contain nut allergens       | `nut_free`          | `allergens = ["milk","eggs"]` | `not contains(allergens, nuts)`                | `true`            |
| Bake temperature 175–200°C inclusive | `temp_ok`           | `bake.temp_c = 180`           | `bake.temp_c >= 175 and bake.temp_c <= 200`    | `true`            |
| Bake time 25–40 minutes inclusive    | `time_ok`           | `bake.minutes = 32`           | `bake.minutes >= 25 and bake.minutes <= 40`    | `true`            |

## Three batches that should fail

Batches 002 to 004 are the same good batch with the allergens changed. Every one of them should fail the nut check.

| batch | `allergens`        | Rego `compliant` | ergo `nut_free`       |
| ----- | ------------------ | ---------------- | --------------------- |
| 002   | `["nuts", "milk"]` | `false`          | fails, cause `value`  |
| 003   | `"nuts"`           | `true`           | fails, cause `value`  |
| 004   | missing            | `false`          | fails, cause `absent` |

Two things go wrong with plain Rego.

**Batch 003 passes.** Its allergens were recorded as the string `"nuts"` rather than a list. `arr[_]` finds nothing inside a string, so `has` never matches, and `not` turns that into a pass. A batch with nuts is declared nut-free. ergo's `excludes` only passes on a list, so anything else fails.

**Batches 002 and 004 look the same.** Rego gives the exact same output for both:

```json
{"compliant":false,"temp_ok":true,"time_ok":true}
```

But they're different problems. Batch 002 has nuts in it. Batch 004 has no allergen record at all, so nobody knows. ergo tells them apart with the `cause`, and the violations say what to fix:

```sh
opa eval -d policy -i batch-004.json -f pretty 'data.bakery.violations'
```

```json
[
  {
    "cause": "absent",
    "check": "nut_free",
    "description": "Must not contain nut allergens",
    "expression": "not contains(allergens, nuts)",
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
]
```

## What ergo doesn't do

The example has more than the evaluation. It lists attestations with their source and timestamp, and it hashes both the attestations and the policy. ergo doesn't collect evidence, sign it or hash it. It takes the input it's given and returns the report.

What it does promise is that the same policy and the same input always give the same report, byte for byte, so the report can be hashed and stored alongside the rest.
