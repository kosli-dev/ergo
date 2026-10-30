import { readSentence, problemRange, treeTokens, describe, forAliases, lastKeyOfText } from "./sentences.mjs";

const lastKey = (path) => {
  const steps = path.steps.filter((s) => typeof s === "object" && "Key" in s);
  if (steps.length) return steps.at(-1).Key;
  const start = path.start;
  if (typeof start === "object" && "Quoted" in start) return start.Quoted;
  return typeof start === "object" && "Field" in start ? start.Field.key : null;
};

const partKey = (path) => lastKeyOfText(path) ?? path;

const namedByNames = (node, out = []) => {
  if (Array.isArray(node)) node.forEach((n) => namedByNames(n, out));
  else if (node !== null && typeof node === "object") {
    if (node.NamedBy && typeof node.NamedBy === "object" && "Name" in node.NamedBy) out.push(node.NamedBy.Name);
    Object.values(node).forEach((n) => namedByNames(n, out));
  }
  return out;
};

const NAMED_BY = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\bnamed\s+by\s+([A-Za-z_][\w-]*)/g;

const partProblems = (tree, text, partNames) => {
  const used = new Set(namedByNames(tree).filter((n) => partNames.includes(n)));
  const out = [];
  for (const m of text.matchAll(NAMED_BY)) {
    const name = m[1];
    if (name === undefined || !used.delete(name)) continue;
    const column = Array.from(text.slice(0, m.index + m[0].length - name.length)).length + 1;
    out.push({ column, message: `named by ${name} reads a part, which isn't supported yet` });
  }
  return out;
};

/** Makes a function that reads a list of located sentences (from `markdownSentences` or `yamlSentences`) with the parser. For each sentence it gives what the line needs: `{...sentence, tree, problems, tokens, lines, aliases, aliasKeys}`. `problems` are `{message, start, end}` with positions in the line, `tokens` colour the sentence from its tree (or are `null` when the text and the tree don't agree, or the text isn't what the line holds), `lines` say how it is read, and `aliasKeys` maps each name in scope to the last key of the list it stands for. The function gives `null` when the parser is missing or stopped. `base` is the kind the tokens that need no colour get. */
export const makeAnalyser = (parser, base = "plain") => {
  const cache = new Map();
  const one = (s, subjects) => {
    const partNames = Object.keys(s.parts ?? {});
    let aliases = partNames;
    let forTree = null;
    const aliasKeys = Object.fromEntries(partNames.map((n) => [n, partKey(s.parts[n])]));
    if (s.kind === "check" && s.forText) {
      const f = readSentence(parser, "for", s.forText, partNames);
      if (f?.tree) {
        forTree = f.tree;
        aliases = [...partNames, ...forAliases(f.tree)];
        for (const item of f.tree.items) {
          const body = Object.values(item)[0];
          aliasKeys[body.alias] = lastKey(body.path);
        }
      }
    }
    const read = readSentence(parser, s.kind, s.text, aliases);
    if (read === null) return null;
    if (read.tree && s.kind !== "from") read.problems.push(...partProblems(read.tree, s.text, partNames));
    const ctx = { forTree, parts: s.parts ?? {}, subjects, subject: s.subject };
    return {
      tree: read.tree,
      problems: read.problems,
      tokens: read.tree && s.exact ? treeTokens(s.kind, read.tree, s.text, aliases, base) : null,
      lines: read.tree ? describe(s.kind, read.tree, ctx) : [],
      aliases,
      aliasKeys,
    };
  };
  return ({ sentences, subjects }) => {
    if (!parser) return null;
    if (cache.size > 4000) cache.clear();
    const out = [];
    for (const s of sentences) {
      const key = JSON.stringify([s.kind, s.text, s.forText, s.parts, s.subject, s.exact, subjects, base]);
      let hit = cache.get(key);
      if (hit === undefined) {
        hit = one(s, subjects);
        if (hit === null) return null;
        cache.set(key, hit);
      }
      const problems = hit.problems.map((p) => {
        const range = s.exact ? problemRange(s.text, p) : { start: 0, end: s.end - s.start };
        return { message: p.message, start: s.start + range.start, end: s.start + range.end };
      });
      out.push({ ...s, ...hit, problems });
    }
    return out;
  };
};

const cut = (tokens, at) => {
  const out = [];
  let pos = 0;
  for (const t of tokens) {
    const end = pos + t.text.length;
    if (at > pos && at < end) out.push({ ...t, text: t.text.slice(0, at - pos) }, { ...t, text: t.text.slice(at - pos) });
    else out.push(t);
    pos = end;
  }
  return out;
};

const within = (tokens, start, end, change) => {
  let pos = 0;
  return tokens.map((t) => {
    const here = pos;
    pos += t.text.length;
    return here >= start && pos <= end ? change(t) : t;
  });
};

/** Puts the readings of the sentences on one line's pieces. A sentence with tokens replaces the pieces it covers, and every problem underlines its range, by adding `problem: true` to the pieces in it. Gives a new list of `{kind, text}` pieces. */
export const decorate = (tokens, entries) => {
  let out = tokens;
  for (const e of entries) {
    if (!e.tokens) continue;
    out = cut(cut(out, e.start), e.end);
    let pos = 0;
    const before = [];
    const after = [];
    for (const t of out) {
      if (pos + t.text.length <= e.start) before.push(t);
      else if (pos >= e.end) after.push(t);
      pos += t.text.length;
    }
    out = [...before, ...e.tokens, ...after];
  }
  for (const e of entries) {
    for (const p of e.problems) {
      out = cut(cut(out, p.start), p.end);
      out = within(out, p.start, p.end, (t) => ({ ...t, problem: true }));
    }
  }
  return out;
};

/** The entries of one line, with the lines counted from 1. */
export const entriesOnLine = (entries, line) => (entries ?? []).filter((e) => e.line === line);

/** Applies `decorate` to every line. `tokenLines` is one list of pieces per line and `text` the document. A line whose pieces don't join back to its text is left as it is. With `entries` `null`, which is what `makeAnalyser`'s function gives without a parser, every line is left as it is. */
export const decorateLines = (tokenLines, text, entries) => {
  if (!entries) return tokenLines;
  const lines = text.split("\n");
  return tokenLines.map((tokens, i) => {
    const here = entriesOnLine(entries, i + 1);
    if (here.length === 0 || tokens.map((t) => t.text).join("") !== lines[i]) return tokens;
    return decorate(tokens, here);
  });
};

/** The sentence under a position, for a hover or a completion: the entry on `line` (from 1) whose text covers `col` (from 0, the end included). Gives `null` when there is none. */
export const entryAt = (entries, line, col) => entriesOnLine(entries, line).find((e) => col >= e.start && col <= e.end) ?? null;

/** What a hover shows for a sentence: `{problems, lines}`, the messages of what is written wrong and the lines that say how the sentence is read. */
export const hoverOf = (entry) => ({ problems: entry.problems.map((p) => p.message), lines: entry.lines });

/** The problems of every sentence as `{line, message}`, in the order of the lines. */
export const sentenceProblems = (entries) =>
  (entries ?? []).flatMap((e) => e.problems.map((p) => ({ line: e.line, message: p.message }))).sort((a, b) => a.line - b.line);
