# What porting ergo turned up

Writing ergo in Rust against this suite shows where `ergo.rego` does something only Rego would do. This file lists what's been found so far. The cases named here are in `from_tests/` unless a path says otherwise.

## Bugs in ergo.rego

**`failed_items` can report the cause `missing`.** The causes table in `REFERENCE.md` has no `missing`. It's a value `ergo.rego` uses inside, to tell "`present` found nothing" apart from other failures, and it leaks out when `present` fails on an item of an `all` or `any`:

```json
{"cause": "missing", "path": "branches[0]", "value": null}
```

The row's own `cause` says `value`, as it should. Cases: `all / an empty path fails closed on a null item (2)`, `all / failed items write paths the way inputs do`, `all / failed items of a named path start with the name`, `all / a path through as inside a list check is shown as a path inside the item`. The Rust port copies it for now, so the other differences stay visible.

**Values JSON can't hold were treated unevenly.** A set passed `in` as its `values`, but a set in the input failed `includes`. A number in a path read the key `1` of `{1: "a"}`. Fixed on the branch `core/reject-non-json-values`, which isn't merged yet: any set or key that isn't a string in the input or params now fails every check as `unusable`, and in a policy it's written wrong.

## Rego details a port has to copy

These aren't wrong, but they come from how `ergo.rego` is written rather than from a rule anyone chose, so another implementation has to reproduce them exactly.

- **An `all` or `any` row's `inputs` follow the inner check's `path` field only.** With `equals` inside, the row shows `commits[].signed`, one value per item. With `compare` inside, which has `left` and `right` but no `path`, it shows the whole items as `approvers[]`.
- **A top-level `all` or `any` names its list differently from a nested one.** At the top, the list is named by its path alone. Nested, an empty path is named after the item, so the same check renders differently depending on where it sits.
- **A key listed in `keys` that the object doesn't have becomes a subject that reads as absent everywhere.** `ergo.rego` uses an internal marker, `{"ergo/absent": true}`, for it. The marker never reaches the report, but a port needs its own stand-in.
- **Written-wrong checks are still rendered and still read.** The expression and the row's `inputs` come from the check as written, even when it can't be run, so a port needs a second, forgiving way to describe a check besides the one that runs it.

## Rules a port wouldn't guess

These are intended and documented, but easy to get wrong. The suite has cases for each.

- Numbers compare by value: `1` equals `1.0`. A language's own equality may say otherwise, as Rust's `serde_json` does.
- `present` on a missing or `null` field fails with cause `value`, not `absent`, because that's the question it asks.
- `from` has to lead to a list or an object. Missing, `null` or anything else fails `$min_subjects` as `absent`, `null` or `unusable`, even with `min_subjects: 0`. With `min_subjects: 0`, the check is described as "The thing list can be read" (`things can be read`).
- A filter that rules a subject out on `value` isn't a violation, but one that can't read its field is. A `present` filter that finds its field missing rules the subject out, whatever the other filters say.
- A ref that can't be read inside an `all` makes every item fail with the ref's cause, even items that would have passed.
- A `subject_type` that isn't a string is shown as the value itself in rows (`3`) and as JSON text in descriptions (`Every 3 id is unique`).
