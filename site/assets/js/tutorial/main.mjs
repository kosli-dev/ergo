import opa from "../../tutorial/vendor/opa-wasm.mjs";
import { defaultCell, cellHighlight, makeRunner, bakeryBatches, defaultNames, checkLines, nameProblem, nameCoach, tutorialPolicy, lineResults, verdict, verdictWord, requirementCoach, gridFromReport, cellLine, subjectsStatus, subjectsCoach, yamlLines, layoutMetrics, createEnterGate, serializeProgress, restoreProgress, layoutLines, keyAction, goalKindAt, parseInput, clampPosition, dotTargets, resultLine, freshDraft, dimResult, jsonSegments, fieldHighlights, segmentClasses, isAt, evidence, grade, intro, makeChecker, parseTime, positions, showMeVisible, steps, straighten } from "./lib.mjs";

const root = document.getElementById("tutorial");
const $ = (name) => root.querySelector(`[data-${name}]`);
const el = {
  dots: $("dots"), menuWrap: $("menu-wrap"), menuButton: $("menu-button"), menu: $("menu"), intro: $("intro"), step: $("step"), end: $("end"), goal: $("goal"), result: $("result"),
  fixed: $("input-fixed"), input: $("input"), restartStep: $("restart-step"), startOver: $("start-over"), sentence: $("sentence"),
  stage: $("stage"), count: $("count"), coach: $("coach"), showme: $("showme"), back: $("back"), next: $("next"),
};

const rich = (text) => {
  const frag = document.createDocumentFragment();
  text.split("`").forEach((part, i) => {
    if (i % 2) {
      const c = document.createElement("code");
      c.textContent = part;
      frag.append(c);
    } else {
      frag.append(part);
    }
  });
  return frag;
};

const make = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};

const store = {
  read() {
    try { return JSON.parse(localStorage.getItem("ergo-tutorial")) ?? {}; } catch { return {}; }
  },
  write(v) {
    try { localStorage.setItem("ergo-tutorial", JSON.stringify(v)); } catch {}
  },
};

const closeMenu = (refocus = false) => {
  el.menu.hidden = true;
  el.menuButton.setAttribute("aria-expanded", "false");
  if (refocus) el.menuButton.focus();
};
const items = () => [...el.menu.querySelectorAll("button:not([hidden])")];
const openMenu = () => {
  el.menu.hidden = false;
  el.menuButton.setAttribute("aria-expanded", "true");
  items()[0]?.focus();
};

const keyhint = $("keyhint");
const END = positions.length;
const drafts = {};
let check = null;
let pos = 0;
let touched = false;
let idleTimer;
let timer;
let dirty = false;
const gate = createEnterGate();
let lastKey = "";
let met = false;

const here = () => positions[pos];
const goalNow = () => steps[here().step].goal;

const fit = (box) => {
  box.style.height = "auto";
  box.style.height = `${box.scrollHeight}px`;
};

const saveDraft = () => {
  const step = here()?.step ?? -1;
  if (step >= 0) {
    drafts[step].sentence = el.sentence.value;
    drafts[step].input = el.input.value;
    persist();
  }
};

const message = (cls, glyph, word, extra) => {
  const wrap = make("div", `tut__state ${cls}`);
  const big = make("p", "tut__verdict");
  big.append(make("span", "tut__glyph", glyph), make("span", "tut__word", word));
  wrap.append(big, ...extra);
  return wrap;
};

const show = (shown) => {
  let node;
  let key;
  if (!check) {
    node = make("p", "tut__loading mono", "loading ergo…");
    key = "loading";
  } else if (shown.state !== "result") {
    node = make("div", "tut__state");
    key = "blank";
  } else {
    const line = resultLine(shown);
    const detail = make("p", "tut__detail mono");
    detail.append(make("span", "tut__cause", line.cause), make("span", "tut__rest", ` · ${line.rest}`));
    const big = make("p", "tut__verdict");
    big.append(make("span", "tut__glyph", shown.passed ? "✓" : "×"), make("span", "tut__word", shown.passed ? "passed" : "failed"));
    node = make("div", `tut__state ${shown.passed ? "is-passed" : "is-failed"}`);
    node.append(big, detail);
    key = `${shown.passed}:${shown.cause}:${JSON.stringify(shown.inputs)}`;
  }
  if (key === lastKey) return;
  lastKey = key;
  el.result.replaceChildren(node);
  node.classList.add("is-new");
};

