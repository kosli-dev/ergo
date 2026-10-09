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

A check that walks two lists, or compares an item with its subject, puts the walking on a [`for` line](#the-for-line) and keeps the assertion flat.

**[sentence.flat]** The grammar is flat, because Rego can't recurse. So:

- one assertion per line
- one `every`, `some`, `count of` or `sum of` per sentence, and only at the start. A second one goes on a `for` line
- `where` holds one or more conditions joined by `and`, and each condition is a path and a phrase, never another `every` or `where`
- `and` joins conditions inside `where` only, never two assertions and never at the top of a sentence
- no `or`, and no brackets except `items[2]`

Two assertions are two checks. "Or" is an `any_of` in the policy around the sentence, because each option has a name and the report says which one passed. Every expression language gets asked for `or` and brackets, and the answer here is no.

## Paths

**[sentence.path.string]** A path is keys joined by `.`, like `git_commit_info.sha1`. A key is written bare when it starts with an ASCII letter or `_` and the rest is ASCII letters, digits, `_`, `$` and `-`, like `coverage-verification`. Any other key is quoted as a JSON string, like `metadata.labels."app.kubernetes.io/name"`, and so is a key that starts with `$`, like `"$schema"`. This is how [syntax.md](syntax.md#naming-a-path) already names paths in the report, so a path from a row can be pasted into a policy.

**[sentence.path.start]** A bare first key is a field of the subject. Inside `where`, and in the argument of a one-line `every` or `some`, it's a field of the item instead (see [sentence.argument.item](#every-some-and-where)). A name given by `as` on a `for` line is a bare word too, and it shadows a field with the same name. `$params` starts at the params and `$input` at the input. Any other `$<word>` is written wrong, with `unknown name $<word>`.

**[sentence.path.index]** `items[2]` reads the third item of `items`, as [sentence.path.brackets](#paths) says. `item 3 of items`, `first of items` and `last of items` are proposed in #174 as the word forms, and no policy in the corpus needs them.

**[sentence.path.argument]** The left side of a sentence is always a path. The right side can be a value or a path, and these rules decide which:

- A quoted string on the right side is text. `is "prod"` compares with the text prod, never with a field called `"prod"`.
- A word of the grammar on the right side is never a field name (see [sentence.words](#words-a-field-cant-be-called)). `is empty` is the phrase, `is true` is the value.
- A field with one of those names is written with a dot in front: `is .empty`, `is .true`. The dot is allowed on any field on the right side, so `is .total_usd` means `is total_usd`, and the report prints it only where it's needed.
- A key that has to be quoted, like `$schema`, is written with the dot too: `is ."$schema"`.

**[sentence.path.dynamic]** `<path> named by <reference>` reads the key that the reference holds, as a ref step does today, and the path can go on after it: `artifacts_statuses named by $params.artifact_name.attestations_statuses`. The reference is `$params` or `$input` plus one key, or a name from a `for` line, like `persona_blob_shas named by persona`. Without that limit, `named by $params.a.b` could end the reference after `a` or after `b`, and the tokenizer found 31 lines in the corpus that read two ways because of it.

**[sentence.path.brackets]** Brackets are the other spelling: `artifacts_statuses[$params.artifact_name]`, `persona_blob_shas[persona]`, and `items[2]` for a position. In brackets the type decides, as in JSON: a string picks a key and a number picks a position. The report prints the word form.

**[sentence.path.keys]** In `from`, `<path> named by each of <list>` makes each listed key a subject, as `keys` does today: `artifact.attestations named by each of $params.required_scans`. There is no bracket form for it, because `a[x]` picks one thing in every language, and a parameter meant to be one name that arrives as a list would turn one subject into several instead of failing. `from` doesn't name its subjects: the checks that used `each_as` names have a `for` line, where the subject's fields are bare.

## Values

**[sentence.value.scalar]** A value is written as JSON writes a scalar: a string in double quotes, a number, `true`, `false` or `null`. A string can also be in single quotes, which keeps backslashes as written, so a regular expression doesn't need them doubled: `'^\s*FROM'` is `"^\\s*FROM"`. Inside single quotes, `\'` is a quote and `\\` a backslash.

**[sentence.value.list]** A list of values is the values separated by `, `, with no brackets: `is one of "staging", "prod"`. A value can hold a comma, `matches "^fix(, |: )"`, because commas inside quotes don't separate.

**[sentence.value.path]** An argument that isn't a value is a path. So `is "prod"` compares with text and `is total_usd` with a field, which is what today's `equals` and `compare` split was for.

## Words a field can't be called

**[sentence.words]** On the right side, these words are read as part of a phrase or as a value, never as the first key of a path: `a`, `after`, `an`, `and`, `as`, `at`, `before`, `between`, `count`, `each`, `empty`, `equal`, `every`, `false`, `in`, `less`, `more`, `named`, `not`, `null`, `of`, `on`, `one`, `or`, `plus`, `some`, `sum`, `true`, `where`, `within`. Without this, `x is empty` could also compare `x` with a field called `empty`, and `x is true` with a field called `true`. A field with one of these names is written `.empty`.

## `every`, `some` and `where`

**[sentence.every.walk]** `every <path>` walks into every list along the path, the last one included, and the assertion applies to each value it ends at. `every pull_requests.commits.author` reads the author of every commit of every pull request, and `every branches matches "^release/"` reads each branch of a list of strings. It passes when every value passes. Because the last list is walked too, `every pull_requests.labels is not empty` checks each label, not that each pull request has labels.

**[sentence.every.empty]** `every` over an empty list fails with cause `value`, because no commits isn't proof that every commit is signed. Over nested lists, each inner list must have an item too, as `each` does today.

**[sentence.every.if_any]** `every <path>, if any, <assertion>` passes over empty lists, at every level it walks. A list that's missing, `null` or not a list still fails as `absent`, `null` or `unusable`. `if any` goes after the path, between commas, because a path can't hold a comma and an argument can. With `some`, it's written wrong, with `if any can't go with some`, since "some approver, if any" would let an empty list pass a check that asks for at least one.

**[sentence.some.walk]** `some <path>` walks the same way, and passes when at least one value passes. An empty list fails with `value`.

**[sentence.where.item]** `where` keeps the items that pass every one of its conditions. Its paths start at the innermost item the quantified path walks, the one that holds the field the path ends at, and the assertion is about the value the path ends at. In `some approvers.username where state is "APPROVED" is in $params.internal_staff`, `state` is read on each approver and `username` is what's checked.

**[sentence.where.undecided]** An item that a condition can't decide, because a field it reads is missing, `null` or the wrong type, isn't left out. Under `every`, `count of` and `sum of`, the check fails with that item's cause, as `count ... where` does today. Under `some`, it counts as an item that failed: another item can still pass the check, and if none does, the check fails with the first cause among the items, as `any` does today. `exists` and `does not exist` are the exception, because a missing field is their answer.

**[sentence.where.every]** Under `every`, an item that `where` leaves out isn't checked. When `where` leaves no items, the check fails with `value`, unless it has `if any`. No policy in the corpus uses `every ... where` yet.

**[sentence.argument.item]** In a one-line `every` or `some`, a path in the argument starts at the item too, so the item can be compared with its own fields: server 0007's `some approvers.timestamp where state is "APPROVED" and username is not pr_author is after last_commit_timestamp` reads both from each approver. #174 says this for `where` and leaves the argument open. To compare an item with the subject, use a `for` line. To reach the input, start with `$input`.

**[sentence.argument.subject]** After `count of` and `sum of`, the assertion is about one number for the subject, so a path in the argument starts at the subject: in `sum of stages.usd is total_usd`, `total_usd` is the subject's.

## Derived values

**[sentence.derived.count]** `count of <path>` walks the path as `every` does and counts the values it ends at, so `count of findings` is the number of findings. With `where`, it counts the items that pass.

**[sentence.derived.sum]** `sum of <list>.<field>` adds the field up across the items. With `where`, only the items that pass. A sum over no items is 0. Numbers are added as decimals, so `0.1 plus 0.2` is `0.3`.

**[sentence.derived.plus]** `<term> plus <term>` adds numbers. A term is a path, a number, a `count of` or a `sum of`. `plus` can't follow a `where`, because `count of x where n is m plus k is t` would read two ways: the tokenizer found three parses for it. Put the `where` on the last term instead.

**[sentence.derived.compare]** A derived value only goes with `is`, `is not`, `is ... within`, `is at least`, `is at most`, `is more than`, `is less than` and `is between`. `count of approvers is empty` is written wrong.

## The `for` line

**[sentence.for.line]** A check can have a `for` line before its `assert`. It holds one or two items separated by `, `, and each item is `every` or `some`, a path, an optional `where` with `and`, and `as` a name:

```yaml
peer_approved:
  description: Someone other than the author approved every pull request
  for: every pull_requests as pr, some pr.approvers where state is "APPROVED" as approver
  assert: approver.username is not pr.author
```

Items nest left to right, so a later one can use an earlier name, as `pr.approvers` does. A third item is written wrong, because two is the one level of nesting Rego gives today.

**[sentence.for.scope]** In `assert` and in a later item, a bare first key is the subject's field and a named item is reached by its name. Inside an item's own `where`, a bare key is that item's field. So in `for: some approvals where role is "qa" as approval` with `assert: approval.approved_at is before started_at`, `role` is the approval's and `started_at` the subject's.

**[sentence.for.name]** A name is a bare word that isn't `params`, `input` or a word of the grammar, like `every`, `as` or `empty`. For the rest of the check it shadows a field of the subject with the same name. A name given twice is written wrong.

**[sentence.for.fail]** Each item fails closed as a one-line `every` or `some` does: `some` over an empty list fails, `every` over one fails unless the item says `if any`, a missing or non-list path fails as `absent`, `null` or `unusable`, and an item a `where` can't decide fails the try with its cause.

**[sentence.for.comma]** The `, ` between items can't be confused with the `, ` between values, because the next item starts with `every` or `some` and a value can't. The tokenizer reads `for: some approvals where role is one of "qa", "dev" as approval, every commits as commit` one way.

**[sentence.for.one_assert]** A `for` line has one `assert`. sdlc-policies 0007's peer approval needs an approver who approved, isn't the author and approved after every commit, which is two assertions about the same items, and doesn't fit. A list under `assert`, all holding for the same items, is the smallest addition that would fit it.

## Phrases

Each phrase is a plain pattern: fixed words with gaps. One line is one form, and a negated form is a line of its own. An implementation matches them its own way. In Rego that's one regular expression per line, matched with `regex.find_all_string_submatch_n`, as ergo does today. No library or notation is needed.

The gaps:

| gap | holds |
| --- | --- |
| `<path>` | a path. On the left of a comparison, also a `count of`, a `sum of` or terms joined with `plus` |
| `<value>` | one value: text in quotes, a number, `true`, `false` or `null` |
| `<values>` | one or more values separated by `, ` |
| `<value or field>` | a value, or a path, or terms joined with `plus`. See [sentence.value.path](#values) for how to tell them apart |
| `<list>` | values separated by `, `, or a path to a list |
| `<number>` | a number |
| `<type>` | `list`, `string`, `number`, `boolean` or `object` |

"Missing", "`null`" and "wrong type" say what a check does when a value it reads is in that state. Everything a phrase reads fails that way, the path on the right and any reference included. Every failure that isn't `value` makes a filter fail the requirement instead of ruling the subject out.

**[sentence.phrase.is]**
```
<path> is <value>
<path> equals <field>
<path> is not <value or field>
```

The field equals, or doesn't equal, what's on the right, as [value.equal](semantics.md#values) says. `is`, `equals` and `is equal to` mean the same, and the report prints `is` before a value and `equals` before a field, so a field on the right side shows as one: `environment is "prod"`, `subject_digest equals fingerprint`. Missing: `absent`. `null`: passes `is null`, otherwise fails as `null`. Wrong type: with a value on the right, `is` fails as `value`, because `"5"` isn't `5` is a sound answer, as today's `equals`. With a field on the right, or with `is not`, two values of different types fail as `unusable`, as today's `compare`.

**[sentence.phrase.within]**
```
<path> is <value> within <number>
<path> equals <field> within <number>
```

Two numbers at most that far apart. The number is 0 or more. Missing: `absent`. `null`: `null`. Wrong type: `unusable`.

**[sentence.phrase.one_of]**
```
<path> is one of <values>
<path> is not one of <values>
```

The field equals one of the values, or none of them. Missing: `absent`. `null`: `null`, even when the values include `null`. Wrong type: `is one of` fails as `value`, and `is not one of` passes, since a number isn't one of three strings. An empty list can't be written.

**[sentence.phrase.in]**
```
<path> is in <path>
<path> is not in <path>
```

The same, with the list read from a path, usually `$params`. Missing: `absent`. `null`: `null`. A list that isn't a list: `unusable`. An empty list fails `is in` as `value`, and passes `is not in`.

**[sentence.phrase.exists]**
```
<path> exists
<path> does not exist
```

As today's `present` and `missing`: a field that's missing or `null` fails `exists` with `value` and passes `does not exist`. Wrong type: never, since any value exists. A parent that can't hold the field fails both as `unusable`.

**[sentence.phrase.empty]**
```
<path> is empty
<path> is not empty
```

`is empty` passes on `[]` and `""`. `is not empty` passes on a list with an item or a string with a character. Missing: `absent`. `null`: `null`. Wrong type, a number, a boolean or an object: `unusable`. This is wider than today on two counts, both open: `is not empty` passes a non-empty list where `non_empty_string` fails, and `is empty` passes `""` where `empty` fails.

**[sentence.phrase.type]**
```
<path> is a <type>
<path> is an <type>
```

The field has that JSON type. Missing: `absent`. `null`: `null`. Wrong type: `value`, because checking the type is the phrase's job.

**[sentence.phrase.contains]**
```
<path> contains <value or field>
<path> does not contain <value or field>
```

The field is a list that holds the value, or doesn't. Missing: `absent`. `null`: `null`. Not a list: `unusable`. `does not contain` passes on an empty list.

**[sentence.phrase.contains_all]**
```
<path> contains all of <list>
<path> contains none of <list>
```

The field is a list that holds every value, or none of them. Missing, `null` and not a list as `contains`. An empty list written in the sentence can't be written, and one read from a path fails as `unusable`, because it would pass every list.

**[sentence.phrase.matches]**
```
<path> matches <list>
<path> does not match <list>
```

The field is a string that matches at least one of the regular expressions, or none of them. They aren't anchored. Missing: `absent`. `null`: `null`. Not a string: `unusable`. A pattern that isn't a valid regular expression is written wrong when it's in the sentence and fails as `unusable` when it's read from a path.

**[sentence.phrase.starts]**
```
<path> starts with <value or field>
<path> ends with <value or field>
```

New, and unused in the corpus. Both sides are strings. Missing: `absent`. `null`: `null`. Not a string: `unusable`.

**[sentence.phrase.order]**
```
<path> is at least <value or field>
<path> is at most <value or field>
<path> is more than <value or field>
<path> is less than <value or field>
```

Both sides are numbers, or both are strings. Missing: `absent`. `null`: `null`. Anything else, two types that differ included: `unusable`.

**[sentence.phrase.between]**
```
<path> is between <value> and <value>
```

A number from the first to the second, both included. The bounds are numbers, and the first isn't above the second, or it's written wrong. Missing: `absent`. `null`: `null`. Not a number: `unusable`. Its `and` belongs to `between`, so `where qty is between 1 and 5 and kind is "a"` has two conditions. An implementation that splits `where` on ` and ` has to skip the one after `between <value>`.

**[sentence.phrase.time]**
```
<path> is before <value or field>
<path> is after <value or field>
<path> is on or after <value or field>
<path> is on or before <value or field>
```

Both sides are timestamps in the same format, both RFC 3339 strings or both numbers, as today's `compare_time`. A timestamp that isn't RFC 3339 fails the check rather than being compared as text. Missing: `absent`. `null`: `null`. Wrong type or format: `unusable`. `is on or after` replaces `is not before`, a double negative the corpus used six times.

**[sentence.phrase.aliases]**
```
<path> is equal to <value or field>
<path> does not equal <value or field>
```

The first is read as `is` or `equals`, the second as `is not`. The report prints `is`, `equals` and `is not`. With them in the grammar, every sentence in the corpus still has exactly one reading.

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
| `every pull_requests some approvers.state is "APPROVED"` | `two quantifiers in one sentence: put them on a for line` |

`environment is prod` parses, as a comparison with a field called `prod`, unless the subject has no such field. That's the one mistake the grammar can't catch, so the message for a missing field in an `is` argument should suggest quotes.

## Printing the sentence

**[sentence.print.canonical]** The report's `expression` is the sentence printed from its parse in one spelling: single spaces, `is` before a value and `equals` before a field, no alias, strings in double quotes with JSON escapes, numbers in their plain form, and values separated by `, `. Parsing the printed sentence gives the same parse.

**[sentence.print.same]** For a sentence written that way, the printed form is byte for byte what the author wrote. In the corpus, 301 of the 303 one-line sentences and assertions print back unchanged. The other two are the same check written with single quotes, `entry does not match '^[A-Za-z0-9._-]+\s*(>=|<=|~=|!=|<|>)'`, which prints as `"^[A-Za-z0-9._-]+\\s*(>=|<=|~=|!=|<|>)"`. Whether the canonical form keeps single quotes for a string with a backslash is open.

## How this was checked

A throwaway tokenizer in JavaScript, outside the repo, turned each phrase above into a regular expression and tried every way to cut each sentence into a quantifier, a path, `where` conditions and a phrase. It counted every reading.

The corpus has 390 lines: 303 one-line sentences and assertions, 13 `for` lines and 74 `from` lines. With the rules as #174 states them, all of them parse, and 215 parse more than one way:

| cause | sentences | rule that removes it |
| --- | ---: | --- |
| a quoted string could be text or a quoted key, `is "prod"` | 95 | [sentence.path.argument](#paths) |
| a phrase word could be a field, `is empty` against `is <field empty>` | 60 | [sentence.words](#words-a-field-cant-be-called) |
| `true`, `false` or `null` could be a field | 55 | both of the above |
| a dynamic key's ref could end at more than one key | 31 | [sentence.path.dynamic](#paths) |

Some lines have two causes. With the rules in this file, every line parses exactly one way. Twelve made-up lines test what the corpus doesn't reach: `plus` after `where` read three ways until [sentence.derived.plus](#derived-values) forbade it, a `for` item named `every` read one way until [sentence.for.name](#the-for-line) forbade it, and `if any` with `some`, two quantifiers in one sentence and `count of ... is empty` parse no way, as they should.
