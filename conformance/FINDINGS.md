# What porting ergo turned up

Writing ergo in Rust against this suite shows where `ergo.rego` does something only Rego would do. This file lists what's been found so far. The cases named here are in `from_tests/` unless a path says otherwise.

## Bugs in ergo.rego

**`failed_items` could report the cause `missing`.** The causes table in `REFERENCE.md` has no `missing`. `ergo.rego` uses it inside to tell "`present` found nothing" apart from other failures, and it leaked out when `present` failed on an item of an `all` or `any`, as `{"cause": "missing", "path": "branches[0]", "value": null}`, while the row itself said `value`. Fixed on the branch `core/no-missing-in-failed-items`: such an item is now listed with cause `value`.

**OPA before 1.20 compares some numbers wrongly, and ergo inherits it.** Up to OPA 1.19.1, `1 >= 100.0` and `1 == 100.0` are `true` and `100.0 > 1` is `false`, whether the numbers are written in the policy or read from JSON. `10.0` and `1000.0` go wrong the same way, while `100`, `1e2` and `2.0` are fine. So on those versions a requirement with `"min_subjects": 100.0` is met by a single subject, an `equals` check with `"value": 100.0` passes on `1`, and `range` and `compare` can go wrong too. CI runs ergo's main checks on 1.19 and the README names it.

| OPA | `1 >= 100.0` | `100.0 > 1` | `1 == 100.0` |
| --- | --- | --- | --- |
| 1.18.0, 1.19.0, 1.19.1 | `true` | `false` | `true` |
| 1.20.0 and later | `false` | `true` | `false` |

The cause is in OPA's `NumberCompare`, which strips trailing `.` and `0` characters with `strings.TrimRight(xs, ".0")`, so `"100.0"` is read as `"1"`. [OPA issue #9098](https://github.com/open-policy-agent/opa/issues/9098) describes that code, but for a different symptom: a panic comparing `0.0` in 1.20.0, fixed in 1.20.1. It says 1.19.1 is correct, because its examples don't include numbers like `100.0`. The wrong comparisons aren't reported anywhere we could find. 1.20.0 fixes them but has the panic, so 1.20.1 is the first version that gets both right.

Case: `present / a min subjects whose value is a whole number is well formed however it is written (2)`, whose expected report was made with 1.19 and is wrong. The Rust port gets it right.

**Values JSON can't hold were treated unevenly.** A set passed `in` as its `values`, but a set in the input failed `includes`. A number in a path read the key `1` of `{1: "a"}`. Fixed in #155: any set or key that isn't a string in the input or params now fails every check as `unusable`, and in a policy it's written wrong.

## Rego details a port has to copy

These aren't wrong, but they come from how `ergo.rego` is written rather than from a rule anyone chose, so another implementation has to reproduce them exactly.

- **An `all` or `any` row's `inputs` follow the inner check's `path` field only.** With `equals` inside, the row shows `commits[].signed`, one value per item. With `compare` inside, which has `left` and `right` but no `path`, it shows the whole items as `approvers[]`.
- **A top-level `all` or `any` names its list differently from a nested one.** At the top, the list is named by its path alone. Nested, an empty path is named after the item, so the same check renders differently depending on where it sits.
- **A key listed in `keys` that the object doesn't have becomes a subject that reads as absent everywhere.** `ergo.rego` uses an internal marker for it, and a port needs its own stand-in. The marker was `{"ergo/absent": true}` until #162, so an input that really held that object was read as missing. It's now `{"ergo/absent": set()}`, which no input can hold since #155. The Rust port never had the problem, because it recognises its stand-in by identity, not by value.
- **Numbers in expressions are written as plain decimals.** `1e2` is written `100`, `1.50` is `1.5`, `1e-7` is `0.0000001` and `-0` is `0`. `ergo.rego` gets there with its own JSON printer (`_json_text`), because OPA's `json.marshal` escapes `<`, `>` and `&` and writes numbers differently in each runtime. A port has to keep each number's text as written to do the same, like `serde_json`'s `arbitrary_precision`.
- **When part of a row's inputs can't be worked out, the whole list is `[]`.** That's how Rego handles an undefined value inside an array, and the report shows it. For example, an `all` with no `check` has `"inputs": []`, not the list it would read.
- **A path written as a string is read as a single key.** `"each": "commits"` reads `commits`, as if it were `["commits"]`, but it's rendered oddly: `every xs[].: xs[].[] == 1`.
- **Written-wrong checks are still rendered and still read.** The expression and the row's `inputs` come from the check as written, even when it can't be run, so a port needs a second, forgiving way to describe a check besides the one that runs it.

## Rules a port wouldn't guess

These are intended and documented, but easy to get wrong. The suite has cases for each.

- Numbers compare by value: `1` equals `1.0`. A language's own equality may say otherwise, as Rust's `serde_json` does.
- `present` on a missing or `null` field fails with cause `value`, not `absent`, because that's the question it asks.
- `from` has to lead to a list or an object. Missing, `null` or anything else fails `$min_subjects` as `absent`, `null` or `unusable`, even with `min_subjects: 0`. With `min_subjects: 0`, the check is described as "The thing list can be read" (`things can be read`).
- A filter that rules a subject out on `value` isn't a violation, but one that can't read its field is. A `present` filter that finds its field missing rules the subject out, whatever the other filters say.
- A ref that can't be read inside an `all` makes every item fail with the ref's cause, even items that would have passed.
- A `subject_type` that isn't a string is shown as the value itself in rows (`3`) and as JSON text in descriptions (`Every 3 id is unique`).
