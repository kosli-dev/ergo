import assert from "node:assert/strict";
import {test} from "node:test";
import {apply} from "../src/apply.ts";
import {compile} from "../src/compile.ts";
import {CAKE} from "./helpers.ts";

type Policy = Record<string, any>;

const DOC = `---
ergo_spec: v0.2
---

# Cake batches

Every batch is safe.

| owner  |
| ------ |
| bakery |

## Subjects

### batch

A batch of cakes.

- from: \`batches\`
- identified by: \`id\`

> The oven writes one batch per tray.

## Requirements

### Cake batch

Cakes are safe.

- subject: \`batch\`

Checks:

* **Nut free**: No nuts.
  \`allergens does not contain "nuts"\`
* **Temp ok**: \`bake.temp_c is between 175 and 200\`

We check the oven log.
`;

const policyOf = (markdown: string): Policy => structuredClone(compile(markdown).policy!) as Policy;

const edited = (change: (policy: Policy) => void, markdown = DOC) => {
  const policy = policyOf(markdown);
  change(policy);
  const result = apply(markdown, policy);
  assert.deepEqual(result.problems, []);
  assert.deepEqual(compile(result.markdown!).policy, policy);
  return result;
};

test("apply gives the source back byte for byte when nothing changed", () => {
  for (const markdown of [DOC, CAKE]) {
    assert.deepEqual(apply(markdown, policyOf(markdown)), {markdown, changes: [], problems: []});
  }
});

test("apply refuses a source with problems", () => {
  assert.deepEqual(apply("# A\n\n# B\n", {}), {
    markdown: null,
    changes: [],
    problems: [{path: "", message: "fix the Markdown first"}],
  });
});

test("apply refuses what the Markdown can't hold", () => {
  const policy = policyOf(DOC);
  policy.subjects.batch.has = {x: "y"};
  assert.deepEqual(apply(DOC, policy), {
    markdown: null,
    changes: [],
    problems: [{path: "subjects.batch.has", message: "the Markdown can't hold parts yet: write this policy in YAML"}],
  });
});

test("apply refuses when the result wouldn't compile back to the policy", () => {
  const policy = policyOf(DOC);
  policy.ergo_spec = undefined;
  assert.deepEqual(apply(DOC, policy), {
    markdown: null,
    changes: [],
    problems: [{path: "", message: "the Markdown wouldn't compile back to this policy"}],
  });
});

test("a changed field rewrites only its code span", () => {
  const {markdown, changes} = edited((p) => (p.subjects.batch.from = "today.batches"));
  assert.deepEqual(changes, ["rewrote batch.from"]);
  assert.equal(markdown, DOC.replace("- from: `batches`", "- from: `today.batches`"));
});

test("a removed field takes its bullet away", () => {
  const {markdown, changes} = edited((p) => delete p.subjects.batch.identified_by);
  assert.deepEqual(changes, ["removed batch.identified by"]);
  assert.equal(markdown, DOC.replace("- identified by: `id`\n", ""));
});

test("a new field goes after the last one, with the same bullet", () => {
  const {markdown, changes} = edited((p) => (p.requirements["cake batch"].min_subjects = 2));
  assert.deepEqual(changes, ["added cake batch.min subjects"]);
  assert.equal(markdown, DOC.replace("- subject: `batch`\n", "- subject: `batch`\n- Min subjects `2`\n"));
});

test("a field in an item with no fields starts a list after the description", () => {
  const source = "## Subjects\n\n### batch\n\nA batch.\n\n> Some prose.\n";
  const {markdown} = edited((p) => (p.subjects.batch.from = "batches"), source);
  assert.equal(markdown, "## Subjects\n\n### batch\n\nA batch.\n\n- From `batches`\n\n> Some prose.\n");
});

test("removing every field and adding others writes them where the list was", () => {
  const source = "## Subjects\n\n### batch\n\n- from: `a`\n\nSome prose.\n";
  const {markdown} = edited((p) => {
    delete p.subjects.batch.from;
    p.subjects.batch.identified_by = "id";
  }, source);
  assert.equal(markdown, "## Subjects\n\n### batch\n\n- Identified by `id`\n\nSome prose.\n");
});

