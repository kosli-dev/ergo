import test from "node:test";
import assert from "node:assert/strict";
import { layoutRows, policySheet, yamlText, markOf, parseJson, reportTables, makeRunner, plural, reportDocument, unroundable } from "../src/lib.mjs";

const block = (kind, startLine, endLine, name) => ({ kind, startLine, endLine, ...(name ? { name } : {}) });

test("a block becomes a row at its first line with the height of its lines", () => {
  const rows = layoutRows({ blocks: [block("requirement", 3, 4, "cake")], problems: [] }, "a\nb\n### Cake\ntext");
  assert.deepEqual(rows, [{ top: 3, height: 2, kind: "requirement", head: [{ kind: "name", text: "cake" }], below: [], problems: [] }]);
});

test("rows come out in source order whatever order the blocks came in", () => {
  const rows = layoutRows({ blocks: [block("check", 5, 5), block("title", 1, 1)], problems: [] }, "");
  assert.deepEqual(rows.map((r) => r.top), [1, 5]);
});

test("a block that holds later blocks stops before the first of them", () => {
  const rows = layoutRows({ blocks: [block("check", 2, 5, "any"), block("option", 4, 4, "a"), block("option", 5, 5, "b")], problems: [] }, "");
  assert.deepEqual(rows.map((r) => [r.top, r.height]), [[2, 2], [4, 1], [5, 1]]);
});

test("a block that starts on the same line as a longer one keeps one line of height at least", () => {
  const rows = layoutRows({ blocks: [block("check", 2, 2), block("option", 2, 2)], problems: [] }, "");
  assert.ok(rows.every((r) => r.height >= 1));
});

test("a problem is shown on the row that holds its line", () => {
  const result = { blocks: [block("check", 2, 3), block("prose", 5, 5)], problems: [{ line: 3, message: "a check needs a bold label" }] };
  const rows = layoutRows(result, "");
  assert.deepEqual(rows[0].problems, ["a check needs a bold label"]);
  assert.deepEqual(rows[1].problems, []);
});

const policy = {
  ergo_spec: "v0.2",
  description: "All good.",
  subjects: { batch: { description: "A batch.", from: "batches", identified_by: "id" } },
  requirements: {
    cake: {
      subject: "batch",
      min_subjects: 2,
      require: "some",
      checks: {
        nut_free: { description: "No nuts.", assert: 'allergens does not contain "nuts"' },
        both: { assert: ["a is 1", "b is 2"], for: "every items" },
        either: { any_of: { first: "a is 1", second: ["b is 2", "c is 3"] } },
      },
    },
    plain: { subject: "batch", checks: {} },
  },
};

test("the policy sheet lists every requirement and check", () => {
  const sheet = policySheet(policy);
  assert.deepEqual(sheet.requirements.map((r) => r.name), ["cake", "plain"]);
  assert.deepEqual(sheet.requirements[0].checks.map((c) => c.name), ["nut_free", "both", "either"]);
  assert.equal(sheet.description, "All good.");
});

test("the policy sheet gives subject, require and min subjects, with the defaults when they are left out", () => {
  const [cake, plain] = policySheet(policy).requirements;
  assert.deepEqual([cake.subject, cake.require, cake.minSubjects], ["batch", "some", 2]);
  assert.deepEqual([plain.subject, plain.require, plain.minSubjects], ["batch", "every", 1]);
});

test("a check shows its sentences as written, whether one or several, and its for line", () => {
  const [nutFree, both] = policySheet(policy).requirements[0].checks;
  assert.deepEqual(nutFree.sentences, ['allergens does not contain "nuts"']);
  assert.equal(nutFree.description, "No nuts.");
  assert.deepEqual(both.sentences, ["a is 1", "b is 2"]);
  assert.equal(both.for, "for every items");
});

test("a requirement's title is its name with spaces for underscores", () => {
  const sheet = policySheet({ requirements: { cake_batch: {}, "cake batch": {} } });
  assert.deepEqual(sheet.requirements.map((r) => [r.name, r.title]), [["cake_batch", "cake batch"], ["cake batch", "cake batch"]]);
});

test("an any_of check shows each option with its sentences", () => {
  const either = policySheet(policy).requirements[0].checks[2];
  assert.deepEqual(either.sentences, []);
  assert.deepEqual(either.options, [
    { name: "first", sentences: ["a is 1"] },
    { name: "second", sentences: ["b is 2", "c is 3"] },
  ]);
});

test("the subjects keep where they come from and what names them", () => {
  assert.deepEqual(policySheet(policy).subjects, [{ name: "batch", description: "A batch.", from: "batches", identifiedBy: "id" }]);
});

