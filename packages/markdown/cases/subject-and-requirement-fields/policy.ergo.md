---
ergo_spec: v0.4-dev
---

# Deployments and their tests

Every deployment to production was approved, and at least one test run passed
before it.

## Subjects

### deployment

A deployment to production.

- from: `deployments whose environment is "prod"`
- identified by: `id`

### test run

- from: `test_runs`

## Requirements

### Approved deployment

Each production deployment has an approver.

- subject: `deployment`
- require: `every`
- min subjects: `0`

Checks:

- **Approved**: Someone approved the deployment
  `approved_by is a non-empty string`

### Some test passed

- subject: `test run`
- require: `some`
- min subjects: `1`

Checks:

- **Passed**: `status is "passed"`
