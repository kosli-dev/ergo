import test, { before } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { compile, parse } from "@kosli/ergo-markdown";
import opa from "@open-policy-agent/opa-wasm";
import { parse as parseYaml } from "yaml";
import { layoutRows, policySheet, makeRunner, parseTime, reportTables, yamlText, reportDocument } from "../src/lib.mjs";
import { sampleCases, readSample, opaVersionNote, sentencesGlue } from "../build.mjs";
import { VIEWS, LABELS } from "../src/layout.mjs";
import { makeRustRunner } from "../src/engines.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "..", "dist", "playground.html");
let html = "";

before(() => {
  execFileSync("node", ["build.mjs"], { cwd: join(here, ".."), stdio: "inherit" });
  html = readFileSync(dist, "utf8");
});

test("the build writes dist/playground.html", () => {
  assert.ok(existsSync(dist));
  assert.ok(html.length > 100000);
});

test("the page has no script tag that ends early", () => {
  const opens = html.match(/<script>/g).length;
  const closes = html.match(/<\/script>/g).length;
  assert.equal(opens, closes);
  assert.equal(html.match(/<\/script/gi).length, closes);
});

test("every placeholder was filled and the page asks nothing from the network", () => {
  for (const p of ["__BUNDLE__", "__SAMPLES__", "__WASM__", "__RUST_WASM__", "__SENTENCES_WASM__"]) assert.ok(!html.includes(p), p);
  assert.ok(!/<link /.test(html));
  assert.ok(!/<script[^>]* src=/.test(html));
});

test("the page holds only ASCII in its samples", () => {
  const start = html.indexOf("window.EDITOR");
  const end = html.indexOf("</script>", start);
  assert.ok(!/[^\x00-\x7f]/.test(html.slice(start, end)));
});

test("the page says the playground, the Markdown format and the Rust engine are experimental", () => {
  assert.match(html, /<p class="notice" id="notice" role="note"><b>Experimental\.<\/b> This playground, the Markdown format and the Rust engine may change or go away\. The Rust engine can give a different report from ergo\.rego\.<\/p>/);
});

test("the playground says what it's for, not that a policy is a document", () => {
  assert.match(html, /<h1>Ergo playground<\/h1><span>write a policy and see its report<\/span>/);
});

test("the page hides the colour swatches but keeps the note until a view that colours lines the way the legend says is open", () => {
  assert.match(html, /<div class="legend bare" id="legend">/);
  assert.match(html, /\.legend\.bare span:not\(\.note\) \{ display:none; \}/);
  assert.match(html, /"legend"\)\s*\.classList\.toggle\(\s*"bare"/);
});

test("the tab labels and the copy button stay on one line, so the tabs fit next to the button", () => {
  assert.match(html, /\.tab \{[^}]*white-space:nowrap;[^}]*\}/);
  assert.match(html, /<button class="ghost" id="copy" title="Copy the YAML">Copy<\/button>/);
});

test("the page has a tab label for every view", () => {
  for (const view of VIEWS) assert.ok(html.includes(JSON.stringify(LABELS[view])), view);
});

