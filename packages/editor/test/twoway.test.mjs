import test from "node:test";
import assert from "node:assert/strict";
import { compile, normalise } from "@kosli/ergo-markdown";
import { editFromYaml, markdownFromPaste, readYaml } from "../src/twoway.mjs";
import { yamlText } from "../src/lib.mjs";
import { readSample } from "../build.mjs";

const bakery = readSample("baking").source;
const bakeryYaml = yamlText(compile(bakery).policy);
const changedLines = (before, after) => {
  const a = before.split("\n");
  const b = after.split("\n");
  assert.equal(a.length, b.length);
  return a.flatMap((line, i) => (line === b[i] ? [] : [i + 1]));
};

test("editing a check's sentence in the YAML rewrites only that check's lines", () => {
  const yaml = bakeryYaml.replace("is between 175 and 200", "is between 170 and 200");
  assert.notEqual(yaml, bakeryYaml);
  const out = editFromYaml(bakery, yaml);
  assert.deepEqual(out.problems, []);
  const check = compile(bakery).blocks.find((b) => b.kind === "check" && /175/.test(bakery.split("\n").slice(b.startLine - 1, b.endLine).join("\n")));
  const changed = changedLines(bakery, out.markdown);
  assert.ok(changed.length > 0);
  assert.ok(changed.every((n) => n >= check.startLine && n <= check.endLine), `changed ${changed} outside ${check.startLine}-${check.endLine}`);
  assert.ok(!changed.includes(check.startLine), "the check's label line stays as written");
  assert.match(out.markdown, /is between 170 and 200/);
  assert.ok(out.changes.length > 0);
});

test("a refusal leaves the source as it was", () => {
  const out = editFromYaml(bakery, bakeryYaml + "meta:\n  owner: bakery\n");
  assert.equal(out.markdown, null);
  assert.deepEqual(out.problems.map((p) => p.path), ["meta"]);
});

test("YAML that doesn't parse gives its problems at their line and no Markdown", () => {
  const out = editFromYaml(bakery, "ergo_spec: v0.2\nsubjects: [\n");
  assert.equal(out.markdown, null);
  assert.ok(out.problems.length > 0);
  assert.ok(out.problems.every((p) => /^line \d+$/.test(p.path) && !/ at line \d+/.test(p.message)));
});

test("YAML that isn't a mapping is not a policy", () => {
  assert.deepEqual(readYaml("- a\n- b\n").problems.map((p) => p.path), ["line 1"]);
  assert.equal(readYaml("just words").policy, null);
});

test("the YAML the Markdown already gives changes nothing", () => {
  assert.deepEqual(editFromYaml(bakery, bakeryYaml), { markdown: bakery, changes: [], problems: [] });
});

test("YAML written differently but meaning the same policy changes nothing", () => {
  const yaml = bakeryYaml.replace('assert: allergens does not contain "nuts"', 'assert:\n          - allergens does not contain "nuts"');
  assert.notEqual(yaml, bakeryYaml);
  assert.equal(editFromYaml(bakery, yaml).markdown, bakery);
});

test("a Markdown source with problems is not rewritten", () => {
  const { source } = readSample("mistyped-fields");
  const out = editFromYaml(source, bakeryYaml);
  assert.equal(out.markdown, null);
  assert.ok(out.problems.length > 0);
});

test("YAML typed next to an empty document writes a new document", () => {
  const out = editFromYaml("  \n", bakeryYaml);
  assert.deepEqual(out.problems, []);
  assert.deepEqual(normalise(compile(out.markdown).policy), normalise(compile(bakery).policy));
});

test("pasting a YAML policy gives a Markdown document for it", () => {
  const markdown = markdownFromPaste(bakeryYaml);
  assert.deepEqual(normalise(compile(markdown).policy), normalise(compile(bakery).policy));
});

test("pasting something that isn't a YAML policy gives nothing", () => {
  assert.equal(markdownFromPaste("# A heading\n\nSome words."), null);
  assert.equal(markdownFromPaste("subjects: {}\n"), null);
  assert.equal(markdownFromPaste(bakeryYaml + "meta: 1\n"), null);
});
