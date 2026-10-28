import { compile, parse } from "@kosli/ergo-markdown";
import opa from "@open-policy-agent/opa-wasm";
import { layoutRows, policySheet, yamlText, markOf, parseJson, makeRunner, parseTime, reportTables, plural } from "./lib.mjs";

const { samples, wasm } = window.EDITOR;
const LH = 22;
const PAD = 12;
const $ = (id) => document.getElementById(id);
const src = $("src");
const gutter = $("gutter");
const panel = $("panel");
const diags = $("diags");
const bands = $("bands");

let current = Object.keys(samples)[0];
let tab = "blocks";
let last = null;
let syncing = false;
let runner = null;
let runnerError = "";
let reportInput = "";
let reportParams = "";

const store = {
  get(k) {
    try {
      return localStorage.getItem("ergo-editor:" + k);
    } catch {
      return null;
    }
  },
  set(k, v) {
    try {
      localStorage.setItem("ergo-editor:" + k, v);
    } catch {
      return;
    }
  },
  del(k) {
    try {
      localStorage.removeItem("ergo-editor:" + k);
    } catch {
      return;
    }
  },
};

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
};

const kindClass = (kind) => kind.replace(/ /g, "-");
const GROUP = { check: "check", option: "check", subject: "declare", requirement: "declare", field: "declare", checks: "declare", prose: "prose" };
const TAGS = { "front matter": "front matter" };

const viewBlocks = (result) => {
  const rows = layoutRows(result, src.value, parseTree(src.value));
  const total = src.value.split("\n").length;
  const map = el("div", "map");
  map.style.height = total * LH + PAD * 2 + "px";
  for (const row of rows) {
    const box = el("div", `mblk g-${GROUP[row.kind] ?? "other"}${row.problems.length ? " has-problem" : ""}`);
    box.style.top = (row.top - 1) * LH + PAD + "px";
    box.style.height = row.height * LH + "px";
    box.append(el("span", "tag", TAGS[row.kind] ?? row.kind));
    const body = el("span", "body");
    const CLASS = { name: "name", said: "said", sentence: "said sentence", value: "said value", source: "detail", quiet: "quiet" };
    if (row.head.length) {
      const [first, ...rest] = row.head;
      const head = el("span", CLASS[first.kind], first.text);
      for (const line of rest) head.append(el("span", CLASS[line.kind], line.text));
      body.append(head);
    }
    for (const line of row.below) body.append(el("span", line.kind === "sentence" ? "detail sentence" : "detail", line.text));
    for (const message of row.problems) body.append(el("span", "problem", message));
    box.append(body);
    box.addEventListener("click", () => goto(row.top));
    map.append(box);
  }
  panel.replaceChildren(map);
  panel.scrollTop = src.scrollTop;
};

const sentenceLines = (sentences, into) => {
  for (const s of sentences) into.append(el("div", "expr", s));
};

const viewPolicy = (result) => {
  const sheet = policySheet(result.policy);
  if (!sheet) {
    panel.replaceChildren(el("p", "empty", "The policy has problems, so there is nothing to show yet. The problems are listed below the editor."));
    return;
  }
  const spec = el("div", "spec");
  if (sheet.description) spec.append(el("p", "empty words", sheet.description));
  if (sheet.subjects.length) {
    const card = el("div", "req");
    const head = el("header");
    head.append(el("h3", null, "Subjects"));
    card.append(head);
    for (const s of sheet.subjects) {
      card.append(el("div", "grouphead", s.name));
      if (s.description) card.append(el("div", "subj words", s.description));
      const line = el("div", "subj");
      const a = el("span");
      a.append(document.createTextNode("from "), el("code", null, s.from));
      const b = el("span");
      b.append(document.createTextNode("identified by "), el("code", null, s.identifiedBy));
      line.append(a, b);
      card.append(line);
    }
    spec.append(card);
  }
  for (const r of sheet.requirements) {
    const card = el("div", "req");
    const head = el("header");
    head.append(el("span", "id", r.name), el("h3", null, r.name.replace(/_/g, " ")));
    if (r.description) head.append(el("p", "words", r.description));
    const badges = el("div", "badges");
    badges.append(
      el("span", "badge", "subject: " + r.subject),
      el("span", "badge", "require: " + r.require),
      el("span", "badge", "min subjects: " + r.minSubjects),
    );
    head.append(badges);
    card.append(head);
    if (r.checks.length) card.append(el("div", "grouphead", "Checks"));
    for (const c of r.checks) {
      const row = el("div", "chk");
      row.append(el("span", "cname", c.name));
      if (c.description) row.append(el("div", "desc words", c.description));
      if (c.for) row.append(el("div", "expr for", c.for));
      sentenceLines(c.sentences, row);
      if (c.options.length) {
        const nest = el("div", "nest");
        nest.append(el("div", "role", "passes when any one of these is met"));
        for (const o of c.options) {
          const inner = el("div", "nest");
          inner.append(el("div", "role", o.name));
          sentenceLines(o.sentences, inner);
          nest.append(inner);
        }
        row.append(nest);
      }
      card.append(row);
    }
    spec.append(card);
  }
  panel.replaceChildren(spec);
};

