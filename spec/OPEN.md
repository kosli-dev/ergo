# Open questions

Things the spec doesn't settle yet, because they need a decision first. Open questions about the spec live here, not in issues.

## Custom operators

0.1 has no custom operators, because a sentence can't call one and no policy downstream defined one (see [#1](https://github.com/kosli-dev/ergo/issues/1)). They come back once the definition below is built.

Decided on 2026-10-16: the spec will take the definition the Rust port uses, on the `core/conformance-suite` branch: a plain JSON object that users and auditors can read, with the name, each parameter's kind (`path`, `paths`, `value`, `number`, `string`) and type, an expression template and a version. The body stays up to each implementation: a Rego rule in `ergo.rego`, CEL or anything else in a port. Ergo then checks for missing, `null` and wrong-typed values in one place instead of trusting every operator to, checks don't repeat `expression` and `inputs`, and a report says which definitions produced it, with a SHA-256 of each. The parameters' names and kinds are also what a sentence needs to call an operator, because they say whether a word after it is a path or a value. Two implementations can still give the same definition different bodies, and the report can't show that.

It's put off until a control needs logic that no phrase covers. On 2026-10-16, pr-reviewer was the only known policy with custom operators, and all seven of them can be written as sentences that Ergo runs. The last one, `contains_all`, is `contains all of` with a field of the subject, and so is DEV-0406's `does not contain`, both since #224. The deadlines DEV-0401, 0402, 0705 and 0802 work out in Rego can be sentences too since #232 and #234, with `days elapsed from X to Y` and a limit looked up by a field of the subject. Allowing one inside `every` and `some` is a separate question for Rego, which can't recurse.

### Where sentences fall short

When a policy needs something no sentence can say, the first question is whether it should be a phrase. On 2026-10-21 every MUST line of Kosli's 23 SDLC controls (sdlc.kosli.com) was written against the evidence Kosli records: the CLI's attestation types, the test data in kosli-dev/sdlc-policies and the server's models. Each sentence was run on a passing and a failing input. Of 105 lines, 37 can be written today, 15 in part, 6 are human judgement or a promise about the future, and 46 need evidence Kosli doesn't record. Only a few lines are short of words:

