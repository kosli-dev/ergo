---
ergo_spec: v0.2
---

# Cake batches

## Subjects

### batch

- from: `batches`

## Requirements

### Cake batch

- subject: `batch`

Checks:

- **Temp ok**:
  - Oven: `bake.temp_c is between 175 and 200`
  - **Probe**: The probe reads it `probe.temp_c is between 175 and 200`
  - **Guess**:
