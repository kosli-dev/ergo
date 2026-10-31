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
rego: fail compare when either side is missing
```

The areas are listed in [`AGENTS.md`](AGENTS.md#commits), and CI checks the title against them. If the change alters the report for an existing policy, say so in the description.

## Releases

A release is a tag on the commit at the tip of `main`, pushed after the test workflow passed on that commit. `.github/release.sh` makes and pushes the tags:

```sh
.github/release.sh rego-v0.1.0
.github/release.sh rego-v0.2.0 spec-v0.2
.github/release.sh rust-v0.1.0
```

It runs the checks below on `origin/main` first, so a tag that would fail in the workflow is never pushed, shows the commit and the tags, and pushes only when you answer `y`. It needs `gh` logged in, to see whether the tests passed.

Changelogs are written by hand, in the pull request that makes the change. The first change after a release adds the next heading, `## X.Y.Z` in `CHANGELOG.md` or `## X.Y` in `spec/CHANGELOG.md`, and the release workflow needs that exact text. For `ergo.rego` and the Rust engine, that change also moves the version to match the heading: the next patch, minor or major of the latest release, a new minor (a new major from 1.0) when the entry has a `### Changed` or `### Removed` part. `.github/changelog-version.sh` checks that in the `checks` job. Between a release and the merge of its bump pull request, it only warns, for both engines. For the spec, that change also moves the spec version to `vX.Y-dev`, see the spec's [Versions](spec/README.md#versions), and the `checks` job fails when it doesn't. From 0.2.0 on, an entry has four parts, `### New`, `### Changed`, `### Fixed` and `### Removed`, with only the parts that have something in them, and a bug fix that changes reports goes under Fixed, with the old and the new row. Other report changes go under Changed, with the old and the new row too. Anything that can break a policy or a report that worked goes under Changed, with what to do about it, even when it comes with a fix.

For `ergo.rego`, the tag is `rego-vX.Y.Z`. On that commit `ergo.rego` says `X.Y.Z-dev` and `CHANGELOG.md` has a line that is exactly `## X.Y.Z`. `_spec` must not end in `-dev` on that commit, so a spec that is still `-dev` has to be released first, or in the same call, like `.github/release.sh rego-v0.3.0 spec-v0.3`, after a pull request dropped its `-dev`. The workflow checks all of that and that the tests passed, publishes a GitHub release with a copy of `ergo.rego` that says `X.Y.Z`, starts the site deploy so the site shows the release, and opens a pull request that moves `main` to the next patch version, like `0.3.1-dev` after `0.3.0`.

GitHub holds the checks of a pull request opened by GitHub Actions until someone approves them, so click "Approve and run" on it, or close and reopen it, then merge it once they pass. Until it's merged, the `checks` job of every pull request stays green but shows a warning that `main` is still at `X.Y.Z-dev`.

For the spec, the tag is `spec-vX.Y`. First a pull request drops `-dev` from `vX.Y-dev` in `_spec`, the `$id` of both schemas and `ergo_spec` in every policy, and moves `ergo_spec` in `README.md` from the last released version to `vX.Y`, with the report output shown there. On the tagged commit they say `X.Y`, without `-dev`, and `spec/CHANGELOG.md` has a line `## X.Y`. The workflow checks that and that the tests passed, runs the spec checks, publishes a GitHub release with both schemas, and starts the site deploy. That release is never marked as the latest, so `releases/latest` stays the newest `ergo.rego`, and `.github/release-latest.py` fails CI if the workflow would change that. It doesn't wait for the deploy, so afterwards check that `https://ergo.kosli.com/spec/X.Y/policy.schema.json` loads.

For the Rust engine, the tag is `rust-vX.Y.Z`, and it publishes the crates `ergo-policy-sentences`, `ergo-policy-engine` and `ergo-policy-cli` to crates.io. The Rust engine is experimental, and its releases are too. Unlike `ergo.rego`, the crates must not say `-dev` on the tagged commit, because that is the version crates.io gets. So a pull request prepares the release first, and one more moves `main` on afterwards:

1. In a pull request, set `version` under `[workspace.package]` in `engines/rust/Cargo.toml` to `X.Y.Z`, and the `version = "..."` of the path dependencies in `engine/Cargo.toml`, `cli/Cargo.toml`, `wasm/Cargo.toml` and `sentences-wasm/Cargo.toml`. Run `cargo update --workspace` in `engines/rust` so `Cargo.lock` follows. The pull request sets the version without `-dev`, and renames the heading in `engines/rust/CHANGELOG.md` from `## X.Y.Z (not released yet)` to exactly `## X.Y.Z`. `release.sh` refuses the tag until it does. Check that `ergo_spec` in the example of `engines/rust/engine/README.md` names a released spec version, and change `0.1.0-dev` to `X.Y.Z` in the line of `README.md` that shows the Rust engine's `engine` field.
2. After it merges and the test workflow passed, run `.github/release.sh rust-vX.Y.Z`. It refuses a version with `-dev`, a version that isn't the one in `Cargo.toml` on `main`, and a changelog without that heading.
3. The workflow checks the same things and that the three crates package, builds the `ergo` binary for Linux (x86_64 and arm64, on Ubuntu 22.04 so it runs with glibc 2.35 and later), macOS (arm64) and Windows (x86_64), publishes the three crates in that order with crates.io's trusted publishing, and creates a GitHub release with the four binaries, each with `LICENSE`, as `.tar.gz` files and a `.zip` for Windows, and a `SHA256SUMS` file for all four. That release is never the latest, so `releases/latest` stays the newest `ergo.rego`. Then it opens a pull request that moves `main` to the next patch version, like the one for `ergo.rego`, and adds the heading `## X.Y.Z (not released yet)` for it to `engines/rust/CHANGELOG.md`. Merge it once its checks pass.

