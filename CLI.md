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
curl -L https://github.com/kosli-dev/ergo/releases/download/rust-v0.1.0/ergo-0.1.0-macos-arm64.tar.gz | tar xz
./ergo --version
```

On Linux, the file is `ergo-0.1.0-linux-x86_64.tar.gz`.

To build it from this repo with Docker instead, see [`engines/rust/README.md`](engines/rust/README.md#building-the-cli).

## Run a policy

Write the policy of the [README](README.md#a-first-policy) in `policy.yaml`, and its input in `deployments.json`. `ergo` reads the policy, the input and the params from files, each one `.json`, `.yaml` or `.yml`. Ask for the report, or only for what went wrong:

```sh
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

The report is the one the [README](README.md#the-report) shows, apart from `engine`, which says `{"name": "ergo-policy-engine", "version": "0.1.0"}`. The violations are the same too.

`--params <file>` gives the policy its params. The file holds the params themselves, like `limit: 9`, without a `params:` key around them, and without `--params` they are `{}`. The output has sorted keys and two-space indents, like `opa eval --format=pretty`, and `--compact` prints one line. `ergo --version` prints the version.

Without `--fail`, the command exits 0 whenever it printed the output, even when `compliant` is `false`. With `--fail` it still prints all of it, then exits with a code that says how the policy did, so a CI job can stop on it:

| Code | When                                                                                                                                      |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | The output was printed, and the policy is met or `--fail` isn't given.                                                                    |
| 1    | With `--fail`: a check failed. Input Ergo can't read, like a missing field, counts as a failed check.                                     |
| 2    | The command line is wrong, a file can't be read or parsed, or the output couldn't be written, so it may be cut short.                     |
| 3    | With `--fail`: the policy is written wrong, so a `$well_formed` row failed, or it has no requirements, so no check ran. This wins over 1. |

When the command line or a file is wrong, the command says why on one line of stderr.

YAML is read the way OPA reads it: `yes`, `no`, `on` and `off` are booleans, `010` is 8, `0x10` is 16, dates stay strings, `<<` merges, and only the first document counts. `ergo` also refuses most files OPA refuses, like one with a control character, a tag that doesn't fit its value like `!!int 1.5`, more than 10,000 levels of nesting, or too many aliases.

These differences are known:

- `ergo` keeps a number as it was written, and OPA turns it into a 64-bit float, so `1.10` stays `1.10` where OPA reads 1.1. Outside the range of a float this changes more than the digits: OPA reads `1e400` as the string `"1e400"` and `1e-400` as 0, and `ergo` reads both as the numbers written. So with `size: 1e400`, `size is at least 5` passes in `ergo` and fails in `ergo.rego`, and with `size: 1e-400`, `size is more than 0` does the same.
- `ergo` reads some malformed files that OPA refuses, so a check can pass on a file `ergo.rego` never reads. These are a line that starts with a tab, or a blank line holding one, a directive other than `%YAML` and `%TAG`, a file of only `...`, an escape YAML 1.1 doesn't have like `\/`, a plain key over two lines or longer than 1,024 characters, `{a` and `: 1}` on separate lines, `&x:` written without a space, and LS or PS used as a line break.
- `ergo` refuses some files OPA reads. These are a tab after a colon, a tag outside YAML's own, a verbatim tag, `!!merge`, UTF-16, a byte order mark inside a value, flow collections nested more than 255 levels, a quoted value whose next line starts with a tab, `*a: v` with no space before the colon, `%YAML 01.1`, and a `!!timestamp` with two spaces before the time.
- A few values differ: LS and PS inside quoted text, the U+FFFD characters for bad UTF-8 in a `!!binary`, and two keys that end up with the same name, like `1:` and `1.0:`, where OPA keeps one at random and `ergo` keeps the last.

## Updating

Run `cargo install --locked ergo-policy-cli` again, or download the newest release of the CLI. [`engines/rust/CHANGELOG.md`](engines/rust/CHANGELOG.md) says what each release changed, and which spec version it follows.