test("a changed description rewrites its paragraphs and leaves the prose around it", () => {
  const {markdown, changes} = edited((p) => {
    p.description = "Every batch is safe.\n\nAnd baked right.";
    p.subjects.batch.description = "A batch of *cakes*.";
  });
  assert.deepEqual(changes, ["rewrote the description", "rewrote batch.description"]);
  assert.equal(
    markdown,
    DOC.replace("Every batch is safe.\n", "Every batch is safe.\n\nAnd baked right.\n").replace(
      "A batch of cakes.",
      "A batch of \\*cakes\\*.",
    ),
  );
});

test("a removed description takes its blank line with it", () => {
  const {markdown, changes} = edited((p) => {
    delete p.description;
    delete p.requirements["cake batch"].description;
  });
  assert.deepEqual(changes, ["removed the description", "removed cake batch.description"]);
  assert.equal(markdown, DOC.replace("Every batch is safe.\n\n", "").replace("Cakes are safe.\n\n", ""));
});

test("a new description goes under the title, or under the item's heading", () => {
  const source = "# T\n\n## Subjects\n\n### s\n\n- from: `x`\n";
  const {markdown, changes} = edited((p) => {
    p.description = "Policy.";
    p.subjects.s.description = "Subject.";
  }, source);
  assert.deepEqual(changes, ["added the description", "added s.description"]);
  assert.equal(markdown, "# T\n\nPolicy.\n\n## Subjects\n\n### s\n\nSubject.\n\n- from: `x`\n");
});

test("a new description with no title goes at the top, after the front matter", () => {
  const source = "---\nergo_spec: v0.2\n---\n\n## Subjects\n";
  assert.equal(edited((p) => (p.description = "Policy."), source).markdown, "---\nergo_spec: v0.2\n---\n\nPolicy.\n\n## Subjects\n");
  assert.equal(edited((p) => (p.description = "Policy."), "## Subjects\n").markdown, "Policy.\n\n## Subjects\n");
});

test("ergo_spec is rewritten, removed or added in the front matter", () => {
  const rewrote = edited((p) => (p.ergo_spec = "v0.4-dev"));
  assert.deepEqual(rewrote.changes, ["rewrote ergo_spec"]);
  assert.equal(rewrote.markdown, DOC.replace("ergo_spec: v0.2", "ergo_spec: v0.4-dev"));
  const removed = edited((p) => delete p.ergo_spec);
  assert.deepEqual(removed.changes, ["removed ergo_spec"]);
  assert.equal(removed.markdown, DOC.replace("---\nergo_spec: v0.2\n---\n\n", ""));
  const added = edited((p) => (p.ergo_spec = "v0.2"), "# T\n");
  assert.deepEqual(added.changes, ["added ergo_spec"]);
  assert.equal(added.markdown, "---\nergo_spec: v0.2\n---\n\n# T\n");
});

test("a changed check is rewritten in its place with the list's bullet", () => {
  const {markdown, changes} = edited((p) => (p.requirements["cake batch"].checks["nut free"].assert = "allergens is empty"));
  assert.deepEqual(changes, ["rewrote cake batch.nut free"]);
  assert.equal(
    markdown,
    DOC.replace('* **Nut free**: No nuts.\n  `allergens does not contain "nuts"`', "* **Nut free**: No nuts.\n  `allergens is empty`"),
  );
});

test("a check that disappears with a new one in its place is renamed there", () => {
  const {markdown, changes} = edited((p) => {
    const checks = p.requirements["cake batch"].checks;
    p.requirements["cake batch"].checks = {"no nuts": checks["nut free"], "temp ok": checks["temp ok"]};
  });
  assert.deepEqual(changes, ["renamed check cake batch.nut free to cake batch.no nuts"]);
  assert.equal(markdown, DOC.replace("* **Nut free**", "* **No nuts**"));
});

