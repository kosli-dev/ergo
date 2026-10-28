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
execFileSync("opa", ["build", "-t", "wasm", "--ignore", ".github", "--ignore", "ports", ...tests.flatMap((t) => ["-e", t]), "-o", bundle, "."]);
execFileSync("tar", ["-xzf", bundle, "-C", runtimeDir, "/policy.wasm", "/data.json"]);

const ergoDir = path.join(runtimeDir, "ergo");
fs.mkdirSync(ergoDir, { recursive: true });
fs.writeFileSync(path.join(ergoDir, "entrypoint.rego"), "package entrypoint\n\nreport := data.ergo.report(input.document, input.policy, input.params)\n\nviolations := data.ergo.violations(input.report)\n\nas_sentences := data.ergo.as_sentences(input.policy)\n\ncompile := data.ergo.compile(input.policy)\n");
execFileSync("opa", ["build", "-t", "wasm", "-e", "entrypoint/report", "-e", "entrypoint/violations", "-e", "entrypoint/as_sentences", "-e", "entrypoint/compile", "-o", path.join(ergoDir, "ergo.tar.gz"), "ergo.rego", path.join(ergoDir, "entrypoint.rego")]);
execFileSync("tar", ["-xzf", path.join(ergoDir, "ergo.tar.gz"), "-C", ergoDir, "/policy.wasm"]);

const parseTime = (v) => {
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const load = (dir, memory) => loadPolicy(fs.readFileSync(path.join(dir, "policy.wasm")), memory, { "time.parse_rfc3339_ns": parseTime });

const builtinsOf = (policy) => {
  const { builtins, opa_json_dump } = policy.wasmInstance.exports;
  const memory = new Uint8Array(policy.mem.buffer);
  const start = opa_json_dump(builtins());
  return Object.keys(JSON.parse(Buffer.from(memory.slice(start, memory.indexOf(0, start))).toString()));
};

Promise.all([load(runtimeDir, { initial: 16 }), load(ergoDir)]).then(async ([policy, ergo]) => {
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

  const document = { deployments: Array.from({ length: 100 }, (_, i) => ({ id: `d-${i}`, environment: i % 3 ? "prod" : "staging", ...(i % 2 ? { approved_by: "a" } : {}), tests: [{ ok: i % 5 > 0 }, { ok: true }] })) };
  const budgetPolicy = {
    ergo_spec: "v0.3-dev",
    subjects: { deployment: { from: 'deployments whose environment is "prod"', identified_by: "id" } },
    requirements: {
      approved: { subject: "deployment", checks: { approved: "approved_by is a non-empty string" } },
      tested: { subject: "deployment", require: "some", checks: { tested: "every tests.ok is true" } },
    },
  };
  const sentencePolicy = {
    ergo_spec: "v0.3-dev",
    subjects: budgetPolicy.subjects,
    requirements: {
      approved: {
        subject: "deployment",
        checks: {
          approved: "approved_by is a non-empty string",
          environment: 'environment is one of "prod", "staging"',
          tests: "tests is not empty",
        },
      },
    },
  };
  const chainPolicy = {
    ergo_spec: "v0.3-dev",
    subjects: {
      deployment: { from: 'deployments whose environment is "prod"', identified_by: "id" },
      test: { from: "deployment.tests" },
    },
    requirements: { approved: { subject: "test", checks: { ok: "ok is true and deployment.approved_by exists" } } },
  };
  const measure = async (name, policy, rows, matching, budgetMB) => {
    const fresh = await load(ergoDir);
    const report = fresh.evaluate({ document, policy, params: {} }, "entrypoint/report")[0].result;
    const usedMB = (fresh.wasmInstance.exports.opa_heap_ptr_get() - fresh.baseHeapPtr) / 1e6;
    const sound = report.results.length === rows && report.requirements.approved.subjects.matching === matching;
    console.log(`A report on 100 deployments ${name} used ${usedMB.toFixed(1)} MB of Wasm memory (budget ${budgetMB} MB)`);
    if (!sound) console.error("The memory budget's report didn't come out as expected, so its measurement can't be trusted");
    if (usedMB > budgetMB) console.error(`That's over the budget. Wasm doesn't cache function calls and frees nothing until the report is done, so look for something worked out again per row, or a large regular expression compiled for every report, or for every parent of a subject read from another subject.`);
    return sound && usedMB <= budgetMB;
  };
  const withEvery = await measure("with a check on every test", budgetPolicy, 338, 66, 24);
  const withSentences = await measure("with three checks on each deployment", sentencePolicy, 301, 66, 17);
  const withChain = await measure("with the tests of each prod deployment as subjects", chainPolicy, 265, 132, 40);
  process.exit(failed.length > 0 || !withEvery || !withSentences || !withChain ? 1 : 0);
});
