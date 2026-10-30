import { compile, parse } from "@kosli/ergo-markdown";
import opa from "@open-policy-agent/opa-wasm";
import { initSync, report as rustReport } from "ergo-wasm";
import { ENGINES, ENGINE_LABELS, readEngine, engineNote, engineMessage, makeRustRunner, stopOnPanic, timed, loadEngine } from "./engines.mjs";
import { highlightMarkdown, highlightYaml } from "./highlight.mjs";
import { editFromYaml, markdownFromPaste } from "./twoway.mjs";
import { VIEWS, LABELS, pick, readLayout, layoutText } from "./layout.mjs";
import { savedEdit, saveEdit, forgetEdit } from "./saved.mjs";
import { layoutRows, policySheet, yamlText, markOf, kindAt, docGroups, parseJson, makeRunner, parseTime, reportTables, plural, reportDocument, unroundable } from "./lib.mjs";

const { samples, wasm, rustWasm } = window.EDITOR;
const LH = 22;
const PAD = 12;
const $ = (id) => document.getElementById(id);
const src = $("src");
const gutter = $("gutter");
const diags = $("diags");
const bands = $("bands");
const hl = $("hl");

let current = Object.keys(samples)[0];
let last = null;
let syncing = false;
const runners = {};
const runnerErrors = {};
let reportInput = "";
let reportParams = "";

const storage = (() => {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
})();
const remember = (key, value) => {
  try {
    storage.setItem("ergo-editor:" + key, value);
  } catch {
    return;
  }
};
const recall = (key) => {
  try {
    return storage.getItem("ergo-editor:" + key);
  } catch {
    return null;
  }
};
let layout = readLayout(recall("layout"));
let engine = readEngine(recall("engine"));
const shows = (view) => layout.left === view || layout.right === view;

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
};

const paint = (into, lines) => {
  const frag = document.createDocumentFragment();
  lines.forEach((tokens, i) => {
    if (i) frag.append("\n");
    for (const t of tokens) frag.append(t.kind === "plain" ? document.createTextNode(t.text) : el("span", "h-" + t.kind, t.text));
  });
  into.replaceChildren(frag);
};

const follow = () => {
  bands.style.transform = `translateY(${-src.scrollTop}px)`;
  hl.style.transform = `translate(${-src.scrollLeft}px, ${-src.scrollTop}px)`;
};

const drawSource = () => {
  paint(hl, highlightMarkdown(src.value, last?.blocks ?? []));
  hl.append("\n");
  follow();
};

const yamlBox = el("textarea", "code");
yamlBox.spellcheck = false;
yamlBox.setAttribute("aria-label", "Policy in YAML");
const yamlHl = el("pre", "hl");
const yamlNotes = el("div", "diags");
yamlNotes.hidden = true;
const yamlPane = (() => {
  const layer = el("div", "hlwrap");
  layer.setAttribute("aria-hidden", "true");
  layer.append(yamlHl);
  const field = el("div", "field");
  field.append(layer, yamlBox);
  const pane = el("div", "yamlpane");
  pane.append(field, yamlNotes);
  return pane;
})();
let yamlProblems = [];
let yamlPending = false;
let noteTimer = 0;
let flashing = false;
const yamlUndo = [];

const drawYaml = () => {
  paint(yamlHl, highlightYaml(yamlBox.value));
  yamlHl.append("\n");
  yamlHl.style.transform = `translate(${-yamlBox.scrollLeft}px, ${-yamlBox.scrollTop}px)`;
};

const showYamlNotes = (problems, changes) => {
  yamlNotes.hidden = !problems.length && !changes.length;
  yamlNotes.replaceChildren(
    ...problems.map((p) => {
      const row = el("div", "diag");
      row.append(el("span", "where", p.path), el("span", null, p.message));
      return row;
    }),
    ...changes.map((c) => {
      const row = el("div", "diag done");
      row.append(el("span", "where", "changed"), el("span", null, c));
      return row;
    }),
    ...(changes.length && yamlUndo.length
      ? [
          (() => {
            const b = el("button", "ghost undo", "Undo the YAML change");
            b.title = "Put the Markdown back as it was before this change (Ctrl+Z or ⌘Z in the Markdown does the same)";
            b.addEventListener("click", undoYaml);
            return b;
          })(),
        ]
      : []),
  );
};

