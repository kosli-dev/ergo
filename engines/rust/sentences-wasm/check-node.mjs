import { readFileSync } from "node:fs";
import { checkProblems, initSync, parseCheck, printCheck } from "./pkg/ergo_policy_sentences_wasm.js";

initSync({ module: readFileSync(new URL("./pkg/ergo_policy_sentences_wasm_bg.wasm", import.meta.url)) });

const read = JSON.parse(parseCheck("approvals is at least 2"));
if (read.tree === undefined) {
  throw new Error(`the line didn't read: ${JSON.stringify(read)}`);
}
const unread = parseCheck('x is "a');
if (unread !== '{"errors":[{"column":6,"message":"unclosed quote at column 6"}]}') {
  throw new Error(`unexpected syntax error: ${unread}`);
}
const problems = checkProblems(JSON.stringify(read.tree), "[]");
if (problems !== '{"problems":[]}') {
  throw new Error(`unexpected problems: ${problems}`);
}
const printed = printCheck(JSON.stringify(read.tree), "[]");
if (printed !== "approvals is at least 2") {
  throw new Error(`the tree printed back as ${printed}`);
}
let refused;
try {
  printCheck("{", "[]");
} catch (error) {
  refused = error;
}
if (!(refused instanceof Error) || !refused.message.startsWith("the tree isn't valid JSON")) {
  throw new Error(`a tree that isn't JSON wasn't refused: ${refused}`);
}
for (const [call, wanted] of [
  [() => parseCheck(42), "line must be a string, not number"],
  [() => parseCheck(null), "line must be a string, not null"],
  [() => printCheck("{}", undefined), "aliases must be a string, not undefined"],
]) {
  let thrown;
  try {
    call();
  } catch (error) {
    thrown = error;
  }
  if (!(thrown instanceof TypeError) || thrown.message !== wanted) {
    throw new Error(`wanted a TypeError "${wanted}", got ${thrown}`);
  }
}
console.log("ergo-policy-sentences-wasm read a sentence, refused a broken one, listed problems and printed it back");
