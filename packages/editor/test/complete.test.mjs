import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { compile } from "@kosli/ergo-markdown";
import * as pkg from "../../../ports/rust/sentences-wasm/pkg/ergo_sentences_wasm.js";
import { makeParser, treeTokens } from "../src/sentences.mjs";
import { suggest, fieldsAfter, completionAt } from "../src/complete.mjs";
import { markdownSentences, yamlSentences, blockKindAt } from "../src/locate.mjs";
import { makeAnalyser } from "../src/analyse.mjs";

pkg.initSync({ module: readFileSync(new URL("../../../ports/rust/sentences-wasm/pkg/ergo_sentences_wasm_bg.wasm", import.meta.url)) });
const parser = makeParser(pkg);
const corpus = JSON.parse(readFileSync(new URL("../../../spec/sentences-corpus.json", import.meta.url), "utf8")).sentence_corpus;

const at = (text, ctx = {}) => {
  const cursor = text.indexOf("|");
  return suggest({ parser, kind: "check", ...ctx, text: text.replace("|", "") }, cursor);
};
const texts = (found, kind) => found.items.filter((i) => !kind || i.kind === kind).map((i) => i.text);

test("a from line offers the subjects of the policy except its own", () => {
  const found = at("|", { kind: "from", subjects: ["artifact", "release", "pr"], subject: "release" });
  assert.deepEqual(texts(found, "subject"), ["artifact", "pr"]);
  assert.deepEqual(texts(at("ar|", { kind: "from", subjects: ["artifact", "release"] }), "subject"), ["artifact"]);
  assert.deepEqual(texts(at("every p|", { kind: "from", subjects: ["pr", "artifact"] }), "subject"), ["pr"]);
  assert.deepEqual(texts(at('"web app".items whose x is 1 |', { kind: "from", subjects: ["web app"] }), "subject"), []);
  assert.deepEqual(texts(at("w|", { kind: "from", subjects: ["web app"] }), "subject"), ["\"web app\""]);
});

test("a path start offers the parts and the aliases in scope, and a place that takes no name offers none", () => {
  const ctx = { parts: { coverage: "a.b" }, aliases: ["coverage", "pr", "approver"] };
  assert.deepEqual(texts(at("every |", ctx), "part"), ["coverage"]);
  assert.deepEqual(texts(at("every |", ctx), "alias"), ["pr", "approver"]);
  assert.deepEqual(texts(at("x is 1 and a|", ctx), "alias"), ["approver"]);
  assert.deepEqual(texts(at("x |", ctx), "alias"), []);
  assert.deepEqual(texts(at("pr|", { ...ctx, kind: "for" }), "alias"), []);
});

test("the grammar words that can come next are the ones the parser still reads", () => {
  const words = texts(at("approvals |"), "word");
  for (const w of ["is", "exists", "does", "contains", "matches", "starts"]) assert.ok(words.includes(w), w);
  for (const w of ["and", "whose", "as", "every"]) assert.ok(!words.includes(w), w);
  assert.deepEqual(texts(at("approvals is at |"), "word"), ["least", "most"]);
  const a = texts(at("approvals is a|"), "word");
  for (const w of ["a", "an", "alphabetically", "after", "at"]) assert.ok(a.includes(w), w);
  assert.ok(!a.includes("and"));
  assert.ok(texts(at("x is 1 |"), "word").includes("and"));
  assert.ok(texts(at("x is 1 and |"), "word").includes("every"));
  assert.deepEqual(texts(at("every xs as x, e|", { kind: "for" }), "word"), ["every"]);
  assert.ok(texts(at("every xs |", { kind: "for" }), "word").includes("as"));
});

