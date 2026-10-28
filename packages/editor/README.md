# Ergo policy editor

A web page for writing an Ergo policy in Markdown. It's an experiment, not published.

```sh
cd packages
pnpm install
pnpm --filter @kosli/ergo-editor build
open editor/dist/editor.html
```

The build needs `opa` on your PATH, because it compiles `ergo.rego` to Wasm for the Report view. It prints the OPA version it used, and warns when that isn't the one the README tests with.

The page is one file with nothing to fetch. On the left is the Markdown. On the right are five views:

- **Blocks**: what the compiler read from each part of the source, next to the lines it came from.
- **Policy**: each requirement and its checks, with each check's description and its sentences as written.
- **Document**: the Markdown as a reader sees it, with a coloured edge on the parts Ergo acts on.
- **YAML**: the compiled policy, with a button to copy it.
- **Report**: `ergo.report` run in the page on the input and params you paste in.

The samples are cases from `packages/markdown/cases`, with their input and params.
