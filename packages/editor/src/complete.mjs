import { GRAMMAR_WORDS } from "./highlight.mjs";

const WORDS = [...new Set([...GRAMMAR_WORDS, "any"])].sort();

const PROBES = [
  "", " x", " 1", ' "x"', " x.y", " $params.x", " x, y", " 1, 2", " x is 1", " x exists", " x is empty", " is 1", " exists", " is empty",
  " x as y", " as y", " by x", " x by y", " of x", " of x is 1", " of 1", " all of 1", " least 1", " most 1", " than 1", " than x",
  " to y", " from x to y", " elapsed from x to y", " from last of x", " last of x", " 1 of x", " x whose y is 1", " whose y is 1",
  " x whose y is 1 exists", " x, if any, exists", " any, exists", " any, is 1", " and x is 1", " and 2", " 2", " string", " list", " x is 1 and y is 2",
  " x named by y", " named by y", " x of y is 1", " x plus 1", " plus 1", " with 1", " within 1", " or after x", " or before x", " x or after y",
  " empty", " non-empty string", " a list", " x is a list", " is a list", " one of 1", " of 1, 2", " not x", " not 1", " not exist", " not empty",
  " x is not empty", " not one of 1", " in x", " is in x", " equal to 1", " to 1", " alphabetically before x", " before x", " after x", " x as y, every z as w",
  " by x is 1", " by x exists", " y is 1 exists", " y is 1 and z is 2 exists", " 1 and 2", " not exist", " exist", " not equal x", " not contain 1", " not match 1",
  " of x is 1 exists", " of x is 1", " y is 1 as z", " is 1 as z", " not exist exists", " not equal x exists", " not exist as z", " not equal x as z", " y is 1 and z is 2 as w", " elapsed from x to y is 1", " from x to y is 1", " x to y is 1", ", exists", ", is 1", " x each of y", " each of y", " of y whose z is 1", " sorted by x as y", " by x as y", " by x alphabetically as y", " x equals y", " equals 1", " equals y",
];

const bare = (name) => /^[A-Za-z_][\w-]*$/.test(name);
const written = (name) => (bare(name) ? name : JSON.stringify(name));

/** Lists the keys of the objects found under a key called `key`, anywhere in a JSON value (lists are walked through). With `key` `null` it lists the keys of the top object. Sorted, without repeats. */
export const fieldsAfter = (input, key) => {
  const found = new Set();
  const visit = (value, under) => {
    if (Array.isArray(value)) {
      for (const item of value) visit(item, under);
    } else if (value !== null && typeof value === "object") {
      if (under === key) for (const k of Object.keys(value)) found.add(k);
      for (const [k, v] of Object.entries(value)) visit(v, k);
    }
  };
  visit(input, null);
  return [...found].sort();
};

const accepts = (parser, kind, head, word) => PROBES.some((tail) => parser.read(kind, head + word + tail)?.tree !== undefined);