const inline = (nodes, into) => {
  for (const n of nodes ?? []) {
    if (n.type === "text") into.append(document.createTextNode(n.value));
    else if (n.type === "inlineCode") into.append(el("code", null, n.value));
    else if (n.type === "strong") {
      const s = el("strong");
      inline(n.children, s);
      into.append(s);
    } else if (n.type === "emphasis") {
      const s = el("em");
      inline(n.children, s);
      into.append(s);
    } else if (n.type === "delete") {
      const s = el("s");
      inline(n.children, s);
      into.append(s);
    } else if (n.type === "break") into.append(document.createTextNode(" "));
    else if (n.children) inline(n.children, into);
    else if (n.value) into.append(document.createTextNode(n.value));
  }
};

const block = (node, blocks) => {
  if (node.type === "heading") {
    const h = el("h" + Math.min(3, node.depth));
    inline(node.children, h);
    return h;
  }
  if (node.type === "thematicBreak") return el("hr");
  if (node.type === "code") return el("pre", null, node.value);
  if (node.type === "blockquote") {
    const q = el("blockquote");
    for (const c of node.children ?? []) q.append(block(c, blocks));
    return q;
  }
  if (node.type === "list") {
    const list = el(node.ordered ? "ol" : "ul");
    for (const item of node.children ?? []) {
      const li = el("li");
      for (const c of item.children ?? []) li.append(block(c, blocks));
      const mark = markOf(item, blocks);
      if (mark) li.classList.add("mark", "mark-" + mark);
      list.append(li);
    }
    return list;
  }
  if (node.type === "table") {
    const wrap = el("div", "tw");
    const t = el("table");
    (node.children ?? []).forEach((row, i) => {
      const tr = el("tr");
      for (const cell of row.children ?? []) {
        const c = el(i === 0 ? "th" : "td");
        inline(cell.children, c);
        tr.append(c);
      }
      t.append(tr);
    });
    wrap.append(t);
    return wrap;
  }
  const p = el("p");
  inline(node.children, p);
  return p;
};

const parseTree = (text) => {
  try {
    return parse(text);
  } catch {
    return { children: [] };
  }
};

const viewDoc = (result) => {
  const tree = parseTree(src.value);
  const doc = el("div", "doc");
  for (const node of tree.children) {
    const out = block(node, result.blocks);
    const mark = node.type === "list" ? null : markOf(node, result.blocks);
    if (mark) out.classList.add("mark", "mark-" + mark);
    doc.append(out);
  }
  panel.replaceChildren(doc.children.length ? doc : el("p", "empty", "Nothing to show yet."));
};

const viewYaml = (result) => {
  const text = yamlText(result.policy);
  panel.replaceChildren(
    text ? el("pre", "yaml", text) : el("p", "empty", "The policy has problems, so there is no YAML yet."),
  );
};

const table = (t) => {
  const wrap = el("div");
  const head = el("h3", null, t.name.replace(/_/g, " "));
  head.append(el("span", "status", t.status.replace(/_/g, " ")));
  wrap.append(head);
  if (t.rows.length) {
    const scroll = el("div", "tw");
    const tb = el("table");
    const hr = el("tr");
    hr.append(el("th", null, "Subject"));
    for (const c of t.checks) hr.append(el("th", null, c));
    tb.append(hr);
    for (const row of t.rows) {
      const tr = el("tr");
      tr.append(el("td", null, row.subject));
      for (const c of t.checks) {
        const cell = row.cells[c];
        const td = el("td", cell ? (cell.passed ? "pass" : "fail") : "");
        if (cell) {
          td.append(document.createTextNode(cell.passed ? "passed" : "failed"));
          if (!cell.passed) td.append(el("small", null, cell.cause));
        }
        tr.append(td);
      }
      tb.append(tr);
    }
    scroll.append(tb);
    wrap.append(scroll);
  }
  if (t.general.length) {
    const scroll = el("div", "tw");
    const tb = el("table");
    const hr = el("tr");
    hr.append(el("th", null, "Rule about the requirement itself"), el("th", null, "Result"));
    tb.append(hr);
    for (const g of t.general) {
      const tr = el("tr");
      tr.append(el("td", null, g.check), el("td", g.passed ? "pass" : "fail", g.passed ? "passed" : "failed: " + g.cause));
      tb.append(tr);
    }
    scroll.append(tb);
    scroll.style.marginTop = ".6rem";
    wrap.append(scroll);
  }
  return wrap;
};

