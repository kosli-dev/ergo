# ergo-policy-cli

**Experimental.** This crate may change without notice. Use [`ergo.rego`](https://github.com/kosli-dev/ergo) for real policies.

Part of [Ergo](https://github.com/kosli-dev/ergo), which turns policy evaluation into a report that says what was checked, what failed and why. This crate installs the `ergo` command, which runs the Rust engine, [`ergo-policy-engine`](https://crates.io/crates/ergo-policy-engine).

```sh
cargo install --locked ergo-policy-cli
ergo report --policy policy.yaml --input deployments.json
ergo violations --policy policy.yaml --input deployments.json
```

The policy, the input and the optional `--params` file are each `.json`, `.yaml` or `.yml`. `report` prints the whole report as JSON and `violations` prints only what failed. The command exits 2 when the command line is wrong, a file can't be read or the output couldn't be written. Otherwise it exits 0, unless `--fail` is given: then it prints the output in full and exits 1 when a check failed, or 3 when the policy is written wrong or has no requirements.
