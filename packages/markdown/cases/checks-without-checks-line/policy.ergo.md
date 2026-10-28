---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- from: `batches`
- identified by: `id`

## Requirements

### Cake batch

- subject: `batch`

Checks:

- **Nut free**: `allergens does not contain "nuts"`

### Baked right

- subject: `batch`

Check:

- **Temp ok**: `bake.temp_c is between 175 and 200`
- **Time ok**: `bake.minutes is between 25 and 40`
