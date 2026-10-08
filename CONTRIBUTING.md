# Contributing to ergo

Bug reports, ideas and pull requests are all welcome. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

ergo is still changing a lot before its first alpha, so the policy and report formats may change under you, and a change you propose may clash with one already in progress. Open an issue before starting anything bigger than a small fix, so we can agree on the shape first.

## Reporting a bug

[Open an issue](https://github.com/kosli-dev/ergo/issues/new/choose) with the policy, the input and the report you got, and say what you expected instead. Cut them down to the smallest version that still shows the problem.

If the bug lets a check pass when it should fail, or you think it's a security problem, email [security@kosli.com](mailto:security@kosli.com) instead of opening a public issue.

## Making a change

You'll need [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) 1.19 and [Regal](https://www.openpolicyagent.org/projects/regal) 0.43.0. Some checks also need Docker.

[`AGENTS.md`](AGENTS.md) has the full rules and the commands CI runs. It's written for coding agents, but it's the same guide for people. In short:

- `ergo.rego` stays a single file with no dependencies, because users copy it into their projects.
- Every change needs tests. A bug fix starts with a test that fails because of the bug.
- No comments in `.rego` files. When code looks simpler than it could be, a test explains why.
- When ergo can't read something or isn't sure, the check fails. Every new operator needs tests for missing, `null` and wrong-typed input.
- The report stays byte-identical for the same policy and input, so sort anything that ends up in it.
- When behaviour changes, update `REFERENCE.md` in the same pull request, and `README.md` if it changes the getting-started example.

## Pull requests

The title becomes the commit on `main`, so it names the area that changed and says what the change does, in lowercase:

```
spec: fail compare when either side is missing
```

The areas are listed in [`AGENTS.md`](AGENTS.md#commits), and CI checks the title against them. If the change alters the report for an existing policy, say so in the description.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