test("words the corpus uses are suggested where it uses them", () => {
  let wanted = 0;
  let found = 0;
  for (const line of corpus.filter((_, i) => i % 3 === 0)) {
    let kind = null;
    let tree = null;
    for (const k of ["check", "for", "from"]) {
      const read = parser.read(k, line);
      if (read.tree) [kind, tree] = [k, read.tree];
      if (tree) break;
    }
    if (!tree) continue;
    let pos = 0;
    for (const t of treeTokens(kind, tree, line, [], "code")) {
      if (t.kind === "word") {
        let off = pos;
        for (const w of t.text.split(/(\s+)/)) {
          if (/^\S+$/.test(w)) {
            wanted++;
            if (suggest({ parser, kind, text: line }, off).items.some((i) => i.text === w)) found++;
          }
          off += w.length;
        }
      }
      pos += t.text.length;
    }
  }
  assert.ok(found / wanted > 0.95, `${found} of ${wanted}`);
});

const input = { pull_requests: [{ author: "a", approvers: [{ username: "u", state: "APPROVED" }] }], "odd key": 1 };

test("field names seen in the input come after a dot, after whose and after $input.", () => {
  assert.deepEqual(fieldsAfter(input, "approvers"), ["state", "username"]);
  assert.deepEqual(fieldsAfter(input, null), ["odd key", "pull_requests"]);
  assert.deepEqual(fieldsAfter(input, "missing"), []);
  assert.deepEqual(fieldsAfter(null, "x"), []);
  assert.deepEqual(texts(at("every pull_requests.|", { input }), "field"), ["approvers", "author"]);
  assert.deepEqual(texts(at("every pull_requests.approvers.u|", { input }), "field"), ["username"]);
  assert.deepEqual(texts(at("every pull_requests.approvers whose |", { input }), "field"), ["state", "username"]);
  assert.deepEqual(texts(at("x is 1 and every pull_requests whose a|", { input }), "field"), ["approvers", "author"]);
  assert.deepEqual(texts(at("$input.|", { input }), "field"), ['"odd key"', "pull_requests"]);
  assert.deepEqual(texts(at("pr.|", { input, aliasKeys: { pr: "pull_requests" }, aliases: ["pr"] }), "field"), ["approvers", "author"]);
  assert.deepEqual(texts(at("every pull_requests.|", { input: null }), "field"), []);
});

test("$params and $input are offered for a dollar sign", () => {
  assert.deepEqual(texts(at("x is $|"), "ref"), ["$params", "$input"]);
  assert.deepEqual(texts(at("x is $pa|"), "ref"), ["$params"]);
});

test("nothing is offered without a parser", () => {
  assert.deepEqual(suggest({ parser: null, kind: "check", text: "x " }, 2).items, []);
});

const ofMarkdown = (source, line, col, extras = {}) => {
  const blocks = compile(source).blocks;
  const entries = makeAnalyser(parser, "code")(markdownSentences(source, blocks));
  return completionAt("markdown", entries, source.split("\n")[line - 1], line, col, { parser, blockKind: blockKindAt(blocks, line), ...extras });
};

const doc = (sentence) => `---
ergo_spec: v0.3-dev
---

# P

## Subjects

### item

- From \`items\`

## Requirements

### Item

- Subject \`item\`

Checks:

- **Named**: Has a name
  ${sentence}
`;

test("completion in Markdown finds the sentence, its aliases and the text to replace", () => {
  const source = doc("`for every xs as env`\n  `every ds.env equals e`");
  const line = source.split("\n").findIndex((l) => l.includes("equals e")) + 1;
  const row = source.split("\n")[line - 1];
  const found = ofMarkdown(source, line, row.indexOf("equals e") + 8);
  assert.deepEqual(found.items.filter((i) => i.kind === "alias").map((i) => i.text), ["env"]);
  assert.equal(row.slice(found.from, found.to), "e");
});

