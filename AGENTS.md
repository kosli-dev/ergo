# Working on Ergo

Ergo is a Rego library that turns policy evaluation into a structured report. Users copy `ergo.rego` into their own projects, so it has to stay a single file with no dependencies.

## Files

- `engines/rego/ergo.rego` is the whole library, and the Rego engine.
- `engines/rego/ergo_test.rego` holds its tests.
- `spec/` is the spec Ergo implements: what each check means as named rules, the syntax, JSON Schemas for a policy and a report, and cases that pin the rules down. `spec/README.md` explains it.
- `engines/rego/spec_test.rego` runs every case in `spec/cases` against `ergo.rego`.
- `README.md` says what Ergo is and walks a new user through a first policy and its report, the same for both engines.
- `OPA.md` is the page for `ergo.rego`: install, how to run it with OPA, Wasm, numbers, `ergo.compile`. `CLI.md` is the page for the `ergo` command: install, how to run it, exit codes, how it reads YAML.
- `REFERENCE.md` describes every field, operator, cause and report entry of the language, the same for both engines.
- `CONTRIBUTING.md` tells people how to report bugs and send changes, and points them here for the rules.
- `CHANGELOG.md` says what each release of `ergo.rego` changed. The spec has its own in `spec/CHANGELOG.md`, and the Rust engine in `engines/rust/CHANGELOG.md`. A change in what a check means goes in `spec/CHANGELOG.md`, and an engine's own fixes go in that engine's file.
- `CODE_OF_CONDUCT.md` is the Contributor Covenant 2.1, unchanged apart from the contact address.
- `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md` are the forms GitHub shows for new issues and pull requests.
- `examples/` holds worked examples. Each one has an input, the same policy in plain Rego and with Ergo, and tests that pin what both versions report.
- `engines/rust/` is a second engine, in Rust. It's experimental and in progress. It's a Cargo workspace with five crates: `ergo-policy-sentences` reads sentences and nothing else, `ergo-policy-engine` builds the report, `ergo-policy-cli` is the `ergo` command that prints a report or the violations from JSON or YAML files, and `ergo-policy-wasm` and `ergo-policy-sentences-wasm` wrap them for a browser. Its tests run every case in `spec/cases`, and `engines/rust/known-failures.txt` lists the ones it still fails.
- `packages/` holds Node tools that build on Ergo, in one pnpm workspace. Someone who only copies `ergo.rego` never needs them.
- `packages/markdown/` compiles a policy written in Markdown into a policy object. It's an experiment, not published.
- `packages/playground/` builds the playground, the web page the site links to as "Try Ergo". It opens on a policy in YAML beside its report, from the Rego engine (`ergo.rego`) or the Rust engine, run in the page. Other tabs show the policy, and let you write it in Markdown, with what the compiler read and the document as a reader sees it. It also reads each sentence with the Rust sentence parser, `ergo-policy-sentences-wasm`, to underline what's written wrong, colour the words, say how a sentence reads and suggest what to type next.

## Checks

Run these before saying a change is done:

```sh
opa check --strict engines/rego spec:spec examples:examples
opa check --strict --schema .github/closed-input-schema.json engines/rego/ergo.rego
opa capabilities --current | jq '.builtins |= map(select(.nondeterministic != true))' > /tmp/ergo-deterministic.json && opa check --strict --capabilities /tmp/ergo-deterministic.json engines/rego/ergo.rego
opa fmt --list engines/rego examples engines/rust/sentences/tests/oracle
opa test engines/rego spec:spec examples:examples --timeout 120s
opa eval --strict-builtin-errors -d engines/rego -d spec:spec -d examples:examples --format raw 'count(data) > 0'
regal lint --disable-all --enable-category bugs --disable redundant-existence-check engines/rego examples engines/rust/sentences/tests/oracle
.github/rego-folders.sh
.github/rego-folders_test.sh
python3 spec/check_rules.py
python3 spec/sentences_corpus.py --check
python3 -m venv /tmp/ergo-venv && /tmp/ergo-venv/bin/pip install --quiet jsonschema==4.26.0 abnf==2.9.0 && /tmp/ergo-venv/bin/python .github/spec-schemas.py
/tmp/ergo-venv/bin/python spec/check_grammar.py
/tmp/ergo-venv/bin/python spec/check_grammar.py --rust 'docker run --rm -i -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust cargo run --locked -q --release -p ergo-policy-sentences --example read'
```

