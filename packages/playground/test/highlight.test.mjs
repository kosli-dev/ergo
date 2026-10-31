import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { compile } from "@kosli/ergo-markdown";
import { GRAMMAR_WORDS, sentenceTokens, highlightMarkdown, highlightYaml } from "../src/highlight.mjs";
import { yamlText } from "../src/lib.mjs";
import { sampleCases, readSample } from "../build.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const tokens = (kind, text) => ({ kind, text });
const kindsOf = (line) => line.map((t) => (t.kind === "plain" ? t.text : `[${t.kind}:${t.text}]`)).join("");
const markdown = (source) => highlightMarkdown(source, compile(source).blocks).map(kindsOf);
const yaml = (text) => highlightYaml(text).map(kindsOf);

test("the grammar words are the words spec/sentences.abnf spells out", () => {
  const abnf = readFileSync(join(here, "..", "..", "..", "spec", "sentences.abnf"), "utf8");
  const words = new Set([...abnf.matchAll(/"([a-z][a-z-]*)"/g)].map((m) => m[1]).filter((w) => w.length > 1 || w === "a"));
  assert.deepEqual([...GRAMMAR_WORDS].sort(), [...words].sort());
});

test("a sentence marks its grammar words, strings and numbers", () => {
  assert.deepEqual(sentenceTokens('allergens does not contain "nuts"'), [
    tokens("plain", "allergens "),
    tokens("word", "does"),
    tokens("plain", " "),
    tokens("word", "not"),
    tokens("plain", " "),
    tokens("word", "contain"),
    tokens("plain", " "),
    tokens("string", '"nuts"'),
  ]);
  assert.deepEqual(sentenceTokens("bake.temp_c is between 175 and 200.5").filter((t) => t.kind === "number"), [
    tokens("number", "175"),
    tokens("number", "200.5"),
  ]);
});

test("a sentence marks $params and $input with the path after them", () => {
  assert.deepEqual(sentenceTokens("name is in $params.allowed_names").at(-1), tokens("ref", "$params.allowed_names"));
  assert.deepEqual(sentenceTokens("$input.tag exists")[0], tokens("ref", "$input.tag"));
});

test("a field named like a grammar word is not marked as one", () => {
  assert.deepEqual(sentenceTokens("bake.is is true").map((t) => t.kind), ["plain", "word", "plain", "word"]);
  assert.deepEqual(sentenceTokens(".is is true")[0], tokens("plain", ".is "));
});

test("a string keeps its escaped quotes", () => {
  assert.deepEqual(sentenceTokens('name is "say \\"hi\\""').at(-1), tokens("string", '"say \\"hi\\""'));
});

test("a digit inside a name is not a number", () => {
  assert.ok(sentenceTokens("step2 is true").every((t) => t.kind !== "number"));
});

test("the Markdown pane marks front matter, headings, field labels, check labels and sentences", () => {
  const source = readSample("baking").source;
  assert.deepEqual(markdown(source).slice(0, 12), [
    "[marker:---]",
    "[key:ergo_spec]:[string: v0.3]",
    "[marker:---]",
    "",
    "[marker:#] [heading:Cake batches]",
    "",
    "[marker:##] [heading:Subjects]",
    "",
    "[marker:###] [heading:batch]",
    "",
    "[marker:-] [key:From] [marker:`][code:batches][marker:`]",
    "[marker:-] [key:Identified by] [marker:`][code:id][marker:`]",
  ]);
  const lines = markdown(source);
  assert.equal(lines[19], "[key:Checks:]");
  assert.equal(lines[21], "[marker:-] [bold:**nut_free**]: Must not contain nut allergens");
  assert.equal(lines[22], '  [marker:`][code:allergens ][word:does][code: ][word:not][code: ][word:contain][code: ][string:"nuts"][marker:`]');
});

test("a field written with a colon marks the label and its colon", () => {
  const lines = markdown("# T\n\n## Subjects\n\n### build\n\n- from: `builds`\n- identified by: `id`\n");
  assert.equal(lines[6], "[marker:-] [key:from:] [marker:`][code:builds][marker:`]");
});

test("the Markdown pane marks the for that starts a for line", () => {
  const lines = markdown(readSample("for-line-peer-approval").source);
  assert.equal(lines[24], "  [marker:`][word:for][code: ][word:every][code: pull_requests ][word:as][code: pr, ][word:some][code: pr.approvers ][word:as][code: approver][marker:`]");
});

test("a field called for inside a sentence is not the for of a for line", () => {
  assert.equal(markdown("# T\n\n## Requirements\n\n### R\n\n- Subject `x`\n\nChecks:\n\n- **C**: c\n  `for.x is 1`\n")[11], "  [marker:`][code:for.x ][word:is][code: ][number:1][marker:`]");
});

