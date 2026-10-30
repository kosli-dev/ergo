---
ergo_spec: v0.3
---

# Cake batches

## Subjects

### batch

- From `batches`
- Identified by `id`

## Requirements

### Cake batch

- Subject `batch`

Checks:

- **Nut free**: `allergens does not contain "nuts"`

### Baked right

- Subject `batch`

Check:

- **Temp ok**: `bake.temp_c is between 175 and 200`
- **Time ok**: `bake.minutes is between 25 and 40`
