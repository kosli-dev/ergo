import test from "node:test";
import assert from "node:assert/strict";
import { makeParser, treeTokens } from "../src/sentences.mjs";
import { makeAnalyser } from "../src/analyse.mjs";

const releasedShape = (tree) =>
  makeParser({
    parseCheck: () => JSON.stringify({ tree }),
    checkProblems: () => JSON.stringify({ problems: [] }),
  });

const sentence = { kind: "check", text: "x is 1", forText: null, parts: {}, subject: "s", exact: true, start: 0, end: 6, line: 1 };

for (const [name, tree] of [
  ["a tree with no assertions", {}],
  ["a tree whose assertions are of a kind it doesn't know", { assertions: [{ Odd: {} }] }],
  ["a tree that is null", null],
]) {
  test(`a sentence the parser reads as ${name} is shown as written, with no colours and no lines`, () => {
    const entries = makeAnalyser(releasedShape(tree), "code")({ sentences: [sentence], subjects: [] });
    assert.equal(entries[0].tokens, null);
    assert.deepEqual(entries[0].lines, []);
    assert.deepEqual(entries[0].problems, []);
  });
}

test("a missing tree gives no colours", () => {
  assert.equal(treeTokens("check", undefined, "x is 1"), null);
  assert.equal(treeTokens("check", null, "x is 1"), null);
});