const showGoal = () => {
  const g = goalNow();
  el.goal.replaceChildren(rich(g.ask));
};

const showCoach = (say, shown, tick) => {
  el.coach.className = `tut__coach is-${say.kind}`;
  const nodes = [rich(say.text)];
  if (tick && shown?.state === "result") {
    nodes.unshift(make("span", `tut__mini ${shown.passed ? "t" : "f"}`, shown.passed ? "✓" : "×"));
  }
  el.coach.replaceChildren(...nodes);
};

const updateShowMe = (idleMs = 0) => {
  el.showme.hidden = met || !goalNow().answer || !showMeVisible({ touched, idleMs });
};

const restartIdle = () => {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => updateShowMe(20000), 20000);
};

const setNext = () => {
  el.next.disabled = !met;
  el.next.classList.toggle("is-ready", met);
  keyhint.classList.toggle("is-ready", met);
};

const draft = () => drafts[here().step];

const renderPredict = () => {
  const wrap = make("div", "tut__predict");
  for (const word of ["passed", "failed"]) {
    const b = make("button", `tut__pick tut__pick--${word}`, word);
    b.type = "button";
    b.addEventListener("click", () => { draft().choice = word; persist(); evaluate(); });
    wrap.append(b);
  }
  el.result.replaceChildren(wrap);
  lastKey = "predict";
};

const evaluate = (typed = false) => {
  if (here().step < 0) return;
  if (isCustom()) return evaluateStage();
  if (!check) return show(null);
  const s = steps[here().step];
  const g = goalNow();
  const d = draft();
  const result = grade(g, check, el.sentence.value, s.editable ? el.input.value : s.input, d.choice ?? null);
  const hidden = g.kind === "predict" && !d.choice;
  if (hidden) {
    if (lastKey !== "predict") renderPredict();
  } else {
    show(result.shown);
  }
  met = result.met;
  showGoal();
  showCoach(result.say, result.shown, !hidden);
  el.result.classList.toggle("is-dim", dimResult(g, result.shown, met));
  setNext();
  updateShowMe();
  if (gate.evaluated(met)) el.next.click();
};

const schedule = () => { dirty = true; clearTimeout(timer); timer = setTimeout(() => { dirty = false; evaluate(true); }, 150); };


const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;


const customKinds = new Set(["names", "requirement", "subjects", "policy"]);
const isCustom = () => customKinds.has(goalNow().kind);
const runner = { run: null };
const stageState = { selected: null, view: "policy", hover: "", grid: null, cell: null, full: false };
const refs = {};

const fieldsOf = (step) => drafts[step]?.fields ?? {};
const nameFor = () => {
  const n = fieldsOf(8).name ?? "";
  return nameProblem(n) ? defaultNames.name : n;
};
const headingFor = () => (fieldsOf(9).heading ?? "").trim() || defaultNames.heading;
const policyFor = () => tutorialPolicy({ name: nameFor(), heading: headingFor(), from: fieldsOf(10).from || defaultNames.from, id: fieldsOf(10).id || defaultNames.id });

const tick = (passed) => {
  const s = make("span", `tut__tick ${passed === true ? "t" : passed === false ? "f" : ""}`, passed === true ? "✓" : passed === false ? "×" : "");
  return s;
};

const textField = (key, placeholder, cls) => {
  const input = make("input", `tut__field mono ${cls}`);
  input.type = "text";
  input.setAttribute("data-field", key);
  input.placeholder = placeholder;
  input.autocomplete = "off";
  input.autocapitalize = "off";
  input.spellcheck = false;
  input.setAttribute("autocorrect", "off");
  input.enterKeyHint = "done";
  input.setAttribute("aria-label", placeholder);
  input.value = draft().fields[key] ?? "";
  input.addEventListener("input", () => {
    draft().fields[key] = input.value;
    gate.typed();
    persist();
    evaluate();
  });
  return input;
};

const lineRow = (tag, parts) => {
  const row = make(tag, "tut__row");
  if (tag === "button") row.type = "button";
  const mark = tick(null);
  const text = make("span", "tut__rowtext mono");
  text.append(...parts);
  row.append(mark, text);
  return { row, mark };
};

