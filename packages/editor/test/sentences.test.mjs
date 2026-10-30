import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { compile } from "@kosli/ergo-markdown";
import * as pkg from "../../../engines/rust/sentences-wasm/pkg/ergo_policy_sentences_wasm.js";
import { makeParser, readSentence, problemRange, treeTokens, describe } from "../src/sentences.mjs";
import { markdownSentences, yamlSentences } from "../src/locate.mjs";
import { makeAnalyser, decorateLines, entryAt, hoverOf, sentenceProblems } from "../src/analyse.mjs";
import { highlightMarkdown, highlightYaml } from "../src/highlight.mjs";

pkg.initSync({ module: readFileSync(new URL("../../../engines/rust/sentences-wasm/pkg/ergo_policy_sentences_wasm_bg.wasm", import.meta.url)) });
const parser = makeParser(pkg);
const corpus = JSON.parse(readFileSync(new URL("../../../spec/sentences-corpus.json", import.meta.url), "utf8")).sentence_corpus;

const policy = (checks, forLine = "") => `---
ergo_spec: v0.3-dev
---

# Items

## Subjects

### item

- From \`items\`
- Identified by \`id\`

## Requirements

### Item

- Subject \`item\`

Checks:

${checks.map((c) => `- **Named**: Has a name\n  ${forLine}${c}`).join("\n")}
`;

const markdownEntries = (source) => makeAnalyser(parser, "code")(markdownSentences(source, compile(source).blocks));
const markedText = (tokens) => tokens.filter((t) => t.problem).map((t) => t.text).join("");
const lineOf = (source, text) => source.split("\n").findIndex((l) => l.includes(text));

const kindOf = (line) => {
  for (const kind of ["check", "for", "from"]) {
    const read = parser.read(kind, line);
    if (read.tree) return [kind, read.tree];
  }
  return null;
};

test("a check that is written wrong is underlined in the Markdown with the message of check_problems", () => {
  const source = policy(["`x is not null`"]);
  const entries = markdownEntries(source);
  assert.deepEqual(sentenceProblems(entries), [{ line: lineOf(source, "x is not null") + 1, message: '"is not null" is written "exists"' }]);
  const lines = decorateLines(highlightMarkdown(source, compile(source).blocks), source, entries);
  assert.equal(markedText(lines[lineOf(source, "x is not null")]), "x is not null");
});

test("a line that is fixed loses its underline and its message", () => {
  const source = policy(["`x exists`"]);
  const entries = markdownEntries(source);
  assert.deepEqual(sentenceProblems(entries), []);
  const lines = decorateLines(highlightMarkdown(source, compile(source).blocks), source, entries);
  assert.ok(lines.every((tokens) => markedText(tokens) === ""));
});

test("a parse error with a column underlines from that column", () => {
  const source = policy(['`x is "a`']);
  const entries = markdownEntries(source);
  assert.deepEqual(sentenceProblems(entries).map((p) => p.message), ["unclosed quote at column 6"]);
  const lines = decorateLines(highlightMarkdown(source, compile(source).blocks), source, entries);
  assert.equal(markedText(lines[lineOf(source, 'x is "a')]), '"a');
});

test("a parse error without a column underlines the whole sentence", () => {
  const source = policy(["`x is`"]);
  const entries = markdownEntries(source);
  assert.deepEqual(sentenceProblems(entries).map((p) => p.message), ["doesn't parse"]);
  const lines = decorateLines(highlightMarkdown(source, compile(source).blocks), source, entries);
  assert.equal(markedText(lines[lineOf(source, "x is")]), "x is");
});

test("a for line and a check are read with the aliases of the for line", () => {
  const source = policy(["`every deployments.env equals env`"], "`for every environments as env`\n  ");
  assert.deepEqual(sentenceProblems(markdownEntries(source)), []);
  const without = policy(["`every deployments.env equals env`"]);
  assert.equal(sentenceProblems(markdownEntries(without)).length, 1);
});

test("a for line is underlined from the message of for_problems and a from line from from_problems", () => {
  const source = policy(["`x exists`"], "`for every xs as x, every x.ys as x`\n  ").replace("`items`", "`every`");
  const messages = sentenceProblems(markdownEntries(source)).map((p) => p.message);
  assert.deepEqual(messages, ["every is a word of the grammar: write .every", "x is given twice"]);
});

