---
ergo_spec: v0.2
---

# Production deployments

## Subjects

### deployment

- From `deployments whose environment is "prod"`
- Identified by `id`

## Requirements

### Prod deploy

Every production deployment is approved

- Subject `deployment`

Checks:

- **Approved**: Someone approved the deployment
  `approved_by is a non-empty string`