The first publish is by hand, because crates.io's trusted publishing can only be set up for a crate that exists. Publish from the merge commit of the pull request that prepared the release: check out that commit by its sha, with `git fetch origin && git checkout <sha>`, and check that `git status` is clean. Merge nothing to `main` from then until the `rust-v` release run has finished, the bump pull requests of other releases included, because `.github/release.sh` tags the tip of `main`, and the tag has to be the commit the crates came from. A maintainer with a crates.io API token runs this in `engines/rust`, in this order, because each crate needs the one before it on crates.io. The token needs the `publish-new` and `change-owners` scopes, with the crate pattern `ergo-policy*`, which works for crates that don't exist yet. Run `cargo login` in a shell that won't keep the token. If a `cargo publish` fails partway, fix the cause and go on from the crate that failed, skipping the ones already on crates.io:

```sh
cargo publish --locked -p ergo-policy-sentences
cargo publish --locked -p ergo-policy-engine
cargo publish --locked -p ergo-policy-cli
```

Then:

1. For each crate, add a `kosli-dev` GitHub team and a second maintainer as owners, so publishing doesn't depend on one account: `cargo owner --add github:kosli-dev:<team> <crate>` and `cargo owner --add <login> <crate>`. Adding the team only works when the person running it is in that team, and when the `kosli-dev` organization lets crates.io read its teams, which an organization owner allows under the organization's third-party (OAuth app) access settings.
2. Create a GitHub environment named `crates-io` and limit it to `rust-v*` tags with a deployment tag rule, so only a tag can publish.
3. For each crate, open its Settings on crates.io and add a trusted publisher for GitHub, with the owner `kosli-dev`, the repository `ergo`, the workflow `release.yml` and the environment `crates-io`.
4. Revoke the API token on crates.io straight away.

Then check that `git rev-parse origin/main` is still that sha, and tag it with `.github/release.sh rust-v0.1.0`. When `rego-v` or `spec-v` tags were pushed for the same commit, wait until their release runs have finished first, with `gh run list --workflow release.yml`: the release runs share one concurrency group, so a newer run cancels one that is waiting, and that release would never be made. The workflow sees the crates are already on crates.io, skips them, and makes the GitHub release with the binaries. Every later release goes through the tag alone.

The site at https://ergo.kosli.com shows the latest published `rego-vX.Y.Z` release, not `main`. The tutorial, the docs pages, the bakery example, the home page's examples and the `ergo.rego` they run all come from that release, and the spec link and schemas from the published `spec-vX.Y` releases, so they can teach something on `main` before it's released and reach the site with the release. The home page's layout and words, the other pages and the CSS follow `main`. CI tests the tutorial and the home page's examples against `main`'s `ergo.rego`, and checks that the released tutorial still fits `main`'s layouts and CSS. [`site/README.md`](site/README.md) has the full list, and how to preview either version.

Releases are only made by the release workflow, never by hand in GitHub or with `gh release create`. GitHub marks a release made by hand as the latest unless you untick it, and then `releases/latest/download/ergo.rego` stops working. The workflow marks an `ergo.rego` release as the latest only when it's the highest `rego-vX.Y.Z` version, so a fix to an older version doesn't take it, and never marks a spec release as the latest. Its release notes are that version's section of the changelog, with links to `.md` files pointing at the tag. The one exception so far is `spec-v0.1`, which was tagged before the workflow published spec releases, so its release was made once by hand with the same title, notes, files and `--latest=false`.

If a release job fails after its tag is pushed, fix the cause and run it again from the Actions tab, or with `gh workflow run release.yml --ref main -f tag=<tag>`. It runs the same checks and steps on that existing tag. For a spec tag whose release is already there, it skips creating it again. For a `rust-vX.Y.Z` tag, run it from the tag instead, with `gh workflow run release.yml --ref rust-vX.Y.Z -f tag=rust-vX.Y.Z` or by picking the tag in the Actions tab. A run from `main` can't publish, because the `crates-io` environment only lets `rust-v*` tags in, and that's on purpose. It skips the crates and the release that are already there.

When both tags are pushed together, the `ergo.rego` job can start the site deploy before the spec's release is published, and that deploy fails, leaving the old site up. The spec job starts another deploy once its release is out, so check the site after both jobs have finished.

`site/spec-schemas.sh` reads the schemas of every published `spec-vX.Y` release when the site is built. It fails the build when a tag's schemas don't name that version, so a bad tag has to be deleted. A bad `rego-vX.Y.Z` tag has to be deleted too, even when its release job failed: the job marks a release as the latest only when its tag is the highest `rego-v` tag, so a stray `rego-v9.0.0` would stop every later release from becoming the latest. The job's log says which tag it compared with and which flag it chose.

If a job fails because the test workflow hasn't finished on that commit, wait and re-run the failed jobs. If only the bump job fails, re-run the failed jobs too. For anything else, delete the tag with `git push --delete origin rego-vX.Y.Z` (or `spec-vX.Y`) and `git tag -d rego-vX.Y.Z`, delete the release if one was created, with `gh release delete rego-vX.Y.Z --yes`, fix `main` and run the script again.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
