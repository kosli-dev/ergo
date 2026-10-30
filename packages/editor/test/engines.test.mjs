import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_ENGINE, ENGINES, ENGINE_LABELS, engineMessage, engineNote, makeRustRunner, renewOnPanic, readEngine } from "../src/engines.mjs";

test("the two engines are labelled by the file they run", () => {
  assert.deepEqual(ENGINES.map((e) => ENGINE_LABELS[e]), ["ergo.rego", "Rust port (experimental)"]);
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
  assert.equal(engineNote({ engine: { name: "ergo-engine", version: "0.1.0-dev" } }), "Report made by the Rust port (ergo-engine 0.1.0-dev).");
  assert.equal(engineNote({ engine: { name: "ergo-engine" } }), "Report made by the Rust port (ergo-engine).");
  assert.equal(engineNote({ engine: { name: "ergo.rego", version: "0.2.0" } }), "Report made by ergo.rego 0.2.0.");
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

test("the messages name the engine that was picked", () => {
  assert.equal(engineMessage("rust", "loading"), "The Rust port is still loading.");
  assert.equal(engineMessage("opa", "loading"), "ergo.rego is still loading.");
  assert.equal(engineMessage("rust", "failed", "no memory"), "The Rust port didn't load: no memory");
  assert.equal(engineMessage("opa", "failed", "bad Wasm"), "ergo.rego didn't load: bad Wasm");
  assert.equal(engineMessage("rust", "run", "unreachable"), "The Rust port couldn't run this: unreachable");
  assert.equal(engineMessage("opa", "run", "boom"), "ergo.rego couldn't run this: boom");
});

const stubMake = (failures) => {
  const made = [];
  const make = () => {
    const id = made.length;
    made.push(id);
    let calls = 0;
    return (x) => {
      if (failures[id] && calls++ === 0) throw failures[id];
      return { id, x };
    };
  };
  return { make, made };
};

test("after a panic the next run uses a fresh runner and the panic still reaches the caller", () => {
  const { make, made } = stubMake([new WebAssembly.RuntimeError("unreachable")]);
  const run = renewOnPanic(make);
  assert.throws(() => run(1), WebAssembly.RuntimeError);
  assert.deepEqual(run(2), { id: 1, x: 2 });
  assert.deepEqual(run(3), { id: 1, x: 3 });
  assert.equal(made.length, 2);
});

test("an error that isn't a panic keeps the runner", () => {
  const { make, made } = stubMake([new Error("the input isn't valid JSON: x")]);
  const run = renewOnPanic(make);
  assert.throws(() => run(1), /isn't valid JSON/);
  assert.deepEqual(run(2), { id: 0, x: 2 });
  assert.equal(made.length, 1);
});

test("a runner that can't be made fails at once and one that can't be made again fails on the next run", () => {
  assert.throws(() => renewOnPanic(() => { throw new Error("no module"); }), /no module/);
  let n = 0;
  const run = renewOnPanic(() => {
    if (n++) throw new Error("no module");
    return () => { throw new WebAssembly.RuntimeError("unreachable"); };
  });
  assert.throws(() => run(), WebAssembly.RuntimeError);
  assert.throws(() => run(), /no module/);
});
