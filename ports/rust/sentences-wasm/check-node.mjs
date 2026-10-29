import { readFileSync } from "node:fs";
import { initSync, parse_check } from "./pkg/ergo_sentences_wasm.js";

initSync({ module: readFileSync(new URL("./pkg/ergo_sentences_wasm_bg.wasm", import.meta.url)) });

const read = JSON.parse(parse_check("approvals is at least 2"));
if (read.tree === undefined) {
  throw new Error(`the line didn't read: ${JSON.stringify(read)}`);
}
console.log("ergo-sentences-wasm read a check sentence into a tree");
