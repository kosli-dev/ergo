import assert from "node:assert/strict";
import {test} from "node:test";
import {compile, nameOf, nameProblem, parse} from "../src/compile.ts";
import {CAKE, CAKE_POLICY, inChecks, inRequirement, problemsOf} from "./helpers.ts";

const messages = (markdown: string) => problemsOf(markdown).map((p) => p.message);

test("the cake example compiles to the expected policy", () => {
  const {policy, problems} = compile(CAKE);
  assert.deepEqual(problems, []);
  assert.deepEqual(policy, CAKE_POLICY);
});

test("the cake example keeps policy keys in order", () => {
  const {policy} = compile(CAKE);
  assert.deepEqual(Object.keys(policy!), ["ergo_spec", "description", "subjects", "requirements"]);
  const checks = (policy as any).requirements["cake batch"].checks;
  assert.deepEqual(Object.keys(checks["each item"]), ["for", "assert"]);
  assert.deepEqual(Object.keys(checks["nut free"]), ["description", "assert"]);
});

test("the cake example reports its blocks with kinds, names and line ranges", () => {
  const {blocks} = compile(CAKE);
  assert.deepEqual(blocks, [
    {kind: "front matter", startLine: 1, endLine: 3},
    {kind: "title", startLine: 5, endLine: 5},
    {kind: "description", startLine: 7, endLine: 7},
    {kind: "prose", startLine: 9, endLine: 9},
    {kind: "subject", name: "batch", startLine: 11, endLine: 17},
    {kind: "description", startLine: 13, endLine: 13},
    {kind: "field", name: "from", startLine: 15, endLine: 15},
    {kind: "field", name: "identified by", startLine: 16, endLine: 16},
    {kind: "prose", startLine: 18, endLine: 18},
    {kind: "requirement", name: "cake batch", startLine: 20, endLine: 36},
    {kind: "description", startLine: 22, endLine: 22},
    {kind: "field", name: "subject", startLine: 24, endLine: 24},
    {kind: "checks", startLine: 26, endLine: 26},
    {kind: "check", name: "nut free", startLine: 28, endLine: 29},
    {kind: "check", name: "temp ok", startLine: 30, endLine: 30},
    {kind: "check", name: "licence allowed", startLine: 31, endLine: 35},
    {kind: "option", name: "declared", startLine: 32, endLine: 32},
    {kind: "option", name: "known", startLine: 33, endLine: 35},
    {kind: "check", name: "each item", startLine: 36, endLine: 36},
  ]);
});

test("parse returns a markdown tree with front matter", () => {
  const tree = parse("---\nergo_spec: v0.2\n---\n\n# T\n");
  assert.deepEqual(tree.children.map((c) => c.type), ["yaml", "heading"]);
});

test("an empty document compiles to an empty policy", () => {
  assert.deepEqual(compile(""), {policy: {subjects: {}, requirements: {}}, problems: [], blocks: []});
});

test("front matter without ergo_spec leaves the key out", () => {
  assert.deepEqual(compile("---\n---\n").problems, [{line: 1, message: "the front matter must be keys and values"}]);
  assert.deepEqual(compile("# T\n").policy, {subjects: {}, requirements: {}});
});

test("ergo_spec goes into the policy as written", () => {
  assert.deepEqual(compile("---\nergo_spec: 3\n---\n").policy, {ergo_spec: 3, subjects: {}, requirements: {}});
});

test("front matter that is not valid yaml is a problem at the yaml line", () => {
  assert.deepEqual(problemsOf("---\nergo_spec: v0.2\na: [\n---\n"), [
    {line: 3, message: "the front matter isn't valid YAML"},
  ]);
});

test("front matter that is a list or a word is a problem on line 1", () => {
  assert.deepEqual(problemsOf("---\n- a\n---\n"), [{line: 1, message: "the front matter must be keys and values"}]);
  assert.deepEqual(problemsOf("---\nhello\n---\n"), [{line: 1, message: "the front matter must be keys and values"}]);
});

test("front matter params is a problem on the params line", () => {
  assert.deepEqual(problemsOf("---\nergo_spec: v0.2\nparams:\n  a: 1\n---\n"), [
    {line: 3, message: "the front matter holds only ergo_spec, not params: pass params to ergo.report"},
  ]);
});

