import {stringify} from "yaml";
import {compile, nameProblem} from "./compile.ts";

export type PathProblem = {path: string; message: string};

export type Rendered = {markdown: string | null; problems: PathProblem[]};

type Json = Record<string, unknown>;

export const NOT_BACK = "the Markdown wouldn't compile back to this policy";

export const isObject = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export const same = (a: unknown, b: unknown): boolean => {
  if (a === b) return true;
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => same(x, b[i]));
  }
  if (!isObject(a) || !isObject(b)) return false;
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((key) => Object.hasOwn(b, key) && same(a[key], b[key]));
};

const join = (path: string, key: string): string => (path === "" ? key : `${path}.${key}`);

const oneOrMore = (value: unknown): unknown =>
  Array.isArray(value) && value.length === 1 ? value[0] : value;

const normaliseCheck = (check: unknown): unknown => {
  if (typeof check === "string") return {assert: check};
  if (!isObject(check)) return check;
  const out: Json = {...check};
  if ("assert" in out) out.assert = oneOrMore(out.assert);
  if (isObject(out.any_of)) {
    out.any_of = Object.fromEntries(Object.entries(out.any_of).map(([name, option]) => [name, oneOrMore(option)]));
  }
  return out;
};

export function normalise(policy: unknown): unknown {
  if (!isObject(policy)) return policy;
  const requirements = policy.requirements ?? {};
  return {
    ...policy,
    subjects: policy.subjects ?? {},
    requirements: !isObject(requirements)
      ? requirements
      : Object.fromEntries(
          Object.entries(requirements).map(([name, requirement]) => [
            name,
            isObject(requirement) && isObject(requirement.checks)
              ? {
                  ...requirement,
                  checks: Object.fromEntries(
                    Object.entries(requirement.checks).map(([check, body]) => [check, normaliseCheck(body)]),
                  ),
                }
              : requirement,
          ]),
        ),
  };
}

const nameRefusal = (name: string): string | null => {
  if (name !== name.trim()) return "starts or ends with a space";
  if (/[^\S ]/.test(name)) return "has a tab, a line break or a space that isn't a plain one";
  if (name.includes("  ")) return "has two spaces in a row";
  if (name !== name.toLowerCase()) return "has upper case";
  return nameProblem(name);
};

const codeRefusal = (value: unknown): string | null => {
  if (typeof value !== "string") return "isn't text";
  if (value === "") return "is empty";
  if (value.includes("`")) return "has a backtick, which a code span can't hold";
  if (/[\r\n]/.test(value)) return "has a line break";
  return value === value.trim() ? null : "starts or ends with a space";
};

const descriptionRefusal = (value: unknown, inItem: boolean): string | null => {
  if (typeof value !== "string") return value === null ? "is null: leave it out instead" : "isn't text";
  if (value === "") return "is empty: leave it out instead";
  const paragraphs = value.split("\n\n");
  if (paragraphs.some((p) => p === "" || p !== p.replace(/\s+/g, " ").trim())) {
    return "has spaces or line breaks the Markdown can't keep";
  }
  if (inItem && paragraphs.includes("Checks:")) {
    return "has a paragraph that is just Checks:, which the Markdown reads as the start of the checks";
  }
  return null;
};

const NO_PARTS = "the Markdown can't hold parts yet: write this policy in YAML";
const NO_META = "the Markdown can't hold meta yet: write this policy in YAML";

