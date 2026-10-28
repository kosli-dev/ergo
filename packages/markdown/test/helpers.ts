import {compile} from "../src/compile.ts";

export const CAKE = `---
ergo_spec: v0.2
---

# Cake batches

Every batch that leaves the bakery is safe to eat and baked right.

## Subjects

### batch

A batch of cakes baked today.

- from: \`batches\`
- identified by: \`id\`

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- subject: \`batch\`

Checks:

- **Nut free**: Must not contain nut allergens.
  \`allergens does not contain "nuts"\`
- **Temp ok**: \`bake.temp_c is between 175 and 200\`
- **Licence allowed**: Every licence is allowed.
  - **Declared**: \`some licenses.license.id is in $params.allowed_licenses\`
  - **Known**:
    \`licenses does not exist\`
    \`$params.known named by name is in $params.allowed_licenses\`
- **Each item**: \`for every items as item\` \`item.ok is true\`
`;

export const CAKE_POLICY = {
  ergo_spec: "v0.2",
  description: "Every batch that leaves the bakery is safe to eat and baked right.",
  subjects: {
    batch: {description: "A batch of cakes baked today.", from: "batches", identified_by: "id"},
  },
  requirements: {
    "cake batch": {
      description: "Cakes are safe to eat and baked right.",
      subject: "batch",
      checks: {
        "nut free": {description: "Must not contain nut allergens.", assert: 'allergens does not contain "nuts"'},
        "temp ok": {assert: "bake.temp_c is between 175 and 200"},
        "licence allowed": {
          description: "Every licence is allowed.",
          any_of: {
            declared: "some licenses.license.id is in $params.allowed_licenses",
            known: ["licenses does not exist", "$params.known named by name is in $params.allowed_licenses"],
          },
        },
        "each item": {for: "every items as item", assert: "item.ok is true"},
      },
    },
  },
};

export const problemsOf = (markdown: string) => compile(markdown).problems;

export const inRequirement = (body: string): string =>
  `## Requirements\n\n### R\n\n${body}\n`;

export const inChecks = (body: string): string => inRequirement(`Checks:\n\n${body}`);