test("front matter with another key is a problem on that key", () => {
  assert.deepEqual(problemsOf("---\nergo_spec: v0.2\nname: x\n---\n"), [
    {line: 3, message: "the front matter holds only ergo_spec, not name"},
  ]);
});

test("front matter with a non-text key is named by its value", () => {
  assert.deepEqual(messages("---\n? [a]\n: 1\n---\n"), ["the front matter holds only ergo_spec, not [\"a\"]"]);
});

test("a second title is a problem", () => {
  assert.deepEqual(problemsOf("# One\n\n# Two\n"), [{line: 3, message: "a policy has one # title"}]);
});

test("the paragraphs after the title are the description, joined by a blank line", () => {
  const {policy, blocks} = compile("# T\n\nFirst\nline.\n\nSecond.\n\n> Quote.\n\nAfter.\n");
  assert.equal((policy as any).description, "First line.\n\nSecond.");
  assert.deepEqual(blocks.map((b) => b.kind), ["title", "description", "prose", "prose"]);
  assert.deepEqual(blocks[1], {kind: "description", startLine: 3, endLine: 6});
});

test("a list straight after the title ends the description window", () => {
  const {policy} = compile("# T\n\n- a\n\nWords.\n");
  assert.equal("description" in policy!, false);
});

test("a heading straight after the title ends the description window", () => {
  const {policy} = compile("# T\n\n## Notes\n\nWords.\n");
  assert.equal("description" in policy!, false);
});

test("a section called Subjects opens subjects and another name opens prose", () => {
  const {policy, blocks} = compile("## Notes\n\nHello.\n\n## Subjects\n\n### a\n");
  assert.deepEqual(policy, {subjects: {a: {}}, requirements: {}});
  assert.deepEqual(blocks.map((b) => b.kind), ["prose", "prose", "prose", "subject"]);
});

test("section names are exact and case sensitive", () => {
  assert.deepEqual(messages("## subjects\n\n### a\n"), [
    '### a is under "subjects", which isn\'t Subjects or Requirements',
  ]);
});

test("a ### heading under another section is a problem on its line", () => {
  assert.deepEqual(problemsOf("## Notes\n\n### Thing\n"), [
    {line: 3, message: '### Thing is under "Notes", which isn\'t Subjects or Requirements'},
  ]);
});

test("a ### heading with no section is a problem", () => {
  assert.deepEqual(problemsOf("### Thing\n"), [{line: 1, message: "### Thing is under no ## section"}]);
});

test("content under a misplaced ### heading is prose", () => {
  const {blocks} = compile("## Notes\n\n### Thing\n\nText.\n");
  assert.deepEqual(blocks.map((b) => b.kind), ["prose", "prose", "prose"]);
});

test("a heading below level three is prose and keeps the item open", () => {
  const {policy, blocks} = compile("## Subjects\n\n### a\n\n#### Notes\n\n- from: `x`\n");
  assert.deepEqual(policy, {subjects: {a: {from: "x"}}, requirements: {}});
  assert.deepEqual(blocks.map((b) => b.kind), ["prose", "subject", "prose", "field"]);
});

test("a table ends a description and is prose", () => {
  const {policy, blocks} = compile("# T\n\nWhy.\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\nAfter.\n");
  assert.equal((policy as any).description, "Why.");
  assert.deepEqual(parse("| a |\n| - |\n").children[0]!.type, "table");
  assert.deepEqual(blocks.map((b) => b.kind), ["title", "description", "prose", "prose"]);
});

test("a subject name is its heading lowercased, trimmed and with each run of whitespace made one space", () => {
  assert.deepEqual(compile("## Subjects\n\n### My  Batch \n").policy, {
    subjects: {"my batch": {}},
    requirements: {},
  });
});

test("a requirement name is its heading lowercased, with each run of whitespace made one space", () => {
  assert.deepEqual(Object.keys((compile("## Requirements\n\n### -- Cake  batch! Ünï 2 --\n").policy as any).requirements), [
    "-- cake batch! ünï 2 --",
  ]);
});

