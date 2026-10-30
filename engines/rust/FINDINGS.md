# What porting Ergo turns up

When the spec and `ergo.rego` disagree, the spec wins (see [spec/README.md](../../spec/README.md)). This file lists each disagreement the port finds, with the case that shows it, and what the port has to copy from `ergo.rego` because the spec doesn't say it.

## The old port's findings, checked against spec v0.2

The old port, on the branch `core/conformance-suite`, listed its findings in `conformance/FINDINGS.md`. Here is where each one stands on spec v0.2. Rules are in `spec/semantics.md` and `spec/syntax.md`, and cases are named `folder / group / case`.

### Still to copy: the spec doesn't say, a case does

- **A subject listed by `named by each of` whose key the object doesn't have.** It's still a subject, its fields read as missing, and its id is its key, as [subjects.keyed.id] now says (an `identified_by` next to `named by each of` is written wrong). [subjects.sentence] only says each key is a subject, and [location.start] says where it points. Case: `subjects / a from line with named by each of a param list / makes each listed key a subject, identified by its key, and a key the object doesn't have is still a subject`.
- **The `expression` of a check that's written wrong.** A sentence that can't be read is shown as written, like `days is 1`, and a check with no `assert` as `<missing assert>`. That holds for a problem found once names are read too: `n is count of k1.k2.k3.k4.k5.k6.k7.k8.k9.k10.k11` is shown as written, while the same sentence over two steps is printed `n equals count of k1.k2`. Case: `deep_walks / eleven steps after a count of on the right of a phrase / is written wrong, as it is on the left`. [report.requirements] says every check is listed with its expression, but not what that is when the check can't be read, while [report.subjects] does say it for subjects (`<invalid from>`). Cases: `derived / a field called days / is written wrong, because days is a word of the grammar` and `requirements / a check written with op / is written wrong: it has no assert, each of its fields is unknown, and the requirement gets no row but $well_formed`.
- **Numbers in an `expression`.** [sentence.print.canonical] says "numbers in their plain form", and two cases pin `1.50` as `1.5` and `1e2` as `100` (`sentences / a number with a trailing zero prints in its plain form / prints as x is 1.5`, `sentences / a number with an exponent prints in its plain form / prints as x is 100`). No case and no rule says what `1e-7` or `-0` print as. `ergo.rego` prints `0.0000001` and `0`, with `_json_text`.
- **A second item of a `for` line that picks from the first item's alias.** With `for: every items as x, last of x.subs as y`, [for.inputs] says a second item that starts at the first item's alias is named with that alias, like `x.subs[]`, but not what it holds when it picks. `ergo.rego` gives one entry named `x.subs[]` that holds each value picked, in the order of the first list, with their locations. When a pick finds nothing, because the list is empty or the position is past its end, that outer item's entry lists the whole list it looked in (an empty list for an empty one), and `failed_items` of that outer item gets `{"cause": "absent", "item": "x.subs", "path": "x.subs", "value": null, "locations": []}` as [for.second_failures] lists for a list that failed. When the pick fails because of a tie, a sort that can't be read or a `whose` that can't decide, that outer item adds nothing to the entry. A second item that doesn't start at the first alias keeps the name of the item where it is, like `item 2 of ps`, and adds no failure of its own for an empty list. Cases: none yet. `engines/rust/engine/tests/regressions/operators/regressions.json` pins the reports.
- **What a `whose` on a `for` item adds to the row's `inputs`.** [for.walk] says how the `whose` reads and [for.inputs] lists "the inputs the checks would show on their own", but neither says whether the paths a `whose` on a `for` item reads from outside the item are listed. `ergo.rego` lists none of them: no `$params`, no `$input` and no parent, like `kid.pc` in `every items whose x is at least kid.pc as z`. The port does the same. Case: none yet. `engines/rust/engine/tests/regressions/operators/regressions.json` pins the reports.

### Now a spec rule

- **Numbers compare by value**, so `1` equals `1.0`: [value.equal].
- **`present` on a missing or `null` field fails with `value`**: [present.missing].
- **`from` has to end on a list or an object**, or `$min_subjects` fails, even with `min_subjects: 0`: [subjects.from]. Its description is then `The <type> list can be read`: [added.text].
- **A filter that rules a subject out on `value` isn't a violation, but one that can't read its field is**: [scope.out], [scope.unreadable]. A `present` filter that finds its field missing rules the subject out whatever the others say: [present.filter].
- **A ref that can't be used in a walk** now fails the whole check as `unusable` with `failed_items: []`, and a ref step that can't be read fails it with the ref's cause and `inputs: []`: [walk.flaws], [for.flaws]. The old rule, where every item failed one by one, is gone.
- **Inputs that are `[]` because part of them can't be worked out.** It isn't a general rule any more. It happens only where [walk.flaws] says.
- **Sets and keys that aren't strings** fail as `unusable`: [walk.flaws]. A port that reads JSON never sees them.
- **A second pick that doesn't start at the first alias fails the check as it would written first**, even when the first list is empty: [for.pick]. `for: every items as x, first of ps as y` with no items and `ps` missing, `null`, not a list or empty fails as `absent`, `null`, `unusable` or `absent`, with `failed_items` `[]`, not as `value`. When the pick can't decide because items tie or a sort can't be read, those items are listed in `failed_items`. A first item that is itself a pick keeps its own cause.
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

