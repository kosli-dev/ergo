import { GRAMMAR_WORDS } from "./highlight.mjs";

const WORDS = new Set([...GRAMMAR_WORDS, "any"]);

const PARSE = { check: "parse_check", for: "parse_for", from: "parse_from" };
const PROBLEMS = { check: "check_problems", for: "for_problems", from: "from_problems" };

/** Wraps the functions of the sentences Wasm (`parse_check`, `parse_for`, `parse_from`, `check_problems`, `for_problems`, `from_problems`) so callers get objects. Once a call throws, every later call gives `null`, because the module can't be trusted after that. */
export const makeParser = (pkg) => {
  let broken = false;
  const call = (name, ...args) => {
    if (broken) return null;
    try {
      return JSON.parse(pkg[name](...args));
    } catch {
      broken = true;
      return null;
    }
  };
  return {
    read: (kind, text) => call(PARSE[kind], text),
    problems: (kind, tree, aliases) => {
      const out = kind === "from" ? call(PROBLEMS[kind], JSON.stringify(tree)) : call(PROBLEMS[kind], JSON.stringify(tree), JSON.stringify(aliases));
      return out === null ? null : out.problems;
    },
  };
};

/** Reads one sentence of the given kind (`check`, `for` or `from`). Gives `{tree, problems}`, where each problem is `{column, message}` and `column` is a 1-based position in the sentence or `null`. Gives `null` when there is no parser or it stopped. `aliases` are the names in scope: a `for` line's aliases and a subject's parts. */
export const readSentence = (parser, kind, text, aliases = []) => {
  if (!parser) return null;
  const read = parser.read(kind, text);
  if (read === null) return null;
  if (read.errors) return { tree: null, problems: read.errors.map((e) => ({ column: e.column, message: e.message })) };
  const found = parser.problems(kind, read.tree, aliases);
  if (found === null) return null;
  return { tree: read.tree, problems: found.map((message) => ({ column: null, message })) };
};

