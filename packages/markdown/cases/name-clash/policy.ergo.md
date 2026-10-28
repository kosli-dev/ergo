---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- From `batches`

### batch

- From `old_batches`

### cake  batch

- From `cakes`

### cake batch

- From `old_cakes`

## Requirements

### Cake batch

- Subject `batch`

Checks:

- **Nut free**: `allergens does not contain "nuts"`
- **Nut  Free**: `allergens does not contain "peanuts"`
- **Temp ok**:
  - **Oven**: `bake.temp_c is between 175 and 200`
  - **oven**: `bake.temp_f is between 347 and 392`

### Cake  batch

- Subject `batch`

Checks:

- **Time ok**: `bake.minutes is between 25 and 40`