test("an empty subject or requirement heading is a problem", () => {
  assert.deepEqual(problemsOf("## Requirements\n\n###\n"), [{line: 3, message: "a label needs a letter or a digit"}]);
  assert.deepEqual(problemsOf("## Subjects\n\n###   \n"), [{line: 3, message: "a label needs a letter or a digit"}]);
});

test("subject names that differ only in whitespace clash", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### cake  batch\n\n### cake batch\n"), [
    {line: 5, message: "subject cake batch has the same name as the subject on line 3"},
  ]);
});

test("two subjects with the same name are a problem on the later one", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n### a\n"), [
    {line: 5, message: "subject a has the same name as the subject on line 3"},
  ]);
});

test("two requirements that give the same name are a problem on the later one", () => {
  assert.deepEqual(problemsOf("## Requirements\n\n### Cake\n\n###  CAKE \n\n### cake!\n"), [
    {line: 5, message: "requirement cake has the same name as the requirement on line 3"},
  ]);
});

test("the same name in different sections is fine", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n## Requirements\n\n### a\n"), []);
});

test("an item block runs to the line before the next heading of level three or less", () => {
  const {blocks} = compile("## Subjects\n\n### a\n\ntext\n\n#### deep\n\n### b\n\ntext\n");
  assert.deepEqual(
    blocks.filter((b) => b.kind === "subject"),
    [
      {kind: "subject", name: "a", startLine: 3, endLine: 8},
      {kind: "subject", name: "b", startLine: 9, endLine: 11},
    ],
  );
});

test("an item block ends at the line before the next section heading", () => {
  const {blocks} = compile("## Subjects\n\n### a\n\n## Requirements\n");
  assert.deepEqual(blocks.find((b) => b.kind === "subject"), {kind: "subject", name: "a", startLine: 3, endLine: 4});
});

test("the paragraphs after a subject heading are its description, joined by a blank line", () => {
  const {policy, blocks} = compile("## Subjects\n\n### a\n\nOne\ntwo.\n\nMore.\n\n- from: `x`\n\nAfter.\n");
  assert.deepEqual(policy, {subjects: {a: {description: "One two.\n\nMore.", from: "x"}}, requirements: {}});
  assert.deepEqual(blocks.filter((b) => b.kind === "description"), [{kind: "description", startLine: 5, endLine: 8}]);
  assert.equal(blocks.at(-1)!.kind, "prose");
});

test("the paragraphs after a requirement heading are its description, up to Checks:", () => {
  const {policy} = compile(inRequirement("Why.\n\nHow.\n\nChecks:\n\n- **A**: `x`\n\nAfter."));
  assert.equal((policy as any).requirements.r.description, "Why.\n\nHow.");
});

test("subjects whose headings differ only by case clash", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### Batch\n\n### batch\n"), [
    {line: 5, message: "subject batch has the same name as the subject on line 3"},
  ]);
});

test("a list ends the description window of an item", () => {
  const {policy} = compile("## Subjects\n\n### a\n\n- from: `x`\n\nWords.\n");
  assert.deepEqual(policy, {subjects: {a: {from: "x"}}, requirements: {}});
});

test("a code block ends the description window of an item", () => {
  const {policy, blocks} = compile("## Subjects\n\n### a\n\n```\nx\n```\n\nWords.\n");
  assert.deepEqual(policy, {subjects: {a: {}}, requirements: {}});
  assert.deepEqual(blocks.map((b) => b.kind), ["prose", "subject", "prose", "prose"]);
});

test("a subject takes from and identified by fields", () => {
  const {policy, blocks} = compile("## Subjects\n\n### a\n\n- identified by: `id`\n- from: `rows`\n");
  assert.deepEqual(policy, {subjects: {a: {from: "rows", identified_by: "id"}}, requirements: {}});
  assert.deepEqual(
    blocks.filter((b) => b.kind === "field"),
    [
      {kind: "field", name: "identified by", startLine: 5, endLine: 5},
      {kind: "field", name: "from", startLine: 6, endLine: 6},
    ],
  );
});

test("a requirement takes subject, require and min subjects fields", () => {
  const {policy} = compile(inRequirement("- min subjects: `3`\n- require: `all`\n- subject: `a`"));
  assert.deepEqual((policy as any).requirements.r, {subject: "a", require: "all", min_subjects: 3});
  assert.deepEqual(Object.keys((policy as any).requirements.r), ["subject", "require", "min_subjects"]);
});

