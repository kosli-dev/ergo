---
ergo_spec: v0.2
---

# Cake batches

Every batch that leaves the bakery is safe to eat.

The bakery's allergy promise covers nuts. Other allergens have their own
policy.

## Subjects

### Batch

A batch of cakes baked today.

One batch is one tray, as the oven logs it.

- from: `batches`
- identified by: `id`

## Requirements

### Cake batch

Cakes are safe to eat.

A customer with a nut allergy relies on this. A batch that can't show its
allergens fails.

- subject: `batch`

Checks:

- **Nut free**: Must not contain nut allergens.
  `allergens does not contain "nuts"`

We check the allergen list the oven writes, not the recipe.