Run them from the repo root. The last three lines use a virtual environment that holds `jsonschema` and `abnf`, and the last one the Docker image that [`engines/rust/README.md`](engines/rust/README.md) builds; it's outside the repo, because some Pythons, like Homebrew's, refuse `pip install` outside one.

`opa fmt --list` should print nothing. If it prints file names, run `opa fmt -w` on them.

The second `opa check` compiles `ergo.rego` the way a host does when it checks `input` against a closed JSON Schema, and should print nothing. If it fails with `undefined ref: input[...]`, Ergo reads something from `input` that the `METADATA` annotation above `package ergo` doesn't declare.

The third `opa check` compiles `ergo.rego` without the built-ins OPA marks as nondeterministic, like `opa.runtime`, `time.now_ns` and `http.send`, and should print nothing. Their answer depends on the machine, not on the policy and the input, and a report must depend only on the policy, the input and the params. A host that runs other people's policies in a sandbox can leave those built-ins out, and then Ergo wouldn't compile there. If it fails with `undefined function`, find a way that doesn't read the machine.

The `opa eval` command runs every test again with `--strict-builtin-errors`, which turns a built-in given the wrong type into an error, and should print `true`. If it prints an error, check the value's type before the built-in on that line, so that Ergo gives the same report with or without the flag.

