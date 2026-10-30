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

- **Baked right**: Baked at 175–200°C for 25–40 minutes.

  The oven logs the temperature and the time of every batch, so a batch
  without them fails.

  `bake.temp_c is between 175 and 200`
  `bake.minutes is between 25 and 40`
- **Nut free**: Must not contain nut allergens.

  Nuts are the allergen customers ask about most.
  `allergens does not contain "nuts"`