test("a sentence in the YAML view is underlined and a fixed one is not", () => {
  const yaml = `subjects:
  item:
    from: items
requirements:
  r:
    subject: item
    checks:
      c:
        assert:
          - x is not null
          - x exists
`;
  const entries = makeAnalyser(parser)(yamlSentences(yaml));
  assert.deepEqual(sentenceProblems(entries), [{ line: 10, message: '"is not null" is written "exists"' }]);
  const lines = decorateLines(highlightYaml(yaml), yaml, entries);
  assert.equal(markedText(lines[9]), "x is not null");
  assert.equal(markedText(lines[10]), "");
});

test("a YAML sentence in quotes that holds an escape is underlined as a whole", () => {
  const yaml = `subjects:
  item:
    from: items
requirements:
  r:
    subject: item
    checks:
      c:
        assert: 'x is not null and y is ''a'''
`;
  const entries = makeAnalyser(parser)(yamlSentences(yaml));
  assert.equal(entries.length, 2);
  const [entry] = entries.filter((e) => e.kind === "check");
  assert.equal(entry.exact, false);
  assert.equal(entry.tokens, null);
  assert.equal(entry.problems.length, 1);
  const row = yaml.split("\n")[8];
  assert.equal(row.slice(entry.problems[0].start, entry.problems[0].end), row.slice(entry.start, entry.end));
  assert.equal(row.slice(entry.start, entry.end), "x is not null and y is ''a''");
});

test("problemRange gives the word at the column, the rest from a quote and the whole text without a column", () => {
  assert.deepEqual(problemRange('x is "a', { column: 6 }), { start: 5, end: 7 });
  assert.deepEqual(problemRange("alpha beta gamma", { column: 7 }), { start: 6, end: 10 });
  assert.deepEqual(problemRange("alpha beta", { column: null }), { start: 0, end: 10 });
  assert.deepEqual(problemRange("alpha", { column: 99 }), { start: 4, end: 5 });
  assert.deepEqual(problemRange("", { column: 1 }), { start: 0, end: 0 });
});

test("a sample of corpus lines is coloured with tokens that join back to the line", () => {
  const sample = corpus.filter((_, i) => i % 14 === 0);
  assert.ok(sample.length >= 20, String(sample.length));
  const seen = new Set();
  for (const line of sample) {
    const [kind, tree] = kindOf(line);
    seen.add(kind);
    const tokens = treeTokens(kind, tree, line, [], "code");
    assert.notEqual(tokens, null, line);
    let at = 0;
    for (const t of tokens) {
      assert.equal(line.slice(at, at + t.text.length), t.text, line);
      at += t.text.length;
      assert.ok(["word", "field", "alias", "ref", "string", "number", "code"].includes(t.kind), `${line}: ${t.kind}`);
    }
    assert.equal(at, line.length);
  }
  assert.ok(seen.has("check") && seen.has("for") && seen.has("from"), [...seen].join());
});

test("every line of the corpus that reads is coloured from its tree", () => {
  for (const line of corpus) {
    const found = kindOf(line);
    if (!found) continue;
    assert.notEqual(treeTokens(found[0], found[1], line, [], "code"), null, line);
  }
});

const pairs = (tokens) => tokens.filter((t) => t.kind !== "code").map((t) => `${t.kind}:${t.text}`);

test("grammar words, names, refs, strings and numbers get their own kinds", () => {
  const line = 'attestations_statuses named by $params.pr_attestation_name.status is "COMPLETE"';
  const read = parser.read("check", line);
  assert.deepEqual(pairs(treeTokens("check", read.tree, line, [], "code")), [
    "field:attestations_statuses",
    "word:named",
    "word:by",
    "ref:$params.pr_attestation_name",
    "field:.status",
    "word:is",
    'string:"COMPLETE"',
  ]);
});