The `regal lint` command runs [Regal](https://www.openpolicyagent.org/projects/regal)'s rules for likely bugs, and should say `No violations found`. One of them, `leaked-internal-reference`, fails when a file outside `package ergo` calls a rule whose name starts with `_`. Test files are allowed to. `redundant-existence-check` is off because it flags `_verdict_cause(passed) := "satisfied" if passed`, where `if passed` is what stops a `false` from counting as satisfied. The flags are on the command line and not in `.regal/config.yaml`.

Every OPA command here names the folders it loads, and none of them scans the repo, so the workflow files under `.github`, the workspace under `packages` and the Rust engine's test data under `engines/rust` are never loaded as data. OPA puts a JSON or YAML file at a data path that starts from the folder it was given, so `spec:spec` and `examples:examples` keep the cases at `data.spec` and the examples' inputs at `data.examples`, where the tests read them. `engines/rego` holds no data, so it needs no prefix. A new folder with Rego has to be added to these commands, to `.github/workflows/test.yml` and to `.github/rego-folders.sh`, which fails in CI when a tracked Rego file is in a folder no command loads.

When you change anything under `packages/`, run these too, one at a time:

```sh
cd packages
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm -r bundle
```

`pnpm test` fails when a line under `packages/markdown/src` isn't reached by a test. Its tests also run `ergo.report` with opa on every case in `packages/markdown/cases` that has an input. The editor's tests build the page, which compiles `ergo.rego` to Wasm with the `opa` on your PATH, and check that each sample gives the report its case expects. They also need the Rust engine built to Wasm in `engines/rust/wasm/pkg` and the sentence parser in `engines/rust/sentences-wasm/pkg`: see "Building for a browser" in `engines/rust/README.md`.

When you change `engines/rust/`, run its checks too. There's no need for Rust on your machine: `engines/rust/README.md` has the Docker command, which runs `cargo fmt --check`, Clippy with warnings as errors, the tests, and a Wasm build of `ergo-policy-sentences`. Use `-j 4` and run one at a time, because a full build takes every core otherwise. The Rust version is pinned in `engines/rust/rust-toolchain.toml` and the `Dockerfile` next to it; change both together. CI runs the same checks in the `tests-rust` job.

A change that only adds or changes spec cases can break those checks too, so run the whole `cargo test` for it. Rust runs every case, and the sentence oracle in `engines/rust/sentences/tests/oracle` needs a row for every sentence in the cases. `python3 engines/rust/sentences/tests/oracle/validate.py` checks the rows against `ergo.rego` with the `opa` on your PATH, or the OPA command you give it, and prints the ones that are missing. It fails only when a row differs, so read its output for missing ones. A case Rust fails goes in `known-failures.txt`.

CI runs these checks on pull requests and on pushes to `main` (`.github/workflows/test.yml`), using the OPA version the README names and Regal 0.43.0. That's OPA 1.20.2, the version the Kosli CLI embeds. When you change the OPA version, change it in the README, in `CONTRIBUTING.md`, in every job of the workflow, in the Docker command below and in `opaVersion` in `site/hugo.toml`.

CI also runs every test compiled to Wasm, with `.github/wasm-tests.sh`, because Wasm walks objects and sets in a different order from `opa eval`, so anything that ends up in the report has to be sorted. The script runs `opa test --target wasm` on 100 tests at a time, because OPA keeps the memory of every test until the run ends, and all of them at once take more than the 16 GB a GitHub runner has. Some batches of 150 already came close to it. It takes the list of tests from a plain `opa test` run, checks that every one of them ran, and fails when two tests share a name, since it picks tests by name. That needs the Linux build of OPA. The macOS one says `engine not found`, so on a Mac give the script the Docker command to run OPA with:

```sh
.github/wasm-tests.sh docker run --rm -v "$PWD":/src:ro -w /src openpolicyagent/opa:1.20.2
```

CI also runs every test with OPA's JavaScript runtime, `@open-policy-agent/opa-wasm` (`.github/wasm-js.cjs`), because that runtime brings its own versions of some built-ins, like a `sprintf` that formats lists and objects differently, and lacks others. The script compiles each test as a Wasm entrypoint, fails if Ergo uses a built-in the runtime doesn't have (apart from `time.parse_rfc3339_ns`, which it passes in, as `REFERENCE.md` tells Wasm users to), and then runs every test. It also fails if `ergo.report` or `ergo.violations` needs any built-in that OPA's Wasm build runs outside the module. OPA reads the arguments of those built-ins back as Rego, so a string holding a byte-order mark fails the whole evaluation. `time.parse_rfc3339_ns` is allowed because Ergo only passes it strings that already match the RFC 3339 pattern. If you add a function for users to call, add it to the entrypoint the script writes, so the check covers it. `sprintf` is one of them, so build text with `concat` instead. `concat` takes only strings, so write anything else with `_text` first. Last, it builds three reports on 100 deployments, one with a check on every test, one with three checks on each deployment and one with the tests of each deployment as subjects, and fails if they use more than 24 MB, 17 MB and 40 MB of Wasm memory. Wasm doesn't cache function calls and frees nothing until the report is done, so something worked out again for every row shows up there long before it slows down `opa eval`. The reports on `main` sit close to those limits, so before adding something that costs memory on every report, measure them on `main` and on your branch. The script prints all three at the end, after running every test. Run it from the repo root, with `opa` on your PATH:

```sh
npm install --silent --no-save --prefix /tmp/ergo-wasm-js @open-policy-agent/opa-wasm@1.10.0 && node .github/wasm-js.cjs /tmp/ergo-wasm-js
```

A `spec` job checks the spec. `python3 spec/check_rules.py` fails when a case cites a rule that doesn't exist, or when a rule has no case and isn't listed under "Rules without cases" in `spec/OPEN.md`. `.github/spec-schemas.py` builds the report for every case and fails when a report doesn't match `spec/report/schema.json`, when Ergo reads a policy as written correctly but it doesn't match `spec/policy/schema.json`, or when a `$well_formed` row fails without naming what's wrong. `python3 spec/sentences_corpus.py --check` fails when `spec/sentences-corpus.json` no longer holds every line of `spec/sentences-corpus.md`. `spec/check_grammar.py` reads sentences with `ergo.rego` and with a parser built from `spec/sentences.abnf`, and fails when one reads a sentence and the other rejects it as a matter of syntax. With `--rust <command>` it also runs `engines/rust`'s sentence reader (`ergo-policy-sentences`, the `read` example) and fails when Rust and the ABNF disagree, with no list of known ones; CI does this, and the second command above does it locally through Docker. It also fails when Rust and `ergo.rego` give different problems for a sentence, so a change to one of `ergo.rego`'s messages has to change Rust's in the same pull request. It leaves out only a Rust problem that ends in `is compared with itself`. The sentences are the corpus, the cases, and a few thousand generated from the grammar and changed a little, with a fixed seed. A sentence `ergo.rego` rejects for another reason, like an unknown name, isn't a disagreement. The known ones are listed in `spec/OPEN.md`, and the script fails on a new one and when a listed one no longer disagrees. If `ergo.rego` gives a message that isn't about syntax, add it to `NON_SYNTAX` in the script.

`main` always carries a `-dev` version, like `0.1.0-dev`, and a test fails without one. After a release `main` moves to the next patch version. `.github/changelog-version.sh` (tested by `changelog-version_test.sh`) runs in the `checks` job, for `ergo.rego` and for the Rust engine: when the top heading of the changelog is already released, the version must be its next patch, and when it isn't, the version must equal the heading and be a new minor (a new major from 1.0) if the heading has a `### Changed` or `### Removed` part. So the first change after a release adds the heading and moves the version to match. The spec has its own version, `_spec` in `ergo.rego`. `.github/spec-version.sh` fails when `_spec` and the `$id` of both schemas disagree, when a file that defines the spec (`spec/syntax.md`, `spec/semantics.md`, both schemas, `spec/sentences.abnf` and `spec/cases/`) differs from the latest `spec-v*` tag and `_spec` still equals that tag, and when `_spec` is not the tag's version or one minor above it (with `-dev`, or without it for a release being prepared), or is above it without a heading in `spec/CHANGELOG.md`. So the first change to the spec moves `_spec`, both `$id`s and every `ergo_spec` to `vX.(Y+1)-dev`, except in `README.md`, which goes with the latest release and is moved by hand in the pull request that releases the spec. The same goes for the `engine` versions in the reports `OPA.md` (for `ergo.rego`) and `CLI.md` (for the CLI) show, for the spec in the `"ergo"` of `OPA.md`'s report and of `README.md`'s, and for the CLI download in `CLI.md`: they are what the latest releases give, the pull request that prepares each release moves them by hand, `release.sh` refuses the tag until it has, and the release workflow's bump pull request and `.github/changelog-version.sh` leave `README.md` and `CLI.md` alone. `REFERENCE.md` and `OPA.md` follow `main`, so the bump pull request moves the `ergo.rego` version in both (the `-dev` one, like `expected ergo-rego 0.4.0-dev` in `OPA.md`), and the sweep to `vX.(Y+1)-dev` moves their `ergo_spec` too. The site needs no change: it follows the latest published release on its own. `release.sh` and the release workflow refuse a `rego-v*` or `spec-v*` tag on a commit whose `_spec` says `-dev`. A release is a tag, which `.github/release.sh` checks and pushes, and `.github/workflows/release.yml` does the rest, with the steps in `CONTRIBUTING.md`. A `rust-v*` tag does the same for the three Rust crates that go to crates.io, and their version has no `-dev` on the tagged commit, unlike `ergo.rego`'s. The site build runs `site/prepare.sh` before Hugo, which takes the schemas of every published `spec-v*` release, so nothing is committed.

CI also fails when a line of Rego isn't reached by any test. To list those lines yourself:

```sh
opa test engines/rego spec:spec examples:examples --timeout 120s --coverage | jq -r '.files | to_entries[] | .key as $f | .value.not_covered[]? | "\($f):\(.start.row)"' | sort -u
```

## Tests

Every change needs tests: new behaviour, bug fixes and changes to existing behaviour alike. A bug fix starts with a test that fails because of the bug. A change without tests isn't finished.

## No comments

There are no comments in the code or the tests, and it should stay that way.

There are two exceptions, both above `package ergo` in `ergo.rego`. The first is the license header. Users copy that file on its own, so the header keeps the license with it. The second is the `METADATA` annotation that declares `input["ergo/names"]` as an object. While Ergo checks, `input` holds Ergo's names, and a host that type-checks `input` against a closed JSON Schema, like Kosli does when a policy is published, would otherwise refuse every read of them. OPA only reads a schema from an annotation, and annotations are comments.

There's one more exception, for code meant for others to call: API doc comments on public items, `///` (and `//!` for a crate) in the Rust crates under `engines/rust`, and JSDoc `/** */` on exported functions and types in `packages/`. They say what the item is, what it takes and what it returns, with an example where it helps, and never why the code is written the way it is. Every other comment stays out, and the Rego files get none.

CI fails on any other comment in a `.rego` file. It asks `opa parse` for each file's comments, so a `#` inside a string doesn't count. To list them yourself:

```sh
git ls-files '*.rego' | while read -r f; do opa parse "$f" --format json --json-include comments,locations | jq -r --arg f "$f" '.package.location.row as $p | .comments[]? | .Location.row as $r | select(($f == "engines/rego/ergo.rego" and $r < $p) | not) | "\($f):\($r)"'; done
```

When something in the code looks like it could be simplified but mustn't be, a test says so instead of a comment. Give the test a name that explains the reason, like `test_out_of_scope_subject_is_recorded_as_evidence`. If you're about to write a comment, write a test.

Before removing or simplifying code, run the tests. Many of them exist to stop "obvious" simplifications that would let a check pass when it should fail.

## Failing closed

When Ergo can't read something or isn't sure, the check fails. It never passes by accident and never disappears from the report. Every change must keep this true, and every new operator needs tests for missing, `null` and wrong-typed input.

The report must stay byte-identical for the same policy and input, whatever order the policy was written in. Sort anything that ends up in the report.

## Docs

When behaviour changes, update its rule in `spec/` and add or change cases for it, so `spec_test.rego` fails when one no longer matches. When a policy or a report changes shape, update `spec/policy/schema.json` or `spec/report/schema.json` too. Update `REFERENCE.md` in the same change. When it affects the first policy or its report, update `README.md` too, when it changes how `ergo.rego` runs, `OPA.md`, and when it changes the `ergo` command, `CLI.md`.

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

- `rego:` `engines/rego/ergo.rego` and its tests
- `rust:` the Rust engine in `engines/rust/`
- `docs:` `README.md`, `OPA.md`, `CLI.md`, `REFERENCE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `CODE_OF_CONDUCT.md` and the issue and pull request templates
- `site:` the website in `site/`
- `ci:` workflows and Dependabot
- `examples:` the worked examples in `examples/`
- `spec:` the spec in `spec/`, its cases and `engines/rego/spec_test.rego`
- `playground:` the playground in `packages/playground`, the Markdown compiler in `packages/markdown` and the pnpm workspace around them

For example, `rego: fail compare when either side is missing`. Commits from before the Rust engine say `core:` for `rego:`, and commits from before the playground say `markdown:` for `playground:`.

One area per commit. A `rego:` or `rust:` change that updates `REFERENCE.md` or `spec/` with it keeps its area. A `rego:` change that alters behaviour adds the cases Rust now fails to `engines/rust/known-failures.txt`, and keeps its area. The `rust:` change that ports it deletes those lines.

When a `rego:` or `rust:` change alters the report for an existing policy, say so in the body, on a line starting with `Changes the report:`.

Add a body when the reason isn't obvious from the first line. PR titles follow the same rules, because they become the commit on `main`. Issue titles do too, so an issue reads like the change that will fix it.

CI checks every PR title against the areas listed above, so a new area only needs adding to that list.