test("a removed check takes its bullet away and a new one goes at the end of the list", () => {
  const {markdown, changes} = edited((p) => {
    const checks = p.requirements["cake batch"].checks;
    delete checks["nut free"];
    checks["time ok"] = {assert: "bake.minutes is between 25 and 40"};
  });
  assert.deepEqual(changes, ["removed check cake batch.nut free", "added check cake batch.time ok"]);
  assert.match(
    markdown!,
    /Checks:\n\n\* \*\*Temp ok\*\*: `bake\.temp_c is between 175 and 200`\n\* \*\*Time ok\*\*: `bake\.minutes is between 25 and 40`\n\nWe check/,
  );
});

test("removing the checks takes Checks: and its list away", () => {
  const {markdown, changes} = edited((p) => delete p.requirements["cake batch"].checks);
  assert.deepEqual(changes, ["removed cake batch.checks"]);
  assert.match(markdown!, /- subject: `batch`\n\nWe check the oven log\.\n$/);
});

test("checks added to a requirement with none go after its fields", () => {
  const source = "## Requirements\n\n### r\n\n- subject: `s`\n\nProse.\n";
  const {markdown, changes} = edited((p) => (p.requirements.r.checks = {c: {assert: "a is 1"}}), source);
  assert.deepEqual(changes, ["added r.checks"]);
  assert.equal(markdown, "## Requirements\n\n### r\n\n- subject: `s`\n\nChecks:\n\n- **C**: `a is 1`\n\nProse.\n");
});

test("fields and checks added to a bare requirement come in that order", () => {
  const {markdown} = edited((p) => {
    p.requirements.r.subject = "s";
    p.requirements.r.checks = {c: {assert: "a is 1"}};
  }, "## Requirements\n\n### r\n");
  assert.equal(markdown, "## Requirements\n\n### r\n\n- Subject `s`\n\nChecks:\n\n- **C**: `a is 1`\n");
});

test("a subject or requirement that disappears with a new one in its place is renamed there", () => {
  const {markdown, changes} = edited((p) => {
    p.subjects = {tray: {...p.subjects.batch, from: "trays"}};
    p.requirements = {"tray check": {...p.requirements["cake batch"], subject: "tray"}};
  });
  assert.deepEqual(changes, [
    "renamed subject batch to tray",
    "rewrote tray.from",
    "renamed requirement cake batch to tray check",
    "rewrote tray check.subject",
  ]);
  assert.equal(
    markdown,
    DOC.replace("### batch", "### Tray")
      .replace("`batches`", "`trays`")
      .replace("### Cake batch", "### Tray check")
      .replace("- subject: `batch`", "- subject: `tray`"),
  );
});