test("a name that is an alias of the for line is coloured as an alias, and a dotted one is a field", () => {
  const line = "approver.username does not equal pr.author and .pr is 1";
  const { tree } = parser.read("check", line);
  assert.deepEqual(pairs(treeTokens("check", tree, line, ["pr", "approver"], "code")), [
    "alias:approver",
    "field:.username",
    "word:does",
    "word:not",
    "word:equal",
    "alias:pr",
    "field:.author",
    "word:and",
    "field:.pr",
    "word:is",
    "number:1",
  ]);
});

test("a for line colours its aliases and its sort order", () => {
  const line = "last of commits sorted by timestamp alphabetically as latest, every latest.files whose size is more than 10 as file";
  const { tree } = parser.read("for", line);
  assert.deepEqual(pairs(treeTokens("for", tree, line, [], "code")), [
    "word:last",
    "word:of",
    "field:commits",
    "word:sorted",
    "word:by",
    "field:timestamp",
    "word:alphabetically",
    "word:as",
    "alias:latest",
    "word:every",
    "field:latest.files",
    "word:whose",
    "field:size",
    "word:is",
    "word:more",
    "word:than",
    "number:10",
    "word:as",
    "alias:file",
  ]);
});

test("a name that spells a type word is a field where a name is expected and a word where a phrase is", () => {
  const line = "list is a list";
  const { tree } = parser.read("check", line);
  assert.deepEqual(pairs(treeTokens("check", tree, line, [], "code")), ["field:list", "word:is", "word:a", "word:list"]);
});

test("tokens are not made when the text and the tree disagree", () => {
  const { tree } = parser.read("check", "x is 1");
  assert.equal(treeTokens("check", tree, "y is 1", [], "code"), null);
  assert.equal(treeTokens("check", tree, "x is 2", [], "code"), null);
  assert.equal(treeTokens("check", tree, "x is 1 2", [], "code"), null);
  assert.equal(treeTokens("check", tree, "x is", [], "code"), null);
});

const kindsByLetter = (tokens) => tokens.flatMap((t) => Array.from(t.text, () => t.kind));

test("a line with a sentence that doesn't read keeps the pattern colours and gets an underline", () => {
  const source = policy(['`x is "a`']);
  const blocks = compile(source).blocks;
  const plain = highlightMarkdown(source, blocks);
  const lines = decorateLines(plain, source, markdownEntries(source));
  const i = lineOf(source, 'x is "a');
  assert.deepEqual(kindsByLetter(lines[i]), kindsByLetter(plain[i]));
  assert.equal(markedText(lines[i]), '"a');
});

test("without the sentences Wasm nothing is changed and the pattern colours stay", () => {
  const source = policy(["`x is not null`"]);
  const blocks = compile(source).blocks;
  const analyse = makeAnalyser(null, "code");
  const entries = analyse(markdownSentences(source, blocks));
  assert.equal(entries, null);
  const plain = highlightMarkdown(source, blocks);
  assert.equal(decorateLines(plain, source, entries), plain);
  assert.deepEqual(sentenceProblems(entries), []);
  assert.equal(entryAt(entries, 1, 0), null);
});

test("a parser that throws is dropped, and the analyser gives null from then on", () => {
  const broken = makeParser({ ...pkg, parse_check: () => { throw new WebAssembly.RuntimeError("unreachable"); } });
  const source = policy(["`x exists`"]);
  const analyse = makeAnalyser(broken, "code");
  assert.equal(analyse(markdownSentences(source, compile(source).blocks)), null);
  assert.equal(broken.read("for", "every xs as x"), null);
  assert.equal(readSentence(broken, "check", "x exists"), null);
  assert.equal(readSentence(null, "check", "x exists"), null);
});

const reading = (line, aliases = [], ctx = {}) => {
  const [kind, tree] = kindOf(line);
  return describe(kind, tree, ctx).join("\n");
};

test("hover reads an every walk with a whose and a param", () => {
  assert.equal(
    reading("every p.items.name whose zz is $params.foo is not empty"),
    [
      "Passes when every value of p.items.name, kept when zz is $params.foo, is not empty. Fails when a value of p.items.name is missing, null or not a list or a string.",
      "every walks into every list along p.items.name, the last one included, and passes when every value passes, and fails when none are left to check.",
      "An item is left out only when a condition is false for it, or when an exists condition finds the field missing. An item a condition can't decide, because a field is missing, null or of the wrong type, fails instead.",
      "$params.foo is the value of foo in the params the report was given.",
    ].join("\n"),
  );
});