test("a field with text after its code span is a problem", () => {
  assert.deepEqual(messages("## Subjects\n\n### a\n\n- identified by: `id`\n- from: `x` y\n"), ["a field is written as key: `value`"]);
});

test("a field with no code span or two paragraphs is a problem", () => {
  assert.deepEqual(messages("## Subjects\n\n### a\n\n- identified by: `id`\n- from: x\n- from: `x`\n  more\n\n  other\n"), [
    "a field is written as key: `value`",
    "a field is written as key: `value`",
  ]);
});

test("a list in an item with no field in it is prose", () => {
  const {problems, blocks} = compile("## Requirements\n\n### r\n\n- subject: `s`\n\n1. a numbered note\n2. another, with `code` in it\n");
  assert.deepEqual(problems, []);
  assert.deepEqual(blocks.at(-1), {kind: "prose", startLine: 7, endLine: 8});
});

test("a field's colon is optional and its key is read whatever its capitals", () => {
  const {policy, problems, blocks} = compile("## Subjects\n\n### a\n\n- From `xs`\n- IDENTIFIED BY: `id`\n\n## Requirements\n\n### R\n\n- Subject `a`\n- Require `some`\n- Min subjects `2`\n");
  assert.deepEqual(problems, []);
  assert.deepEqual(policy, {
    subjects: {a: {from: "xs", identified_by: "id"}},
    requirements: {r: {subject: "a", require: "some", min_subjects: 2}},
  });
  assert.deepEqual(blocks.filter((b) => b.kind === "field").map((b) => b.name), ["from", "identified by", "subject", "require", "min subjects"]);
});

test("in a subject or requirement, words and one code span are a field, colon or not", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- Frm `xs`\n"), [{line: 5, message: 'a subject\'s fields are from and identified by, not "Frm"'}]);
  assert.deepEqual(problemsOf(inRequirement("- See `docs`")), [
    {line: 5, message: 'a requirement\'s fields are subject, require and min subjects, not "See"'},
  ]);
  assert.deepEqual(problemsOf(inRequirement("- See the docs\n- See `docs` and more")), []);
});

test("outside a subject or requirement, a bullet without a colon is a field only when it starts with a field's name", () => {
  assert.deepEqual(problemsOf("# T\n\n- See `docs`\n"), []);
  assert.deepEqual(problemsOf("# T\n\n- From `xs`\n"), [{line: 3, message: "a field goes under a ### subject or requirement"}]);
});

test("an unknown key with a colon names the key as written", () => {
  assert.deepEqual(messages("## Subjects\n\n### a\n\n- Owner: `x`\n"), ['a subject\'s fields are from and identified by, not "Owner"']);
});

test("a bullet in an item that starts with a field's name is a field even when written wrong", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- from batches\n"), [{line: 5, message: "a field is written as key: `value`"}]);
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- identified by id\n"), [{line: 5, message: "a field is written as key: `value`"}]);
  assert.deepEqual(problemsOf(inRequirement("- min subjects 2\n- subject\n- require: every")), [
    {line: 5, message: "a field is written as key: `value`"},
    {line: 6, message: "a field is written as key: `value`"},
    {line: 7, message: "a field is written as key: `value`"},
  ]);
});

test("a bullet in an item that only starts like a field's name is prose", () => {
  assert.deepEqual(problemsOf(inRequirement("- fromage is a cheese\n- subjects of the crown\n- required reading")), []);
});

test("a field item that is not a paragraph or has no key is a problem", () => {
  assert.deepEqual(messages("## Subjects\n\n### a\n\n- from: `x`\n- ```\n  x\n  ```\n- `x`\n- : `x`\n- text `x` more\n"), [
    "a field is written as key: `value`",
    "a field is written as key: `value`",
    "a field is written as key: `value`",
    "a field is written as key: `value`",
  ]);
});

test("a field may have whitespace after its code span", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- from: `x` \n"), []);
});

test("an unknown subject field is a problem naming the key as written", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- Colour: `x`\n"), [
    {line: 5, message: 'a subject\'s fields are from and identified by, not "Colour"'},
  ]);
});

