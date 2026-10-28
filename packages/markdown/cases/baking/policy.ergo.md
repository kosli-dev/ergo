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

- **Nut free**: Must not contain nut allergens
  `allergens does not contain "nuts"`
- **Temp ok**: Bake temperature 175–200°C inclusive
  `bake.temp_c is between 175 and 200`
- **Time ok**: Bake time 25–40 minutes inclusive
  `bake.minutes is between 25 and 40`