const fitTall = () => {
  if (!steps[here()?.step]?.collapse || el.step.hidden) return true;
  const cs = getComputedStyle(el.step);
  const shown = [...el.step.children].filter((c) => !c.hidden);
  const others = shown.filter((c) => c !== el.fixed && c !== el.result).reduce((n, c) => n + c.getBoundingClientRect().height, 0);
  const free = el.step.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom) - (parseFloat(cs.rowGap) || 0) * (shown.length - 1) - others - Math.max(178, el.result.firstElementChild?.offsetHeight ?? 0);
  for (let f = 14; f >= 11; f -= 0.5) {
    el.fixed.style.fontSize = `${f}px`;
    if (el.fixed.offsetHeight <= free) return true;
  }
  el.fixed.style.fontSize = "11px";
  return false;
};

const updateCell = () => {
  const f = draft().fields;
  const [id, name] = (stageState.selected ?? "").split("|");
  const sentence = checkLines(nameFor()).find((l) => l.name === name)?.sentence;
  stageState.cell = stageState.grid && sentence ? cellHighlight(parseInput(el.input.value).value, (f.from ?? "").trim(), (f.id ?? "").trim(), id, sentence) : null;
};

const layoutBatches = () => {
  const s = steps[here()?.step];
  if (!s?.collapse || el.step.hidden) return;
  updateCell();
  stageState.full = false;
  if (stageState.grid) {
    stageState.full = true;
    showView(s, draft());
    if (fitTall()) return;
    stageState.full = false;
  }
  showView(s, draft());
  fitTall();
};

const hoverLine = (sentence) => {
  stageState.hover = sentence;
  applyHighlight();
};

const buildStage = (kind) => {
  el.stage.replaceChildren();
  el.stage.classList.toggle("is-fill", kind === "policy");
  refs.rows = [];
  const lines = checkLines(nameFor());
  if (kind === "names") {
    const wrap = make("div", "tut__rows");
    lines.forEach((l, i) => {
      let lead = `${l.name}: `;
      if (i === 0) {
        lead = make("span", "tut__namewrap");
        lead.append(textField("name", "____", "tut__namefield"), make("span", "tut__colon", ":"), " ");
      }
      const { row, mark } = lineRow("div", [lead, l.sentence]);
      row.addEventListener("mouseenter", () => hoverLine(l.sentence));
      row.addEventListener("mouseleave", () => hoverLine(""));
      row.addEventListener("focusin", () => hoverLine(l.sentence));
      row.addEventListener("focusout", () => hoverLine(""));
      wrap.append(row);
      refs.rows.push(mark);
    });
    el.stage.append(wrap);
  } else if (kind === "requirement") {
    const head = textField("heading", "a heading, like Safe to sell", "tut__headfield");
    const wrap = make("div", "tut__rows");
    refs.buttons = [];
    lines.forEach((l) => {
      const { row, mark } = lineRow("button", [`${l.name}: ${l.sentence}`]);
      row.addEventListener("mouseenter", () => hoverLine(l.sentence));
      row.addEventListener("mouseleave", () => hoverLine(""));
      row.addEventListener("focus", () => hoverLine(l.sentence));
      row.addEventListener("blur", () => hoverLine(""));
      row.addEventListener("click", () => {
        draft().fields.tapped = l.name;
        persist();
        evaluate();
      });
      wrap.append(row);
      refs.rows.push(mark);
      refs.buttons.push(row);
    });
    el.stage.append(head, wrap);
  } else if (kind === "subjects") {
    const mk = (label, key, placeholder) => {
      const lab = make("label", "tut__ask");
      lab.append(make("span", "", label), textField(key, placeholder, "tut__smallfield"));
      return lab;
    };
    el.stage.append(mk("Where are the batches?", "from", "a key"), mk("What names each one?", "id", "a field"));
  } else if (kind === "policy") {
    const sw = make("div", "tut__switch");
    sw.setAttribute("role", "group");
    for (const view of ["policy", "report"]) {
      const b = make("button", "tut__tab", view);
      b.type = "button";
      b.dataset.view = view;
      b.addEventListener("click", () => {
        stageState.view = view;
        stageState.note = "";
        renderPolicyBox();
        evaluate();
      });
      sw.append(b);
    }
    refs.box = make("div", "tut__box");
    el.stage.append(sw, refs.box);
    renderPolicyBox();
  }
};

