# Changes to the spec

Each version says whether reports changed, so that anyone who only stores reports knows when to look.

## 0.1, not released yet

The first version. Policies need `ergo_spec: v0.1` at their top, and reports get `ergo` and `engine` there.

- One version for the policy, the report and what one means for the other. A policy names it in `ergo_spec`, and a report in `ergo`.
- A report says what made it in `engine`.
- A report's hash is the SHA-256 of the report without `engine`, written as RFC 8785 says.
- The schemas have `$id`s under `https://ergo.kosli.com/spec/0.1/`.
- Custom operators go, because a sentence can't call one. They come back once a definition format is built, see [OPEN.md](OPEN.md#custom-operators).
- Substitutes go, since an `any_of` of sentences says the same. Reports lose the `substituted` cause.
- Checks are sentences only. A check written as an object with `op` is written wrong, with `missing assert` and `unknown field op`, and so are `all`, `any`, `inputs`, `literal`, `ref` values, selectors and derived sides written by hand.
- Subjects are written with `from` lines only. A `from` or `identified_by` that isn't a string is written wrong with `not a string`, and `applies_to` and `of` are unknown fields. Literal key lists, selectors in `from` and `identified_by`, and filter names, descriptions and meta have no `from` line form and go with them.
- A requirement written wrong gets only its `$well_formed` row, and its `subjects` counts are 0. Reports lose the `ill_formed` cause, which only such a requirement's rows had. A filter written wrong on a parent subject now fails the `$well_formed` row of each requirement on its children too.
- Reports lose the `unmatched` cause, which only a selector gave, and a check's entry in `requirements` has only `description`, `meta`, `expression` and `$refs`. Its `expression` is always the sentence, printed as [sentence.print.canonical](syntax.md#printing-the-sentence) says.
- A position read from a param that holds a number above 9007199254740991 is `unusable`. It used to read nothing, so `does not exist` passed. A check on such a path fails as `unusable`, so does a check on a part whose path reads it, where it failed as `value`, and a `from` line like `ls[$params.big]` fails `$min_subjects` as `unusable`, where it failed as `absent`.
