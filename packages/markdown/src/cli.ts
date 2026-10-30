#!/usr/bin/env node
import {readFileSync, writeFileSync} from "node:fs";
import {parse, stringify} from "yaml";
import {apply} from "./apply.ts";
import {compile} from "./compile.ts";
import {type PathProblem, render} from "./render.ts";

/** What the command line needs from outside: where to print, and how to read and write files. Tests pass fakes. */
export type Io = {
  stdout: (text: string) => void;
  stderr: (text: string) => void;
  readFile: (path: string) => string;
  writeFile: (path: string, text: string) => void;
};

const USAGE = `usage:
  ergo compile <file>
  ergo check <file>
  ergo render <policy>
  ergo apply <file> <policy>
`;

const ARGUMENTS: Record<string, number> = {compile: 1, check: 1, render: 1, apply: 2};

const told = (problems: PathProblem[]): string =>
  problems.map((p) => `${p.path === "" ? "" : `${p.path}: `}${p.message}\n`).join("");

/**
 * Runs one command and returns its exit code.
 *
 * The commands are `compile <file>`, `check <file>`, `render <policy>` and `apply <file> <policy>`. It returns 0 on success, 1 when the Markdown or policy has problems (they go to `stderr`, and nothing is written), and 2 for a wrong command or a file it can't read.
 */
export function main(argv: string[], io: Io): number {
  const [command, ...files] = argv;
  if (command === undefined || !Object.hasOwn(ARGUMENTS, command) || files.length !== ARGUMENTS[command]) {
    io.stderr(USAGE);
    return 2;
  }

  const texts: string[] = [];
  for (const file of files) {
    try {
      texts.push(io.readFile(file));
    } catch (error) {
      io.stderr(`cannot read ${file}: ${error instanceof Error ? error.message : String(error)}\n`);
      return 2;
    }
  }
  const file = files[0]!;
  const markdown = texts[0]!;

  if (command === "render" || command === "apply") {
    const policyFile = files[files.length - 1]!;
    let policy: object;
    try {
      policy = parse(texts[texts.length - 1]!);
    } catch (error) {
      io.stderr(`cannot read ${policyFile}: ${(error as Error).message}\n`);
      return 2;
    }
    if (command === "render") {
      const rendered = render(policy);
      if (rendered.markdown === null) {
        io.stderr(told(rendered.problems));
        return 1;
      }
      io.stdout(rendered.markdown);
      return 0;
    }
    const unread = compile(markdown).problems;
    if (unread.length > 0) {
      io.stderr(`${unread.map((p) => `${file}:${p.line}: ${p.message}\n`).join("")}not written\n`);
      return 1;
    }
    const applied = apply(markdown, policy);
    if (applied.markdown === null) {
      io.stderr(`${told(applied.problems)}not written\n`);
      return 1;
    }
    if (applied.changes.length > 0) io.writeFile(file, applied.markdown);
    io.stdout(applied.changes.length > 0 ? applied.changes.map((c) => `${c}\n`).join("") : "no changes\n");
    return 0;
  }

  const {policy, problems} = compile(markdown);
  if (problems.length > 0) {
    io.stderr(problems.map((p) => `${file}:${p.line}: ${p.message}\n`).join(""));
    return 1;
  }
  if (command === "compile") io.stdout(stringify(policy, {lineWidth: 0}));
  return 0;
}

if (import.meta.main) {
  process.exitCode = main(process.argv.slice(2), {
    stdout: (text) => process.stdout.write(text),
    stderr: (text) => process.stderr.write(text),
    readFile: (path) => readFileSync(path, "utf8"),
    writeFile: (path, text) => writeFileSync(path, text),
  });
}
