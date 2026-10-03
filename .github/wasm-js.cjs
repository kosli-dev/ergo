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

const parseTime = (v) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(?:Z|([+-])(\d{2}):(\d{2}))$/.exec(v);
  if (!m) return undefined;
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second);
  const fields = [date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate(), date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds()];
  if (fields.some((f, i) => f !== [year, month, day, hour, minute, second][i])) return undefined;
  const offset = m[8] ? BigInt((m[8] === "-" ? -1 : 1) * (Number(m[9]) * 3600 + Number(m[10]) * 60)) : 0n;
  const nanos = (BigInt(date.getTime() / 1000) - offset) * 1000000000n + BigInt((m[7] || "").padEnd(9, "0").slice(0, 9));
  if (nanos < -(2n ** 63n) || nanos >= 2n ** 63n) return undefined;
  return JSON.rawJSON(String(nanos));
};

loadPolicy(fs.readFileSync(path.join(runtimeDir, "policy.wasm")), undefined, { "time.parse_rfc3339_ns": parseTime }).then((policy) => {
  const { builtins, opa_json_dump } = policy.wasmInstance.exports;
  const memory = new Uint8Array(policy.mem.buffer);
  const start = opa_json_dump(builtins());
  const needed = Object.keys(JSON.parse(Buffer.from(memory.slice(start, memory.indexOf(0, start))).toString()));
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
  process.exit(failed.length > 0 ? 1 : 0);
});
