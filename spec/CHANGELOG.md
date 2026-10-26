# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.2

### New

- A `whose` in a subject's `from` line takes a one-line `some` or `every` as a condition ([sentence.subject.condition](syntax.md#subjects)), like `release whose some files.path does not match "^docs/"`. Its `$applies` row gives the inputs and the cause the same sentence gives as a check row. Reports for policies written before don't change, and a policy that used to be written wrong there is now read.

### Changed

- `main` follows the unreleased 0.2, so `ergo_spec` is `v0.2-dev` and a report's `ergo` says `v0.2-dev`. A policy that says `v0.1` is written wrong on `main`, with `unsupported version v0.1, expected v0.2-dev`. [policy.version](syntax.md#policies) takes an optional `-dev` after the version, so `v0.2-dev` is a version and `v0.2-beta` is not. The `$id` of both schemas is under `https://ergo.kosli.com/spec/0.2-dev/`. Reports change in `ergo`, from `v0.1` to `v0.2-dev`.

## 0.1

The first version. Policies need `ergo_spec: v0.1` at their top, and reports get `ergo` and `engine` there.

Before it, the spec had no version, and Ergo read policies written in an older shape: checks as objects with `op` and `path`, subjects with `applies_to` filters, custom operators added as Rego rules, and substitutes. The changes below are against that shape, for anyone with a policy or reports from before 0.1. `ergo.as_sentences` rewrites such a policy into sentences where it can.

- One version for the policy, the report and what one means for the other. A policy names it in `ergo_spec`, and a report in `ergo`.
- A report says what made it in `engine`.
- A report's hash is the SHA-256 of the report without `engine`, written as RFC 8785 says.
- The schemas have `$id`s under `https://ergo.kosli.com/spec/0.1/`.
- Custom operators, which a policy added as `op_passed` rules in the `ergo` package, go, because a sentence can't call one. They come back once a definition format is built, see [OPEN.md](OPEN.md#custom-operators).
- Substitutes, a `substitute` check that satisfied another when it failed, go, since an `any_of` of sentences says the same. Reports lose the `substituted` cause.
- Checks are sentences only. A check written as an object with `op` is written wrong, with `missing assert` and `unknown field op`, and so are `all`, `any`, `inputs`, `literal`, `ref` values, selectors and derived sides written by hand.
- Subjects are written with `from` lines only. A `from` or `identified_by` that isn't a string is written wrong with `not a string`, and `applies_to` and `of` are unknown fields. Literal key lists, selectors in `from` and `identified_by`, and filter names, descriptions and meta have no `from` line form and go with them.
- A requirement written wrong gets only its `$well_formed` row, and its `subjects` counts are 0. Reports lose the `ill_formed` cause, which only such a requirement's rows had. A filter written wrong on a parent subject now fails the `$well_formed` row of each requirement on its children too.
- Reports lose the `unmatched` cause, which only a selector gave, and a check's entry in `requirements` has only `description`, `meta`, `expression` and `$refs`. Its `expression` is always the sentence, printed as [sentence.print.canonical](syntax.md#printing-the-sentence) says.
- A position read from a param that holds a number above 9007199254740991 is `unusable`. It used to read nothing, so `does not exist` passed. A check on such a path fails as `unusable`, so does a check on a part whose path reads it, where it failed as `value`, and a `from` line like `ls[$params.big]` fails `$min_subjects` as `unusable`, where it failed as `absent`.
- `$well_formed`, `$min_subjects`, `$unique_ids` and `$applies` are reserved: a check with one of those names is written wrong with `name reserved`, where it used to add a second row of that name.
- A `from` line that loops through a child subject says `leads to a loop`, where it said `a chain of more than three subjects isn't supported yet`.