## Rules that a case contradicts

Here a rule's text says one thing and a case, which `ergo.rego` passes, says another. The port follows the case, because the runner holds it to the cases, until the spec settles which one is right.

- **`from: $input` on an input that is a list.** [subjects.from] says a `from` that ends `found` on a list makes each item a subject, and that with no steps it reads the whole input, so `[1]` would give one subject. The case gives none and fails `$min_subjects` as `unusable`. Case: `requirements / the whole input as the subject / fails min_subjects as unusable on a list`.
- **The id of a subject that isn't an object, when it has an `identified_by`.** [subjects.id] says the id is `null` when the path doesn't end `found`, and a path into a string ends `not_an_object`. The case gives `"a"` the id `"a"`. Case: `requirements / ... / takes items that aren't objects as subjects, each its own id when it has no id field`.
- **More than 15 decimal places in a sum.** [tally.sum] asks only that each number times 10^p is whole and below 10^15, so `1e-16` plus `0` would pass (`1e-16` times 10^16 is 1). The case, and `ergo.rego` (`places <= 15`), fail it as `unusable`. The engine fails any sum where p is above 15. Case: `derived / a plus that needs more than 15 digits at a common scale / fails as unusable when a term has 16 decimal places`.
- **The order of a failed walk sentence's inputs under a `for` line.** [for.failure_inputs] says the entries "keep the order the sentence reads them, its left side and then its right side, and aren't sorted by name". Two groups of cases disagree with that, and with each other. Under `for: every keys as k`, `some rows.n is at least artifact.nums named by k` lists `artifact.nums named by k` before `rows[].n`: the right side first, in name order, as [walk.inputs] sorts a walk's row (`walks / a walk whose parent path is named by a field of each item`, `walks / a walk through a for name, read from a parent on its right side`, `sentences / a for alias inside an item's scope`). Under `for: every files as f`, `some f.tags is artifact.owner` lists `f.tags[]` before `artifact.owner`: the left side first, against name order (`walks / a for line with a walk next to a parent`). The engine puts entries that start at a `for` alias first and keeps the walk's name order for the rest, which is the one order that fits all of them.

## Things the spec leaves to the implementation

- **The order of keys in the report.** [report.policy] and [report.requirements] say `meta` is copied into the report, and AGENTS.md says the report stays byte for byte the same whatever order the policy was written in. Nothing in the spec says in which order an object's keys are written. [report.hash] doesn't need one, since RFC 8785 sorts keys, and `ergo.rego` gets sorted keys from OPA. serde_json sorts keys unless its `preserve_order` feature is on, and with it on `meta` kept the order it was written in. So the engine sorts every object in the report and in `violations()` by key, code point by code point, and `tests/key_order.rs` runs with that feature on too.

## Where Rust's `regex` reads a pattern differently from RE2

[patterns.syntax] says a pattern is RE2 syntax, and `ergo.rego` runs Go's RE2 through OPA. The port uses the `regex` crate, and reads each pattern through `ergo_sentences::rust_pattern` first, the same text the parser checks for `invalid pattern`. That function rewrites what the two read differently:

- **`\d`, `\w`, `\s` and `\b` are ASCII in RE2 and Unicode in Rust.** With OPA, `^\d$` doesn't match `٣`, `^\w$` doesn't match `é`, `^\s$` matches neither a vertical tab nor a non-breaking space, and `a\b` matches `aé`. Rust's defaults would give the opposite for all of them. So `\d` is written `[0-9]`, `\w` `[0-9A-Za-z_]`, `\s` `[\t\n\x0C\r ]`, their capitals the negated sets, and `\b` and `\B` `(?-u:\b)` and `(?-u:\B)`. Inside brackets the sets are nested, which Rust allows, so `[\d_]` is `[[0-9]_]`. No case pins this. It would take a case like `x matches "^\\d$"` on `"٣"`, which fails as `value`.
- **Syntax only RE2 has**, like `\Q...\E`, a `{` that isn't a repeat, `[]a]`, and more than 1000 repeats being invalid, was already rewritten or rejected by ergo-sentences. Its oracle test checks validity against RE2.
- **A pattern Rust can't compile** after that, for example one too big for its size limit, fails the check as `unusable`, so it never passes by accident.