export function refusals(policy: unknown): PathProblem[] {
  const out: PathProblem[] = [];
  const refuse = (path: string, message: string | null) => {
    if (message !== null) out.push({path, message});
  };

  const sentences = (path: string, value: unknown, underAssert: boolean) => {
    const list = Array.isArray(value) ? value : [value];
    if (list.length === 0) refuse(path, "is empty");
    list.forEach((sentence, i) => {
      const at = Array.isArray(value) ? join(path, String(i)) : path;
      refuse(at, codeRefusal(sentence));
      if (underAssert && typeof sentence === "string" && sentence.startsWith("for ")) {
        refuse(at, "starts with for, so the Markdown would read it as the check's for line: write .for");
      }
    });
  };

  const check = (path: string, body: unknown) => {
    if (!isObject(body)) return refuse(path, "isn't a sentence or an object");
    for (const [key, value] of Object.entries(body)) {
      const at = join(path, key);
      if (key === "description") refuse(at, descriptionRefusal(value, false));
      else if (key === "assert") sentences(at, value, true);
      else if (key === "for") refuse(at, codeRefusal(value));
      else if (key === "any_of") {
        if (!isObject(value)) refuse(at, "isn't an object");
        else if (Object.keys(value).length === 0) refuse(at, "is empty");
        else {
          for (const [name, option] of Object.entries(value)) {
            refuse(join(at, name), nameRefusal(name));
            sentences(join(at, name), option, false);
          }
        }
      } else if (key === "meta") refuse(at, NO_META);
      else refuse(at, `the Markdown has no place for ${key}`);
    }
    if ("assert" in body && "any_of" in body) refuse(path, "has both assert and any_of");
    if (!("assert" in body) && !("any_of" in body)) refuse(path, "needs assert or any_of");
  };

  const item = (path: string, body: unknown, kind: "subject" | "requirement") => {
    if (body === null) return refuse(path, "is null: give it a from");
    if (!isObject(body)) return refuse(path, "isn't an object");
    for (const [key, value] of Object.entries(body)) {
      const at = join(path, key);
      if (key === "description") refuse(at, descriptionRefusal(value, true));
      else if (kind === "subject" && (key === "from" || key === "identified_by")) refuse(at, codeRefusal(value));
      else if (kind === "subject" && key === "has") refuse(at, NO_PARTS);
      else if (kind === "requirement" && (key === "subject" || key === "require")) refuse(at, codeRefusal(value));
      else if (kind === "requirement" && key === "min_subjects") {
        if (!Number.isSafeInteger(value) || (value as number) < 0) refuse(at, "isn't a whole number of 0 or more");
      } else if (kind === "requirement" && key === "checks") {
        if (!isObject(value)) refuse(at, "isn't an object");
        else if (Object.keys(value).length === 0) refuse(at, "is empty: give it a check, or leave checks out");
        else {
          for (const [name, body] of Object.entries(value)) {
            refuse(join(at, name), nameRefusal(name));
            check(join(at, name), body);
          }
        }
      } else if (kind === "requirement" && key === "meta") refuse(at, NO_META);
      else refuse(at, `the Markdown has no field ${key}`);
    }
  };

  const normal = normalise(policy);
  if (!isObject(normal)) return [{path: "", message: "a policy is an object"}];
  for (const [key, value] of Object.entries(normal)) {
    if (key === "ergo_spec") continue;
    if (key === "description") refuse(key, descriptionRefusal(value, false));
    else if (key === "subjects" || key === "requirements") {
      if (!isObject(value)) {
        refuse(key, "isn't an object");
        continue;
      }
      for (const [name, body] of Object.entries(value)) {
        refuse(join(key, name), nameRefusal(name));
        item(join(key, name), body, key === "subjects" ? "subject" : "requirement");
      }
    } else if (key === "meta") refuse(key, NO_META);
    else refuse(key, `the Markdown has no place for ${key}`);
  }
  return out;
}

const firstDifference = (got: unknown, want: unknown, path: string): string | null => {
  if (same(got, want)) return null;
  if (!isObject(got) || !isObject(want)) return path;
  for (const key of new Set([...Object.keys(want), ...Object.keys(got)])) {
    const found = firstDifference(got[key], want[key], join(path, key));
    if (found !== null) return found;
  }
  return path;
};

export function notBack(markdown: string, policy: unknown): PathProblem[] {
  const compiled = compile(markdown);
  const path = compiled.problems.length > 0 ? "" : firstDifference(compiled.policy, normalise(policy), "");
  return path === null ? [] : [{path, message: NOT_BACK}];
}

