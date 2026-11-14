# Glossary

The words the code of both engines uses for the ideas of Ergo, and what each one means. It's for people who work on Ergo. [`REFERENCE.md`](REFERENCE.md) is for people who write policies, and it says "cause" where the code often says "flaw", for example.

The aim is one word for one idea. Some words aren't there yet, and the last section lists where.

## subject

The thing a requirement checks, like a deployment or a pull request, and also each one of them. [`REFERENCE.md`](REFERENCE.md) says "A subject is the kind of thing a requirement checks" and, a few lines later, "each item is a subject".

- Rust: `find_subjects` in `subjects.rs` finds them, `Subject` in `policy.rs` is the definition written in the policy, and `Ctx.subject` in `path.rs` is the one being checked.
- Rego: `_subject_def` in `policy/subjects.rego` is the definition, and `subj` is the value being checked in most rules.

## entry

One element of a list in the report, written `{"name": ..., "value": ..., "locations": [...]}`. `REFERENCE.md` puts it like this: "Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`".

- Rust: `input` in `report.rs` builds one, and `subject_entry` builds a subject's entry in `subjects`.
- Rego: `_entry_anchor` in `report/requirements.rego`.

The Rust engine also has two structs called `Entry` that aren't this: one in `subjects.rs`, a subject with where it was found, and one in `ops/walk.rs`, one step of a walk.

## item

One element of a list that a check or a `from` line reads, like a file in `files`. In a report it shows as `"item": "item 1 of files"` in `failed_items`, and `REFERENCE.md` writes "An item of the list that isn't an object, like a string or a `null`, is still a subject."

- Rust: `WalkItem` in `ops/walk.rs`, and `ItemAt` in the same file.
- Rego: `_item_at` in `lines/walk.rego`, and `data.ergo_item`.

## root

Where a name starts reading. Outside a relative clause that's the subject, unless the name is `$input`, `$params`, a `for` name, a part, a parent subject's name or the subject's own name. `REFERENCE.md` says "Everywhere else, names resolve from their root:". Inside a relative clause, a name starts at the focus instead.

- Rust: `is_root` and `root` in `path.rs`, `from_a_root` in `ops/walk.rs`, `root_text` in `ops/message.rs`.
- Rego: `_root_read_flaw` and `_plain_root_flaw` in `lines/roots.rego`.

## focus

What a relative clause is about, like each approver. `REFERENCE.md` gives `xs whose count of ys.k is 1`, where `k` of each `y` is read inside the focus, and says "inside one a name resolves against the focus, the thing the clause is about".

- Rust: `focus_ctx` and `focus_lost` in `ops/walk.rs`.
- Rego: `_focus_entry` in `lines/walk.rego` and `_tally_focus_cause` in `checks/derived.rego`.

## problem

Something wrong in the policy as written, like `unknown field op`. A problem fails the `$well_formed` row, and `REFERENCE.md` says "A problem fails `$well_formed` on every requirement that names a subject whose chain has it". It's about what the author wrote, never about the input.

- Rust: `Problems` and `add_problem` in `policy.rs`, `well_formed_row` in `report.rs`.
- Rego: `policy/problems.rego`, like `_unknown_problems`, and `_well_formed_row` in `report/chains.rego` and `report/entry.rego`.

## fault

Why one item failed its check, a fact about the data, as text: `$params.q is "s", which isn't a number`. A fault is a piece of a row's message. `REFERENCE.md` never uses the word.

- Rust: `root_fault` in `ops/message.rs`, and the text `for_line.rs` builds in `own_beside_root` and around `root_fault`.
- Rego: `_m_fault` and `_m_faults` in `messages/faults.rego`, and `_tally_root_fault` in `lines/roots.rego`.

## cause

Why a check got its verdict: `Satisfied`, `NotAnObject`, `Ambiguous`, `Unusable`, `Absent`, `Null` or `Value`. `REFERENCE.md` and `spec/semantics.md` call it a cause.

- Rust: `Cause` in `cause.rs`.
- Rego: the `cause` of a row.

The code also says `flaw` for two ideas, and `flaw` isn't a word of Ergo: use `cause` for why a check got its verdict, including when a root couldn't be read (`root_flaw` in Rust and the `flaw` arguments in `checks/derived.rego` are causes), and `problem` for something wrong in the policy (`_number_flaw`, `meta_number_flaws` and `_from_path_flaws` are problems).