| Gap                      | Example                                                                | Needed by      | Where it belongs                                                                                                                   |
| ------------------------ | ---------------------------------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Pick by order            | the author of the last commit                                          | SDLC-CTRL-0007 | a `for` item, [sentence.for.pick](syntax.md#the-for-line), runs                                                                    |
| A sentence in `any_of`   | the declared licence, else the one the params give for the name        | SDLC-CTRL-0004 | an `any_of` of sentences, [sentence.any_of](syntax.md#the-shape-of-a-sentence), runs                                               |
| Parsing and decoding     | lockfile and Dockerfile lines, SPDX expressions, base64, signed tokens | SDLC-CTRL-0004 | before Ergo, when the evidence is attested, so the report still shows the facts                                                    |
| Calendar time            | renewed every 12 months                                                | none           | `months` and `years elapsed`, once a control needs them. Fixed units run (#234)                                                    |
| Arithmetic beyond `plus` | coverage as `covered / total`, an average                              | none           | more derived values next to `count of`, `sum of` and `plus`                                                                        |
| Distinct counts          | at least 2 distinct reviewers                                          | none           | a derived value, like `count of distinct approvers.username`                                                                       |
| Orderings of one domain  | version order, a network range, a glob                                 | none           | a custom operator, because each has its own rules                                                                                  |
| Recursion                | dependencies of dependencies                                           | none           | before Ergo. Rego can't recurse, so a custom operator can't either                                                                 |
| Rules across subjects    | at most 5% of deployments failed                                       | none           | something on the requirement, since a check sees one subject at a time                                                             |

"Needed by" lists the SDLC controls that hit the gap. The rows marked "none" were guesses before that check, and no SDLC line needed them.

A gap that many controls share becomes a phrase or a derived value, which stays readable, runs the same everywhere and fails closed in one place. A gap that belongs to one domain becomes a custom operator, with a definition that says what it means. Parsing and decoding stay out of Ergo, because an operator that decodes hides the evidence from the report as much as Rego that runs before Ergo does.

The same check found two ways a check passes when it shouldn't. A sentence that compares a path with itself always passes, which happens when a `whose` or a one-line `every` reads a bare key that the writer meant as the subject's ([#273](https://github.com/kosli-dev/ergo/issues/273)). And numbers held as strings, as Sonar records them, are ordered as text, so `"9"` is at least `"80"` ([#274](https://github.com/kosli-dev/ergo/issues/274)).

## Parts

A subject's parts (`has`, see [syntax.md](syntax.md#parts)) leave a few things open:

- `named by` a bare word that is a part's alias is written wrong. It would have to read the part's value and use it as a key, as it does for a `for` alias, and nothing says yet whether a part that is a path with its own `named by` can be used that way.

## Time limits

`time.format` only takes years 1678 to 2261 and only counts the first nine digits of a fraction. Both limits come from OPA, which holds a time as nanoseconds since 1970 in a 64-bit integer. A port in another language would have to add them on purpose. Either they stay, and the spec keeps them as a rule every implementation follows, or the spec drops them and `ergo.rego` has to compare times some other way outside that range.

## Which steps a walk walks

`every` and `some` walk "into every list along the path" ([walk.lists](semantics.md#every-and-some)), and Ergo decides that from the data: a step is walked when at least one value there is a list, and then every value there must be one. So `every prs.commits.signed is true` on `{"prs": [{"commits": {"signed": true}}]}` passes, because `commits` is an object and nothing is walked at that step, but the same pull request fails as `unusable` when another one has a list of commits. It fails closed whenever the data shows a list, and only passes data shaped wrong when every item is shaped wrong the same way and the wrong shape still holds a field that passes.

Three ways to settle it:

- Keep it as it is, and say so in the spec.
- Have the author mark the lists, like `every prs[].commits[].signed`. That changes the grammar of [#174](https://github.com/kosli-dev/ergo/issues/174), and costs some of its plain reading.
- Give Ergo the shape of the input, as a schema, so a step is walked because the schema says it holds a list. [#191](https://github.com/kosli-dev/ergo/pull/191) already declares a schema for part of `input`.

## Sentences the spec doesn't say enough about yet

`ergo.rego` doesn't run these forms, and the spec doesn't pin down their rows, so there are no cases for them. A case for each can go in once the question is settled, and be listed in `known_differences` in `spec_test.rego` while `ergo.rego` fails it.

- `it` on the right side of a phrase, like `x is it` or `x is one of it`: left out for now, so it's written wrong (see [#323](https://github.com/kosli-dev/ergo/issues/323)).
- `last of`: what a row's `inputs` name is. `first of xs` prints `item 1 of xs`, because the position is known when the sentence is read. The last position isn't, and an empty list has no item to number. It could print `last of xs`, or `item 3 of xs` for a list of three and something else for an empty one. The meaning is clear: the last item, absent on an empty list, `unusable` on something that isn't a list, as `first of` is.
- `count of`, `sum of` and `plus` in the phrase of an `every` or `some`, like `every xs is count of ys`, and an elapsed time there, like `every xs is days elapsed from started to ended`: [sentence.argument.item](syntax.md#every-some-and-whose) says a path in the argument starts at the item, but not what the row's `inputs` show for a number worked out from each item.
- An elapsed time in the `whose` of a `count of`, a `sum of` or an `every`, when an item can't be decided: which path `failed_items` names when the check reads two, `started` or `ended`.
- An elapsed time in a subject's `from` line, like `vulns whose days elapsed from started to ended is 1`: what the `$applies` row shows for it, and which paths its `inputs` list.
- A `plus` in the `whose` of a `count of` or a `sum of`, like `count of xs whose a plus b is 3 is 1`: whether a `whose` condition can have `plus` on its left.

## Numbers in a report's hash

[report.hash](semantics.md#statuses) writes the report as RFC 8785 says, and RFC 8785 writes every number as a 64-bit float. Ergo copies numbers from the input into the report with every digit, so a report holding `1.00000000000000000001` hashes as if it held `1`. Two reports that differ only there get the same hash. A number too big or too small for a 64-bit float, like `1e400`, can't be written that way at all, and implementations already write it differently in the report (see [Values](semantics.md#values)). The open question is whether that's fine, or whether the hash should write numbers as the report does.

## Numbers with huge exponents

OPA crashes when it compares a number whose exponent is beyond ±1e6 with any other number, from the input, the params or the policy, so `ergo.rego` gives no report at all. `size is at least 5` on this input stops OPA 1.20.2 with `panic: illegal value` in `ast.NumberCompare`:

```json
{"items": [{"size": 1e1000001}]}
```

`1e-1000001` does the same, and so does `size is at least limit` on `{"items": [{"size": 1e1000000, "limit": 1e1000001}]}`. `1e1000000` against `5` is compared correctly, and so is `1e400` against `1e401`. The crash doesn't need a check that compares anything: OPA sorts subject ids, so `identified_by: id` on two subjects with ids `1e1000000` and `1e1000001` crashes too, whatever the check says.

[Values](semantics.md#values) allows a fix that fails such a check as `unusable`. That can't cover the sort of subject ids, because no check row reads them. Both wait for a real need, or for OPA to fix the crash.

## Where ergo.rego and the Rust port differ

The spec doesn't settle these yet, because the two engines give different reports. Both still fail and pass the same checks.

- **A check with a field it doesn't take.** [sentence.print.written_wrong](syntax.md#printing-the-sentence) doesn't say how a check prints when its sentences read but it has an unknown field, a `for` that isn't a string, or `for` or `assert` next to `any_of`. `ergo.rego` prints it as written and Rust prints it from its parse, so `{"assert": " x  is  1", "zzz": 1}` gives `x  is  1` with one and `x is 1` with the other.

## Rules without cases

Every rule needs a case, apart from the ones listed here. The `sentence` rules here are for forms `ergo.rego` doesn't run or check yet. `report.engine` gives different values for each engine, so a case can't pin it, and `ergo_test.rego` tests it instead. `report.hash` waits for the question about hashing numbers above. `report.keys` is about how the report is written out, and a case compares a report as values, where the order of keys doesn't count. `check_rules.py` fails when a rule on this list has a case or doesn't exist, so the list stays true.

- `sentence.forms`
- `sentence.subject.depth`
- `sentence.argument.subject`
- `report.engine`
- `report.keys`
- `report.hash`

## Sentences the ABNF and ergo.rego read differently

`check_grammar.py` reads sentences with `ergo.rego` and with a parser built from `sentences.abnf`, and fails on any sentence that one reads and the other rejects as a matter of syntax. A disagreement goes here, as a line like ``- check `"x is 1"` ``, with the sentence written as JSON, until it's decided. The script also fails when a listed one stops disagreeing. None is listed now.
