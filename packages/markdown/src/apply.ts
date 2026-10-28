import type {Block} from "./compile.ts";
import type {List, ListItem, Nodes, Paragraph, Text} from "mdast";
import {toString} from "mdast-util-to-string";
import {compile, nameOf, parse, plain} from "./compile.ts";
import {
  FIELD_ORDER,
  type Kept,
  type PathProblem,
  checkLines,
  isObject,
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

const pairRenames = (was: Json, now: Json): Map<string, string> => {
  const before = Object.keys(was);
  const after = Object.keys(now);
  const renames = new Map<string, string>();
  before.forEach((name, i) => {
    const next = after[i];
    if (!after.includes(name) && next !== undefined && !before.includes(next)) renames.set(name, next);
  });
  const lost = before.filter((name) => !after.includes(name) && !renames.has(name));
  const gained = after.filter((name) => !before.includes(name) && ![...renames.values()].includes(name));
  if (lost.length === 1 && gained.length === 1 && same(was[lost[0]!], now[gained[0]!])) renames.set(lost[0]!, gained[0]!);
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

  const slice = (node: Nodes): string => markdown.slice(node.position!.start.offset!, node.position!.end.offset!);

  const descriptionOf = (li: ListItem) => {
    const first = li.children[0] as Paragraph;
    const colon = first.children[1]!.position!.start.offset!;
    const paragraphs: Paragraph[] = [first];
    for (let k = 1; li.children[k]?.type === "paragraph"; k++) paragraphs.push(li.children[k] as Paragraph);
    const found: {text: string; start: number; end: number}[] = [];
    let coded = false;
    paragraphs.forEach((para, j) => {
      if (coded) return;
      const colonNode = para.children[1] as Text;
      const nodes = j === 0 ? [{...colonNode, value: colonNode.value.slice(1)}, ...para.children.slice(2)] : para.children;
      const at = nodes.findIndex((node) => node.type === "inlineCode");
      const before = at < 0 ? nodes : nodes.slice(0, at);
      coded = at >= 0;
      const text = plain(before);
      if (text === "") return;
      const from = j === 0 ? colon + 1 : para.position!.start.offset!;
      const start = from + /^\s*/.exec(markdown.slice(from))![0].length;
      const last = before[before.length - 1]!;
      found.push({text, start, end: start + markdown.slice(start, last.position!.end.offset!).trimEnd().length});
    });
    return {found, colon};
  };

  const keptOf = (block: Block, was: Json, now: Json, renamed: string | undefined): Kept => {
    const li = itemAt(block.startLine)!;
    const strongOf = (item: ListItem) => (item.children[0] as {children: Nodes[]}).children[0]!;
    const strong = slice(strongOf(li));
    const nested = li.children.find((child): child is List => child.type === "list");
    const options = new Map((nested?.children ?? []).map((option) => [nameOf(toString(strongOf(option))), slice(strongOf(option))]));
    const wanted = renamed === undefined ? strong : `**${label(renamed)}**`;
    const relabel = (text: string) => text.replace(strong, () => wanted);
    if (same(was.description, now.description)) {
      const codes = codesOf(li);
      const boundary = (codes[0] ?? nested)!.position!.start.offset!;
      const before = markdown.slice(lineStart(block.startLine), boundary);
      const trimmed = before.replace(/\s+$/, "");
      return {head: relabel(trimmed).split("\n"), sameLine: !before.slice(trimmed.length).includes("\n"), options};
    }
    const {found, colon} = descriptionOf(li);
    const wantedTexts = typeof now.description === "string" ? now.description.split("\n\n") : [];
    const keeps = (i: number) => found[i]?.text === wantedTexts[i];
    const equalCount = found.length === wantedTexts.length;
    let prefix = 0;
    while (prefix < wantedTexts.length && keeps(prefix)) prefix++;
    const paragraphs = wantedTexts.map((text, i) =>
      (equalCount ? keeps(i) : i < prefix) ? markdown.slice(found[i]!.start, found[i]!.end) : descriptionLines(text)[0]!,
    );
    const bullet = BULLET.exec(lines[block.startLine - 1]!)?.[1] ?? "- ";
    const pad = " ".repeat(bullet.length);
    const opening = relabel(markdown.slice(lineStart(block.startLine), colon + 1));
    const head = [`${opening}${paragraphs.length > 0 ? ` ${paragraphs[0]}` : ""}`];
    for (const text of paragraphs.slice(1)) head.push("", `${pad}${text}`);
    return {head, options};
  };

  const sentencesOf = (value: unknown): unknown[] => (value === undefined ? [] : Array.isArray(value) ? value : [value]);

  const codesOf = (item: ListItem) =>
    item.children.flatMap((child) => (child.type === "paragraph" ? child.children : [])).filter((n) => n.type === "inlineCode");

  const inPlace = (block: Block, was: Json, now: Json): boolean => {
    const options = (check: Json) => (isObject(check.any_of) ? check.any_of : {});
    const wasOptions = options(was);
    const nowOptions = options(now);
    const shaped =
      same(was.description, now.description) &&
      ("for" in was) === ("for" in now) &&
      ("any_of" in was) === ("any_of" in now) &&
      sentencesOf(was.assert).length === sentencesOf(now.assert).length &&
      same(Object.keys(wasOptions).sort(), Object.keys(nowOptions).sort()) &&
      Object.keys(wasOptions).every((o) => sentencesOf(wasOptions[o]).length === sentencesOf(nowOptions[o]).length);
    if (!shaped) return false;
    const rewrite = (code: Nodes & {value: string}, value: string) => {
      if (value !== code.value) edit(code.position!.start.offset!, code.position!.end.offset!, `\`${value}\``);
    };
    const li = itemAt(block.startLine)!;
    const asserts = sentencesOf(now.assert) as string[];
    let k = 0;
    for (const code of codesOf(li)) rewrite(code, code.value.startsWith("for ") ? `for ${now.for}` : asserts[k++]!);
    for (const option of li.children.find((child): child is List => child.type === "list")?.children ?? []) {
      const strong = (option.children[0] as {children: Nodes[]}).children[0]!;
      const sentences = sentencesOf(nowOptions[nameOf(toString(strong))]) as string[];
      codesOf(option).forEach((code, i) => rewrite(code, sentences[i]!));
    }
    return true;
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
      const paragraphs = tree.children.filter(
        (node): node is Paragraph =>
          node.type === "paragraph" && node.position!.start.line >= old.startLine && node.position!.end.line <= old.endLine,
      );
      const wasTexts = paragraphs.map((node) => plain(node.children));
      const nowTexts = (now as string).split("\n\n");
      if (wasTexts.length === nowTexts.length) {
        paragraphs.forEach((node, i) => {
          if (wasTexts[i] !== nowTexts[i]) replace(node.position!.start.line, node.position!.end.line, descriptionLines(nowTexts[i]));
        });
      } else {
        let kept = 0;
        while (kept < Math.min(wasTexts.length, nowTexts.length) && wasTexts[kept] === nowTexts[kept]) kept++;
        const rest = descriptionLines(nowTexts.slice(kept).join("\n\n"));
        if (kept === nowTexts.length) remove(paragraphs[kept]!.position!.start.line, old.endLine);
        else if (kept === wasTexts.length) insertAfter(old.endLine, ["", ...rest]);
        else replace(paragraphs[kept]!.position!.start.line, old.endLine, rest);
      }
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
    const renames = pairRenames(old, target);
    for (const block of own) {
      const name = block.name!;
      const renamed = renames.get(name);
      if (renamed !== undefined) {
        const kept = keptOf(block, old[name] as Json, target[renamed] as Json, renamed);
        replace(block.startLine, block.endLine, checkLines(renamed, target[renamed], bulletOf(block), kept));
        changes.push(`renamed check ${path}.${name} to ${path}.${renamed}`);
      } else if (!(name in target)) {
        remove(block.startLine, block.endLine);
        changes.push(`removed check ${path}.${name}`);
      } else if (!same(old[name], target[name])) {
        if (!inPlace(block, old[name] as Json, target[name] as Json)) {
          const kept = keptOf(block, old[name] as Json, target[name] as Json, undefined);
          replace(block.startLine, block.endLine, checkLines(name, target[name], bulletOf(block), kept));
        }
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
    const renames = pairRenames(was, now);
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
