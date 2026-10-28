import assert from "node:assert/strict";
import {existsSync, readdirSync, readFileSync} from "node:fs";
import {join} from "node:path";
import {test} from "node:test";
import {fileURLToPath} from "node:url";
import {apply} from "../src/apply.ts";
import {compile} from "../src/compile.ts";
import {render} from "../src/render.ts";

const cases = fileURLToPath(new URL("../cases/", import.meta.url));
const good = readdirSync(cases)
  .filter((name) => existsSync(join(cases, name, "policy.yaml")))
  .sort();

for (const name of good) {
  test(`case ${name} renders to Markdown that compiles back, and applies to itself unchanged`, () => {
    const markdown = readFileSync(join(cases, name, "policy.ergo.md"), "utf8");
    const {policy} = compile(markdown);
    const rendered = render(policy!);
    assert.deepEqual(rendered.problems, []);
    assert.deepEqual(compile(rendered.markdown!).policy, policy);
    assert.deepEqual(apply(markdown, policy!), {markdown, changes: [], problems: []});
  });
}

const random = (seed: number) => () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const NAMES = ["batch", "pull request", "crème brûlée", "nut free", "nut_free", "a-b", "1st", "#1 *x*", "ok?", "x.y"];
const WORDS = ["Cakes", "are", "*safe*", "_to_", "eat", "`now`", "[x]", "<b>", "&amp;", "#", "-", "1.", "\\", "C:"];
const SENTENCES = ["a is 1", 'b is "x"', "count of c is at least 2", "for x is 1", "some d.e is in $params.f"];

function policyFrom(next: () => number) {
  const pick = <T>(list: T[]): T => list[Math.floor(next() * list.length)]!;
  const some = <T>(make: () => T, most: number): T[] => Array.from({length: Math.floor(next() * (most + 1))}, make);
  const text = () =>
    some(() => some(() => pick(WORDS), 4).concat("end").join(" "), 1)
      .concat("Last.")
      .join("\n\n");
  const names = (most: number) => [...new Set(some(() => pick(NAMES), most))];
  const atLeastOne = (most: number) => [...new Set([pick(NAMES), ...some(() => pick(NAMES), most - 1)])];
  const maybe = <T>(value: T): T | undefined => (next() < 0.5 ? value : undefined);
  const sentences = (forFree: boolean) => {
    const list = some(() => pick(SENTENCES.filter((s) => forFree || !s.startsWith("for "))), 2);
    return list.length === 0 ? "a is 1" : list.length === 1 ? list[0]! : list;
  };
  const clean = (object: Record<string, unknown>) =>
    Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
  const check = () =>
    clean({
      description: maybe(text()),
      ...(next() < 0.7
        ? {for: maybe("every xs as x"), assert: sentences(false)}
        : {any_of: Object.fromEntries(atLeastOne(2).map((n) => [n, sentences(true)]))}),
    });
  return clean({
    ergo_spec: maybe("v0.2"),
    description: maybe(text()),
    subjects: Object.fromEntries(
      names(3).map((n) => [n, clean({description: maybe(text()), from: maybe("xs"), identified_by: maybe("id")})]),
    ),
    requirements: Object.fromEntries(
      names(3).map((n) => [
        n,
        clean({
          description: maybe(text()),
          subject: maybe(pick(NAMES)),
          require: maybe("some"),
          min_subjects: maybe(Math.floor(next() * 3)),
          checks: maybe(Object.fromEntries(atLeastOne(3).map((c) => [c, check()]))),
        }),
      ]),
    ),
  });
}

test("generated policies render, compile back, and apply onto each other's Markdown", () => {
  const next = random(20261028);
  for (let i = 0; i < 300; i++) {
    const first = policyFrom(next);
    const second = policyFrom(next);
    const rendered = render(first);
    assert.deepEqual(rendered.problems, [], JSON.stringify(first));
    assert.deepEqual(compile(rendered.markdown!).policy, first);
    const applied = apply(rendered.markdown!, second);
    assert.deepEqual(applied.problems, [], JSON.stringify([first, second]));
    assert.deepEqual(compile(applied.markdown!).policy, second);
    assert.deepEqual(apply(applied.markdown!, second).changes, []);
    assert.deepEqual(compile(apply(applied.markdown!, first).markdown!).policy, first);
  }
});

test("generated policies apply onto every case written by hand, refused only where prose would become a description", () => {
  const next = random(28102026);
  const sources = good.map((name) => readFileSync(join(cases, name, "policy.ergo.md"), "utf8"));
  const refused: {path: string; message: string}[] = [];
  for (let i = 0; i < 100; i++) {
    for (const source of sources) {
      const policy = policyFrom(next);
      const applied = apply(source, policy);
      if (applied.markdown === null) {
        refused.push(...applied.problems);
        continue;
      }
      assert.deepEqual(compile(applied.markdown).policy, policy);
    }
  }
  for (const problem of refused) {
    assert.equal(problem.message, "the Markdown wouldn't compile back to this policy");
    assert.match(problem.path, /\.description$/);
  }
  assert.ok(refused.length < 50, `${refused.length} refused`);
});
