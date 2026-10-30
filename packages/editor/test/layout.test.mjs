import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_LAYOUT, LABELS, VIEWS, pick, readLayout, layoutText } from "../src/layout.mjs";

test("the page starts with the Markdown on the left and the blocks on the right", () => {
  assert.deepEqual(DEFAULT_LAYOUT, { left: "markdown", right: "blocks" });
});

test("picking a view the other pane doesn't show puts it in this pane", () => {
  assert.deepEqual(pick(DEFAULT_LAYOUT, "right", "yaml"), { left: "markdown", right: "yaml" });
  assert.deepEqual(pick(DEFAULT_LAYOUT, "left", "report"), { left: "report", right: "blocks" });
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
  assert.deepEqual(VIEWS.map((v) => LABELS[v]), ["Markdown", "Blocks", "Policy", "Document", "YAML", "Report"]);
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
