import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_ENGINE, ENGINES, ENGINE_LABELS, engineMessage, engineNote, makeRustRunner, readEngine, stopOnPanic } from "../src/engines.mjs";

test("the two engines are labelled Rego engine and Rust engine", () => {
  assert.deepEqual(ENGINES.map((e) => ENGINE_LABELS[e]), ["Rego engine", "Rust engine (experimental)"]);
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
  assert.equal(engineNote({ engine: { name: "ergo-engine", version: "0.1.0-dev" } }), "Report made by the Rust engine (ergo-engine 0.1.0-dev).");
  assert.equal(engineNote({ engine: { name: "ergo-engine" } }), "Report made by the Rust engine (ergo-engine).");
  assert.equal(engineNote({ engine: { name: "ergo.rego", version: "0.3.0-dev" } }), "Report made by the Rego engine (ergo.rego 0.3.0-dev).");
  assert.equal(engineNote({ engine: { name: "ergo.rego" } }), "Report made by the Rego engine (ergo.rego).");
  assert.equal(engineNote({ engine: { name: "other", version: "1.0" } }), "Report made by other 1.0.");
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

test("the messages name the engine that was picked", () => {
  assert.equal(engineMessage("rust", "loading"), "The Rust engine is still loading.");
  assert.equal(engineMessage("opa", "loading"), "The Rego engine is still loading.");
  assert.equal(engineMessage("rust", "failed", "no memory"), "The Rust engine didn't load: no memory");
  assert.equal(engineMessage("opa", "failed", "bad Wasm"), "The Rego engine didn't load: bad Wasm");
  assert.equal(engineMessage("rust", "stopped"), "The Rust engine stopped after an internal error. Reload the page to use it again.");
  assert.equal(engineMessage("rust", "run", "unreachable"), "The Rust engine couldn't run this: unreachable");
  assert.equal(engineMessage("opa", "run", "boom"), "The Rego engine couldn't run this: boom");
});

test("after a panic the Rust engine stops and says to reload the page", () => {
  const calls = [];
  const run = stopOnPanic("rust", (x) => {
    calls.push(x);
    if (x === 1) throw new WebAssembly.RuntimeError("unreachable");
    return { x };
  });
  assert.deepEqual(run(0), { x: 0 });
  for (const x of [1, 2]) {
    assert.throws(() => run(x), (e) => e.stopped === true && e.message === "The Rust engine stopped after an internal error. Reload the page to use it again.");
  }
  assert.deepEqual(calls, [0, 1]);
});

test("an error that isn't a panic reaches the caller and the runner keeps going", () => {
  const run = stopOnPanic("rust", (x) => {
    if (x === 1) throw new Error("the input isn't valid JSON: x");
    return { x };
  });
  assert.throws(() => run(1), (e) => e.stopped === undefined && /isn't valid JSON/.test(e.message));
  assert.deepEqual(run(2), { x: 2 });
});