test("a removed subject takes its whole section, prose included", () => {
  const {markdown, changes} = edited((p) => delete p.subjects.batch);
  assert.deepEqual(changes, ["removed subject batch"]);
  assert.match(markdown!, /## Subjects\n\n## Requirements\n/);
});

test("a new subject goes at the end of its section", () => {
  const {markdown, changes} = edited((p) => (p.subjects.oven = {from: "ovens"}));
  assert.deepEqual(changes, ["added subject oven"]);
  assert.match(markdown!, /> The oven writes one batch per tray\.\n\n### Oven\n\n- From `ovens`\n\n## Requirements\n/);
});

test("the last requirements removed at the end of the file leave one newline", () => {
  const source = "## Requirements\n\n### a\n\n- subject: `s`\n\n### b\n\n- subject: `s`\n";
  const {markdown} = edited((p) => (p.requirements = {}), source);
  assert.equal(markdown, "## Requirements\n");
});

test("removing the last requirement and adding another puts the new one in its section", () => {
  const source = "## Requirements\n\n### a\n\n- subject: `s`\n";
  const {markdown} = edited((p) => (p.requirements = {a: p.requirements.a, b: {subject: "t"}}), source);
  assert.equal(markdown, "## Requirements\n\n### a\n\n- subject: `s`\n\n### B\n\n- Subject `t`\n");
  const replaced = edited((p) => (p.requirements = {b: {subject: "t"}, c: {subject: "u"}}), source);
  assert.equal(replaced.markdown, "## Requirements\n\n### B\n\n- subject: `t`\n\n### C\n\n- Subject `u`\n");
});

test("a missing section is added: subjects before the requirements, requirements at the end", () => {
  const subjects = edited((p) => (p.subjects.s = {from: "x"}), "# T\n\n## Requirements\n");
  assert.equal(subjects.markdown, "# T\n\n## Subjects\n\n### S\n\n- From `x`\n\n## Requirements\n");
  const requirements = edited((p) => (p.requirements.r = {subject: "s"}), "# T\n\nText.");
  assert.equal(requirements.markdown, "# T\n\nText.\n\n## Requirements\n\n### R\n\n- Subject `s`\n");
  const both = edited((p) => (p.subjects.s = {}), "");
  assert.equal(both.markdown, "## Subjects\n\n### S\n");
});

test("a new subject in a document with no requirements goes at the end", () => {
  assert.equal(edited((p) => (p.subjects.s = {}), "# T\n").markdown, "# T\n\n## Subjects\n\n### S\n");
});

test("removing all that stood between a heading and a prose paragraph is refused, since the paragraph would become the description", () => {
  const source = "## Requirements\n\n### r\n\n- subject: `s`\n\nProse.\n";
  assert.deepEqual(apply(source, {requirements: {r: {}}}), {
    markdown: null,
    changes: [],
    problems: [{path: "requirements.r.description", message: "the Markdown wouldn't compile back to this policy"}],
  });
});

test("a check that keeps its name keeps its label as written, its description too when that didn't change", () => {
  const source = "## Requirements\n\n### r\n\n- subject: `s`\n\nChecks:\n\n- **NUT  free**: *No* nuts. `a is 1`\n";
  const one = edited((p) => (p.requirements.r.checks["nut free"].assert = ["a is 1", "b is 2"]), source);
  assert.equal(one.markdown, source.replace("*No* nuts. `a is 1`", "*No* nuts.\n  `a is 1`\n  `b is 2`"));
  const two = edited((p) => (p.requirements.r.checks["nut free"].description = "None."), source);
  assert.equal(two.markdown, source.replace("*No* nuts. `a is 1`", "None.\n  `a is 1`"));
  const three = edited((p) => (p.requirements.r.checks["nut free"].for = "every xs as x"), source);
  assert.equal(three.markdown, source.replace("*No* nuts. `a is 1`", "*No* nuts.\n  `for every xs as x`\n  `a is 1`"));
});

test("a check keeps its sentences on its label's line when they were there", () => {
  const source = "## Requirements\n\n### r\n\nChecks:\n\n- **c**: `a is 1`\n";
  const {markdown} = edited((p) => (p.requirements.r.checks.c = {assert: "b is 2", for: "every xs as x"}), source);
  assert.equal(markdown, "## Requirements\n\n### r\n\nChecks:\n\n- **c**:\n  `for every xs as x`\n  `b is 2`\n");
  const one = edited((p) => (p.requirements.r.checks.c = {assert: "b is 2", description: "D."}), source);
  assert.equal(one.markdown, "## Requirements\n\n### r\n\nChecks:\n\n- **c**: D.\n  `b is 2`\n");
});

test("a renamed check keeps its description as written", () => {
  const source = "## Requirements\n\n### r\n\nChecks:\n\n- **old**: *Kept* text.\n  `a is 1`\n";
  const {markdown} = edited((p) => (p.requirements.r.checks = {new: p.requirements.r.checks.old}), source);
  assert.equal(markdown, source.replace("**old**", "**New**"));
});

test("an option that keeps its name keeps its label as written", () => {
  const source = "## Requirements\n\n### r\n\nChecks:\n\n- **c**:\n  - **OPT one**: `a is 1`\n  - **two**: `b is 2`\n";
  const {markdown} = edited((p) => (p.requirements.r.checks.c.any_of = {"opt one": ["a is 1", "c is 3"], three: "d is 4"}), source);
  assert.equal(markdown, "## Requirements\n\n### r\n\nChecks:\n\n- **c**:\n  - **OPT one**:\n    `a is 1`\n    `c is 3`\n  - **Three**: `d is 4`\n");
});

const LINKED = `# P

Read [the rules](https://x.y/r) **first**.

Second paragraph.

## Subjects

### s

- from: \`b\`

## Requirements

### r

See [the list](https://x.y/l) for *why*.

Next \`not code\` words.

- subject: \`s\`

Checks:

- **A**: See [rule 4](https://x.y/4) for *why*.

  More [here](https://x.y/h).

  \`a is 1\`
- **Old**: \`b is 1\`
`;

test("changing one description paragraph keeps the others as written", () => {
  const {markdown} = edited((p) => {
    p.description = p.description.replace("Second", "2nd");
    p.requirements.r.description = p.requirements.r.description.replace("See the list", "Look at the list");
    p.requirements.r.checks.a.description = p.requirements.r.checks.a.description.replace("More here", "Less here");
  }, LINKED);
  assert.equal(
    markdown,
    LINKED.replace("Second paragraph", "2nd paragraph")
      .replace("See [the list](https://x.y/l) for *why*.", "Look at the list for why.")
      .replace("More [here](https://x.y/h).\n\n", "Less here.\n"),
  );
});

test("when the paragraphs change in number, the ones before the first change stay as written", () => {
  const added = edited((p) => {
    p.description += "\n\nThird.";
    p.requirements.r.checks.a.description += "\n\nAnd more.";
  }, LINKED);
  assert.equal(
    added.markdown,
    LINKED.replace("Second paragraph.\n", "Second paragraph.\n\nThird.\n").replace(
      "More [here](https://x.y/h).\n\n",
      "More [here](https://x.y/h).\n\n  And more.\n",
    ),
  );
  const cut = edited((p) => {
    p.description = p.description.split("\n\n")[0];
    p.requirements.r.description = p.requirements.r.description.split("\n\n")[0];
    p.requirements.r.checks.a.description = p.requirements.r.checks.a.description.split("\n\n")[0];
  }, LINKED);
  assert.equal(
    cut.markdown,
    LINKED.replace("Second paragraph.\n\n", "")
      .replace("Next `not code` words.\n\n", "")
      .replace("\n\n  More [here](https://x.y/h).\n\n", "\n"),
  );
  const first = edited((p) => (p.description = `Zero.\n\n${p.description}`), LINKED);
  assert.equal(first.markdown, LINKED.replace("Read [the rules](https://x.y/r) **first**.", "Zero.\n\nRead the rules first."));
});

test("a check renamed to a name with a replacement pattern in it is renamed as written", () => {
  for (const name of ["cost $& more", "a $' b", "a $` b", "x $$ $1"]) {
    const {markdown} = edited((p) => (p.requirements.r.checks = {[name]: p.requirements.r.checks.a, old: p.requirements.r.checks.old}), LINKED);
    assert.deepEqual(Object.keys((compile(markdown!).policy as Policy).requirements.r.checks), [name, "old"]);
  }
});

test("a check renamed to a longer name keeps its sentence on its own line and its place", () => {
  const source = "## Requirements\n\n### r\n\nChecks:\n\n- **a**: *Words* [here](https://x.y).\n  `a is 1`\n- **old**: `b is 1`\n";
  const {markdown, changes} = edited((p) => {
    const checks = p.requirements.r.checks;
    p.requirements.r.checks = {old: checks.old, "a much longer name": checks.a};
  }, source);
  assert.deepEqual(changes, ["renamed check r.a to r.a much longer name"]);
  assert.equal(markdown, source.replace("**a**", "**A much longer name**"));
  const same = edited((p) => (p.requirements.r.checks = {"a much longer name": p.requirements.r.checks.a, old: p.requirements.r.checks.old}), source);
  assert.equal(same.markdown, source.replace("**a**", "**A much longer name**"));
});

test("a document written with CRLF line endings is written back with CRLF only", () => {
  const source = DOC.replace(/\n/g, "\r\n");
  const unchanged = apply(source, policyOf(source));
  assert.deepEqual(unchanged, {markdown: source, changes: [], problems: []});
  const {markdown} = edited((p) => {
    p.requirements["cake batch"].checks.sealed = {description: "Sealed.", assert: "box.sealed is true"};
    p.description = "Every batch is safe.\n\nAnd tasty.";
  }, source);
  assert.ok(!/(^|[^\r])\n/.test(markdown!));
  assert.ok(markdown!.includes("* **Sealed**: Sealed.\r\n  `box.sealed is true`\r\n"));
});
