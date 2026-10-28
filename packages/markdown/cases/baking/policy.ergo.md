---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- From `batches`
- Identified by `id`

## Requirements

### cake_batch

- Subject `batch`

Checks:

- **nut_free**: Must not contain nut allergens
  `allergens does not contain "nuts"`
- **temp_ok**: Bake temperature 175–200°C inclusive
  `bake.temp_c is between 175 and 200`
- **time_ok**: Bake time 25–40 minutes inclusive
  `bake.minutes is between 25 and 40`
