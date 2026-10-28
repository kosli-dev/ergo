---
ergo_spec: v0.2
---

# Cake batches

Every batch that leaves the bakery is safe to eat and baked right.

This paragraph is for people. So is the table below.

| Owner    | Reviewed   |
| -------- | ---------- |
| Bakery   | 2026-10-01 |

## Subjects

### batch

A batch of cakes baked today.

- from: `batches`
- identified by: `id`

> The oven writes one batch per tray.

#### Where batches come from

The oven log, exported every evening:

```json
{"batches": [{"id": "b-1"}]}
```

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

A second paragraph after the description stays prose.

- subject: `batch`

Checks:

- **Nut free**: Must not contain *nut* allergens.
  `allergens does not contain "nuts"`

We check the oven log rather than the recipe, because the recipe is what we
meant to do and the log is what happened.

1. A numbered list after the checks is prose.
2. So is this item.
