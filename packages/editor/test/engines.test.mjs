import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_ENGINE, ENGINES, ENGINE_LABELS, engineNote, makeRustRunner, readEngine } from "../src/engines.mjs";

test("the two engines are labelled by the file they run", () => {
  assert.deepEqual(ENGINES.map((e) => ENGINE_LABELS[e]), ["ergo.rego (OPA Wasm)", "ergo-engine (Rust Wasm)"]);
  assert.deepEqual(Object.keys(ENGINE_LABELS).sort(), [...ENGINES].sort());
});

test("a saved engine comes back as it was saved", () => {
  for (const engine of ENGINES) assert.equal(readEngine(engine), engine);
});

test("a missing or unknown saved engine gives ergo.rego", () => {
  assert.equal(DEFAULT_ENGINE, "opa");
  for (const text of [null, undefined, "", "Rust", "rust ", "{}"]) assert.equal(readEngine(text), "opa", String(text));
});

test("the note names the engine and its version", () => {
  assert.equal(engineNote({ engine: { name: "ergo-engine", version: "0.1.0-dev" } }), "Report made by ergo-engine 0.1.0-dev.");
  assert.equal(engineNote({ engine: { name: "ergo.rego" } }), "Report made by ergo.rego.");
});

test("the note is empty when the report doesn't say which engine made it", () => {
  for (const report of [null, undefined, {}, { engine: null }, { engine: {} }, { engine: { name: 3 } }]) assert.equal(engineNote(report), "");
});

test("the Rust runner passes the three texts on as JSON and returns the parsed report", () => {
  const seen = [];
  const run = makeRustRunner((...args) => {
    seen.push(args);
    return '{"compliant":true}';
  });
  assert.deepEqual(run(' {"a": 9007199254740993} ', { subjects: {} }, " {} "), { compliant: true });
  assert.deepEqual(seen, [['{"a": 9007199254740993}', '{"subjects":{}}', "{}"]]);
});

test("the Rust runner gives null for a report of null and lets an error through", () => {
  assert.equal(makeRustRunner(() => "null")("{}", {}, "{}"), null);
  assert.throws(() => makeRustRunner(() => { throw new Error("the input isn't valid JSON: x"); })("{", {}, "{}"), /the input isn't valid JSON/);
});
