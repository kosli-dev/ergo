---
ergo_spec: v0.4-dev
---

# Cake batches

## Subjects

### batch

- From `batches`

## Requirements

### Cake batch

- Subject `batch`

Checks:

- **Temp ok**:
  - Oven: `bake.temp_c is between 175 and 200`
  - **Probe**: The probe reads it `probe.temp_c is between 175 and 200`
  - **Guess**:
