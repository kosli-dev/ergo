# Ergo policy editor

A web page for writing an Ergo policy in Markdown. It's an experiment, not published.

```sh
cd packages
pnpm install
pnpm --filter @kosli/ergo-editor build
open editor/dist/editor.html
```

The build needs `opa` on your PATH, because it compiles `ergo.rego` to Wasm for the Report view. It prints the OPA version it used, and warns when that isn't the one the README tests with.

The page is one file with nothing to fetch. The Markdown is coloured by kind of block, with headings, labels and the words, strings, numbers and `$params` or `$input` of each sentence and each subject's from line picked out. The grammar words are the ones `spec/sentences.abnf` spells out. Each of the two panes can show any view, picked from its tabs, and picking a view the other pane shows swaps them. The page starts with the Markdown on the left and the blocks on the right, and remembers the panes you pick. Besides the Markdown, the views are:

- **Blocks**: what the compiler read from each part of the source, next to the lines it came from.
- **Policy**: each requirement and its checks, with each check's description and its sentences as written.
- **Document**: the Markdown as a reader sees it, with a coloured edge on the parts Ergo acts on.
- **YAML**: the compiled policy, with its sentences picked out the same way and a button to copy it. You can edit it: when the YAML reads as a policy, the Markdown is rewritten where that policy changed and nowhere else. When the Markdown can't say it, or the YAML doesn't parse, the problems show under the YAML and the Markdown stays as it was. Pasting a YAML policy into an empty document writes a new one.
- **Report**: `ergo.report` run in the page on the input and params you paste in.

The samples are cases from `packages/markdown/cases`, with their input and params. Your edits to a sample are kept in the browser until the sample itself changes, or you press reset.
