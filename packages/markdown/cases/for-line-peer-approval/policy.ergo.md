---
ergo_spec: v0.2
---

# Releases

## Subjects

### release

- from: `releases`
- identified by: `id`

## Requirements

### Release

- subject: `release`

Checks:

- **Signed**: Every commit is signed
  `every pull_requests.commits.signed is true`
- **Peer approved**: Someone other than the author approved every pull request
  `for every pull_requests as pr, some pr.approvers as approver`
  `approver.state is "APPROVED"`
  `approver.username does not equal pr.author`
