# Working on ergo

ergo is a Rego library that turns policy evaluation into a structured report. Users copy `ergo.rego` into their own projects, so it has to stay a single file with no dependencies.

## Files

- `ergo.rego` is the whole library.
- `ergo_test.rego` holds its tests.
- `custom_op_test.rego` defines custom operators that only the tests use.
- `README.md` walks a new user through a first policy.
- `REFERENCE.md` describes every field, operator, cause and report entry.
- `packages/` holds Node tools that build on ergo, in one pnpm workspace. Someone who only copies `ergo.rego` never needs them.
- `packages/markdown/` compiles policies written in Markdown into requirements objects. Its README covers how to write one.

## Checks

Run these before saying a change is done:

```sh
opa check --strict . --ignore .github --ignore packages
opa fmt --list .
opa test . --ignore .github --ignore packages
```

`opa fmt --list .` should print nothing. If it prints file names, run `opa fmt -w .`.

OPA loads every JSON and YAML file it finds as data. The workflow files under `.github` clash with each other, and so do the workspace's files under `packages`, so the checks ignore both folders.

When you change anything under `packages/`, run these too:

```sh
cd packages
pnpm install
pnpm check
pnpm test
```

CI runs all of these on pull requests and on pushes to `main` (`.github/workflows/test.yml`), using the OPA version the README names. When you change that version, change it in the README and in both CI jobs.

CI also fails when a line of Rego, or of TypeScript under `packages/markdown/src`, isn't reached by any test. `pnpm test` checks the TypeScript. To list the Rego lines yourself:

```sh
opa test . --ignore .github --ignore packages --coverage | jq -r '.files | to_entries[] | .key as $f | .value.not_covered[]? | "\($f):\(.start.row)"' | sort -u
```

## Tests

Every change needs tests: new behaviour, bug fixes and changes to existing behaviour alike. A bug fix starts with a test that fails because of the bug. A change without tests isn't finished.

## No comments

There are no comments in the code or the tests, and it should stay that way.

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
- `markdown:` the Markdown compiler in `packages/markdown`, its examples and its README

For example, `core: fail compare when either side is missing`.

One area per commit. A `core:` change that updates `REFERENCE.md` with it stays `core:`.

When a `core:` change alters the report for an existing policy, say so in the body, on a line starting with `Changes the report:`.

Add a body when the reason isn't obvious from the first line. PR titles follow the same rules, because they become the commit on `main`.

CI checks every PR title against the areas listed above, so a new area only needs adding to that list.
