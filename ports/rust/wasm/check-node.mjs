import { readFileSync } from "node:fs";
import { initSync, report } from "./pkg/ergo_wasm.js";

initSync({ module: readFileSync(new URL("./pkg/ergo_wasm_bg.wasm", import.meta.url)) });

const spec = /^_spec := "(.*)"$/m.exec(
  readFileSync(new URL("../../../ergo.rego", import.meta.url), "utf8"),
)[1];
const policy = {
  ergo_spec: spec,
  subjects: { item: { from: "items", identified_by: "id" } },
  requirements: { r: { subject: "item", checks: { ok: "n is 1" } } },
};
const built = JSON.parse(report(JSON.stringify({ items: [{ id: "a", n: 1 }] }), JSON.stringify(policy), "{}"));
if (built.engine?.name !== "ergo-engine") {
  throw new Error(`unexpected engine: ${JSON.stringify(built.engine)}`);
}
if (built.compliant !== true) {
  throw new Error(`report isn't compliant: ${JSON.stringify(built)}`);
}
console.log(`ergo-wasm built a report with ${built.engine.name}`);
