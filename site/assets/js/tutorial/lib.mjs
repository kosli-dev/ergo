export const parseTime = (v) => {
  if (!JSON.rawJSON) throw new Error("this browser can't hold a time in nanoseconds exactly, so compare_time can't run here");
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

export const straighten = (text) => text.replace(/[“”]/g, '"').replace(/[‘’]/g, "'");

export const buildPolicy = (sentence) => ({
  subjects: { batch: { from: [] } },
  requirements: { tutorial: { subject: "batch", checks: { sentence } } },
});

export const parseInput = (text) => {
  let value;
  try {
    value = JSON.parse(text);
  } catch (e) {
    return { ok: false, message: `That isn't valid JSON yet. ${e.message}` };
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, message: 'The input needs to be an object, in curly brackets, like {"allergens": []}.' };
  }
  return { ok: true, value };
};

const plainWords = (message) => {
  const quote = /^unclosed quote at column (\d+)$/.exec(message);
  if (quote) return `A quote is never closed (column ${quote[1]}). Text goes between two double quotes.`;
  const after = /^nothing after the path at column (\d+)/.exec(message);
  if (after) return `The sentence stops too soon (column ${after[1]}). It needs to say what the field should do.`;
  return "ergo can't read that as a sentence yet.";
};

export const readReport = (report) => {
  const rows = report?.results ?? [];
  const well = rows.find((r) => r.check === "$well_formed");
  if (well && well.passed !== true) {
    const problem = (well.inputs ?? []).find((i) => i.name === "checks.sentence")?.value?.[0] ?? "";
    return { state: "unreadable", message: problem, plain: plainWords(problem) };
  }
  const row = rows.find((r) => r.check === "sentence");
  if (!row) return { state: "nothing" };
  return { state: "result", passed: row.passed === true, cause: row.cause, inputs: row.inputs ?? [], failed: row.failed_assertions ?? [] };
};

export const makeRunner = (evaluate) => (input, policy) => {
  const out = evaluate({ input, policy });
  return out?.length && out[0].result !== undefined ? out[0].result : null;
};

export const makeChecker = (evaluate) => (sentence, input) => {
  const text = straighten(sentence).trim();
  if (text === "") return { state: "empty" };
  const out = evaluate({ input, policy: buildPolicy(text) });
  if (!out?.length || out[0].result === undefined) return { state: "nothing" };
  return readReport(out[0].result);
};

const passes = (r) => r.state === "result" && r.passed;
const failsWith = (r, cause) => r.state === "result" && !r.passed && r.cause === cause;

const quoted = (sentence) => /"([^"]*)"/.exec(straighten(sentence))?.[1] ?? null;

const badInput = (shown) =>
  shown.message.startsWith("That isn't valid JSON") ? "The input isn't valid JSON yet. Check the commas, brackets and quotes." : shown.message;

const fieldFound = (field, say) => ({
  ok: ({ check, sentence, sample }) => check(sentence, sample).cause !== "absent",
  say: say ?? (() => `ergo can't find that field in the input. The field is \`${field}\`.`),
});

const defaultSample = { allergens: ["milk"] };

const numbersFor = (sentence, path) => {
  const m = new RegExp(`${path.replace(/\./g, "\\.")} is between (-?[\\d.]+) and (-?[\\d.]+)`).exec(straighten(sentence));
  return m ? [Number(m[1]), Number(m[2])] : null;
};

const bakeInput = (temp, minutes) => ({ bake: { temp_c: temp, minutes } });
const kitchen = (ingredients, tasters) => ({ ingredients, tasters });
const flour = { name: "flour", certified: true };
const butter = { name: "butter", certified: true };
const ana = { name: "Ana", verdict: "approved" };
const bo = { name: "Bo", verdict: "rejected" };

const otherThanNuts = (sentence) => {
  const q = quoted(sentence);
  return q !== null && q !== "nuts" ? `That checks for ${q}. We're looking for nuts.` : null;
};

const nutFreeAnswer = 'allergens does not contain "nuts"';

export const bakeryBatches = {
  batches: [
    { id: "cake-batch-2026-03-18-001", allergens: ["milk", "eggs"], bake: { minutes: 32, temp_c: 180 } },
    { id: "cake-batch-2026-03-18-002", allergens: ["nuts", "milk"], bake: { minutes: 32, temp_c: 180 } },
    { id: "cake-batch-2026-03-18-003", allergens: "nuts", bake: { minutes: 32, temp_c: 180 } },
    { id: "cake-batch-2026-03-18-004", bake: { minutes: 32, temp_c: 180 } },
  ],
};

