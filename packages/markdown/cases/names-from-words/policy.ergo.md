---
ergo_spec: v0.3-dev
---

# Names

## Subjects

### pull request

- From `pull_requests`
- Identified by `number`

## Requirements

### Crème brûlée — the "recipe" check!

- Subject `pull request`

Checks:

- **Approved by 2+ people**: `count of approvers is at least 2`
- **(Optional) review**: `reviewed is true`
- **CI__green**: `ci.status is "green"`