const undoYaml = () => {
  const step = yamlUndo[yamlUndo.length - 1];
  if (!step || src.value !== step.after) return false;
  yamlUndo.pop();
  src.value = step.before;
  clearTimeout(noteTimer);
  showYamlNotes([], []);
  recompile();
  if (last && shows("yaml")) viewYaml(last);
  return true;
};

const fromYaml = () => {
  clearTimeout(yamlTimer);
  yamlPending = false;
  const out = editFromYaml(src.value, yamlBox.value);
  yamlProblems = out.problems;
  clearTimeout(noteTimer);
  if (out.markdown === null) return showYamlNotes(out.problems, []);
  if (out.markdown !== src.value) {
    yamlUndo.push({ before: src.value, after: out.markdown });
    src.value = out.markdown;
    recompile();
  }
  showYamlNotes([], out.changes);
};

const flash = (text) => {
  flashing = true;
  $("note").textContent = text;
  setTimeout(() => {
    flashing = false;
    if (!flashing) $("note").textContent = noteText();
  }, 4000);
};

const kindClass = (kind) => kind.replace(/ /g, "-");
const GROUP = { check: "check", option: "check", subject: "declare", requirement: "declare", field: "declare", checks: "declare", prose: "prose" };
const TAGS = { "front matter": "front matter" };

const viewBlocks = (result, into) => {
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
  into.replaceChildren(map);
  if (shows("markdown")) into.scrollTop = src.scrollTop;
};

const sentenceLines = (sentences, into) => {
  for (const s of sentences) into.append(el("div", "expr", s));
};