export const steps = [
  {
    input: '{"allergens": ["milk", "eggs"]}',
    editable: false,
    goal: {
      kind: "sentence",
      ask: "This is a milk loaf, so its allergen list must warn about milk. Write a check that passes when the allergens contain milk.",
      field: "allergens",
      phrase: "contains",
      word: "milk",
      next: 'Now say what it should contain: `"milk"`',
      start: "A check is a field, then what it should do. Start with `allergens`.",
      fieldFirst: "Start with the field: `allergens`",
      answer: { sentence: 'allergens contains "milk"' },
      tests: [
        fieldFound("allergens"),
        {
          ok: ({ check, sentence }) => passes(check(sentence, { allergens: ["milk"] })),
          say: ({ sentence }) => {
            const q = quoted(sentence);
            if (q === null) return "Not quite. It should pass when the allergens contain milk.";
            return q === "milk" ? "That fails when milk is there. We want it to pass." : `That checks for ${q}. The goal is milk.`;
          },
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, { allergens: ["eggs"] }), "value"),
          say: () => "That passes even without milk. It should fail when milk is missing.",
        },
        {
          ok: ({ shown }) => passes(shown),
          say: () => "That fails on this batch, which has milk and eggs. It should pass.",
        },
      ],
      done: "That's a check. ergo read the allergens, found milk, and passed it.",
    },
  },
  {
    input: '{"allergens": ["milk", "eggs", "nuts"]}',
    editable: true,
    view: { mark: { path: ["allergens"], index: 2 } },
    goal: {
      kind: "sentence",
      ask: "This batch has nuts, and we're a nut-free bakery. Write a check that fails it.",
      field: "allergens",
      phrase: "does not contain",
      word: "nuts",
      next: 'Now the allergen: `"nuts"`',
      start: "Same shape. You'll need `does not contain`.",
      fieldFirst: "Start with the field again: `allergens`",
      answer: { sentence: nutFreeAnswer },
      tests: [
        fieldFound("allergens"),
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, { allergens: ["milk", "eggs", "nuts"] }), "value"),
          say: ({ sentence }) => {
            const q = quoted(sentence);
            if (q === "nuts") return "That passes when there are nuts. We want the opposite.";
            if (q !== null) return `That checks for ${q}. We're looking for nuts.`;
            return "Not quite. It should fail this batch, which has nuts.";
          },
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, { allergens: ["milk"] })),
          say: ({ sentence }) => otherThanNuts(sentence) ?? "That fails on a batch with no nuts. Only nuts should make it fail.",
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, { allergens: ["milk", "eggs"] })),
          say: ({ sentence }) => otherThanNuts(sentence) ?? "That fails on a batch with milk and eggs. Only nuts should make it fail.",
        },
      ],
      done: "ergo read the allergens, found nuts, and failed the batch. Cause: `value`.",
    },
  },
  {
    input: '{"baked_by": "Sam"}',
    editable: true,
    carry: true,
    carryRoot: 1,
    goal: {
      kind: "predict",
      ask: "Here's another batch. Nobody recorded its allergens. What will ergo say?",
      expect: { passed: false, cause: "absent" },
      prompt: "Pick one. ergo will show its answer.",
      wrong: "It fails.",
      explain: "Cause `absent`: nobody recorded the allergens, so ergo can't tell. When ergo isn't sure, the check fails.",
    },
  },
  {
    input: '{"allergens": "nuts"}',
    editable: true,
    carry: true,
    carryRoot: 1,
    goal: {
      kind: "predict",
      ask: "Here's another batch. Its allergens were typed as text, not a list. What will ergo say?",
      expect: { passed: false, cause: "unusable" },
      prompt: "Pick one. ergo will show its answer.",
      wrong: "It fails.",
      explain: "Cause `unusable`: the allergens are there, but not as a list, so ergo can't check them. It fails.",
    },
  },
  {
    input: '{\n  "bake": {\n    "temp_c": 180,\n    "minutes": 32\n  }\n}',
    editable: true,
    goal: {
      kind: "sentence",
      ask: "The oven must be between 175 and 200 °C. Write a check for this batch's temperature.",
      sample: bakeInput(180, 32),
      field: "bake.temp_c",
      phrase: "is between",
      start: "The temperature is inside `bake`. Join them with a dot: `bake.temp_c`.",
      fieldFirst: "Start with the field: `bake.temp_c`",
      phraseSay: "Now say the range: `is between`",
      next: "Now the two numbers, with `and` between them.",
      unreadable: "ergo can't read that yet. A check is the path, `is between`, then two numbers with `and` between them.",
      hints: [
        { re: /^temp_c\b/, text: "That field is inside `bake`. Write `bake.temp_c`." },
        { re: /^bake(?:\.(?!temp_c$)[\w-]*)?$/, text: "Join them with a dot: `bake.temp_c`." },
        { re: /^bake\.temp_c is between\s+-?[\d.]+$/, text: "Now `and`, then the top of the range." },
        { re: /^bake\.temp_c is between\s+-?[\d.]+\s+and$/, text: "Now the top of the range." },
      ],
      messages: { "min above max": "The first number is bigger than the second. Put the smaller one first." },
      answer: { sentence: "bake.temp_c is between 175 and 200" },
      tests: [
        fieldFound("bake.temp_c", ({ sentence }) =>
          /^\s*temp_c\b/.test(sentence) ? "That field is inside `bake`. Write `bake.temp_c`." : "ergo can't find that field in the input. The field is `bake.temp_c`."),
        {
          ok: ({ check, sentence }) => passes(check(sentence, bakeInput(175, 32))),
          say: ({ sentence }) => {
            const n = numbersFor(sentence, "bake.temp_c");
            return n && n[0] > 175 ? `The lowest allowed is 175, and this starts at ${n[0]}.` : "That rejects 175, and 175 is allowed.";
          },
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, bakeInput(200, 32))),
          say: ({ sentence }) => {
            const n = numbersFor(sentence, "bake.temp_c");
            return n && n[1] < 200 ? `The highest allowed is 200, and this stops at ${n[1]}.` : "That rejects 200, and 200 is allowed.";
          },
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(174, 32)), "value"),
          say: ({ sentence }) => {
            const n = numbersFor(sentence, "bake.temp_c");
            return n && n[0] < 175 ? "That lets 174 through. The low end is 175." : "Not quite. 175 to 200 are allowed, and 174 is not.";
          },
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(201, 32)), "value"),
          say: ({ sentence }) => {
            const n = numbersFor(sentence, "bake.temp_c");
            return n && n[1] > 200 ? "That lets 201 through. The top is 200." : "Not quite. 175 to 200 are allowed, and 201 is not.";
          },
        },
      ],
      done: "175 and 200 pass, 174 and 201 don't. `is between` includes both ends.",
    },
  },
  {
    input: '{\n  "bake": {\n    "temp_c": 180,\n    "minutes": 45\n  }\n}',
    editable: true,
    carry: true,
    carryRoot: 4,
    goal: {
      kind: "sentence",
      ask: "This batch baked for 45 minutes, and it must bake for 25 to 40. Your check still passes it. Add the minutes, joined with `and`.",
      sample: bakeInput(180, 32),
      field: "bake.temp_c",
      phrase: "is between",
      start: "Start from the temperature check, then add `and` and the minutes.",
      fieldFirst: "Start from the temperature check: `bake.temp_c is between 175 and 200`.",
      phraseSay: "Now say the range: `is between`",
      next: "Now the two numbers, with `and` between them.",
      unreadable: "ergo can't read that yet. Each part is a path, `is between`, then two numbers. Join the parts with `and`.",
      hints: [
        { re: /between\s+-?[\d.]+\s+and\s+-?[\d.]+\s+and$/, text: "Now the minutes, inside `bake` too: `bake.minutes`." },
        { re: /\sand\s+bake(?:\.(?!minutes$)[\w-]*)?$/, text: "Now the minutes, inside `bake` too: `bake.minutes`." },
        { re: /\sand\s+bake\.minutes$/, text: "Now say the range: `is between`" },
        { re: /\sand\s+bake\.minutes is between$/, text: "Now the two numbers, with `and` between them." },
        { re: /\sand\s+bake\.minutes is between\s+-?[\d.]+$/, text: "Now `and`, then the top of the range." },
        { re: /\sand\s+bake\.minutes is between\s+-?[\d.]+\s+and$/, text: "Now the top of the range." },
      ],
      messages: { "min above max": "A first number is bigger than the second. Put the smaller one first." },
      answer: { sentence: "bake.temp_c is between 175 and 200 and bake.minutes is between 25 and 40" },
      tests: [
        fieldFound("bake.temp_c"),
        {
          ok: ({ check, sentence }) => passes(check(sentence, bakeInput(180, 32))),
          say: () => "That fails a normal batch, 180 °C for 32 minutes. Check both ranges.",
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(210, 32)), "value") && failsWith(check(sentence, bakeInput(174, 32)), "value"),
          say: () => "The temperature must still be between 175 and 200 °C.",
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(180, 41)), "value"),
          say: ({ sentence }) => {
            const n = numbersFor(sentence, "bake.minutes");
            if (!/bake\.minutes/.test(sentence)) return "Nothing checks the minutes yet. Add them with `and`.";
            return n && n[1] > 40 ? "That lets 41 minutes through. The most is 40." : "The minutes must be 25 to 40.";
          },
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(180, 24)), "value"),
          say: () => "That lets 24 minutes through. The least is 25.",
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, bakeInput(180, 25))) && passes(check(sentence, bakeInput(180, 40))),
          say: () => "25 and 40 minutes are allowed.",
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, bakeInput(180, 45)), "value"),
          say: () => "45 minutes is too long. This batch should fail.",
        },
      ],
      done: "Both parts must pass. ergo tells you which one didn't.",
    },
  },
  {
    input: '{\n  "ingredients": [\n    {"name": "flour", "certified": true},\n    {"name": "butter", "certified": true}\n  ],\n  "tasters": [\n    {"name": "Ana", "verdict": "approved"},\n    {"name": "Bo", "verdict": "rejected"}\n  ]\n}',
    editable: true,
    goal: {
      kind: "sentence",
      ask: "Every ingredient needs a supplier certificate. Check that each one is certified.",
      sample: kitchen([flour, butter], [ana, bo]),
      field: "every ingredients.certified",
      phrase: "is",
      start: "Start with `every`, then the path through the list: `every ingredients.certified`.",
      fieldFirst: "Start with `every`, then the path through the list: `every ingredients.certified`.",
      phraseSay: "Now what it should be: `is true`",
      next: "Now the value: `true`",
      unreadable: "ergo can't read that yet. A check on a list is `every`, the path, `is`, then the value.",
      hints: [
        { re: /^every$/, text: "Now the path through the list: `ingredients.certified`." },
        { re: /^every\s+[\w-]+(?:\.(?!certified$)[\w-]*)?$/, text: "The list is `ingredients`. The certificate is inside each item: `ingredients.certified`." },
      ],
      answer: { sentence: "every ingredients.certified is true" },
      tests: [
        fieldFound("ingredients.certified", () => "ergo can't find that list in the input. The path is `ingredients.certified`."),
        {
          ok: ({ sentence }) => /^\s*(every|some)\b/.test(sentence),
          say: () => "A list needs `every` in front, to look at each item.",
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, kitchen([flour, butter], [ana, bo]))),
          say: () => "That fails when every ingredient is certified. It should pass.",
        },
        {
          ok: ({ check, sentence }) => failsWith(check(sentence, kitchen([flour, { ...butter, certified: false }], [ana, bo])), "value"),
          say: ({ sentence }) =>
            /^\s*some\b/.test(sentence)
              ? "That passes as soon as one ingredient is certified. We need every one: use `every`."
              : "That should fail when an ingredient isn't certified.",
        },
        {
          ok: ({ check, sentence }) => !passes(check(sentence, kitchen([flour, { name: "butter" }], [ana, bo]))),
          say: () => "An ingredient with no certificate should fail too.",
        },
      ],
      done: "Every ingredient has a certificate, so it passes. One without would fail it.",
    },
  },
  {
    input: '{\n  "ingredients": [\n    {"name": "flour", "certified": true},\n    {"name": "butter", "certified": true}\n  ],\n  "tasters": [\n    {"name": "Ana", "verdict": "approved"},\n    {"name": "Bo", "verdict": "rejected"}\n  ]\n}',
    editable: true,
    goal: {
      kind: "sentence",
      ask: "At least one taster must approve the batch.",
      sample: kitchen([flour, butter], [ana, bo]),
      field: "some tasters.verdict",
      phrase: "is",
      word: "approved",
      start: "Same idea, but one is enough: `some` means at least one. Start with `some`, then `tasters.verdict`.",
      fieldFirst: "Start with `some`: one taster is enough. Then `tasters.verdict`.",
      phraseSay: 'Now what it should be: `is "approved"`',
      next: 'Now the value, in double quotes: `"approved"`',
      unreadable: "ergo can't read that yet. A check on a list is `some`, the path, `is`, then the value.",
      hints: [
        { re: /^some$/, text: "Now the path through the list: `tasters.verdict`." },
        { re: /^some\s+[\w-]+(?:\.(?!verdict$)[\w-]*)?$/, text: "The list is `tasters`. The verdict is inside each taster: `tasters.verdict`." },
      ],
      answer: { sentence: 'some tasters.verdict is "approved"' },
      tests: [
        {
          ok: ({ sentence }) => !/\sis\s+(?!not\b)[A-Za-z_][\w-]*\s*$/.test(straighten(sentence).trim()),
          say: () => 'The text goes in double quotes, like `"approved"`.',
        },
        fieldFound("tasters.verdict", () => "ergo can't find that list in the input. The path is `tasters.verdict`."),
        {
          ok: ({ sentence }) => /^\s*(every|some)\b/.test(sentence),
          say: () => "A list needs `some` in front, to look at each item.",
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, kitchen([flour, butter], [ana, bo]))),
          say: ({ sentence }) => {
            const q = quoted(sentence);
            if (/^\s*every\b/.test(sentence)) return "That needs every taster to approve. One is enough: use `some`.";
            if (q !== null && q !== "approved") return `That looks for ${q}. We want "approved".`;
            return "That fails when one taster approves. It should pass.";
          },
        },
        {
          ok: ({ check, sentence }) => !passes(check(sentence, kitchen([flour, butter], [{ ...ana, verdict: "rejected" }, bo]))),
          say: () => "That passes even when nobody approves. It should fail then.",
        },
        {
          ok: ({ check, sentence }) => passes(check(sentence, kitchen([flour, butter], [ana, { ...bo, verdict: "approved" }]))),
          say: () => "That fails when everyone approves. It should pass.",
        },
      ],
      done: "`some` means at least one, so one approval is enough. ergo looked at each taster and found Ana's.",
    },
  },
  {
    input: '{"allergens": ["milk", "eggs"], "bake": {"temp_c": 180, "minutes": 32}}',
    fields: { name: "" },
    flat: true,
    goal: {
      kind: "names",
      ask: "In the report, each check is a row, and its name tells people which row failed. The other two have names. Name the first one.",
      done: "Every check has a name now. The report uses it on each row.",
    },
  },
  {
    input: '{"allergens": ["milk", "eggs"], "bake": {"temp_c": 180, "minutes": 45}}',
    fields: { heading: "", tapped: "" },
    flat: true,
    goal: {
      kind: "requirement",
      ask: "Give the requirement a heading. Then find the check that fails it.",
      done: "One failed check is enough to fail the requirement. ergo shows which one.",
    },
  },
  {
    input: JSON.stringify(bakeryBatches),
    fields: { from: "", id: "" },
    collapse: true,
    goal: {
      kind: "subjects",
      ask: "A whole day of batches in one input. Tell ergo where the list is and what tells the batches apart.",
      questions: { from: "Which key holds the list of batches?", id: "Which field tells the batches apart?" },
      done: "Four batches, one report. Tap a × to see why it failed.",
    },
  },
  {
    input: "{}",
    fields: {},
    goal: {
      kind: "policy",
      ask: "Everything you wrote is a policy.",
      done: "",
    },
  },
];