test("hover says that if any lets an empty list pass and that some needs one", () => {
  assert.match(reading("every xs, if any, is 1"), /passes when every value passes, or when none are left to check/);
  assert.match(reading("some xs is 1"), /some walks into every list along xs.*passes when at least one value passes/);
});

test("hover names what an alias of the for line stands for", () => {
  const forTree = parser.read("for", "every pull_requests as pr, some pr.approvers as approver").tree;
  const { tree } = parser.read("check", "approver.username does not equal pr.author");
  assert.deepEqual(describe("check", tree, { forTree }), [
    "Passes when approver.username is not pr.author. Fails when approver.username or what it is compared with is missing or null, or the two have different types.",
    "approver is each item of pr.approvers. pr passes when some approver passes, and approver passes when all the checks hold.",
    "pr is each item of pull_requests. Every pr must pass.",
  ]);
});

test("hover does not call a name an alias on the left of a whose", () => {
  const forTree = parser.read("for", "every environments as env").tree;
  const { tree } = parser.read("check", 'some deployments.name whose env is "prod" exists');
  assert.ok(!describe("check", tree, { forTree }).some((l) => l.startsWith("env is each item")));
});

test("hover names the path a part of the subject stands for", () => {
  const { tree } = parser.read("check", "coverage.hunks is at least 3");
  assert.deepEqual(describe("check", tree, { parts: { coverage: "compliance_status.cov" } }), [
    "Passes when coverage.hunks is at least 3. Fails when coverage.hunks is missing, null or not a number.",
    "coverage is the part of the subject at compliance_status.cov.",
  ]);
});

test("hover reads a for line, a pick and its sort order", () => {
  assert.deepEqual(reading("last of commits sorted by timestamp as latest, every latest.files as file"), [
    "latest is the last item of commits, in order of timestamp. When the list has no such item, the check fails as absent. When another item has the same value, the check fails as ambiguous. The picked latest must pass.",
    "file is each item of latest.files. latest passes when every file passes, and file passes when all the checks hold.",
  ].join("\n"));
});

test("hover reads a from line that goes on from another subject", () => {
  const { tree } = parser.read("from", "artifact.pull_requests whose base is $params.branch");
  assert.deepEqual(describe("from", tree, { subjects: ["artifact", "pr"], subject: "pr" }), [
    "The subject's rows come from the rows of the subject artifact, at artifact.pull_requests.",
    "Only rows where base is $params.branch are in scope.",
    "A subject is left out only when a filter is false for it, or when an exists filter finds its field missing. A filter that can't be decided, because a field is missing, null or of the wrong type, fails the requirement instead.",
    "$params.branch is the value of branch in the params the report was given.",
  ]);
});

test("hover reads a count, a sum, elapsed time, between and within", () => {
  assert.match(reading("count of xs whose n is 1 is at least 2"), /^Passes when the number of xs, kept when n is 1, is at least 2\. Fails when xs is missing, null or not a list\./);
  assert.equal(reading("n is between 5 and 9"), "Passes when n is between 5 and 9, both included. Fails when n is missing, null or not a number.");
  assert.equal(reading("n is 6 within 1"), "Passes when n is within 1 of 6. Fails when n is missing, null or not a number.");
  assert.equal(reading("days elapsed from s to e is 2"), "Passes when the days from s to e is 2. Fails when either time of the days from s to e is missing, null or not a time.");
  assert.equal(reading("it is a non-empty string"), "Passes when it is a string with at least one character. Fails when it is missing, null or not a string.\nit is the subject itself.");
});

test("hover shows the reading and the problems of the sentence under the pointer", () => {
  const source = policy(["`x is not null`", "`x is at least 2`"]);
  const entries = markdownEntries(source);
  const line = lineOf(source, "x is at least 2") + 1;
  const entry = entryAt(entries, line, source.split("\n")[line - 1].indexOf("at least"));
  assert.deepEqual(hoverOf(entry), { problems: [], lines: ["Passes when x is at least 2. Fails when x is missing, null or not a number."] });
  const bad = entryAt(entries, lineOf(source, "x is not null") + 1, 6);
  assert.deepEqual(hoverOf(bad).problems, ['"is not null" is written "exists"']);
  assert.equal(entryAt(entries, 1, 0), null);
});