export const escapeText = (text: string, where: "inline" | "line start" | "heading" = "inline"): string => {
  let out = text
    .replace(/[\\`*[\]<>]/g, "\\$&")
    .replace(/(?<![\p{L}\p{N}])_|_(?![\p{L}\p{N}])/gu, "\\_")
    .replace(/&(?=#?[\p{L}\p{N}]+;)/gu, "\\&");
  if (where === "heading") out = out.replace(/#/g, "\\#");
  if (where === "line start") out = out.replace(/^[#+=~-]/, "\\$&").replace(/^(\d+)([.)])/, "$1\\$2");
  return out;
};

export const label = (name: string): string => {
  const first = name[0]!;
  const upper = first.toUpperCase();
  return escapeText(upper.length === 1 && upper.toLowerCase() === first ? upper + name.slice(1) : name);
};

const paragraphs = (description: unknown): string[] =>
  typeof description === "string" ? description.split("\n\n").map((p) => escapeText(p, "line start")) : [];

const list = (value: unknown): string[] => (Array.isArray(value) ? value : [value]) as string[];

const FIELD_WORDS: Record<string, string> = {
  from: "From",
  identified_by: "Identified by",
  subject: "Subject",
  require: "Require",
  min_subjects: "Min subjects",
};

export const fieldLine = (key: string, value: unknown, bullet = "- "): string =>
  `${bullet}${FIELD_WORDS[key]} \`${String(value)}\``;

export const FIELD_ORDER = {
  subject: ["from", "identified_by"],
  requirement: ["subject", "require", "min_subjects"],
} as const;

export type Kept = {head?: string[]; sameLine?: boolean; strong?: string; options?: Map<string, string>};

export function checkLines(name: string, body: unknown, bullet = "- ", kept: Kept = {}): string[] {
  const check = normaliseCheck(body) as Json;
  const pad = " ".repeat(bullet.length);
  const [first, ...rest] = paragraphs(check.description);
  const strong = kept.strong ?? `**${label(name)}**`;
  const lines = kept.head ?? [`${bullet}${strong}:${first === undefined ? "" : ` ${first}`}`];
  if (kept.head === undefined) for (const p of rest) lines.push("", `${pad}${p}`);
  const spans = [...(typeof check.for === "string" ? [`for ${check.for}`] : []), ...("assert" in check ? list(check.assert) : [])];
  const sameLine = kept.sameLine ?? first === undefined;
  if (sameLine && spans.length === 1 && !isObject(check.any_of)) lines[lines.length - 1] += ` \`${spans[0]}\``;
  else for (const span of spans) lines.push(`${pad}\`${span}\``);
  if (isObject(check.any_of)) {
    for (const [option, sentences] of Object.entries(check.any_of)) {
      const spansOf = list(sentences);
      const optionLabel = kept.options?.get(option) ?? `**${label(option)}**`;
      if (spansOf.length === 1) lines.push(`${pad}- ${optionLabel}: \`${spansOf[0]}\``);
      else lines.push(`${pad}- ${optionLabel}:`, ...spansOf.map((span) => `${pad}  \`${span}\``));
    }
  }
  return lines;
}

export function itemLines(kind: "subject" | "requirement", name: string, body: Json): string[] {
  const lines = [`### ${label(name).replace(/#/g, "\\#")}`];
  for (const p of paragraphs(body.description)) lines.push("", p);
  const fields = FIELD_ORDER[kind].filter((key) => key in body);
  if (fields.length > 0) lines.push("", ...fields.map((key) => fieldLine(key, body[key])));
  if (isObject(body.checks)) {
    lines.push("", "Checks:", "");
    for (const [check, checkBody] of Object.entries(body.checks)) lines.push(...checkLines(check, checkBody));
  }
  return lines;
}

export const frontMatterLines = (ergoSpec: unknown): string[] => [
  "---",
  ...stringify({ergo_spec: ergoSpec}, {lineWidth: 0}).trimEnd().split("\n"),
  "---",
];

export const descriptionLines = (description: unknown): string[] =>
  paragraphs(description).flatMap((p, i) => (i === 0 ? [p] : ["", p]));

export function render(policy: object): Rendered {
  const problems = refusals(policy);
  if (problems.length > 0) return {markdown: null, problems};
  const normal = normalise(policy) as Json;
  const parts: string[][] = [];
  if ("ergo_spec" in normal) parts.push(frontMatterLines(normal.ergo_spec));
  if ("description" in normal) parts.push(descriptionLines(normal.description));
  for (const [section, kind] of [
    ["Subjects", "subject"],
    ["Requirements", "requirement"],
  ] as const) {
    parts.push([`## ${section}`]);
    const items = normal[section.toLowerCase()] as Json;
    for (const [name, body] of Object.entries(items)) parts.push(itemLines(kind, name, body as Json));
  }
  const markdown = `${parts.map((lines) => lines.join("\n")).join("\n\n")}\n`;
  const back = notBack(markdown, policy);
  return back.length > 0 ? {markdown: null, problems: back} : {markdown, problems: []};
}
