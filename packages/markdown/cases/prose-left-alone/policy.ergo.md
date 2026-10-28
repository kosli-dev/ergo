---
ergo_spec: v0.3-dev
---

# Cake batches

Every batch that leaves the bakery is safe to eat and baked right.

| Owner    | Reviewed   |
| -------- | ---------- |
| Bakery   | 2026-10-01 |

This paragraph comes after the table, so it's for people, like the table.

## Subjects

### batch

A batch of cakes baked today.

- From `batches`
- Identified by `id`

> The oven writes one batch per tray.

#### Where batches come from

The oven log, exported every evening:

```json
{"batches": [{"id": "b-1"}]}
```

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- Subject `batch`

A paragraph after the fields stays prose.

Checks:

- **Nut free**: Must not contain *nut* allergens.
  `allergens does not contain "nuts"`

We check the oven log rather than the recipe, because the recipe is what we
meant to do and the log is what happened.

1. A numbered list after the checks is prose.
2. So is this item.
