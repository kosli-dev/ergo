# ergo-policy-sentences-wasm

Reads Ergo's sentences in a browser or in Node, without the engine. It wraps [`ergo-policy-sentences`](../sentences/README.md), and only strings cross the boundary: a line goes in, JSON text comes out.

- `parseCheck(line)`, `parseFor(line)`, `parseFrom(line)` and `parsePath(line)` return `{"tree": ...}`, or `{"errors": [{"column": ..., "message": ...}]}` when the line doesn't read. `column` is `null` when the message names none.
- `checkProblems(tree, aliases)` and `forProblems(tree, aliases)` return `{"problems": [...]}` for a tree you give as JSON text. `aliases` is a JSON array of names.
- `fromProblems(tree)` does the same for a `from` line.
- `printCheck(tree, aliases)` and `printFor(tree, aliases)` write a tree back as a line, and `printFrom(tree, aliases, parents)` does it for a `from` line.

The problem and print functions throw an `Error` when the tree, the aliases or the parents aren't valid JSON, like `the tree isn't valid JSON: ...`. Every function throws a `TypeError` that names the argument when one isn't a string, like `line must be a string, not number`.

```js
import { readFileSync } from "node:fs";
import { initSync, parseCheck, printCheck } from "./pkg/ergo_policy_sentences_wasm.js";

initSync({ module: readFileSync("./pkg/ergo_policy_sentences_wasm_bg.wasm") });
console.log(parseCheck('x is "a'));
const { tree } = JSON.parse(parseCheck("approvals is at least 2"));
console.log(printCheck(JSON.stringify(tree), "[]"));
```

It prints:

```text
{"errors":[{"column":6,"message":"unclosed quote at column 6"}]}
approvals is at least 2
```

The shape of the tree's JSON has no stability promise yet.

To build it, see [Building for a browser](../README.md#building-for-a-browser).