/** Says what can be typed at `cursor` in a sentence. `ctx` holds the `parser`, the `kind` (`check`, `for` or `from`), the `text` of the sentence, the names in scope (`aliases`, with `aliasKeys` for the list each one stands for, and the subject's `parts`), the `subjects` of the policy and the `subject` this sentence belongs to, and the JSON `input` to read field names from. Gives `{from, to, items}`: replace `from` to `to` with the text of one item, each `{text, kind}`, where kind is `word`, `alias`, `part`, `subject`, `field` or `ref`. */
export const suggest = (ctx, cursor) => {
  const { parser, kind, text, aliasKeys = {}, subjects = [], subject = null, input = null } = ctx;
  const parts = Object.keys(ctx.parts ?? {});
  const aliases = ctx.aliases ?? [];
  const before = text.slice(0, cursor);
  const prefix = /[$\w-]*$/.exec(before)[0];
  const start = cursor - prefix.length;
  const head = before.slice(0, start);
  const none = { from: start, to: cursor, items: [] };
  if (!parser) return none;
  const starts = (name) => name.startsWith(prefix) && name !== prefix;
  const items = [];
  const field = (key) => {
    for (const name of fieldsAfter(input, key)) if (starts(name) || name === prefix) items.push({ text: written(name), kind: "field" });
  };
  if (head.endsWith(".")) {
    const owner = /([A-Za-z_][\w-]*|"[^"]*")\]?\.$/.exec(head)?.[1] ?? null;
    if (/(?:^|[\s,])\$input\.$/.test(head)) field(null);
    else if (owner !== null && Object.hasOwn(aliasKeys, owner)) field(aliasKeys[owner]);
    else if (owner !== null) field(owner.replace(/^"|"$/g, ""));
    return { from: start, to: cursor, items };
  }
  const whose = /(?:^|\s)(\S+)\s+whose\s+(?:.*\band\s+)?$/.exec(head);
  if (whose) {
    field(whose[1].split(".").at(-1).replace(/^"|"$/g, ""));
    return { from: start, to: cursor, items };
  }
  if (prefix.startsWith("$")) {
    for (const name of ["$params", "$input"]) if (name.startsWith(prefix)) items.push({ text: name, kind: "ref" });
    return { from: start, to: cursor, items };
  }
  if (accepts(parser, kind, head, "zz9")) {
    if (kind === "from" && /^(?:every\s+)?$/.test(head)) {
      for (const name of subjects) if (name !== subject && (starts(name) || name === prefix)) items.push({ text: written(name), kind: "subject" });
    }
    if (kind !== "from") {
      for (const name of parts) if (starts(name)) items.push({ text: name, kind: "part" });
      for (const name of aliases) if (!parts.includes(name) && starts(name)) items.push({ text: name, kind: "alias" });
    }
  }
  for (const word of WORDS) if (word.startsWith(prefix) && accepts(parser, kind, head, word)) items.push({ text: word, kind: "word" });
  return { from: start, to: cursor, items };
};

const typed = (view, lineText, col, blockKind) => {
  if (view === "markdown") {
    const ticks = lineText.slice(0, col).split("`").length - 1;
    if (ticks % 2 === 0 || !["check", "option", "from"].includes(blockKind)) return null;
    const start = lineText.lastIndexOf("`", col - 1) + 1;
    const text = lineText.slice(start, col);
    const isFor = blockKind !== "from" && text.startsWith("for ");
    const skip = isFor ? 4 : 0;
    return { kind: blockKind === "from" ? "from" : isFor ? "for" : "check", text: text.slice(skip), cursor: text.length - skip };
  }
  const m = /^(\s*(?:-\s+|(assert|for|from):\s+))(.*)$/.exec(lineText.slice(0, col));
  if (!m) return null;
  return { kind: m[2] === "for" ? "for" : m[2] === "from" ? "from" : "check", text: m[3], cursor: m[3].length };
};

/** Works out what to complete at a position of a view. `entries` come from the analyser, `line` counts from 1 and `col` from 0. `extras` holds the `parser`, the `subjects` and `input` the suggestions read, and, for Markdown, the `blockKind` of the line. A sentence the analyser has read gives its names in scope. A line being typed that isn't read yet, like a code span with no closing backtick, is taken from the line. Gives `{from, to, items}` with `from` and `to` as positions in the line, or `null` when the position isn't in a sentence. */
export const completionAt = (view, entries, lineText, line, col, extras) => {
  const entry = (entries ?? []).find((e) => e.line === line && e.exact && col >= e.start && col <= e.end);
  let ctx;
  let offset;
  if (entry) {
    ctx = { kind: entry.kind, text: entry.text, aliases: entry.aliases, aliasKeys: entry.aliasKeys, parts: entry.parts, subject: entry.subject };
    offset = entry.start;
  } else {
    const read = typed(view, lineText, col, extras.blockKind);
    if (!read) return null;
    ctx = { kind: read.kind, text: read.text, aliases: [], aliasKeys: {}, parts: {}, subject: null };
    offset = col - read.cursor;
  }
  const found = suggest({ ...ctx, parser: extras.parser, subjects: extras.subjects, input: extras.input }, col - offset);
  return { from: found.from + offset, to: found.to + offset, items: found.items };
};
