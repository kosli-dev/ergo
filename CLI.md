# Ergo CLI

**Experimental.** The `ergo` command runs the Rust engine of Ergo. It reads a policy, an input and params from files and prints the report or the violations as JSON. It gives the same report as [`ergo.rego`](OPA.md), apart from `engine`, which says which one made it. What a policy can say, and what a report holds, is the same for both engines, so it is in the [README](README.md) and the [reference](REFERENCE.md).

This page follows the latest release of the CLI.

## Install

Install the `ergo` CLI from crates.io. You need Rust, which [rustup](https://rustup.rs/) installs:

```sh
cargo install --locked ergo-policy-cli
```

Or download it, without Rust, for Linux (x86_64) or macOS (arm64) from the [latest release of the CLI](https://github.com/kosli-dev/ergo/releases?q=rust&expanded=true), unpack it and put `ergo` on your `PATH`:

```sh
curl -L https://github.com/kosli-dev/ergo/releases/download/rust-v0.4.0/ergo-0.4.0-macos-arm64.tar.gz | tar xz
./ergo --version
```

On Linux, the file is `ergo-0.4.0-linux-x86_64.tar.gz`.

To build it from this repo with Docker instead, see [`engines/rust/README.md`](engines/rust/README.md#building-the-cli).

## Run a policy

Write the policy of the [README](README.md#a-first-policy) in `policy.yaml`, and its input in `deployments.json`. `ergo` reads the policy, the input and the params from files, each one `.json`, `.yaml` or `.yml`. Ask for the report, or only for what went wrong:

```sh
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

The report is the one the [README](README.md#the-report) shows, apart from `engine`, which says `{"name": "ergo-rust", "version": "0.4.0"}`. The violations are the same too.

`--params <file>` gives the policy its params. The file holds the params themselves, like `limit: 9`, without a `params:` key around them, and without `--params` they are `{}`. The output has sorted keys and two-space indents, like `opa eval --format=pretty`, and `--compact` prints one line. From 0.5.0, `ergo --version` prints the version and the commit it was built from, like `ergo 0.5.0-dev (commit ab81076ed80cff04a4c2e395418ca5535c6c3dab)`, and `unknown` for a build made outside a git checkout of this repo. Before that it prints only the version.

Without `--fail`, the command exits 0 whenever it printed the output, even when `compliant` is `false`. With `--fail` it still prints all of it, then exits with a code that says how the policy did, so a CI job can stop on it:

| Code | When                                                                                                                                      |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | The output was printed, and the policy is met or `--fail` isn't given.                                                                    |
| 1    | With `--fail`: a check failed. Input Ergo can't read, like a missing field, counts as a failed check.                                     |
| 2    | The command line is wrong, a file can't be read or parsed, or the output couldn't be written, so it may be cut short.                     |
| 3    | With `--fail`: the policy is written wrong, so a `$well_formed` row failed, or it has no requirements, so no check ran. This wins over 1. |

When the command line or a file is wrong, the command says why on one line of stderr.

YAML is read the way OPA 1.21 and later read it. OPA 1.20 reads some of it differently, `yes`, `no`, `on` and `off` as booleans for one, so with OPA 1.20 `ergo.rego` can give another report on the same YAML file. Only `true` and `false` are booleans, so `yes`, `no`, `on` and `off` are strings: with `approved: yes`, `approved is true` fails, so write `approved: true`. `010` is 8, `0x10` is 16, dates stay strings, and a date tagged `!!timestamp` is written out in full, like `2001-12-14T00:00:00Z`. `<<` merges, and a key written in the mapping wins over a merged one, wherever the `<<` is. A tag YAML doesn't define, like `!custom 5`, keeps the text, `"5"`, and a bare `!` reads a plain value as if it had no tag, so `! 5` is 5. Only the first document counts, but the others must still be valid YAML. `ergo` also refuses most files OPA refuses, like one with a control character, a directive other than `%YAML 1.1` and `%TAG`, a tag that doesn't fit its value like `!!int 1.5` or `!!bool yes`, the same alias twice as a key of one mapping, more than 10,000 levels of nesting, or too many aliases.

These differences are known:

- `ergo` keeps a number as it was written, and OPA turns it into a 64-bit float, so `1.10` stays `1.10` where OPA reads 1.1. Outside the range of a float this changes more than the digits: OPA reads `1e400` as the string `"1e400"` and `1e-400` as 0, and `ergo` reads both as the numbers written. So with `size: 1e400`, `size is at least 5` passes in `ergo` and fails in `ergo.rego`, and with `size: 1e-400`, `size is more than 0` does the same.
- `ergo` reads some malformed files that OPA refuses, so a check can pass on a file `ergo.rego` never reads. These are a line that starts with a tab, or a blank line holding one, a tab after the dash of a list item, like `-<tab>a`, which `ergo` reads as `["a"]`, a file of only `...`, an escape YAML 1.1 doesn't have like `\/`, a plain key over two lines or longer than 1,024 characters inside `{}`, like `{a` and ` b: 1}` on two lines, which `ergo` reads as `{"a b": 1}` (written as a `key: value` line, both refuse it), `{a` and `: 1}` on separate lines, `&x:` written without a space, an anchor name with a character other than a letter, a digit, `-` and `_`, like `&a.b`, `&a/b`, `&é` or an emoji, in any document, and a byte order mark at the start of a line after `...`, like `a: 1`, `...` and `<BOM>b: 2`, which `ergo` reads as `{"a": 1}`. That last one includes a byte order mark before `---`, `%YAML 1.2`, `%TAG` or `%FOO`, so `ergo` doesn't check the directive after it.
- `ergo` refuses some files OPA reads. These are a tab after a colon, UTF-16, a byte order mark inside a value or right after `---` at the start of a later document, flow collections nested more than 255 levels, in the first document or a later one, a quoted value whose next line starts with a tab, `*a: v` with no space before the colon, `%YAML 1.1#c` with no space before the comment, and a directive inside a document with no `...` before it, like `a: 1`, `%YAML 1.1`, `---` and `b: 2` on four lines, which OPA reads as `{"a": 1}`. The same goes for `%TAG` there, and for a list as the first document.
- `ergo` reads LS and PS (U+2028 and U+2029) as ordinary characters, and OPA reads them as line breaks. So `a: 1<LS>b: 2` is `{"a": 1, "b": 2}` in OPA and refused by `ergo`, `a: x<LS>y` is refused by OPA and read by `ergo` as text that holds the LS, and in quoted text OPA drops the spaces around one, so `"x <LS> y"` is `"x<LS>y"` in OPA and keeps the spaces in `ergo`.
- The U+FFFD characters for bad UTF-8 in a `!!binary` differ.

## Test a policy with examples (experimental)

**Experimental, from 0.5.0.** A policy can carry examples: inputs, each with the outcome its report must have, written in the words the report uses. `ergo test` runs them. The form of an outcome, and what it checks, is in the [reference](REFERENCE.md#examples).

`ergo report --format outcome` prints a report as outcome lines in YAML, so you write an example by running the policy on its input and pasting what it prints under `outcome:`. With the policy below in `policy.yaml`, and `deployments.json` holding:

```json
{
  "deployments": [
    {"id": "d1", "author": "ann", "approver": "bob"},
    {"id": "d2", "author": "cat", "approver": "cat"}
  ]
}
```

`ergo report --policy policy.yaml --input deployments.json --format outcome` prints:

```yaml
- not compliant
- approved is not met:
    - deployment d1 passes approver_set
    - deployment d1 passes not_self_approved
    - deployment d2 passes approver_set
    - deployment d2 fails not_self_approved because approver is "cat", and author is "cat"
```

Each example keeps only the lines it is about. Here is the policy with two examples:

```yaml
ergo_spec: v0.7-dev
subjects:
  deployment:
    from: deployments
    identified_by: id
requirements:
  approved:
    subject: deployment
    checks:
      approver_set: approver is a non-empty string
      not_self_approved: approver does not equal author

examples:
  - name: a deployment needs an approver
    input:
      deployments:
        - {id: d1, author: ann}
        - {id: d2, author: ann, approver: bob}
    outcome:
      - approved:
          - deployment d1 fails approver_set because approver is missing
          - deployment d2 passes approver_set

  - name: nobody approves their own deployment
    input:
      deployments:
        - {id: d1, author: ann, approver: bob}
        - {id: d2, author: cat, approver: cat}
    outcome:
      - approved:
          - deployment d1 passes not_self_approved
          - deployment d2 fails not_self_approved
```

`ergo test policy.yaml` prints:

```
passed: a deployment needs an approver
passed: nobody approves their own deployment
2 examples: 2 passed, 0 failed
```

A line covers its check, so every failure of that check must be listed. If the first example's `d2` had `approver: ""` and the example listed only `d1`, it would fail, and `ergo test` shows its lines next to the report's:

```
failed: a deployment needs an approver
  no line says deployment d2 fails approver_set because approver is ""
  expected:
    - approved:
        - deployment d1 fails approver_set because approver is missing
  actual:
    - approved:
        - deployment d1 fails approver_set because approver is missing
        - deployment d2 fails approver_set because approver is ""
passed: nobody approves their own deployment
warning: no example shows approver_set of approved failing
warning: no example shows approver_set of approved passing
2 examples: 1 passed, 1 failed
```

The last lines warn about each check that no example shows failing, or none shows passing, counting only the examples that passed. `--strict` makes a warning fail the run, for CI. `ergo test` exits 0 when every example passed, 1 when one failed or, with `--strict`, when there's a warning, and 2 when the policy file can't be read or its examples are written wrong, like two examples with the same name, or an outcome that is empty, isn't a list, or has a heading with no status and no lines. It also refuses a YAML policy file that writes a key twice in the same mapping anywhere inside `examples` or `example_params`, like two `outcome` keys in one example, because the second would replace the first and the example would lose its lines without a word. A JSON policy file isn't checked for that yet, and neither is a mapping that writes a key twice outside `examples` and that an alias brings into it. `ergo report --format outcome` exits 2 for a report it can't show yet, and with `--fail` it exits 3 for a policy written wrong, as it does without `--format`.

A child subject's line names its parent after its id, with `in`, every time, and a grandchild's names its grandparent after that. With `artifact` read from `every deployment.artifacts` and `tested` checking `tests_passed: tests is "passed"` on each artifact, and `deployments.json` holding:

```json
{
  "deployments": [
    {"id": "d1", "artifacts": [{"name": "web", "tests": "failed"}, {"name": "api", "tests": "passed"}]},
    {"id": "d2", "artifacts": [{"name": "web", "tests": "passed"}]}
  ]
}
```

`ergo report --policy policy.yaml --input deployments.json --format outcome` prints:

```yaml
- not compliant
- tested is not met:
    - artifact web in deployment d1 fails tests_passed because tests is "failed"
    - artifact api in deployment d1 passes tests_passed
    - artifact web in deployment d2 passes tests_passed
```

So the two artifacts called `web` are two lines. A line for a child subject that leaves out its `in`, like `artifact web passes tests_passed`, fails its example with `can't read the line 'artifact web passes tests_passed': artifact is read inside deployment, so its id is followed by in deployment <id>`.

For now, outcome lines cover the policy's own checks. A line for a check Ergo adds like `$min_subjects`, for a subject out of scope, or for a subject whose id is an object or a list can't be written yet, and `--format outcome` refuses a report that has a row of that kind it would have to print. It also refuses a report whose heading could name two requirements, like `x is met:` for `x` when the policy also has a requirement called `x is met`, because `ergo test` would refuse that heading. An example whose lines cover such a row fails and says it can't check it yet.

## Updating

Run `cargo install --locked ergo-policy-cli` again, or download the newest release of the CLI. [`engines/rust/CHANGELOG.md`](engines/rust/CHANGELOG.md) says what each release changed, and which spec version it follows.
