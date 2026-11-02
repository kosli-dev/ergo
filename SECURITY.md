# Security policy

## Supported versions

Ergo is before 1.0, and only the latest release of each thing we ship gets fixes:

- `ergo.rego`, released as `rego-v*` tags
- the spec, released as `spec-v*` tags
- the Rust crates and the `ergo` command, released as `rust-v*` tags

If you find a problem in an older release, check the latest one first.

## Reporting a vulnerability

Report it privately, in one of two ways:

- through GitHub: [open a security advisory](https://github.com/kosli-dev/ergo/security/advisories/new)
- by email to [security@kosli.com](mailto:security@kosli.com), if you don't have a GitHub account

Please don't use a public issue or pull request, because this repository is public and anything posted there is seen by everyone at once.

Say what the problem is, give the smallest policy and input that show it, and say what you think it lets someone do. A check that passes when it should fail counts, so include it too.

We will reply, tell you what we decided and why, fix what needs fixing, and credit you in the release notes if you want us to. Please give us reasonable time to ship a fix before you say anything in public.

## Bug bounty

There is no bug bounty for Ergo, and reports about it don't qualify for a payment.

Kosli does run a paid bug bounty for app.kosli.com, its APIs and www.kosli.com. The scope and rates are at <https://www.kosli.com/vulnerability-disclosure>.

Reports about Ergo are still welcome, and we would rather hear about a problem than not.
