import assert from "node:assert/strict";
import {test} from "node:test";
import {compile} from "../src/compile.ts";
import {normalise, render, same} from "../src/render.ts";
import {CAKE, CAKE_POLICY} from "./helpers.ts";

const policyWith = (requirement: Record<string, unknown>) => ({
  subjects: {batch: {from: "batches"}},
  requirements: {r: {subject: "batch", ...requirement}},
});

const refused = (policy: object) => {
  const {markdown, problems} = render(policy);
  assert.equal(markdown, null);
  return problems;
};

test("render writes the house style", () => {
  const {markdown, problems} = render(CAKE_POLICY);
  assert.deepEqual(problems, []);
  assert.equal(
    markdown,
    `---
ergo_spec: v0.2
---

Every batch that leaves the bakery is safe to eat and baked right.

## Subjects

### Batch

A batch of cakes baked today.

- From \`batches\`
- Identified by \`id\`

## Requirements

### Cake batch

Cakes are safe to eat and baked right.

- Subject \`batch\`

Checks:

- **Nut free**: Must not contain nut allergens.
  \`allergens does not contain "nuts"\`
- **Temp ok**: \`bake.temp_c is between 175 and 200\`
- **Licence allowed**: Every licence is allowed.
  - **Declared**: \`some licenses.license.id is in $params.allowed_licenses\`
  - **Known**:
    \`licenses does not exist\`
    \`$params.known named by name is in $params.allowed_licenses\`
- **Each item**:
  \`for every items as item\`
  \`item.ok is true\`
`,
  );
  assert.deepEqual(compile(markdown!).policy, CAKE_POLICY);
});

test("the cake example compiles back from its rendering", () => {
  const policy = compile(CAKE).policy!;
  assert.deepEqual(compile(render(policy).markdown!).policy, policy);
});

test("an empty policy renders the two sections and no front matter", () => {
  assert.equal(render({subjects: {}, requirements: {}}).markdown, "## Subjects\n\n## Requirements\n");
});

test("a requirement's fields come in a fixed order whatever the policy's order", () => {
  const {markdown} = render(policyWith({min_subjects: 2, require: "some"}));
  assert.match(markdown!, /- Subject `batch`\n- Require `some`\n- Min subjects `2`\n/);
});