const pid = (path) => JSON.stringify(path);

const isScalar = (v) => v === null || typeof v !== "object";
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const holdsObject = (v) => isObj(v) || (Array.isArray(v) && v.some(isObj));

export const isPretty = (value) => isObj(value) && Object.values(value).some(holdsObject);

const lastThree = (id) => `\u2026${String(id).slice(-3)}`;

export const jsonSegments = (value, opts = {}) => {
  const out = [];
  let slot = null;
  const tag = () => (slot === null ? {} : { slot });
  const text = (s, within) => out.push({ text: s, within, ...tag() });
  const scalar = (v, path, within, index) => {
    const short = opts.shortIds && typeof v === "string" && path?.at(-1) === opts.shortIds && path.at(-2) === "*";
    out.push({ text: JSON.stringify(short ? lastThree(v) : v), within, leafOf: path ? pid(path) : null, index, raw: v, ...tag() });
  };
  const compact = (v, path, within) => {
    if (Array.isArray(v)) {
      text("[", within);
      v.forEach((item, i) => {
        if (i > 0) text(", ", within);
        if (isScalar(item)) scalar(item, path, within, i);
        else {
          const outer = slot;
          if (path && !path.includes("*")) slot = i;
          compact(item, path ? [...path, "*"] : null, within);
          slot = outer;
        }
      });
      text("]", within);
    } else if (isObj(v)) {
      text("{", within);
      const collapsed = opts.collapse && path?.includes("*") && slot !== opts.expand;
      Object.entries(v).forEach(([k, val], i) => {
        if (collapsed && i > 0) return;
        if (i > 0) text(", ", within);
        const child = path ? [...path, k] : null;
        out.push({ text: JSON.stringify(k), within, key: child ? pid(child) : null, ...tag() });
        text(": ", within);
        compact(val, child, child ? [...within, pid(child)] : within);
      });
      if (collapsed && Object.keys(v).length > 1) text(", …", within);
      text("}", within);
    } else {
      scalar(v, path, within, null);
    }
  };
  const block = (v, path, within, depth) => {
    const pad = "  ".repeat(depth + 1);
    const end = "  ".repeat(depth);
    if (isObj(v)) {
      text("{\n", within);
      Object.entries(v).forEach(([k, val], i) => {
        if (i > 0) text(",\n", within);
        const child = path ? [...path, k] : null;
        text(pad, within);
        out.push({ text: JSON.stringify(k), within, key: child ? pid(child) : null });
        text(": ", within);
        const inner = child ? [...within, pid(child)] : within;
        if (holdsObject(val)) block(val, child, inner, depth + 1);
        else compact(val, child, inner);
      });
      text(`\n${end}}`, within);
    } else {
      text("[\n", within);
      v.forEach((item, i) => {
        if (i > 0) text(",\n", within);
        text(pad, within);
        if (isScalar(item)) scalar(item, path, within, i);
        else {
          const outer = slot;
          if (path && !path.includes("*")) slot = i;
          compact(item, path ? [...path, "*"] : null, within);
          slot = outer;
        }
      });
      text(`\n${end}]`, within);
    }
  };
  if (!opts.flat && isPretty(value)) block(value, [], [], 0);
  else compact(value, [], []);
  return out;
};

