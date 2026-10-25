# Contributing to Ergo

Bug reports, ideas and pull requests are all welcome. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

Ergo is still changing a lot before its first alpha, so the policy and report formats may change under you, and a change you propose may clash with one already in progress. Open an issue before starting anything bigger than a small fix, so we can agree on the shape first.

## Reporting a bug

[Open an issue](https://github.com/kosli-dev/ergo/issues/new/choose) with the policy, the input and the report you got, and say what you expected instead. Cut them down to the smallest version that still shows the problem.

If the bug lets a check pass when it should fail, or you think it's a security problem, email [security@kosli.com](mailto:security@kosli.com) instead of opening a public issue.

## Making a change

You'll need [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) 1.20.2 and [Regal](https://www.openpolicyagent.org/projects/regal) 0.43.0. Some checks also need Docker.

[`AGENTS.md`](AGENTS.md) has the full rules and the commands CI runs. It's written for coding agents, but it's the same guide for people. In short:

- `ergo.rego` stays a single file with no dependencies, because users copy it into their projects.
- Every change needs tests. A bug fix starts with a test that fails because of the bug.
- No comments in `.rego` files. When code looks simpler than it could be, a test explains why.
- When Ergo can't read something or isn't sure, the check fails. Every new operator needs tests for missing, `null` and wrong-typed input.
- The report stays byte-identical for the same policy and input, so sort anything that ends up in it.
- When behaviour changes, update `REFERENCE.md` in the same pull request, and `README.md` if it changes the getting-started example.

## Pull requests

The title becomes the commit on `main`, so it names the area that changed and says what the change does, in lowercase:

```
core: fail compare when either side is missing
```

The areas are listed in [`AGENTS.md`](AGENTS.md#commits), and CI checks the title against them. If the change alters the report for an existing policy, say so in the description.

## Releases

A release is a tag on a commit of `main`, pushed after the test workflow passed on that commit:

```sh
git tag rego-v0.1.0 <commit>
git push origin rego-v0.1.0
```

Changelogs are written by hand, in the pull request that makes the change. The first change after a release adds the next heading, `## X.Y.Z` in `CHANGELOG.md` or `## X.Y` in `spec/CHANGELOG.md`, and the release workflow needs that exact text.

For `ergo.rego`, the tag is `rego-vX.Y.Z`. On that commit `ergo.rego` says `X.Y.Z-dev` and `CHANGELOG.md` has a line that is exactly `## X.Y.Z`. The workflow checks all of that and that the tests passed, publishes a GitHub release with a copy of `ergo.rego` that says `X.Y.Z`, and opens a pull request that moves `main` to the next `-dev` version.

A pull request opened by GitHub Actions gets no checks, so close and reopen it to run them, then merge it. Until it's merged, the `checks` job of every pull request stays green but shows a warning that `main` is still at `X.Y.Z-dev`.

For the spec, the tag is `spec-vX.Y`. The `$id` of both schemas, `_spec` in `ergo.rego` and a line `## X.Y` in `spec/CHANGELOG.md` already say `X.Y`. The workflow checks that and that the tests passed, runs the spec checks and starts the site deploy. It doesn't wait for the deploy, so afterwards check that `https://ergo.kosli.com/spec/X.Y/policy.schema.json` loads.

`site/spec-schemas.sh` reads the schemas of every `spec-vX.Y` tag when the site is built. It fails the build when a tag's schemas don't name that version, so a bad tag has to be deleted.

If a job fails because the test workflow hasn't finished on that commit, wait and re-run the failed jobs. If only the bump job fails, re-run the failed jobs too. For anything else, delete the tag with `git push --delete origin rego-vX.Y.Z` (or `spec-vX.Y`), delete the release if one was created, with `gh release delete rego-vX.Y.Z --yes`, fix `main` and tag again.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
