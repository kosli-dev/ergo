import type {List, ListItem, Nodes, Paragraph, PhrasingContent, Root, RootContent} from "mdast";
import {fromMarkdown} from "mdast-util-from-markdown";
import {frontmatterFromMarkdown} from "mdast-util-frontmatter";
import {gfmTableFromMarkdown} from "mdast-util-gfm-table";
import {toString} from "mdast-util-to-string";
import {frontmatter} from "micromark-extension-frontmatter";
import {gfmTable} from "micromark-extension-gfm-table";
import {isMap, isScalar, parseDocument} from "yaml";

export type Problem = {line: number; message: string};

export type BlockKind =
  | "title"
  | "description"
  | "subject"
  | "requirement"
  | "field"
  | "check"
  | "option"
  | "front matter"
  | "prose";

export type Block = {kind: BlockKind; name?: string; startLine: number; endLine: number};

export type Compiled = {
  policy: Record<string, unknown> | null;
  problems: Problem[];
  blocks: Block[];
};

type Item = {
  kind: "subject" | "requirement";
  fields: Map<string, {value: unknown; line: number}>;
  description?: string;
  checks: Map<string, Record<string, unknown>> | null;
  checksSeen: boolean;
  descriptionOpen: boolean;
};

type Span = {value: string; line: number};

const NO_LABEL = "a label needs a letter or a digit";
const NOT_FIELD = "a field is written as key: `value`";
const COLON = "a bold label is followed by a colon";
const CHECK_TAIL = "a check's sentences go in code spans, with nothing else after the first one";
const OPTION_TAIL = "an option's sentences go in code spans, with nothing else after the first one";

const FIELD_KEYS = {
  subject: ["from", "identified_by"],
  requirement: ["subject", "require", "min_subjects"],
} as const;

const FIELD_START = /^(from|identified by|subject|require|min subjects)(?![\p{L}\p{N}_])/u;

const FIELD_MESSAGE = {
  subject: (key: string) => `a subject's fields are from and identified by, not "${key}"`,
  requirement: (key: string) =>
    `a requirement's fields are subject, require and min subjects, not "${key}"`,
};

const startOf = (node: {position?: {start: {line: number}}}): number => node.position?.start.line ?? 0;
const endOf = (node: {position?: {end: {line: number}}}): number => node.position?.end.line ?? 0;

const collapse = (text: string): string => text.replace(/\s+/g, " ").trim();

const labelName = (text: string): string =>
  text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "_")
    .replace(/^_+|_+$/g, "");

const plain = (nodes: PhrasingContent[]): string =>
  collapse(toString({type: "paragraph", children: nodes} satisfies Paragraph));

export function parse(markdown: string): Root {
  return fromMarkdown(markdown, {
    extensions: [frontmatter(["yaml"]), gfmTable()],
    mdastExtensions: [frontmatterFromMarkdown(["yaml"]), gfmTableFromMarkdown()],
  });
}

function readField(li: ListItem): {key: string; value: string; line: number} | null {
  const only = li.children[0];
  if (li.children.length !== 1 || only?.type !== "paragraph") return null;
  const [label, code, ...rest] = only.children;
  if (label?.type !== "text" || code?.type !== "inlineCode") return null;
  if (!rest.every((node) => node.type === "text" && node.value.trim() === "")) return null;
  const head = label.value.trimEnd();
  if (!head.endsWith(":")) return null;
  const key = head.slice(0, -1).trim();
  if (key === "") return null;
  return {key, value: code.value, line: startOf(li)};
}

function looksLikeField(li: ListItem): boolean {
  const first = li.children[0];
  return readField(li) !== null || (first?.type === "paragraph" && FIELD_START.test(toString(first).trim()));
}

function looksLikeCheck(li: ListItem): boolean {
  const first = li.children[0];
  if (first?.type !== "paragraph") return false;
  const [label, colon] = first.children;
  return (
    label?.type === "strong" &&
    colon?.type === "text" &&
    colon.value.startsWith(":") &&
    first.children.some((node) => node.type === "inlineCode")
  );
}