test("markdownSentences finds each sentence with its place, its for line and its subject", () => {
  const source = readFileSync(new URL("../../markdown/cases/for-line-peer-approval/policy.ergo.md", import.meta.url), "utf8");
  const { sentences, subjects } = markdownSentences(source, compile(source).blocks);
  assert.deepEqual(subjects, ["release"]);
  assert.deepEqual(sentences.map((s) => s.kind), ["from", "check", "for", "check", "check"]);
  const lines = source.split("\n");
  for (const s of sentences) assert.equal(lines[s.line - 1].slice(s.start, s.end), s.text);
  assert.deepEqual(sentences.map((s) => s.forText), [null, null, null, "every pull_requests as pr, some pr.approvers as approver", "every pull_requests as pr, some pr.approvers as approver"]);
  assert.equal(sentences[0].subject, "release");
  assert.deepEqual(sentenceProblems(makeAnalyser(parser, "code")({ sentences, subjects })), []);
});

test("yamlSentences finds the from, for, assert and any_of sentences, the parts of the subject and where each is written", () => {
  const yaml = `subjects:
  round:
    from: rounds
    has:
      coverage: compliance_status.cov
      other:
        from: x.y
requirements:
  r:
    subject: round
    checks:
      a:
        for: every xs as x
        assert:
          - x.n is 1
          - |
            coverage.n is 2
      b:
        any_of:
          one: "y exists"
          two:
            - 'z exists'
`;
  const { sentences, subjects } = yamlSentences(yaml);
  assert.deepEqual(subjects, ["round"]);
  assert.deepEqual(sentences.map((s) => [s.kind, s.text, s.line, s.exact]), [
    ["from", "rounds", 3, true],
    ["for", "every xs as x", 13, true],
    ["check", "x.n is 1", 15, true],
    ["check", "coverage.n is 2", 17, true],
    ["check", "y exists", 20, true],
    ["check", "z exists", 22, true],
  ]);
  const rows = yaml.split("\n");
  for (const s of sentences) assert.equal(rows[s.line - 1].slice(s.start, s.end), s.text);
  assert.deepEqual(sentences[2].parts, { coverage: "compliance_status.cov", other: "x.y" });
  assert.equal(sentences[2].forText, "every xs as x");
  assert.equal(sentences[4].forText, null);
});

test("yamlSentences gives nothing for text that isn't a policy", () => {
  assert.deepEqual(yamlSentences("").sentences, []);
  assert.deepEqual(yamlSentences("- 1\n- 2").sentences, []);
  assert.deepEqual(yamlSentences("subjects: 4\nrequirements: x").sentences, []);
});

const hoverFirst = (line, ctx = {}) => {
  const [kind, tree] = kindOf(line);
  return describe(kind, tree, ctx)[0];
};