const keyOnlyPhrases = ["does not exist", "exists", "is not empty", "is empty"];

const valuePhrases = [
  "is equal to", "does not equal", "equals", "is not one of", "is not in", "is one of", "is in", "is not",
  "is a non-empty string", "is a list", "is a string", "is a number", "is a boolean", "is an object",
  "does not contain", "contains all of", "contains none of", "contains",
  "does not match", "matches", "starts with", "ends with",
  "is at least", "is at most", "is more than", "is less than", "is between",
  "is before", "is after", "is on or after", "is on or before", "is",
];

export const readPhrase = (rest) => {
  const text = rest.trimStart();
  if (text.length === rest.length) return null;
  const found = [...keyOnlyPhrases.map((p) => [p, "key"]), ...valuePhrases.map((p) => [p, "value"])]
    .sort((a, b) => b[0].length - a[0].length)
    .find(([p]) => text.startsWith(p) && (text.length === p.length || /\s/.test(text[p.length])));
  return found ? found[1] : null;
};

export const splitSentences = (text) => {
  const parts = [];
  for (const piece of text.split(/\s+and\s+/)) {
    if (parts.length && /\bbetween\s+-?[\d.]+$/.test(parts.at(-1))) parts[parts.length - 1] += ` and ${piece}`;
    else parts.push(piece);
  }
  return parts.filter((p, i) => p.trim() !== "" || i === 0);
};