test("no policy gives no sheet and no YAML", () => {
  assert.equal(policySheet(null), null);
  assert.equal(yamlText(null), "");
});

test("YAML keeps a long sentence on one line", () => {
  const long = "a ".repeat(100).trim();
  const text = yamlText({ checks: { x: { assert: long } } });
  assert.ok(text.includes(long));
});

const tree = (start, end) => ({ position: { start: { line: start }, end: { line: end } } });

test("a node that overlaps a check gets the check colour even when it also overlaps a field", () => {
  assert.equal(markOf(tree(4, 8), [block("field", 4, 4), block("check", 6, 7)]), "check");
});

test("a node that overlaps only a field gets the declaration colour", () => {
  assert.equal(markOf(tree(4, 4), [block("field", 4, 4)]), "declare");
});

test("a node that overlaps only a title gets the other colour", () => {
  assert.equal(markOf(tree(1, 1), [block("title", 1, 1)]), "other");
});

test("a node that overlaps only prose, or nothing, gets no colour", () => {
  assert.equal(markOf(tree(2, 3), [block("prose", 2, 3)]), null);
  assert.equal(markOf(tree(9, 9), [block("check", 1, 2)]), null);
  assert.equal(markOf({}, [block("check", 1, 2)]), null);
});

test("JSON that does not parse is reported with what it was", () => {
  const out = parseJson("{", "input");
  assert.equal(out.ok, false);
  assert.match(out.message, /^The input isn't valid JSON yet\./);
});

test("any JSON is accepted, as Ergo takes any input and params", () => {
  assert.deepEqual(parseJson("[]", "params"), { ok: true, value: [] });
  assert.deepEqual(parseJson("null", "input"), { ok: true, value: null });
  assert.deepEqual(parseJson('"x"', "params"), { ok: true, value: "x" });
  assert.deepEqual(parseJson('{"a": 1}', "params"), { ok: true, value: { a: 1 } });
});

test("the report's document holds the input and params as written, so no number is rounded", () => {
  const doc = reportDocument('{"n": 9007199254740993, "d": 1.0000000000000001}', { p: 1 }, "[1e400]");
  assert.ok(doc instanceof ArrayBuffer);
  assert.equal(
    new TextDecoder().decode(doc),
    '{"input":{"n": 9007199254740993, "d": 1.0000000000000001},"policy":{"p":1},"params":[1e400]}',
  );
});

test("numbers a JavaScript number can't hold as written are found, and strings are skipped", () => {
  assert.deepEqual(
    unroundable('{"a": 9007199254740993, "b": 1.0000000000000001, "c": 1e400, "s": "9007199254740993"}'),
    ["9007199254740993", "1.0000000000000001", "1e400"],
  );
  assert.deepEqual(unroundable('{"a": 9007199254740992, "b": 1.50, "c": 1e2, "d": -0.1, "e": 2.5e-3}'), []);
  assert.deepEqual(unroundable('{"s": "a\\"b 99999999999999999999", "n": 1}'), []);
});

test("the runner passes input, policy and params together and returns null when there is no result", () => {
  let seen;
  const run = makeRunner((doc) => {
    seen = doc;
    return [{ result: { compliant: true } }];
  });
  const doc = reportDocument('{"a": 1}', { p: 1 }, '{"q": 1}');
  assert.deepEqual(run(doc), { compliant: true });
  assert.equal(seen, doc);
  assert.equal(makeRunner(() => [])(doc), null);
  assert.equal(makeRunner(() => [{}])(doc), null);
});

const report = {
  requirements: { cake: { status: "not_met" } },
  results: [
    { requirement: "cake", check: "$well_formed", subject: { type: "batch", id: null }, passed: true, cause: "satisfied" },
    { requirement: "cake", check: "nut_free", subject: { type: "batch", id: "b1" }, passed: true, cause: "satisfied" },
    { requirement: "cake", check: "temp_ok", subject: { type: "batch", id: "b1" }, passed: false, cause: "value" },
    { requirement: "cake", check: "nut_free", subject: { type: "batch", id: "b2" }, passed: false, cause: "absent" },
    { requirement: "other", check: "x", subject: { type: "batch", id: "z" }, passed: true, cause: "satisfied" },
  ],
};

test("the report becomes one table per requirement with subjects as rows and checks as columns", () => {
  const [cake] = reportTables(report);
  assert.equal(cake.name, "cake");
  assert.equal(cake.status, "not_met");
  assert.deepEqual(cake.checks, ["nut_free", "temp_ok"]);
  assert.deepEqual(cake.rows.map((r) => r.subject), ['"b1"', '"b2"']);
  assert.deepEqual(cake.rows[0].cells.temp_ok, { passed: false, cause: "value" });
  assert.equal(cake.rows[1].cells.temp_ok, undefined);
});

test("rows about the requirement itself are kept apart from the subjects", () => {
  const [cake] = reportTables(report);
  assert.deepEqual(cake.general, [{ check: "$well_formed", passed: true, cause: "satisfied" }]);
});

test("a subject inside a parent says which parent", () => {
  const [t] = reportTables({
    requirements: { r: {} },
    results: [{ requirement: "r", check: "c", subject: { type: "pr", id: "7", in: { artifact: "sha-1" } }, passed: true, cause: "satisfied" }],
  });
  assert.equal(t.rows[0].subject, '"7" in artifact "sha-1"');
});

test("no report gives no tables", () => {
  assert.deepEqual(reportTables(null), []);
});

test("a count says one thing or several things", () => {
  assert.equal(plural(1, "check"), "1 check");
  assert.equal(plural(0, "check"), "0 checks");
  assert.equal(plural(4, "problem"), "4 problems");
});

test("a problem on a line no block covers still gets a row at that line", () => {
  const rows = layoutRows({ blocks: [{ kind: "check", name: "a", startLine: 1, endLine: 2 }], problems: [{ line: 4, message: "a check needs a bold label" }] }, "x\ny\n\nz");
  assert.deepEqual(rows.at(-1), { top: 4, height: 1, kind: "problem", head: [], below: [], problems: ["a check needs a bold label"] });
  assert.equal(rows.length, 2);
});

test("a check's row shows what the compiler read, not the source again", () => {
  const result = {
    policy: { requirements: { cake: { checks: {
      nut_free: { description: "No nuts", assert: "allergens does not contain \"nuts\"" },
      made: { description: "Says how", any_of: { recipe: ["a is 1", "b is 2"] } },
    } } } },
    problems: [],
    blocks: [
      block("requirement", 1, 1, "cake"),
      block("check", 2, 3, "nut_free"),
      block("check", 4, 6, "made"),
      block("option", 5, 6, "recipe"),
    ],
  };
  const rows = layoutRows(result, "");
  assert.deepEqual(rows[1].head, [{ kind: "name", text: "nut_free" }, { kind: "said", text: "No nuts" }]);
  assert.deepEqual(rows[1].below, [{ kind: "sentence", text: "allergens does not contain \"nuts\"" }]);
  assert.deepEqual(rows[2].head, [{ kind: "name", text: "made" }, { kind: "said", text: "Says how" }]);
  assert.deepEqual(rows[2].below, []);
  assert.deepEqual(rows[3].below, [{ kind: "sentence", text: "a is 1" }, { kind: "sentence", text: "b is 2" }]);
});

test("a check's row falls back to its source line when the policy has problems", () => {
  const rows = layoutRows({ policy: null, problems: [], blocks: [block("requirement", 1, 1, "cake"), block("check", 2, 3, "a")] }, "### Cake\n- **A**: x\n  `y`");
  assert.deepEqual(rows[1].head, [{ kind: "name", text: "a" }]);
  assert.deepEqual(rows[1].below, [{ kind: "source", text: "- **A**: x" }]);
});

test("a one-line option shows its sentence on the same line as its name", () => {
  const result = {
    policy: { requirements: { r: { checks: { c: { any_of: { declared: "some ids is in $params.allowed", known: ["a is 1", "b is 2"] } } } } } },
    problems: [],
    blocks: [block("requirement", 1, 1, "r"), block("check", 2, 5, "c"), block("option", 3, 3, "declared"), block("option", 4, 5, "known")],
  };
  const rows = layoutRows(result, "");
  assert.deepEqual(rows[2].head, [{ kind: "name", text: "declared" }, { kind: "sentence", text: "some ids is in $params.allowed" }]);
  assert.deepEqual(rows[2].below, []);
});

test("a field's row shows its value as the compiler read it", () => {
  const result = {
    policy: { subjects: { component: { from: "components", identified_by: "name" } }, requirements: { r: { subject: "component", min_subjects: 0, checks: {} } } },
    problems: [],
    blocks: [
      block("subject", 1, 3, "component"),
      block("field", 2, 2, "from"),
      block("field", 3, 3, "identified by"),
      block("requirement", 4, 6, "r"),
      block("field", 5, 5, "subject"),
      block("field", 6, 6, "min subjects"),
    ],
  };
  const heads = layoutRows(result, "").filter((r) => r.kind === "field").map((r) => r.head);
  assert.deepEqual(heads, [
    [{ kind: "name", text: "from" }, { kind: "value", text: "components" }],
    [{ kind: "name", text: "identified by" }, { kind: "value", text: "name" }],
    [{ kind: "name", text: "subject" }, { kind: "value", text: "component" }],
    [{ kind: "name", text: "min subjects" }, { kind: "value", text: "0" }],
  ]);
});

test("the title's row shows the heading's text without the Markdown marks", () => {
  const tree = { children: [{ type: "heading", depth: 1, position: { start: { line: 1 } }, children: [{ type: "text", value: "Component " }, { type: "inlineCode", value: "licences" }] }] };
  const rows = layoutRows({ policy: null, problems: [], blocks: [block("title", 1, 1)] }, "# Component `licences`", tree);
  assert.deepEqual(rows[0].head, [{ kind: "name", text: "Component licences" }]);
});

test("a description's row shows every line of its paragraphs, blank lines included", () => {
  const rows = layoutRows({ policy: { description: "One two.\n\nThree." }, problems: [], blocks: [block("title", 1, 1), block("description", 3, 6)] }, "# T\n\nOne\ntwo.\n\nThree.\n");
  assert.deepEqual(rows[1].head, [{ kind: "source", text: "One" }]);
  assert.deepEqual(rows[1].below, [{ kind: "source", text: "two." }, { kind: "source", text: "\u00a0" }, { kind: "source", text: "Three." }]);
});

test("a Checks: row counts the checks in the list after it, options aside", () => {
  const blocks = [block("requirement", 1, 9, "r"), block("checks", 2, 2), block("check", 4, 6, "a"), block("option", 5, 6, "o"), block("check", 7, 7, "b"), block("checks", 9, 9)];
  const rows = layoutRows({ policy: null, problems: [], blocks }, "");
  assert.deepEqual(rows.filter((r) => r.kind === "checks").map((r) => r.head), [[{ kind: "name", text: "2 checks" }], [{ kind: "name", text: "0 checks" }]]);
});

test("the front matter's row shows the spec version the policy reads", () => {
  const rows = layoutRows({ policy: { ergo_spec: "v0.2" }, problems: [], blocks: [block("front matter", 1, 3)] }, "---\nergo_spec: v0.2\n---");
  assert.deepEqual(rows[0].head, [{ kind: "name", text: "ergo_spec" }, { kind: "value", text: "v0.2" }]);
});

test("a subject's label shows its id as JSON, so 1 and \"1\" are two rows", () => {
  const [t] = reportTables({
    requirements: { r: { status: "not_met" } },
    results: [
      { requirement: "r", check: "ok", subject: { id: 1 }, passed: false, cause: "value" },
      { requirement: "r", check: "ok", subject: { id: "1" }, passed: true, cause: "satisfied" },
    ],
  });
  assert.deepEqual(t.rows, [
    { subject: "1", cells: { ok: { passed: false, cause: "value" } } },
    { subject: '"1"', cells: { ok: { passed: true, cause: "satisfied" } } },
  ]);
});

test("two subjects with the same id stay two rows, so a failure is never overwritten", () => {
  const [t] = reportTables({
    requirements: { r: { status: "not_met" } },
    results: [
      { requirement: "r", check: "a", subject: { id: "x" }, passed: false, cause: "value" },
      { requirement: "r", check: "b", subject: { id: "x" }, passed: true, cause: "satisfied" },
      { requirement: "r", check: "a", subject: { id: "x" }, passed: true, cause: "satisfied" },
      { requirement: "r", check: "b", subject: { id: "x" }, passed: true, cause: "satisfied" },
    ],
  });
  assert.equal(t.rows.length, 2);
  assert.deepEqual(t.rows[0].cells.a, { passed: false, cause: "value" });
  assert.deepEqual(t.rows[1].cells.a, { passed: true, cause: "satisfied" });
});

test("a subject's $applies row and its check rows share one row, whatever order they come in", () => {
  const [t] = reportTables({
    requirements: { r: { status: "not_met" } },
    results: [
      { requirement: "r", check: "$applies", subject: { id: 1 }, passed: true, cause: "satisfied" },
      { requirement: "r", check: "$applies", subject: { id: "1" }, passed: true, cause: "satisfied" },
      { requirement: "r", check: "ok", subject: { id: 1 }, passed: false, cause: "absent" },
      { requirement: "r", check: "ok", subject: { id: "1" }, passed: true, cause: "satisfied" },
    ],
  });
  assert.deepEqual(
    t.rows.map((r) => [r.subject, Object.keys(r.cells), r.cells.ok.passed]),
    [
      ["1", ["$applies", "ok"], false],
      ['"1"', ["$applies", "ok"], true],
    ],
  );
});

