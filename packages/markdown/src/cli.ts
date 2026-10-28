#!/usr/bin/env node
import {readFileSync} from "node:fs";
import {stringify} from "yaml";
import {compile} from "./compile.ts";

export type Io = {
  stdout: (text: string) => void;
  stderr: (text: string) => void;
  readFile: (path: string) => string;
};

const USAGE = `usage:
  ergo compile <file>
  ergo check <file>
`;

export function main(argv: string[], io: Io): number {
  const [command, file] = argv;
  if ((command !== "compile" && command !== "check") || file === undefined || argv.length !== 2) {
    io.stderr(USAGE);
    return 2;
  }

  let markdown: string;
  try {
    markdown = io.readFile(file);
  } catch (error) {
    io.stderr(`cannot read ${file}: ${error instanceof Error ? error.message : String(error)}\n`);
    return 2;
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
  });
}
