---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- from: `batches`
- identified by: `id`

Checks:

- **Nut free**: `allergens does not contain "nuts"`

## Requirements

### Cake batch

- subject: `batch`

Checks:

- **Temp ok**: `bake.temp_c is between 175 and 200`