test("an unknown requirement field is a problem", () => {
  assert.deepEqual(messages(inRequirement("- from: `x`")), [
    'a requirement\'s fields are subject, require and min subjects, not "from"',
  ]);
});

test("a field set twice is a problem that names the first line", () => {
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- from: `x`\n- from: `y`\n"), [
    {line: 6, message: "from is already set on line 5"},
  ]);
});

test("min subjects must be a whole number", () => {
  assert.deepEqual(messages(inRequirement("- min subjects: `two`")), ["min subjects must be a whole number"]);
  assert.deepEqual(messages(inRequirement("- min subjects: `-1`")), ["min subjects must be a whole number"]);
  assert.deepEqual(messages(inRequirement("- min subjects: `1.5`")), ["min subjects must be a whole number"]);
});

test("a field under the title or a bare section is a problem", () => {
  assert.deepEqual(problemsOf("# T\n\n- from: `x`\n"), [{line: 3, message: "a field goes under a ### subject or requirement"}]);
  assert.deepEqual(problemsOf("## Subjects\n\n- from: `x`\n- plain item\n"), [
    {line: 3, message: "a field goes under a ### subject or requirement"},
  ]);
  assert.deepEqual(problemsOf("## Requirements\n\n- subject: `x`\n"), [
    {line: 3, message: "a field goes under a ### subject or requirement"},
  ]);
});

test("a list under another section is prose", () => {
  assert.deepEqual(problemsOf("## Notes\n\n- from: `x`\n"), []);
});

test("other top-level nodes are prose", () => {
  const {blocks} = compile("# T\n\nDesc.\n\n> quote\n\n| a |\n|---|\n| b |\n\n<div>x</div>\n");
  assert.deepEqual(blocks.map((b) => b.kind), ["title", "description", "prose", "prose", "prose"]);
});

test("a requirement without Checks has no checks key", () => {
  assert.deepEqual((compile(inRequirement("- subject: `a`")).policy as any).requirements.r, {subject: "a"});
});

test("Checks followed by something that is not a list is a problem", () => {
  assert.deepEqual(problemsOf(inRequirement("Checks:\n\nWords.")), [
    {line: 5, message: "Checks: must be followed by a list"},
  ]);
  assert.deepEqual(messages(inRequirement("Checks:")), ["Checks: must be followed by a list"]);
});

test("a second Checks list is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `x`\n\nChecks:\n\n- **A**: `y`")), [
    {line: 9, message: "a requirement has one Checks: list"},
  ]);
});

test("a second Checks without a list says it needs a list", () => {
  assert.deepEqual(messages(inChecks("- **A**: `x`\n\nChecks:\n")), ["Checks: must be followed by a list"]);
});

test("Checks in a subject or under the title is prose, and its checks are problems", () => {
  assert.deepEqual(compile("## Subjects\n\n### a\n\nChecks:\n\n- from: `x`\n").policy, {
    subjects: {a: {from: "x"}},
    requirements: {},
  });
  assert.deepEqual(problemsOf("# T\n\nChecks:\n\n- **A**: `x`\n"), [
    {line: 5, message: "a check goes in the list right after Checks:"},
  ]);
});

test("Checks in a requirement is a checks block with no name, even when it is a problem", () => {
  assert.deepEqual(compile(inChecks("- **A**: `x`")).blocks.find((b) => b.kind === "checks"), {kind: "checks", startLine: 5, endLine: 5});
  const blocks = (markdown: string) => compile(markdown).blocks.filter((b) => b.kind === "checks").map((b) => b.startLine);
  assert.deepEqual(blocks(inChecks("- **A**: `x`")), [5]);
  assert.deepEqual(blocks(inRequirement("Checks:\n\nWords.")), [5]);
  assert.deepEqual(blocks("## Subjects\n\n### a\n\nChecks:\n"), []);
});

test("a check after a paragraph that ends the Checks list is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `x`\n\nWhy.\n\n- **B**: `y`\n- **C**: Words `z`")), [
    {line: 11, message: "a check goes in the list right after Checks:"},
    {line: 12, message: "a check goes in the list right after Checks:"},
  ]);
});