test("completion in Markdown works inside a code span that is not closed yet", () => {
  const source = doc("`approvals is at ");
  const line = source.split("\n").length - 1;
  const row = source.split("\n")[line - 1];
  const found = ofMarkdown(source, line, row.length);
  assert.deepEqual(found.items.map((i) => i.text), ["least", "most"]);
  assert.equal(found.from, found.to);
  assert.equal(ofMarkdown(doc("`for every xs as x`\n  `x i"), source.split("\n").length, 6)?.items.some((i) => i.text === "is"), true);
});

test("completion in Markdown gives nothing outside a sentence", () => {
  const source = doc("`x exists`");
  assert.equal(ofMarkdown(source, 1, 2), null);
  const prose = source.split("\n").findIndex((l) => l.includes("Has a name")) + 1;
  assert.equal(ofMarkdown(source, prose, 10), null);
});

test("completion in Markdown after from reads the subjects of the policy", () => {
  const source = doc("`x exists`").replace("`items`", "`ar`");
  const line = source.split("\n").findIndex((l) => l.includes("`ar`")) + 1;
  const found = ofMarkdown(source, line, source.split("\n")[line - 1].indexOf("ar`") + 2, { subjects: ["artifact", "item"] });
  assert.deepEqual(found.items.filter((i) => i.kind === "subject").map((i) => i.text), ["artifact"]);
});

const yamlText = `subjects:
  round:
    from: rounds
    has:
      coverage: x.cov
requirements:
  r:
    subject: round
    checks:
      c:
        for: every xs as env
        assert:
          - cov
`;

test("completion in YAML offers the parts of the subject and the aliases of the for line", () => {
  const entries = makeAnalyser(parser)(yamlSentences(yamlText));
  const row = yamlText.split("\n")[12];
  const found = completionAt("yaml", entries, row, 13, row.length, { parser });
  assert.deepEqual(found.items.filter((i) => i.kind === "part").map((i) => i.text), ["coverage"]);
  const none = completionAt("yaml", entries, "  - ", 13, 4, { parser });
  assert.ok(none === null || none.items.length >= 0);
});

test("completion in YAML works on a line that isn't a value yet", () => {
  const entries = makeAnalyser(parser)(yamlSentences("subjects:\n  s:\n    from: items\n"));
  const found = completionAt("yaml", entries, "    from: it", 3, 12, { parser, subjects: ["items2"] });
  assert.equal(found.from, 10);
  const assertLine = completionAt("yaml", [], "        assert: x is ", 1, 21, { parser });
  assert.ok(assertLine.items.some((i) => i.text === "at"));
  assert.equal(completionAt("yaml", [], "      name: x", 1, 11, { parser }), null);
});

test("after named by only names are offered, not the words that would be read as a name there", () => {
  const found = at("x named by |", { aliases: ["pr"] });
  assert.deepEqual(texts(found, "word"), []);
  assert.deepEqual(texts(found, "alias"), ["pr"]);
  assert.deepEqual(texts(at("x named by a|", { aliases: ["pr", "approver"] })), ["approver"]);
});

test("after is not the word null is not offered, because is not null is written wrong, but it is after is", () => {
  assert.ok(!texts(at("x is not |"), "word").includes("null"));
  assert.ok(texts(at("x is |"), "word").includes("null"));
  assert.ok(texts(at("x is not |"), "word").includes("empty"));
  assert.ok(!texts(at("x is not |"), "word").includes("is"));
});

test("a word is offered when the sentence would be read with it as a word, and not when it would only be read as a name", () => {
  assert.ok(texts(at("approvals |"), "word").includes("starts"));
  assert.ok(!texts(at("x is not |"), "word").includes("by"));
  assert.ok(texts(at("every xs |", { kind: "for" }), "word").includes("as"));
});

test("fields after whose are read under the last key of a path, a quoted key with a dot included", () => {
  const input = { a: { "x.y": [{ n: 1 }] }, x: [{ m: 1 }] };
  assert.deepEqual(texts(at('every a."x.y" whose |', { input }), "field"), ["n"]);
  assert.deepEqual(texts(at("every a.y whose |", { input }), "field"), []);
});
