# Working on ergo

ergo is a Rego library that turns policy evaluation into a structured report. Users copy `ergo.rego` into their own projects, so it has to stay a single file with no dependencies.

## Files

- `ergo.rego` is the whole library.
- `ergo_test.rego` holds its tests.
- `custom_op_test.rego` defines custom operators that only the tests use.
- `README.md` walks a new user through a first policy.
- `REFERENCE.md` describes every field, operator, cause and report entry.
- `examples/` holds worked examples. Each one has an input, the same policy in plain Rego and with ergo, and tests that pin what both versions report.

## Checks

Run these before saying a change is done:

```sh
opa check --strict . --ignore .github
opa fmt --list .
opa test . --ignore .github
opa eval --strict-builtin-errors --ignore .github -d . --format raw 'count(data) > 0'
regal lint --disable-all --enable-category bugs --disable redundant-existence-check --ignore-files '.github/**' .
```

`opa fmt --list .` should print nothing. If it prints file names, run `opa fmt -w .`.

The `opa eval` command runs every test again with `--strict-builtin-errors`, which turns a built-in given the wrong type into an error, and should print `true`. If it prints an error, check the value's type before the built-in on that line, so that ergo gives the same report with or without the flag.

The `regal lint` command runs [Regal](https://www.openpolicyagent.org/projects/regal)'s rules for likely bugs, and should say `No violations found`. One of them, `leaked-internal-reference`, fails when a file outside `package ergo` calls a rule whose name starts with `_`. Test files are allowed to. `redundant-existence-check` is off because it flags `_verdict_cause(passed) := "satisfied" if passed`, where `if passed` is what stops a `false` from counting as satisfied. The flags are on the command line and not in `.regal/config.yaml` because OPA would load that file as data.

OPA loads every JSON and YAML file it finds as data. The workflow files under `.github` clash with each other, so the checks ignore that folder.

CI runs these checks on pull requests and on pushes to `main` (`.github/workflows/test.yml`), using the OPA version the README names and Regal 0.43.0. When you change the OPA version, change it in both places.

CI also compiles the baking example to Wasm with `opa build -t wasm`, runs it with the JavaScript runtime `@open-policy-agent/opa-wasm`, and fails when its report or violations differ from `opa eval`'s. The runtime doesn't have every built-in, so the step also fails when ergo uses one it lacks, even in code the example never reaches. The only exception is `time.parse_rfc3339_ns`, which `REFERENCE.md` tells Wasm users to pass in themselves.

CI also fails when a line of Rego isn't reached by any test. To list those lines yourself:

```sh
opa test . --ignore .github --coverage | jq -r '.files | to_entries[] | .key as $f | .value.not_covered[]? | "\($f):\(.start.row)"' | sort -u
```

## Tests

Every change needs tests: new behaviour, bug fixes and changes to existing behaviour alike. A bug fix starts with a test that fails because of the bug. A change without tests isn't finished.

## No comments

There are no comments in the code or the tests, and it should stay that way.

The one exception is the license header at the top of `ergo.rego`. Users copy that file on its own, so the header keeps the license with it.

CI fails on any other comment in a `.rego` file. It asks `opa parse` for each file's comments, so a `#` inside a string doesn't count. To list them yourself:

```sh
git ls-files '*.rego' | while read -r f; do opa parse "$f" --format json --json-include comments,locations | jq -r --arg f "$f" '.comments[]? | .Location.row as $r | select(($f == "ergo.rego" and $r <= 2) | not) | "\($f):\($r)"'; done
```

When something in the code looks like it could be simplified but mustn't be, a test says so instead of a comment. Give the test a name that explains the reason, like `test_out_of_scope_subject_is_recorded_as_evidence`. If you're about to write a comment, write a test.

Before removing or simplifying code, run the tests. Many of them exist to stop "obvious" simplifications that would let a check pass when it should fail.

## Failing closed

When ergo can't read something or isn't sure, the check fails. It never passes by accident and never disappears from the report. Every change must keep this true, and every new operator needs tests for missing, `null` and wrong-typed input.

The report must stay byte-identical for the same policy and input, whatever order the policy was written in. Sort anything that ends up in the report.

## Docs

When behaviour changes, update `REFERENCE.md` in the same change. When it affects the getting-started example, update `README.md` too.

Every output shown in the docs must come from actually running it, not from memory.

## Writing

This applies to everything you write: docs, test names, commit messages, pull requests, issues, and your replies to the people you're working with.

Write in plain English that anyone can follow:

- Say things simply. No jargon, no buzzwords, no filler, and no pet words like "load-bearing".
- Explain what the reader needs at that point, and no more. Leave the theory out.
- Don't sound robotic either. Vary sentence length, and join related ideas with "and", "but", "so" and "because" rather than stacking short sentences.
- Show real examples.

When talking to people:

- No flattery and no ceremony. Don't praise the question, don't thank people for feedback, and don't announce what you're about to do at length. Just answer or do it.
- Be direct. If something is wrong, say so and say why. If you disagree, say that too.
- Be honest about what you did. Say what you ran and what it showed. If you didn't check something, or a check failed, say so plainly.
- Keep it short. Lead with the answer, then give what's needed to act on it.

## Commits

The first line names the part of the repo that changed, then says what the change does, in the imperative and in lowercase:

- `core:` the library and its tests
- `docs:` `README.md`, `REFERENCE.md` and `AGENTS.md`
- `site:` the website in `site/`
- `ci:` workflows and Dependabot
- `examples:` the worked examples in `examples/`

For example, `core: fail compare when either side is missing`.

One area per commit. A `core:` change that updates `REFERENCE.md` with it stays `core:`.

When a `core:` change alters the report for an existing policy, say so in the body, on a line starting with `Changes the report:`.

Add a body when the reason isn't obvious from the first line. PR titles follow the same rules, because they become the commit on `main`. Issue titles do too, so an issue reads like the change that will fix it.

CI checks every PR title against the areas listed above, so a new area only needs adding to that list.
