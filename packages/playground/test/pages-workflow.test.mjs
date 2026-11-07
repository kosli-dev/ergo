import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve, sep } from "node:path";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const check = (workflow) => {
  const steps = workflow.jobs.build.steps;
  const command = "pnpm --filter @kosli/ergo-playground test";
  const index = steps.findIndex((step) => step.run === command);
  assert.ok(index >= 0, "Pages must test the staged playground before deployment");
  const step = steps[index];
  assert.equal(step["working-directory"], "${{ runner.temp }}/playground/packages");
  assert.equal(step.env?.ERGO_PLAYGROUND_SAMPLE_CASES, "${{ runner.temp }}/playground/packages/playground/sample-cases.json");
  assert.ok(!step.if && !step["continue-on-error"], "staged tests must run and stop a failed build");
  const build = steps.findIndex((step) => step.run?.includes("pnpm --filter @kosli/ergo-playground build"));
  const publish = steps.findIndex((step) => step.uses?.startsWith("actions/upload-pages-artifact@"));
  const opa = steps.findIndex((step) => step.uses?.startsWith("open-policy-agent/setup-opa@"));
  assert.ok(opa >= 0 && opa < build && build < index && index < publish);
};

test("Pages tests the staged interface against released engines before publishing it", { skip: Boolean(process.env.ERGO_PLAYGROUND_SAMPLE_CASES) }, () => {
  const workflow = parse(readFileSync(new URL("../../../.github/workflows/pages.yml", import.meta.url), "utf8"));
  check(workflow);
  const missing = structuredClone(workflow);
  missing.jobs.build.steps = missing.jobs.build.steps.filter((step) => step.run !== "pnpm --filter @kosli/ergo-playground test");
  assert.throws(() => check(missing), /Pages must test/);
  const ignored = structuredClone(workflow);
  ignored.jobs.build.steps.find((step) => step.run === "pnpm --filter @kosli/ergo-playground test")["continue-on-error"] = true;
  assert.throws(() => check(ignored), /staged tests must run/);
});

test("Pages gives pnpm setup a manifest it can read from the workspace", { skip: Boolean(process.env.ERGO_PLAYGROUND_SAMPLE_CASES) }, () => {
  const root = fileURLToPath(new URL("../../../", import.meta.url));
  const workflow = parse(readFileSync(new URL("../../../.github/workflows/pages.yml", import.meta.url), "utf8"));
  const step = workflow.jobs.build.steps.find((step) => step.uses?.startsWith("pnpm/action-setup@"));
  const input = step.with.package_json_file.replace("${{ runner.temp }}", tmpdir());
  const manifest = JSON.parse(readFileSync(join(root, input), "utf8"));
  assert.match(manifest.packageManager, /^pnpm@.+$/);
});

test("Pages gives Node setup a lockfile it can hash inside the workspace", { skip: Boolean(process.env.ERGO_PLAYGROUND_SAMPLE_CASES) }, () => {
  const root = resolve(fileURLToPath(new URL("../../../", import.meta.url)));
  const workflow = parse(readFileSync(new URL("../../../.github/workflows/pages.yml", import.meta.url), "utf8"));
  const step = workflow.jobs.build.steps.find((step) => step.uses?.startsWith("actions/setup-node@") && step.with?.cache === "pnpm");
  const input = step.with["cache-dependency-path"].replace("${{ runner.temp }}", tmpdir());
  const file = resolve(root, input);
  const hash = file.startsWith(`${root}${sep}`) ? createHash("sha256").update(readFileSync(file)).digest("hex") : "";
  assert.notEqual(hash, "", "Node setup ignores cache files outside GITHUB_WORKSPACE");
  assert.equal(hash, createHash("sha256").update(readFileSync(new URL("../../pnpm-lock.yaml", import.meta.url))).digest("hex"));
});
