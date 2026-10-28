import assert from "node:assert/strict";
import {existsSync, readdirSync, readFileSync} from "node:fs";
import {test} from "node:test";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {parse} from "yaml";
import {compile} from "../src/compile.ts";

const cases = fileURLToPath(new URL("../cases/", import.meta.url));
const names = existsSync(cases) ? readdirSync(cases, {withFileTypes: true}).filter((e) => e.isDirectory()).map((e) => e.name).sort() : [];

for (const name of names) {
  test(`case ${name} compiles as its expected files say`, () => {
    const file = (base: string) => join(cases, name, base);
    const {policy, problems} = compile(readFileSync(file("policy.ergo.md"), "utf8"));
    assert.notEqual(existsSync(file("policy.yaml")), existsSync(file("problems.json")));
    if (existsSync(file("policy.yaml"))) {
      assert.deepEqual(problems, []);
      assert.deepEqual(policy, parse(readFileSync(file("policy.yaml"), "utf8")));
    } else {
      assert.deepEqual(problems, JSON.parse(readFileSync(file("problems.json"), "utf8")));
      assert.equal(policy, null);
    }
  });
}