## Places that don't match yet

These feed the renames later. Nothing here has changed.

- **subject**: three ideas under one word. `Subject` in `engines/rust/engine/src/policy.rs` is the definition, `Ctx.subject` in `path.rs` is one value, and `REFERENCE.md` uses it for both the kind and each one. A kind of thing and one of them need two words.
- **entry**: `Entry` in `engines/rust/engine/src/subjects.rs` and `Entry` in `ops/walk.rs` are two structs for two ideas, and neither is the report's entry. `_focus_entry` in `engines/rego/src/lines/walk.rego` is the walk one, and `_entry_ref` in `engines/rego/src/reading/values.rego` builds a `{"type", "id"}` reference to a subject found in the input, which is not the report's entry either.
- **item**: `Item` in `engines/rust/engine/src/checks.rs` is one line of a check (its text and what it does), `Item` in `ops/for_line.rs` is the part of a `for` line that picks something, and `WalkItem` in `ops/walk.rs` is one list element. Only the last one is what `REFERENCE.md` calls an item.
- **root**: `Location.root` in `engines/rust/engine/src/path.rs` is which document a value came from, `Input` or `Params`, which `REFERENCE.md` calls "the root of the params". `_is_root` in `engines/rego/src/policy/subjects.rego` is true for a subject that has no `of`, one that isn't built on another subject. A subject other subjects are built on is still a root in this sense.
- **flaw**: the code says `flaw` for two ideas, and the words to use are `cause` and `problem`. These names mean a problem in the policy: `_number_flaw` and `_number_flaws` in `engines/rego/src/checks/leaf_ops.rego`, `meta_number_flaws` and `number_flaws` in Rust, `_from_path_flaws` in `engines/rego/src/lines/from_lines.rego`, and `_s_join_flaws` and `_s_elapsed_flaw` in `engines/rego/src/sentences/`. These mean a cause: `root_flaw`, `root_flaw_ordered`, `root_flaw_counted`, `root_flaw_with`, `sentence_root_flaw`, `outer_flaw`, `reads_a_flawed_root`, `unflawed_cause`, `left_flawed` and `right_flawed` in the Rust engine (mostly `ops/message.rs`, `ops/for_line.rs` and `ops/lists.rs`), and `_flaw` in `engines/rego/src/policy/problems.rego` (used in `report/chains.rego` and `report/evaluation.rego`, it returns `"unusable"` or an empty string), `sentence_flaw` in `engines/rust/engine/src/ops/for_line.rs` (a local name and a parameter that hold the `sentence_root_flaw` result), `_cond_flaw`, `_root_read_flaw`, `_plain_root_flaw`, `_leaf_root_flaw`, `_walk_root_flaw`, `_walk_flawed`, `_for_flawed_cause`, `_list_flaw`, `_list_flawed`, `_ref_step_flaw`, `_ref_step_flawed`, `_flawed_root_msgs`, `check_flaws`, `filter_flaws` and the `flaw` and `flaws` arguments in the Rego engine. The bare local name `flawed` is a cause too (39 uses in Rust and Rego), and so is the test helper `flawed_with` in `engines/rust/engine/src/ops/lists/tests.rs` (16 uses). Three test names in Rust say it as well: `a_written_list_or_a_field_on_the_right_is_never_a_flaw` and `a_ref_that_reads_the_wrong_kind_of_value_is_a_flaw_and_a_missing_one_is_not` in `ops/lists/tests.rs`, and `a_walk_without_a_flawed_check_is_not_flawed_and_one_inside_an_any_of_is_asked_too` in `ops/walk/tests.rs`. About 270 lines of code in all, 44 distinct names counting the two spec rule names below.
- **flaw in the spec**: the rule ids `walk.flaws` and `for.flaws` in `spec/semantics.md`, the spec cases and both CHANGELOGs are causes too. Renaming them changes the spec and its changelog, so it is a separate and larger step than renaming code.
- **fault**: in Rust, `root_fault` in `ops/message.rs` returns text. In Rego, `_m_fault` in `messages/faults.rego` returns pairs of a path and the kind wanted (`[check.path, "a number"]`), and the text comes later from `_m_isnt`. Same word, different things, and Rego's `_m_key_fault` returns text like Rust's.
- **problem**: no mismatch found. Both engines use the word only for what `$well_formed` lists.