test("a check in a subject, under the title, under another section or in a quote is a problem", () => {
  const message = "a check goes in the list right after Checks:";
  assert.deepEqual(problemsOf("## Subjects\n\n### a\n\n- **A**: `x`\n"), [{line: 5, message}]);
  assert.deepEqual(problemsOf("# T\n\n- **A**: `x`\n"), [{line: 3, message}]);
  assert.deepEqual(problemsOf("## Notes\n\n> - **A**: `x`\n"), [{line: 3, message}]);
  assert.deepEqual(problemsOf(inRequirement("Check:\n\n- **A**: `x`")), [{line: 7, message}]);
});

test("a bullet with a bold label but no code span is prose outside Checks", () => {
  assert.deepEqual(problemsOf("# T\n\n- **Note**: words only\n- `x`\n\n1. text\n"), []);
});

test("a bullet with a bold label and a code span is a misplaced check whatever follows the label", () => {
  assert.deepEqual(problemsOf("# T\n\n- **Note** `x`\n"), [
    {line: 3, message: "a check goes in the list right after Checks:"},
  ]);
});

test("an item already reported inside a check is not reported again", () => {
  assert.deepEqual(messages(inChecks("- **A**: `x`\n\n  > - **O**: `y`")), [
    "a check's sentences go in code spans, with nothing else after the first one",
  ]);
});

test("Checks does not count as the description of a requirement", () => {
  const {policy} = compile(inChecks("- **A**: `x`"));
  assert.deepEqual((policy as any).requirements.r, {checks: {a: {assert: "x"}}});
});

test("a check item with an empty checks list gives empty checks", () => {
  assert.deepEqual(messages(inChecks("- **A**: `x`")), []);
});

test("a check without a bold label is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- Just `x`")), [{line: 7, message: "a check needs a bold label"}]);
  assert.deepEqual(messages(inChecks("- ```\n  x\n  ```")), ["a check needs a bold label"]);
  assert.deepEqual(messages(inChecks("- text **A**: `x`")), ["a check needs a bold label"]);
});

test("a bold label that is not followed by a colon is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A** `x`")), [{line: 7, message: "a bold label is followed by a colon"}]);
  assert.deepEqual(messages(inChecks("- **A**")), ["a bold label is followed by a colon"]);
  assert.deepEqual(messages(inChecks("- **A** : `x`")), ["a bold label is followed by a colon"]);
});

test("a label of punctuation is a name like any other", () => {
  assert.deepEqual(Object.keys((compile(inChecks("- **!!**: `x`\n- **A**:\n  - **?**: `y`")).policy as any).requirements.r.checks), ["!!", "a"]);
  assert.deepEqual((compile(inChecks("- **A**:\n  - **?**: `y`")).policy as any).requirements.r.checks.a, {any_of: {"?": "y"}});
});

test("nameOf and nameProblem give the name a heading or label makes and what is wrong with it", () => {
  assert.equal(nameOf("  Cake \n batch! "), "cake batch!");
  assert.equal(nameOf("cake batch"), "cake batch");
  assert.equal(nameProblem("cake batch"), null);
  assert.equal(nameProblem(""), "a label needs a letter or a digit");
  assert.equal(nameProblem("$applies"), "a name can't start with $");
});

test("a name that starts with $ is a problem, whatever it names", () => {
  const message = "a name can't start with $";
  assert.deepEqual(problemsOf("## Subjects\n\n### $batch\n"), [{line: 3, message}]);
  assert.deepEqual(problemsOf("## Requirements\n\n### $applies\n"), [{line: 3, message}]);
  assert.deepEqual(problemsOf(inChecks("- **$well_formed**: `x`")), [{line: 7, message}]);
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **$o**: `x`")), [{line: 8, message}]);
  assert.deepEqual(problemsOf(inChecks("- **A $**: `x`")), []);
});

test("two checks with the same name are a problem on the later one", () => {
  assert.deepEqual(problemsOf(inChecks("- **Nut free**: `x`\n- **nut  FREE**: `y`\n- **Nut-free**: `z`")), [
    {line: 8, message: "check nut free has the same name as the check on line 7"},
  ]);
});

