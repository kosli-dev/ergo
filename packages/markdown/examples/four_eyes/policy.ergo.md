# Four eyes

Every commit that reaches a protected branch must be approved by someone who
didn't write it.

The rule is per author, not per pull request. For each person who wrote part of
a pull request, someone other than them must approve it after its latest commit.
So two developers who review each other's work both pass.

## Subjects

A **commit** is each of `trails`, identified by its `name`.

| Property                | Path                                                                                                |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| name                    | `name`                                                                                              |
| PR attestation          | `compliance_status.attestations_statuses[attestation_type=pull_request]`                            |
| pull requests           | `compliance_status.attestations_statuses[attestation_type=pull_request].pull_requests`              |
| initial-commit evidence | `compliance_status.attestations_statuses[attestation_type=custom:initial-commit].is_compliant`      |

The pull request attestation is picked by its type, not its name, because the
name is whatever the flow calls it.

## Constants

**Web-flow authors** are authors matching any of:

- `^.*?\[bot\] <[^>]+>$`
- `^GitHub <noreply@github.com>$`

These are commits no person wrote: bots, and edits made in GitHub's web
interface. There's no account to link them to.

## Substitutes

- `initial_commit` — the **initial-commit evidence** must be `true`.
  A compliant initial-commit attestation stands in for the pull request a first commit can't have.

A repository's first commit has no parent, so it can never have a pull request.
Without this substitute, it would fail every check below.

## The trail covers a commit `commits_present`

At least one **commit** must be in scope.

Must hold:

- `commit_identified` — the **name** must be a non-empty string.
  The trail names the commit it covers.

## The commit was reviewed `commit_reviewed`

No minimum: `commits_present` already fails when there are no commits, and
failing here too would report the same problem twice.

Must hold:

- `pr_attestation_present` — the **PR attestation** must be present,
  or else `initial_commit`.
  Pull request review data was collected for this commit.

- `pull_request_found` — at least one **pull request** must exist,
  or else `initial_commit`.
  Records the **pull requests**' `url`.
  The commit is associated with at least one pull request.

- `identities_resolved` — some **pull request** must have its identities
  resolved, treating **web-flow authors** as explained, or else `initial_commit`.
  Some pull request has every commit linked to a GitHub account or explained as a web-flow commit, or else has every one of its approvers resolved.

- `independently_approved` — some **pull request** must be independently
  approved, treating **web-flow authors** as explained, or else `initial_commit`.
  Some pull request has an approval from someone other than each of its authors, after its latest commit.

The last two use custom operators. They compare fields across two lists inside
one pull request, which no built-in operator can do. `four_eyes_ops.rego` defines
them, and `custom_ops.json` tells `ergo` how to describe them.
