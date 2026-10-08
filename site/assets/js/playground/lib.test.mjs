import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bakeryPolicy, byCodePoint, decodeState, encodeState, formats, parseRego, parseTime, showStatus, sortKeys, toRego, toYaml } from "./lib.mjs";
import opa from "../../playground/vendor/opa-wasm.mjs";

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

const roundTrips = (value, names = Object.keys(formats)) => {
  for (const from of names) {
    for (const to of names) {
      const once = formats[to].parse(formats[to].write(formats[from].parse(formats[from].write(value))));
      assert.deepEqual(once, value, `${from} → ${to}`);
    }
  }
};

test("the bakery policy comes out of the example file as it was written", () => {
  const written = bakeryFile.split("\n").slice(1).map((l) => l.slice(2)).join("\n");
  assert.equal(bakeryPolicy(bakeryFile), written);
});

test("every format reads back what every other format writes", () => {
  roundTrips(formats.yaml.parse(bakeryPolicy(bakeryFile)));
  roundTrips({ subjects: tricky, requirements: tricky });
  roundTrips(tricky, ["json", "yaml"]);
});

test("Rego refuses a policy it can't write as rules, and says why", () => {
  assert.throws(() => toRego(tricky), /Rego can't hold a section called "key with spaces"/);
  assert.throws(() => toRego({ input: {} }), /Rego can't hold a section called "input"/);
  for (const v of [{}, [], "x", null]) assert.throws(() => toRego(v), /Rego can only hold a policy with sections/);
});

test("lists of plain values are written on one line", () => {
  assert.equal(toYaml({ path: ["bake", "temp_c"], deep: [[1, 2]] }), "path: [bake, temp_c]\ndeep:\n- [1, 2]\n");
  assert.equal(toRego({ requirements: { path: ["bake", "temp_c"] } }), 'requirements := {\n\t"path": ["bake", "temp_c"],\n}\n');
});

test("the Rego it writes is formatted the way opa fmt formats it and means the same to OPA", () => {
  const dir = mkdtempSync(join(tmpdir(), "playground-"));
  const file = join(dir, "x.rego");
  const policy = { subjects: tricky, requirements: tricky };
  writeFileSync(file, `package x\n\n${toRego(policy)}`);
  assert.equal(execFileSync("opa", ["fmt", "--list", file], { encoding: "utf8" }), "");
  const read = JSON.parse(execFileSync("opa", ["eval", "-d", file, "--format", "raw", "data.x"], { encoding: "utf8" }));
  assert.deepEqual(read, policy);
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
  assert.deepEqual(v, { requirements: { prod_deploy: { from: ["deployments"], value: "prod\\n", names: ["b", "a"], none: [], n: -25 } } });
  assert.deepEqual(parseRego("{}"), {});
  assert.deepEqual(parseRego("[true, false, null]"), [true, false, null]);
  assert.deepEqual(parseRego("x = [true, false, null]"), { x: [true, false, null] });
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
  assert.throws(() => parseRego("a := 1\nb := 2\na := 3"), /a is given twice at line 3, column 1/);
  assert.throws(() => parseRego("a := 1\n{}"), /expected a rule like requirements := \{\.\.\.\} at line 2/);
  assert.throws(() => parseRego("a := 1\nreport := ergo.report(input, {}, {})"), /unexpected input at line 2/);
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
  const state = { p: "a: 1\n# 😀", pf: "rego", i: "{}", if: "yaml", a: "x: 1", af: "json" };
  assert.deepEqual(await decodeState(await encodeState(state)), state);
});

test("a shared link with a format the page doesn't have is refused", async () => {
  const ok = { p: "", pf: "yaml", i: "", if: "json", a: "", af: "json" };
  for (const bad of [{ pf: "constructor" }, { if: "rego" }, { af: "rego" }, { p: 1 }, { a: undefined }]) {
    await assert.rejects(async () => decodeState(await encodeState({ ...ok, ...bad })), /not a playground link/);
  }
  await assert.rejects(() => decodeState("not-base64!"));
});

test("a status ergo reports is shown as it is, and any other as not met", () => {
  assert.deepEqual(showStatus("met"), ["t", "met"]);
  assert.deepEqual(showStatus("not_met"), ["f", "not met"]);
  assert.deepEqual(showStatus("not_applicable"), ["muted", "not applicable"]);
  for (const s of [undefined, null, true, "MET", "constructor", "toString"]) assert.deepEqual(showStatus(s), ["f", "not met"], String(s));
});

test("the page's Wasm build gives the same report as opa eval", async () => {
  const wasm = join(repo, "site/assets/playground/ergo.wasm");
  const ergo = await opa.loadPolicy(readFileSync(wasm), undefined, { "time.parse_rfc3339_ns": parseTime });
  const dir = mkdtempSync(join(tmpdir(), "playground-"));
  writeFileSync(join(dir, "p.rego"), "package p\n\nimport data.ergo\n\nreport := ergo.report(input.input, input.policy, input.params)\n");
  const cases = {
    bakery: { input: JSON.parse(readFileSync(join(repo, "examples/baking/batches.json"), "utf8")), policy: formats.yaml.parse(bakeryPolicy(bakeryFile)), params: {} },
    params: {
      input: { items: [{ id: "a", n: 3, big: false }, { id: "b", n: 9, big: false }] },
      policy: {
        subjects: { item: { from: ["items"], id: ["id"] }, big: { of: "item", applies_to: { big: { op: "equals", path: ["big"], value: true } } } },
        requirements: {
          small: { description: "Items are small", meta: { control: "X-1" }, subject: "item", checks: { n: { op: "range", path: ["n"], min: 0, max: { ref: ["$$params", "max"] }, meta: { severity: 2 } } } },
          positive: { subject: "item", checks: { n: { op: "range", path: ["n"], min: 0, max: 100 } } },
          none_big: { subject: "big", min_subjects: 0, checks: { n: { op: "range", path: ["n"], min: 0, max: 100 } } },
        },
      },
      params: { max: 5 },
    },
    empty: { input: {}, policy: { subjects: {}, requirements: { r: { subject: "nope", checks: {} } } }, params: {} },
    "not a policy": { input: {}, policy: [], params: null },
  };
  for (const [name, c] of Object.entries(cases)) {
    writeFileSync(join(dir, "input.json"), JSON.stringify(c));
    const want = JSON.parse(execFileSync("opa", ["eval", "-d", join(repo, "ergo.rego"), "-d", join(dir, "p.rego"), "-i", join(dir, "input.json"), "--format", "raw", "data.p.report"], { encoding: "utf8" }));
    const got = ergo.evaluate(c)[0].result;
    assert.deepEqual(got, want, name);
    assert.notEqual(got.requirements, undefined, name);
  }
  const statuses = ergo.evaluate(cases.params)[0].result.requirements;
  assert.deepEqual([statuses.small.status, statuses.positive.status, statuses.none_big.status], ["not_met", "met", "not_applicable"]);
});
