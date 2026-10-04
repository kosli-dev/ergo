import opa from "../../playground/vendor/opa-wasm.mjs";
import { bakeryRequirements, decodeState, encodeState, formats, parseTime, sortKeys } from "./lib.mjs";

const root = document.getElementById("playground");

const panes = Object.fromEntries([...root.querySelectorAll("[data-pane]")].map((el) => {
  const pane = {
    code: el.querySelector("textarea"),
    error: el.querySelector(".pg__error"),
    format: null,
    setFormat(f) {
      pane.format = f;
      el.querySelectorAll("[data-format]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.format === f)));
    },
    set(text, f) { pane.code.value = text; pane.setFormat(f); },
    read() {
      try {
        const v = formats[pane.format].parse(pane.code.value);
        pane.error.textContent = "";
        return { ok: true, value: v };
      } catch (e) {
        pane.error.textContent = e.message.split("\n")[0];
        return { ok: false };
      }
    },
  };
  el.querySelectorAll("[data-format]").forEach((b) => b.addEventListener("click", () => {
    if (b.dataset.format === pane.format) return;
    const r = pane.read();
    if (r.ok) pane.set(formats[b.dataset.format].write(r.value), b.dataset.format);
  }));
  pane.code.addEventListener("input", () => schedule());
  return [el.dataset.pane, pane];
}));

const bakery = () => {
  panes.requirements.set(bakeryRequirements(root.dataset.requirements), "yaml");
  panes.input.set(root.dataset.input, "json");
};

const status = root.querySelector("[data-status]");
const summary = root.querySelector("[data-summary]");
const table = root.querySelector("[data-results]");
const raw = root.querySelector("[data-raw]");
const reportEl = root.querySelector(".pg__report");
const note = root.querySelector("[data-note]");

const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};

const show = (report) => {
  status.textContent = "";
  const verdict = el("p", "pg__verdict");
  verdict.append("compliant: ", el("span", report.compliant === true ? "t" : "f", JSON.stringify(report.compliant)));
  const reqs = el("ul", "pg__reqs mono");
  for (const [name, r] of Object.entries(report.requirements ?? {})) {
    const li = el("li");
    li.append(el("span", "", name), " ", el("span", r.satisfied === true ? "t" : "f", r.satisfied === true ? "satisfied" : "not satisfied"));
    if (r.subjects) li.append(el("span", "muted", ` · ${r.subjects.matching} of ${r.subjects.total} subjects match`));
    reqs.append(li);
  }
  summary.replaceChildren(verdict, reqs);

  table.tBodies[0].replaceChildren(...(report.results ?? []).map((row) => {
    const tr = el("tr");
    const id = row.subject?.id;
    tr.append(
      el("td", "mono", row.requirement),
      el("td", "mono", id === null || id === undefined ? `(${row.subject?.type ?? "requirement"})` : typeof id === "string" ? id : JSON.stringify(id)),
      el("td", `mono ${String(row.check).startsWith("$") ? "sys" : ""}`, row.check),
      el("td", `mono ${row.passed === true ? "t" : "f"}`, row.passed === true ? "passed" : "failed"),
      el("td", "mono", row.cause),
    );
    const inputs = el("td", "mono pg__inputs");
    for (const x of row.inputs ?? []) inputs.append(el("div", "", `${x.name} = ${"value" in x ? JSON.stringify(x.value) : "(missing)"}`));
    tr.append(inputs);
    return tr;
  }));
  table.hidden = false;
  raw.querySelector("pre").textContent = JSON.stringify(report, null, 2);
  raw.hidden = false;
  reportEl.classList.remove("is-stale");
};

let policy;
let timer;
const schedule = () => { clearTimeout(timer); timer = setTimeout(run, 200); };

const run = () => {
  const r = panes.requirements.read();
  const i = panes.input.read();
  if (!policy) return;
  if (!r.ok || !i.ok) { reportEl.classList.add("is-stale"); return; }
  try {
    const out = policy.evaluate({ input: i.value, requirements: r.value });
    if (!out?.length || out[0].result === undefined) throw new Error("ergo gave no report");
    show(sortKeys(out[0].result));
  } catch (e) {
    reportEl.classList.add("is-stale");
    status.textContent = `ergo stopped: ${e.message}`;
  }
};

root.querySelector("[data-action=share]").addEventListener("click", async () => {
  const hash = await encodeState({ r: panes.requirements.code.value, rf: panes.requirements.format, i: panes.input.code.value, if: panes.input.format });
  history.replaceState(null, "", `#${hash}`);
  try {
    await navigator.clipboard.writeText(location.href);
    note.textContent = "Link copied. It holds what you typed.";
  } catch {
    note.textContent = "The link is in the address bar. It holds what you typed.";
  }
});

root.querySelector("[data-action=reset]").addEventListener("click", () => {
  history.replaceState(null, "", location.pathname);
  note.textContent = "";
  bakery();
  run();
});

const restore = async () => {
  if (location.hash.length < 2) return false;
  try {
    const s = await decodeState(location.hash.slice(1));
    panes.requirements.set(s.r, s.rf);
    panes.input.set(s.i, s.if);
    return true;
  } catch {
    note.textContent = "That link couldn't be read, so this is the bakery.";
    return false;
  }
};

if (!(await restore())) bakery();
try {
  const res = await fetch(root.dataset.wasm);
  if (!res.ok) throw new Error(`couldn't fetch ergo (${res.status})`);
  policy = await opa.loadPolicy(await res.arrayBuffer(), undefined, { "time.parse_rfc3339_ns": parseTime });
  status.textContent = "";
  run();
} catch (e) {
  status.textContent = `ergo didn't load: ${e.message}`;
}
