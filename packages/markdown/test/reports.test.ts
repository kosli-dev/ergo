import {test} from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {compile} from "../src/compile.ts";

const cases = fileURLToPath(new URL("../cases/", import.meta.url));
const ergo = fileURLToPath(new URL("../../../engines/rego/ergo.rego", import.meta.url));

const report = (policy: unknown, params: unknown, input: string): string => {
  const dir = mkdtempSync(join(tmpdir(), "ergo-markdown-"));
  try {
    mkdirSync(join(dir, "policy"));
    mkdirSync(join(dir, "params"));
    writeFileSync(join(dir, "policy", "data.json"), JSON.stringify(policy));
    writeFileSync(join(dir, "params", "data.json"), JSON.stringify(params));
    const out = execFileSync("opa", ["eval", "--format", "json", "-d", ergo, "-d", dir, "-i", input, "data.ergo.report(input, data.policy, data.params)"], {encoding: "utf8"});
    return JSON.stringify(JSON.parse(out).result[0].expressions[0].value, null, 2) + "\n";
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
};

const withReports = existsSync(cases) ? readdirSync(cases).filter((name) => existsSync(join(cases, name, "report.json"))).sort() : [];

for (const name of withReports) {
  test(`the policy compiled from case ${name} gives its report, byte for byte`, () => {
    const dir = join(cases, name);
    const {policy, problems} = compile(readFileSync(join(dir, "policy.ergo.md"), "utf8"));
    assert.deepEqual(problems, []);
    const params = existsSync(join(dir, "params.json")) ? JSON.parse(readFileSync(join(dir, "params.json"), "utf8")) : {};
    assert.equal(report(policy, params, join(dir, "input.json")), readFileSync(join(dir, "report.json"), "utf8"));
  });
}