/** The part of a sentence a problem is about, as `{start, end}` positions in the text. With a column it is the word that starts there, or the rest of the sentence when that is a quote. Without one it is the whole sentence. */
export const problemRange = (text, problem) => {
  const letters = Array.from(text);
  const length = text.length;
  if (problem.column === null || problem.column === undefined || letters.length === 0) return { start: 0, end: length };
  const at = Math.min(Math.max(problem.column - 1, 0), letters.length - 1);
  const start = letters.slice(0, at).join("").length;
  if (/["']/.test(letters[at])) return { start, end: length };
  let end = start;
  for (let i = at; i < letters.length && !/\s/.test(letters[i]); i++) end += letters[i].length;
  return { start, end };
};

const K = (text, role) => ({ type: "key", text, role });
const S = () => ({ type: "string" });
const N = (text) => ({ type: "number", text });
const D = (text) => ({ type: "dollar", text });

const variant = (value) => (typeof value === "string" ? [value, null] : Object.entries(value)[0]);

const refOps = (ref, out) => {
  const [type, value] = variant(ref);
  if (type === "Params") out.push(D("$params"), K(value, "ref"));
  else if (type === "Input") out.push(D("$input"), K(value, "ref"));
  else if (type === "Unknown") {
    out.push(D(value.name));
    if (value.key !== null) out.push(K(value.key, "ref"));
  } else out.push(K(value, "alias"));
};

const pathOps = (path, out, aliases) => {
  const [kind, position] = path.position ? variant(path.position) : [null, null];
  if (kind === "Item") out.push(N(position.number));
  const [type, value] = variant(path.start);
  if (type === "Params") out.push(D("$params"));
  else if (type === "Input") out.push(D("$input"));
  else if (type === "Unknown") out.push(D(value));
  else if (type === "Field") out.push(K(value.key, !value.dot && aliases.has(value.key) ? "alias" : "field"));
  const rooted = type === "Params" || type === "Input";
  path.steps.forEach((step, i) => {
    const [name, body] = variant(step);
    if (name === "Key") out.push(K(body, rooted && i === 0 ? "ref" : "field"));
    else if (name === "BracketKey") out.push(K(body, "field"));
    else if (name === "Index") out.push(N(body));
    else refOps(body, out);
  });
};

const valueOps = (value, out) => {
  const [type, body] = variant(value);
  if (type === "String") out.push(S());
  else if (type === "Number") out.push(N(body));
};

const termOps = (term, out, aliases) => {
  const [type, body] = variant(term);
  if (type === "Path") pathOps(body, out, aliases);
  else if (type === "Number") out.push(N(body));
  else if (type === "Derived") derivedOps(body, out, aliases);
  else if (type === "Elapsed") {
    pathOps(body.from, out, aliases);
    pathOps(body.to, out, aliases);
  }
};

const derivedOps = (derived, out, aliases) => {
  pathOps(derived.path, out, aliases);
  for (const c of derived.whose) conditionOps(c, out, aliases);
};

const operandOps = (operand, out, aliases) => {
  const [type, body] = variant(operand);
  if (type === "Value") valueOps(body, out);
  else for (const t of body) termOps(t, out, aliases);
};

const listOps = (list, out, aliases) => {
  const [type, body] = variant(list);
  if (type === "Values") for (const v of body) valueOps(v, out);
  else pathOps(body, out, aliases);
};

const phraseOps = (phrase, out, aliases) => {
  const [type, body] = variant(phrase);
  if (type === "Is") {
    operandOps(body.operand, out, aliases);
    if (body.within !== null) out.push(N(body.within));
  } else if (["Order", "Contains", "Alphabetically", "Time"].includes(type)) operandOps(body.operand, out, aliases);
  else if (type === "Between") out.push(N(body.min), N(body.max));
  else if (type === "OneOf" || type === "Matches") listOps(body.list, out, aliases);
  else if (type === "ContainsAll" || type === "ContainsNone") listOps(body, out, aliases);
  else if (type === "StartsWith" || type === "EndsWith") operandOps(body, out, aliases);
};

const leftOps = (left, out, aliases) => {
  const [type, body] = variant(left);
  if (type === "Path") pathOps(body, out, aliases);
  else if (type === "Derived") derivedOps(body, out, aliases);
  else {
    pathOps(body.from, out, aliases);
    pathOps(body.to, out, aliases);
  }
};

const conditionOps = (condition, out, aliases) => {
  leftOps(condition.left, out, aliases);
  phraseOps(condition.phrase, out, aliases);
};

const positionOps = (position, out) => {
  const [type, body] = variant(position);
  if (type === "Item") out.push(N(body.number));
};

const operandsOf = (kind, tree, aliases) => {
  const out = [];
  if (kind === "check") {
    for (const a of tree.assertions) {
      const [type, body] = variant(a);
      if (type === "Plain") {
        pathOps(body.path, out, aliases);
      } else if (type === "Quantified") {
        pathOps(body.path, out, aliases);
        for (const c of body.whose) conditionOps(c, out, aliases);
      } else for (const t of body.terms) termOps(t, out, aliases);
      phraseOps(body.phrase, out, aliases);
    }
  } else if (kind === "for") {
    for (const item of tree.items) {
      const [type, body] = variant(item);
      if (type === "Pick") positionOps(body.position, out);
      pathOps(body.path, out, aliases);
      for (const c of body.whose) conditionOps(c, out, aliases);
      if (type === "Pick" && body.sorted_by) pathOps(body.sorted_by.path, out, aliases);
      out.push(K(body.alias, "alias"));
    }
  } else {
    pathOps(tree.path, out, aliases);
    if (tree.named_by_each_of) pathOps(tree.named_by_each_of, out, aliases);
    for (const c of tree.whose) {
      const [type, body] = variant(c);
      if (type === "Condition") conditionOps(body, out, aliases);
      else {
        pathOps(body.path, out, aliases);
        phraseOps(body.phrase, out, aliases);
      }
    }
  }
  return out;
};

const LEXEME = /(\s+)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(\$[A-Za-z0-9_]*)|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|([A-Za-z_][\w-]*)|([\s\S])/gy;

const lexemes = (text) => {
  const out = [];
  LEXEME.lastIndex = 0;
  let m;
  while (LEXEME.lastIndex < text.length && (m = LEXEME.exec(text))) {
    const [all, space, string, dollar, number, ident] = m;
    const type = space ? "space" : string ? "string" : dollar ? "dollar" : number ? "number" : ident ? "ident" : "punct";
    out.push({ type, text: all });
  }
  return out;
};

const merge = (tokens) => {
  const out = [];
  for (const t of tokens) {
    const last = out.at(-1);
    if (last && last.kind === t.kind) last.text += t.text;
    else out.push({ ...t });
  }
  return out;
};

const ROLE = { field: "field", alias: "alias", ref: "ref" };

/** Colours a sentence from its tree. The tree has no positions, so the names and values it holds are matched, in order, against the words, strings and numbers of the text. Gives a list of `{kind, text}` pieces that joins back to `text`, with the kinds `word`, `field`, `alias`, `ref`, `string` and `number`, and `base` for the rest. Gives `null` when the text and the tree don't match, so the caller can colour it another way. */
export const treeTokens = (kind, tree, text, aliases = [], base = "plain") => {
  const ops = operandsOf(kind, tree, new Set(aliases));
  const tokens = [];
  let next = 0;
  let previous = null;
  for (const lex of lexemes(text)) {
    const op = ops[next];
    let piece = { kind: base, text: lex.text };
    if (lex.type === "ident") {
      const afterDot = previous?.type === "punct" && previous.text === ".";
      const isWord = WORDS.has(lex.text) && !afterDot;
      const asKey = op?.type === "key" && op.text === lex.text;
      const typeWord = ["a", "an"].includes(previous?.text);
      if (asKey && (!isWord || !typeWord)) {
        piece = { kind: ROLE[op.role], text: lex.text };
        next++;
      } else if (isWord) piece = { kind: "word", text: lex.text };
      else return null;
    } else if (lex.type === "string") {
      if (op?.type !== "string" && op?.type !== "key") return null;
      piece = { kind: "string", text: lex.text };
      next++;
    } else if (lex.type === "number") {
      if (op?.type !== "number" || op.text !== lex.text) return null;
      piece = { kind: "number", text: lex.text };
      next++;
    } else if (lex.type === "dollar") {
      if (op?.type !== "dollar" || op.text !== lex.text) return null;
      piece = { kind: "ref", text: lex.text };
      next++;
    }
    if (lex.type !== "space") {
      const dot = tokens.at(-1);
      if (previous?.type === "punct" && previous.text === "." && dot && piece.kind !== base) dot.kind = piece.kind;
      previous = lex;
    }
    tokens.push(piece);
  }
  return next === ops.length ? merge(tokens) : null;
};

const keyText = (key) => (/^[A-Za-z_][\w-]*$/.test(key) ? key : JSON.stringify(key));

const positionText = (position) => {
  const [type, body] = variant(position);
  if (type === "Item") return `item ${body.number}${body.from_last ? " from last" : ""} of `;
  return type === "First" ? "first of " : "last of ";
};

const referenceText = (ref) => {
  const [type, value] = variant(ref);
  if (type === "Params") return `$params.${keyText(value)}`;
  if (type === "Input") return `$input.${keyText(value)}`;
  if (type === "Unknown") return value.key === null ? value.name : `${value.name}.${keyText(value.key)}`;
  return value;
};

/** Writes a path as a sentence writes it, like `item 2 of pr.approvers` or `xs named by $params.k`. */
export const pathText = (path) => {
  const [type, value] = variant(path.start);
  const start = type === "It" ? "it" : type === "Params" ? "$params" : type === "Input" ? "$input" : type === "Unknown" ? value : `${value.dot ? "." : ""}${keyText(value.key)}`;
  const steps = path.steps.map((step) => {
    const [name, body] = variant(step);
    if (name === "Key") return `.${keyText(body)}`;
    if (name === "NamedBy") return ` named by ${referenceText(body)}`;
    if (name === "Brackets") return `[${referenceText(body)}]`;
    if (name === "BracketKey") return `[${JSON.stringify(body)}]`;
    return `[${body}]`;
  });
  return (path.position ? positionText(path.position) : "") + start + steps.join("");
};

const valueText = (value) => {
  const [type, body] = variant(value);
  if (type === "String") return JSON.stringify(body);
  if (type === "Number") return body;
  return type.toLowerCase();
};

const UNITS = { Seconds: "seconds", Minutes: "minutes", Hours: "hours", Days: "days", Weeks: "weeks" };

const derivedText = (derived) => {
  const kept = whoseText(derived.whose);
  return `${derived.kind === "Count" ? "the number of" : "the sum of"} ${pathText(derived.path)}${kept}`;
};

const termText = (term) => {
  const [type, body] = variant(term);
  if (type === "Path") return pathText(body);
  if (type === "Number") return body;
  if (type === "Derived") return derivedText(body);
  return `the ${UNITS[body.unit]} from ${pathText(body.from)} to ${pathText(body.to)}`;
};

const operandText = (operand) => {
  const [type, body] = variant(operand);
  return type === "Value" ? valueText(body) : body.map(termText).join(" plus ");
};

const listText = (list) => {
  const [type, body] = variant(list);
  return type === "Values" ? body.map(valueText).join(", ") : pathText(body);
};

const leftText = (left) => {
  const [type, body] = variant(left);
  if (type === "Path") return pathText(body);
  return termText({ [type]: body });
};

const ORDER = { AtLeast: "at least", AtMost: "at most", MoreThan: "more than", LessThan: "less than" };
const TIME = { Before: "before", After: "after", OnOrAfter: "on or after", OnOrBefore: "on or before" };
const TYPE = { List: "a list", String: "a string", Number: "a number", Boolean: "a boolean", Object: "an object" };
const not = (flag, yes, no) => (flag ? no : yes);

const phraseText = (phrase) => {
  const [type, b] = variant(phrase);
  if (type === "Is") return b.within === null ? `is ${not(b.not, "", "not ")}${operandText(b.operand)}` : `is within ${b.within} of ${operandText(b.operand)}`;
  if (type === "Order") return `is ${ORDER[b.order]} ${operandText(b.operand)}`;
  if (type === "Between") return `is between ${b.min} and ${b.max}, both included`;
  if (type === "OneOf") return `is ${not(b.not, "", "not ")}one of ${listText(b.list)}`;
  if (type === "Exists") return b.not ? "does not exist" : "exists";
  if (type === "Empty") return `is ${not(b.not, "", "not ")}empty`;
  if (type === "NonEmptyString") return "is a string with at least one character";
  if (type === "Type") return `is ${TYPE[b]}`;
  if (type === "Contains") return `${b.not ? "does not contain" : "contains"} ${operandText(b.operand)}`;
  if (type === "ContainsAll") return `contains all of ${listText(b)}`;
  if (type === "ContainsNone") return `contains none of ${listText(b)}`;
  if (type === "Matches") return `${b.not ? "matches none" : "matches at least one"} of the patterns ${listText(b.list)}`;
  if (type === "StartsWith") return `starts with ${operandText(b)}`;
  if (type === "EndsWith") return `ends with ${operandText(b)}`;
  if (type === "Alphabetically") return `is alphabetically ${b.after ? "after" : "before"} ${operandText(b.operand)}`;
  return `is ${TIME[b.time]} ${operandText(b.operand)}, as times`;
};

const conditionText = (condition) => `${leftText(condition.left)} ${phraseText(condition.phrase)}`;

const whoseText = (whose) => (whose.length === 0 ? "" : `, kept when ${whose.map(conditionText).join(" and ")},`);

const pathStarts = (path) => {
  const [type, value] = variant(path.start);
  return type === "Field" && !value.dot ? value.key : null;
};

const refKeys = (path, out) => {
  const [type] = variant(path.start);
  if (type === "Params") out.add(`$params.${path.steps[0] ? keyText(variant(path.steps[0])[1]) : ""}`);
  if (type === "Input") out.add(`$input.${path.steps[0] ? keyText(variant(path.steps[0])[1]) : ""}`);
  for (const step of path.steps) {
    const [name, body] = variant(step);
    if (name === "NamedBy" || name === "Brackets") {
      const [kind, value] = variant(body);
      if (kind === "Params") out.add(`$params.${keyText(value)}`);
      if (kind === "Input") out.add(`$input.${keyText(value)}`);
    }
  }
};

const collectPaths = (kind, tree) => {
  const paths = [];
  const itemSide = new Set();
  const fromPhrase = (phrase) => {
    const [type, b] = variant(phrase);
    const operand = (o) => {
      const [t, body] = variant(o);
      if (t === "Field") for (const term of body) fromTerm(term);
    };
    const list = (l) => {
      const [t, body] = variant(l);
      if (t === "Path") paths.push(body);
    };
    if (["Is", "Order", "Contains", "Alphabetically", "Time"].includes(type)) operand(b.operand);
    else if (type === "OneOf" || type === "Matches") list(b.list);
    else if (type === "ContainsAll" || type === "ContainsNone") list(b);
    else if (type === "StartsWith" || type === "EndsWith") operand(b);
  };
  const fromTerm = (term) => {
    const [type, body] = variant(term);
    if (type === "Path") paths.push(body);
    else if (type === "Derived") {
      paths.push(body.path);
      body.whose.forEach(fromCondition);
    } else if (type === "Elapsed") paths.push(body.from, body.to);
  };
  const fromCondition = (c) => {
    const [type, body] = variant(c.left);
    if (type === "Path") {
      paths.push(body);
      itemSide.add(body);
    } else fromTerm({ [type]: body });
    fromPhrase(c.phrase);
  };
  if (kind === "check") {
    for (const a of tree.assertions) {
      const [type, body] = variant(a);
      if (type === "Derived") body.terms.forEach(fromTerm);
      else paths.push(body.path);
      if (type === "Quantified") body.whose.forEach(fromCondition);
      fromPhrase(body.phrase);
    }
  } else if (kind === "for") {
    for (const item of tree.items) {
      const [, body] = variant(item);
      paths.push(body.path);
      body.whose.forEach(fromCondition);
      if (body.sorted_by) paths.push(body.sorted_by.path);
    }
  } else {
    paths.push(tree.path);
    if (tree.named_by_each_of) paths.push(tree.named_by_each_of);
    for (const c of tree.whose) {
      const [type, body] = variant(c);
      if (type === "Condition") fromCondition(body);
      else {
        paths.push(body.path);
        fromPhrase(body.phrase);
      }
    }
  }
  paths.itemSide = itemSide;
  return paths;
};

const forItemText = (item) => {
  const [type, b] = variant(item);
  const kept = whoseText(b.whose).replace(/,$/, "");
  if (type === "Walk") {
    const every = b.quantifier === "Every";
    const tail = every ? (b.if_any ? " (it passes when there are none)" : "") : "";
    return `${b.alias} is each item of ${pathText(b.path)}${kept}${tail}. ${every ? "The checks must hold for every one." : "The checks must hold for at least one."}`;
  }
  const order = b.sorted_by ? `, in order of ${pathText(b.sorted_by.path)}${b.sorted_by.alphabetically ? " alphabetically" : ""}` : "";
  const [place, at] = variant(b.position);
  const which = place === "Item" ? `item ${at.number}${at.from_last ? " from the end" : ""}` : `the ${place === "First" ? "first" : "last"} item`;
  return `${b.alias} is ${which} of ${pathText(b.path)}${kept}${order}.`;
};

const fromConditionText = (c) => {
  const [type, b] = variant(c);
  if (type === "Condition") return conditionText(b);
  const q = b.quantifier === "Every" ? "every" : "some";
  return `${q} ${pathText(b.path)}${b.if_any ? ", if any," : ""} ${phraseText(b.phrase)}`;
};

/** Says in plain words how a sentence is read, as a list of lines. `ctx` holds `aliases`, the `for` line's tree under `forTree` (for a check), the subject's `parts` as `{alias: path}`, and the `subjects` names (for a `from` line). */
export const describe = (kind, tree, ctx = {}) => {
  const parts = ctx.parts ?? {};
  const aliasLines = new Map();
  const forAliases = new Map();
  for (const item of ctx.forTree?.items ?? tree.items ?? []) forAliases.set(variant(item)[1].alias, forItemText(item));
  const paths = collectPaths(kind, tree);
  const names = (path) => {
    const key = pathStarts(path);
    if (key === null || paths.itemSide.has(path)) return;
    if (kind === "check" && forAliases.has(key)) aliasLines.set(key, forAliases.get(key));
    else if (Object.hasOwn(parts, key)) aliasLines.set(key, `${key} is the part of the subject at ${parts[key]}.`);
  };
  const lines = [];
  if (kind === "check") {
    const notes = [];
    const said = tree.assertions.map((a) => {
      const [type, b] = variant(a);
      if (type === "Plain") return `${pathText(b.path)} ${phraseText(b.phrase)}`;
      if (type === "Derived") return `${b.terms.map(termText).join(" plus ")} ${phraseText(b.phrase)}`;
      const every = b.quantifier === "Every";
      const rule = every
        ? b.if_any
          ? "passes when every value passes, or when none are left to check"
          : "passes when every value passes, and fails when none are left to check"
        : "passes when at least one value passes, and fails when none are left to check";
      notes.push(`${every ? "every" : "some"} walks into every list along ${pathText(b.path)}, the last one included, and ${rule}.`);
      return `${every ? "every value of" : "some value of"} ${pathText(b.path)}${whoseText(b.whose)} ${phraseText(b.phrase)}`;
    });
    if (said.length === 1) lines.push(`Passes when ${said[0]}.`);
    else lines.push("Passes when all of these hold:", ...said.map((t, i) => `${i + 1}. ${t}`));
    lines.push(...notes);
  } else if (kind === "for") {
    lines.push(`Runs the checks under it once for each combination of these items, in order: ${tree.items.map((i) => variant(i)[1].alias).join(", ")}.`);
    for (const item of tree.items) lines.push(forItemText(item));
  } else {
    const first = pathStarts(tree.path);
    const subjects = ctx.subjects ?? [];
    const own = first !== null && subjects.includes(first) && first !== ctx.subject;
    lines.push(
      `${own ? `The subject's rows come from the rows of the subject ${first}, at ${pathText(tree.path)}` : `The subject's rows come from ${pathText(tree.path)} in the input`}${tree.every ? ", walking into every list along it" : ""}.`,
    );
    if (tree.named_by_each_of) lines.push(`One row for each key listed in ${pathText(tree.named_by_each_of)}.`);
    if (tree.whose.length) lines.push(`Only rows where ${tree.whose.map(fromConditionText).join(" and ")} are in scope.`);
  }
  for (const path of paths) names(path);
  for (const step of paths.flatMap((p) => p.steps)) {
    const [name, body] = variant(step);
    if (name === "NamedBy" || name === "Brackets") {
      const [type, value] = variant(body);
      if (type === "Name" && kind === "check" && forAliases.has(value)) aliasLines.set(value, forAliases.get(value));
      else if (type === "Name" && Object.hasOwn(parts, value)) aliasLines.set(value, `${value} is the part of the subject at ${parts[value]}.`);
    }
  }
  const refs = new Set();
  for (const path of paths) refKeys(path, refs);
  for (const ref of [...refs].sort()) lines.push(ref.startsWith("$params") ? `${ref} is the value of ${ref.slice(8)} in the params the report was given.` : `${ref} is ${ref.slice(7)} in the report's input, read from the top.`);
  lines.push(...[...aliasLines.values()]);
  if (paths.some((p) => variant(p.start)[0] === "It")) lines.push("it is the subject itself.");
  return lines;
};

/** The names a `for` line gives, in order, from its tree. */
export const forAliases = (tree) => tree.items.map((item) => variant(item)[1].alias);
