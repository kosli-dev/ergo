const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const [runtimeDir] = process.argv.slice(2);
const runtime = path.join(runtimeDir, "node_modules/@open-policy-agent/opa-wasm");
const { loadPolicy } = require(runtime);
const provided = require(path.join(runtime, "src/builtins/index.js"));

const tests = execFileSync("git", ["ls-files", "*_test.rego"], { encoding: "utf8" }).split("\n").filter(Boolean).flatMap((file) => {
  const source = fs.readFileSync(file, "utf8");
  const pkg = source.match(/^package ([\w.]+)/m)[1].replaceAll(".", "/");
  return [...new Set(source.match(/^test_\w+/gm))].map((name) => `${pkg}/${name}`);
});

const bundle = path.join(runtimeDir, "suite.tar.gz");
execFileSync("opa", ["build", "-t", "wasm", "--ignore", ".github", ...tests.flatMap((t) => ["-e", t]), "-o", bundle, "."]);
execFileSync("tar", ["-xzf", bundle, "-C", runtimeDir, "/policy.wasm", "/data.json"]);

const ergoDir = path.join(runtimeDir, "ergo");
fs.mkdirSync(ergoDir, { recursive: true });
fs.writeFileSync(path.join(ergoDir, "entrypoint.rego"), "package entrypoint\n\nreport := data.ergo.report(input.document, input.policy, input.params)\n\nviolations := data.ergo.violations(input.report)\n");
execFileSync("opa", ["build", "-t", "wasm", "-e", "entrypoint/report", "-e", "entrypoint/violations", "-o", path.join(ergoDir, "ergo.tar.gz"), "ergo.rego", path.join(ergoDir, "entrypoint.rego")]);
execFileSync("tar", ["-xzf", path.join(ergoDir, "ergo.tar.gz"), "-C", ergoDir, "/policy.wasm"]);

const parseTime = (v) => {
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const load = (dir) => loadPolicy(fs.readFileSync(path.join(dir, "policy.wasm")), undefined, { "time.parse_rfc3339_ns": parseTime });

const builtinsOf = (policy) => {
  const { builtins, opa_json_dump } = policy.wasmInstance.exports;
  const memory = new Uint8Array(policy.mem.buffer);
  const start = opa_json_dump(builtins());
  return Object.keys(JSON.parse(Buffer.from(memory.slice(start, memory.indexOf(0, start))).toString()));
};

Promise.all([load(runtimeDir), load(ergoDir)]).then(([policy, ergo]) => {
  const outside = builtinsOf(ergo).filter((b) => b !== "time.parse_rfc3339_ns");
  if (outside.length > 0) {
    console.error(`ergo uses built-ins that OPA's Wasm build runs outside the module: ${outside.join(", ")}`);
    process.exit(1);
  }

  const needed = builtinsOf(policy);
  const missing = needed.filter((b) => !provided[b] && b !== "time.parse_rfc3339_ns");
  if (missing.length > 0) {
    console.error(`ergo uses built-ins the Wasm JS runtime doesn't have: ${missing.join(", ")}`);
    process.exit(1);
  }

  policy.setData(JSON.parse(fs.readFileSync(path.join(runtimeDir, "data.json"))));
  const failed = tests.filter((test) => {
    try {
      return policy.evaluate({}, test)[0]?.result !== true;
    } catch (e) {
      console.error(`${test}: ${e.message}`);
      return true;
    }
  });
  failed.forEach((test) => console.error(`FAIL ${test}`));
  console.log(`PASS: ${tests.length - failed.length}/${tests.length} with the Wasm JS runtime`);

  const budgetMB = 20;
  const document = { deployments: Array.from({ length: 100 }, (_, i) => ({ id: `d-${i}`, environment: i % 3 ? "prod" : "staging", ...(i % 2 ? { approved_by: "a" } : {}), tests: [{ ok: i % 5 > 0 }, { ok: true }] })) };
  const budgetPolicy = {
    subjects: { deployment: { from: ["deployments"], id: ["id"], applies_to: { is_prod: { op: "equals", path: ["environment"], value: "prod" } } } },
    requirements: {
      approved: { subject: "deployment", checks: { approved: { op: "non_empty_string", path: ["approved_by"] } } },
      tested: { subject: "deployment", require: "some", checks: { tested: { op: "all", path: ["tests"], check: { op: "equals", path: ["ok"], value: true } } } },
    },
  };
  const report = ergo.evaluate({ document, policy: budgetPolicy, params: {} }, "entrypoint/report")[0].result;
  const usedMB = (ergo.wasmInstance.exports.opa_heap_ptr_get() - ergo.baseHeapPtr) / 1e6;
  const sound = report.results.length === 338 && report.requirements.approved.subjects.matching === 66;
  console.log(`A report on 100 deployments used ${usedMB.toFixed(1)} MB of Wasm memory (budget ${budgetMB} MB)`);
  if (!sound) console.error("The memory budget's report didn't come out as expected, so its measurement can't be trusted");
  if (usedMB > budgetMB) console.error(`That's over the budget. Wasm doesn't cache function calls and frees nothing until the report is done, so look for something worked out again per row.`);
  process.exit(failed.length > 0 || !sound || usedMB > budgetMB ? 1 : 0);
});
