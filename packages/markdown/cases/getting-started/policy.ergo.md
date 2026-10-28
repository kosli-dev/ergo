---
ergo_spec: v0.2
---

# Production deployments

## Subjects

### deployment

- from: `deployments whose environment is "prod"`
- identified by: `id`

## Requirements

### Prod deploy

Every production deployment is approved

- subject: `deployment`

Checks:

- **Approved**: Someone approved the deployment
  `approved_by is a non-empty string`
