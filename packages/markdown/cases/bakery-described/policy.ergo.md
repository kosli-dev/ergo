---
ergo_spec: v0.3-dev
---

# Cake batches

Every batch that leaves the bakery is safe to eat and baked right.

## Subjects

### batch

A batch of cakes baked today.

- From `batches`
- Identified by `id`

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- Subject `batch`

Checks:

- **Nut free**: Must not contain nut allergens.
  `allergens does not contain "nuts"`
- **Baked right**: Baked at 175–200°C for 25–40 minutes.
  `bake.temp_c is between 175 and 200`
  `bake.minutes is between 25 and 40`

We check the oven log rather than the recipe, because the recipe is what we
meant to do and the log is what happened.
