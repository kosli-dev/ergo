import { parse } from "@kosli/ergo-markdown";
import { LineCounter, parseDocument, isMap, isScalar, isSeq } from "yaml";

const INNER = { check: true, option: true };

const innermost = (blocks, line, accept) => {
  let best = null;
  for (const b of blocks) {
    if (b.startLine <= line && line <= b.endLine && accept(b) && (!best || b.startLine >= best.startLine)) best = b;
  }
  return best;
};

const codeNodes = (node, out = []) => {
  if (node.type === "inlineCode") out.push(node);
  for (const child of node.children ?? []) codeNodes(child, out);
  return out;
};

/** The kind of the innermost check, option or from block at a line, or `null`. `check` and `option` are sentence blocks and `field` is a `from` field. */
export const blockKindAt = (blocks, line) => {
  const b = innermost(blocks, line, (x) => INNER[x.kind] || (x.kind === "field" && x.name === "from"));
  return b ? (b.kind === "field" ? "from" : b.kind) : null;
};

const trimmed = (text) => {
  const lead = text.length - text.trimStart().length;
  return { text: text.trim(), lead };
};

/** Finds every sentence in a policy written as Markdown: the code spans of checks and options, which are `for` lines when they start with `for `, and the code span of a subject's `from` field. `blocks` is what `compile` gives. Each sentence is `{kind, line, start, end, text, exact, group, forText, subject}`, where `line` counts from 1, `start` and `end` are positions in that line, `exact` says the text is what the line holds there, `group` names the check it belongs to and `forText` is that check's `for` line. Gives `{sentences, subjects}`. */
export const markdownSentences = (source, blocks) => {
  const lines = source.split("\n");
  const found = [];
  let tree;
  try {
    tree = parse(source);
  } catch {
    return { sentences: [], subjects: [] };
  }
  for (const node of codeNodes(tree)) {
    const line = node.position.start.line;
    const block = innermost(blocks, line, (b) => INNER[b.kind] || (b.kind === "field" && b.name === "from"));
    if (!block) continue;
    const text = lines[line - 1] ?? "";
    const raw = source.slice(node.position.start.offset, node.position.end.offset);
    const ticks = /^`+/.exec(raw)?.[0].length ?? 0;
    let col = node.position.start.column - 1 + ticks;
    let value = node.value;
    if (text.slice(col, col + value.length) !== value && text.slice(col + 1, col + 1 + value.length) === value) col++;
    const exact = text.slice(col, col + value.length) === value && node.position.end.line === line;
    const isFor = block.kind === "check" && value.startsWith("for ");
    const skip = isFor ? 4 : 0;
    const body = trimmed(value.slice(skip));
    found.push({
      kind: block.kind === "field" ? "from" : isFor ? "for" : "check",
      line,
      start: col + skip + body.lead,
      end: col + skip + body.lead + body.text.length,
      text: body.text,
      exact,
      group: block.kind === "field" ? null : block.startLine,
      blockKind: block.kind,
    });
  }
  const forOf = new Map();
  for (const s of found) if (s.kind === "for" && !forOf.has(s.group)) forOf.set(s.group, s.text);
  const subjectBlocks = blocks.filter((b) => b.kind === "subject");
  const sentences = found.map((s) => ({
    ...s,
    forText: s.kind === "check" ? (forOf.get(s.group) ?? null) : null,
    subject: s.kind === "from" ? (innermost(subjectBlocks, s.line, () => true)?.name ?? null) : null,
    parts: {},
  }));
  return { sentences, subjects: subjectBlocks.map((b) => b.name).filter((n) => typeof n === "string") };
};

const keyName = (node) => (isScalar(node) ? String(node.value) : null);

const pairsOf = (node) => (isMap(node) ? node.items : []);

const getPair = (map, name) => pairsOf(map).find((p) => keyName(p.key) === name)?.value ?? null;

/** Finds every sentence in a policy written as YAML: each subject's `from`, and each check's `for`, `assert` and `any_of` options. Each is `{kind, line, start, end, text, exact, forText, subject, parts}`, as `markdownSentences` gives, and `parts` is the subject's `has` as `{alias: path}`. A text that is inside quotes or spans lines has `exact: false` unless it is written as it reads. Gives `{sentences, subjects}`. */
export const yamlSentences = (text) => {
  const counter = new LineCounter();
  let doc;
  try {
    doc = parseDocument(text, { lineCounter: counter });
  } catch {
    return { sentences: [], subjects: [] };
  }
  const lines = text.split("\n");
  const sentences = [];
  const at = (node, kind, extra) => {
    if (!isScalar(node) || typeof node.value !== "string" || !node.range) return;
    const value = node.value.trim();
    if (value === "") return;
    const first = counter.linePos(node.range[0]);
    const block = node.type === "BLOCK_LITERAL" || node.type === "BLOCK_FOLDED";
    let line = first.line;
    let col = first.col - 1;
    if (block) {
      const content = lines.slice(line, counter.linePos(Math.max(node.range[1] - 1, node.range[0])).line);
      const used = content.map((l, i) => [l, line + 1 + i]).filter(([l]) => l.trim() !== "");
      line = used.length ? used[0][1] : line + 1;
      col = used.length ? used[0][0].length - used[0][0].trimStart().length : 0;
    } else if (node.type === "QUOTE_DOUBLE" || node.type === "QUOTE_SINGLE") col++;
    const row = lines[line - 1] ?? "";
    const exact = row.slice(col, col + value.length) === value;
    const last = counter.linePos(node.range[1]);
    const quoted = node.type === "QUOTE_DOUBLE" || node.type === "QUOTE_SINGLE";
    const rawEnd = !block && last.line === line ? last.col - 1 - (quoted ? 1 : 0) : col + value.length;
    sentences.push({ kind, line, start: col, end: exact ? col + value.length : Math.max(rawEnd, col + 1), text: value, exact, ...extra });
  };
  const subjects = getPair(doc.contents, "subjects");
  const subjectNames = pairsOf(subjects).map((p) => keyName(p.key)).filter((n) => n !== null);
  const partsOf = new Map();
  for (const p of pairsOf(subjects)) {
    const name = keyName(p.key);
    const parts = {};
    for (const part of pairsOf(getPair(p.value, "has"))) {
      const alias = keyName(part.key);
      const path = isScalar(part.value) ? part.value.value : isMap(part.value) ? getPair(part.value, "from")?.value : null;
      if (alias !== null && typeof path === "string") parts[alias] = path;
    }
    partsOf.set(name, parts);
    const from = getPair(p.value, "from");
    at(from, "from", { subject: name, forText: null, parts });
  }
  for (const r of pairsOf(getPair(doc.contents, "requirements"))) {
    const subject = getPair(r.value, "subject")?.value;
    const parts = typeof subject === "string" ? (partsOf.get(subject) ?? {}) : {};
    for (const c of pairsOf(getPair(r.value, "checks"))) {
      const check = c.value;
      const forNode = getPair(check, "for");
      const forText = isScalar(forNode) && typeof forNode.value === "string" ? forNode.value.trim() : null;
      const ctx = { subject: typeof subject === "string" ? subject : null, parts };
      at(forNode, "for", { ...ctx, forText: null });
      const asserts = (node) => (isSeq(node) ? node.items : [node]);
      for (const a of asserts(getPair(check, "assert"))) at(a, "check", { ...ctx, forText });
      for (const o of pairsOf(getPair(check, "any_of"))) for (const a of asserts(o.value)) at(a, "check", { ...ctx, forText: null });
    }
  }
  return { sentences, subjects: subjectNames };
};
