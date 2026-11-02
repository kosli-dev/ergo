# Security policy

## Supported versions

Ergo is before 1.0, and only the latest release of each thing we ship gets fixes:

- `ergo.rego`, released as `rego-v*` tags
- the spec, released as `spec-v*` tags
- the Rust crates and the `ergo` command, released as `rust-v*` tags

If you find a problem in an older release, check the latest one first.

## Reporting a vulnerability

Report it privately through GitHub: [open a security advisory](https://github.com/kosli-dev/ergo/security/advisories/new). Please don't use a public issue or pull request, because this repository is public and anything posted there is seen by everyone at once.

Say what the problem is, give the smallest policy and input that show it, and say what you think it lets someone do. A check that passes when it should fail counts, so include it too.

We will reply, tell you what we decided and why, fix what needs fixing, and credit you in the release notes if you want us to. Please give us reasonable time to ship a fix before you say anything in public.
