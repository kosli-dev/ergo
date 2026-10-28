import type {Block} from "./compile.ts";
import type {ListItem, Nodes} from "mdast";
import {toString} from "mdast-util-to-string";
import {compile, parse} from "./compile.ts";
import {
  FIELD_ORDER,
  type PathProblem,
  checkLines,
  notBack,
  descriptionLines,
  fieldLine,
  frontMatterLines,
  itemLines,
  label,
  normalise,
  refusals,
  same,
} from "./render.ts";

export type Applied = {markdown: string | null; changes: string[]; problems: PathProblem[]};

type Json = Record<string, unknown>;
type Edit = {start: number; end: number; text: string; order: number};
type Kind = "subject" | "requirement";

const BULLET = /^(\s*(?:[-*+]|\d+[.)]) +)/;

const pairRenames = (before: string[], after: string[]): Map<string, string> => {
  const renames = new Map<string, string>();
  before.forEach((name, i) => {
    const next = after[i];
    if (!after.includes(name) && next !== undefined && !before.includes(next)) renames.set(name, next);
  });
  return renames;
};

export function apply(markdown: string, policy: object): Applied {
  const compiled = compile(markdown);
  if (compiled.problems.length > 0) {
    return {markdown: null, changes: [], problems: [{path: "", message: "fix the Markdown first"}]};
  }
  const problems = refusals(policy);
  if (problems.length > 0) return {markdown: null, changes: [], problems};

  const before = compiled.policy as Json;
  const after = normalise(policy) as Json;
  const blocks = compiled.blocks;
  const tree = parse(markdown);

  const lines = markdown.split("\n");
  const count = markdown.endsWith("\n") ? lines.length - 1 : lines.length;
  const starts: number[] = [];
  lines.reduce((offset, line) => (starts.push(offset), offset + line.length + 1), 0);
  const lineStart = (n: number): number => (n <= count ? starts[n - 1]! : markdown.length);
  const blank = (n: number): boolean => n >= 1 && n <= count && lines[n - 1]!.trim() === "";

  const edits: Edit[] = [];
  const changes: string[] = [];
  const removed = new Set<number>();
  const edit = (start: number, end: number, text: string) => edits.push({start, end, text, order: edits.length});
  const text = (block: string[]) => block.map((line) => `${line}\n`).join("");

  const replace = (first: number, last: number, block: string[]) =>
    edit(lineStart(first), lineStart(last + 1), text(block));

  const remove = (first: number, last: number) => {
    const from = blank(first - 1) && !removed.has(first - 1) && (last >= count || blank(last + 1)) ? first - 1 : first;
    for (let n = from; n <= last; n++) removed.add(n);
    edit(lineStart(from), lineStart(last + 1), "");
  };

  const insertAfter = (line: number, block: string[]) => {
    const open = line === count && !markdown.endsWith("\n") && count > 0 ? "\n" : "";
    edit(lineStart(line + 1), lineStart(line + 1), open + text(block));
  };

  const insertBlock = (line: number, block: string[]) =>
    insertAfter(line, [
      ...(line >= 1 && !blank(line) ? [""] : []),
      ...block,
      ...(line + 1 <= count && !blank(line + 1) ? [""] : []),
    ]);

  const lastKept = (from: number, floor: number): number => {
    let line = from;
    while (line > floor && (blank(line) || removed.has(line))) line--;
    return line;
  };

  const bulletOf = (block: Block): string => BULLET.exec(lines[block.startLine - 1]!)?.[1] ?? "- ";

  const itemAt = (line: number): ListItem | undefined => {
    let found: ListItem | undefined;
    const walk = (node: Nodes) => {
      if (node.type === "listItem" && node.position?.start.line === line) found ??= node;
      if ("children" in node) for (const child of node.children) walk(child);
    };
    walk(tree);
    return found;
  };

  const inside = (outer: Block, block: Block) => block.startLine > outer.startLine && block.startLine <= outer.endLine;
  const items = blocks.filter((b) => b.kind === "subject" || b.kind === "requirement");

  const describe = (path: string, old: Block | undefined, anchor: number, was: unknown, now: unknown) => {
    if (same(was, now)) return;
    const at = path === "" ? "the description" : `${path}.description`;
    if (now === undefined) {
      remove(old!.startLine, old!.endLine);
      changes.push(`removed ${at}`);
    } else if (old === undefined) {
      insertBlock(anchor, descriptionLines(now));
      changes.push(`added ${at}`);
    } else {
      replace(old.startLine, old.endLine, descriptionLines(now));
      changes.push(`rewrote ${at}`);
    }
  };

  const frontMatter = blocks.find((b) => b.kind === "front matter");
  if (!same(before.ergo_spec, after.ergo_spec)) {
    if (!("ergo_spec" in after)) {
      remove(frontMatter!.startLine, frontMatter!.endLine + (blank(frontMatter!.endLine + 1) ? 1 : 0));
      changes.push("removed ergo_spec");
    } else if (frontMatter === undefined) {
      insertBlock(0, frontMatterLines(after.ergo_spec));
      changes.push("added ergo_spec");
    } else {
      replace(frontMatter.startLine, frontMatter.endLine, frontMatterLines(after.ergo_spec));
      changes.push("rewrote ergo_spec");
    }
  }

  const title = blocks.find((b) => b.kind === "title");
  describe(
    "",
    blocks.find((b) => b.kind === "description" && !items.some((item) => inside(item, b))),
    title?.startLine ?? frontMatter?.endLine ?? 0,
    before.description,
    after.description,
  );

  const checks = (path: string, item: Block, last: number, was: unknown, now: unknown) => {
    if (same(was, now)) return;
    const own = blocks.filter((b) => b.kind === "check" && inside(item, b));
    if (now === undefined) {
      remove(blocks.find((b) => b.kind === "checks" && inside(item, b))!.startLine, own[own.length - 1]!.endLine);
      changes.push(`removed ${path}.checks`);
      return;
    }
    const target = now as Json;
    if (was === undefined) {
      insertBlock(lastKept(last, item.startLine), [
        "Checks:",
        "",
        ...Object.entries(target).flatMap(([name, body]) => checkLines(name, body)),
      ]);
      changes.push(`added ${path}.checks`);
      return;
    }
    const old = was as Json;
    const renames = pairRenames(Object.keys(old), Object.keys(target));
    for (const block of own) {
      const name = block.name!;
      const renamed = renames.get(name);
      if (renamed !== undefined) {
        replace(block.startLine, block.endLine, checkLines(renamed, target[renamed], bulletOf(block)));
        changes.push(`renamed check ${path}.${name} to ${path}.${renamed}`);
      } else if (!(name in target)) {
        remove(block.startLine, block.endLine);
        changes.push(`removed check ${path}.${name}`);
      } else if (!same(old[name], target[name])) {
        replace(block.startLine, block.endLine, checkLines(name, target[name], bulletOf(block)));
        changes.push(`rewrote ${path}.${name}`);
      }
    }
    const added = Object.keys(target).filter((name) => !(name in old) && ![...renames.values()].includes(name));
    if (added.length === 0) return;
    const anchor = own.filter((b) => !removed.has(b.startLine)).pop()!;
    insertAfter(anchor.endLine, added.flatMap((name) => checkLines(name, target[name], bulletOf(anchor))));
    for (const name of added) changes.push(`added check ${path}.${name}`);
  };

  const fields = (kind: Kind, path: string, item: Block, anchor: number, was: Json, now: Json): number => {
    const own = blocks.filter((b) => b.kind === "field" && inside(item, b));
    const added: string[] = [];
    for (const key of FIELD_ORDER[kind]) {
      const word = key.replace("_", " ");
      const block = own.find((b) => b.name!.replaceAll(" ", "_") === key);
      if (same(was[key], now[key])) continue;
      if (!(key in now)) {
        remove(block!.startLine, block!.endLine);
        changes.push(`removed ${path}.${word}`);
      } else if (block === undefined) {
        added.push(key);
        changes.push(`added ${path}.${word}`);
      } else {
        const code = itemAt(block.startLine)!.children[0]!;
        const span = "children" in code ? code.children.find((n) => n.type === "inlineCode")! : code;
        edit(span.position!.start.offset!, span.position!.end.offset!, `\`${String(now[key])}\``);
        changes.push(`rewrote ${path}.${word}`);
      }
    }
    const kept = own.filter((b) => !removed.has(b.startLine));
    const last = kept[kept.length - 1];
    if (added.length > 0 && last !== undefined) {
      insertAfter(last.endLine, added.map((key) => fieldLine(key, now[key], bulletOf(last))));
    } else if (added.length > 0) {
      insertBlock(lastKept(anchor, item.startLine), added.map((key) => fieldLine(key, now[key])));
    }
    return last?.endLine ?? anchor;
  };

  const diffItem = (kind: Kind, name: string, item: Block, was: Json, now: Json) => {
    const description = blocks.find((b) => b.kind === "description" && inside(item, b));
    describe(name, description, item.startLine, was.description, now.description);
    const last = fields(kind, name, item, description?.endLine ?? item.startLine, was, now);
    if (kind === "requirement") checks(name, item, last, was.checks, now.checks);
  };

  const headings = tree.children.flatMap((node) =>
    node.type === "heading" && node.depth <= 2
      ? [{depth: node.depth, text: toString(node).trim(), line: node.position!.start.line}]
      : [],
  );

  for (const [key, kind, section] of [
    ["subjects", "subject", "Subjects"],
    ["requirements", "requirement", "Requirements"],
  ] as const) {
    const was = before[key] as Json;
    const now = after[key] as Json;
    const renames = pairRenames(Object.keys(was), Object.keys(now));
    for (const item of items.filter((b) => b.kind === kind)) {
      const name = item.name!;
      const renamed = renames.get(name);
      if (renamed !== undefined) {
        replace(item.startLine, item.startLine, [`### ${label(renamed).replace(/#/g, "\\#")}`]);
        changes.push(`renamed ${kind} ${name} to ${renamed}`);
        diffItem(kind, renamed, item, was[name] as Json, now[renamed] as Json);
      } else if (name in now) {
        diffItem(kind, name, item, was[name] as Json, now[name] as Json);
      } else {
        remove(item.startLine, item.endLine);
        changes.push(`removed ${kind} ${name}`);
      }
    }
    const added = Object.keys(now).filter((name) => !(name in was) && ![...renames.values()].includes(name));
    if (added.length === 0) continue;
    const block = added.flatMap((name, i) => [...(i === 0 ? [] : [""]), ...itemLines(kind, name, now[name] as Json)]);
    for (const name of added) changes.push(`added ${kind} ${name}`);
    const heading = headings.filter((h) => h.depth === 2 && h.text === section).pop();
    if (heading !== undefined) {
      const next = headings.find((h) => h.line > heading.line)?.line ?? count + 1;
      insertBlock(lastKept(next - 1, heading.line), block);
      continue;
    }
    const requirements = headings.filter((h) => h.depth === 2 && h.text === "Requirements").pop();
    const end = kind === "subject" && requirements !== undefined ? requirements.line - 1 : count;
    insertBlock(lastKept(end, 0), [`## ${section}`, "", ...block]);
  }

  edits.sort((a, b) => b.start - a.start || b.end - a.end || b.order - a.order);
  let out = markdown;
  for (const e of edits) out = out.slice(0, e.start) + e.text + out.slice(e.end);
  if (markdown.endsWith("\n") && !markdown.endsWith("\n\n")) out = out.replace(/\n+$/, "\n");

  const back = notBack(out, policy);
  return back.length > 0 ? {markdown: null, changes: [], problems: back} : {markdown: out, changes, problems: []};
}