test("the Markdown pane reads the From field of a subject as a sentence, and the other fields as names", () => {
  const lines = markdown(readSample("getting-started").source);
  assert.equal(lines[10], '[marker:-] [key:From] [marker:`][code:deployments ][word:whose][code: environment ][word:is][code: ][string:"prod"][marker:`]');
  assert.equal(lines[11], "[marker:-] [key:Identified by] [marker:`][code:id][marker:`]");
  assert.equal(lines[19], "[marker:-] [key:Subject] [marker:`][code:deployment][marker:`]");
});

test("the YAML view reads a subject's from as a sentence, and identified_by, subject and parts as names", () => {
  const text = "subjects:\n  a:\n    from: $params.list named by every id\n    identified_by: some.id\n    has:\n      every_one: is.in\nrequirements:\n  r:\n    subject: some\n";
  assert.deepEqual(yaml(text), [
    "[key:subjects]:",
    "  [key:a]:",
    "    [key:from]: [ref:$params.list] [word:named] [word:by] [word:every] id",
    "    [key:identified_by]: [string:some.id]",
    "    [key:has]:",
    "      [key:every_one]: [string:is.in]",
    "[key:requirements]:",
    "  [key:r]:",
    "    [key:subject]: [string:some]",
    "",
  ]);
});

test("the YAML view reads a key with spaces, quoted or not", () => {
  const text = "requirements:\n  cake batch:\n    checks:\n      \"nut: free\":\n        assert: it is 1\n      'it''s ok':\n        assert: it is 2\n";
  assert.deepEqual(yaml(text).slice(1, 7), [
    "  [key:cake batch]:",
    "    [key:checks]:",
    '      [key:"nut: free"]:',
    "        [key:assert]: [word:it] [word:is] [number:1]",
    "      [key:'it''s ok']:",
    "        [key:assert]: [word:it] [word:is] [number:2]",
  ]);
});

test("a code span outside a check is not read as a sentence", () => {
  const lines = markdown("# T\n\nThe value `is in` stays plain.\n");
  assert.equal(lines[2], "The value [marker:`][code:is in][marker:`] stays plain.");
});

test("a backtick with no partner stays plain", () => {
  assert.deepEqual(highlightMarkdown("a ` b", []), [[tokens("plain", "a ` b")]]);
});

test("a code span closes only on a run of the same number of backticks", () => {
  assert.deepEqual(highlightMarkdown("``a ` b``", [])[0], [tokens("marker", "``"), tokens("code", "a ` b"), tokens("marker", "``")]);
});

test("lines inside a fenced code block are code", () => {
  assert.deepEqual(markdown("```\n# not a heading\n```\n"), ["[code:```]", "[code:# not a heading]", "[code:```]", ""]);
});

test("the YAML view marks keys, plain values and the sentences of a check", () => {
  const lines = yaml(yamlText(compile(readSample("any-of-licences").source).policy));
  assert.ok(lines.includes("[key:ergo_spec]: [string:v0.3]"));
  assert.ok(lines.includes("      [key:licence allowed]:"));
  assert.ok(lines.includes("        [key:description]: [string:The licence is allowed]"));
  assert.ok(lines.includes("          [key:declared]: [word:some] licenses.license.id [word:is] [word:in] [ref:$params.allowed_licenses]"));
  assert.ok(lines.includes("            [marker:- ]licenses [word:does] [word:not] [word:exist]"));
});

test("the YAML view marks a for line and the sentences listed under assert", () => {
  const text = "requirements:\n  r:\n    checks:\n      c:\n        for: every items as item\n        assert:\n          - item.count is 2\n";
  assert.deepEqual(yaml(text).slice(4, 7), [
    "        [key:for]: [word:every] items [word:as] [word:item]",
    "        [key:assert]:",
    "          [marker:- ][word:item].count [word:is] [number:2]",
  ]);
});

test("the YAML view reads a description that spans lines as text, not as a sentence", () => {
  assert.deepEqual(yaml("description: |-\n  It is in.\n\n  Every one.\nsubjects: {}"), [
    "[key:description]:[marker: |-]",
    "  [string:It is in.]",
    "",
    "  [string:Every one.]",
    "[key:subjects]: [string:{}]",
  ]);
});

test("the YAML view reads a check named assert as a name", () => {
  const lines = yaml("requirements:\n  r:\n    checks:\n      assert:\n        description: it is fine\n");
  assert.equal(lines[3], "      [key:assert]:");
  assert.equal(lines[4], "        [key:description]: [string:it is fine]");
});

test("the YAML view marks numbers and booleans", () => {
  assert.deepEqual(yaml("min_subjects: 2\nflag: true"), ["[key:min_subjects]: [number:2]", "[key:flag]: [word:true]"]);
});

for (const [label, dir] of Object.entries(sampleCases)) {
  test(`the ${label} sample's highlighted lines spell out its source and its YAML`, () => {
    const { source } = readSample(dir);
    const result = compile(source);
    const back = (lines) => lines.map((l) => l.map((t) => t.text).join("")).join("\n");
    assert.equal(back(highlightMarkdown(source, result.blocks)), source);
    const text = yamlText(result.policy);
    assert.equal(back(highlightYaml(text)), text);
  });
}
