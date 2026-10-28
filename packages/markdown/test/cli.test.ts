import assert from "node:assert/strict";
import {execFileSync, spawnSync} from "node:child_process";
import {test} from "node:test";
import {parse} from "yaml";
import {main} from "../src/cli.ts";
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
  });
  assert.equal(result, 2);
});

test("the command line entry point runs the real program", () => {
  const file = new URL("../src/cli.ts", import.meta.url).pathname;
  const bad = spawnSync("node", [file, "check", "/dev/stdin"], {input: "# A\n\n# B\n", encoding: "utf8"});
  assert.equal(bad.status, 1);
  assert.equal(bad.stderr, "/dev/stdin:3: a policy has one # title\n");
  const usage = spawnSync("node", [file], {encoding: "utf8"});
  assert.equal(usage.status, 2);
  const out = execFileSync("node", [file, "compile", "/dev/stdin"], {input: CAKE, encoding: "utf8"});
  assert.deepEqual(parse(out), CAKE_POLICY);
});