const casesDir = join(here, "..", "..", "markdown", "cases");
const regoVersion = /^version := "(.+)"$/m.exec(readFileSync(join(casesDir, "..", "..", "..", "engines", "rego", "ergo.rego"), "utf8"))[1];
const expected = (dir, file) => {
  const path = join(casesDir, dir, file);
  if (!existsSync(path)) return null;
  const value = JSON.parse(readFileSync(path, "utf8"));
  if (value.engine?.version === "ergo.rego's version") value.engine.version = regoVersion;
  return value;
};
let ergo;
const runErgoText = async (inputText, policy, paramsText) => {
  ergo ??= await opa.loadPolicy(Buffer.from(/wasm: "([^"]+)"/.exec(html)[1], "base64"), undefined, { "time.parse_rfc3339_ns": parseTime });
  return makeRunner((doc) => ergo.evaluate(doc))(reportDocument(inputText, policy, paramsText));
};
let rust;
const runRust = async (input, policy, params) => {
  if (!rust) {
    const glue = await import("../../../engines/rust/wasm/pkg/ergo_policy_wasm.js");
    glue.initSync({ module: Buffer.from(/rustWasm: "([^"]+)"/.exec(html)[1], "base64") });
    rust = makeRustRunner(glue.report);
  }
  return rust(JSON.stringify(input), policy, JSON.stringify(params));
};
const runErgo = (input, policy, params) => runErgoText(JSON.stringify(input), policy, JSON.stringify(params));

test("the Wasm inside the page reads a number a JavaScript number can't hold as written", async () => {
  const policy = {
    ergo_spec: /ergo_spec: (v[0-9.]+(?:-dev)?)/.exec(readFileSync(join(casesDir, "baking", "policy.ergo.md"), "utf8"))[1],
    subjects: { item: { from: "items", identified_by: "id" } },
    requirements: { r: { subject: "item", checks: { exact: "n is 9007199254740993", cap: "n is at most $params.max" } } },
  };
  const report = await runErgoText('{"items": [{"id": "a", "n": 9007199254740993}]}', policy, '{"max": 9007199254740992}');
  const cells = Object.fromEntries(report.results.filter((r) => r.subject.id === "a").map((r) => [r.check, r.passed]));
  assert.deepEqual(cells, { cap: false, exact: true });
});

test("the Rust Wasm inside the page reads a number a JavaScript number can't hold as written", async () => {
  const policy = {
    ergo_spec: /^_spec := "(v[0-9.]+(?:-dev)?)"/m.exec(readFileSync(join(casesDir, "..", "..", "..", "engines", "rego", "ergo.rego"), "utf8"))[1],
    subjects: { item: { from: "items", identified_by: "id" } },
    requirements: { r: { subject: "item", checks: { exact: "n is 9007199254740993", cap: "n is at most $params.max" } } },
  };
  const glue = await import("../../../engines/rust/wasm/pkg/ergo_policy_wasm.js");
  await runRust({}, policy, {});
  const text = glue.report('{"items": [{"id": "a", "n": 9007199254740993}]}', JSON.stringify(policy), '{"max": 9007199254740992}');
  assert.ok(text.includes("9007199254740993"));
  const report = JSON.parse(text);
  const cells = Object.fromEntries(report.results.filter((r) => r.subject.id === "a").map((r) => [r.check, r.passed]));
  assert.deepEqual(cells, { cap: false, exact: true });
});

test("the Rust Wasm inside the page throws a plain message for input that isn't JSON", async () => {
  const glue = await import("../../../engines/rust/wasm/pkg/ergo_policy_wasm.js");
  await runRust({}, {}, {});
  assert.throws(() => glue.report("{", "{}", "{}"), /^Error: the input isn't valid JSON: /);
});

test("the page holds the sentences Wasm and it reads a sentence", async () => {
  const bytes = Buffer.from(/sentencesWasm: "([^"]+)"/.exec(html)[1], "base64");
  const pkgDir = join(here, "..", "..", "..", "engines", "rust", "sentences-wasm", "pkg");
  assert.deepEqual(bytes, readFileSync(join(pkgDir, "ergo_policy_sentences_wasm_bg.wasm")));
  const glue = await import("../../../engines/rust/sentences-wasm/pkg/ergo_policy_sentences_wasm.js");
  glue.initSync({ module: bytes });
  assert.equal(JSON.parse(glue.parseCheck("approvals is at least 2")).tree.assertions.length, 1);
});

test("the build says when the sentences Wasm is not built and where to build it", () => {
  assert.throws(() => sentencesGlue(join(here, "no-such-folder")), /The sentences Wasm isn't built: .*no-such-folder has no ergo_policy_sentences_wasm\.js.*"Building for a browser" in engines\/rust\/README\.md/);
  assert.equal(sentencesGlue().bytes.length > 1000, true);
});

test("the Wasm inside the page takes input and params that aren't objects, as Ergo does", async () => {
  const policy = { ergo_spec: /ergo_spec: (v[0-9.]+(?:-dev)?)/.exec(readFileSync(join(casesDir, "baking", "policy.ergo.md"), "utf8"))[1], subjects: { item: { from: "items" } }, requirements: { r: { subject: "item", checks: { c: "x exists" } } } };
  for (const input of ["null", "[]", '"x"']) {
    const report = await runErgoText(input, policy, "{}");
    assert.equal(report.requirements.r.status, "not_met", input);
  }
});

test("the bakery sample is the baking case", () => {
  assert.equal(sampleCases.bakery, "baking");
});

for (const [name, dir] of Object.entries(sampleCases)) {
  const sample = readSample(dir);
  const result = compile(sample.source);
  const problems = expected(dir, "problems.json");

  test(`the ${name} sample has the problems its case expects`, () => {
    assert.deepEqual(result.problems, problems ?? []);
  });

  test(`every block and problem of the ${name} sample has a layout row`, () => {
    const rows = layoutRows(result, sample.source);
    for (const b of result.blocks.filter((x) => x.kind !== "prose")) {
      assert.ok(rows.some((r) => r.top === b.startLine && r.kind === b.kind), `${b.kind} at line ${b.startLine}`);
    }
    for (const p of result.problems) {
      assert.ok(rows.some((r) => r.problems.includes(p.message) && p.line >= r.top && p.line < r.top + r.height), `line ${p.line}`);
    }
  });

  test(`every check and option row of the ${name} sample shows every sentence the compiler read`, () => {
    const rows = layoutRows(result, sample.source, parse(sample.source));
    const shown = rows.flatMap((r) => [...r.head, ...r.below]).filter((l) => l.kind === "sentence").map((l) => l.text);
    const read = Object.values(result.policy?.requirements ?? {}).flatMap((r) =>
      Object.values(r.checks ?? {}).flatMap((c) => [
        ...(c.for ? [c.for] : []),
        ...[c.assert ?? []].flat(),
        ...Object.values(c.any_of ?? {}).flatMap((o) => [o].flat()),
      ]),
    );
    assert.deepEqual(shown.toSorted(), read.toSorted());
  });

  test(`the title row of the ${name} sample shows text, not Markdown`, () => {
    const title = layoutRows(result, sample.source, parse(sample.source)).find((r) => r.kind === "title");
    if (title) assert.ok(!title.head[0].text.startsWith("#"), title.head[0].text);
  });

  if (problems) continue;

  test(`the YAML view of the ${name} sample reads back as the same policy`, () => {
    assert.deepEqual(parseYaml(yamlText(result.policy)), result.policy);
  });

  test(`the ${name} sample shows every requirement and check in the policy sheet`, () => {
    const sheet = policySheet(result.policy);
    for (const [reqName, req] of Object.entries(result.policy.requirements)) {
      const shown = sheet.requirements.find((r) => r.name === reqName);
      assert.ok(shown, reqName);
      assert.deepEqual(shown.checks.map((c) => c.name), Object.keys(req.checks));
    }
  });

  test(`the Rust Wasm inside the page gives the ${name} sample the report its case expects`, async () => {
    const report = await runRust(sample.input, result.policy, sample.params);
    assert.equal(report.engine.name, "ergo-rust");
    assert.deepEqual({ ...report, engine: null }, { ...expected(dir, "report.json"), engine: null });
  });

  test(`the Wasm inside the page gives the ${name} sample the report its case expects`, async () => {
    const report = await runErgo(sample.input, result.policy, sample.params);
    assert.deepEqual(report, expected(dir, "report.json"));
    assert.ok(reportTables(report).length > 0);
  });
}

for (const dir of readdirSync(casesDir).filter((d) => existsSync(join(casesDir, d, "policy.yaml"))).sort()) {
  test(`the YAML view of case ${dir} reads back as the same policy, names with spaces and punctuation included`, () => {
    const { policy } = compile(readFileSync(join(casesDir, dir, "policy.ergo.md"), "utf8"));
    assert.deepEqual(parseYaml(yamlText(policy)), policy);
  });
}

test("the build says which OPA it used and warns when the README tests another one", () => {
  const readme = "and we test Ergo with OPA 1.20.2. Older";
  assert.equal(opaVersionNote("Version: 1.20.2\nBuild Commit: x", readme), "Built Ergo to Wasm with OPA 1.20.2.");
  assert.equal(
    opaVersionNote("Version: 1.21.2\n", readme),
    "Built Ergo to Wasm with OPA 1.21.2. Warning: the README says we test Ergo with OPA 1.20.2.",
  );
});