const failsClosed = [
  ['x is "a"', "x is missing, null or not a string"],
  ['x is not "a"', "x is missing, null or not a string"],
  ["x is 1", "x is missing, null or not a number"],
  ["x is true", "x is missing, null or not a boolean"],
  ["x is null", "x is missing"],
  ["x does not equal y", "x or what it is compared with is missing or null, or the two have different types"],
  ['x is one of "a", "b"', "x is missing, null or not the same type as the values"],
  ['x is not one of "a"', "x is missing, null or not the same type as the values"],
  ["x is not one of $params.k", "x is missing, null or not the type of the values in the list, or the list it is compared with is missing, null or not a list of one type"],
  ["x exists", "x is missing or null"],
  ["x does not exist", "x has a value that isn't null"],
  ["x.y does not exist", "x.y has a value that isn't null, or something it sits in is not an object"],
  ["x is empty", "x is missing, null or not a list or a string"],
  ["x is not empty", "x is missing, null or not a list or a string"],
  ["x is a list", "x is missing, null or not a list"],
  ["x is an object", "x is missing, null or not an object"],
  ["x is a non-empty string", "x is missing, null or not a string"],
  ['x contains "a"', "x is missing, null or not a list, or its items are of another type than the value"],
  ['labels does not contain "a"', "labels is missing, null or not a list, or its items are of another type than the value"],
  ["x contains y", "x is missing, null or not a list, or what it is compared with is missing or null or of another type than the items"],
  ['x contains all of "a"', "x is missing, null or not a list, or its items are of another type than the values"],
  ['x contains none of "a", "b"', "x is missing, null or not a list, or its items are of another type than the values"],
  ["x contains none of $params.k", "x is missing, null or not a list, or the list it is compared with is missing, null, empty or not a list of one type"],
  ['x matches "a"', "x is missing, null or not a string"],
  ['x does not match "a"', "x is missing, null or not a string"],
  ["x does not match $params.p", "x is missing, null or not a string, or the patterns are missing, null, not a list or not all valid regular expressions"],
  ['x starts with "a"', "x is missing, null or not a string"],
  ['x is alphabetically before "b"', "x is missing, null or not a string"],
  ["x is at least 2", "x is missing, null or not a number"],
  ["x is at least y", "x or what it is compared with is missing, null or not a number"],
  ["x is between 1 and 3", "x is missing, null or not a number"],
  ['x is before "2026-01-01"', "x is missing, null or not a time in the same format as what it is compared with"],
  ["x is 3 within 1", "x is missing, null or not a number"],
  ["sum of x is 3", "x is missing, null or not a list of numbers"],
  ["count of x is 1", "x is missing, null or not a list"],
];

test("hover says what fails every kind of check, so a check that can't read its value is never taken for a pass", () => {
  for (const [line, fails] of failsClosed) assert.match(hoverFirst(line), new RegExp(`\\. Fails when ${fails.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\.$`), line);
});

test("hover says that a value in a list the check walks into fails the check when it is missing", () => {
  assert.match(hoverFirst("every xs.y is not empty"), /Fails when a value of xs\.y is missing, null or not a list or a string\.$/);
  assert.match(hoverFirst("some xs.y is 2"), /Fails when a value of xs\.y is missing, null or not a number\.$/);
});

test("hover says what fails each of several checks", () => {
  const [kind, tree] = kindOf("x is 1 and y exists");
  assert.equal(
    describe(kind, tree, {}).at(-1),
    "Fails when any of them fails, and in particular when x is missing, null or not a number, or when y is missing or null.",
  );
});