function scan(
  nodes: PhrasingContent[],
  started = false,
): {before: PhrasingContent[]; spans: Span[]; stray?: PhrasingContent} {
  const first = started ? 0 : nodes.findIndex((node) => node.type === "inlineCode");
  const before = first < 0 ? nodes : nodes.slice(0, first);
  const spans: Span[] = [];
  let stray: PhrasingContent | undefined;
  for (const node of first < 0 ? [] : nodes.slice(first)) {
    if (node.type === "inlineCode") spans.push({value: node.value, line: startOf(node)});
    else if (node.type !== "text" || node.value.trim() !== "") stray ??= node;
  }
  return {before, spans, stray};
}

export function compile(markdown: string): Compiled {
  const root = parse(markdown);
  const problems: Problem[] = [];
  const blocks: Block[] = [];
  const placed = new Set<ListItem>();
  const problem = (line: number, message: string) => problems.push({line, message});
  const block = (kind: BlockKind, node: RootContent | ListItem, name?: string, end?: number) =>
    blocks.push({
      kind,
      ...(name === undefined || name === "" ? {} : {name}),
      startLine: startOf(node),
      endLine: end ?? endOf(node),
    });

  const nodes = root.children;
  const lastLine = nodes.length === 0 ? 1 : endOf(nodes[nodes.length - 1]!);
  const headingLines = nodes
    .filter((node) => node.type === "heading" && node.depth <= 3)
    .map(startOf);

  let ergoSpec: {value: unknown} | null = null;
  let description: string | undefined;
  const subjects = new Map<string, Item>();
  const requirements = new Map<string, Item>();
  const subjectLines = new Map<string, number>();
  const requirementLines = new Map<string, number>();

  let titleSeen = false;
  let titleOpen = false;
  let section: "none" | "subjects" | "requirements" | "other" = "none";
  let sectionText = "";
  let item: Item | null = null;

  const describe = (sofar: string | undefined, node: Paragraph): string => {
    if (sofar === undefined) {
      block("description", node);
      return collapse(toString(node));
    }
    blocks[blocks.length - 1]!.endLine = endOf(node);
    return `${sofar}\n\n${collapse(toString(node))}`;
  };

  const claim = (scope: Map<string, number>, kind: string, name: string, line: number): boolean => {
    const earlier = scope.get(name);
    if (earlier !== undefined) {
      problem(line, `${kind} ${name} has the same name as the ${kind} on line ${earlier}`);
      return false;
    }
    scope.set(name, line);
    return true;
  };

  const readFrontMatter = (node: RootContent & {type: "yaml"}) => {
    const first = startOf(node);
    const doc = parseDocument(node.value);
    const error = doc.errors[0];
    if (error) {
      problem(first + (error.linePos?.[0].line ?? 1), "the front matter isn't valid YAML");
      return;
    }
    if (!isMap(doc.contents)) {
      problem(1, "the front matter must be keys and values");
      return;
    }
    for (const pair of doc.contents.items) {
      const key = isScalar(pair.key) ? String(pair.key.value) : String(pair.key);
      const offset = isScalar(pair.key) ? (pair.key.range?.[0] ?? 0) : 0;
      const line = first + node.value.slice(0, offset).split("\n").length;
      if (key === "ergo_spec") ergoSpec = {value: doc.toJS().ergo_spec};
      else if (key === "params") {
        problem(line, "the front matter holds only ergo_spec, not params: pass params to ergo.report");
      } else problem(line, `the front matter holds only ergo_spec, not ${key}`);
    }
  };

  const readLabel = (li: ListItem, missing: string) => {
    const para = li.children[0];
    const strong = para?.type === "paragraph" ? para.children[0] : undefined;
    if (para?.type !== "paragraph" || strong?.type !== "strong") {
      problem(startOf(li), missing);
      return null;
    }
    const colon = para.children[1];
    if (colon?.type !== "text" || !colon.value.startsWith(":")) {
      problem(startOf(strong), COLON);
      return null;
    }
    const name = labelName(toString(strong));
    if (name === "") problem(startOf(li), NO_LABEL);
    const rest: PhrasingContent[] = [{...colon, value: colon.value.slice(1)}, ...para.children.slice(2)];
    return {name, rest};
  };

  const readOptions = (list: List): Map<string, string | string[]> => {
    const options = new Map<string, string | string[]>();
    const lines = new Map<string, number>();
    for (const li of list.children) {
      const label = readLabel(li, "an option needs a bold label");
      block("option", li, label?.name);
      if (label === null) continue;
      const {before, spans, stray} = scan(label.rest);
      if (spans.length > 0 && plain(before) !== "") problem(startOf(li), "an option takes no description");
      if (spans.length === 0) problem(startOf(li), "an option needs a sentence in a code span");
      if (stray) problem(startOf(stray), OPTION_TAIL);
      for (const extra of li.children.slice(1)) problem(startOf(extra), OPTION_TAIL);
      if (label.name === "" || !claim(lines, "option", label.name, startOf(li))) continue;
      if (spans.length > 0) {
        options.set(label.name, spans.length === 1 ? spans[0]!.value : spans.map((s) => s.value));
      }
    }
    return options;
  };

  const readCheck = (li: ListItem, checks: Map<string, Record<string, unknown>>, lines: Map<string, number>) => {
    placed.add(li);
    const label = readLabel(li, "a check needs a bold label");
    block("check", li, label?.name);
    if (label === null) return;
    let k = 1;
    const paragraphs = [label.rest];
    for (let next = li.children[k]; next?.type === "paragraph"; next = li.children[++k]) paragraphs.push(next.children);
    const descriptions: string[] = [];
    const spans: Span[] = [];
    for (const children of paragraphs) {
      const found = scan(children, spans.length > 0);
      if (plain(found.before) !== "") descriptions.push(plain(found.before));
      if (found.stray) problem(startOf(found.stray), CHECK_TAIL);
      spans.push(...found.spans);
    }
    const forSpans = spans.filter((s) => s.value.startsWith("for "));
    const sentences = spans.filter((s) => !s.value.startsWith("for "));
    if (forSpans.length > 1) problem(forSpans[1]!.line, "a check has one for line");

    const nested = li.children.slice(k);
    const list = nested.find((child): child is List => child.type === "list");
    for (const extra of nested) if (extra !== list) problem(startOf(extra), CHECK_TAIL);

    let options: Map<string, string | string[]> | undefined;
    if (list) {
      if (sentences.length > 0) problem(startOf(list), "a check has sentences or options, not both");
      options = readOptions(list);
    } else if (sentences.length === 0 && forSpans.length > 0) {
      problem(forSpans[0]!.line, "a check needs a sentence besides its for line");
    } else if (sentences.length === 0) {
      problem(startOf(li), "a check needs a sentence in a code span, or a list of options");
    }

    if (label.name === "" || !claim(lines, "check", label.name, startOf(li))) return;
    const text = descriptions.join("\n\n");
    checks.set(label.name, {
      ...(text === "" ? {} : {description: text}),
      ...(forSpans.length > 0 ? {for: forSpans[0]!.value.slice(4)} : {}),
      ...(sentences.length === 0 || list
        ? {}
        : {assert: sentences.length === 1 ? sentences[0]!.value : sentences.map((s) => s.value)}),
      ...(options ? {any_of: Object.fromEntries(options)} : {}),
    });
  };

  const readChecks = (list: List, current: Item, first: boolean) => {
    const target = first ? (current.checks = new Map()) : new Map<string, Record<string, unknown>>();
    const lines = new Map<string, number>();
    for (const li of list.children) readCheck(li, target, lines);
  };

  const readFields = (list: List, current: Item) => {
    for (const li of list.children) {
      placed.add(li);
      const field = readField(li);
      block("field", li, field?.key);
      if (field === null) {
        problem(startOf(li), NOT_FIELD);
        continue;
      }
      const key = field.key.replaceAll(" ", "_");
      if (!(FIELD_KEYS[current.kind] as readonly string[]).includes(key)) {
        problem(field.line, FIELD_MESSAGE[current.kind](field.key));
        continue;
      }
      const earlier = current.fields.get(key);
      if (earlier) {
        problem(field.line, `${field.key} is already set on line ${earlier.line}`);
        continue;
      }
      if (key === "min_subjects") {
        if (/^[0-9]+$/.test(field.value)) current.fields.set(key, {value: Number(field.value), line: field.line});
        else problem(field.line, "min subjects must be a whole number");
      } else {
        current.fields.set(key, {value: field.value, line: field.line});
      }
    }
  };

  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]!;

    if (node.type === "yaml") {
      block("front matter", node);
      readFrontMatter(node);
      continue;
    }

    if (node.type === "heading") {
      titleOpen = false;
      if (item) item.descriptionOpen = false;
      const text = toString(node).trim();

      if (node.depth === 1) {
        if (titleSeen) {
          problem(startOf(node), "a policy has one # title");
          block("prose", node);
        } else {
          titleSeen = true;
          titleOpen = true;
          block("title", node);
        }
      } else if (node.depth === 2) {
        item = null;
        sectionText = text;
        section = text === "Subjects" ? "subjects" : text === "Requirements" ? "requirements" : "other";
        block("prose", node);
      } else if (node.depth === 3) {
        item = null;
        if (section === "other") {
          problem(startOf(node), `### ${text} is under "${sectionText}", which isn't Subjects or Requirements`);
          block("prose", node);
        } else if (section === "none") {
          problem(startOf(node), `### ${text} is under no ## section`);
          block("prose", node);
        } else {
          const kind = section === "subjects" ? "subject" : "requirement";
          const name = kind === "subject" ? collapse(text).toLowerCase() : labelName(text);
          const next = headingLines.find((line) => line > startOf(node));
          block(kind, node, name, next === undefined ? lastLine : next - 1);
          const created: Item = {kind, fields: new Map(), checks: null, checksSeen: false, descriptionOpen: true};
          item = created;
          if (kind === "requirement" && name === "") problem(startOf(node), NO_LABEL);
          else if (claim(kind === "subject" ? subjectLines : requirementLines, kind, name, startOf(node))) {
            (kind === "subject" ? subjects : requirements).set(name, created);
          }
        }
      } else {
        block("prose", node);
      }
      continue;
    }

    if (node.type === "paragraph") {
      const text = toString(node);
      if (item && text === "Checks:" && item.kind === "requirement") {
        item.descriptionOpen = false;
        block("field", node, "checks");
        const next = nodes[i + 1];
        if (next?.type !== "list") {
          problem(startOf(node), "Checks: must be followed by a list");
          continue;
        }
        const first = !item.checksSeen;
        if (!first) problem(startOf(node), "a requirement has one Checks: list");
        item.checksSeen = true;
        readChecks(next, item, first);
        i++;
        continue;
      }
      if (item && text !== "Checks:" && item.descriptionOpen) {
        item.description = describe(item.description, node);
        continue;
      }
      if (!item && titleOpen) {
        description = describe(description, node);
        continue;
      }
      if (item) item.descriptionOpen = false;
      titleOpen = false;
      block("prose", node);
      continue;
    }

    titleOpen = false;
    if (item) item.descriptionOpen = false;

    if (node.type === "list" && item && node.children.some(looksLikeField)) {
      readFields(node, item);
      continue;
    }

    if (node.type === "list" && section !== "other") {
      for (const li of node.children) {
        if (readField(li)) problem(startOf(li), "a field goes under a ### subject or requirement");
      }
    }
    block("prose", node);
  }

  const unplaced = (node: Nodes) => {
    if (node.type === "listItem" && placed.has(node)) return;
    if (node.type === "listItem" && looksLikeCheck(node)) problem(startOf(node), "a check goes in the list right after Checks:");
    if ("children" in node) for (const child of node.children) unplaced(child);
  };
  unplaced(root);

  problems.sort((a, b) => a.line - b.line);

  const itemOut = (it: Item, keys: readonly string[]) => ({
    ...(it.description === undefined ? {} : {description: it.description}),
    ...Object.fromEntries(keys.flatMap((key) => (it.fields.has(key) ? [[key, it.fields.get(key)!.value]] : []))),
    ...(it.checks ? {checks: Object.fromEntries(it.checks)} : {}),
  });

  const policy =
    problems.length > 0
      ? null
      : {
          ...(ergoSpec ? {ergo_spec: (ergoSpec as {value: unknown}).value} : {}),
          ...(description === undefined ? {} : {description}),
          subjects: Object.fromEntries([...subjects].map(([name, it]) => [name, itemOut(it, FIELD_KEYS.subject)])),
          requirements: Object.fromEntries(
            [...requirements].map(([name, it]) => [name, itemOut(it, FIELD_KEYS.requirement)]),
          ),
        };

  blocks.sort((a, b) => a.startLine - b.startLine);
  return {policy, problems, blocks};
}
