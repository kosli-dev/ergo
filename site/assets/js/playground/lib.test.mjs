import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bakeryRequirements, byCodePoint, decodeState, encodeState, formats, parseRego, parseTime, sortKeys, toRego, toYaml } from "./lib.mjs";

const repo = new URL("../../../../", import.meta.url).pathname;
const bakeryFile = readFileSync(join(repo, "examples/baking/ergo/baking.yaml"), "utf8");

const tricky = {
  empty: { list: [], object: {} },
  strings: ["", "yes", "no", "1", "a: b", "#x", "- y", "[z]", "multi\nline", "tab\there", "quote \" and \\", "175–200°C", "😀"],
  numbers: [0, -1, 1.5, 1e21, -0.25],
  other: [true, false, null],
  nested: [[1, [2]], [{ a: 1 }], { b: [{ c: [] }] }],
  "key with spaces": { "$name": "x", "": "empty key" },
};

const roundTrips = (value) => {
  for (const from of Object.keys(formats)) {
    for (const to of Object.keys(formats)) {
      const once = formats[to].parse(formats[to].write(formats[from].parse(formats[from].write(value))));
      assert.deepEqual(once, value, `${from} → ${to}`);
    }
  }
};

test("the bakery requirements come out of the example file as they were written", () => {
  const written = bakeryFile.split("\n").slice(2).map((l) => l.slice(4)).join("\n");
  assert.equal(bakeryRequirements(bakeryFile), written);
});

test("every format reads back what every other format writes", () => {
  roundTrips(formats.yaml.parse(bakeryRequirements(bakeryFile)));
  roundTrips(tricky);
});

test("lists of plain values are written on one line", () => {
  assert.equal(toYaml({ path: ["bake", "temp_c"], deep: [[1, 2]] }), "path: [bake, temp_c]\ndeep:\n- [1, 2]\n");
  assert.equal(toRego({ path: ["bake", "temp_c"] }), 'requirements := {\n\t"path": ["bake", "temp_c"],\n}\n');
});

test("the Rego it writes is formatted the way opa fmt formats it and means the same to OPA", () => {
  const dir = mkdtempSync(join(tmpdir(), "playground-"));
  const file = join(dir, "x.rego");
  writeFileSync(file, `package x\n\n${toRego(tricky)}`);
  assert.equal(execFileSync("opa", ["fmt", "--list", file], { encoding: "utf8" }), "");
  const read = JSON.parse(execFileSync("opa", ["eval", "-d", file, "--format", "raw", "data.x.requirements"], { encoding: "utf8" }));
  assert.deepEqual(read, tricky);
});

test("Rego as people write it, with comments, trailing commas, raw strings and sets", () => {
  const v = parseRego(`requirements := {"prod_deploy": {
	# who
	"from": ["deployments",],
	"value": \`prod\\n\`,
	"names": {"b", "a"},
	"none": set(),
	"n": -2.5e1, # trailing
}}`);
  assert.deepEqual(v, { prod_deploy: { from: ["deployments"], value: "prod\\n", names: ["b", "a"], none: [], n: -25 } });
  assert.deepEqual(parseRego("{}"), {});
  assert.deepEqual(parseRego("x = [true, false, null]"), [true, false, null]);
});

test("Rego that OPA wouldn't take gives an error with its place", () => {
  assert.throws(() => parseRego('{"a": [1, 2,, 3]}'), /unexpected input at line 1, column 13/);
  assert.throws(() => parseRego('{"a": 1,\n "a": 2}'), /"a" is given twice at line 2/);
  assert.throws(() => parseRego("{1: 2}"), /keys must be strings/);
  assert.throws(() => parseRego('{"a": 1} {}'), /unexpected input after the value/);
  assert.throws(() => parseRego('{"a": [1'), /expected , or \] at line 1, column 9/);
  assert.throws(() => parseRego('{"a" 1}'), /expected } at line 1, column 6/);
  assert.throws(() => parseRego("[01]"), /unexpected input/);
  assert.throws(() => parseRego(""), /unexpected end/);
});

test("a key called __proto__ stays a key", () => {
  const v = parseRego('{"__proto__": {"a": 1}}');
  assert.deepEqual(Object.keys(v), ["__proto__"]);
  assert.equal(Object.getPrototypeOf(v), Object.prototype);
  assert.deepEqual(JSON.parse(formats.json.write(v)), JSON.parse('{"__proto__": {"a": 1}}'));
});

test("keys are sorted by code point, as ergo sorts them", () => {
  assert.ok(byCodePoint("！", "😀") < 0);
  assert.deepEqual(Object.keys(sortKeys({ "😀": 1, "！": 2, b: 3, a: { d: 1, c: 2 } })), ["a", "b", "！", "😀"]);
  assert.deepEqual(Object.keys(sortKeys([{ y: 1, x: 2 }])[0]), ["x", "y"]);
});

test("times are read to the nanosecond, the same as OPA reads them", () => {
  for (const [time, ns] of [
    ["2026-05-01T10:00:00.123456789Z", "1777629600123456789"],
    ["1969-12-31T23:59:59.5Z", "-500000000"],
    ["1678-01-01T00:00:00Z", "-9214560000000000000"],
    ["2024-02-29T12:00:00+02:00", "1709200800000000000"],
  ]) assert.equal(JSON.stringify(parseTime(time)), ns, time);
});

test("a shared link gives back what was typed", async () => {
  const state = { r: "a: 1\n# 😀", rf: "rego", i: "{}", if: "yaml" };
  assert.deepEqual(await decodeState(await encodeState(state)), state);
});

test("a shared link with a format the page doesn't have is refused", async () => {
  for (const bad of [{ r: "", rf: "constructor", i: "", if: "json" }, { r: "", rf: "yaml", i: "", if: "rego" }, { r: 1, rf: "yaml", i: "", if: "json" }]) {
    await assert.rejects(async () => decodeState(await encodeState(bad)), /not a playground link/);
  }
  await assert.rejects(() => decodeState("not-base64!"));
});