const renderPolicyBox = () => {
  for (const b of el.stage.querySelectorAll(".tut__tab")) b.setAttribute("aria-pressed", String(b.dataset.view === stageState.view));
  const policy = policyFor();
  if (stageState.view === "policy") {
    const pre = make("div", "tut__yaml mono");
    for (const line of yamlLines(policy)) {
      const b = make("button", "tut__yl", line.text.trim());
      b.type = "button";
      b.style.setProperty("--ind", line.text.length - line.text.trimStart().length);
      b.addEventListener("click", () => {
        stageState.note = line.note;
        showCoach({ kind: "phrase", text: line.note }, null, false);
      });
      pre.append(b);
    }
    refs.box.replaceChildren(pre);
  } else {
    const report = runner.run ? runner.run(bakeryBatches, policy) : null;
    const pre = make("pre", "tut__report mono", JSON.stringify(report, null, 2) ?? "");
    pre.tabIndex = 0;
    refs.box.replaceChildren(pre);
  }
};

const evaluateStage = () => {
  if (!runner.run) return;
  const kind = goalNow().kind;
  const f = draft().fields;
  let say = { kind: "phrase", text: "" };
  el.result.hidden = kind === "policy";
  if (kind === "names") {
    const name = f.name ?? "";
    const report = runner.run(JSON.parse(steps[8].input), tutorialPolicy({ name: nameProblem(name) ? defaultNames.name : name, heading: defaultNames.heading }));
    lineResults(report, nameProblem(name) ? defaultNames.name : name).forEach((l, i) => { refs.rows[i].replaceWith((refs.rows[i] = tick(l.passed))); });
    say = nameCoach(name);
    el.result.replaceChildren();
  } else if (kind === "requirement") {
    const heading = (f.heading ?? "").trim();
    const name = nameFor();
    const key = heading === "" ? "x" : heading;
    const policy = tutorialPolicy({ name, heading: key });
    const report = runner.run(JSON.parse(steps[9].input), policy);
    const results = lineResults(report, name);
    results.forEach((l, i) => { refs.rows[i].replaceWith((refs.rows[i] = tick(l.passed))); });
    refs.buttons.forEach((b, i) => b.classList.toggle("is-picked", heading !== "" && f.tapped === results[i].name));
    say = requirementCoach({ heading, tapped: f.tapped ?? "" }, results);
    if (heading === "") {
      el.result.replaceChildren();
    } else {
      const status = verdict(report, Object.keys(report.requirements)[0]);
      const ok = status === "met";
      const big = make("p", "tut__verdict");
      big.append(make("span", "tut__glyph", ok ? "✓" : "×"), make("span", "tut__word", verdictWord(status)));
      const node = make("div", `tut__state ${ok ? "is-passed" : "is-failed"}`);
      node.append(big);
      el.result.replaceChildren(node);
    }
  } else if (kind === "subjects") {
    const from = (f.from ?? "").trim();
    const id = (f.id ?? "").trim();
    const name = nameFor();
    const heading = headingFor();
    stageState.grid = null;
    const report = from === "" ? null : runner.run(bakeryBatches, tutorialPolicy({ name, heading, from, id: id || "id" }));
    const state = subjectsStatus({ from, id }, report);
    say = subjectsCoach({ from, id }, state);
    el.result.replaceChildren(say.met ? gridNode(report, heading, name) : make("div"));
    if (!stageState.grid) stageState.selected = null;
    applyHighlight();
  } else if (kind === "policy") {
    say = { kind: "phrase", text: stageState.note || "This is YAML. You can write the same policy in JSON." };
  }
  met = kind === "policy" ? true : say.met;
  showGoal();
  showCoach(say, null, false);
  setNext();
  el.showme.hidden = true;
  applyHighlight();
  layoutBatches();
  if (gate.evaluated(met)) el.next.click();
};

