import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const readCatalogue = (path) => {
  const env = { ...process.env };
  delete env.ERGO_PLAYGROUND_SAMPLE_CASES;
  if (path) env.ERGO_PLAYGROUND_SAMPLE_CASES = path;
  return execFileSync(process.execPath, ["--input-type=module", "-e", 'import { sampleCases } from "./build.mjs"; console.log(JSON.stringify(sampleCases));'], {
    cwd: new URL("..", import.meta.url), env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
};

test("local builds use the working tree's sample catalogue", () => {
  assert.equal(JSON.parse(readCatalogue()).bakery, "baking");
});

test("a released sample catalogue replaces main's catalogue completely", () => {
  const dir = mkdtempSync(join(tmpdir(), "ergo-samples-"));
  try {
    const path = join(dir, "samples.json");
    const released = { "released bakery": "released-baking" };
    writeFileSync(path, JSON.stringify(released));
    assert.deepEqual(JSON.parse(readCatalogue(path)), released);
    writeFileSync(path, "{");
    assert.throws(() => readCatalogue(path));
    assert.throws(() => readCatalogue(join(dir, "missing.json")));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
