Steps 1 and 3 of the plan are on the [`spec/sentences`](https://github.com/kosli-dev/ergo/tree/spec/sentences/spec) branch. Step 2, the readability test, needs a person who hasn't seen ergo, so it isn't done. There's no PR.

- [`sentences-corpus.md`](https://github.com/kosli-dev/ergo/blob/spec/sentences/spec/sentences-corpus.md) rewrites every check, filter and `from` as sentences, with today's form beside each. That covers sdlc-policies, the server's demo and npm-bump policies, pr-reviewer, ergo's examples and all 36 DEV controls, which are in [kosli-playground/dev-process-controls](https://github.com/kosli-playground/dev-process-controls). In all, 229 checks and 74 filters.
- [`sentences.md`](https://github.com/kosli-dev/ergo/blob/spec/sentences/spec/sentences.md) is the grammar. Each phrase is a Cucumber Expression, with what it does on missing, `null` and wrong-typed input.

It follows the issue as of 10:28 today, `for` lines and names without `$` included. 13 checks moved to a `for` line, and with that DEV-0501 fits.

## Phrase tally

Counted from the parses, twins included: `is` 164, `is not empty` 54, `at $params.x` 44, `is before` 21, `some` 19, `is one of` 18, `every` 15, `where` 14 (7 with `and`), `for` 13, `count of` 12, `is at least` 9, `is not` 9, `at each of` 6, `is empty` 6, `is in` 6, `is not before` 6, `is after` 5, `matches` 5, `exists` 4, `is between` 4, `, if any,` 3, `contains` 3, `does not match` 3, `contains all of` 2, `sum of` 2, `plus` 2, `within` 2, `does not contain` 1, `is a` 1, `is not in` 1.

Nothing uses `is not one of`, `does not exist`, `contains none of`, `starts with`, `ends with`, `is at most`, `is more than`, `is less than`, `is not after`, `ignoring case` or the index words.

## Misfits

These don't fit:

- **sdlc-policies 0007 `peer_approval`.** It needs an approver who approved, isn't the author, and approved after every commit. A `for` line handles the two quantifiers, but that's two assertions about the same approver and `for` has one `assert`. The smallest addition is a list under `assert`, all holding for the same items. That's what today's `any_of` option means.
- **pr-reviewer `keys_match`.** The key to look up comes from the item: `for: every …personas_dispatched as persona` with `assert: …persona_blob_shas at persona matches "^[0-9a-f]{40}$"`. That needs `at <name>`, which ergo can't do today, so it stays custom. The other six custom operators all become sentences.
- **DEV-0302 `components_listed`** becomes two checks, so it has two rows.
- **server demo 0008** builds one requirement per suite in Rego. sdlc-policies' version already says the same thing with `at each of`.

These fit, but change what passes:

- `is not empty` passes a non-empty list where `non_empty_string` fails (52 checks).
- `is empty` passes `""` where `empty` fails (6 checks), and that one passes quietly.
- No input in these repos hits either. Making each phrase strict about type fixes both, but then `is empty` and `is not empty` aren't opposites on strings.
- Two checks compare timestamps as text today. With `is after`, a timestamp that isn't RFC 3339 fails.
- Three pr-reviewer custom operators skipped items with a missing field. The sentences fail them as `absent`, as #173 already does.
- 37 paths lose a Rego default, like `artifact_name` defaulting to `"artifact"`.

## Ambiguities the tokenizer found

With the rules as the issue states them, all 390 lines parse, but 215 parse more than one way. Four rules bring that to 0:

| what reads two ways | lines | rule |
| --- | ---: | --- |
| `is "prod"`: text, or a quoted key | 95 | a quoted string in an argument is a value, and a quoted key there is written `."$schema"`, as jq does |
| `is not empty`: a phrase, or `is not` a field called `empty` | 60 | phrase words can't start a path in an argument, so that field is written `."empty"` |
| `is true`: a value, or a field called `true` | 55 | the same two rules |
| `artifacts_statuses at $params.artifact_name.attestations_statuses`: where does the ref end? | 31 | the ref after `at` is `$params` or `$input` plus one key, which every ref in the corpus already is |

Made-up probes found two more: `count of x where n is m plus k is t` reads three ways, so `plus` can't follow `where`, and `between 1 and 5` inside `where` means an implementation can't just split `where` on ` and `.

The issue's `{path} contains/does not contain {json}` doesn't work as a Cucumber Expression either. `/` only alternates single words, so it compiles to `(contains|does) not contain` and never matches `contains`. Also, `( not)` matches both forms without saying which one it matched. The draft has one expression for each form.

## Open decisions

- **`is` or `must`.** 74 filters and 21 `where` conditions need `is` whatever checks use. Of the checks, 9 read better with `must`, and all of them say something bad is absent: `findings is 0`, `allow_force_pushes is false`, `open_bump_prs is empty`. The rest read the same either way.
- **The dynamic key.** It appears 44 times, all in sdlc-policies and the server demos, and mostly in `from` to pick one artifact out of a trail. 32 of them have more path after the key. `at` is still a placeholder.
- **`where` in `from` or `applies_to`.** All 74 filters sit on the subject, and no policy filters inside `from`. That's #113's call.
- **A subject with a parent.** The `for` line covers everything that reached for it: DEV-0501, the item-against-subject comparisons in DEV-0401, 0407, 0502, 0503, 0601 and server 0010, and pr-reviewer's `keys_match`. None of them needs #52 now.
- **Time phrases.** 21 `is before`, 5 `is after`, 6 `is not before`. The last one is a double negative for "on or after", and `is on or after` would read better. Four of them compare a deadline that Rego computed (#140).
- **One-line `every`/`some`, or always `for`.** 20 checks use the one-line form and 13 need `for`. 18 of the 20 read nothing after the path except a value or `$params`, so the second scoping rule only matters in 2 of them. But the 3 `count of`/`sum of ... where` checks read the item in their `where` either way, because a `for` line can't produce a number.

## Rego spike

This one is outside the repo. It's not ergo, just one evaluator fed checks as objects or as sentences parsed with the full phrase table: 3,000 deployments, 8 checks, all three giving the same counts.

| | `opa eval` | Wasm JS runtime | Wasm heap |
| --- | ---: | ---: | ---: |
| checks as objects | 382 ms | 41 ms | 51.0 MB |
| sentences parsed once per check | 388 ms | 44 ms | 51.9 MB |
| sentences parsed per subject | 424 ms | 1,907 ms | 739 MB |

Parsing once per check costs about what today's objects do. Parsing per subject is out of the question in Wasm. The spike also hit the `is not empty` ambiguity: two phrases matched, and OPA refused to pick one until the table took the first match in order.