test("a check description is the text before the first code span, with spaces collapsed", () => {
  const {policy} = compile(inChecks("- **A**:   Must be\n  fine **really**.\n  `x`"));
  assert.deepEqual((policy as any).requirements.r.checks.a, {description: "Must be fine really.", assert: "x"});
});

test("a check's description runs over its paragraphs up to the first code span", () => {
  const check = (body: string) => (compile(inChecks(body)).policy as any).requirements.r.checks.a;
  assert.deepEqual(check("- **A**: First\n  line.\n\n  Second.\n\n  `x`\n  `y`"), {description: "First line.\n\nSecond.", assert: ["x", "y"]});
  assert.deepEqual(check("- **A**:\n\n  Only here.\n\n  `x`"), {description: "Only here.", assert: "x"});
  assert.deepEqual(check("- **A**: Words.\n\n  More.\n  `x`"), {description: "Words.\n\nMore.", assert: "x"});
  assert.deepEqual(check("- **A**: Words.\n\n  - **O**: `x`"), {description: "Words.", any_of: {o: "x"}});
  assert.deepEqual(check("- **A**: `x`\n\n  `y`"), {assert: ["x", "y"]});
});

test("a check's paragraph with words after its first code span is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: Words `x`\n\n  More words.")), [
    {line: 9, message: "a check's sentences go in code spans, with nothing else after the first one"},
  ]);
});

test("a check with several sentences asserts a list", () => {
  const {policy} = compile(inChecks("- **A**: `x` `y`\n  `z`"));
  assert.deepEqual((policy as any).requirements.r.checks.a.assert, ["x", "y", "z"]);
});

test("a code span value passes through as written", () => {
  const {policy} = compile(inChecks("- **A**: `a  <b> *c* \\d`"));
  assert.deepEqual((policy as any).requirements.r.checks.a.assert, "a  <b> *c* \\d");
});

test("text between or after code spans is a problem on its line", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `x` and `y`")), [
    {line: 7, message: "a check's sentences go in code spans, with nothing else after the first one"},
  ]);
  assert.deepEqual(messages(inChecks("- **A**: `x` **y**")), [
    "a check's sentences go in code spans, with nothing else after the first one",
  ]);
  assert.deepEqual(messages(inChecks("- **A**: `x`  \n  `y`")), [
    "a check's sentences go in code spans, with nothing else after the first one",
  ]);
});

test("another child in a check item is a problem on that child's line", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `x`\n\n  more words")), [
    {line: 9, message: "a check's sentences go in code spans, with nothing else after the first one"},
  ]);
});

test("a second nested list in a check item is a problem", () => {
  assert.deepEqual(messages(inChecks("- **A**:\n  - **B**: `x`\n\n  text\n\n  - **C**: `y`")), [
    "a check's sentences go in code spans, with nothing else after the first one",
    "a check's sentences go in code spans, with nothing else after the first one",
  ]);
});

test("a for line and a sentence give for and assert", () => {
  const {policy} = compile(inChecks("- **A**: `for some xs as x` `x.ok is true`"));
  assert.deepEqual((policy as any).requirements.r.checks.a, {for: "some xs as x", assert: "x.ok is true"});
});

test("two for lines are a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `for a as b` `for c as d` `x`")), [
    {line: 7, message: "a check has one for line"},
  ]);
});

test("a for line with no other sentence is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `for a as b`")), [
    {line: 7, message: "a check needs a sentence besides its for line"},
  ]);
});

test("a for line may go with a list of options", () => {
  const {policy} = compile(inChecks("- **A**: `for a as b`\n  - **O**: `x`"));
  assert.deepEqual((policy as any).requirements.r.checks.a, {for: "a as b", any_of: {o: "x"}});
});

test("a nested list gives any_of with strings and lists", () => {
  const {policy} = compile(inChecks("- **A**: Words.\n  - **One**: `x`\n  - **Two**: `y` `z`"));
  assert.deepEqual((policy as any).requirements.r.checks.a, {description: "Words.", any_of: {one: "x", two: ["y", "z"]}});
});

test("sentences and options together are a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: `x`\n  - **O**: `y`")), [
    {line: 8, message: "a check has sentences or options, not both"},
  ]);
});

test("a check with no sentence and no options is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**: Words only.")), [
    {line: 7, message: "a check needs a sentence in a code span, or a list of options"},
  ]);
});

