import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const require = createRequire(import.meta.url);

const cases = join(root, "packages", "markdown", "cases");
export const sampleCases = {
  bakery: "baking",
  "any of": "any-of-licences",
  "for line": "for-line-peer-approval",
  "getting started": "getting-started",
  "no bold label": "check-without-bold-label",
  "paragraph between checks": "check-after-a-paragraph",
  "mistyped fields": "mistyped-fields",
  "long descriptions": "descriptions-over-paragraphs",
  "long check description": "check-description-over-paragraphs",
};

const readJson = (path, fallback) => (existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : fallback);

export const readSample = (dir) => ({
  source: readFileSync(join(cases, dir, "policy.ergo.md"), "utf8"),
  input: readJson(join(cases, dir, "input.json"), {}),
  params: readJson(join(cases, dir, "params.json"), {}),
});

const escapeJson = (value) =>
  JSON.stringify(value)
    .replace(/</g, "\\u003c")
    .replace(/[\u0080-￿]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));

export const opaVersionNote = (versionOutput, readme) => {
  const used = /^Version: (\S+)/m.exec(versionOutput)?.[1] ?? "an unknown version";
  const tested = /we test Ergo with OPA (\d+\.\d+\.\d+)/.exec(readme)?.[1];
  const note = `Built Ergo to Wasm with OPA ${used}.`;
  return used === tested ? note : `${note} Warning: the README says we test Ergo with OPA ${tested ?? "(not found)"}.`;
};

const buildWasm = () => {
  console.log(opaVersionNote(execFileSync("opa", ["version"], { encoding: "utf8" }), readFileSync(join(root, "README.md"), "utf8")));
  const dir = mkdtempSync(join(tmpdir(), "ergo-editor-"));
  try {
    mkdirSync(join(dir, "src"));
    copyFileSync(join(root, "ergo.rego"), join(dir, "src", "ergo.rego"));
    writeFileSync(
      join(dir, "src", "editor.rego"),
      "package editor\n\nimport data.ergo\n\nreport := ergo.report(input.input, input.policy, input.params)\n",
    );
    execFileSync("opa", ["build", "-t", "wasm", "-e", "editor/report", "-o", join(dir, "bundle.tar.gz"), join(dir, "src")], { stdio: "inherit" });
    execFileSync("tar", ["-xzf", join(dir, "bundle.tar.gz"), "-C", dir, "/policy.wasm"], { stdio: "ignore" });
    return readFileSync(join(dir, "policy.wasm")).toString("base64");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

export const buildEditor = async (out = join(here, "dist", "editor.html")) => {
  const opaWasm = join(dirname(require.resolve("@open-policy-agent/opa-wasm")), "..", "dist", "opa-wasm-browser.esm.js");
  const bundled = await build({
    entryPoints: [join(here, "src", "main.mjs")],
    bundle: true,
    write: false,
    format: "iife",
    platform: "browser",
    target: "es2022",
    minify: true,
    alias: { "@open-policy-agent/opa-wasm": opaWasm },
  });
  const script = bundled.outputFiles[0].text.replace(/<\/script/gi, "<\\/script");
  const samples = Object.fromEntries(Object.entries(sampleCases).map(([name, dir]) => [name, readSample(dir)]));
  const template = readFileSync(join(here, "src", "index.template.html"), "utf8");
  const html = template
    .replace("__SAMPLES__", () => escapeJson(samples))
    .replace("__WASM__", () => buildWasm())
    .replace("__BUNDLE__", () => script);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, html);
  return { out, bytes: Buffer.byteLength(html) };
};

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { out, bytes } = await buildEditor();
  console.log(`${out} ${(bytes / 1024).toFixed(0)} KB`);
}
