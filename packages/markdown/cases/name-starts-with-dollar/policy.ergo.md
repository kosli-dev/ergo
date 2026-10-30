---
ergo_spec: v0.3
---

# Cake batches

## Subjects

### $batch

- From `batches`
- Identified by `id`

## Requirements

### $applies

- Subject `$batch`

Checks:

- **$well_formed**: `allergens does not contain "nuts"`
- **Baked right**:
  - **$oven**: `bake.temp_c is between 175 and 200`
  - **Probe**: `probe.temp_c is between 175 and 200`
