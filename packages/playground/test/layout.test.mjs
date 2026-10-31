import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_LAYOUT, LABELS, VIEWS, noteView, showsLegend, pick, readLayout, layoutText } from "../src/layout.mjs";

test("the page starts with the YAML on the left and the report on the right", () => {
  assert.deepEqual(DEFAULT_LAYOUT, { left: "yaml", right: "report" });
});

test("picking a view the other pane doesn't show puts it in this pane", () => {
  assert.deepEqual(pick(DEFAULT_LAYOUT, "right", "policy"), { left: "yaml", right: "policy" });
  assert.deepEqual(pick(DEFAULT_LAYOUT, "left", "markdown"), { left: "markdown", right: "report" });
});

test("picking the view the other pane shows swaps the two panes", () => {
  assert.deepEqual(pick({ left: "markdown", right: "yaml" }, "left", "yaml"), { left: "yaml", right: "markdown" });
  assert.deepEqual(pick({ left: "markdown", right: "yaml" }, "right", "markdown"), { left: "yaml", right: "markdown" });
});

test("picking the view a pane already shows changes nothing", () => {
  const layout = { left: "policy", right: "markdown" };
  assert.equal(pick(layout, "left", "policy"), layout);
});

test("no pick ever shows a view in both panes", () => {
  for (const left of VIEWS) {
    for (const right of VIEWS) {
      if (left === right) continue;
      for (const side of ["left", "right"]) {
        for (const view of VIEWS) {
          const out = pick({ left, right }, side, view);
          assert.notEqual(out.left, out.right);
          assert.equal(out[side], view);
        }
      }
    }
  }
});

test("every view has a tab label", () => {
  assert.deepEqual(Object.keys(LABELS).sort(), [...VIEWS].sort());
  assert.deepEqual(VIEWS.map((v) => LABELS[v]), ["YAML", "Report", "Policy", "Markdown (experimental)", "Blocks", "Document"]);
});

test("a saved layout comes back as it was saved", () => {
  const layout = { left: "yaml", right: "markdown" };
  assert.deepEqual(readLayout(layoutText(layout)), layout);
});

test("a missing, broken or impossible saved layout gives the default one", () => {
  for (const text of [null, "", "{", "[]", "null", '{"left":"yaml","right":"yaml"}', '{"left":"yaml","right":"nothing"}', '{"left":"yaml"}']) {
    assert.deepEqual(readLayout(text), DEFAULT_LAYOUT, String(text));
  }
});

test("the note under the page is about the pane you edit, YAML or Markdown, on either side", () => {
  assert.equal(noteView({ left: "yaml", right: "report" }), "yaml");
  assert.equal(noteView({ left: "report", right: "yaml" }), "yaml");
  assert.equal(noteView({ left: "markdown", right: "blocks" }), "markdown");
  assert.equal(noteView({ left: "blocks", right: "markdown" }), "markdown");
  assert.equal(noteView({ left: "yaml", right: "markdown" }), "yaml");
});

test("with no pane to edit the note is about the right pane", () => {
  assert.equal(noteView({ left: "policy", right: "report" }), "report");
  assert.equal(noteView({ left: "report", right: "doc" }), "doc");
});

test("the legend shows when a pane shows a view that colours lines the way it says", () => {
  for (const view of ["markdown", "blocks"]) {
    assert.equal(showsLegend({ left: "yaml", right: view }), true, view);
    assert.equal(showsLegend({ left: view, right: "report" }), true, view);
  }
});

test("the legend hides when no pane colours lines the way it says, as the policy and the document use the colours for other things", () => {
  assert.equal(showsLegend(DEFAULT_LAYOUT), false);
  assert.equal(showsLegend({ left: "report", right: "yaml" }), false);
  assert.equal(showsLegend({ left: "policy", right: "doc" }), false);
  assert.equal(showsLegend({ left: "yaml", right: "policy" }), false);
});
