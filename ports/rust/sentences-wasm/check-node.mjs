import { readFileSync } from "node:fs";
import { check_problems, initSync, parse_check, print_check } from "./pkg/ergo_sentences_wasm.js";

initSync({ module: readFileSync(new URL("./pkg/ergo_sentences_wasm_bg.wasm", import.meta.url)) });

const read = JSON.parse(parse_check("approvals is at least 2"));
if (read.tree === undefined) {
  throw new Error(`the line didn't read: ${JSON.stringify(read)}`);
}
const unread = parse_check('x is "a');
if (unread !== '{"errors":[{"column":6,"message":"unclosed quote at column 6"}]}') {
  throw new Error(`unexpected syntax error: ${unread}`);
}
const problems = check_problems(JSON.stringify(read.tree), "[]");
if (problems !== '{"problems":[]}') {
  throw new Error(`unexpected problems: ${problems}`);
}
const printed = print_check(JSON.stringify(read.tree), "[]");
if (printed !== "approvals is at least 2") {
  throw new Error(`the tree printed back as ${printed}`);
}
let refused;
try {
  print_check("{", "[]");
} catch (error) {
  refused = error;
}
if (!(refused instanceof Error) || !refused.message.startsWith("the tree isn't valid JSON")) {
  throw new Error(`a tree that isn't JSON wasn't refused: ${refused}`);
}
for (const [call, wanted] of [
  [() => parse_check(42), "line must be a string, not number"],
  [() => parse_check(null), "line must be a string, not null"],
  [() => print_check("{}", undefined), "aliases must be a string, not undefined"],
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
console.log("ergo-sentences-wasm read a sentence, refused a broken one, listed problems and printed it back");
