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
curl -L https://github.com/kosli-dev/ergo/releases/download/rust-v0.3.0/ergo-0.3.0-macos-arm64.tar.gz | tar xz
./ergo --version
```

On Linux, the file is `ergo-0.3.0-linux-x86_64.tar.gz`.

To build it from this repo with Docker instead, see [`engines/rust/README.md`](engines/rust/README.md#building-the-cli).

## Run a policy

Write the policy of the [README](README.md#a-first-policy) in `policy.yaml`, and its input in `deployments.json`. `ergo` reads the policy, the input and the params from files, each one `.json`, `.yaml` or `.yml`. Ask for the report, or only for what went wrong:

```sh
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

The report is the one the [README](README.md#the-report) shows, apart from `engine`, which says `{"name": "ergo-rust", "version": "0.3.0"}`. The violations are the same too.

`--params <file>` gives the policy its params. The file holds the params themselves, like `limit: 9`, without a `params:` key around them, and without `--params` they are `{}`. The output has sorted keys and two-space indents, like `opa eval --format=pretty`, and `--compact` prints one line. `ergo --version` prints the version.

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

## Updating

Run `cargo install --locked ergo-policy-cli` again, or download the newest release of the CLI. [`engines/rust/CHANGELOG.md`](engines/rust/CHANGELOG.md) says what each release changed, and which spec version it follows.