const gridNode = (report, heading, name) => {
  const names = checkLines(name).map((l) => l.name);
  const key = Object.keys(report.requirements)[0];
  const grid = gridFromReport(report, key, names);
  stageState.grid = grid;
  if (!stageState.selected || !grid.cells[stageState.selected]) stageState.selected = defaultCell(grid);
  const wrap = make("div", "tut__gridwrap");
  const status = grid.status === "met";
  const head = make("p", `tut__gridhead ${status ? "t" : "f"}`);
  head.append(make("span", "tut__mini", status ? "✓" : "×"), `${heading}: ${verdictWord(grid.status)}`);
  const table = make("div", "tut__grid mono");
  table.style.setProperty("--cols", names.length);
  table.append(make("span", ""), ...names.map((n) => make("span", "tut__colhead", n)));
  const detail = make("p", "tut__celldetail mono", stageState.selected ? cellLine(grid, ...stageState.selected.split("|")) : "");
  for (const id of grid.ids) {
    table.append(make("span", "tut__rowhead", grid.shortId(id)));
    for (const n of names) {
      const c = grid.cells[`${id}|${n}`];
      const b = make("button", `tut__cell ${c.passed ? "t" : "f"}`, c.passed ? "✓" : "×");
      b.type = "button";
      b.setAttribute("aria-label", `${grid.shortId(id)} ${n} ${c.passed ? "passed" : "failed"}`);
      b.classList.toggle("is-picked", stageState.selected === `${id}|${n}`);
      b.addEventListener("click", () => {
        stageState.selected = `${id}|${n}`;
        detail.textContent = cellLine(grid, id, n);
        for (const o of table.querySelectorAll(".tut__cell")) o.classList.remove("is-picked");
        b.classList.add("is-picked");
        layoutBatches();
      });
      table.append(b);
    }
  }
  wrap.append(head, table, detail);
  return wrap;
};

const showEditing = (on) => {
  draft().editing = on;
  persist();
  el.fixed.hidden = on;
  el.input.hidden = !on;
  if (on) fit(el.input);
};

let viewSegs = [];

const customHighlights = (value) => {
  const kind = goalNow().kind;
  if (kind === "subjects") return subjectHighlights(value);
  if (kind === "names" || kind === "requirement") {
    const tapped = kind === "requirement" ? checkLines(nameFor()).find((l) => l.name === draft().fields.tapped)?.sentence : "";
    return fieldHighlights(stageState.hover || tapped || "", value);
  }
  return [];
};

const subjectHighlights = (value) => {
  const f = draft().fields;
  const from = (f.from ?? "").trim();
  const id = (f.id ?? "").trim();
  if (from === "") return [];
  const hls = [fieldHighlights(from, value)[0]];
  if (id !== "") hls.push(fieldHighlights(`every ${from}.${id}`, value)[0]);
  return hls;
};

const applyHighlight = () => {
  if (!viewSegs.length) return;
  const value = parseInput(el.input.value).value;
  if (goalNow().kind === "subjects" && stageState.grid) {
    const cell = stageState.cell;
    for (const { node, seg } of viewSegs) {
      node.className = cell?.hl && seg.slot === cell.slot ? segmentClasses(seg, cell.hl).join(" ") : "";
    }
    return;
  }
  const hl = !value ? [] : isCustom() ? customHighlights(value) : fieldHighlights(el.sentence.value, value);
  for (const { node, seg } of viewSegs) {
    node.className = segmentClasses(seg, hl).join(" ");
  }
};

const viewOptions = (s) => {
  if (s.collapse !== true) return { flat: s.flat === true };
  if (!stageState.grid) return { collapse: true };
  if (stageState.full) return { shortIds: (draft().fields.id ?? "").trim() };
  return { collapse: true, expand: stageState.cell?.slot };
};

const showView = (s, d) => {
  viewSegs = [];
  el.fixed.style.fontSize = "";
  const parsed = parseInput(el.input.value);
  if (!parsed.ok) {
    el.fixed.textContent = el.input.value;
    return;
  }
  const mark = s.view?.mark;
  const flash = !reduced() && !d.viewed;
  const segs = jsonSegments(parsed.value, viewOptions(s));
  const laid = layoutLines(segs);
  const metrics = layoutMetrics(laid);
  const tall = metrics.lines > 1 || s.flat === true;
  for (const box of [el.fixed, el.input]) {
    box.classList.toggle("is-tall", tall);
    box.style.setProperty("--lines", metrics.lines);
    box.style.setProperty("--cols", metrics.cols);
    box.style.setProperty("--min", s.collapse ? "11px" : "12px");
  }
  const nodes = segs.map((seg) => {
    const node = make("span", "", seg.text);
    viewSegs.push({ node, seg });
    return node;
  });
  const blocks = laid.map((line) => {
    const block = make("div", "tut__ln");
    block.style.setProperty("--ind", line.indent);
    for (const part of line.parts) {
      const node = nodes[part.index];
      node.textContent = node.textContent === part.text ? node.textContent : part.text;
      block.append(node);
    }
    return block;
  });
  el.fixed.replaceChildren(...blocks);
  applyHighlight();
  if (flash && mark) for (const { node, seg } of viewSegs) if (isAt(seg, mark)) node.classList.add("is-flash");
  d.viewed = true;
};