export const fieldHighlight = (sentence, value, isLast = true) => {
  const none = { exact: null, partial: [], item: null, valueLine: false, lists: [] };
  const full = straighten(sentence).trimStart();
  const quantifier = /^(?:every|some)\s+/.exec(full);
  const text = quantifier ? full.slice(quantifier[0].length) : full;
  const token = /^[\w-]+(?:\.[\w-]*)*/.exec(text)?.[0];
  if (!token || !isObj(value)) return none;
  const atEnd = isLast && token.length === text.length;
  const parts = token.split(".");
  let exact = null;
  let partial = [];
  let nodes = [value];
  let matchedAll = false;
  const walked = [];
  const lists = [];
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i];
    const objects = nodes.filter(isObj);
    const have = objects.filter((o) => Object.hasOwn(o, seg));
    if (have.length === 0) {
      if (i === parts.length - 1 && atEnd && seg !== "") {
        const keys = [...new Set(objects.flatMap((o) => Object.keys(o)))].filter((k) => k.startsWith(seg));
        partial = keys.map((k) => [...walked, k]);
      }
      break;
    }
    walked.push(seg);
    exact = [...walked];
    nodes = have.map((o) => o[seg]);
    if (i < parts.length - 1 && nodes.some(Array.isArray)) {
      lists.push([...walked]);
      walked.push("*");
      nodes = nodes.flatMap((n) => (Array.isArray(n) ? n : [n]));
    }
    if (i === parts.length - 1) matchedAll = true;
  }
  const rest = text.slice(token.length);
  let item = null;
  const literal = /"([^"]*)"|'([^']*)'|\b(true|false|null)\b|(-?\d+(?:\.\d+)?)/.exec(rest);
  if (matchedAll && literal) {
    const q = literal[1] ?? literal[2] ?? (literal[3] !== undefined ? JSON.parse(literal[3]) : Number(literal[4]));
    if (exact.includes("*")) {
      if (nodes.some((n) => n === q)) item = { path: exact, index: null, value: q };
    } else if (Array.isArray(nodes[0])) {
      const index = nodes[0].indexOf(q);
      if (index >= 0) item = { path: exact, index };
    } else if (nodes[0] === q) {
      item = { path: exact, index: null };
    }
  }
  const valueLine = matchedAll && readPhrase(rest) === "value";
  return { exact, partial, item, valueLine, lists };
};

export const fieldHighlights = (sentence, value) => {
  const full = straighten(sentence).trimStart();
  const parts = splitSentences(full);
  return parts.map((part, i) => fieldHighlight(part, value, i === parts.length - 1));
};

export const isAt = (seg, loc) => {
  if (!loc || !seg.leafOf || seg.leafOf !== pid(loc.path)) return false;
  return loc.value !== undefined ? seg.raw === loc.value : seg.index === loc.index;
};

export const segmentClasses = (seg, hl) => {
  if (Array.isArray(hl)) return [...new Set(hl.flatMap((h) => segmentClasses(seg, h)))];
  const cls = [];
  if (seg.key && ((hl.exact && seg.key === pid(hl.exact)) || (hl.lists ?? []).some((l) => pid(l) === seg.key))) cls.push("is-field");
  else if (seg.key && hl.partial.some((p) => pid(p) === seg.key)) cls.push("is-hint");
  if (hl.valueLine && hl.exact && seg.within.includes(pid(hl.exact))) cls.push("is-valueline");
  if (isAt(seg, hl.item)) cls.push("is-item");
  return cls;
};

export const judgePrediction = (goal, choice, shown) => {
  if (shown.state !== "result") return { kind: "wrong", correct: null, text: "ergo can't run it yet. Check the input and the check above." };
  const correct = (choice === "passed") === shown.passed;
  if (shown.passed !== goal.expect.passed || shown.cause !== goal.expect.cause) {
    return { kind: "done", correct, text: `ergo says ${shown.passed ? "passed" : "failed"}, cause \`${shown.cause}\`.` };
  }
  return { kind: "done", correct, text: `${correct ? "Right." : goal.wrong} ${goal.explain}` };
};

