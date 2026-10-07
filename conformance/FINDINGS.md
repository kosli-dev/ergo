# What porting ergo turned up

Writing ergo in Rust against this suite shows where `ergo.rego` does something only Rego would do. This file lists what's been found so far. The cases named here are in `from_tests/` unless a path says otherwise.

## Bugs in ergo.rego

**`failed_items` can report the cause `missing`.** The causes table in `REFERENCE.md` has no `missing`. It's a value `ergo.rego` uses inside, to tell "`present` found nothing" apart from other failures, and it leaks out when `present` fails on an item of an `all` or `any`:

```json
{"cause": "missing", "path": "branches[0]", "value": null}
```

The row's own `cause` says `value`, as it should. Cases: `all / an empty path fails closed on a null item (2)`, `all / failed items write paths the way inputs do`, `all / failed items of a named path start with the name`, `all / a path through as inside a list check is shown as a path inside the item`. The Rust port copies it for now, so the other differences stay visible.

**OPA 1.19 compares some numbers wrongly, and ergo inherits it.** In OPA 1.19.0, `1 >= 100.0` is `true` and `100.0 > 1` is `false`, with the numbers written in the query or read from JSON. `10.0` and `1000.0` do the same, while `100`, `1e2` and `2.0` are fine. OPA 1.20.2 gets all of them right. So on 1.19 a requirement with `"min_subjects": 100.0` is met by a single subject, and `range` and `compare` can go wrong the same way. CI runs ergo's main checks on 1.19 and the README names it. Case: `present / a min subjects whose value is a whole number is well formed however it is written (2)`, whose expected report was made with 1.19 and is wrong. The Rust port gets it right.

**Values JSON can't hold were treated unevenly.** A set passed `in` as its `values`, but a set in the input failed `includes`. A number in a path read the key `1` of `{1: "a"}`. Fixed on the branch `core/reject-non-json-values`, which isn't merged yet: any set or key that isn't a string in the input or params now fails every check as `unusable`, and in a policy it's written wrong.

## Rego details a port has to copy

These aren't wrong, but they come from how `ergo.rego` is written rather than from a rule anyone chose, so another implementation has to reproduce them exactly.

- **An `all` or `any` row's `inputs` follow the inner check's `path` field only.** With `equals` inside, the row shows `commits[].signed`, one value per item. With `compare` inside, which has `left` and `right` but no `path`, it shows the whole items as `approvers[]`.
- **A top-level `all` or `any` names its list differently from a nested one.** At the top, the list is named by its path alone. Nested, an empty path is named after the item, so the same check renders differently depending on where it sits.
- **A key listed in `keys` that the object doesn't have becomes a subject that reads as absent everywhere.** `ergo.rego` uses an internal marker, `{"ergo/absent": true}`, for it. The marker never reaches the report, but a port needs its own stand-in.
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