let furthest = 0;
const persist = () => store.write(serializeProgress(Math.min(pos, END - 1), drafts, furthest));

const focusStep = () => {
  const kind = goalKindAt(pos);
  if (kind === "intro" || kind === "end") el.next.focus({ preventScroll: true });
  else if (customKinds.has(kind)) {
    const f = el.stage.querySelector("[data-field]");
    (f ?? el.next).focus({ preventScroll: true });
  } else if (kind === "sentence") {
    el.sentence.focus({ preventScroll: true });
    const end = el.sentence.value.length;
    el.sentence.setSelectionRange(end, end);
  } else {
    document.activeElement?.blur();
  }
};

const go = (n, fresh = false, focus = true) => {
  clearTimeout(timer);
  dirty = false;
  gate.reset();
  if (!fresh) saveDraft();
  pos = n;
  furthest = Math.max(furthest, n);
  touched = false;
  lastKey = "";
  met = false;
  const onIntro = pos === 0;
  const onEnd = pos === END;
  el.intro.hidden = !onIntro;
  el.end.hidden = !onEnd;
  el.step.hidden = onIntro || onEnd;
  el.back.style.visibility = onIntro ? "hidden" : "";
  el.back.disabled = onIntro;
  el.dots.style.visibility = onIntro ? "hidden" : "";
  el.count.textContent = "";
  el.restartStep.hidden = onIntro || onEnd;
  el.dots.replaceChildren(...dotTargets(pos, furthest).map(({ state, tip, jump }) => {
    const li = make("li", `tut__dot is-${state}`);
    li.dataset.tip = tip;
    if (jump === null) {
      li.setAttribute("aria-label", state === "current" ? `${tip}, current` : tip);
    } else {
      const b = make("button", "");
      b.type = "button";
      b.setAttribute("aria-label", `Go back to ${tip}`);
      b.addEventListener("click", () => go(jump));
      li.append(b);
    }
    return li;
  }));
  el.dots.setAttribute("aria-label", onIntro ? "" : onEnd ? "all steps done" : `step ${here().step + 1} of ${steps.length}`);
  el.menuWrap.hidden = onIntro;
  closeMenu();
  if (onIntro) {
    el.next.textContent = "start";
    el.next.disabled = false;
    el.next.classList.add("is-ready");
    keyhint.classList.add("is-ready");
  } else if (onEnd) {
    el.next.textContent = "restart";
    el.next.disabled = false;
    el.next.classList.add("is-ready");
    keyhint.classList.add("is-ready");
  } else {
    const { step } = here();
    const s = steps[step];
    const d = drafts[step] ?? freshDraft(drafts, step);
    drafts[step] = d;
    el.input.value = d.input;
    el.sentence.value = d.sentence;
    el.next.textContent = step === steps.length - 1 ? "finish" : "next";
    el.count.replaceChildren(make("span", "tut__count-now", String(step + 1)), ` / ${steps.length}`);
    setNext();
    showGoal();
    el.coach.replaceChildren();
    el.showme.hidden = true;
    restartIdle();
    const custom = isCustom();
    showEditing(!custom && !!d.editing);
    el.sentence.hidden = custom;
    el.stage.hidden = !custom;
    el.result.hidden = false;
    stageState.selected = null;
    stageState.grid = null;
    stageState.cell = null;
    stageState.note = "";
    stageState.view = "policy";
    if (custom) {
      el.input.hidden = true;
      el.fixed.hidden = !["subjects", "names", "requirement"].includes(s.goal.kind);
      buildStage(s.goal.kind);
    } else {
      el.stage.replaceChildren();
      fit(el.sentence);
    }
    showView(s, d);
    evaluate();
  }
  persist();
  if (focus) focusStep();
};

