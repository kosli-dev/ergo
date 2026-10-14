# Working on ergo

ergo is a Rego library that turns policy evaluation into a structured report. Users copy `ergo.rego` into their own projects, so it has to stay a single file with no dependencies.

## Files

- `ergo.rego` is the whole library.
- `ergo_test.rego` holds its tests.
- `custom_op_test.rego` defines custom operators that only the tests use.
- `spec/` is the spec ergo implements: what each check means as named rules, the syntax, JSON Schemas for a policy and a report, and cases that pin the rules down. `spec/README.md` explains it.
- `spec_test.rego` runs every case in `spec/cases` against `ergo.rego`.
- `README.md` walks a new user through a first policy.
- `REFERENCE.md` describes every field, operator, cause and report entry.
- `CONTRIBUTING.md` tells people how to report bugs and send changes, and points them here for the rules.
- `CODE_OF_CONDUCT.md` is the Contributor Covenant 2.1, unchanged apart from the contact address.
- `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md` are the forms GitHub shows for new issues and pull requests.
- `examples/` holds worked examples. Each one has an input, the same policy in plain Rego and with ergo, and tests that pin what both versions report.

## Checks

Run these before saying a change is done:

```sh
opa check --strict . --ignore .github
opa fmt --list .
opa test . --ignore .github --timeout 120s
opa eval --strict-builtin-errors --ignore .github -d . --format raw 'count(data) > 0'
regal lint --disable-all --enable-category bugs --disable redundant-existence-check --ignore-files '.github/**' .
python3 spec/check_rules.py
python3 spec/sentences_corpus.py --check
python3 -m venv /tmp/ergo-venv && /tmp/ergo-venv/bin/pip install --quiet jsonschema==4.26.0 && /tmp/ergo-venv/bin/python .github/spec-schemas.py
```

Run them from the repo root. The last line puts `jsonschema` in a virtual environment outside the repo, because some Pythons, like Homebrew's, refuse `pip install` outside one.

`opa fmt --list .` should print nothing. If it prints file names, run `opa fmt -w .`.

The `opa eval` command runs every test again with `--strict-builtin-errors`, which turns a built-in given the wrong type into an error, and should print `true`. If it prints an error, check the value's type before the built-in on that line, so that ergo gives the same report with or without the flag.

The `regal lint` command runs [Regal](https://www.openpolicyagent.org/projects/regal)'s rules for likely bugs, and should say `No violations found`. One of them, `leaked-internal-reference`, fails when a file outside `package ergo` calls a rule whose name starts with `_`. Test files are allowed to. `redundant-existence-check` is off because it flags `_verdict_cause(passed) := "satisfied" if passed`, where `if passed` is what stops a `false` from counting as satisfied. The flags are on the command line and not in `.regal/config.yaml` because OPA would load that file as data.

OPA loads every JSON and YAML file it finds as data. The workflow files under `.github` clash with each other, so the checks ignore that folder.

CI runs these checks on pull requests and on pushes to `main` (`.github/workflows/test.yml`), using the OPA version the README names and Regal 0.43.0. That's OPA 1.20.2, the version the Kosli CLI embeds. When you change the OPA version, change it in the README, in `CONTRIBUTING.md`, in every job of the workflow, in the Docker command below and in `opaVersion` in `site/hugo.toml`.

CI also runs every test compiled to Wasm, with `.github/wasm-tests.sh`, because Wasm walks objects and sets in a different order from `opa eval`, so anything that ends up in the report has to be sorted. The script runs `opa test --target wasm` on 150 tests at a time, because OPA keeps the memory of every test until the run ends, and all of them at once take more than the 16 GB a GitHub runner has. It fails when two tests share a name, since it picks tests by name. That needs the Linux build of OPA. The macOS one says `engine not found`, so on a Mac give the script the Docker command to run OPA with:

```sh
.github/wasm-tests.sh docker run --rm -v "$PWD":/src:ro -w /src openpolicyagent/opa:1.20.2
```

CI also runs every test with OPA's JavaScript runtime, `@open-policy-agent/opa-wasm` (`.github/wasm-js.cjs`), because that runtime brings its own versions of some built-ins, like a `sprintf` that formats lists and objects differently, and lacks others. The script compiles each test as a Wasm entrypoint, fails if ergo uses a built-in the runtime doesn't have (apart from `time.parse_rfc3339_ns`, which it passes in, as `REFERENCE.md` tells Wasm users to), and then runs every test. It also fails if `ergo.report` or `ergo.violations` needs any built-in that OPA's Wasm build runs outside the module. OPA reads the arguments of those built-ins back as Rego, so a string holding a byte-order mark fails the whole evaluation. `time.parse_rfc3339_ns` is allowed because ergo only passes it strings that already match the RFC 3339 pattern. If you add a function for users to call, add it to the entrypoint the script writes, so the check covers it. `sprintf` is one of them, so build text with `concat` instead. `concat` takes only strings, so write anything else with `_text` first. Last, it builds one report on 100 deployments and fails if that uses more than 20 MB of Wasm memory. Wasm doesn't cache function calls and frees nothing until the report is done, so something worked out again for every row shows up there long before it slows down `opa eval`.

A `spec` job checks the spec. `python3 spec/check_rules.py` fails when a case cites a rule that doesn't exist, or when a rule has no case and isn't listed under "Rules without cases" in `spec/OPEN.md`. `.github/spec-schemas.py` builds the report for every case and fails when a report doesn't match `spec/report/schema.json`, or when ergo reads a policy as written correctly but it doesn't match `spec/policy/schema.json`. `python3 spec/sentences_corpus.py --check` fails when `spec/sentences-corpus.json` no longer holds every line of `spec/sentences-corpus.md`.

CI also fails when a line of Rego isn't reached by any test. To list those lines yourself:

```sh
opa test . --ignore .github --timeout 120s --coverage | jq -r '.files | to_entries[] | .key as $f | .value.not_covered[]? | "\($f):\(.start.row)"' | sort -u
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

When behaviour changes, update its rule in `spec/` and add or change cases for it, so `spec_test.rego` fails when one no longer matches. When a policy or a report changes shape, update `spec/policy/schema.json` or `spec/report/schema.json` too. Update `REFERENCE.md` in the same change. When it affects the getting-started example, update `README.md` too.

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
- `docs:` `README.md`, `REFERENCE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` and the issue and pull request templates
- `site:` the website in `site/`
- `ci:` workflows and Dependabot
- `examples:` the worked examples in `examples/`
- `spec:` the spec in `spec/`, its cases and `spec_test.rego`

For example, `core: fail compare when either side is missing`.

One area per commit. A `core:` change that updates `REFERENCE.md` or `spec/` with it stays `core:`.

When a `core:` change alters the report for an existing policy, say so in the body, on a line starting with `Changes the report:`.

Add a body when the reason isn't obvious from the first line. PR titles follow the same rules, because they become the commit on `main`. Issue titles do too, so an issue reads like the change that will fix it.

CI checks every PR title against the areas listed above, so a new area only needs adding to that list.