test("hover says that a whose that can't decide an item fails the check, in checks, counts and for lines", () => {
  const note = "An item is left out only when a condition is false for it, or when an exists condition finds the field missing. An item a condition can't decide, because a field is missing, null or of the wrong type, fails instead.";
  assert.ok(reading("every xs.v whose n is 1 is 5").includes(note));
  assert.ok(reading("count of xs whose n is 1 is 2").includes(note));
  assert.ok(!reading("every xs.v is 5").includes("left out"));
  assert.match(reading("every cs whose n is 1 as c"), /An item the whose can't decide fails the check\./);
  assert.match(reading("item 1 of cs whose n is 1 as c"), /An item the whose can't decide fails the check\./);
});

test("hover says that a from filter that can't be decided fails the requirement and does not leave the subject out", () => {
  const lines = reading('things whose kind is "a"');
  assert.match(lines, /A subject is left out only when a filter is false for it, or when an exists filter finds its field missing\. A filter that can't be decided, because a field is missing, null or of the wrong type, fails the requirement instead\./);
  assert.ok(!reading("things").includes("left out"));
});

test("hover reads named by each of as one subject per listed key, even for a key the object doesn't have", () => {
  const lines = reading("attestations named by each of $params.keys");
  assert.match(lines, /attestations is read in the input as an object\./);
  assert.match(lines, /one subject for each key listed in \$params\.keys, which must be a list of strings\. A listed key the object doesn't have is still a subject, and its checks fail\./);
  assert.match(lines, /When the object can't be read, the requirement fails, and each listed key is still a subject\./);
  assert.ok(!lines.includes("rows"));
  const child = describe("from", parser.read("from", "artifact named by each of $params.keys").tree, { subjects: ["artifact", "att"], subject: "att" });
  assert.equal(child[0], "The keys belong to each subject artifact, which must be an object.");
});

test("hover reads a for line with some as each item passing when some of the next items pass", () => {
  assert.equal(
    reading("every prs as pr, some pr.approvers as approver"),
    [
      "pr is each item of prs. Every pr must pass.",
      "approver is each item of pr.approvers. pr passes when some approver passes, and approver passes when all the checks hold.",
    ].join("\n"),
  );
  assert.ok(!reading("some prs as pr, every pr.approvers as approver").includes("combination"));
  assert.match(reading("some prs as pr, every pr.approvers as approver"), /^pr is each item of prs\. At least one pr must pass\.\napprover is each item of pr\.approvers\. pr passes when every approver passes,/);
});

test("hover says that a pick past the end fails as absent and that equal sort values fail as ambiguous", () => {
  assert.equal(
    reading("item 2 of commits sorted by timestamp as c"),
    "c is item 2 of commits, in order of timestamp. When the list has no such item, the check fails as absent. When another item has the same value, the check fails as ambiguous.",
  );
  const plain = reading("first of commits as c");
  assert.match(plain, /fails as absent\./);
  assert.ok(!plain.includes("ambiguous"));
});

test("hover prints a quoted first key that is written as a field the way the report names it", () => {
  assert.match(hoverFirst('"a"."b" is 1'), /^Passes when \.a\.b is 1\./);
  assert.match(hoverFirst('"a.b"."c" is 1'), /^Passes when "a\.b"\.c is 1\./);
});

test("a quoted first key that is a word of the grammar is coloured like any other quoted key", () => {
  const colours = (line) => pairs(treeTokens("check", parser.read("check", line).tree, line, ["a"], "code"));
  assert.deepEqual(colours('"a".b is 1'), ['string:"a"', "field:.b", "word:is", "number:1"]);
  assert.deepEqual(colours('"x".b is 1'), ['string:"x"', "field:.b", "word:is", "number:1"]);
});

test("no hover over a line that reads says undefined", () => {
  const quoted = ['"a"."b" is 1', '"empty".items exists', 'every "count".x is 1', 'count of "it".xs is 2'];
  for (const line of [...corpus, ...quoted]) {
    const found = kindOf(line);
    if (!found) continue;
    const text = describe(found[0], found[1]).join("\n");
    assert.ok(!text.includes("undefined"), `${line}: ${text}`);
  }
});

test("a name after named by that isn't an alias is coloured as a field", () => {
  const { tree } = parser.read("check", "x named by y is 1");
  assert.deepEqual(treeTokens("check", tree, "x named by y is 1", [], "code").filter((t) => t.text === "y"), [{ kind: "field", text: "y" }]);
  assert.deepEqual(treeTokens("check", tree, "x named by y is 1", ["y"], "code").filter((t) => t.text === "y"), [{ kind: "alias", text: "y" }]);
});

const one = (text, parts, kind = "check") => {
  const entries = makeAnalyser(parser, "code")({ sentences: [{ kind, text, forText: null, parts, subject: "s", exact: true, start: 10, end: 10 + text.length, line: 1 }], subjects: [] });
  return entries[0];
};

test("naming a part after named by is underlined on the part with the message ergo.rego gives", () => {
  const entry = one("x named by cov is 1", { cov: "a.b" });
  assert.deepEqual(entry.problems, [{ message: "named by cov reads a part, which isn't supported yet", start: 10 + 11, end: 10 + 14 }]);
});

test("a part named by in two places gives one message, and a part in a string or an ordinary name gives none", () => {
  assert.equal(one("x named by cov is 1 and y named by cov is 2", { cov: "a.b" }).problems.length, 1);
  assert.deepEqual(one('x is "named by cov"', { cov: "a.b" }).problems, []);
  assert.deepEqual(one("x named by other is 1", { cov: "a.b" }).problems, []);
  assert.deepEqual(one("x named by cov is 1", {}).problems, []);
});

test("a part with a quoted dotted key stands for that key in the aliases", () => {
  const entry = one("cov.x is 1", { cov: 'a."b.c"' });
  assert.equal(entry.aliasKeys.cov, "b.c");
  assert.equal(one("cov.x is 1", { cov: "a.b[0]" }).aliasKeys.cov, "b");
});
