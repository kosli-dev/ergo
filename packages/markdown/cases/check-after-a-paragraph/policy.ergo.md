---
ergo_spec: v0.2
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

- **Nut free**: Must not contain nut allergens.
  `allergens does not contain "nuts"`

Nuts are the allergen customers ask about most.

- **Temp ok**: Bake temperature 175–200°C inclusive.
  `bake.temp_c is between 175 and 200`