const showReport = (out, result) => {
  out.replaceChildren();
  if (runnerError) return out.append(el("p", "notice", runnerError));
  if (!runner) return out.append(el("p", "notice info", "Ergo is still loading."));
  if (!result.policy) return out.append(el("p", "notice", "The policy has problems, so it can't run yet. The problems are listed below the editor."));
  const input = parseJson(reportInput, "input");
  if (!input.ok) return out.append(el("p", "notice", input.message));
  const params = parseJson(reportParams, "params");
  if (!params.ok) return out.append(el("p", "notice", params.message));
  let report;
  try {
    report = runner(input.value, result.policy, params.value);
  } catch (e) {
    return out.append(el("p", "notice", "Ergo couldn't run this: " + e.message));
  }
  if (report === null) return out.append(el("p", "notice", "Ergo gave no report for this policy and input."));
  out.append(el("p", "notice info", report.compliant ? "Every requirement is met." : "At least one requirement is not met."));
  for (const t of reportTables(report)) out.append(table(t));
  const raw = el("details");
  raw.append(el("summary", null, "The full report as JSON"), el("pre", null, JSON.stringify(report, null, 2)));
  out.append(raw);
};

const viewReport = (result) => {
  const run = el("div", "run");
  const inputLabel = el("label", null, "Input");
  const inputBox = el("textarea");
  inputBox.value = reportInput;
  inputBox.spellcheck = false;
  inputLabel.append(inputBox);
  const paramsLabel = el("label", null, "Params");
  const paramsBox = el("textarea", "short");
  paramsBox.value = reportParams;
  paramsBox.spellcheck = false;
  paramsLabel.append(paramsBox);
  const out = el("div");
  out.style.display = "flex";
  out.style.flexDirection = "column";
  out.style.gap = "1rem";
  let timer = 0;
  const again = () => {
    reportInput = inputBox.value;
    reportParams = paramsBox.value;
    clearTimeout(timer);
    timer = setTimeout(() => showReport(out, last), 200);
  };
  inputBox.addEventListener("input", again);
  paramsBox.addEventListener("input", again);
  run.append(inputLabel, paramsLabel, out);
  panel.replaceChildren(run);
  showReport(out, result);
};

const NOTES = {
  blocks: "Each block sits next to the lines it came from.",
  policy: "The policy as Ergo reads it, in plain words.",
  doc: "A coloured edge marks text that Ergo acts on.",
  yaml: "The same policy in YAML, ready to use.",
  report: "Runs the policy on the input in your browser.",
};

const render = (result) => {
  last = result;
  const lines = src.value.split("\n");
  const kinds = new Array(lines.length).fill("");
  for (const b of result.blocks) {
    for (let i = b.startLine; i <= b.endLine && i <= lines.length; i++) kinds[i - 1] = kindClass(b.kind);
  }
  const badLines = new Set(result.problems.map((p) => p.line));
  gutter.replaceChildren(
    ...lines.map((_, i) => el("div", "gline" + (kinds[i] ? " k-" + kinds[i] : "") + (badLines.has(i + 1) ? " bad" : ""), String(i + 1))),
  );
  bands.replaceChildren(
    ...result.blocks
      .filter((b) => b.kind !== "prose")
      .map((b) => {
        const band = el("div", "band b-" + kindClass(b.kind));
        band.style.top = (b.startLine - 1) * LH + PAD + "px";
        band.style.height = (b.endLine - b.startLine + 1) * LH + "px";
        return band;
      }),
  );
  bands.style.transform = `translateY(${-src.scrollTop}px)`;

  $("n-req").textContent = plural(result.blocks.filter((b) => b.kind === "requirement").length, "requirement");
  $("n-chk").textContent = plural(result.blocks.filter((b) => b.kind === "check").length, "check");
  $("n-diag-wrap").textContent = plural(result.problems.length, "problem");
  $("n-diag-wrap").classList.toggle("bad", result.problems.length > 0);

  diags.hidden = result.problems.length === 0;
  diags.replaceChildren(
    ...result.problems.map((p) => {
      const b = el("button", "diag");
      b.append(el("span", "where", "line " + p.line), el("span", null, p.message));
      b.addEventListener("click", () => goto(p.line));
      return b;
    }),
  );

  $("note").textContent = NOTES[tab];
  if (tab === "blocks") viewBlocks(result);
  else if (tab === "policy") viewPolicy(result);
  else if (tab === "doc") viewDoc(result);
  else if (tab === "yaml") viewYaml(result);
  else viewReport(result);
};

