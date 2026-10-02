# Baking

A cake batch must pass three rules:

1. It must not contain nut allergens.
2. It must be baked at 175–200°C.
3. It must be baked for 25–40 minutes.

`batches.json` has four batches. Batch 001 is fine, and batches 002 to 004 each record their allergens differently:

| batch | `allergens`        |
| ----- | ------------------ |
| 001   | `["milk", "eggs"]` |
| 002   | `["nuts", "milk"]` |
| 003   | `"nuts"`           |
| 004   | missing            |

The same policy is written twice: in plain Rego in `plain-rego/`, and with ergo in `ergo/`. Run these from the root of the repo.

## Plain Rego

```sh
opa eval -d examples/baking/plain-rego -i examples/baking/batches.json -f pretty 'data.baking.batches'
```

Each batch gets `true` or `false` for each rule. Batch 003 contains nuts, but it comes out compliant:

```json
{
  "compliant": true,
  "nut_free": true,
  "temp_ok": true,
  "time_ok": true
}
```

Its allergens are the string `"nuts"`, not a list, so `has` never finds `"nuts"` and `not` turns that into a pass. Batches 002 and 004 come out exactly the same, although 002 has nuts in it and 004 has no allergen record at all.

## ergo

```sh
opa eval -d ergo.rego -d examples/baking/ergo -i examples/baking/batches.json -f pretty 'data.baking.report'
```

The rules are in `ergo/baking.yaml`, with each rule's wording as its `description`. ergo checks every batch and records what it read. Only batch 001 passes, and the violations say why each of the others failed:

| batch                       | check      | value read        | cause    |
| --------------------------- | ---------- | ----------------- | -------- |
| `cake-batch-2026-03-18-002` | `nut_free` | `["nuts","milk"]` | `value`  |
| `cake-batch-2026-03-18-003` | `nut_free` | `"nuts"`          | `value`  |
| `cake-batch-2026-03-18-004` | `nut_free` | `null`            | `absent` |

To get those rows yourself, ask for `data.baking.violations` instead of the report.

## The workings table

The report has everything needed to show the workings clause by clause. `ergo/workings.rego` builds that table from the report, with one row per check for each batch, and `ergo/baking.rego` exposes it as `workings_table`:

```sh
opa eval -d ergo.rego -d examples/baking/ergo -i examples/baking/batches.json -f pretty 'data.baking.workings_table'
```

Each row has the clause's wording, the check, what it read, the expression and the result. Here is batch 004 as a table:

| clause                               | check      | inputs              | expression                                  | passed  |
| ------------------------------------ | ---------- | ------------------- | ------------------------------------------- | ------- |
| Must not contain nut allergens       | `nut_free` | `allergens = null`  | `not contains(allergens, "nuts")`           | `false` |
| Bake temperature 175–200°C inclusive | `temp_ok`  | `bake.temp_c = 180` | `bake.temp_c >= 175 and bake.temp_c <= 200` | `true`  |
| Bake time 25–40 minutes inclusive    | `time_ok`  | `bake.minutes = 32` | `bake.minutes >= 25 and bake.minutes <= 40` | `true`  |

`workings.rego` only reads the report, not anything about baking, so it works for any ergo policy. The plain Rego version has nothing to build it from: its output is `true` or `false` for each rule.

## Tests

`plain-rego/baking_test.rego` and `ergo/baking_test.rego` pin what each version reports for these batches, so `opa test . --ignore .github` from the repo root checks them along with ergo's own tests.
