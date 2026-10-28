---
ergo_spec: v0.3-dev
---

# Cake batches

## Subjects

### batch

- From `batches`
- Identified by `id`

Checks:

- **Nut free**: `allergens does not contain "nuts"`

## Requirements

### Cake batch

- Subject `batch`

Checks:

- **Temp ok**: `bake.temp_c is between 175 and 200`