const viewPolicy = (result, into) => {
  const sheet = policySheet(result.policy);
  if (!sheet) {
    into.replaceChildren(el("p", "empty", "The policy has problems, so there is nothing to show yet. The problems are listed below the editor."));
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
    if (r.title !== r.name) head.append(el("span", "id", r.name));
    head.append(el("h3", null, r.title));
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
  into.replaceChildren(spec);
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
    const kind = kindAt(node, blocks);
    if (kind) list.classList.add("k-" + kind);
    for (const item of node.children ?? []) {
      const li = el("li");
      for (const c of item.children ?? []) li.append(block(c, blocks));
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
  if (node.type === "paragraph" && kindAt(node, blocks) === "checks") return el("p", "label", "Checks");
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

const viewDoc = (result, into) => {
  const tree = parseTree(src.value);
  const doc = el("div", "doc");
  for (const item of docGroups(tree.children)) {
    const node = item.heading ?? item;
    let out;
    if (item.heading) {
      out = el("section", "sec");
      for (const n of item.nodes) out.append(block(n, result.blocks));
    } else out = block(item, result.blocks);
    const mark = node.type === "list" ? null : markOf(node, result.blocks);
    if (mark) out.classList.add("mark", "mark-" + mark);
    doc.append(out);
  }
  into.replaceChildren(doc.children.length ? doc : el("p", "empty", "Nothing to show yet."));
};

const viewYaml = (result) => {
  if (document.activeElement !== yamlBox) {
    yamlBox.value = yamlText(result.policy);
    drawYaml();
    yamlProblems = [];
    clearTimeout(noteTimer);
    const undoable = yamlUndo.length && yamlUndo[yamlUndo.length - 1].after === src.value;
    if (!undoable) showYamlNotes(result.policy ? [] : [{ path: "Markdown", message: "The Markdown has problems, so there is no YAML for it yet." }], []);
  }
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
  if (runnerErrors[engine]) return out.append(el("p", "notice", runnerErrors[engine]));
  if (!runners[engine]) return out.append(el("p", "notice info", engineMessage(engine, "loading")));
  if (!result.policy) return out.append(el("p", "notice", "The policy has problems, so it can't run yet. The problems are listed below the editor."));
  const input = parseJson(reportInput, "input");
  if (!input.ok) return out.append(el("p", "notice", input.message));
  const params = parseJson(reportParams, "params");
  if (!params.ok) return out.append(el("p", "notice", params.message));
  let report;
  try {
    report = runners[engine](reportInput, result.policy, reportParams);
  } catch (e) {
    return out.append(el("p", "notice", e.stopped ? e.message : engineMessage(engine, "run", e.message)));
  }
  if (report === null) return out.append(el("p", "notice", "Ergo gave no report for this policy and input."));
  out.append(el("p", "notice info", [report.compliant ? "Every requirement is met." : "At least one requirement is not met.", engineNote(report, timers[engine]?.ms)].filter(Boolean).join(" ")));
  const rounded = [...new Set([...unroundable(reportInput), ...unroundable(reportParams)])];
  if (rounded.length) {
    out.append(
      el(
        "p",
        "notice info",
        `Ergo checked ${rounded.join(", ")} as written, but this page shows ${rounded.length === 1 ? "it" : "them"} rounded, because a JavaScript number can't hold ${rounded.length === 1 ? "it" : "them"}.`,
      ),
    );
  }
  for (const t of reportTables(report)) out.append(table(t));
  const raw = el("details");
  raw.append(el("summary", null, "The full report as JSON"), el("pre", null, JSON.stringify(report, null, 2)));
  out.append(raw);
};

const viewReport = (result, into) => {
  const run = el("div", "run");
  const engineLabel = el("label", null, "Engine");
  const engineBox = el("select");
  for (const e of ENGINES) {
    const option = el("option", null, ENGINE_LABELS[e]);
    option.value = e;
    engineBox.append(option);
  }
  engineBox.value = engine;
  engineLabel.append(engineBox);
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
  engineBox.addEventListener("change", () => {
    engine = readEngine(engineBox.value);
    remember("engine", engine);
    showReport(out, last);
  });
  inputBox.addEventListener("input", again);
  paramsBox.addEventListener("input", again);
  run.append(engineLabel, inputLabel, paramsLabel, out);
  into.replaceChildren(run);
  showReport(out, result);
};

const NOTES = {
  markdown: "Write the policy as a document.",
  blocks: "Each block sits next to the lines it came from.",
  policy: "The policy as Ergo reads it, in plain words.",
  doc: "A coloured edge marks text that Ergo acts on.",
  yaml: "Edit the YAML and the Markdown follows a second after you stop typing, or straight away with Ctrl+Enter (⌘Enter). Paste a YAML policy into an empty document to start from it.",
  report: "Runs the policy on the input in your browser.",
};

const noteText = () => NOTES[layout.right === "markdown" ? layout.left : layout.right];

const mdView = $("mdview");
const cursor = $("cursor");
const copy = $("copy");
const panes = Object.fromEntries(
  ["left", "right"].map((side) => {
    const root = $("pane-" + side);
    const tabs = {};
    const list = root.querySelector(".tablist");
    for (const view of VIEWS) {
      const b = el("button", "tab", LABELS[view]);
      b.addEventListener("click", () => choose(side, view));
      tabs[view] = b;
      list.append(b);
    }
    const panel = el("div", "panel");
    panel.addEventListener("scroll", () => {
      if (syncing || layout[side] !== "blocks" || !shows("markdown")) return;
      syncing = true;
      src.scrollTop = panel.scrollTop;
      gutter.scrollTop = panel.scrollTop;
      follow();
      syncing = false;
    });
    return [side, { tabs, panel, body: root.querySelector(".body"), tools: root.querySelector(".tools") }];
  }),
);

const place = (into, node) => {
  if (node.parentNode !== into) into.replaceChildren(node);
};

const drawPane = (side, result) => {
  const pane = panes[side];
  const view = layout[side];
  for (const [name, b] of Object.entries(pane.tabs)) b.setAttribute("aria-selected", String(name === view));
  if (view === "markdown") {
    place(pane.body, mdView);
    place(pane.tools, cursor);
    gutter.scrollTop = src.scrollTop;
    follow();
    return;
  }
  if (view === "yaml") {
    place(pane.body, yamlPane);
    place(pane.tools, copy);
    viewYaml(result);
    return;
  }
  pane.tools.replaceChildren();
  place(pane.body, pane.panel);
  if (view === "blocks") viewBlocks(result, pane.panel);
  else if (view === "policy") viewPolicy(result, pane.panel);
  else if (view === "doc") viewDoc(result, pane.panel);
  else viewReport(result, pane.panel);
};

const choose = (side, view) => {
  const before = layout;
  layout = pick(layout, side, view);
  remember("layout", layoutText(layout));
  for (const s of ["left", "right"]) if (layout[s] !== before[s]) panes[s].panel.scrollTop = 0;
  if (last) render(last);
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
  drawSource();

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

  if (!flashing) $("note").textContent = noteText();
  drawPane("left", result);
  drawPane("right", result);
};

const goto = (line) => {
  if (!shows("markdown")) choose(layout.left === "blocks" ? "right" : "left", "markdown");
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
  const saved = saveEdit(storage, current, samples[current].source, src.value);
  const edited = src.value !== samples[current].source;
  $("s-edited").textContent = !edited ? "" : saved ? "your edited version" : "your edited version (not saved)";
  $("s-edited").title = edited && !saved ? "This browser won't let the page save your edit, so a reload gives the sample back." : "";
  $("s-edited").classList.toggle("unsaved", edited && !saved);
};

let timer = 0;
src.addEventListener("input", () => {
  drawSource();
  clearTimeout(timer);
  timer = setTimeout(recompile, 150);
});
let yamlTimer = 0;
yamlBox.addEventListener("input", () => {
  drawYaml();
  yamlPending = true;
  clearTimeout(yamlTimer);
  yamlTimer = setTimeout(fromYaml, 1000);
});
yamlBox.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
    e.preventDefault();
    fromYaml();
  }
});
src.addEventListener("keydown", (e) => {
  if (e.key.toLowerCase() === "z" && (e.metaKey || e.ctrlKey) && !e.shiftKey && undoYaml()) e.preventDefault();
});
yamlBox.addEventListener("scroll", () => {
  yamlHl.style.transform = `translate(${-yamlBox.scrollLeft}px, ${-yamlBox.scrollTop}px)`;
});
yamlBox.addEventListener("blur", () => {
  if (yamlPending) fromYaml();
  if (!yamlProblems.length && last && shows("yaml")) viewYaml(last);
});
src.addEventListener("paste", (e) => {
  if (src.value.trim()) return;
  const markdown = markdownFromPaste(e.clipboardData?.getData("text/plain") ?? "");
  if (!markdown) return;
  e.preventDefault();
  src.value = markdown;
  recompile();
  flash("Wrote a Markdown document from the pasted YAML.");
});
src.addEventListener("scroll", () => {
  if (syncing) return;
  syncing = true;
  gutter.scrollTop = src.scrollTop;
  follow();
  for (const side of ["left", "right"]) if (layout[side] === "blocks") panes[side].panel.scrollTop = src.scrollTop;
  syncing = false;
});
for (const ev of ["keyup", "click"]) {
  src.addEventListener(ev, () => {
    cursor.textContent = "line " + (src.value.slice(0, src.selectionStart).split("\n").length);
  });
}

