---
ergo_spec: v0.2
---

# Names

## Subjects

### pull request

- from: `pull_requests`
- identified by: `number`

## Requirements

### Crème brûlée — the "recipe" check!

- subject: `pull request`

Checks:

- **Approved by 2+ people**: `count of approvers is at least 2`
- **(Optional) review**: `reviewed is true`
- **CI__green**: `ci.status is "green"`
