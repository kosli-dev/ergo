/** The words a check sentence is built from, like `every`, `is` and `more`. They are shown as keywords. */
export const GRAMMAR_WORDS = new Set([
  "a", "after", "all", "alphabetically", "an", "and", "as", "at", "before", "between", "boolean", "by",
  "contain", "contains", "count", "days", "does", "each", "elapsed", "empty", "end", "ends", "equal", "equals",
  "every", "exist", "exists", "false", "first", "followed", "from", "hours", "if", "in", "is", "it", "item", "last",
  "least", "less", "list", "match", "matches", "minutes", "more", "most", "named", "non-empty", "none",
  "not", "null", "number", "object", "of", "on", "one", "or", "plus", "seconds", "some", "sorted",
  "start", "starts", "string", "sum", "than", "to", "true", "weeks", "whose", "with", "within",
]);

const SENTENCE = /("(?:[^"\\]|\\.)*"?)|(\$(?:params|input)(?:\.[A-Za-z_][\w-]*)*)|((?<![\w.])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w.]))|(\.?[A-Za-z_][\w-]*)|(\s+|.)/gy;

const join = (tokens) => {
  const out = [];
  for (const t of tokens) {
    if (!t.text) continue;
    const prev = out.at(-1);
    if (prev && prev.kind === t.kind) prev.text += t.text;
    else out.push({ ...t });
  }
  return out;
};

/** Splits a sentence into pieces to colour. Each piece is `{kind, text}`, where `kind` is `string`, `ref` (like `$input.items`), `number` or `word` (a grammar word). Everything else, like other words and spaces, gets the kind `base`, which is `"plain"` unless you pass another. Joining the pieces gives back the sentence. */
export const sentenceTokens = (text, base = "plain") => {
  const out = [];
  SENTENCE.lastIndex = 0;
  let m;
  while (SENTENCE.lastIndex < text.length && (m = SENTENCE.exec(text))) {
    const [all, str, ref, num, word] = m;
    if (str) out.push({ kind: "string", text: all });
    else if (ref) out.push({ kind: "ref", text: all });
    else if (num) out.push({ kind: "number", text: all });
    else if (word) out.push({ kind: GRAMMAR_WORDS.has(word) ? "word" : base, text: all });
    else out.push({ kind: base, text: all });
  }
  return join(out);
};

const linesIn = (blocks, kinds, name) => {
  const lines = new Set();
  for (const b of blocks ?? []) {
    if (!kinds.includes(b.kind) || (name && b.name !== name)) continue;
    for (let i = b.startLine; i <= b.endLine; i++) lines.add(i);
  }
  return lines;
};

const closingTicks = (text, from, n) => {
  let j = from;
  while ((j = text.indexOf("`", j)) !== -1) {
    let k = j;
    while (text[k] === "`") k++;
    if (k - j === n) return j;
    j = k;
  }
  return -1;
};

const inline = (text, sentence) => {
  const out = [];
  let plain = "";
  const flush = () => {
    out.push({ kind: "plain", text: plain });
    plain = "";
  };
  let i = 0;
  while (i < text.length) {
    if (text[i] === "`") {
      let n = 0;
      while (text[i + n] === "`") n++;
      const end = closingTicks(text, i + n, n);
      if (end === -1) {
        plain += text.slice(i, i + n);
        i += n;
        continue;
      }
      flush();
      const body = text.slice(i + n, end);
      out.push({ kind: "marker", text: text.slice(i, i + n) });
      const lead = sentence ? /^for(?=\s)/.exec(body)?.[0] ?? "" : "";
      if (lead) out.push({ kind: "word", text: lead });
      out.push(...(sentence ? sentenceTokens(body.slice(lead.length), "code") : [{ kind: "code", text: body }]));
      out.push({ kind: "marker", text: text.slice(end, end + n) });
      i = end + n;
      continue;
    }
    const strong = text.startsWith("**", i) ? "**" : text.startsWith("__", i) ? "__" : "";
    const close = strong ? text.indexOf(strong, i + 2) : -1;
    if (close > i + 2) {
      flush();
      out.push({ kind: "bold", text: text.slice(i, close + 2) });
      i = close + 2;
      continue;
    }
    plain += text[i];
    i++;
  }
  flush();
  return out;
};

const LIST = /^(\s*)([-*+]|\d+[.)])(\s+)(.*)$/;