test("descriptions over several paragraphs keep a blank line between them", () => {
  const policy = {
    description: "One.\n\nTwo.",
    subjects: {},
    requirements: {r: {description: "A.\n\nB.", subject: "s", checks: {c: {description: "X.\n\nY.", assert: "a is 1"}}}},
  };
  const {markdown} = render(policy);
  assert.match(markdown!, /^One\.\n\nTwo\.\n/);
  assert.match(markdown!, /### R\n\nA\.\n\nB\.\n/);
  assert.match(markdown!, /- \*\*C\*\*: X\.\n\n {2}Y\.\n {2}`a is 1`\n/);
  assert.deepEqual(compile(markdown!).policy, policy);
});

test("text Markdown would read as formatting is escaped, so it comes back as written", () => {
  const description = "a *b* _c_ snake_case `d` [e](f) <g> &amp; \\ h#";
  const policy = {
    description: "# not a heading\n\n- not a list\n\n1. not a list\n\n+ x\n\n= y\n\n~~~ z",
    subjects: {"#1 *s*": {description}},
    requirements: {"under_score": {subject: "#1 *s*", checks: {"_c_": {description, assert: "a is 1"}}}},
  };
  const {markdown, problems} = render(policy);
  assert.deepEqual(problems, []);
  assert.deepEqual(compile(markdown!).policy, policy);
  assert.match(markdown!, /### \\#1 \\\*s\\\*\n/);
  assert.match(markdown!, /### Under_score\n/);
});

test("a name whose first letter has no one-letter capital keeps it", () => {
  const policy = {subjects: {"ßeta": {}, "1st": {}}, requirements: {}};
  const {markdown} = render(policy);
  assert.match(markdown!, /### ßeta\n\n### 1st\n/);
  assert.deepEqual(compile(markdown!).policy, policy);
});

test("normalise turns the shapes that mean the same to Ergo into the one compile gives", () => {
  assert.deepEqual(
    normalise({
      requirements: {
        r: {subject: "s", checks: {a: "x is 1", b: {assert: ["x is 1"]}, c: {any_of: {o: ["x is 1"], p: ["y", "z"]}}}},
        q: {subject: "s"},
      },
    }),
    {
      subjects: {},
      requirements: {
        r: {subject: "s", checks: {a: {assert: "x is 1"}, b: {assert: "x is 1"}, c: {any_of: {o: "x is 1", p: ["y", "z"]}}}},
        q: {subject: "s"},
      },
    },
  );
  assert.equal(normalise("x"), "x");
  assert.deepEqual(normalise({requirements: "x"}), {subjects: {}, requirements: "x"});
  assert.deepEqual(normalise({requirements: {r: {checks: {c: 1}}}}), {subjects: {}, requirements: {r: {checks: {c: 1}}}});
});

test("render accepts the shapes normalise turns into the Markdown's", () => {
  const {markdown, problems} = render({requirements: {r: {subject: "s", checks: {c: "x is 1", d: {assert: ["y is 1"]}}}}});
  assert.deepEqual(problems, []);
  assert.match(markdown!, /- \*\*C\*\*: `x is 1`\n- \*\*D\*\*: `y is 1`\n/);
});

test("render refuses a policy that isn't an object", () => {
  assert.deepEqual(refused([] as unknown as object), [{path: "", message: "a policy is an object"}]);
});

test("render refuses what the Markdown can't hold, naming the path", () => {
  const cases: [object, string, string][] = [
    [{meta: {}, subjects: {}}, "meta", "the Markdown can't hold meta yet: write this policy in YAML"],
    [{title: "x"}, "title", "the Markdown has no place for title"],
    [{subjects: []}, "subjects", "isn't an object"],
    [{subjects: {s: null}}, "subjects.s", "is null: give it a from"],
    [{subjects: {s: "x"}}, "subjects.s", "isn't an object"],
    [{subjects: {s: {has: {x: "y"}}}}, "subjects.s.has", "the Markdown can't hold parts yet: write this policy in YAML"],
    [{subjects: {s: {where: "x"}}}, "subjects.s.where", "the Markdown has no field where"],
    [{subjects: {s: {from: 1}}}, "subjects.s.from", "isn't text"],
    [{subjects: {s: {from: ""}}}, "subjects.s.from", "is empty"],
    [{subjects: {s: {from: "a`b"}}}, "subjects.s.from", "has a backtick, which a code span can't hold"],
    [{subjects: {s: {from: "a\nb"}}}, "subjects.s.from", "has a line break"],
    [{subjects: {s: {from: " a"}}}, "subjects.s.from", "starts or ends with a space"],
    [{subjects: {s: {description: null}}}, "subjects.s.description", "is null: leave it out instead"],
    [{subjects: {s: {description: 1}}}, "subjects.s.description", "isn't text"],
    [{subjects: {s: {description: ""}}}, "subjects.s.description", "is empty: leave it out instead"],
    [{description: "a  b"}, "description", "has spaces or line breaks the Markdown can't keep"],
    [{description: "a\n\n\n\nb"}, "description", "has spaces or line breaks the Markdown can't keep"],
    [{description: "a\nb"}, "description", "has spaces or line breaks the Markdown can't keep"],
    [
      {subjects: {s: {description: "A.\n\nChecks:"}}},
      "subjects.s.description",
      "has a paragraph that is just Checks:, which the Markdown reads as the start of the checks",
    ],
    [{subjects: {Batch: {}}}, "subjects.Batch", "has upper case"],
    [{subjects: {" b": {}}}, "subjects. b", "starts or ends with a space"],
    [{subjects: {"a\tb": {}}}, "subjects.a\tb", "has a tab, a line break or a space that isn't a plain one"],
    [{subjects: {"a  b": {}}}, "subjects.a  b", "has two spaces in a row"],
    [{subjects: {"": {}}}, "subjects.", "a label needs a letter or a digit"],
    [{subjects: {$x: {}}}, "subjects.$x", "a name can't start with $"],
    [{subjects: {"a\u00a0b": {}}}, "subjects.a\u00a0b", "has a tab, a line break or a space that isn't a plain one"],
    [policyWith({min_subjects: -1}), "requirements.r.min_subjects", "isn't a whole number of 0 or more"],
    [policyWith({min_subjects: 1.5}), "requirements.r.min_subjects", "isn't a whole number of 0 or more"],
    [policyWith({require: 1}), "requirements.r.require", "isn't text"],
    [policyWith({meta: {}}), "requirements.r.meta", "the Markdown can't hold meta yet: write this policy in YAML"],
    [policyWith({checks: []}), "requirements.r.checks", "isn't an object"],
    [policyWith({checks: {}}), "requirements.r.checks", "is empty: give it a check, or leave checks out"],
    [policyWith({checks: {Nut: {assert: "a"}}}), "requirements.r.checks.Nut", "has upper case"],
    [policyWith({checks: {c: 1}}), "requirements.r.checks.c", "isn't a sentence or an object"],
    [policyWith({checks: {c: {}}}), "requirements.r.checks.c", "needs assert or any_of"],
    [policyWith({checks: {c: {assert: []}}}), "requirements.r.checks.c.assert", "is empty"],
    [policyWith({checks: {c: {assert: ["a", "b`"]}}}), "requirements.r.checks.c.assert.1", "has a backtick, which a code span can't hold"],
    [
      policyWith({checks: {c: {assert: "for every xs as x"}}}),
      "requirements.r.checks.c.assert",
      "starts with for, so the Markdown would read it as the check's for line: write .for",
    ],
    [policyWith({checks: {c: {assert: "a", for: ""}}}), "requirements.r.checks.c.for", "is empty"],
    [policyWith({checks: {c: {assert: "a", meta: {}}}}), "requirements.r.checks.c.meta", "the Markdown can't hold meta yet: write this policy in YAML"],
    [policyWith({checks: {c: {assert: "a", when: "b"}}}), "requirements.r.checks.c.when", "the Markdown has no place for when"],
    [policyWith({checks: {c: {assert: "a", description: ""}}}), "requirements.r.checks.c.description", "is empty: leave it out instead"],
    [policyWith({checks: {c: {assert: "a", any_of: {o: "b"}}}}), "requirements.r.checks.c", "has both assert and any_of"],
    [policyWith({checks: {c: {any_of: "b"}}}), "requirements.r.checks.c.any_of", "isn't an object"],
    [policyWith({checks: {c: {any_of: {}}}}), "requirements.r.checks.c.any_of", "is empty"],
    [policyWith({checks: {c: {any_of: {O: "b"}}}}), "requirements.r.checks.c.any_of.O", "has upper case"],
    [policyWith({checks: {c: {any_of: {o: []}}}}), "requirements.r.checks.c.any_of.o", "is empty"],
    [policyWith({checks: {c: {any_of: {o: " b"}}}}), "requirements.r.checks.c.any_of.o", "starts or ends with a space"],
  ];
  for (const [policy, path, message] of cases) assert.deepEqual(refused(policy), [{path, message}], path);
});

test("an option sentence may start with for, since only a check has a for line", () => {
  const policy = policyWith({checks: {c: {any_of: {o: "for x", p: "y"}}}});
  assert.deepEqual(compile(render(policy).markdown!).policy, normalise(policy));
});

test("render lists every refusal at once", () => {
  assert.deepEqual(refused({subjects: {A: {from: ""}}, meta: {}}), [
    {path: "subjects.A", message: "has upper case"},
    {path: "subjects.A.from", message: "is empty"},
    {path: "meta", message: "the Markdown can't hold meta yet: write this policy in YAML"},
  ]);
});

test("render refuses when its Markdown wouldn't compile back to the policy", () => {
  assert.deepEqual(refused({ergo_spec: undefined, subjects: {}, requirements: {}}), [
    {path: "", message: "the Markdown wouldn't compile back to this policy"},
  ]);
});

test("same tells a missing key from one set to undefined, and a list from an object", () => {
  assert.equal(same({a: undefined}, {}), false);
  assert.equal(same({a: undefined}, {b: undefined}), false);
  assert.equal(same([1], {0: 1}), false);
  assert.equal(same([1, [2]], [1, [2]]), true);
  assert.equal(same([1], [1, 2]), false);
});
