# How checks are written as sentences

Draft 0.1, a proposal from [#174](https://github.com/kosli-dev/ergo/issues/174). Nothing implements it yet. This file says how a check written as a one-line sentence, like `approved_by is not empty`, reads into the [model](semantics.md#the-model-of-a-check), what counts as written wrong, and how the report prints it. What a check means once it's read is in [semantics.md](semantics.md), as for today's syntax in [syntax.md](syntax.md).

[`sentences-corpus.md`](sentences-corpus.md) has every check from sdlc-policies, the server's demo and npm-bump policies, pr-reviewer, ergo's examples and Tore's DEV controls written both ways. Every sentence in it parses exactly one way with the phrases below. The phrases, the tally and the misfits come from it.

## The shape of a sentence

**[sentence.line]** A check, a filter, or one condition of a `where`, is one line. It holds one assertion: a thing, then a phrase, then the phrase's arguments.

```
approved_by is not empty
environment is "prod"
every commits.verified is true
every review.incidents.action_ticket, if any, is not empty
some approvers.username where state is "APPROVED" is in $params.internal_staff
count of findings where source is "claude" is claude_found
sum of stages.usd where kind is "model" is total_usd within 0.01
```

**[sentence.forms]** The thing is one of:

- a path, as in `approved_by is not empty`
- `every <path>` or `some <path>`, optionally with `where`, and the assertion is about each item the path ends at
- `count of <path>` or `sum of <path>`, optionally with `where`, and the assertion is about the number
- a path, a `count of` or a `sum of` joined to more terms with `plus`, as in `count of records plus capped is findings_in`

**[sentence.flat]** The grammar is flat, because Rego can't recurse. So:

- one assertion per line
- one `every`, `some`, `count of` or `sum of` per sentence, and only at the start
- `where` holds one or more conditions joined by `and`, and each condition is a path and a phrase, never another `every` or `where`
- `and` joins conditions inside `where` only, never two assertions and never at the top of a sentence
- no `or`, and no brackets except `items[2]`

Two assertions are two checks. "Or" is an `any_of` in the policy around the sentence, because each option has a name and the report says which one passed. Every expression language gets asked for `or` and brackets, and the answer here is no.

## Paths

**[sentence.path.string]** A path is keys joined by `.`, like `git_commit_info.sha1`. A key is written bare when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_`, `$` and `-`, like `coverage-verification`. Any other key is quoted as a JSON string, like `metadata.labels."app.kubernetes.io/name"`, and so is a key that starts with `$`, like `"$schema"`. This is how [syntax.md](syntax.md#naming-a-path) already names paths in the report, so a path from a row can be pasted into a policy.

**[sentence.path.start]** A bare first key is a field of the subject. Inside `where`, and in the argument of `every` and `some`, it's a field of the item instead (see [sentence.argument.item](#every-some-and-where)). `$params` starts at the params, `$input` at the input, and `$<name>` at a name given by `as`. Any other `$<word>` is written wrong, with `unknown name $<word>`.

**[sentence.path.index]** `items[2]` reads the third item of `items`. `item 3 of items`, `first of items` and `last of items` are proposed in #174 as the word forms, and no policy in the corpus needs them.

**[sentence.path.argument]** In an argument, where a phrase expects a value or a path, a quoted string is a value, so a path whose first key is quoted is written with a leading `.`, as jq does: `id is ."$schema"`. The same goes for a field named like a phrase word or a value (see [sentence.words](#words-a-field-cant-be-called)): `state is ."empty"`.

**[sentence.path.dynamic]** `<path> at $params.<key>` reads the key named by the param, as a ref step does today, and the path can go on after it: `artifacts_statuses at $params.artifact_name.attestations_statuses`. The ref after `at` is `$params` or `$input` and one key, or a bare `$<name>`. Without that limit, `at $params.a.b` could end its ref after `a` or after `b`, and the tokenizer found 30 sentences in the corpus that read two ways because of it. The word `at`, and whether a ref can go deeper, are open.

**[sentence.path.keys]** In `from`, `<path> at each of <values>` makes each listed key a subject, as `keys` does today: `artifact.attestations at each of $params.required_scans`. `<path> as $<name>` names each subject, as `each_as` does. Both go at the end, `at each of` first.

## Values

**[sentence.value.scalar]** A value is written as JSON writes a scalar: a string in double quotes, a number, `true`, `false` or `null`. A string can also be in single quotes, which keeps backslashes as written, so a regular expression doesn't need them doubled: `'^\s*FROM'` is `"^\\s*FROM"`. Inside single quotes, `\'` is a quote and `\\` a backslash.

**[sentence.value.list]** A list of values is the values separated by `, `, with no brackets: `is one of "staging", "prod"`. A value can hold a comma, `matches "^fix(, |: )"`, because commas inside quotes don't separate.

**[sentence.value.path]** An argument that isn't a value is a path. So `is "prod"` compares with text and `is total_usd` with a field, which is what today's `equals` and `compare` split was for.

## Words a field can't be called

**[sentence.words]** In an argument, these words are read as part of a phrase or as a value, never as the first key of a path: `a`, `after`, `an`, `at`, `before`, `between`, `count`, `earliest`, `empty`, `equal`, `every`, `false`, `in`, `latest`, `less`, `more`, `not`, `null`, `one`, `some`, `sum`, `true`. Without this, `x is empty` could also compare `x` with a field called `empty`, and `x is true` with a field called `true`. A field with one of these names is written `."empty"`.

## `every`, `some` and `where`

**[sentence.every.walk]** `every <path>` walks into every list along the path, the last one included, and the assertion applies to each value it ends at. `every pull_requests.commits.author` reads the author of every commit of every pull request, and `every branches matches "^release/"` reads each branch of a list of strings. It passes when every value passes. Because the last list is walked too, `every pull_requests.labels is not empty` checks each label, not that each pull request has labels.

**[sentence.every.empty]** `every` over an empty list fails with cause `value`, because no commits isn't proof that every commit is signed. Over nested lists, each inner list must have an item too, as `each` does today.

**[sentence.every.if_any]** `every <path>, if any, <assertion>` passes over empty lists, at every level it walks. A list that's missing, `null` or not a list still fails as `absent`, `null` or `unusable`. `if any` goes after the path, between commas, because a path can't hold a comma and an argument can. With `some`, it's written wrong, with `if any can't go with some`, since "some approver, if any" would let an empty list pass a check that asks for at least one.

**[sentence.some.walk]** `some <path>` walks the same way, and passes when at least one value passes. An empty list fails with `value`.

**[sentence.where.item]** `where` keeps the items that pass every one of its conditions. Its paths start at the innermost item the quantified path walks, the one that holds the field the path ends at, and the assertion is about the value the path ends at. In `some approvers.username where state is "APPROVED" is in $params.internal_staff`, `state` is read on each approver and `username` is what's checked.

**[sentence.where.undecided]** An item that a condition can't decide, because a field it reads is missing, `null` or the wrong type, isn't left out. Under `every`, `count of` and `sum of`, the check fails with that item's cause, as `count ... where` does today. Under `some`, it counts as an item that failed: another item can still pass the check, and if none does, the check fails with the first cause among the items, as `any` does today. `exists` and `does not exist` are the exception, because a missing field is their answer.

**[sentence.where.every]** Under `every`, an item that `where` leaves out isn't checked. When `where` leaves no items, the check fails with `value`, unless it has `if any`. No policy in the corpus uses `every ... where` yet.

**[sentence.argument.item]** Inside `every` and `some`, a path in the argument starts at the item too, so the item can be compared with its own fields. To reach the subject, name it with `as` in `from`: `some approvers.username where state is "APPROVED" is not $pr.author`. To reach the input, start with `$input`.

**[sentence.argument.subject]** After `count of` and `sum of`, the assertion is about one number for the subject, so a path in the argument starts at the subject: in `sum of stages.usd is total_usd`, `total_usd` is the subject's.

## Derived values

**[sentence.derived.count]** `count of <path>` walks the path as `every` does and counts the values it ends at, so `count of findings` is the number of findings. With `where`, it counts the items that pass.

**[sentence.derived.sum]** `sum of <list>.<field>` adds the field up across the items. With `where`, only the items that pass. A sum over no items is 0. Numbers are added as decimals, so `0.1 plus 0.2` is `0.3`.

**[sentence.derived.plus]** `<term> plus <term>` adds numbers. A term is a path, a number, a `count of` or a `sum of`. `plus` can't follow a `where`, because `count of x where n is m plus k is t` would read two ways: the tokenizer found three parses for it. Put the `where` on the last term instead.

**[sentence.derived.compare]** A derived value only goes with `is`, `is not`, `is ... within`, `is at least`, `is at most`, `is more than`, `is less than` and `is between`. `count of approvers is empty` is written wrong.

**[sentence.derived.latest]** Proposed: `latest of <path>` and `earliest of <path>` as an argument, the latest or earliest timestamp in a list. It's the one addition the corpus asks for, to say sdlc-policies' "approved after the last commit" without a second quantifier: `some approvers.timestamp where state is "APPROVED" and username is not $pr.author is after latest of $pr.commits.timestamp`.

## Phrases

Each phrase is a [Cucumber Expression](https://github.com/cucumber/cucumber-expressions), so a port in Go, Java, JavaScript, Python or Ruby gets a matcher for it from the library. The parameters are `{lhs}` (a path, or a derived value with `plus`), `{path}`, `{value}`, `{values}` (values separated by `, `), `{list}` (values, or a path to a list), `{operand}` (a value, or a path with `plus`), `{number}` and `{type}` (`list`, `string`, `number`, `boolean` or `object`).

Each polarity is its own expression. Cucumber's `( not)` matches both but doesn't say which, and its `/` alternates single words only, so `{path} contains/does not contain {value}`, as #174 wrote it, compiles to `(contains|does) not contain` and never matches `contains`.

"Missing", "`null`" and "wrong type" say what a check does when a value it reads is in that state. Everything a phrase reads fails that way, the argument's path or ref included. Every failure that isn't `value` makes a filter fail the requirement instead of ruling the subject out.

**[sentence.phrase.is]** `{lhs} is {operand}` and `{lhs} is not {operand}`. The field equals, or doesn't equal, the argument, as [value.equal](semantics.md#values) says. Missing: `absent`. `null`: passes `is null`, otherwise fails as `null`. Wrong type: with a value as the argument, `is` fails as `value`, because `"5"` isn't `5` is a sound answer, as today's `equals`. With a path, or with `is not`, two values of different types fail as `unusable`, as today's `compare`.

**[sentence.phrase.within]** `{lhs} is {operand} within {number}`. Two numbers at most that far apart. The number is 0 or more. Missing: `absent`. `null`: `null`. Wrong type: `unusable`.

**[sentence.phrase.one_of]** `{lhs} is one of {values}` and `{lhs} is not one of {values}`. The field equals one of the values, or none of them. Missing: `absent`. `null`: `null`, even when the values include `null`. Wrong type: `is one of` fails as `value`, and `is not one of` passes, since a number isn't one of three strings. An empty list can't be written.

**[sentence.phrase.in]** `{lhs} is in {path}` and `{lhs} is not in {path}`. The same, with the list read from a path, usually `$params`. Missing: `absent`. `null`: `null`. A list that isn't a list: `unusable`. An empty list fails `is in` as `value`, and passes `is not in`.

**[sentence.phrase.exists]** `{lhs} exists` and `{lhs} does not exist`. As today's `present` and `missing`: a field that's missing or `null` fails `exists` with `value` and passes `does not exist`. Wrong type: never, since any value exists. A parent that can't hold the field fails both as `unusable`.

**[sentence.phrase.empty]** `{lhs} is empty` and `{lhs} is not empty`. `is empty` passes on `[]` and `""`. `is not empty` passes on a list with an item or a string with a character. Missing: `absent`. `null`: `null`. Wrong type, a number, a boolean or an object: `unusable`. This is wider than today on two counts, both open: `is not empty` passes a non-empty list where `non_empty_string` fails, and `is empty` passes `""` where `empty` fails.

**[sentence.phrase.type]** `{lhs} is a {type}` and `{lhs} is an {type}`. The field has that JSON type. Missing: `absent`. `null`: `null`. Wrong type: `value`, because checking the type is the phrase's job.

**[sentence.phrase.contains]** `{lhs} contains {operand}` and `{lhs} does not contain {operand}`. The field is a list that holds the value, or doesn't. Missing: `absent`. `null`: `null`. Not a list: `unusable`. `does not contain` passes on an empty list.

**[sentence.phrase.contains_all]** `{lhs} contains all of {list}` and `{lhs} contains none of {list}`. The field is a list that holds every value, or none of them. Missing, `null` and not a list as `contains`. An empty list written in the sentence can't be written, and one read from a path fails as `unusable`, because it would pass every list.

**[sentence.phrase.matches]** `{lhs} matches {list}` and `{lhs} does not match {list}`. The field is a string that matches at least one of the regular expressions, or none of them. They aren't anchored. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A pattern that isn't a valid regular expression is written wrong when it's in the sentence and fails as `unusable` when it's read from a path.

**[sentence.phrase.starts]** `{lhs} starts with {operand}` and `{lhs} ends with {operand}`. New, and unused in the corpus. Both sides are strings. Missing: `absent`. `null`: `null`. Not a string: `unusable`.

**[sentence.phrase.order]** `{lhs} is at least {operand}`, `is at most`, `is more than` and `is less than`. Both sides are numbers, or both are strings. Missing: `absent`. `null`: `null`. Anything else, two types that differ included: `unusable`.

**[sentence.phrase.between]** `{lhs} is between {value} and {value}`. A number from the first to the second, both included. The bounds are numbers, and the first isn't above the second, or it's written wrong. Missing: `absent`. `null`: `null`. Not a number: `unusable`. Its `and` belongs to `between`, so `where qty is between 1 and 5 and kind is "a"` has two conditions. An implementation that splits `where` on ` and ` has to skip the one after `between <value>`.

**[sentence.phrase.time]** `{lhs} is before {operand}`, `is after`, `is not before` and `is not after`. Both sides are timestamps in the same format, both RFC 3339 strings or both numbers, as today's `compare_time`. `is not before` means "on or after": it still fails when either side isn't a timestamp. Missing: `absent`. `null`: `null`. Wrong type or format: `unusable`. These words are open: `is on or after` and `is on or before` might read better.

**[sentence.phrase.aliases]** `{lhs} equals {operand}` and `{lhs} is equal to {operand}` are read as `is`, and `{lhs} does not equal {operand}` as `is not`. With them in the grammar, every sentence in the corpus still has exactly one reading.

**[sentence.derived.fail]** `count of` and `sum of` over a list that's missing, `null` or not a list fail as `absent`, `null` or `unusable`. A number to add that isn't a number fails as `unusable`. `every` and `some` fail the same way on the list they walk.

## Written wrong

**[sentence.written_wrong.slot]** A sentence that doesn't parse is written wrong, as a check that can't be read into the model is today. Its rows fail with `ill_formed` and `$well_formed` lists it. Because the grammar is flat, the message can name the slot, what it expected and the column:

| sentence | `$well_formed` says |
| --- | --- |
| `approved_by is empy` | `unknown phrase "is empy" at column 13, expected one of: is empty, is not empty, is one of, ...` |
| `environment is "prod` | `unclosed quote at column 16` |
| `every commits.signed` | `nothing after the path at column 21: expected a phrase, like "is" or "exists"` |
| `sum of stages.usd is total within` | `"within" needs a number after it` |
| `some approvers, if any, is not empty` | `if any can't go with some` |
| `every pull_requests some approvers.state is "APPROVED"` | `two quantifiers in one sentence: put the inner list in its own subject` |

`environment is prod` parses, as a comparison with a field called `prod`, unless the subject has no such field. That's the one mistake the grammar can't catch, so the message for a missing field in an `is` argument should suggest quotes.

## Printing the sentence

**[sentence.print.canonical]** The report's `expression` is the sentence printed from its parse in one spelling: single spaces, the first phrase in each rule above rather than an alias, strings in double quotes with JSON escapes, numbers in their plain form, and values separated by `, `. Parsing the printed sentence gives the same parse.

**[sentence.print.same]** For a sentence written that way, the printed form is byte for byte what the author wrote. In the corpus, 374 of 376 sentences print back unchanged. The other two are the same check written with single quotes, `entry does not match '^[A-Za-z0-9._-]+\s*(>=|<=|~=|!=|<|>)'`, which prints as `"^[A-Za-z0-9._-]+\\s*(>=|<=|~=|!=|<|>)"`. Whether the canonical form keeps single quotes for a string with a backslash is open.

## How this was checked

A throwaway tokenizer in JavaScript, outside the repo, compiled each phrase above with `@cucumber/cucumber-expressions` 18.0.1 and tried every way to cut each sentence into a quantifier, a path, `where` conditions and a phrase. It counted every reading.

With the rules as #174 states them, all 376 sentences in the corpus parse, and 213 parse more than one way:

| cause | sentences | rule that removes it |
| --- | ---: | --- |
| a quoted string could be text or a quoted key, `is "prod"` | 94 | [sentence.path.argument](#paths) |
| a phrase word could be a field, `is empty` against `is <field empty>` | 60 | [sentence.words](#words-a-field-cant-be-called) |
| `true`, `false` or `null` could be a field | 55 | both of the above |
| a dynamic key's ref could end at more than one key | 30 | [sentence.path.dynamic](#paths) |

Some sentences have two causes. With the rules in this file, every sentence parses exactly one way. Ten made-up sentences test what the corpus doesn't reach: `plus` after `where` read three ways until [sentence.derived.plus](#derived-values) forbade it, and `if any` with `some`, two quantifiers and `count of ... is empty` parse no way, as they should.