export const coach = (goal, ctx) => {
  const failed = goal.tests.find((t) => !t.ok(ctx));
  if (!failed) return { kind: "done", text: goal.done };
  const text = straighten(ctx.sentence).trim();
  const { shown } = ctx;
  if (shown.state === "empty") return { kind: "empty", text: goal.start };
  if (shown.state === "unreadable") {
    const hint = goal.hints?.find((h) => h.re.test(text));
    if (hint) return { kind: "phrase", text: hint.text };
    if (goal.messages?.[shown.message]) return { kind: "unreadable", text: goal.messages[shown.message] };
    if (!text.startsWith(goal.field)) return { kind: "empty", text: goal.fieldFirst };
    const quote = /^unclosed quote at column (\d+)$/.exec(shown.message);
    if (quote) {
      const partial = /"([^"]+)$/.exec(text)?.[1];
      return { kind: "unreadable", text: partial ? `A quote isn't closed. Add \`"\` after ${partial}.` : `A quote isn't closed. Add \`"\` to finish the text (column ${quote[1]}).` };
    }
    const hasPhrase = new RegExp(`\\b${goal.phrase}\\b`).test(text);
    if (shown.message.startsWith("nothing after the path") || (!text.includes('"') && !hasPhrase)) {
      return { kind: "phrase", text: goal.phraseSay ?? `Now say what it should do: \`${goal.phrase}\`` };
    }
    if (text.replace(/\s+/g, " ") === `${goal.field} ${goal.phrase}`) return { kind: "next", text: goal.next };
    if (goal.word && !text.includes('"')) return { kind: "unreadable", text: `The text goes in double quotes, like \`"${goal.word}"\`.` };
    return { kind: "unreadable", text: goal.unreadable ?? "ergo can't read that yet. A check is the field, then the phrase, then the text in double quotes." };
  }
  return { kind: "wrong", text: failed.say(ctx) };
};

export const grade = (goal, check, sentence, inputText, choice = null) => {
  const parsed = parseInput(inputText);
  const shown = parsed.ok ? check(sentence, parsed.value) : { state: "badinput", message: parsed.message };
  if (goal.kind === "predict") {
    const picked = choice !== null;
    return {
      shown,
      met: picked,
      say: picked && shown.state !== "badinput" ? judgePrediction(goal, choice, shown) : { kind: "predict", text: shown.state === "badinput" ? badInput(shown) : goal.prompt },
    };
  }
  const sample = goal.sample ?? defaultSample;
  const coached = goal.kind === "sentence" && !parsed.ok ? check(sentence, sample) : shown;
  return {
    shown,
    met: goal.tests.every((t) => t.ok({ check, sentence, shown, sample })),
    say: coach(goal, { check, sentence, shown: coached, sample }),
  };
};

export const carryFrom = (drafts, step) =>
  drafts[step - 1]?.sentence ?? drafts[steps[step].carryRoot]?.sentence ?? "";

export const freshDraft = (drafts, step) => ({
  sentence: steps[step].carry ? carryFrom(drafts, step) : "",
  input: steps[step].input,
  ...(steps[step].fields ? { fields: { ...steps[step].fields } } : {}),
});

export const progressDots = (pos) =>
  steps.map((_, i) => (pos >= positions.length ? "done" : positions[pos].step === i ? "current" : positions[pos].step > i ? "done" : "todo"));

export const stepTitles = ["First check", "A failure", "Nothing recorded", "The wrong kind", "Numbers", "Two parts with and", "Every", "Some", "Names", "The requirement", "A day of batches", "The policy"];

export const dotTargets = (pos, furthest = pos) =>
  steps.map((_, i) => {
    const at = positions.findIndex((p) => p.step === i);
    const state = pos < positions.length && positions[pos].step === i ? "current" : at <= Math.max(pos, furthest) ? "done" : "todo";
    return { state, tip: `Step ${i + 1} · ${stepTitles[i]}`, jump: state === "done" ? at : null };
  });

export const resultLine = (result) => ({
  cause: result.cause,
  rest: result.failed?.length ? result.failed.map((a) => a.assertion).join(" · ") : evidence(result).map((e) => `${e.name} = ${e.text}`).join(" · "),
});

export const dimResult = (goal, shown, met) => goal.kind === "sentence" && shown.state === "result" && !met;

export const showMeVisible = ({ touched, idleMs }) => touched || idleMs >= 20000;

export const evidence = (result) =>
  result.inputs.map((i) => ({
    name: i.name,
    text: result.cause === "absent" ? "not in the input" : JSON.stringify(i.value),
    missing: result.cause === "absent",
  }));

export const intro = {
  lines: [
    "We run a small bakery. Every batch of cake gets a record, like this:",
    "We'll write checks in plain English, and ergo will run them on those records.",
  ],
  example: '{"allergens": ["milk", "eggs"]}',
};

export const positions = [{ step: -1 }, ...steps.map((_, step) => ({ step }))];

export const firstPositionOf = (step) => positions.findIndex((p) => p.step === step);

export const clampPosition = (n, saved = {}) => {
  if (!Number.isInteger(n) || n < 0 || n >= positions.length) return 0;
  const { step } = positions[n];
  if ((step === 2 || step === 3) && !saved.s2) return 0;
  if (step === 5 && !saved.s5) return 0;
  return n;
};

export const keyAction = ({ key, ctrl = false, meta = false, alt = false }, target, met, kind, pending = false) => {
  if (ctrl || meta || alt) return null;
  if (target === "menu") return null;
  if (target === "sentence") {
    if (key === "Enter") return met ? "next" : pending ? "defer" : "swallow";
    if (key === "Escape") return "blur";
    return null;
  }
  if (target === "editor") return key === "Escape" ? "blur" : null;
  if (key === "Enter") return target === "body" && met ? "next" : null;
  if (key === "ArrowRight") return met ? "next" : null;
  if (key === "ArrowLeft") return kind === "intro" ? null : "back";
  if (kind === "predict") {
    if (key === "p") return "pick-passed";
    if (key === "f") return "pick-failed";
  }
  return null;
};

