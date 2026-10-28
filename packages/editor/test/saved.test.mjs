import test from "node:test";
import assert from "node:assert/strict";
import { editKey, hashText, savedEdit, saveEdit, forgetEdit } from "../src/saved.mjs";

const memory = (entries = {}) => {
  const map = new Map(Object.entries(entries));
  return {
    get length() {
      return map.size;
    },
    key: (i) => [...map.keys()][i] ?? null,
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
    map,
  };
};

test("a saved edit is keyed by the sample's name and its shipped text", () => {
  assert.notEqual(editKey("bakery", "a"), editKey("bakery", "b"));
  assert.notEqual(editKey("bakery", "a"), editKey("any of", "a"));
  assert.equal(hashText("same"), hashText("same"));
});

test("an edit comes back while the sample is the same", () => {
  const storage = memory();
  saveEdit(storage, "bakery", "shipped", "edited");
  assert.equal(savedEdit(storage, "bakery", "shipped"), "edited");
});

test("an edit saved against an older sample is dropped when the sample changes", () => {
  const storage = memory();
  saveEdit(storage, "bakery", "old sample", "edited");
  assert.equal(savedEdit(storage, "bakery", "new sample"), "new sample");
  assert.equal(storage.map.size, 0);
});

test("an edit saved before edits were keyed by the sample is dropped", () => {
  const storage = memory({ "ergo-editor:bakery": "- from: `things`", "ergo-editor:any of": "kept" });
  assert.equal(savedEdit(storage, "bakery", "shipped"), "shipped");
  assert.deepEqual([...storage.map.keys()], ["ergo-editor:any of"]);
});

test("nothing is saved while the text is the shipped sample", () => {
  const storage = memory();
  saveEdit(storage, "bakery", "shipped", "shipped");
  assert.equal(storage.map.size, 0);
  saveEdit(storage, "bakery", "shipped", "edited");
  saveEdit(storage, "bakery", "shipped", "shipped");
  assert.equal(storage.map.size, 0);
});

test("forgetting an edit gives the shipped sample back", () => {
  const storage = memory();
  saveEdit(storage, "bakery", "shipped", "edited");
  forgetEdit(storage, "bakery", "shipped");
  assert.equal(savedEdit(storage, "bakery", "shipped"), "shipped");
});

test("storage that throws leaves the shipped sample and saves nothing", () => {
  const broken = {
    get length() {
      throw new Error("blocked");
    },
    getItem() {
      throw new Error("blocked");
    },
    setItem() {
      throw new Error("blocked");
    },
    removeItem() {
      throw new Error("blocked");
    },
  };
  assert.equal(savedEdit(broken, "bakery", "shipped"), "shipped");
  assert.doesNotThrow(() => saveEdit(broken, "bakery", "shipped", "edited"));
  assert.doesNotThrow(() => forgetEdit(broken, "bakery", "shipped"));
});
