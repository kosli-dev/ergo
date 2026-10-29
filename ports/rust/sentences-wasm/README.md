# ergo-sentences-wasm

Reads Ergo's sentences in a browser or in Node, without the engine. It wraps [`ergo-sentences`](../sentences/README.md), and only strings cross the boundary: a line goes in, JSON text comes out.

- `parse_check(line)`, `parse_for(line)`, `parse_from(line)` and `parse_path(line)` return `{"tree": ...}`, or `{"errors": [{"column": ..., "message": ...}]}` when the line doesn't read. `column` is `null` when the message names none.
- `check_problems(tree, aliases)` and `for_problems(tree, aliases)` return `{"problems": [...]}` for a tree you give as JSON text. `aliases` is a JSON array of names.
- `from_problems(tree)` does the same for a `from` line.
- `print_check(tree, aliases)` and `print_for(tree, aliases)` write a tree back as a line, and `print_from(tree, aliases, parents)` does it for a `from` line.

The problem and print functions throw an `Error` when the tree, the aliases or the parents aren't valid JSON, like `the tree isn't valid JSON: ...`.

```js
import { readFileSync } from "node:fs";
import { initSync, parse_check, print_check } from "./pkg/ergo_sentences_wasm.js";

initSync({ module: readFileSync("./pkg/ergo_sentences_wasm_bg.wasm") });
console.log(parse_check('x is "a'));
const { tree } = JSON.parse(parse_check("approvals is at least 2"));
console.log(print_check(JSON.stringify(tree), "[]"));
```

It prints:

```text
{"errors":[{"column":6,"message":"unclosed quote at column 6"}]}
approvals is at least 2
```

The shape of the tree's JSON has no stability promise yet.

To build it, see [Building for a browser](../README.md#building-for-a-browser).
