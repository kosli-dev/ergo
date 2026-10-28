import assert from "node:assert/strict";
import {execFileSync, spawnSync} from "node:child_process";
import {mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {test} from "node:test";
import {parse, stringify} from "yaml";
import {main} from "../src/cli.ts";
import {compile} from "../src/compile.ts";
import {CAKE, CAKE_POLICY} from "./helpers.ts";

const run = (argv: string[], files: Record<string, string> = {}) => {
  let out = "";
  let err = "";
  const code = main(argv, {
    stdout: (t) => (out += t),
    stderr: (t) => (err += t),
    readFile: (path) => {
      const text = files[path];
      if (text === undefined) throw new Error("no such file");
      return text;
    },
    writeFile: (path, text) => {
      files[path] = text;
    },
  });
  return {code, out, err};
};

test("compile prints the policy as yaml and exits 0", () => {
  const {code, out, err} = run(["compile", "p.ergo.md"], {"p.ergo.md": CAKE});
  assert.equal(code, 0);
  assert.equal(err, "");
  assert.deepEqual(parse(out), CAKE_POLICY);
  assert.match(out, /^ergo_spec: v0\.2\ndescription: Every batch/);
});

test("compile does not wrap long lines", () => {
  const long = "word ".repeat(60).trim();
  const {out} = run(["compile", "p"], {p: `# T\n\n${long}\n`});
  assert.equal(out, `description: ${long}\nsubjects: {}\nrequirements: {}\n`);
});

test("compile prints problems on stderr and exits 1", () => {
  const {code, out, err} = run(["compile", "p"], {p: "# A\n\n# B\n"});
  assert.equal(code, 1);
  assert.equal(out, "");
  assert.equal(err, "p:3: a policy has one # title\n");
});

test("check prints nothing and exits 0 when there are no problems", () => {
  assert.deepEqual(run(["check", "p"], {p: CAKE}), {code: 0, out: "", err: ""});
});

test("check prints each problem as file, line and message and exits 1", () => {
  const {code, out, err} = run(["check", "p"], {p: "# A\n\n# B\n\n### x\n"});
  assert.equal(code, 1);
  assert.equal(out, "");
  assert.equal(err, "p:3: a policy has one # title\np:5: ### x is under no ## section\n");
});

test("an unknown command prints usage and exits 2", () => {
  const {code, err} = run(["explain", "p"]);
  assert.equal(code, 2);
  assert.match(err, /^usage:/);
});

test("no command or no file prints usage and exits 2", () => {
  assert.equal(run([]).code, 2);
  assert.equal(run(["compile"]).code, 2);
  assert.equal(run(["check"]).code, 2);
});

test("an extra argument prints usage and exits 2", () => {
  assert.equal(run(["check", "a", "b"]).code, 2);
});

test("a file that cannot be read gives one line on stderr and exits 2", () => {
  assert.deepEqual(run(["check", "missing.md"]), {code: 2, out: "", err: "cannot read missing.md: no such file\n"});
});

test("a thrown value that is not an error is still reported", () => {
  const result = main(["check", "p"], {
    stdout: () => {},
    stderr: () => {},
    readFile: () => {
      throw "boom";
    },
    writeFile: () => {},
  });
  assert.equal(result, 2);
});

test("render prints the policy as Markdown and exits 0", () => {
  const {code, out, err} = run(["render", "p.yaml"], {"p.yaml": stringify(CAKE_POLICY)});
  assert.equal(err, "");
  assert.equal(code, 0);
  assert.deepEqual(compile(out).policy, CAKE_POLICY);
});

test("render reads JSON as well as YAML", () => {
  assert.equal(run(["render", "p.json"], {"p.json": '{"subjects": {}, "requirements": {}}'}).out, "## Subjects\n\n## Requirements\n");
});

test("render prints each refusal with its path and exits 1", () => {
  const {code, out, err} = run(["render", "p.yaml"], {"p.yaml": "subjects:\n  Batch: {has: {}}\n"});
  assert.equal(code, 1);
  assert.equal(out, "");
  assert.equal(err, "subjects.Batch: has upper case\nsubjects.Batch.has: the Markdown can't hold parts yet: write this policy in YAML\n");
});

test("a policy file that isn't YAML gives one line on stderr and exits 2", () => {
  const {code, err} = run(["render", "p.yaml"], {"p.yaml": "a: [\n"});
  assert.equal(code, 2);
  assert.match(err, /^cannot read p\.yaml: /);
});

test("apply rewrites the file in place and prints the changes", () => {
  const policy = structuredClone(CAKE_POLICY) as any;
  policy.subjects.batch.from = "today.batches";
  const files: Record<string, string> = {"p.ergo.md": CAKE, "p.yaml": stringify(policy)};
  const {code, out, err} = run(["apply", "p.ergo.md", "p.yaml"], files);
  assert.deepEqual({code, out, err}, {code: 0, out: "rewrote batch.from\n", err: ""});
  assert.equal(files["p.ergo.md"], CAKE.replace("`batches`", "`today.batches`"));
});

test("apply with nothing to change leaves the file and says so", () => {
  const files: Record<string, string> = {"p.ergo.md": CAKE, "p.yaml": stringify(CAKE_POLICY)};
  let wrote = false;
  const code = main(["apply", "p.ergo.md", "p.yaml"], {
    stdout: (t) => assert.equal(t, "no changes\n"),
    stderr: () => assert.fail(),
    readFile: (path) => files[path]!,
    writeFile: () => (wrote = true),
  });
  assert.equal(code, 0);
  assert.equal(wrote, false);
});

test("apply prints the problems and not written, and exits 1", () => {
  const files: Record<string, string> = {"p.ergo.md": "# A\n\n# B\n", "p.yaml": "{}"};
  assert.deepEqual(run(["apply", "p.ergo.md", "p.yaml"], files), {code: 1, out: "", err: "fix the Markdown first\nnot written\n"});
  assert.equal(files["p.ergo.md"], "# A\n\n# B\n");
});

test("apply needs two files, and render one", () => {
  assert.equal(run(["apply", "p.ergo.md"]).code, 2);
  assert.equal(run(["render", "a", "b"]).code, 2);
  assert.equal(run(["toString", "a"]).code, 2);
});

test("the command line entry point runs the real program", () => {
  const file = new URL("../src/cli.ts", import.meta.url).pathname;
  const dir = mkdtempSync(join(tmpdir(), "ergo-markdown-"));
  try {
    writeFileSync(join(dir, "bad.ergo.md"), "# A\n\n# B\n");
    writeFileSync(join(dir, "cake.ergo.md"), CAKE);
    const bad = spawnSync("node", [file, "check", "bad.ergo.md"], {cwd: dir, encoding: "utf8"});
    assert.equal(bad.status, 1);
    assert.equal(bad.stderr, "bad.ergo.md:3: a policy has one # title\n");
    const usage = spawnSync("node", [file], {encoding: "utf8"});
    assert.equal(usage.status, 2);
    const out = execFileSync("node", [file, "compile", "cake.ergo.md"], {cwd: dir, encoding: "utf8"});
    assert.deepEqual(parse(out), CAKE_POLICY);
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
});
