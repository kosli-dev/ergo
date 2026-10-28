import { stringify } from "yaml";

export const parseTime = (v) => {
  if (!JSON.rawJSON) throw new Error("this browser can't hold a time in nanoseconds exactly, so compare_time can't run here");
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

export const makeRunner = (evaluate) => (input, policy, params) => {
  const out = evaluate({ input, policy, params });
  return out?.length && out[0].result !== undefined ? out[0].result : null;
};

export const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

export const yamlText = (policy) => (policy ? stringify(policy, { lineWidth: 0 }) : "");

const textOf = (node) => (typeof node?.value === "string" ? node.value : (node?.children ?? []).map(textOf).join(""));

export const headingText = (tree, line) => {
  const node = (tree?.children ?? []).find((n) => n.type === "heading" && n.position?.start?.line === line);
  return node ? textOf(node) : "";
};

const fieldKey = (name) => name.replace(/ /g, "_");

const sentencesRead = (block, check) => {
  if (!check) return null;
  if (block.kind === "check") return [...(check.for ? [check.for] : []), ...sentencesOf(check.assert)];
  if (block.kind === "option" && check.any_of && Object.hasOwn(check.any_of, block.name)) return sentencesOf(check.any_of[block.name]);
  return null;
};

const linesOf = (block, height, raw, at, more, checks) => {
  const item = (kind, text) => ({ kind, text: String(text) });
  if (block.kind === "front matter") {
    return { head: at.policy?.ergo_spec ? [item("name", "ergo_spec"), item("value", at.policy.ergo_spec)] : [item("source", raw)], below: [] };
  }
  if (block.kind === "title") return { head: [item("name", headingText(at.tree, block.startLine) || raw)], below: [] };
  if (block.kind === "prose") return { head: [item("quiet", raw)], below: [] };
  if (block.kind === "checks") return { head: [item("name", plural(checks, "check"))], below: [] };
  if (block.kind === "description") return { head: [item("source", raw)], below: more.map((line) => item("source", line || "\u00a0")) };
  const head = block.name ? [item("name", block.name)] : [];
  if (block.kind === "field") {
    const value = at.owner?.[fieldKey(block.name ?? "")];
    if (value !== undefined && typeof value !== "object") head.push(item("value", value));
    return { head, below: [] };
  }
  if (block.kind === "check" || block.kind === "option") {
    const sentences = sentencesRead(block, at.check);
    if (!sentences) return { head, below: height > 1 ? [item("source", raw)] : [] };
    if (block.kind === "check" && at.check.description) head.push(item("said", at.check.description));
    const lines = sentences.map((text) => item("sentence", text));
    return height > 1 ? { head, below: lines } : { head: [...head, ...lines], below: [] };
  }
  return { head, below: [] };
};

const checksAfter = (sorted, i) => {
  let count = 0;
  for (const b of sorted.slice(i + 1)) {
    if (b.kind === "check") count++;
    else if (b.kind !== "option") break;
  }
  return count;
};

export const layoutRows = (result, source = "", tree = null) => {
  const lines = source.split("\n");
  const sorted = [...result.blocks].sort((a, b) => a.startLine - b.startLine || b.endLine - a.endLine);
  const at = { policy: result.policy, tree, owner: null, requirement: null, check: null };
  const rows = sorted.map((b, i) => {
    if (b.kind === "subject") at.owner = result.policy?.subjects?.[b.name] ?? null;
    if (b.kind === "requirement") at.owner = at.requirement = result.policy?.requirements?.[b.name] ?? null;
    if (b.kind === "check") at.check = at.requirement?.checks?.[b.name] ?? null;
    const next = sorted[i + 1];
    const endLine = next && next.startLine <= b.endLine ? Math.max(b.startLine, next.startLine - 1) : b.endLine;
    const height = endLine - b.startLine + 1;
    return {
      top: b.startLine,
      height,
      kind: b.kind,
      ...linesOf(b, height, (lines[b.startLine - 1] ?? "").trim(), at, lines.slice(b.startLine, endLine).map((line) => line.trim()), checksAfter(sorted, i)),
      problems: result.problems.filter((p) => p.line >= b.startLine && p.line <= endLine).map((p) => p.message),
    };
  });
  const loose = result.problems
    .filter((p) => !rows.some((r) => p.line >= r.top && p.line < r.top + r.height))
    .map((p) => ({ top: p.line, height: 1, kind: "problem", head: [], below: [], problems: [p.message] }));
  return [...rows, ...loose].sort((a, b) => a.top - b.top);
};

const sentencesOf = (assert) => (assert === undefined ? [] : Array.isArray(assert) ? assert : [assert]);

const checkSheet = (name, check) => ({
  name,
  description: check.description ?? "",
  sentences: sentencesOf(check.assert),
  for: check.for ?? "",
  options: Object.entries(check.any_of ?? {}).map(([optionName, option]) => ({
    name: optionName,
    sentences: sentencesOf(option),
  })),
});

export const policySheet = (policy) => {
  if (!policy) return null;
  return {
    description: policy.description ?? "",
    subjects: Object.entries(policy.subjects ?? {}).map(([name, s]) => ({
      name,
      description: s.description ?? "",
      from: s.from ?? "",
      identifiedBy: s.identified_by ?? "",
    })),
    requirements: Object.entries(policy.requirements ?? {}).map(([name, r]) => ({
      name,
      title: name.replace(/_/g, " "),
      description: r.description ?? "",
      subject: r.subject ?? "",
      require: r.require ?? "every",
      minSubjects: r.min_subjects ?? 1,
      checks: Object.entries(r.checks ?? {}).map(([checkName, check]) => checkSheet(checkName, check)),
    })),
  };
};

const GROUPS = { check: "check", option: "check", subject: "declare", requirement: "declare", field: "declare", checks: "declare" };
const PRIORITY = ["check", "declare", "other"];

export const markOf = (node, blocks) => {
  const start = node.position?.start?.line;
  const end = node.position?.end?.line;
  if (start === undefined) return null;
  const groups = blocks
    .filter((b) => b.kind !== "prose" && b.startLine <= end && b.endLine >= start)
    .map((b) => GROUPS[b.kind] ?? "other");
  return PRIORITY.find((g) => groups.includes(g)) ?? null;
};

export const parseJson = (text, what) => {
  let value;
  try {
    value = JSON.parse(text);
  } catch (e) {
    return { ok: false, message: `The ${what} isn't valid JSON yet. ${e.message}` };
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, message: `The ${what} needs to be an object, in curly brackets.` };
  }
  return { ok: true, value };
};

const subjectLabel = (subject) => {
  const parents = Object.entries(subject.in ?? {}).map(([k, v]) => `${k} ${v}`);
  return [String(subject.id), ...(parents.length ? [`in ${parents.join(", ")}`] : [])].join(" ");
};

export const reportTables = (report) => {
  const rows = report?.results ?? [];
  return Object.entries(report?.requirements ?? {}).map(([name, requirement]) => {
    const mine = rows.filter((r) => r.requirement === name);
    const checks = [];
    const subjects = new Map();
    const general = [];
    for (const row of mine) {
      const cell = { passed: row.passed === true, cause: String(row.cause ?? "") };
      if (row.subject?.id === null || row.subject?.id === undefined) {
        general.push({ check: row.check, ...cell });
        continue;
      }
      if (!checks.includes(row.check)) checks.push(row.check);
      const label = subjectLabel(row.subject);
      if (!subjects.has(label)) subjects.set(label, {});
      subjects.get(label)[row.check] = cell;
    }
    return {
      name,
      status: requirement.status ?? "",
      checks,
      rows: [...subjects].map(([subject, cells]) => ({ subject, cells })),
      general,
    };
  });
};
