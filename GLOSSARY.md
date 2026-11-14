# Glossary

The words the code of both engines uses for the ideas of Ergo, and what each one means. It's for people who work on Ergo. [`REFERENCE.md`](REFERENCE.md) is for people who write policies, and it says "cause" where the code says "flaw", for example.

The aim is one word for one idea. Some words aren't there yet, and the last section lists where.

## subject

The thing a requirement checks, like a deployment or a pull request, and also each one of them. [`REFERENCE.md`](REFERENCE.md) says "A subject is the kind of thing a requirement checks" and, a few lines later, "each item is a subject".

- Rust: `find_subjects` in `subjects.rs` finds them, `Subject` in `policy.rs` is the definition written in the policy, and `Ctx.subject` in `path.rs` is the one being checked.
- Rego: `_subject_def` in `policy/subjects.rego` is the definition, and `subj` is the value being checked in most rules.

## entry

One element of a list in the report, written `{"name": ..., "value": ..., "locations": [...]}`. `REFERENCE.md` puts it like this: "Every entry in a row's `inputs`, in a check's `$refs` and in `failed_items` has `locations`".

- Rust: `input` in `report.rs` builds one, and `subject_entry` builds a subject's entry in `subjects`.
- Rego: `_entry_ref` in `reading/values.rego` and `_entry_anchor` in `report/requirements.rego`.

The Rust engine also has two structs called `Entry` that aren't this: one in `subjects.rs`, a subject with where it was found, and one in `ops/walk.rs`, one step of a walk.

## item

One element of a list that a check or a `from` line reads, like a file in `files`. In a report it shows as `"item": "item 1 of files"` in `failed_items`, and `REFERENCE.md` writes "An item of the list that isn't an object, like a string or a `null`, is still a subject."

- Rust: `WalkItem` in `ops/walk.rs`, and `ItemAt` in the same file.
- Rego: `_item_at` in `lines/walk.rego`, and `data.ergo_item`.

## root

Where a name starts reading. Outside a relative clause that's the subject, unless the name is `$input`, `$params`, a `for` name, a part, a parent subject's name or the subject's own name. `REFERENCE.md` says "Everywhere else a name resolves from its root". Inside a relative clause, a name starts at the focus instead.

- Rust: `is_root` and `root` in `path.rs`, `from_a_root` in `ops/walk.rs`, `root_text` in `ops/message.rs`.
- Rego: `_root_read_flaw` and `_plain_root_flaw` in `lines/roots.rego`.

## focus

What a relative clause is about, like each approver. `REFERENCE.md` gives `xs whose count of ys.k is 1`, where `k` of each `y` is read inside the focus, and says "inside one a name resolves against the focus, the thing the clause is about".

- Rust: `focus_ctx` and `focus_lost` in `ops/walk.rs`.
- Rego: `_focus_entry` in `lines/walk.rego` and `_tally_focus_cause` in `checks/derived.rego`.

## problem

Something wrong in the policy as written, like `unknown field op`. A problem fails the `$well_formed` row, and `REFERENCE.md` says "A problem fails `$well_formed` on every requirement that names a subject whose chain has it". It's about what the author wrote, never about the input.

- Rust: `Problems` and `add_problem` in `policy.rs`, `well_formed_row` in `report.rs`.
- Rego: `policy/problems.rego`, like `_unknown_problems`, and `_well_formed` in `report/requirements.rego`.

## fault

Why one item failed its check, a fact about the data, as text: `$params.q is "s", which isn't a number`. A fault is a piece of a row's message. `REFERENCE.md` never uses the word.

- Rust: `root_fault` in `ops/message.rs`, and the text `for_line.rs` builds in `own_beside_root` and around `root_fault`.
- Rego: `_m_fault` and `_m_faults` in `messages/faults.rego`, and `_tally_root_fault` in `lines/roots.rego`.

## flaw

How a root couldn't be read: `absent`, `null` or `unusable`. It's the cause inside a fault, so the fault says it in words and the flaw is the word the row's `cause` takes. `REFERENCE.md` calls these causes and never uses "flaw".

- Rust: `root_flaw` in `ops/message.rs`, which returns the cause and the text.
- Rego: `_cond_flaw` and the `flaws` arguments in `checks/derived.rego`, `_root_read_flaw` in `lines/roots.rego`.

## Places that don't match yet

These feed the renames later. Nothing here has changed.

- **subject**: three ideas under one word. `Subject` in `engines/rust/engine/src/policy.rs` is the definition, `Ctx.subject` in `path.rs` is one value, and `REFERENCE.md` uses it for both the kind and each one. A kind of thing and one of them need two words.
- **entry**: `Entry` in `engines/rust/engine/src/subjects.rs` and `Entry` in `ops/walk.rs` are two structs for two ideas, and neither is the report's entry. `_focus_entry` in `engines/rego/src/lines/walk.rego` is the walk one, and `_entry_ref` in `engines/rego/src/reading/values.rego` is a subject found in the input.
- **item**: `Item` in `engines/rust/engine/src/checks.rs` is one line of a check (its text and what it does), `Item` in `ops/for_line.rs` is the part of a `for` line that picks something, and `WalkItem` in `ops/walk.rs` is one list element. Only the last one is what `REFERENCE.md` calls an item.
- **root**: `Location.root` in `engines/rust/engine/src/path.rs` is which document a value came from, `Input` or `Params`, which `REFERENCE.md` calls "the root of the params". `_is_root` in `engines/rego/src/policy/subjects.rego` means a subject with no `of`, a subject nothing is built on.
- **flaw**: `_number_flaw` and `_number_flaws` in `engines/rego/src/checks/leaf_ops.rego`, `meta_number_flaws` in `engines/rust/engine/src/policy.rs` and `_from_path_flaws` in `engines/rego/src/lines/from_lines.rego` are problems in the policy, not flaws of a root. `_for_flawed_cause` in `lines/for_lines.rego` and `_walk_flawed` in `lines/walk.rego` use "flawed" for the cause as well.
- **cause and flaw**: `Cause` in `engines/rust/engine/src/cause.rs` and the `cause` of a row are what `REFERENCE.md` calls a cause, and `flaw` is the same thing when it is a root's. Two words for one idea, unless a flaw is kept to the unreadable ones (`absent`, `null`, `unusable`).
- **fault**: in Rust, `root_fault` in `ops/message.rs` returns text. In Rego, `_m_fault` in `messages/faults.rego` returns pairs of a path and the kind wanted (`[check.path, "a number"]`), and the text comes later from `_m_isnt`. Same word, different things, and Rego's `_m_key_fault` returns text like Rust's.
- **problem**: no mismatch found. Both engines use the word only for what `$well_formed` lists.