export const goalKindAt = (pos) => {
  if (pos === 0) return "intro";
  if (pos >= positions.length) return "end";
  return steps[positions[pos].step].goal.kind;
};

export const createEnterGate = () => {
  let typing = 0;
  let wanted = null;
  return {
    typed() { typing += 1; wanted = null; },
    press() { wanted = typing; },
    reset() { typing += 1; wanted = null; },
    evaluated(met) {
      const act = wanted === typing && met === true;
      wanted = null;
      return act;
    },
  };
};

const goodChoice = (c) => c === "passed" || c === "failed";

export const serializeProgress = (pos, drafts, furthest = pos) => ({
  pos,
  furthest,
  drafts: Object.fromEntries(
    Object.entries(drafts).map(([step, d]) => [step, { sentence: d.sentence, input: d.input, ...(d.fields ? { fields: d.fields } : {}), ...(d.choice ? { choice: d.choice } : {}), ...(d.editing ? { editing: true } : {}) }]),
  ),
});

export const restoreProgress = (saved) => {
  const drafts = {};
  const raw = saved && typeof saved.drafts === "object" && saved.drafts !== null ? saved.drafts : {};
  const goodFields = (f, step) => {
    const template = steps[step].fields;
    if (!template) return {};
    const out = { ...template };
    if (f && typeof f === "object") for (const k of Object.keys(template)) if (typeof f[k] === "string") out[k] = f[k];
    return { fields: out };
  };
  const keep = (step, d, sentence) => {
    drafts[step] = {
      sentence,
      input: d.input,
      ...goodFields(d.fields, step),
      viewed: true,
      ...(goodChoice(d.choice) ? { choice: d.choice } : {}),
      ...(d.editing === true ? { editing: true } : {}),
    };
  };
  for (const [key, d] of Object.entries(raw)) {
    const step = Number(key);
    if (!Number.isInteger(step) || step < 0 || step >= steps.length || !d || typeof d.input !== "string") continue;
    if (typeof d.sentence === "string") keep(step, d, d.sentence);
    else if (Array.isArray(d.sentences) && d.sentences.length >= 1 && d.sentences.every((x) => typeof x === "string")) {
      keep(step, d, d.sentences[0]);
      if (step === 6 && d.sentences[1]) keep(7, d, d.sentences[1]);
    }
  }
  const saves = { s2: drafts[1]?.sentence ?? "", s5: drafts[4]?.sentence ?? "" };
  const pos = clampPosition(saved?.pos, saves);
  const furthest = Number.isInteger(saved?.furthest) && saved.furthest > pos && saved.furthest <= positions.length ? saved.furthest : pos;
  return { drafts, pos, furthest };
};

export const layoutLines = (segments) => {
  const lines = [[]];
  segments.forEach((seg, index) => {
    seg.text.split("\n").forEach((piece, i) => {
      if (i > 0) lines.push([]);
      if (piece !== "") lines.at(-1).push({ text: piece, index });
    });
  });
  return lines.map((parts) => {
    let indent = 0;
    while (parts.length && /^ +$/.test(parts[0].text) && parts[0].text.length) {
      indent += parts[0].text.length;
      parts.shift();
    }
    if (parts.length) {
      const lead = /^ +/.exec(parts[0].text)?.[0].length ?? 0;
      if (lead) {
        indent += lead;
        parts[0] = { ...parts[0], text: parts[0].text.slice(lead) };
      }
    }
    return { indent, parts };
  });
};

export const defaultNames = { name: "nut_free", heading: "Safe to sell", from: "batches", id: "id" };

export const checkLines = (name) => [
  { name, sentence: 'allergens does not contain "nuts"' },
  { name: "temp_ok", sentence: "bake.temp_c is between 175 and 200" },
  { name: "time_ok", sentence: "bake.minutes is between 25 and 40" },
];

export const slug = (heading) => {
  const s = heading.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return s === "" ? "requirement" : s;
};

export const nameProblem = (name, taken = ["temp_ok", "time_ok"]) => {
  if (name === "") return "empty";
  if (/\s/.test(name)) return "space";
  if (taken.includes(name)) return "taken";
  if (name.startsWith("$")) return "dollar";
  if (/[A-Z]/.test(name) && /^[A-Za-z0-9_]+$/.test(name)) return "upper";
  if (!/^[a-z0-9_]+$/.test(name)) return "chars";
  return null;
};

const nameSay = {
  empty: "A short name, no spaces. For example `nut_free`.",
  space: "No spaces. Use `_` instead.",
  taken: "That name is taken.",
  dollar: "Names can't start with `$`. ergo keeps that for its own checks.",
  upper: "Use lowercase letters only.",
  chars: "Use only lowercase letters, digits and `_`.",
};

export const nameCoach = (name) => {
  const problem = nameProblem(name);
  return problem ? { kind: "wrong", text: nameSay[problem], met: false } : { kind: "done", text: steps[8].goal.done, met: true };
};

export const tutorialPolicy = ({ name = defaultNames.name, heading = defaultNames.heading, from = null, id = null } = {}) => ({
  subjects: { batch: from === null ? { from: [] } : { from: [from], id: [id] } },
  requirements: {
    [slug(heading)]: {
      description: heading,
      subject: "batch",
      checks: Object.fromEntries(checkLines(name).map((l) => [l.name, l.sentence])),
    },
  },
});

const rowsOf = (report) => (report?.results ?? []).filter((r) => !r.check.startsWith("$"));

export const lineResults = (report, name) => {
  const rows = rowsOf(report);
  return checkLines(name).map((l) => {
    const row = rows.find((r) => r.check === l.name);
    return { ...l, passed: row ? row.passed === true : null, cause: row?.cause ?? null };
  });
};