const markdownLine = (line, sentence, field) => {
  const heading = /^(#{1,6})(\s+)(.*)$/.exec(line);
  if (heading) return [{ kind: "marker", text: heading[1] }, { kind: "plain", text: heading[2] }, { kind: "heading", text: heading[3] }];
  const item = LIST.exec(line);
  const head = item ? [{ kind: "plain", text: item[1] }, { kind: "marker", text: item[2] }, { kind: "plain", text: item[3] }] : [];
  let rest = item ? item[4] : line;
  if (field && rest.includes("`")) {
    const label = rest.slice(0, rest.indexOf("`"));
    const name = label.trimEnd();
    head.push({ kind: "key", text: name }, { kind: "plain", text: label.slice(name.length) });
    rest = rest.slice(label.length);
  }
  return [...head, ...inline(rest, sentence)];
};

/** Splits each line of a policy's Markdown into pieces to colour. Returns one list of `{kind, text}` pieces per line. `blocks` comes from `compile`, and tells which lines are sentences, fields and labels. */
export const highlightMarkdown = (source, blocks) => {
  const lines = source.split("\n");
  const sentences = new Set([...linesIn(blocks, ["check", "option"]), ...linesIn(blocks, ["field"], "from")]);
  const fields = linesIn(blocks, ["field"]);
  const labels = linesIn(blocks, ["checks"]);
  let front = lines[0] === "---";
  let fence = "";
  return lines.map((line, i) => {
    const n = i + 1;
    if (front) {
      if (n > 1 && line === "---") front = false;
      if (line === "---") return [{ kind: "marker", text: line }];
      const kv = /^([^:\s][^:]*)(:)(.*)$/.exec(line);
      return join(kv ? [{ kind: "key", text: kv[1] }, { kind: "plain", text: kv[2] }, { kind: "string", text: kv[3] }] : [{ kind: "plain", text: line }]);
    }
    const opens = /^\s*(`{3,}|~{3,})/.exec(line);
    if (fence) {
      if (opens && opens[1][0] === fence[0] && opens[1].length >= fence.length) fence = "";
      return join([{ kind: "code", text: line }]);
    }
    if (opens) {
      fence = opens[1];
      return join([{ kind: "code", text: line }]);
    }
    if (labels.has(n)) return join([{ kind: "key", text: line.trimEnd() }, { kind: "plain", text: line.slice(line.trimEnd().length) }]);
    return join(markdownLine(line, sentences.has(n), fields.has(n)));
  });
};

const isSentencePath = (keys) =>
  (keys.at(-1) === "from" && keys.at(-3) === "subjects" && keys.length === 3) ||
  (["assert", "for"].includes(keys.at(-1)) && keys.at(-3) === "checks") || (keys.at(-2) === "any_of" && keys.at(-4) === "checks");

const scalar = (text) => {
  const value = text.trimStart();
  const space = { kind: "plain", text: text.slice(0, text.length - value.length) };
  if (/^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(value)) return [space, { kind: "number", text: value }];
  if (/^(?:true|false|null)$/.test(value)) return [space, { kind: "word", text: value }];
  return [space, { kind: "string", text: value }];
};

const unquote = (key) => {
  if (key.startsWith("'")) return key.slice(1, -1).replace(/''/g, "'");
  if (key.startsWith('"')) {
    try {
      return JSON.parse(key);
    } catch {
      return key.slice(1, -1);
    }
  }
  return key;
};

/** Splits each line of YAML into pieces to colour. Returns one list of `{kind, text}` pieces per line. */
export const highlightYaml = (text) => {
  const stack = [];
  let scalarBlock = -1;
  return text.split("\n").map((line) => {
    const indent = line.length - line.trimStart().length;
    if (scalarBlock >= 0 && (line.trim() === "" || indent > scalarBlock)) {
      return join([{ kind: "plain", text: line.slice(0, indent) }, { kind: "string", text: line.slice(indent) }]);
    }
    scalarBlock = -1;
    const [, lead, dash = "", rest] = /^(\s*)(- )?(.*)$/.exec(line);
    while (stack.length && stack.at(-1).indent >= indent) stack.pop();
    const keys = stack.map((s) => s.key);
    const head = [{ kind: "plain", text: lead }, { kind: "marker", text: dash }];
    const kv = /^([^\s"'#][^:]*?|"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'):(?=\s|$)(.*)$/.exec(rest);
    if (!kv) {
      if (!rest) return join(head);
      return join([...head, ...(dash && isSentencePath(keys) ? sentenceTokens(rest) : scalar(rest))]);
    }
    const [, key, value] = kv;
    const keyIndent = indent + dash.length;
    stack.push({ indent: keyIndent, key: unquote(key) });
    head.push({ kind: "key", text: key }, { kind: "plain", text: ":" });
    if (/^\s*[|>][-+]?\d*\s*$/.test(value)) {
      scalarBlock = keyIndent;
      return join([...head, { kind: "marker", text: value }]);
    }
    if (!value.trim()) return join([...head, { kind: "plain", text: value }]);
    return join([...head, ...(isSentencePath([...keys, key]) ? sentenceTokens(value) : scalar(value))]);
  });
};
