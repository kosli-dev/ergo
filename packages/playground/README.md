# Ergo playground

A web page for trying Ergo in the browser, called the playground on the website: a policy as YAML beside its report, with Markdown as an experimental way to write the policy. It's an experiment. It's on the website at `/playground/`, and it asks search engines not to index it.

```sh
cd packages
pnpm install
pnpm --filter @kosli/ergo-playground build
open playground/dist/playground.html
```

The build needs `opa` on your PATH, because it compiles `ergo.rego` to Wasm for the Report view. It also needs the Rust engine built to Wasm in `engines/rust/wasm/pkg`, which the Report view can run instead, and the Rust sentence parser built to Wasm in `engines/rust/sentences-wasm/pkg`: see "Building for a browser" in `engines/rust/README.md` for both. It prints the OPA version it used, and warns when that isn't the one the README tests with.

The page is one file with nothing to fetch. The Markdown is coloured by kind of block, with headings, labels and the words, strings, numbers and `$params` or `$input` of each sentence and each subject's from line picked out. The grammar words are the ones `spec/sentences.abnf` spells out. Each of the two panes can show any view, picked from its tabs, and picking a view the other pane shows swaps them. The page starts with the YAML on the left and the report on the right, and remembers the panes you pick. Markdown is an experiment, not a format the rest of Ergo uses, so its tab says so. The views are:

- **YAML**: the compiled policy, with its sentences picked out the same way and a button to copy it. You can edit it: about a second after you stop typing, when you leave the YAML, or when you press Ctrl+Enter (⌘Enter), and the YAML reads as a policy, the Markdown is rewritten where that policy changed and nowhere else. Ctrl+Z (⌘Z) in the Markdown, or the Undo button under the YAML, takes that change back to the exact text before it. When the Markdown can't say it, or the YAML doesn't parse, the problems show under the YAML and the Markdown stays as it was. Pasting a YAML policy into an empty document writes a new one.
- **Report**: the report, from the Rego engine (`ergo.rego`) or the Rust engine (experimental), whichever the engine picker names, run in the page on the input and params you paste in, which can be any JSON. The note under it says how long the engine took to make the report, timing only the engine's own call. Each engine runs once when it loads, so that time doesn't include the browser compiling it. They reach Ergo as written, so a number too big or too precise for JavaScript is checked as written. The page shows such a number rounded, and says so. Each subject has its own row, with its id as JSON, so `1` and `"1"` are two rows.
- **Policy**: each requirement and its checks, with each check's description and its sentences as written.
- **Markdown** (experimental): the policy written as a document, coloured by kind of block.
- **Blocks**: what the compiler read from each part of the source, next to the lines it came from.
- **Document**: the Markdown as a reader sees it, with a coloured edge on the parts Ergo acts on.

The Markdown and YAML views read every sentence as you type, with the Rust sentence parser (`ergo-policy-sentences-wasm`), without a report:

- **Errors**: a check, a `for` line or a `from` line that is written wrong is underlined, at the column the parser names or else the whole sentence, and its message is listed at the bottom of the page. Fixing the line clears it. The playground only underlines problems found in one sentence, with its `for` line and its subject's parts. Problems that need the whole policy, like an alias named like a subject or a loop in the `from` lines, show in the well-formed row of the Report view instead. A `for` line's aliases and a subject's parts count as names in scope for the checks under it.
- **Colours**: the words, names, aliases, `$params` and `$input` references, strings and numbers of a sentence are coloured from what the parser read. The tree has no positions, so the page matches its names and values against the line from left to right. When they don't match, or the parser isn't loaded, the line keeps the colours of the patterns.
- **Hover**: pointing at a sentence says how it is read, in plain words: what `every` and `some` do with an empty list, what a `whose` keeps, and what an alias or a part of the subject stands for.
- **Completion**: it opens as you type a word, after a dot, and with Ctrl+Space. It offers the grammar words that can come next (the page tries each word with the parser), subject names in a `from` line, aliases and parts where a path starts, and the field names found in the input JSON of the Report view after a dot or `whose`. Up and Down choose, Tab or Enter take, Esc closes.

The samples are cases from `packages/markdown/cases`, with their input and params. Your edits to a sample are kept in the browser until the sample itself changes, or you press reset. An edit shows "your edited version" next to the samples. When the sample changed, the page says once that your old edit was dropped. When the browser won't save an edit, the page says "not saved", and a reload gives the sample back rather than an older edit.