export const verdict = (report, key) => report?.requirements?.[key]?.status ?? null;

export const verdictWord = (status) => (status === "met" ? "met" : status === "not_met" ? "not met" : "not applicable");

export const tapOutcome = (results, tapped) => {
  if (tapped === "") return "none";
  const line = results.find((l) => l.name === tapped);
  if (!line) return "none";
  return line.passed === false ? "right" : "wrong";
};

export const requirementCoach = ({ heading, tapped }, results) => {
  if (heading.trim() === "") return { kind: "empty", text: "Write a heading for the requirement: what is it all for?", met: false };
  const outcome = tapOutcome(results, tapped);
  if (outcome === "right") return { kind: "done", text: steps[9].goal.done, met: true };
  if (outcome === "wrong") return { kind: "wrong", text: "That one passed. Look for the ×.", met: false };
  return { kind: "phrase", text: "Not met. Tap the check that's to blame.", met: false };
};

const shortId = (id) => `…${String(id).slice(-3)}`;

export const gridFromReport = (report, key, checks) => {
  const rows = rowsOf(report);
  const ids = [...new Set(rows.map((r) => r.subject.id))];
  const cells = {};
  for (const r of rows) {
    cells[`${r.subject.id}|${r.check}`] = {
      passed: r.passed === true,
      cause: r.cause,
      value: (r.inputs ?? []).map((i) => `${i.name} = ${r.cause === "absent" ? "not in the input" : JSON.stringify(i.value)}`).join(", "),
    };
  }
  return { ids, checks, cells, status: verdict(report, key), shortId };
};

export const cellLine = (grid, id, check) => {
  const c = grid.cells[`${id}|${check}`];
  return c ? `${c.passed ? "satisfied" : c.cause} · ${c.value}` : "";
};

export const defaultCell = (grid) => {
  const all = grid.ids.flatMap((id) => grid.checks.map((n) => `${id}|${n}`));
  return all.find((k) => grid.cells[k]?.passed === false) ?? all[0] ?? null;
};

export const cellHighlight = (value, from, idField, id, sentence) => {
  const list = isObj(value) ? value[from] : null;
  const slot = Array.isArray(list) ? list.findIndex((b) => isObj(b) && b[idField] === id) : -1;
  if (slot < 0) return null;
  const { exact } = fieldHighlight(sentence, list[slot]);
  const hl = exact ? { exact: [from, "*", ...exact], partial: [], item: null, valueLine: true, lists: [] } : null;
  return { slot, hl };
};

export const subjectsStatus = ({ from, id }, report) => {
  const ok = (r) => r?.requirements && Object.values(r.requirements)[0]?.subjects?.total === 4;
  const rows = rowsOf(report);
  const ids = [...new Set(rows.map((r) => r.subject.id))];
  const fromOk = Boolean(ok(report)) && from !== "";
  const idOk = fromOk && ids.length === 4 && ids.every((x) => typeof x === "string");
  return { fromOk, idOk };
};

export const subjectsCoach = ({ from, id }, state) => {
  const top = Object.keys(bakeryBatches);
  const batch = bakeryBatches.batches[0];
  if (from === "") return { kind: "empty", text: "Look at the file. Which key holds the list of batches?", met: false };
  if (!state.fromOk) {
    if (!top.includes(from)) return { kind: "wrong", text: `There's no \`${from}\` at the top of the file. Look at the first key.`, met: false };
    return { kind: "wrong", text: "That key isn't the list of batches.", met: false };
  }
  if (id === "") return { kind: "phrase", text: "Yes, that's where the batches are. Now look inside one: which field names it?", met: false };
  if (!state.idOk) {
    if (!(id in batch)) return { kind: "wrong", text: `No batch has \`${id}\`. Look for the field that looks like a name.`, met: false };
    return { kind: "wrong", text: "That isn't a name. Each batch needs a name that's different from the others.", met: false };
  }
  return { kind: "done", text: steps[10].goal.done, met: true };
};

const yamlText = (s) => (/^[A-Za-z0-9][A-Za-z0-9 ,.'_-]*$/.test(s) && !/^(true|false|null|yes|no)$/i.test(s) && !/^[\d.-]+$/.test(s) ? s : JSON.stringify(s));

export const yamlLines = (policy) => {
  const lines = [];
  const add = (text, step, note) => lines.push({ text, step, note });
  const [key, req] = Object.entries(policy.requirements)[0];
  const subj = policy.subjects.batch;
  add("subjects:", null, "A policy has two parts: what you look at, and what must be true of it.");
  add("  batch:", 11, "The thing each check is run on. You found its list in step 11.");
  add(`    from: [${subj.from?.[0] ?? ""}]`, 11, "You said where the batches are in step 11.");
  add(`    id: [${subj.id?.[0] ?? ""}]`, 11, "You said what names each batch in step 11.");
  add("requirements:", null, "The rules. Each one has a heading, a subject and some checks.");
  add(`  ${key}:`, 10, "Made from your heading in step 10.");
  add(`    description: ${yamlText(req.description)}`, 10, "Your heading from step 10.");
  add("    subject: batch", 11, "Each check runs on every batch.");
  add("    checks:", null, "The checks of this requirement, each with a name.");
  const origins = [[9, 2], [9, 5], [9, 6]];
  const names = Object.keys(req.checks);
  names.forEach((name, i) => {
    const [named, wrote] = [origins[i][0], origins[i][1]];
    add(`      ${name}: ${req.checks[name]}`, named, i === 0 ? `You named this in step ${named} and wrote it in step ${wrote}.` : `The name is from step ${named}. You wrote the sentence in step ${wrote}.`);
  });
  return lines;
};

export const policyYaml = (policy) => yamlLines(policy).map((l) => l.text).join("\n");

export const layoutMetrics = (lines, segs) => ({
  lines: lines.length,
  cols: Math.max(...lines.map((l) => l.indent + l.parts.reduce((n, p) => n + p.text.length, 0)), 1),
});