const goto = (line) => {
  src.scrollTop = Math.max(0, (line - 1) * LH - 60);
  src.focus();
  const pos = src.value.split("\n").slice(0, line - 1).join("\n").length + (line > 1 ? 1 : 0);
  src.setSelectionRange(pos, pos);
  const g = gutter.children[line - 1];
  if (g) {
    g.classList.add("hit");
    setTimeout(() => g.classList.remove("hit"), 700);
  }
};

const recompile = () => {
  let result;
  try {
    result = compile(src.value);
  } catch (e) {
    result = { policy: null, blocks: [], problems: [{ line: 1, message: "Ergo couldn't read this document. " + (e?.message ?? e) }] };
  }
  render(result);
  store.set(current, src.value);
};

let timer = 0;
src.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(recompile, 150);
});
src.addEventListener("scroll", () => {
  if (syncing) return;
  syncing = true;
  gutter.scrollTop = src.scrollTop;
  bands.style.transform = `translateY(${-src.scrollTop}px)`;
  if (tab === "blocks") panel.scrollTop = src.scrollTop;
  syncing = false;
});
panel.addEventListener("scroll", () => {
  if (syncing || tab !== "blocks") return;
  syncing = true;
  src.scrollTop = panel.scrollTop;
  gutter.scrollTop = panel.scrollTop;
  bands.style.transform = `translateY(${-panel.scrollTop}px)`;
  syncing = false;
});
for (const ev of ["keyup", "click"]) {
  src.addEventListener(ev, () => {
    $("cursor").textContent = "line " + (src.value.slice(0, src.selectionStart).split("\n").length);
  });
}

const buttons = {};
const load = (which) => {
  current = which;
  for (const [name, b] of Object.entries(buttons)) b.setAttribute("aria-pressed", String(name === which));
  src.value = store.get(which) ?? samples[which].source;
  reportInput = JSON.stringify(samples[which].input, null, 2);
  reportParams = JSON.stringify(samples[which].params, null, 2);
  src.scrollTop = 0;
  recompile();
};
for (const name of Object.keys(samples)) {
  const b = el("button", null, name);
  b.setAttribute("aria-pressed", "false");
  b.addEventListener("click", () => load(name));
  buttons[name] = b;
  $("samples").insertBefore(b, $("s-reset"));
}
$("s-reset").addEventListener("click", () => {
  store.del(current);
  load(current);
});

const TABS = [["t-blocks", "blocks"], ["t-policy", "policy"], ["t-doc", "doc"], ["t-yaml", "yaml"], ["t-report", "report"]];
for (const [id, name] of TABS) {
  $(id).addEventListener("click", () => {
    tab = name;
    for (const [i, n] of TABS) $(i).setAttribute("aria-selected", String(n === name));
    panel.scrollTop = 0;
    if (last) render(last);
  });
}
$("copy").addEventListener("click", async () => {
  const b = $("copy");
  try {
    await navigator.clipboard.writeText(yamlText(last?.policy));
    b.textContent = "Copied";
  } catch {
    b.textContent = "Blocked";
  }
  setTimeout(() => {
    b.textContent = "Copy YAML";
  }, 1400);
});

const bytes = Uint8Array.from(atob(wasm), (c) => c.charCodeAt(0));
opa.loadPolicy(bytes, undefined, { "time.parse_rfc3339_ns": parseTime }).then(
  (policy) => {
    runner = makeRunner((doc) => policy.evaluate(doc));
    if (tab === "report" && last) render(last);
  },
  (e) => {
    runnerError = "Ergo didn't load: " + e.message;
    if (tab === "report" && last) render(last);
  },
);

load(current);
