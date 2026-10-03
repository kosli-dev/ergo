const fs = require("fs");
const path = require("path");

const [wasmFile, runtimeDir] = process.argv.slice(2);
const runtime = path.join(runtimeDir, "node_modules/@open-policy-agent/opa-wasm");
const { loadPolicy } = require(runtime);
const provided = require(path.join(runtime, "src/builtins/index.js"));
const passedInByUsers = ["time.parse_rfc3339_ns"];

loadPolicy(fs.readFileSync(wasmFile)).then((policy) => {
  const { builtins, opa_json_dump } = policy.wasmInstance.exports;
  const memory = new Uint8Array(policy.mem.buffer);
  const start = opa_json_dump(builtins());
  const needed = Object.keys(JSON.parse(Buffer.from(memory.slice(start, memory.indexOf(0, start))).toString()));
  const missing = needed.filter((b) => !provided[b] && !passedInByUsers.includes(b));
  if (missing.length > 0) {
    console.error(`ergo uses built-ins the Wasm JS runtime doesn't have: ${missing.join(", ")}`);
    process.exit(1);
  }
  console.log(`The Wasm JS runtime has every built-in ergo needs: ${needed.filter((b) => provided[b]).join(", ")}`);
});