test("an option without a bold label is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - `x`")), [{line: 8, message: "an option needs a bold label"}]);
});

test("an option label without a colon is a problem", () => {
  assert.deepEqual(messages(inChecks("- **A**:\n  - **O** `x`")), ["a bold label is followed by a colon"]);
});


test("an option with a description is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **O**: Words `x`")), [
    {line: 8, message: "an option takes no description"},
  ]);
});

test("an option with no code span is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **O**:")), [
    {line: 8, message: "an option needs a sentence in a code span"},
  ]);
  assert.deepEqual(messages(inChecks("- **A**:\n  - **O**: words")), ["an option needs a sentence in a code span"]);
});

test("an option with text after its first span is a problem", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **O**: `x` and `y`")), [
    {line: 8, message: "an option's sentences go in code spans, with nothing else after the first one"},
  ]);
});

test("another child in an option is a problem on its line", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **O**: `x`\n\n    more")), [
    {line: 10, message: "an option's sentences go in code spans, with nothing else after the first one"},
  ]);
});

test("two options with the same name are a problem on the later one", () => {
  assert.deepEqual(problemsOf(inChecks("- **A**:\n  - **O**: `x`\n  - **o**: `y`")), [
    {line: 9, message: "option o has the same name as the option on line 8"},
  ]);
});

test("an option that starts with for is a plain sentence", () => {
  const {policy} = compile(inChecks("- **A**:\n  - **O**: `for a as b`"));
  assert.deepEqual((policy as any).requirements.r.checks.a, {any_of: {o: "for a as b"}});
});

test("policy is null when there is any problem", () => {
  assert.equal(compile("# A\n\n# B\n").policy, null);
});

test("problems are sorted by line and keep the order they were found in", () => {
  const {problems} = compile("## Subjects\n\n### a\n\n- x: `1`\n- from: nope\n\n### a\n\n# T\n# U\n");
  assert.deepEqual(problems.map((p) => p.line), [5, 6, 8, 11]);
  assert.deepEqual(
    compile(inRequirement("- from: `x`\n- bad")).problems.map((p) => p.line),
    [5, 6],
  );
});

test("blocks are sorted by start line", () => {
  const {blocks} = compile(CAKE);
  assert.deepEqual(blocks.map((b) => b.startLine), [...blocks.map((b) => b.startLine)].sort((a, b) => a - b));
});

test("a check with a bold label and a colon only still lists its block", () => {
  const {blocks} = compile(inChecks("- **A**: `x`"));
  assert.deepEqual(blocks.filter((b) => b.kind === "check"), [{kind: "check", name: "a", startLine: 7, endLine: 7}]);
});

test("a name such as __proto__ is kept as a plain key", () => {
  const {policy} = compile("## Subjects\n\n### \\_\\_proto\\_\\_\n\n- from: `x`\n");
  assert.deepEqual(Object.keys((policy as any).subjects), ["__proto__"]);
});

test("with no title, the paragraphs at the top are the policy's description", () => {
  assert.equal(compile("Top.\n\nMore.\n\n## Subjects\n").policy!.description, "Top.\n\nMore.");
  assert.equal(compile("---\nergo_spec: v0.2\n---\n\nTop.\n").policy!.description, "Top.");
});

test("paragraphs after a title that follows a description at the top are prose", () => {
  const {policy, blocks} = compile("Top.\n\n# T\n\nUnder the title.\n");
  assert.equal(policy!.description, "Top.");
  assert.deepEqual(blocks.map((b) => b.kind), ["description", "title", "prose"]);
});

test("a paragraph after a table at the top is prose", () => {
  assert.equal(compile("| a |\n| - |\n| b |\n\nText.\n").policy!.description, undefined);
});

test("a field written in a table cell under a requirement is a problem", () => {
  assert.deepEqual(problemsOf(inRequirement("| a |\n| - |\n| Min subjects `5` |")), [
    {line: 7, message: "a field goes in the list of fields, as - key `value`"},
  ]);
});

test("a paragraph that starts with a word that isn't a field key and a code span is prose", () => {
  assert.deepEqual(problemsOf(inRequirement("- Subject `batch`\n\nNote: `x`")), []);
});
