# What porting Ergo turns up

When the spec and `ergo.rego` disagree, the spec wins (see [spec/README.md](../../spec/README.md)). This file lists each disagreement the port finds, with the case that shows it, and what the port has to copy from `ergo.rego` because the spec doesn't say it.

## The old port's findings, checked against spec v0.2

The old port, on the branch `core/conformance-suite`, listed its findings in `conformance/FINDINGS.md`. Here is where each one stands on spec v0.2. Rules are in `spec/semantics.md` and `spec/syntax.md`, and cases are named `folder / group / case`.

### Still to copy: the spec doesn't say, a case does

- **A subject listed by `named by each of` whose key the object doesn't have.** It's still a subject, its fields read as missing, and its id is its key, even with an `identified_by` (`sast`, not the `name` field it holds). [subjects.sentence] only says each key is a subject, and [location.start] says where it points. Case: `subjects / a from line with named by each of a param list / makes each listed key a subject, identified by its key, and a key the object doesn't have is still a subject`.
- **The `expression` of a check that's written wrong.** A sentence that can't be read is shown as written, like `days is 1`, and a check with no `assert` as `<missing assert>`. [report.requirements] says every check is listed with its expression, but not what that is when the check can't be read, while [report.subjects] does say it for subjects (`<invalid from>`). Cases: `derived / a field called days / is written wrong, because days is a word of the grammar` and `requirements / a check written with op / is written wrong: it has no assert, each of its fields is unknown, and the requirement gets no row but $well_formed`.
- **Numbers in an `expression`.** [sentence.print.canonical] says "numbers in their plain form", and two cases pin `1.50` as `1.5` and `1e2` as `100` (`sentences / a number with a trailing zero prints in its plain form / prints as x is 1.5`, `sentences / a number with an exponent prints in its plain form / prints as x is 100`). No case and no rule says what `1e-7` or `-0` print as. `ergo.rego` prints `0.0000001` and `0`, with `_json_text`.

### Now a spec rule

- **Numbers compare by value**, so `1` equals `1.0`: [value.equal].
- **`present` on a missing or `null` field fails with `value`**: [present.missing].
- **`from` has to end on a list or an object**, or `$min_subjects` fails, even with `min_subjects: 0`: [subjects.from]. Its description is then `The <type> list can be read`: [added.text].
- **A filter that rules a subject out on `value` isn't a violation, but one that can't read its field is**: [scope.out], [scope.unreadable]. A `present` filter that finds its field missing rules the subject out whatever the others say: [present.filter].
- **A ref that can't be used in a walk** now fails the whole check as `unusable` with `failed_items: []`, and a ref step that can't be read fails it with the ref's cause and `inputs: []`: [walk.flaws], [for.flaws]. The old rule, where every item failed one by one, is gone.
- **Inputs that are `[]` because part of them can't be worked out.** It isn't a general rule any more. It happens only where [walk.flaws] says.
- **Sets and keys that aren't strings** fail as `unusable`: [walk.flaws]. A port that reads JSON never sees them.
- **A check that's written wrong is still listed** in the requirement's `checks`, with only a `$well_formed` row: [well_formed], [report.requirements]. Its `expression` is under "Still to copy" above.

### Gone with the 0.1 and 0.2 shape

- **`failed_items` with cause `missing`.** Fixed in `ergo.rego`, and `missing` isn't in `spec/report/schema.json`'s causes.
- **OPA before 1.20 comparing `1` and `100.0` wrongly.** It was OPA's bug, CI runs only OPA 1.20.2 now, and the case it broke is gone.
- **An `all` or `any` row's `inputs` following the inner check's `path`**, and **a top-level `all` or `any` naming its list differently from a nested one.** There's no `op` any more. A walk's `inputs` are named as [walk.inputs] and the `name.*` rules say, and a `for` line's as [for.inputs] says.
- **The internal stand-in for a key that isn't there.** `keys` became `named by each of`. What such a subject reads is under "Still to copy" above.
- **A path written as a string read as one key.** Paths are sentences now: [sentence.path.string].
- **A `subject_type` that isn't a string.** A row's `type` is the name of the subject definition: [requirement.subject].

## Disagreements between the spec and `ergo.rego`

### Sentences

`ergo-sentences` reads what `spec/sentences.abnf` allows, and `check_grammar.py --rust` checks that on every sentence it tries. Comparing it with `ergo.rego` on about 18,000 generated and real lines found these differences. No sentence in `spec/cases` or the corpus hits them, which is why `check_grammar.py` doesn't list them in `spec/OPEN.md`.

- **A `for` item with a bracket index and no quantifier.** `ergo.rego` reads `x[3] as i` as `item 4 of x as i`. The ABNF's `for-item` needs `every`, `some` or a position in words, so Rust rejects it with `an item starts with "every", "some" or a position, like "last of"`.
- **Tabs at either end of a line.** `ergo.rego` drops all whitespace there (`trim_space`), so `x is 1` followed by a tab reads. The ABNF drops only spaces, and so does Rust.
- **The messages for a line that doesn't parse.** When a check doesn't parse, `ergo.rego` also tries to read it as a `from` line and a `for` line, and lists what those readings find. So `items whose k matches "("` as a check gets `invalid pattern "("`, which comes from reading it as a `from` line, where Rust says `doesn't parse`. Rust only reports on the kind of line it was asked to read. Both reject the same lines; only the messages differ.
