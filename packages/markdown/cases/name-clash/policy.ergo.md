---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- from: `batches`

### batch

- from: `old_batches`

## Requirements

### Cake batch

- subject: `batch`

Checks:

- **Nut free**: `allergens does not contain "nuts"`
- **Nut-free!**: `allergens does not contain "peanuts"`
- **Temp ok**:
  - **Oven**: `bake.temp_c is between 175 and 200`
  - **oven**: `bake.temp_f is between 347 and 392`

### Cake  batch

- subject: `batch`

Checks:

- **Time ok**: `bake.minutes is between 25 and 40`