const buttons = {};
const load = (which) => {
  current = which;
  for (const [name, b] of Object.entries(buttons)) b.setAttribute("aria-pressed", String(name === which));
  const edit = savedEdit(storage, which, samples[which].source);
  src.value = edit.text;
  yamlUndo.length = 0;
  if (edit.dropped) flash(`Your saved edit of ${which} was dropped, because the sample changed since you made it.`);
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
  forgetEdit(storage, current, samples[current].source);
  load(current);
});

copy.addEventListener("click", async () => {
  const b = copy;
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

const decode = (text) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
const timers = {};
const loaded = (name, timer, run) => {
  timers[name] = timer;
  loadEngine(runners, name, run);
  if (shows("report") && last) render(last);
};
const failed = (name, e) => {
  runnerErrors[name] = engineMessage(name, "failed", e.message);
  if (shows("report") && last) render(last);
};
opa.loadPolicy(decode(wasm), undefined, { "time.parse_rfc3339_ns": parseTime }).then(
  (policy) => {
    const evaluate = timed((doc) => policy.evaluate(doc));
    const run = makeRunner(evaluate);
    loaded("opa", evaluate, (inputText, policyValue, paramsText) => run(reportDocument(inputText, policyValue, paramsText)));
  },
  (e) => failed("opa", e),
);
try {
  initSync({ module: decode(rustWasm) });
  const report = timed(rustReport);
  loaded("rust", report, stopOnPanic("rust", makeRustRunner(report)));
} catch (e) {
  failed("rust", e);
}

load(current);
