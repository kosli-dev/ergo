---
ergo_spec: v0.4-dev
---

# Component licences

Every component we ship has a licence we allow.

It reads two params: `allowed_licenses`, the licences we allow, and
`known_package_licenses`, the licence of each package whose SBOM doesn't
declare one, by package name.

## Subjects

### component

- From `components`
- Identified by `name`

## Requirements

### Licences

- Subject `component`

Checks:

- **Licence allowed**: The licence is allowed
  - **Declared**: `some licenses.license.id is in $params.allowed_licenses`
  - **Known**:
    `licenses does not exist`
    `$params.known_package_licenses named by name is in $params.allowed_licenses`
