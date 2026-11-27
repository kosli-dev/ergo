# Ergo CLI

**Experimental.** The `ergo` command runs the Rust engine of Ergo. It reads a policy, an input and params from files, or from standard input, and prints the report or the violations as JSON. It gives the same report as [`ergo.rego`](OPA.md), apart from `engine`, which says which one made it. What a policy can say, and what a report holds, is the same for both engines, so it is in the [README](README.md) and the [reference](REFERENCE.md).

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

Write the policy of the [README](README.md#a-first-policy) in `policy.yaml`, and its input in `deployments.json`. `ergo` reads the policy, the input and the params from files, each one `.json`, `.yaml` or `.yml`, or from standard input with `-` (see [Read from standard input](#read-from-standard-input)). Ask for the report, or only for what went wrong:

```sh
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

The report is the one the [README](README.md#the-report) shows, apart from `engine`, which says `{"name": "ergo-rust", "version": "0.4.0"}`. The violations are the same too.

> **Multi-document YAML isn't supported.** A YAML file can hold several documents, split by `---`, as the output of `helm template` and many other tools does. `ergo` reads only the first document, and nothing in the report says there was another. Checks on the later documents give no result, and the report can say `compliant` because of it. With this `input.yaml`:
>
> ```yaml
> kind: ServiceAccount
> ---
> kind: Deployment
> replicas: 0
> ```
>
> Ergo reads `{"kind": "ServiceAccount"}`. The `Deployment` is never checked, so a policy that requires every deployment to have replicas passes. Split the file before Ergo reads it, or put the documents in one list, and write the policy's `from` to match.

`--params <file>` gives the policy its params. The file holds the params themselves, like `limit: 9`, without a `params:` key around them, and without `--params` they are `{}`. The output has sorted keys and two-space indents, like `opa eval --format=pretty`, and `--compact` prints one line. From 0.5.0, `ergo --version` prints the version and the commit it was built from, like `ergo 0.5.0-dev (commit ab81076ed80cff04a4c2e395418ca5535c6c3dab)`, and `unknown` for a build made outside a git checkout of this repo. Before that it prints only the version.

Without `--fail`, the command exits 0 whenever it printed the output, even when `compliant` is `false`. With `--fail` it still prints all of it, then exits with a code that says how the policy did, so a CI job can stop on it:

| Code | When                                                                                                                                      |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | The output was printed, and the policy is met or `--fail` isn't given.                                                                    |
| 1    | With `--fail`: a check failed. Input Ergo can't read, like a missing field, counts as a failed check.                                     |
| 2    | The command line is wrong, a file can't be read or parsed, or the output couldn't be written, so it may be cut short.                     |
| 3    | With `--fail`: the policy is written wrong, so a `$well_formed` row failed, or it has no requirements, so no check ran. This wins over 1. |

When the command line or a file is wrong, the command says why on one line of stderr.

YAML is read the way OPA 1.21 and later read it. OPA 1.20 reads some of it differently, `yes`, `no`, `on` and `off` as booleans for one, so with OPA 1.20 `ergo.rego` can give another report on the same YAML file. Only `true` and `false` are booleans, so `yes`, `no`, `on` and `off` are strings: with `approved: yes`, `approved is true` fails, so write `approved: true`. `010` is 8, `0x10` is 16, dates stay strings, and a date tagged `!!timestamp` is written out in full, like `2001-12-14T00:00:00Z`. `<<` merges, and a key written in the mapping wins over a merged one, wherever the `<<` is. A tag YAML doesn't define, like `!custom 5`, keeps the text, `"5"`, and a bare `!` reads a plain value as if it had no tag, so `! 5` is 5. Only the first document counts, but the others must still be valid YAML (see the warning under [Run a policy](#run-a-policy)). `ergo` also refuses most files OPA refuses, like one with a control character, a directive other than `%YAML 1.1` and `%TAG`, a tag that doesn't fit its value like `!!int 1.5` or `!!bool yes`, the same alias twice as a key of one mapping, more than 10,000 levels of nesting, or too many aliases.

These differences are known:

- `ergo` keeps a number as it was written, and OPA turns it into a 64-bit float, so `1.10` stays `1.10` where OPA reads 1.1. Outside the range of a float this changes more than the digits: OPA reads `1e400` as the string `"1e400"` and `1e-400` as 0, and `ergo` reads both as the numbers written. So with `size: 1e400`, `size is at least 5` passes in `ergo` and fails in `ergo.rego`, and with `size: 1e-400`, `size is more than 0` does the same.
- `ergo` reads some malformed files that OPA refuses, so a check can pass on a file `ergo.rego` never reads. These are a line that starts with a tab, or a blank line holding one, a tab after the dash of a list item, like `-<tab>a`, which `ergo` reads as `["a"]`, a file of only `...`, an escape YAML 1.1 doesn't have like `\/`, a plain key over two lines or longer than 1,024 characters inside `{}`, like `{a` and ` b: 1}` on two lines, which `ergo` reads as `{"a b": 1}` (written as a `key: value` line, both refuse it), `{a` and `: 1}` on separate lines, `&x:` written without a space, an anchor name with a character other than a letter, a digit, `-` and `_`, like `&a.b`, `&a/b`, `&é` or an emoji, in any document, and a byte order mark at the start of a line after `...`, like `a: 1`, `...` and `<BOM>b: 2`, which `ergo` reads as `{"a": 1}`. That last one includes a byte order mark before `---`, `%YAML 1.2`, `%TAG` or `%FOO`, so `ergo` doesn't check the directive after it.
- `ergo` refuses some files OPA reads. These are a tab after a colon, UTF-16, a byte order mark inside a value or right after `---` at the start of a later document, flow collections nested more than 255 levels, in the first document or a later one, a quoted value whose next line starts with a tab, `*a: v` with no space before the colon, `%YAML 1.1#c` with no space before the comment, and a directive inside a document with no `...` before it, like `a: 1`, `%YAML 1.1`, `---` and `b: 2` on four lines, which OPA reads as `{"a": 1}`. The same goes for `%TAG` there, and for a list as the first document.
- `ergo` reads LS and PS (U+2028 and U+2029) as ordinary characters, and OPA reads them as line breaks. So `a: 1<LS>b: 2` is `{"a": 1, "b": 2}` in OPA and refused by `ergo`, `a: x<LS>y` is refused by OPA and read by `ergo` as text that holds the LS, and in quoted text OPA drops the spaces around one, so `"x <LS> y"` is `"x<LS>y"` in OPA and keeps the spaces in `ergo`.
- The U+FFFD characters for bad UTF-8 in a `!!binary` differ.

### Run a policy on `ergo.rego`

**Experimental, from 0.5.0.** `ergo report` and `ergo violations` build the report with the Rust engine. To get the one `ergo.rego` makes, the one you use in production, add `--engine rego` and the path of `ergo.rego`:

```sh
ergo report --policy policy.yaml --input deployments.json --engine rego --ergo-rego ergo.rego
ergo violations --policy policy.yaml --input deployments.json --engine rego --ergo-rego ergo.rego
```

It needs [`opa`](https://www.openpolicyagent.org/docs/#1-download-opa) and `ergo.rego`. `ergo` runs `opa eval` once, calling only `ergo.report` and, for `violations`, `ergo.violations`, and prints what `ergo.rego` built: the `engine` of the report says `ergo-rego` and its version, and `violations` are the ones `ergo.rego` builds. `--compact`, `--fail`, the exit codes, and `--format outcome` for `report` work as they do on the Rust engine. The rules for `--ergo-rego`, `ERGO_REGO`, `ERGO_OPA` and the temporary folder are the ones [for `ergo test --engine rego`](#run-the-examples-on-ergorego), including that `ergo` never looks for `ergo.rego` on its own and never downloads it. It exits 2, and never falls back to the Rust engine, when it can't read `ergo.rego`, can't run `opa`, `opa` fails or prints something that isn't one report, or `ergo.rego` doesn't support the policy's `ergo_spec`. The policy's `ergo_spec` must be one that the `ergo.rego` you pass supports, so a policy written for a newer spec than the release you downloaded is refused. It finds that out from the problem `ergo.rego` gives in the `$well_formed` row, which has the words `unsupported version `: an `ergo.rego` that words it another way isn't recognised, and `ergo` then prints its report as it is, with exit 0, or 3 with `--fail`, in place of exiting 2.

When `ergo.rego` can't be found, because there is no `--ergo-rego` and no `ERGO_REGO`, or the path can't be read, `ergo` says how to get the release. Without a path, `ergo report --policy policy.yaml --input deployments.json --engine rego` exits 2 and prints:

```
ergo: --engine rego needs ergo.rego, and it was not found in --ergo-rego or ERGO_REGO.
Get the release you run in production and pass its path. For ergo.rego 0.6.0, the latest release when this ergo was built:
  curl -fsSL -o ergo.rego https://github.com/kosli-dev/ergo/releases/download/rego-v0.6.0/ergo.rego
  ergo report --engine rego --ergo-rego ergo.rego ...
```

The `curl` line names the latest release of `ergo.rego` when this version of `ergo` was released. If you run an older one in production, change the version in the URL.

A policy written for a newer spec than the `ergo.rego` you pass is refused. For `ok.yaml` with `ergo_spec: v0.7-dev` and the `ergo.rego` of release `rego-v0.6.0` in `../rel`, `ergo report --policy ok.yaml --input input.json --engine rego --ergo-rego ../rel/ergo.rego` exits 2 and prints:

```
ergo: the ergo.rego at ../rel/ergo.rego refuses the policy file ok.yaml: policy ergo_spec: unsupported version v0.7-dev, expected v0.6
```

### Read from standard input

A value of `-` for `--policy`, `--input` or `--params`, or for the policy of `ergo test`, reads standard input, so the output of another tool can be piped in. Standard input has no file extension, so `--stdin-format json` or `--stdin-format yaml` says how it is written. `ergo` never guesses, because JSON is also valid YAML but the two read some values differently: `010` is 8 in YAML and a syntax error in JSON.

Take this `policy.yaml`:

```yaml
ergo_spec: v0.7-dev
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
requirements:
  prod_deploy:
    description: Every production deployment is approved
    subject: deployment
    checks:
      approved:
        description: Someone approved the deployment
        assert: approved_by is a non-empty string
```

and this `input.yaml`, whose second document `ergo` reads but doesn't check (see the warning under [Run a policy](#run-a-policy)):

```yaml
deployments:
  - id: d1
    environment: prod
    approved_by: bob
  - id: d2
    environment: prod
  - id: d3
    environment: staging
---
kind: Other
```

```sh
cat input.yaml | ergo report --format pretty --color never --policy policy.yaml --input - --stdin-format yaml
```

```
✗ prod_deploy is not met
    ✗ deployment d2 fails approved
      because approved_by is missing

  8 rows: 6 passed, 1 failed, 1 out of scope

∴ not compliant
```

Standard input is read once, so only one of `--policy`, `--input` and `--params` can be `-`. The rules for a file are the rules for standard input: the same reader, only the first YAML document counts and the others must still be valid YAML, the same errors and the same exit codes, and the messages say `standard input` where they say a file. It works with `--engine rego` too. Nothing changes for a path that is a file. `ergo` reads standard input last, after it has checked the command line and read every file, so a mistake that needs no input is reported at once, even when the tool that feeds standard input hasn't finished. Each of these exits 2, prints no report and says why on one line of stderr:

| What                                            | Message                                                                                        |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| A `-` with no `--stdin-format`                  | `--stdin-format json or yaml is needed when a value is -`                                      |
| A `--stdin-format` other than `json` and `yaml` | `--stdin-format must be json or yaml`                                                          |
| A `--stdin-format` with no value of `-`         | `--stdin-format only goes with a value of -`                                                   |
| Two or more values of `-`                       | `only one of --policy, --input and --params can be read from standard input`                   |
| Standard input that is a terminal               | `standard input is a terminal; pipe the input in`                                              |
| Standard input that isn't UTF-8                 | `can't read the input on standard input: stream did not contain valid UTF-8`                   |
| Standard input that isn't valid JSON or YAML    | `the input on standard input isn't valid JSON: EOF while parsing an object at line 2 column 0` |

Empty standard input is read as an empty file is: it is an error for `json`, and `null` for `yaml`.

### A view for a terminal

**Experimental, from 0.5.0.** `ergo report --format pretty` prints the report for a person to read, and the default stays JSON. With the policy of the [next section](#test-a-policy-with-examples-experimental) in `policy.yaml`, and the `deployments.json` of that section, which holds two deployments, `d1` approved by `bob` for `ann`, and `d2` approved by `cat` for `cat`, `ergo report --format pretty --policy policy.yaml --input deployments.json` prints:

```
✗ approved is not met
    ✗ deployment d2 fails not_self_approved
      because approver is "cat", and author is "cat"

  7 rows: 6 passed, 1 failed, 0 out of scope

∴ not compliant
```

It works on a report from either engine, so `--engine rego --ergo-rego ergo.rego` gives the same text. The requirements that are not met come first, each with its failed rows and the report's own `message` after `because`, then the requirements that are met or not applicable, one line each. The rows that passed and the subjects out of scope are only counted. The last line says `compliant` or `not compliant`, from the report's `compliant`, after the therefore sign (∴, U+2234), which Ergo uses for what follows from the evidence. A row names its subject by type and id, like `deployment d2`, and by type alone for a row with no id, like `deployment fails $min_subjects`. A requirement whose `status` this version doesn't know is listed among the ones that are not met, as `has status "x"`.

`--show all` lists every row under its requirement, in the order of the report. For the same policy and input it prints:

```
✗ approved is not met
    ✓ deployment passes $well_formed
    ✓ deployment passes $min_subjects
    ✓ deployment passes $unique_ids
    ✓ deployment d1 passes approver_set
    ✓ deployment d1 passes not_self_approved
    ✓ deployment d2 passes approver_set
    ✗ deployment d2 fails not_self_approved
      because approver is "cat", and author is "cat"

  7 rows: 6 passed, 1 failed, 0 out of scope

∴ not compliant
```

A row for a child subject names its parents, like `✗ artifact web in deployment d1 fails tests_passed`, the way [`--format outcome`](#test-a-policy-with-examples-experimental) writes its lines. `--show failed` is the default. `--format pretty` can't go with `--compact`, or with `violations`, and `--show` and `--color` only go with `--format pretty` and `ergo test`.

**Scope.** A policy with a `whose` filter has an `$applies` row for each subject. A subject in scope is `✓ deployment d1 is in scope`, shown with `--show all`. Only a subject whose `$applies` row fails with the cause `value` is out of scope: it is dim, `– deployment d3 is out of scope (environment is "staging")`, shown only with `--show all` and counted as out of scope. A `$applies` row that fails with any other cause, like `absent` for a deployment with no `environment`, means Ergo can't tell whether the subject is in scope, so the requirement is not met and the row is a failed row like any other, listed and counted as failed. With `from: deployments whose environment is "prod"`, `approver_set: approver is a non-empty string` and `{"deployments": [{"id": "d1", "environment": "prod", "approver": "bob"}, {"id": "d2", "approver": ""}]}`, the view is:

```
✗ approved is not met
    ✗ deployment d2 fails $applies
      because environment is missing

  6 rows: 5 passed, 1 failed, 0 out of scope

∴ not compliant
```

**Control characters.** A name, an id or a message that comes from the policy, the input or the engine can hold control characters, like an escape code that clears the screen. The view writes every control character (U+0000 to U+001F, U+007F and U+0080 to U+009F, so a newline too), the line and paragraph separators (U+2028, U+2029) and the characters that change the direction of text (U+061C, U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069) as a visible `\u{1b}`, with the code in hexadecimal, and only then adds its own colour codes. `ergo test` on a terminal does the same, and so does the engine line of `ergo test` when it is piped. Error messages on stderr are escaped the same way, except that their own line breaks stay.

**Colour.** Colour is written only when stdout is a terminal. It is off when the `NO_COLOR` environment variable is set and not empty, and `--color auto|always|never` overrides both: `always` writes the codes even into a pipe or a file, and `never` writes none. The colours are plain ANSI codes: red for a failed requirement or row, whole line, green for the `✓` of a requirement or row that passed, dim for `–` lines, which are out of scope or not applicable, and bold for the last line. `⚠` is yellow.

**Glyphs.** The marks `✓`, `✗`, `⚠`, `–` and `∴` are written when the first of `LC_ALL`, `LC_CTYPE` and `LANG` that is set and not empty contains `UTF-8` or `utf8`, in any case. Without one, or with no variable set, the plain words stand in for them: `ok`, `FAIL`, `warn`, `-` and `->`. With `LC_ALL=C`, the same report prints:

```
FAIL approved is not met
    FAIL deployment d2 fails not_self_approved
      because approver is "cat", and author is "cat"

  7 rows: 6 passed, 1 failed, 0 out of scope

-> not compliant
```

The glyphs don't depend on colour, and colour doesn't depend on them. Nothing here changes an exit code: `--fail` gives the codes in the table above for `--format pretty` too, and the view is printed before the command exits.

`--format pretty` shows only the fields it needs: `compliant`, each requirement's `status`, and each row's `requirement`, `check`, `passed`, `subject` and `message`, and the `cause` of a row of `$applies` that failed. When it can't read one of them, like a report with no `results`, a row that names a requirement that isn't in `requirements`, or a `compliant` that isn't `true` or `false`, it exits 2 and names what it couldn't read, and prints no verdict. It never checks the version of `ergo.rego` that made the report.

The first line of `ergo --help` and of the usage printed for a call with no arguments has the therefore sign, or `->` when the locale isn't UTF-8. `--version`, the JSON and the outcome lines and the violations never do, and have no colour.

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

tests:
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

On a terminal, or with `--color always`, `ergo test` marks its lines as [`--format pretty`](#a-view-for-a-terminal) does, with the same colour and glyph rules. It lists the failed examples and the warnings, then an empty line and a summary that starts with the therefore sign, and `--show all` lists every example. With `--show all`, `ergo test policy.yaml` on a terminal prints:

```
✓ a deployment needs an approver
✓ nobody approves their own deployment

∴ 2 examples: 2 passed, 0 failed
```

`--color always` gives the marked form even when stdout isn't a terminal. On a terminal, `--color never` keeps the glyph marks and only drops the colour, since the glyphs depend on the locale and the colour on `--color` and `NO_COLOR`. When stdout isn't a terminal and `--color always` isn't given, which is a pipe, a file or a CI log, the output is the plain lines above, `passed:`, `failed:`, `warning:` and `2 examples: 2 passed, 0 failed`, word for word, whatever `--show` says. The exit codes don't change.

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

The last lines warn about each check that no example shows failing, or none shows passing, counting only the examples that passed. `--strict` makes a warning fail the run, for CI. `ergo test` exits 0 when every example passed, 1 when one failed or, with `--strict`, when there's a warning, and 2 when the policy file can't be read or its examples are written wrong, like two examples with the same name, a field under `tests` it doesn't know, `examples` or `example_params` still at the top level of the policy (they are `tests.examples` and `tests.params` now), or an outcome that is empty, isn't a list, or has a heading with no status and no lines. It also refuses a YAML policy file that writes a key twice in the same mapping anywhere inside `tests`, like two `outcome` keys in one example, because the second would replace the first and the example would lose its lines without a word. A JSON policy file isn't checked for that yet, and neither is a mapping that writes a key twice outside `tests` and that an alias brings into it. `ergo report --format outcome` exits 2 for a report it can't show yet, and with `--fail` it exits 3 for a policy written wrong, as it does without `--format`.

A child subject's line names its parent after its id, with `in`, every time, and a grandchild's names its grandparent after that. With this policy in `artifacts.yaml`:

```yaml
ergo_spec: v0.7-dev
subjects:
  deployment:
    from: deployments
    identified_by: id
  artifact:
    from: every deployment.artifacts
    identified_by: name
requirements:
  tested:
    subject: artifact
    checks:
      tests_passed: tests is "passed"

tests:
  examples:
    - name: every artifact's tests pass
      input:
        deployments:
          - {id: d1, artifacts: [{name: web, tests: failed}]}
          - {id: d2, artifacts: [{name: web, tests: passed}]}
      outcome:
        - tested:
            - artifact web in deployment d1 fails tests_passed
            - artifact web in deployment d2 passes tests_passed
```

and `artifacts.json` holding:

```json
{
  "deployments": [
    {"id": "d1", "artifacts": [{"name": "web", "tests": "failed"}, {"name": "api", "tests": "passed"}]},
    {"id": "d2", "artifacts": [{"name": "web", "tests": "passed"}]}
  ]
}
```

`ergo report --policy artifacts.yaml --input artifacts.json --format outcome` prints:

```yaml
- not compliant
- tested is not met:
    - artifact web in deployment d1 fails tests_passed because tests is "failed"
    - artifact api in deployment d1 passes tests_passed
    - artifact web in deployment d2 passes tests_passed
```

So the two artifacts called `web` are two lines, and `ergo test artifacts.yaml` prints:

```
passed: every artifact's tests pass
1 example: 1 passed, 0 failed
```

A line for a child subject that leaves out its `in`, like `artifact web passes tests_passed`, fails its example with `can't read the line 'artifact web passes tests_passed': artifact is read inside deployment, so its id is followed by in deployment <id>`.

The checks Ergo adds, `$min_subjects`, `$unique_ids`, `$unique_ancestor_ids` and `$well_formed`, have lines too, under their own names. Their rows have no id, so their lines have none. A row for the requirement's own subject names no subject at all, like `fails $min_subjects because in-scope deployment count is 0`, and a row with an `in` names the subject and its parents, like `artifact in deployment d4 fails $min_subjects because in-scope artifact count is 0`. A subject out of scope isn't a failure, so its line says `is out of scope`, like `deployment d3 is out of scope because environment is "dev"`, and `is in scope` says the opposite. With this policy in `production.yaml`:

```yaml
ergo_spec: v0.7-dev
subjects:
  deployment:
    from: deployments whose environment is "prod"
    identified_by: id
  artifact:
    from: every deployment.artifacts
    identified_by: name
requirements:
  approved:
    subject: deployment
    checks:
      approver_set: approver is a non-empty string
  tested:
    subject: artifact
    checks:
      tests_passed: tests is "passed"

tests:
  examples:
    - name: only production deployments need an approver
      input:
        deployments:
          - {id: d1, environment: prod, approver: bob}
          - {id: d3, environment: dev}
      outcome:
        - approved is met:
            - deployment d3 is out of scope because environment is "dev"

    - name: a production deployment with no artifacts fails
      input:
        deployments:
          - {id: d4, environment: prod, approver: bob, artifacts: []}
      outcome:
        - tested is not met:
            - artifact in deployment d4 fails $min_subjects because in-scope artifact count is 0
```

and `production.json` holding:

```json
{
  "deployments": [
    {"id": "d1", "environment": "prod", "approver": "bob", "artifacts": [{"name": "web", "tests": "passed"}]},
    {"id": "d3", "environment": "dev"},
    {"id": "d4", "environment": "prod", "approver": "bob", "artifacts": []}
  ]
}
```

`ergo report --policy production.yaml --input production.json --format outcome` prints:

```yaml
- not compliant
- approved is met:
    - deployment d3 is out of scope because environment is "dev"
    - deployment d1 passes approver_set
    - deployment d4 passes approver_set
- tested is not met:
    - artifact in deployment d4 fails $min_subjects because in-scope artifact count is 0
    - artifact web in deployment d1 passes tests_passed
```

`--format outcome` prints a check Ergo adds only when it fails, and a subject's scope only when it is out of scope. `ergo test production.yaml` prints:

```
passed: only production deployments need an approver
passed: a production deployment with no artifacts fails
warning: no example shows approver_set of approved failing
warning: no example shows approver_set of approved passing
warning: no example shows tests_passed of tested failing
warning: no example shows tests_passed of tested passing
2 examples: 2 passed, 0 failed
```

The lines of Ergo's own checks and of scope count for no warning. A line that says a subject is out of scope only agrees when Ergo read its condition and the value didn't match. When Ergo can't tell, like for a deployment with no `environment`, the row is a failure that no line can name yet, so `ergo report --policy production.yaml --input unknown.json --format outcome`, with `unknown.json` holding `{"deployments": [{"id": "d5", "approver": "bob", "artifacts": []}]}`, exits 2 with:

```
ergo: lines for an $applies row that failed with absent, not value, aren't supported yet, as for deployment d5 in approved
```

`--format outcome` also refuses a report with a row whose id is an object or a list, a policy written wrong, two rows of one check and one subject that say different things, like two deployments `d1` where one passes and one fails, and a report whose heading could name two requirements, like `x is met:` for `x` when the policy also has a requirement called `x is met`, because `ergo test` would refuse that heading or no line would agree with both rows. An example whose lines cover a row that can't be written fails and says it can't check it yet. It also refuses a `$min_subjects` row with only some of its parents in `in`, like a test run inside an artifact inside a deployment that has no `artifacts` field, a row of a check Ergo adds whose subject name a longer one of the policy starts the same way as, like subjects `sign` and `sign in`, and two out-of-scope rows for one id with different `because` messages, though `deployment d3 is out of scope` with no `because` passes in `ergo test`.

### Run the examples on `ergo.rego`

**Experimental, from 0.5.0.** `ergo test` builds each example's report with the Rust engine. A policy that runs on `ergo.rego` can be tested on it instead, with `--engine rego`, so a difference between the two engines shows up as a failing example. It needs [`opa`](https://www.openpolicyagent.org/docs/#1-download-opa) and a copy of `ergo.rego`, like the one you use in production. Only where the reports come from changes: the lines, the warnings and the exit codes stay the same. With `ergo.rego` and `policy.yaml`, the policy with two examples above, in the current folder, `ergo test --engine rego --ergo-rego ergo.rego policy.yaml` prints:

```
engine: ergo-rego 0.7.0-dev
passed: a deployment needs an approver
passed: nobody approves their own deployment
2 examples: 2 passed, 0 failed
```

The first line names the engine the reports came from, as their `engine` field gives it, so the run can't be taken for one on the Rust engine. `ergo` runs `opa eval` once for all the examples: it compiles the policy once with `ergo.compile` and builds each report with `ergo.report`. It gives `opa` the policy and the inputs in a file in a new temporary folder, which it removes after The folder and the file are private to your user (mode 0700 and 0600). If you stop `ergo` with Ctrl-C while `opa` runs, the folder stays behind and you can delete it: it is called `ergo-test-`, `ergo-report-` or `ergo-violations-`, by the command, and a number, in your temporary folder. It needs `ergo.compile`, which [`OPA.md`](OPA.md) says may change, so a change to it can break `--engine rego`.

- `--ergo-rego` is the path of `ergo.rego`. It can't hold a `:`, which `opa` reads as a prefix, so `ergo` exits 2 and asks you to move the file. Without it, `ergo` reads the path from the `ERGO_REGO` environment variable. It never looks for `ergo.rego` on its own, so a stray copy in the folder can't test another version than the one you meant. `--ergo-rego` and `ERGO_REGO` are refused without `--engine rego`, so a run on the Rust engine can't be taken for one on `ergo.rego`. When there is no path, or it can't be read, `ergo` also says how to get the release, with a `curl` line, as [above](#run-a-policy-on-ergorego).
- `opa` is the one on your `PATH`, or the command in the `ERGO_OPA` environment variable when it's set.
- `ergo` reads the policy file and passes what it read to `opa`, so a YAML policy is read the way the Rust engine reads it. That is the way OPA 1.21 and later read YAML, apart from the differences listed above.

`ergo test --engine rego` exits 2, and never falls back to the Rust engine, when it can't read `ergo.rego`, can't run `opa`, `opa` fails, or `opa` prints something that isn't one report per example. It also exits 2 when `ergo.rego` doesn't support the policy's `ergo_spec`, with the problem `ergo.rego` gives. For `policy.yaml` with `ergo_spec: v0.6` saved as `old.yaml`, `ergo test --engine rego --ergo-rego ergo.rego old.yaml` exits 2 with:

```
ergo: the ergo.rego at ergo.rego refuses the policy file old.yaml: policy ergo_spec: unsupported version v0.6, expected v0.7-dev
```

## Updating

Run `cargo install --locked ergo-policy-cli` again, or download the newest release of the CLI. [`engines/rust/CHANGELOG.md`](engines/rust/CHANGELOG.md) says what each release changed, and which spec version it follows.