document.addEventListener("keydown", (e) => {
  const a = document.activeElement;
  const target = a === el.sentence || a?.hasAttribute?.("data-field") ? "sentence" : a === el.input ? "editor" : el.menuWrap.contains(a) ? "menu" : a === el.next ? "next" : a?.closest("button, a") ? "button" : "body";
  const action = keyAction({ key: e.key, ctrl: e.ctrlKey, meta: e.metaKey, alt: e.altKey }, target, !el.next.disabled, goalKindAt(pos), dirty || !check);
  if (!action) return;
  if (action === "blur") { a.blur(); return; }
  e.preventDefault();
  if (action === "defer") {
    gate.press();
    if (check) {
      clearTimeout(timer);
      dirty = false;
      evaluate();
    }
  } else if (action === "next") el.next.click();
  else if (action === "back") { if (!el.back.disabled) el.back.click(); }
  else if (action === "pick-passed") root.querySelector(".tut__pick--passed")?.click();
  else if (action === "pick-failed") root.querySelector(".tut__pick--failed")?.click();
});
el.sentence.addEventListener("input", () => {
  const straight = straighten(el.sentence.value);
  if (straight !== el.sentence.value) {
    const at = el.sentence.selectionStart;
    el.sentence.value = straight;
    el.sentence.setSelectionRange(at, at);
  }
  fit(el.sentence);
  applyHighlight();
  gate.typed();
  touched = true;
  restartIdle();
  saveDraft();
  schedule();
});
el.input.addEventListener("input", () => { fit(el.input); touched = true; restartIdle(); saveDraft(); schedule(); });
const startEditing = () => { showEditing(true); el.input.focus(); };
el.fixed.addEventListener("click", () => { if (steps[here().step].editable && !draft().editing) startEditing(); });
el.menuButton.addEventListener("click", () => (el.menu.hidden ? openMenu() : closeMenu()));
el.menu.addEventListener("keydown", (e) => {
  const list = items();
  const at = list.indexOf(document.activeElement);
  if (e.key === "Escape") { e.preventDefault(); closeMenu(true); }
  else if (e.key === "ArrowDown") { e.preventDefault(); list[(at + 1) % list.length].focus(); }
  else if (e.key === "ArrowUp") { e.preventDefault(); list[(at - 1 + list.length) % list.length].focus(); }
  else if (e.key === "Tab") closeMenu();
});
el.menuButton.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeMenu();
  if (e.key === "ArrowDown" && el.menu.hidden) { e.preventDefault(); openMenu(); }
});
document.addEventListener("click", (e) => { if (!el.menuWrap.contains(e.target)) closeMenu(); });
el.restartStep.addEventListener("click", () => {
  closeMenu();
  const { step } = here();
  drafts[step] = freshDraft(drafts, step);
  go(pos, true);
});
el.startOver.addEventListener("click", () => {
  closeMenu();
  for (const k of Object.keys(drafts)) delete drafts[k];
  furthest = 0;
  go(0, true);
  try { localStorage.removeItem("ergo-tutorial"); } catch {}
});
el.showme.addEventListener("click", () => {
  const { answer } = goalNow();
  if (!answer) return;
  el.sentence.value = answer.sentence;
  fit(el.sentence);
  applyHighlight();
  touched = true;
  saveDraft();
  evaluate(true);
});
el.back.addEventListener("click", () => go(pos - 1));
el.next.addEventListener("click", () => {
  if (el.next.disabled) return;
  if (pos === END) {
    for (const k of Object.keys(drafts)) delete drafts[k];
    furthest = 0;
    go(0);
  } else {
    go(pos + 1);
  }
});
window.addEventListener("resize", () => {
  layoutBatches(); if (!el.step.hidden) { if (!el.input.hidden) fit(el.input); fit(el.sentence); } });

$("intro-line1").textContent = intro.lines[0];
$("intro-example").textContent = intro.example;
$("intro-line2").textContent = intro.lines[1];

const restored = restoreProgress(store.read());
Object.assign(drafts, restored.drafts);
const startPos = restored.pos;
furthest = restored.furthest;
go(startPos, false, startPos === 0);
try {
  const res = await fetch(root.dataset.wasm);
  if (!res.ok) throw new Error(`couldn't fetch ergo (${res.status})`);
  const ergo = await opa.loadPolicy(await res.arrayBuffer(), undefined, { "time.parse_rfc3339_ns": parseTime });
  check = makeChecker((doc) => ergo.evaluate(doc));
  runner.run = makeRunner((doc) => ergo.evaluate(doc));
  if (isCustom() && !el.stage.hidden) buildStage(goalNow().kind);
  evaluate();
} catch (e) {
  el.result.replaceChildren(make("p", "tut__loading mono", `ergo didn't load: ${e.message}`));
}
