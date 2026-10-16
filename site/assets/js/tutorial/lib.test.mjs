import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import opa from "../../tutorial/vendor/opa-wasm.mjs";
import * as lib from "./lib.mjs";
import { defaultCell, cellHighlight, makeRunner, defaultNames, checkLines, slug, nameProblem, nameCoach, tutorialPolicy, lineResults, verdict, verdictWord, tapOutcome, requirementCoach, gridFromReport, cellLine, subjectsStatus, subjectsCoach, yamlLines, policyYaml, bakeryBatches, createEnterGate, serializeProgress, restoreProgress, layoutLines, splitSentences, fieldHighlights, keyAction, goalKindAt, isPretty, firstPositionOf, progressDots, stepTitles, dotTargets, resultLine, carryFrom, dimResult, freshDraft, judgePrediction, jsonSegments, fieldHighlight, segmentClasses, isAt, showMeVisible, buildPolicy, clampPosition, intro, positions, evidence, grade, makeChecker, parseInput, parseTime, steps, straighten } from "./lib.mjs";

const wasm = readFileSync(new URL("../../tutorial/ergo.wasm", import.meta.url));
const ergo = await opa.loadPolicy(wasm, undefined, { "time.parse_rfc3339_ns": parseTime });
const check = makeChecker((doc) => ergo.evaluate(doc));

const goalMet = (step, goal, sentence, input) =>
  grade(steps[step].goal, check, sentence, input ?? steps[step].input).met;

const nutFree = 'allergens does not contain "nuts"';

test("the policy has one subject that is the whole input, one requirement and one check", () => {
  assert.deepEqual(buildPolicy("x is 1"), {
    subjects: { batch: { from: [] } },
    requirements: { tutorial: { subject: "batch", checks: { sentence: "x is 1" } } },
  });
});

test("curly quotes become straight quotes before ergo reads them", () => {
  assert.equal(straighten("allergens contains “milk”"), 'allergens contains "milk"');
  assert.equal(straighten("a is ‘b’"), "a is 'b'");
  const r = check("allergens contains “milk”", { allergens: ["milk"] });
  assert.deepEqual([r.state, r.passed, r.cause], ["result", true, "satisfied"]);
});

test("ergo gives the causes the steps explain", () => {
  const cause = (s, i) => { const r = check(s, i); return [r.passed, r.cause]; };
  assert.deepEqual(cause(nutFree, { allergens: ["nuts", "milk"] }), [false, "value"]);
  assert.deepEqual(cause(nutFree, { baked_by: "Sam" }), [false, "absent"]);
  assert.deepEqual(cause(nutFree, { allergens: "nuts" }), [false, "unusable"]);
});

test("an empty sentence is empty, not an error", () => {
  assert.equal(check("   ", {}).state, "empty");
});

test("a sentence that is written wrong gives ergo's message in plain words", () => {
  const r = check('allergens contains "milk', { allergens: ["milk"] });
  assert.equal(r.state, "unreadable");
  assert.equal(r.message, "unclosed quote at column 20");
  assert.match(r.plain, /quote is never closed \(column 20\)/);
  assert.equal(check("allergens", {}).state, "unreadable");
});

test("the input must be a JSON object", () => {
  assert.equal(parseInput('{"a": 1}').ok, true);
  for (const bad of ["", "{", "[]", "5", "null"]) assert.equal(parseInput(bad).ok, false, bad);
  assert.match(parseInput("{").message, /isn't valid JSON/);
});

test("evidence shows what the row read", () => {
  const r = check(nutFree, { allergens: ["milk", "eggs"] });
  assert.deepEqual(evidence(r), [{ name: "allergens", text: '["milk","eggs"]', missing: false }]);
  assert.equal(evidence(check(nutFree, {}))[0].missing, true);
});

test("step 1 is met by the hint sentence and not by a wrong one", () => {
  assert.equal(goalMet(0, 0, 'allergens contains "milk"'), true);
  assert.equal(goalMet(0, 0, "allergens contains “milk”"), true);
  assert.equal(goalMet(0, 0, 'allergens contains "eggs"'), false);
  assert.equal(goalMet(0, 0, 'allergens contains "nuts"'), false);
  assert.equal(goalMet(0, 0, 'allergens does not contain "milk"'), false);
  assert.equal(goalMet(0, 0, ""), false);
  assert.equal(goalMet(0, 0, 'allergens contains "milk'), false);
});

test("step 2 goal A is met by the hint sentence and not by a wrong one", () => {
  assert.equal(goalMet(1, 0, nutFree), true);
  assert.equal(goalMet(1, 0, 'allergens contains "nuts"'), false);
  assert.equal(goalMet(1, 0, 'allergens contains "milk"'), false);
  assert.equal(goalMet(1, 0, 'allergens does not contain "milk"'), false);
  assert.equal(goalMet(1, 0, ""), false);
});

test("step 2 goal A does not depend on what the reader has done to the input", () => {
  assert.equal(goalMet(1, 0, nutFree, '{"allergens": ["nuts"]}'), true);
  assert.equal(goalMet(1, 0, nutFree, "{"), true);
});

test("the screens are the intro, then one per step in order", () => {
  assert.deepEqual(positions, [{ step: -1 }, ...Array.from({ length: 12 }, (_, step) => ({ step }))]);
  assert.equal(steps.every((s) => s.goals === undefined && s.goal !== undefined), true);
});

test("a saved screen that needs an earlier sentence starts again without it", () => {
  const none = {};
  const s2 = { s2: nutFree };
  const both = { s2: nutFree, s5: "bake.temp_c is between 175 and 200" };
  assert.equal(clampPosition(1, none), 1);
  assert.equal(clampPosition(2, none), 2);
  assert.equal(clampPosition(3, none), 0);
  assert.equal(clampPosition(4, none), 0);
  assert.equal(clampPosition(3, s2), 3);
  assert.equal(clampPosition(5, s2), 5);
  assert.equal(clampPosition(6, s2), 0);
  assert.equal(clampPosition(6, both), 6);
  assert.equal(clampPosition(7, none), 7);
  assert.equal(clampPosition(8, none), 8);
  assert.equal(clampPosition(13, both), 0);
  assert.equal(clampPosition(9, none), 9);
  assert.equal(clampPosition("2", both), 0);
  assert.equal(clampPosition(1), 1);
});

test("the intro example is a record ergo can read, and ergo is lowercase", () => {
  assert.equal(parseInput(intro.example).ok, true);
  assert.equal(/\bErgo\b|ERGO/.test(JSON.stringify(intro)), false);
});

const say = (step, goal, sentence, input) => grade(steps[step].goal, check, sentence, input ?? steps[step].input).say;

test("the answer of every goal meets that goal", () => {
  steps.filter((s) => s.goal.kind === "sentence").forEach((s) => {
    const si = steps.indexOf(s);
    const g = s.goal;
    const sentence = g.answer.sentence ?? nutFree;
    const input = g.answer.input ?? s.input;
    const r = grade(g, check, sentence, input);
    assert.equal(r.met, true, `step ${si + 1}`);
    assert.equal(r.say.kind, "done");
  });
});

test("step 1 coaching: empty", () => {
  assert.deepEqual(say(0, 0, ""), { kind: "empty", text: "A check is a field, then what it should do. Start with `allergens`." });
});

test("step 1 coaching: the field without a phrase says what comes next", () => {
  assert.deepEqual(say(0, 0, "allergens"), { kind: "phrase", text: "Now say what it should do: `contains`" });
  assert.equal(say(0, 0, "allergens contain").kind, "phrase");
});

test("step 1 coaching: a sentence that doesn't start with the field starts again", () => {
  assert.deepEqual(say(0, 0, "milk"), { kind: "empty", text: "Start with the field: `allergens`" });
});

test("step 1 coaching: an unclosed quote points at the text", () => {
  assert.deepEqual(say(0, 0, 'allergens contains "milk'), { kind: "unreadable", text: "A quote isn't closed. Add `\"` after milk." });
  assert.match(say(0, 0, 'allergens contains "').text, /column 20/);
});

test("step 1 coaching: text without quotes asks for quotes", () => {
  assert.equal(say(0, 0, "allergens contains milk").text, 'The text goes in double quotes, like `"milk"`.');
});

test("step 1 coaching: the wrong field", () => {
  assert.equal(say(0, 0, 'alergens contains "milk"').text, "ergo can't find that field in the input. The field is `allergens`.");
});

test("step 1 coaching: checking for eggs", () => {
  assert.deepEqual(say(0, 0, 'allergens contains "eggs"'), { kind: "wrong", text: "That checks for eggs. The goal is milk." });
});

test("step 1 coaching: failing when milk is there", () => {
  assert.equal(say(0, 0, 'allergens does not contain "milk"').text, "That fails when milk is there. We want it to pass.");
});

test("step 1 coaching: passing without milk", () => {
  assert.equal(say(0, 0, 'allergens does not contain "eggs"').text, "That fails on this batch, which has milk and eggs. It should pass.");
  assert.equal(say(0, 0, "allergens is empty").text, "Not quite. It should pass when the allergens contain milk.");
  assert.equal(say(0, 0, "allergens is a list").text, "That passes even without milk. It should fail when milk is missing.");
  assert.equal(say(0, 0, 'allergens is not "x"').kind, "wrong");
});

test("step 1 coaching: done", () => {
  assert.deepEqual(say(0, 0, 'allergens contains "milk"'), { kind: "done", text: steps[0].goal.done });
});

test("step 2 coaching: empty, phrase, quotes and unclosed quote", () => {
  assert.deepEqual(say(1, 0, ""), { kind: "empty", text: "Same shape. You'll need `does not contain`." });
  assert.equal(say(1, 0, "milk").text, "Start with the field again: `allergens`");
  assert.deepEqual(say(1, 0, "allergens"), { kind: "phrase", text: "Now say what it should do: `does not contain`" });
  assert.equal(say(1, 0, "allergens does not").kind, "phrase");
  assert.equal(say(1, 0, "allergens does not contain nuts").text, 'The text goes in double quotes, like `"nuts"`.');
  assert.equal(say(1, 0, 'allergens does not contain "nuts').text, "A quote isn't closed. Add `\"` after nuts.");
});

test("step 2 coaching: contains nuts passes when there are nuts", () => {
  assert.deepEqual(say(1, 0, 'allergens contains "nuts"'), { kind: "wrong", text: "That passes when there are nuts. We want the opposite." });
});

test("step 2 coaching: another allergen", () => {
  assert.equal(say(1, 0, 'allergens does not contain "milk"').text, "That checks for milk. We're looking for nuts.");
});

test("step 2 coaching: failing on a batch without nuts", () => {
  assert.equal(say(1, 0, 'allergens contains "milk"').text, "That checks for milk. We're looking for nuts.");
  assert.equal(say(1, 0, "allergens is not empty").text, "Not quite. It should fail this batch, which has nuts.");
  assert.equal(say(1, 0, 'allergens contains "nuts" and allergens contains "milk"').kind, "wrong");
});

test("step 2 coaching: a sentence that fails milk and eggs", () => {
  assert.equal(say(1, 0, 'allergens does not contain "nuts" and allergens contains "x"').text, "That fails on a batch with no nuts. Only nuts should make it fail.");
});

test("step 2 coaching: done", () => {
  assert.deepEqual(say(1, 0, nutFree), { kind: "done", text: "ergo read the allergens, found nuts, and failed the batch. Cause: `value`." });
});

test("step 2 coaching: a bad input doesn't hide the sentence coaching", () => {
  assert.equal(say(1, 0, 'allergens contains "nuts"', "{").kind, "wrong");
  assert.equal(say(1, 0, "", "{").kind, "empty");
});

test("show me appears after typing or after 20 seconds", () => {
  assert.equal(showMeVisible({ touched: false, idleMs: 0 }), false);
  assert.equal(showMeVisible({ touched: false, idleMs: 19999 }), false);
  assert.equal(showMeVisible({ touched: false, idleMs: 20000 }), true);
  assert.equal(showMeVisible({ touched: true, idleMs: 0 }), true);
});

test("the result is dimmed when the sentence runs but the goal is not met, and only on sentence goals", () => {
  const dim = (step, goal, sentence, input) => {
    const r = grade(steps[step].goal, check, sentence, input ?? steps[step].input);
    return dimResult(steps[step].goal, r.shown, r.met);
  };
  assert.equal(dim(0, 0, 'allergens contains "eggs"'), true);
  assert.equal(dim(0, 0, 'allergens contains "milk"'), false);
  assert.equal(dim(0, 0, ""), false);
  assert.equal(dim(0, 0, 'allergens contains "milk'), false);
  assert.equal(dim(1, 0, 'allergens contains "nuts"'), true);
  assert.equal(dim(1, 0, nutFree), false);
  assert.equal(dim(2, 0, nutFree), false);
  assert.equal(dim(3, 0, nutFree), false);
});

test("step 2 opens on a batch with nuts and fails it", () => {
  assert.equal(steps[1].input, '{"allergens": ["milk", "eggs", "nuts"]}');
  const r = grade(steps[1].goal, check, nutFree, steps[1].input);
  assert.deepEqual([r.shown.passed, r.shown.cause, r.met], [false, "value", true]);
  assert.equal(goalMet(1, 0, 'allergens does not contain "eggs"'), false);
  assert.equal(say(1, 0, 'allergens does not contain "eggs"').text, "That checks for eggs. We're looking for nuts.");
});

test("the views mark the new value, and the segments rebuild each input exactly", () => {
  assert.deepEqual(steps[1].view.mark, { path: ["allergens"], index: 2 });
  assert.equal(steps[3].view, undefined);
  assert.equal(steps[0].view, undefined);
  assert.equal(steps[2].view, undefined);
  for (const s of steps.filter((x) => !x.collapse && x.goal.kind !== "policy" && x.goal.kind !== "requirement" && x.goal.kind !== "names")) assert.equal(jsonSegments(JSON.parse(s.input)).map((x) => x.text).join(""), s.input);
  const marked = (si) => jsonSegments(JSON.parse(steps[si].input)).filter((seg) => isAt(seg, steps[si].view.mark)).map((seg) => seg.text);
  assert.deepEqual(marked(1), ['"nuts"']);
});

test("steps 3 and 4 show a new batch, with nothing to remove and no delay", () => {
  for (const s of steps) {
    assert.equal(s.view?.before, undefined);
    assert.equal(s.view?.tag, undefined);
  }
  assert.equal(steps[2].input, '{"baked_by": "Sam"}');
  assert.equal(steps[2].goal.ask, "Here's another batch. Nobody recorded its allergens. What will ergo say?");
  assert.equal(steps[3].goal.ask, "Here's another batch. Its allergens were typed as text, not a list. What will ergo say?");
});

test("the predicted result for steps 3 and 4 is what ergo really says", () => {
  for (const si of [2, 3]) {
    const g = steps[si].goal;
    const r = grade(g, check, nutFree, steps[si].input);
    assert.deepEqual([r.shown.passed, r.shown.cause], [g.expect.passed, g.expect.cause], `step ${si + 1}`);
  }
});

test("a prediction goal is not met until the reader picks, then either answer counts", () => {
  for (const si of [2, 3]) {
    const g = steps[si].goal;
    const before = grade(g, check, nutFree, steps[si].input);
    assert.equal(before.met, false);
    assert.deepEqual(before.say, { kind: "predict", text: g.prompt });
    for (const choice of ["passed", "failed"]) {
      const r = grade(g, check, nutFree, steps[si].input, choice);
      assert.equal(r.met, true, `${si} ${choice}`);
      assert.equal(r.say.kind, "done");
      assert.equal(r.say.correct, choice === "failed");
    }
  }
});

test("the reveal says if the guess was right, then explains", () => {
  const g3 = steps[2].goal;
  const right = grade(g3, check, nutFree, steps[2].input, "failed").say.text;
  const wrong = grade(g3, check, nutFree, steps[2].input, "passed").say.text;
  assert.equal(right, "Right. Cause `absent`: nobody recorded the allergens, so ergo can't tell. When ergo isn't sure, the check fails.");
  assert.equal(wrong, "It fails. Cause `absent`: nobody recorded the allergens, so ergo can't tell. When ergo isn't sure, the check fails.");
  const g4 = steps[3].goal;
  assert.equal(grade(g4, check, nutFree, steps[3].input, "passed").say.text, "It fails. Cause `unusable`: the allergens are there, but not as a list, so ergo can't check them. It fails.");
  assert.match(grade(g4, check, nutFree, steps[3].input, "failed").say.text, /^Right\. Cause `unusable`/);
});

test("after the reveal the result follows edits to the input or the check", () => {
  const g3 = steps[2].goal;
  const edited = grade(g3, check, nutFree, '{"allergens": ["milk"]}', "failed");
  assert.equal(edited.say.text, "ergo says passed, cause `satisfied`.");
  assert.equal(edited.met, true);
  assert.equal(grade(g3, check, 'baked_by is "Sam"', steps[2].input, "failed").say.text, "ergo says passed, cause `satisfied`.");
  assert.equal(grade(g3, check, nutFree, "{", "failed").say.text, "The input isn't valid JSON yet. Check the commas, brackets and quotes.");
  assert.equal(judgePrediction(g3, "failed", { state: "unreadable" }).correct, null);
});

test("prediction goals are never dimmed and have no answer to show", () => {
  for (const si of [2, 3]) {
    const g = steps[si].goal;
    const r = grade(g, check, nutFree, steps[si].input, "failed");
    assert.equal(dimResult(g, r.shown, r.met), false);
    assert.equal(g.answer, undefined);
  }
});

test("restarting a step gives back its opening input and sentence, with no prediction or replay state", () => {
  const drafts = {
    1: { sentence: nutFree, input: "{}" },
    2: { sentence: "changed", input: "{}", choice: "passed", viewed: true, editing: true },
    4: { sentence: "bake.temp_c is between 175 and 200", input: "{}" },
  };
  assert.deepEqual(freshDraft(drafts, 0), { sentence: "", input: steps[0].input });
  assert.deepEqual(freshDraft(drafts, 1), { sentence: "", input: steps[1].input });
  assert.deepEqual(freshDraft(drafts, 2), { sentence: nutFree, input: steps[2].input });
  assert.deepEqual(freshDraft(drafts, 3), { sentence: "changed", input: steps[3].input });
  assert.deepEqual(freshDraft(drafts, 4), { sentence: "", input: steps[4].input });
  assert.deepEqual(freshDraft(drafts, 5), { sentence: "bake.temp_c is between 175 and 200", input: steps[5].input });
  assert.deepEqual(freshDraft(drafts, 6), { sentence: "", input: steps[6].input });
  assert.deepEqual(freshDraft(drafts, 7), { sentence: "", input: steps[7].input });
  assert.equal(Object.hasOwn(freshDraft(drafts, 2), "choice"), false);
});

test("a restarted step carries its sentence from the right earlier step", () => {
  assert.equal(carryFrom({ 1: { sentence: nutFree } }, 2), nutFree);
  assert.equal(carryFrom({ 1: { sentence: nutFree } }, 3), nutFree);
  assert.equal(carryFrom({}, 2), "");
  assert.equal(carryFrom({ 4: { sentence: "x" } }, 5), "x");
  assert.equal(carryFrom({ 1: { sentence: nutFree } }, 5), "");
  assert.equal(grade(steps[2].goal, check, freshDraft({ 1: { sentence: nutFree } }, 2).sentence, steps[2].input).shown.cause, "absent");
});

test("the screens have no chips or lead-in lines", () => {
  for (const s of steps) for (const g of [s.goal]) {
    assert.equal(g.chips, undefined);
    assert.equal(g.lead, undefined);
  }
});

test("the first coaching line of steps 1 and 2 shows the shape or the new words", () => {
  assert.match(steps[0].goal.start, /^A check is a field, then what it should do\. Start with `allergens`\.$/);
  assert.equal(steps[1].goal.start, "Same shape. You'll need `does not contain`.");
});

test("the intro is two short lines and an example", () => {
  assert.equal(intro.lines.length, 2);
  assert.equal(intro.credit, undefined);
});

test("progress dots: done before the step, current on it, todo after, all done at the end", () => {
  assert.equal(progressDots(0).length, 12);
  assert.deepEqual(progressDots(0), Array(12).fill("todo"));
  assert.deepEqual(progressDots(1), ["current", ...Array(11).fill("todo")]);
  assert.deepEqual(progressDots(3), ["done", "done", "current", ...Array(9).fill("todo")]);
  assert.deepEqual(progressDots(12), [...Array(11).fill("done"), "current"]);
  assert.deepEqual(progressDots(positions.length), Array(12).fill("done"));
});

test("only the dots of finished steps jump, and every dot names its step", () => {
  assert.equal(stepTitles.length, steps.length);
  const dots = dotTargets(3);
  assert.deepEqual(dots.map((d) => d.jump), [1, 2, null, ...Array(9).fill(null)]);
  assert.equal(dots[2].tip, "Step 3 · Nothing recorded");
  assert.deepEqual(dotTargets(0).map((d) => d.jump), Array(12).fill(null));
  assert.deepEqual(dotTargets(positions.length).map((d) => d.jump), steps.map((_, i) => i + 1));
});

test("after going back, the dots of steps already reached still jump forward", () => {
  const dots = dotTargets(2, 9);
  assert.deepEqual(dots.map((d) => d.state), ["done", "current", ...Array(7).fill("done"), ...Array(3).fill("todo")]);
  assert.deepEqual(dots.map((d) => d.jump), [1, null, 3, 4, 5, 6, 7, 8, 9, null, null, null]);
});

test("the furthest step reached is saved and comes back, but never behind the current one", () => {
  const drafts = { 1: { sentence: 'allergens does not contain "nuts"', input: "{}" } };
  assert.equal(serializeProgress(2, drafts, 9).furthest, 9);
  assert.equal(restoreProgress(serializeProgress(2, drafts, 9)).furthest, 9);
  assert.equal(restoreProgress({ pos: 2, furthest: 1, drafts: serializeProgress(2, drafts).drafts }).furthest, 2);
  assert.equal(restoreProgress({ pos: 2, furthest: "9", drafts: serializeProgress(2, drafts).drafts }).furthest, 2);
  assert.equal(restoreProgress({ pos: 2, furthest: 999, drafts: serializeProgress(2, drafts).drafts }).furthest, 2);
});

test("the result line puts the cause and the evidence together", () => {
  assert.deepEqual(resultLine(check(nutFree, { allergens: ["milk", "eggs", "nuts"] })), { cause: "value", rest: 'allergens = ["milk","eggs","nuts"]' });
  assert.deepEqual(resultLine(check(nutFree, {})), { cause: "absent", rest: "allergens = not in the input" });
  assert.equal(resultLine(check(nutFree, { allergens: ["milk"] })).cause, "satisfied");
});

const noHl = { exact: null, partial: [], item: null, valueLine: false, lists: [] };
const batch = { allergens: ["milk", "eggs", "nuts"], bake: { temp_c: 180, temp_f: 356 } };

test("the whole field matches a key and its value", () => {
  assert.deepEqual(fieldHighlight("allergens", batch), { exact: ["allergens"], partial: [], item: null, valueLine: false, lists: [] });
  assert.deepEqual(fieldHighlight("allergens contains", batch).exact, ["allergens"]);
});

test("part of a key is a hint, and only while it is being typed", () => {
  assert.deepEqual(fieldHighlight("allerg", batch), { exact: null, partial: [["allergens"]], item: null, valueLine: false, lists: [] });
  assert.deepEqual(fieldHighlight("a", batch).partial, [["allergens"]]);
  assert.deepEqual(fieldHighlight("allerg contains", batch), noHl);
});

test("a typo, an unknown field or a non-field word match nothing", () => {
  assert.deepEqual(fieldHighlight("alergens", batch), noHl);
  assert.deepEqual(fieldHighlight("alergens contains", batch), noHl);
  assert.deepEqual(fieldHighlight("milk contains", batch), noHl);
  assert.deepEqual(fieldHighlight("Allergens contains", batch), noHl);
  assert.deepEqual(fieldHighlight("", batch), noHl);
  assert.deepEqual(fieldHighlight('"allergens"', batch), noHl);
  assert.deepEqual(fieldHighlight("$params.x is 1", batch), noHl);
});

test("leading spaces are ignored", () => {
  assert.deepEqual(fieldHighlight("   allergens contains", batch).exact, ["allergens"]);
  assert.deepEqual(fieldHighlight("  allerg", batch).partial, [["allergens"]]);
});

test("dotted paths match step by step and the deepest matching key wins", () => {
  assert.deepEqual(fieldHighlight("bake.temp_c is 3", batch), { exact: ["bake", "temp_c"], partial: [], item: null, valueLine: true, lists: [] });
  assert.deepEqual(fieldHighlight("bake", batch).exact, ["bake"]);
  assert.deepEqual(fieldHighlight("bake.te", batch), { exact: ["bake"], partial: [["bake", "temp_c"], ["bake", "temp_f"]], item: null, valueLine: false, lists: [] });
  assert.deepEqual(fieldHighlight("bake.xyz is 1", batch), { exact: ["bake"], partial: [], item: null, valueLine: false, lists: [] });
  assert.deepEqual(fieldHighlight("allergens.x", batch).exact, ["allergens"]);
});

test("a quoted value in the list marks that item", () => {
  assert.deepEqual(fieldHighlight('allergens contains "milk"', batch).item, { path: ["allergens"], index: 0 });
  assert.deepEqual(fieldHighlight("allergens contains 'nuts'", batch).item, { path: ["allergens"], index: 2 });
  assert.deepEqual(fieldHighlight('allergens does not contain "eggs"', batch).item, { path: ["allergens"], index: 1 });
});

test("a quoted value that is not in the list, or not closed, marks no item", () => {
  assert.equal(fieldHighlight('allergens contains "soy"', batch).item, null);
  assert.equal(fieldHighlight('allergens contains "mil', batch).item, null);
  assert.equal(fieldHighlight('alergens contains "milk"', batch).item, null);
  assert.equal(fieldHighlight('allergens contains "milk"', { allergens: [] }).item, null);
});

test("a quoted value equal to a text field marks that value, and curly quotes count", () => {
  assert.deepEqual(fieldHighlight('allergens does not contain "nuts"', { allergens: "nuts" }).item, { path: ["allergens"], index: null });
  assert.deepEqual(fieldHighlight("allergens contains “milk”", batch).item, { path: ["allergens"], index: 0 });
  assert.deepEqual(fieldHighlight("allergens contains ‘eggs’", batch).item, { path: ["allergens"], index: 1 });
  assert.equal(fieldHighlight('baked_by is "Sam"', { baked_by: "Sam" }).item.index, null);
});

test("step 3 highlights nothing because there is no allergens key, step 4 highlights its value", () => {
  assert.deepEqual(fieldHighlight(nutFree, JSON.parse(steps[2].input)), noHl);
  const hl = fieldHighlight(nutFree, JSON.parse(steps[3].input));
  assert.deepEqual([hl.exact, hl.item], [["allergens"], { path: ["allergens"], index: null }]);
});

test("segments get the field, hint, value, item and mark classes", () => {
  const segs = jsonSegments(batch);
  const classes = (hl) => segs.map((s) => [s.text, segmentClasses(s, hl)]).filter(([, c]) => c.length);
  assert.deepEqual(classes(fieldHighlight("allerg", batch)), [['"allergens"', ["is-hint"]]]);
  const exact = classes(fieldHighlight("allergens", batch));
  assert.deepEqual(exact[0], ['"allergens"', ["is-field"]]);
  assert.equal(exact.length, 1);
  const item = classes(fieldHighlight('allergens contains "eggs"', batch)).filter(([, c]) => c.includes("is-item"));
  assert.deepEqual(item, [['"eggs"', ["is-valueline", "is-item"]]]);
  assert.deepEqual(classes(noHl), []);
  const nuts = classes(fieldHighlight('allergens contains "nuts"', batch)).filter(([, c]) => c.includes("is-item"));
  assert.deepEqual(nuts, [['"nuts"', ["is-valueline", "is-item"]]]);
  assert.deepEqual(classes(fieldHighlight("bake.temp_c", batch)), [['"temp_c"', ["is-field"]]]);
});

const line = (sentence, value = batch) => fieldHighlight(sentence, value).valueLine;
const lined = (sentence) => jsonSegments(batch).filter((s) => segmentClasses(s, fieldHighlight(sentence, batch)).includes("is-valueline")).map((s) => s.text).join("");

test("no phrase yet means no underline under the value", () => {
  assert.equal(line("allergens"), false);
  assert.equal(line("allergens "), false);
  assert.equal(line("allergens contain"), false);
});

test("part of a phrase shows only the key", () => {
  assert.equal(line("allergens cont"), false);
  assert.equal(line("allergens does not"), false);
  assert.equal(line("allergens is a"), true);
  assert.deepEqual(fieldHighlight("allergens cont", batch).exact, ["allergens"]);
});

test("a complete phrase underlines the whole value, once it is followed by a space or the end", () => {
  assert.equal(line("allergens contains"), true);
  assert.equal(line("allergens contains "), true);
  assert.equal(line('allergens contains "milk"'), true);
  assert.equal(line("allergens   contains"), true);
  assert.equal(lined("allergens contains"), '["milk", "eggs", "nuts"]');
  assert.equal(lined("allergens"), "");
  assert.equal(lined("bake.temp_c is 3"), "180");
});

test("a two-word or longer phrase counts when it is complete, and the longest phrase wins", () => {
  assert.equal(line("allergens does not contain"), true);
  assert.equal(line('allergens does not contain "nuts"'), true);
  assert.equal(line("allergens is not one of"), true);
  assert.equal(line("allergens is between 1 and 5"), true);
  assert.equal(line("allergens is"), true);
  assert.equal(line("allergens is a list"), true);
});

test("a phrase that takes nothing after it highlights the key only", () => {
  for (const s of ["allergens exists", "allergens does not exist", "allergens is empty", "allergens is not empty"]) {
    assert.equal(line(s), false, s);
    assert.deepEqual(fieldHighlight(s, batch).exact, ["allergens"]);
  }
});

test("the underline stays when the quoted value matches no item", () => {
  const hl = fieldHighlight('allergens contains "soy"', batch);
  assert.deepEqual([hl.valueLine, hl.item], [true, null]);
});

test("without the field there is no underline, and a phrase alone does nothing", () => {
  assert.equal(line("alergens contains"), false);
  assert.equal(line("contains"), false);
  assert.equal(line("milk contains"), false);
});

test("the underline shows on step 1 and not on step 3 whose batch has no allergens", () => {
  assert.equal(line('allergens contains "milk"', JSON.parse(steps[0].input)), true);
  assert.equal(line(nutFree, JSON.parse(steps[2].input)), false);
  assert.equal(line(nutFree, JSON.parse(steps[3].input)), true);
});

test("right after a complete phrase the coaching names the next part instead of correcting", () => {
  assert.deepEqual(say(0, 0, "allergens contains"), { kind: "next", text: 'Now say what it should contain: `"milk"`' });
  assert.deepEqual(say(0, 0, "allergens contains "), { kind: "next", text: 'Now say what it should contain: `"milk"`' });
  assert.deepEqual(say(1, 0, "allergens does not contain"), { kind: "next", text: 'Now the allergen: `"nuts"`' });
  assert.deepEqual(say(1, 0, "  allergens  does not contain "), { kind: "next", text: 'Now the allergen: `"nuts"`' });
});

test("an unquoted word after the phrase still gets the double quotes hint", () => {
  assert.equal(say(0, 0, "allergens contains milk").text, 'The text goes in double quotes, like `"milk"`.');
  assert.equal(say(1, 0, "allergens does not contain nuts").text, 'The text goes in double quotes, like `"nuts"`.');
});

test("the new item has no lime class of its own: it is found by position and flashes neutral", () => {
  const segs = jsonSegments({ allergens: ["milk", "eggs", "nuts"] });
  const mark = steps[1].view.mark;
  assert.deepEqual(segs.filter((s) => isAt(s, mark)).map((s) => s.text), ['"nuts"']);
  assert.equal(segs.some((s) => segmentClasses(s, fieldHighlight("", { allergens: [] })).length > 0), false);
  assert.equal(isAt(segs[0], null), false);
});

const sayN = (si, gi, sentence, input) => grade(steps[si].goal, check, sentence, input ?? steps[si].input).say;
const metN = (si, gi, sentence, input) => grade(steps[si].goal, check, sentence, input ?? steps[si].input).met;

const T5 = "bake.temp_c is between 175 and 200";
const T6 = `${T5} and bake.minutes is between 25 and 40`;

test("ergo reads the numbers as the steps say: both ends are in, the bounds fail as value", () => {
  const bake = (t, m = 32) => ({ bake: { temp_c: t, minutes: m } });
  for (const t of [175, 180, 200]) assert.equal(check(T5, bake(t)).passed, true, String(t));
  for (const t of [174, 201]) assert.deepEqual([check(T5, bake(t)).passed, check(T5, bake(t)).cause], [false, "value"]);
  assert.equal(check("bake.temp_c is between 200 and 175", bake(180)).message, "min above max");
  assert.equal(check("temp_c is between 175 and 200", bake(180)).cause, "absent");
  assert.equal(check(T5, { bake: { temp_c: "180" } }).cause, "unusable");
});

test("the first goal of step 5 is met by the answer, and not by wrong sentences", () => {
  assert.equal(metN(4, 0, T5), true);
  assert.equal(metN(4, 0, "bake.temp_c is between 175 and 199"), false);
  assert.equal(metN(4, 0, "bake.temp_c is between 176 and 200"), false);
  assert.equal(metN(4, 0, "bake.temp_c is between 170 and 200"), false);
  assert.equal(metN(4, 0, "bake.temp_c is between 175 and 210"), false);
  assert.equal(metN(4, 0, "temp_c is between 175 and 200"), false);
  assert.equal(metN(4, 0, "bake.temp_c is at least 175"), false);
  assert.equal(metN(4, 0, "bake.temp_c is between 200 and 175"), false);
});

test("step 5 coaching, state by state", () => {
  assert.deepEqual(sayN(4, 0, ""), { kind: "empty", text: "The temperature is inside `bake`. Join them with a dot: `bake.temp_c`." });
  assert.equal(sayN(4, 0, "bake").text, "Join them with a dot: `bake.temp_c`.");
  assert.equal(sayN(4, 0, "bake.").text, "Join them with a dot: `bake.temp_c`.");
  assert.equal(sayN(4, 0, "bake.temp_c").text, "Now say the range: `is between`");
  assert.equal(sayN(4, 0, "bake.temp_c is").text, "Now say the range: `is between`");
  assert.deepEqual(sayN(4, 0, "bake.temp_c is between"), { kind: "next", text: "Now the two numbers, with `and` between them." });
  assert.equal(sayN(4, 0, "bake.temp_c is between 175").text, "Now `and`, then the top of the range.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 175 and").text, "Now the top of the range.");
  assert.equal(sayN(4, 0, T5).kind, "done");
});

test("step 5 coaching for the wrong field and the wrong numbers", () => {
  assert.equal(sayN(4, 0, "temp_c").text, "That field is inside `bake`. Write `bake.temp_c`.");
  assert.equal(sayN(4, 0, "temp_c is between 175 and 200").text, "That field is inside `bake`. Write `bake.temp_c`.");
  assert.equal(sayN(4, 0, "bake.tmp_c is between 175 and 200").text, "ergo can't find that field in the input. The field is `bake.temp_c`.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 200 and 175").text, "The first number is bigger than the second. Put the smaller one first.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 176 and 200").text, "The lowest allowed is 175, and this starts at 176.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 175 and 199").text, "The highest allowed is 200, and this stops at 199.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 170 and 200").text, "That lets 174 through. The low end is 175.");
  assert.equal(sayN(4, 0, "bake.temp_c is between 175 and 210").text, "That lets 201 through. The top is 200.");
});

test("step 6 starts from the step 5 sentence, whose result on the shown batch is a pass", () => {
  assert.equal(steps[5].carry, true);
  const r = grade(steps[5].goal, check, T5, steps[5].input);
  assert.deepEqual([r.shown.passed, r.met], [true, false]);
  assert.equal(r.say.text, "Nothing checks the minutes yet. Add them with `and`.");
});

test("step 6 is met by the answer, and the shown batch fails on the minutes", () => {
  assert.equal(metN(5, 0, T6), true);
  const r = grade(steps[5].goal, check, T6, steps[5].input);
  assert.deepEqual([r.shown.passed, r.shown.cause], [false, "value"]);
  assert.deepEqual(r.shown.failed, [{ assertion: "bake.minutes is between 25 and 40", cause: "value" }]);
  assert.deepEqual(resultLine(r.shown), { cause: "value", rest: "bake.minutes is between 25 and 40" });
  assert.equal(r.say.text, "Both parts must pass. ergo tells you which one didn't.");
});

test("step 6 is not met by sentences that let a batch through, or leave a part out", () => {
  assert.equal(metN(5, 0, T5), false);
  assert.equal(metN(5, 0, `${T5} and bake.minutes is between 25 and 50`), false);
  assert.equal(metN(5, 0, `${T5} and bake.minutes is between 20 and 40`), false);
  assert.equal(metN(5, 0, `${T5} and bake.minutes is between 26 and 40`), false);
  assert.equal(metN(5, 0, `${T5} and bake.minutes is between 25 and 39`), false);
  assert.equal(metN(5, 0, "bake.minutes is between 25 and 40"), false);
  assert.equal(metN(5, 0, `bake.minutes is between 25 and 40 and ${T5}`), true);
});

test("step 6 coaching, state by state", () => {
  assert.equal(sayN(5, 0, `${T5} and`).text, "Now the minutes, inside `bake` too: `bake.minutes`.");
  assert.equal(sayN(5, 0, `${T5} and bake`).text, "Now the minutes, inside `bake` too: `bake.minutes`.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes`).text, "Now say the range: `is between`");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between`).text, "Now the two numbers, with `and` between them.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between 25`).text, "Now `and`, then the top of the range.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between 25 and`).text, "Now the top of the range.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between 25 and 50`).text, "That lets 41 minutes through. The most is 40.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between 20 and 40`).text, "That lets 24 minutes through. The least is 25.");
  assert.equal(sayN(5, 0, "bake.minutes is between 25 and 40").text, "The temperature must still be between 175 and 200 °C.");
  assert.equal(sayN(5, 0, `${T5} and bake.minutes is between 40 and 25`).text, "A first number is bigger than the second. Put the smaller one first.");
  assert.equal(sayN(5, 0, "").kind, "empty");
});

test("the result line shows the failed sentences for an and, and the evidence otherwise", () => {
  const both = check(T6, { bake: { temp_c: 210, minutes: 45 } });
  assert.equal(resultLine(both).rest, "bake.temp_c is between 175 and 200 · bake.minutes is between 25 and 40");
  const one = check(T5, { bake: { temp_c: 210 } });
  assert.deepEqual(resultLine(one), { cause: "value", rest: "bake.temp_c = 210" });
  assert.equal(resultLine(check(T6, { bake: { temp_c: 180, minutes: 32 } })).rest, "bake.minutes = 32 · bake.temp_c = 180");
});

test("ergo reads every and some as the steps say", () => {
  const f = { name: "flour", certified: true };
  const b = { name: "butter", certified: true };
  const a = { name: "Ana", verdict: "approved" };
  const r = { name: "Bo", verdict: "rejected" };
  const A = "every ingredients.certified is true";
  const B = 'some tasters.verdict is "approved"';
  assert.equal(check(A, { ingredients: [f, b] }).passed, true);
  assert.deepEqual([check(A, { ingredients: [f, { ...b, certified: false }] }).passed, check(A, { ingredients: [f, { ...b, certified: false }] }).cause], [false, "value"]);
  assert.equal(check(A, { ingredients: [f, { name: "butter" }] }).cause, "absent");
  assert.equal(check(B, { tasters: [a, r] }).passed, true);
  assert.equal(check(B, { tasters: [r, r] }).passed, false);
  assert.equal(check(B, { tasters: [a, { ...r, verdict: "approved" }] }).passed, true);
  assert.equal(check('every tasters.verdict is "approved"', { tasters: [a, r] }).passed, false);
});

test("step 7 goal A is met by the answer and not by wrong sentences", () => {
  assert.equal(metN(6, 0, "every ingredients.certified is true"), true);
  assert.equal(metN(6, 0, "some ingredients.certified is true"), false);
  assert.equal(metN(6, 0, "ingredients.certified is true"), false);
  assert.equal(metN(6, 0, "every ingredient.certified is true"), false);
  assert.equal(metN(6, 0, 'every ingredients.certified is "true"'), false);
  assert.equal(metN(6, 0, "every ingredients.certified exists"), false);
});

test("step 7 goal A coaching, state by state", () => {
  assert.deepEqual(sayN(6, 0, ""), { kind: "empty", text: "Start with `every`, then the path through the list: `every ingredients.certified`." });
  assert.equal(sayN(6, 0, "every").text, "Now the path through the list: `ingredients.certified`.");
  assert.equal(sayN(6, 0, "every ingred").text, "The list is `ingredients`. The certificate is inside each item: `ingredients.certified`.");
  assert.equal(sayN(6, 0, "every ingredients").text, "The list is `ingredients`. The certificate is inside each item: `ingredients.certified`.");
  assert.equal(sayN(6, 0, "every ingredients.certified").text, "Now what it should be: `is true`");
  assert.deepEqual(sayN(6, 0, "every ingredients.certified is"), { kind: "next", text: "Now the value: `true`" });
  assert.equal(sayN(6, 0, "some ingredients.certified is true").text, "That passes as soon as one ingredient is certified. We need every one: use `every`.");
  assert.equal(sayN(6, 0, "ingredients.certified is true").text, "A list needs `every` in front, to look at each item.");
  assert.equal(sayN(6, 0, "every ingredient.certified is true").text, "ergo can't find that list in the input. The path is `ingredients.certified`.");
  assert.equal(sayN(6, 0, "every ingredients.certified is true").kind, "done");
});

test("step 7 goal B is met by the answer and not by wrong sentences", () => {
  assert.equal(metN(7, 0, 'some tasters.verdict is "approved"'), true);
  assert.equal(metN(7, 0, 'every tasters.verdict is "approved"'), false);
  assert.equal(metN(7, 0, 'some tasters.verdict is "rejected"'), false);
  assert.equal(metN(7, 0, 'some tasters.verdict is not "approved"'), false);
  assert.equal(metN(7, 0, "some tasters.verdict is approved"), false);
  assert.equal(metN(7, 0, ""), false);
});

test("step 7 goal B coaching, state by state", () => {
  assert.deepEqual(sayN(7, 0, ""), { kind: "empty", text: "Same idea, but one is enough: `some` means at least one. Start with `some`, then `tasters.verdict`." });
  assert.equal(sayN(7, 0, "some").text, "Now the path through the list: `tasters.verdict`.");
  assert.equal(sayN(7, 0, "some tasters").text, "The list is `tasters`. The verdict is inside each taster: `tasters.verdict`.");
  assert.equal(sayN(7, 0, "some tasters.verdict").text, 'Now what it should be: `is "approved"`');
  assert.deepEqual(sayN(7, 0, "some tasters.verdict is"), { kind: "next", text: 'Now the value, in double quotes: `"approved"`' });
  assert.equal(sayN(7, 0, 'some tasters.verdict is "approved').text, "A quote isn't closed. Add `\"` after approved.");
  assert.equal(sayN(7, 0, "some tasters.verdict is approved").text, 'The text goes in double quotes, like `"approved"`.');
  assert.equal(sayN(7, 0, 'every tasters.verdict is "approved"').text, "That needs every taster to approve. One is enough: use `some`.");
  assert.equal(sayN(7, 0, 'some tasters.verdict is "rejected"').text, "That passes even when nobody approves. It should fail then.");
  assert.equal(sayN(7, 0, "every").text, "Start with `some`: one taster is enough. Then `tasters.verdict`.".replace("Start with `some`: one taster is enough. Then `tasters.verdict`.", "Start with `some`: one taster is enough. Then `tasters.verdict`."));
  assert.equal(sayN(7, 0, 'some tasters.verdict is "approved"').kind, "done");
});

test("meeting step 7 changes nothing by itself: step 8 is its own screen, reached with next", () => {
  assert.equal(lib.nextGoalPosition, undefined);
  assert.equal(lib.handover, undefined);
  const g7 = grade(steps[6].goal, check, "every ingredients.certified is true", steps[6].input);
  assert.deepEqual([g7.met, g7.say.kind], [true, "done"]);
  assert.deepEqual(positions[7], { step: 6 });
  assert.deepEqual(positions[8], { step: 7 });
  assert.equal(steps[7].input, steps[6].input);
  assert.equal(steps[7].carry, undefined);
  assert.equal(firstPositionOf(6), 7);
  assert.equal(firstPositionOf(7), 8);
});

const pretty = JSON.parse(steps[6].input);

test("a nested object or a list of objects is printed one field per line", () => {
  assert.equal(isPretty(JSON.parse(steps[4].input)), true);
  assert.equal(isPretty(pretty), true);
  for (const si of [0, 1, 2, 3]) assert.equal(isPretty(JSON.parse(steps[si].input)), false);
  assert.equal(steps[4].input, '{\n  "bake": {\n    "temp_c": 180,\n    "minutes": 32\n  }\n}');
  assert.equal(steps[6].input.split("\n").length, 10);
  assert.equal(jsonSegments(pretty).map((s) => s.text).join(""), steps[6].input);
  assert.deepEqual(JSON.parse(steps[6].input), pretty);
});

test("every step's input is the layout the segments print", () => {
  for (const s of steps.filter((x) => !x.collapse && x.goal.kind !== "policy" && x.goal.kind !== "requirement" && x.goal.kind !== "names")) assert.equal(jsonSegments(JSON.parse(s.input)).map((x) => x.text).join(""), s.input);
});

test("a dotted path highlights the nested key on the pretty layout, and the underline follows the phrase", () => {
  const bake = JSON.parse(steps[4].input);
  const segs = jsonSegments(bake);
  const classes = (sentence) => segs.map((s) => [s.text, segmentClasses(s, fieldHighlight(sentence, bake))]).filter(([, c]) => c.length);
  assert.deepEqual(classes("bake.temp_c"), [['"temp_c"', ["is-field"]]]);
  assert.deepEqual(classes("bake.temp_c is between"), [['"temp_c"', ["is-field"]], ["180", ["is-valueline"]]]);
  assert.deepEqual(classes("bake.te"), [['"bake"', ["is-field"]], ['"temp_c"', ["is-hint"]]]);
  assert.deepEqual(classes("temp_c"), []);
});

test("a path through a list highlights the list key and the key in every item", () => {
  const segs = jsonSegments(pretty);
  const hl = fieldHighlight("every ingredients.certified", pretty);
  assert.deepEqual([hl.exact, hl.lists], [["ingredients", "*", "certified"], [["ingredients"]]]);
  const marked = segs.filter((s) => segmentClasses(s, hl).includes("is-field")).map((s) => s.text);
  assert.deepEqual(marked, ['"ingredients"', '"certified"', '"certified"']);
});

test("the underline covers the value in every item once the phrase is typed", () => {
  const segs = jsonSegments(pretty);
  const lined = (sentence) => segs.filter((s) => segmentClasses(s, fieldHighlight(sentence, pretty)).includes("is-valueline")).map((s) => s.text);
  assert.deepEqual(lined("every ingredients.certified is true"), ["true", "true"]);
  assert.deepEqual(lined("every ingredients.certified"), []);
  assert.deepEqual(lined("every ingredients.certified exists"), []);
});

test("a quoted value marks every matching item in a list of objects", () => {
  const segs = jsonSegments(pretty);
  const items = (sentence, value = pretty) => jsonSegments(value).filter((s) => segmentClasses(s, fieldHighlight(sentence, value)).includes("is-item")).map((s) => s.text);
  assert.deepEqual(items('some tasters.verdict is "approved"'), ['"approved"']);
  assert.deepEqual(items('some tasters.verdict is "rejected"'), ['"rejected"']);
  assert.deepEqual(items('some tasters.verdict is "soy"'), []);
  const both = { ...pretty, tasters: [{ name: "Ana", verdict: "approved" }, { name: "Bo", verdict: "approved" }] };
  assert.deepEqual(items('some tasters.verdict is "approved"', both), ['"approved"', '"approved"']);
  assert.equal(segs.length > 0, true);
});

test("a leading every or some is skipped when finding the field, and partial words show a hint", () => {
  assert.deepEqual(fieldHighlight("every ingredients", pretty).exact, ["ingredients"]);
  assert.deepEqual(fieldHighlight("some tasters.ver", pretty).partial, [["tasters", "*", "verdict"]]);
  assert.deepEqual(fieldHighlight("every", pretty), noHl);
  assert.deepEqual(fieldHighlight("everything", pretty).exact, null);
  assert.deepEqual(fieldHighlight("every flour.certified", pretty), noHl);
});

test("there are twelve steps and thirteen screens", () => {
  assert.equal(steps.length, 12);
  assert.equal(positions.length, 13);
});

const k = (key, mods = {}) => ({ key, ...mods });

test("Enter in the sentence field goes next when the goal is met, and does nothing when it isn't", () => {
  assert.equal(keyAction(k("Enter"), "sentence", true, "sentence"), "next");
  assert.equal(keyAction(k("Enter"), "sentence", false, "sentence"), "swallow");
  assert.equal(keyAction(k("Enter"), "sentence", false, "predict"), "swallow");
});

test("Escape in a text field blurs it, and Enter in the input editor is left alone", () => {
  assert.equal(keyAction(k("Escape"), "sentence", false, "sentence"), "blur");
  assert.equal(keyAction(k("Escape"), "editor", false, "sentence"), "blur");
  assert.equal(keyAction(k("Enter"), "editor", true, "sentence"), null);
});

test("the arrow keys only move between steps outside a text field", () => {
  assert.equal(keyAction(k("ArrowRight"), "body", true, "sentence"), "next");
  assert.equal(keyAction(k("ArrowRight"), "body", false, "sentence"), null);
  assert.equal(keyAction(k("ArrowLeft"), "body", false, "sentence"), "back");
  assert.equal(keyAction(k("ArrowLeft"), "body", true, "predict"), "back");
  for (const target of ["sentence", "editor", "menu"]) {
    assert.equal(keyAction(k("ArrowRight"), target, true, "sentence"), null, target);
    assert.equal(keyAction(k("ArrowLeft"), target, true, "sentence"), null, target);
  }
});

test("there is no back on the intro, and next works from the intro and the end", () => {
  assert.equal(keyAction(k("ArrowLeft"), "body", true, "intro"), null);
  assert.equal(keyAction(k("ArrowRight"), "body", true, "intro"), "next");
  assert.equal(keyAction(k("ArrowRight"), "body", true, "end"), "next");
  assert.equal(keyAction(k("ArrowLeft"), "body", true, "end"), "back");
});

test("p and f pick on prediction steps outside a text field only", () => {
  assert.equal(keyAction(k("p"), "body", false, "predict"), "pick-passed");
  assert.equal(keyAction(k("f"), "body", false, "predict"), "pick-failed");
  assert.equal(keyAction(k("p"), "sentence", false, "predict"), null);
  assert.equal(keyAction(k("f"), "editor", false, "predict"), null);
  assert.equal(keyAction(k("p"), "body", false, "sentence"), null);
  assert.equal(keyAction(k("f"), "body", false, "intro"), null);
});

test("key presses with Ctrl, Cmd or Alt are ignored", () => {
  for (const mods of [{ ctrl: true }, { meta: true }, { alt: true }]) {
    assert.equal(keyAction(k("Enter", mods), "sentence", true, "sentence"), null);
    assert.equal(keyAction(k("ArrowRight", mods), "body", true, "sentence"), null);
    assert.equal(keyAction(k("p", mods), "body", false, "predict"), null);
    assert.equal(keyAction(k("Escape", mods), "sentence", true, "sentence"), null);
  }
});

test("the menu keeps its own keys, and other keys do nothing", () => {
  assert.equal(keyAction(k("Escape"), "menu", true, "sentence"), null);
  assert.equal(keyAction(k("ArrowDown"), "menu", true, "sentence"), null);
  assert.equal(keyAction(k("a"), "body", true, "sentence"), null);
});

test("the goal kind at each screen picks the focus and the shortcuts", () => {
  assert.deepEqual(positions.map((_, i) => goalKindAt(i)), ["intro", "sentence", "sentence", "predict", "predict", "sentence", "sentence", "sentence", "sentence", "names", "requirement", "subjects", "policy"]);
  assert.equal(goalKindAt(positions.length), "end");
});

test("Enter goes to the next step from the body when the goal is met, and from nowhere else but the sentence field", () => {
  assert.equal(keyAction(k("Enter"), "body", true, "sentence"), "next");
  assert.equal(keyAction(k("Enter"), "body", false, "sentence"), null);
  assert.equal(keyAction(k("Enter"), "body", true, "predict"), "next");
  assert.equal(keyAction(k("Enter"), "body", true, "intro"), "next");
});

test("Enter in the input editor inserts a newline, and a focused button keeps its own Enter", () => {
  for (const met of [true, false]) {
    assert.equal(keyAction(k("Enter"), "editor", met, "sentence"), null);
    assert.equal(keyAction(k("Enter"), "next", met, "sentence"), null);
    assert.equal(keyAction(k("Enter"), "button", met, "sentence"), null);
    assert.equal(keyAction(k("Enter"), "menu", met, "sentence"), null);
  }
});

test("the arrow keys and the pick keys also work with focus on a button", () => {
  assert.equal(keyAction(k("ArrowRight"), "next", true, "sentence"), "next");
  assert.equal(keyAction(k("ArrowLeft"), "button", true, "predict"), "back");
  assert.equal(keyAction(k("p"), "button", false, "predict"), "pick-passed");
  assert.equal(keyAction(k("Enter", { ctrl: true }), "body", true, "sentence"), null);
});

test("Enter pressed before ergo has answered is deferred, not dropped, and a met goal still goes next", () => {
  assert.equal(keyAction(k("Enter"), "sentence", false, "sentence", true), "defer");
  assert.equal(keyAction(k("Enter"), "sentence", false, "sentence", false), "swallow");
  assert.equal(keyAction(k("Enter"), "sentence", true, "sentence", true), "next");
  assert.equal(keyAction(k("Enter"), "sentence", false, "predict", true), "defer");
  assert.equal(keyAction(k("Enter"), "editor", false, "sentence", true), null);
  assert.equal(keyAction(k("Enter", { ctrl: true }), "sentence", false, "sentence", true), null);
});

test("the step 6 result is not dimmed once the goal is met, even though it failed, and is dimmed before", () => {
  const g = steps[5].goal;
  const done = grade(g, check, T6, steps[5].input);
  assert.deepEqual([done.shown.passed, done.met, dimResult(g, done.shown, done.met)], [false, true, false]);
  const carried = grade(g, check, T5, steps[5].input);
  assert.deepEqual([carried.shown.passed, carried.met, dimResult(g, carried.shown, carried.met)], [true, false, true]);
  const wrong = grade(g, check, `${T5} and bake.minutes is between 25 and 50`, steps[5].input);
  assert.equal(dimResult(g, wrong.shown, wrong.met), true);
});

test("sentences joined with and are split apart, but the and of between is not", () => {
  assert.deepEqual(splitSentences(T5), [T5]);
  assert.deepEqual(splitSentences(T6), [T5, "bake.minutes is between 25 and 40"]);
  assert.deepEqual(splitSentences(`${T5} and`), [`${T5} and`]);
  assert.deepEqual(splitSentences(`${T5} and `), [T5]);
  assert.deepEqual(splitSentences("a is 1 and b is 2 and c exists"), ["a is 1", "b is 2", "c exists"]);
  assert.deepEqual(splitSentences("a is between 1 and 2 and b is 3"), ["a is between 1 and 2", "b is 3"]);
});

test("every sentence of an and gets the field, the value underline and the hint", () => {
  const bake = JSON.parse(steps[5].input);
  const segs = jsonSegments(bake);
  const classes = (sentence) => segs.map((s) => [s.text, segmentClasses(s, fieldHighlights(sentence, bake))]).filter(([, c]) => c.length);
  assert.deepEqual(classes(T6), [['"temp_c"', ["is-field"]], ["180", ["is-valueline"]], ['"minutes"', ["is-field"]], ["45", ["is-valueline"]]]);
  assert.deepEqual(classes(`${T5} and bake.min`), [['"bake"', ["is-field"]], ['"temp_c"', ["is-field"]], ["180", ["is-valueline"]], ['"minutes"', ["is-hint"]]]);
  assert.deepEqual(classes(`${T5} and bake.minutes`), [['"temp_c"', ["is-field"]], ["180", ["is-valueline"]], ['"minutes"', ["is-field"]]]);
  assert.deepEqual(classes(`${T5} and bakx.min`), [['"temp_c"', ["is-field"]], ["180", ["is-valueline"]]]);
  assert.deepEqual(classes(T5), [['"temp_c"', ["is-field"]], ["180", ["is-valueline"]]]);
});

test("an unquoted literal marks every matching item the same way a quoted one does", () => {
  const segs = jsonSegments(pretty);
  const hl = fieldHighlights("every ingredients.certified is true", pretty);
  const marked = segs.filter((s) => segmentClasses(s, hl).includes("is-item"));
  assert.deepEqual(marked.map((s) => s.text), ["true", "true"]);
  const lined = segs.filter((s) => segmentClasses(s, hl).includes("is-valueline"));
  assert.deepEqual(lined.map((s) => s.text), ["true", "true"]);
  assert.deepEqual(marked.map((s) => segmentClasses(s, hl)), [["is-valueline", "is-item"], ["is-valueline", "is-item"]]);
  const mixed = { ...pretty, ingredients: [{ name: "flour", certified: true }, { name: "butter", certified: false }] };
  assert.deepEqual(jsonSegments(mixed).filter((s) => segmentClasses(s, fieldHighlights("every ingredients.certified is true", mixed)).includes("is-item")).map((s) => s.text), ["true"]);
  assert.deepEqual(jsonSegments(mixed).filter((s) => segmentClasses(s, fieldHighlights("some ingredients.certified is false", mixed)).includes("is-item")).map((s) => s.text), ["false"]);
});

test("numbers and null mark matching values, and a literal that matches nothing marks no item", () => {
  const bake = JSON.parse(steps[4].input);
  const items = (sentence, value = bake) => jsonSegments(value).filter((s) => segmentClasses(s, fieldHighlights(sentence, value)).includes("is-item")).map((s) => s.text);
  assert.deepEqual(items("bake.temp_c is 180"), ["180"]);
  assert.deepEqual(items("bake.temp_c is 181"), []);
  assert.deepEqual(items("bake.temp_c is null", { bake: { temp_c: null } }), ["null"]);
  assert.deepEqual(items('allergens contains "milk"', { allergens: ["milk", "eggs"] }), ['"milk"']);
});

test("a deferred Enter acts only on the evaluation pending when it was pressed", () => {
  const gate = createEnterGate();
  gate.press();
  assert.equal(gate.evaluated(true), true);
  gate.press();
  assert.equal(gate.evaluated(false), false);
  assert.equal(gate.evaluated(true), false);
});

test("an Enter that found the goal unmet is forgotten, and a later success does not fire it", () => {
  const gate = createEnterGate();
  gate.typed();
  gate.press();
  assert.equal(gate.evaluated(false), false);
  gate.typed();
  assert.equal(gate.evaluated(true), false);
  assert.equal(gate.evaluated(true), false);
});

test("typing after Enter drops the request, and a step change resets it", () => {
  const gate = createEnterGate();
  gate.press();
  gate.typed();
  assert.equal(gate.evaluated(true), false);
  gate.press();
  gate.reset();
  assert.equal(gate.evaluated(true), false);
  assert.equal(gate.evaluated(true), false);
});

test("an evaluation with no Enter pressed never acts", () => {
  const gate = createEnterGate();
  assert.equal(gate.evaluated(true), false);
  gate.typed();
  assert.equal(gate.evaluated(true), false);
});


test("saved progress keeps every step's sentence, input and prediction", () => {
  const drafts = {
    0: { sentence: 'allergens contains "milk"', input: steps[0].input },
    1: { sentence: nutFree, input: steps[1].input },
    2: { sentence: nutFree, input: steps[2].input, choice: "failed" },
    3: { sentence: nutFree, input: '{"allergens": "milk"}', choice: "passed", editing: true },
    4: { sentence: T5, input: steps[4].input },
    5: { sentence: T6, input: steps[5].input },
    6: { sentence: "every ingredients.certified is true", input: steps[6].input },
    7: { sentence: 'some tasters.verdict is "approved"', input: steps[7].input },
  };
  const back = restoreProgress(JSON.parse(JSON.stringify(serializeProgress(8, drafts))));
  assert.equal(back.pos, 8);
  for (const [k, d] of Object.entries(drafts)) {
    assert.equal(back.drafts[k].sentence, d.sentence, k);
    assert.equal(back.drafts[k].input, d.input);
    assert.equal(back.drafts[k].choice, d.choice);
    assert.equal(back.drafts[k].editing, d.editing);
    assert.equal(back.drafts[k].viewed, true);
  }
});

test("restored steps 6, 7 and 8 are still passable with their sentences as typed", () => {
  const drafts = { 4: { sentence: T5, input: steps[4].input }, 5: { sentence: T6, input: steps[5].input }, 6: { sentence: "every ingredients.certified is true", input: steps[6].input }, 7: { sentence: 'some tasters.verdict is "approved"', input: steps[7].input } };
  const back = restoreProgress(serializeProgress(8, drafts));
  for (const si of [5, 6, 7]) assert.equal(grade(steps[si].goal, check, back.drafts[si].sentence, back.drafts[si].input).met, true, String(si));
});

test("an old save with step 7 goal B in the same step maps to step 8, and does not crash", () => {
  const old = {
    pos: 8,
    drafts: {
      1: { sentences: [nutFree, ""], input: steps[1].input },
      4: { sentences: [T5, ""], input: steps[4].input },
      5: { sentences: [T6, ""], input: steps[5].input },
      6: { sentences: ["every ingredients.certified is true", 'some tasters.verdict is "approved"'], input: steps[6].input },
    },
  };
  const back = restoreProgress(old);
  assert.equal(back.pos, 8);
  assert.equal(back.drafts[6].sentence, "every ingredients.certified is true");
  assert.equal(back.drafts[7].sentence, 'some tasters.verdict is "approved"');
  assert.equal(back.drafts[7].input, steps[6].input);
  assert.equal(grade(steps[7].goal, check, back.drafts[7].sentence, back.drafts[7].input).met, true);
  const empty = restoreProgress({ pos: 7, drafts: { 6: { sentences: ["every ingredients.certified is true", ""], input: steps[6].input } } });
  assert.equal(empty.pos, 7);
  assert.equal(empty.drafts[7], undefined);
  assert.deepEqual(restoreProgress({ pos: 8, drafts: { 6: { sentences: [], input: "{}" }, 7: { sentences: 5, input: "{}" } } }).drafts, {});
});

test("restoring ignores what it can't read, and starts at the intro when an earlier answer is missing", () => {
  assert.deepEqual(restoreProgress(null), { drafts: {}, pos: 0, furthest: 0 });
  assert.deepEqual(restoreProgress({ pos: 3, s2: nutFree }), { drafts: {}, pos: 0, furthest: 0 });
  const bad = restoreProgress({ pos: 3, drafts: { 1: { sentence: nutFree, input: "{}" }, 2: { sentence: 5, input: "{}" }, 99: { sentence: "a", input: "{}" }, 3: { sentence: "a", input: 5 }, 4: { sentence: "a", input: "{}", choice: "maybe" } } });
  assert.deepEqual(Object.keys(bad.drafts).sort(), ["1", "4"]);
  assert.equal(bad.drafts[4].choice, undefined);
  assert.equal(bad.pos, 3);
  assert.equal(restoreProgress({ pos: 6, drafts: { 1: { sentence: nutFree, input: "{}" } } }).pos, 0);
});

test("each line of the pretty input is its own block with its own indent", () => {
  const lines = layoutLines(jsonSegments(JSON.parse(steps[6].input)));
  assert.deepEqual(lines.map((l) => l.indent), [0, 2, 4, 4, 2, 2, 4, 4, 2, 0]);
  assert.equal(lines.map((l) => " ".repeat(l.indent) + l.parts.map((p) => p.text).join("")).join("\n"), steps[6].input);
  assert.equal(lines[3].parts.map((p) => p.text).join(""), '{"name": "butter", "certified": true}');
});

test("a one line input is one block, and every part points back to its segment", () => {
  for (const si of [0, 1, 2, 3]) {
    const segs = jsonSegments(JSON.parse(steps[si].input));
    const lines = layoutLines(segs);
    assert.equal(lines.length, 1);
    assert.equal(lines[0].indent, 0);
    assert.equal(lines[0].parts.map((p) => p.text).join(""), steps[si].input);
    for (const p of lines[0].parts) assert.equal(segs[p.index].text.includes(p.text), true);
  }
  const bake = layoutLines(jsonSegments(JSON.parse(steps[4].input)));
  assert.deepEqual(bake.map((l) => l.indent), [0, 2, 4, 4, 2, 0]);
});

const run = makeRunner((doc) => ergo.evaluate(doc));
const batch9 = JSON.parse(steps[8].input);
const batch10 = JSON.parse(steps[9].input);
const key = (heading) => slug(heading);

test("the batches in step 11 are exactly the bakery example's file", () => {
  const file = JSON.parse(readFileSync(new URL("../../../../examples/baking/batches.json", import.meta.url), "utf8"));
  assert.deepEqual(bakeryBatches, file);
  assert.deepEqual(JSON.parse(steps[10].input), file);
});

test("step 9 runs three named checks on one batch and all of them pass", () => {
  const report = run(batch9, tutorialPolicy({ name: "nut_free" }));
  assert.deepEqual(lineResults(report, "nut_free").map((l) => [l.name, l.passed]), [["nut_free", true], ["temp_ok", true], ["time_ok", true]]);
  assert.equal(verdict(report, "safe_to_sell"), "met");
});

test("ergo takes almost any check name, but the tutorial asks for lowercase letters, digits and _", () => {
  for (const name of ["nut free", "Nut_Free", "nut-free", "nut_free"]) {
    const report = run(batch9, tutorialPolicy({ name }));
    assert.equal(lineResults(report, name)[0].passed, true, name);
  }
  assert.equal(nameProblem("nut_free"), null);
  assert.equal(nameProblem("nut_free_2"), null);
  assert.equal(nameProblem("123"), null);
  assert.equal(nameProblem("n"), null);
});

test("step 9 name coaching, state by state", () => {
  assert.deepEqual(nameCoach(""), { kind: "wrong", text: "A short name, no spaces. For example `nut_free`.", met: false });
  assert.equal(nameCoach("nut free").text, "No spaces. Use `_` instead.");
  assert.equal(nameCoach("nut ").text, "No spaces. Use `_` instead.");
  assert.equal(nameCoach("temp_ok").text, "That name is taken.");
  assert.equal(nameCoach("time_ok").text, "That name is taken.");
  assert.equal(nameCoach("Nut_free").text, "Use lowercase letters only.");
  assert.equal(nameCoach("nut-free").text, "Use only lowercase letters, digits and `_`.");
  assert.equal(nameCoach("nut.free").text, "Use only lowercase letters, digits and `_`.");
  assert.equal(nameCoach("$nut").text, "Names can't start with `$`. ergo keeps that for its own checks.");
  assert.deepEqual(nameCoach("nut_free"), { kind: "done", text: "Every check has a name now. The report uses it on each row.", met: true });
  assert.equal(nameCoach("nuts_2").met, true);
});

test("step 9 is met by a good name and not by a bad or taken one", () => {
  for (const good of ["nut_free", "nuts", "a1"]) assert.equal(nameCoach(good).met, true, good);
  for (const bad of ["", " ", "temp_ok", "time_ok", "Nut", "nut free", "nut-free", "ü", "$x"]) assert.equal(nameCoach(bad).met, false, JSON.stringify(bad));
});

test("step 10: with the time check failing, the requirement is not met and time_ok is the row to blame", () => {
  const report = run(batch10, tutorialPolicy({ name: "nut_free", heading: "Safe to sell" }));
  assert.equal(verdict(report, "safe_to_sell"), "not_met");
  assert.equal(verdictWord(verdict(report, "safe_to_sell")), "not met");
  assert.equal(report.requirements.safe_to_sell.description, "Safe to sell");
  const results = lineResults(report, "nut_free");
  assert.deepEqual(results.map((l) => [l.name, l.passed, l.cause]), [["nut_free", true, "satisfied"], ["temp_ok", true, "satisfied"], ["time_ok", false, "value"]]);
});

test("step 10 coaching and grading come from the report", () => {
  const report = run(batch10, tutorialPolicy({ name: "nut_free", heading: "Safe to sell" }));
  const results = lineResults(report, "nut_free");
  assert.deepEqual(requirementCoach({ heading: "", tapped: "" }, results), { kind: "empty", text: "Write a heading for the requirement: what is it all for?", met: false });
  assert.equal(requirementCoach({ heading: "  ", tapped: "time_ok" }, results).met, false);
  assert.deepEqual(requirementCoach({ heading: "Safe to sell", tapped: "" }, results), { kind: "phrase", text: "Not met. Tap the check that's to blame.", met: false });
  assert.deepEqual(requirementCoach({ heading: "Safe to sell", tapped: "temp_ok" }, results), { kind: "wrong", text: "That one passed. Look for the ×.", met: false });
  assert.equal(requirementCoach({ heading: "Safe to sell", tapped: "nut_free" }, results).text, "That one passed. Look for the ×.");
  assert.deepEqual(requirementCoach({ heading: "Safe to sell", tapped: "time_ok" }, results), { kind: "done", text: "One failed check is enough to fail the requirement. ergo shows which one.", met: true });
  assert.equal(tapOutcome(results, "nope"), "none");
  assert.equal(tapOutcome(results, ""), "none");
});

test("step 10 follows the failing row even when the reader's name differs", () => {
  const report = run(batch10, tutorialPolicy({ name: "no_nuts", heading: "Safe" }));
  const results = lineResults(report, "no_nuts");
  assert.equal(tapOutcome(results, "time_ok"), "right");
  assert.equal(tapOutcome(results, "no_nuts"), "wrong");
  const nutsBad = run({ ...batch10, allergens: ["nuts"] }, tutorialPolicy({ name: "no_nuts", heading: "Safe" }));
  assert.equal(tapOutcome(lineResults(nutsBad, "no_nuts"), "no_nuts"), "right");
});

const bakery = (from, id, name = "nut_free", heading = "Safe to sell") => run(bakeryBatches, tutorialPolicy({ name, heading, from, id }));
const names11 = (name = "nut_free") => checkLines(name).map((l) => l.name);

test("step 11: four batches, only the first passes, and the causes are value, unusable and absent", () => {
  const report = bakery("batches", "id");
  const grid = gridFromReport(report, "safe_to_sell", names11());
  assert.equal(grid.ids.length, 4);
  assert.deepEqual(grid.checks, ["nut_free", "temp_ok", "time_ok"]);
  assert.equal(grid.status, "not_met");
  const cell = (n, check) => grid.cells[`cake-batch-2026-03-18-00${n}|${check}`];
  for (const check of grid.checks) assert.equal(cell(1, check).passed, true, check);
  assert.deepEqual([cell(2, "nut_free").passed, cell(2, "nut_free").cause], [false, "value"]);
  assert.deepEqual([cell(3, "nut_free").passed, cell(3, "nut_free").cause], [false, "unusable"]);
  assert.deepEqual([cell(4, "nut_free").passed, cell(4, "nut_free").cause], [false, "absent"]);
  for (const n of [2, 3, 4]) for (const check of ["temp_ok", "time_ok"]) assert.equal(cell(n, check).passed, true);
  assert.deepEqual(report.requirements.safe_to_sell.causes.map((c) => c.cause).sort(), ["absent", "unusable", "value"]);
});

test("step 11 cell lines say the cause and the value that was read", () => {
  const grid = gridFromReport(bakery("batches", "id"), "safe_to_sell", names11());
  assert.equal(cellLine(grid, "cake-batch-2026-03-18-002", "nut_free"), 'value · allergens = ["nuts","milk"]');
  assert.equal(cellLine(grid, "cake-batch-2026-03-18-003", "nut_free"), 'unusable · allergens = "nuts"');
  assert.equal(cellLine(grid, "cake-batch-2026-03-18-004", "nut_free"), "absent · allergens = not in the input");
  assert.equal(cellLine(grid, "cake-batch-2026-03-18-001", "temp_ok"), "satisfied · bake.temp_c = 180");
  assert.equal(grid.shortId("cake-batch-2026-03-18-004"), "…004");
});

test("step 11 opens on the first failing cell, which is the nut check of batch 002", () => {
  const grid = gridFromReport(bakery("batches", "id"), "safe_to_sell", names11());
  assert.equal(defaultCell(grid), "cake-batch-2026-03-18-002|nut_free");
});

test("the default cell is the first cell when nothing fails, and null with no batches", () => {
  const grid = { ids: ["a", "b"], checks: ["x", "y"], cells: { "a|x": { passed: true }, "a|y": { passed: true }, "b|x": { passed: true }, "b|y": { passed: true } } };
  assert.equal(defaultCell(grid), "a|x");
  assert.equal(defaultCell({ ids: [], checks: ["x"], cells: {} }), null);
});

test("the default cell skips a failing cell later in the row and finds an earlier row first", () => {
  const grid = { ids: ["a", "b"], checks: ["x", "y"], cells: { "a|x": { passed: true }, "a|y": { passed: false }, "b|x": { passed: false }, "b|y": { passed: true } } };
  assert.equal(defaultCell(grid), "a|y");
});

const sentenceOf = (check) => checkLines("nut_free").find((l) => l.name === check).sentence;
const hlFor = (n, check) => cellHighlight(bakeryBatches, "batches", "id", `cake-batch-2026-03-18-00${n}`, sentenceOf(check));

test("each check highlights the field it reads in its own batch", () => {
  assert.deepEqual(hlFor(2, "nut_free").hl.exact, ["batches", "*", "allergens"]);
  assert.deepEqual(hlFor(2, "temp_ok").hl.exact, ["batches", "*", "bake", "temp_c"]);
  assert.deepEqual(hlFor(1, "time_ok").hl.exact, ["batches", "*", "bake", "minutes"]);
  assert.equal(hlFor(3, "nut_free").slot, 2);
  assert.deepEqual(hlFor(3, "nut_free").hl.exact, ["batches", "*", "allergens"]);
});

test("a batch with no allergens key highlights nothing but still names its row", () => {
  assert.deepEqual(hlFor(4, "nut_free"), { slot: 3, hl: null });
});

test("no highlight when the list key is wrong or the batch is not there", () => {
  assert.equal(cellHighlight(bakeryBatches, "nope", "id", "x", "allergens"), null);
  assert.equal(cellHighlight(bakeryBatches, "batches", "id", "missing", "allergens"), null);
  assert.equal(cellHighlight(null, "batches", "id", "x", "allergens"), null);
  assert.equal(cellHighlight({ batches: "nuts" }, "batches", "id", "x", "allergens"), null);
});

test("segments of a batch carry its place in the list, and only those", () => {
  const segs = jsonSegments(bakeryBatches);
  const slots = [...new Set(segs.filter((x) => x.slot !== undefined).map((x) => x.slot))];
  assert.deepEqual(slots, [0, 1, 2, 3]);
  assert.equal(segs.filter((x) => x.slot === undefined).map((x) => x.text).join("").includes("cake-batch"), false);
  const hl = hlFor(2, "nut_free");
  const marked = segs.filter((x) => segmentClasses(x, hl.hl).includes("is-field")).map((x) => x.slot);
  assert.deepEqual(marked, [0, 1, 2]);
});

test("short ids change only the shown text of the id, not its value", () => {
  const segs = jsonSegments(bakeryBatches, { shortIds: "id" });
  const ids = segs.filter((x) => x.leafOf === JSON.stringify(["batches", "*", "id"]));
  assert.deepEqual(ids.map((x) => x.text), ['"…001"', '"…002"', '"…003"', '"…004"']);
  assert.deepEqual(ids.map((x) => x.raw), bakeryBatches.batches.map((b) => b.id));
  assert.equal(segs.map((x) => x.text).join("").includes("cake-batch"), false);
  assert.equal(jsonSegments(bakeryBatches).map((x) => x.text).join("").includes("cake-batch-2026-03-18-001"), true);
});

test("full mode shows every batch whole on one line each", () => {
  const text = jsonSegments(bakeryBatches, { shortIds: "id" }).map((x) => x.text).join("");
  const lines = text.split("\n").filter((l) => l.includes("…"));
  assert.equal(lines.length, 4);
  assert.equal(lines[1].trim(), '{"id": "…002", "allergens": ["nuts", "milk"], "bake": {"minutes": 32, "temp_c": 180}},');
  assert.equal(lines[3].trim(), '{"id": "…004", "bake": {"minutes": 32, "temp_c": 180}}');
});

test("collapsing can leave one batch open in full", () => {
  const text = jsonSegments(bakeryBatches, { collapse: true, expand: 2 }).map((x) => x.text).join("");
  const lines = text.split("\n").filter((l) => l.includes("cake-batch"));
  assert.equal(lines.length, 4);
  assert.deepEqual(lines.map((l) => l.includes("…")), [true, true, false, true]);
  assert.equal(lines[2].trim(), '{"id": "cake-batch-2026-03-18-003", "allergens": "nuts", "bake": {"minutes": 32, "temp_c": 180}},');
});

test("step 11 is met only by the real list key and a real name field", () => {
  const status = (from, id) => subjectsStatus({ from, id }, from === "" ? null : bakery(from, id === "" ? "id" : id));
  assert.deepEqual(status("batches", "id"), { fromOk: true, idOk: true });
  assert.deepEqual(status("batches", "name"), { fromOk: true, idOk: false });
  assert.deepEqual(status("batches", "bake"), { fromOk: true, idOk: false });
  assert.deepEqual(status("batches", "allergens"), { fromOk: true, idOk: false });
  assert.deepEqual(status("batch", "id"), { fromOk: false, idOk: false });
  assert.deepEqual(status("", "id"), { fromOk: false, idOk: false });
  assert.deepEqual(status("id", "id"), { fromOk: false, idOk: false });
});

test("step 11 coaching points at the real keys, state by state", () => {
  const coach = (from, id) => subjectsCoach({ from, id }, subjectsStatus({ from, id }, from === "" ? null : bakery(from, id === "" ? "id" : id)));
  assert.equal(coach("", "").text, "Look at the file. Which key holds the list of batches?");
  assert.equal(coach("batch", "").text, "There's no `batch` at the top of the file. Look at the first key.");
  assert.equal(coach("batches", "").text, "Yes, that's where the batches are. Now look inside one: which field names it?");
  assert.equal(coach("batches", "name").text, "No batch has `name`. Look for the field that looks like a name.");
  assert.equal(coach("batches", "bake").text, "That isn't a name. Each batch needs a name that's different from the others.");
  assert.deepEqual(coach("batches", "id"), { kind: "done", text: "Four batches, one report. Tap a × to see why it failed.", met: true });
});

test("the slug of a heading is lowercase words joined with _", () => {
  assert.equal(slug("Safe to sell"), "safe_to_sell");
  assert.equal(slug("  Safe to sell!  "), "safe_to_sell");
  assert.equal(slug("Nut-free & baked"), "nut_free_baked");
  assert.equal(slug("***"), "requirement");
  assert.equal(slug(""), "requirement");
  assert.equal(slug("Day 2: cakes"), "day_2_cakes");
});

test("the YAML is built from the reader's own parts", () => {
  const policy = tutorialPolicy({ name: "no_nuts", heading: "Safe to sell", from: "batches", id: "id" });
  assert.equal(policyYaml(policy), [
    "subjects:",
    "  batch:",
    "    from: [batches]",
    "    identified_by: [id]",
    "requirements:",
    "  safe_to_sell:",
    "    description: Safe to sell",
    "    subject: batch",
    "    checks:",
    '      no_nuts: allergens does not contain "nuts"',
    "      temp_ok: bake.temp_c is between 175 and 200",
    "      time_ok: bake.minutes is between 25 and 40",
  ].join("\n"));
  assert.match(policyYaml(tutorialPolicy({ heading: "Is it: safe? # yes", from: "batches", id: "id" })), /description: "Is it: safe\? # yes"/);
});

const parseYaml = (text) => {
  const root = {};
  const stack = [[-1, root]];
  for (const line of text.split("\n")) {
    const indent = line.search(/\S/);
    const m = /^(\S[^:]*):(?: (.*))?$/.exec(line.trim());
    while (stack.at(-1)[0] >= indent) stack.pop();
    const parent = stack.at(-1)[1];
    const [, k, v] = m;
    if (v === undefined) { parent[k] = {}; stack.push([indent, parent[k]]); }
    else if (v.startsWith("[")) parent[k] = v.slice(1, -1).split(", ");
    else if (v.startsWith('"')) parent[k] = JSON.parse(v);
    else parent[k] = v;
  }
  return root;
};

test("the YAML policy, read back, gives exactly the report of step 11", () => {
  for (const name of ["nut_free", "no_nuts"]) {
    const policy = tutorialPolicy({ name, heading: "Safe to sell", from: "batches", id: "id" });
    const fromYaml = parseYaml(policyYaml(policy));
    assert.deepEqual(fromYaml, policy);
    assert.deepEqual(run(bakeryBatches, fromYaml), run(bakeryBatches, policy));
  }
  const odd = tutorialPolicy({ name: "nut_free", heading: "Is it: safe? # yes", from: "batches", id: "id" });
  assert.deepEqual(parseYaml(policyYaml(odd)), odd);
});

test("every YAML line says where it came from", () => {
  const lines = yamlLines(tutorialPolicy({ name: "no_nuts", heading: "Safe", from: "batches", id: "id" }));
  assert.equal(lines.length, 12);
  assert.equal(lines.every((l) => typeof l.note === "string" && l.note.length > 0), true);
  assert.equal(lines.find((l) => l.text.includes("no_nuts")).note, "You named this in step 9 and wrote it in step 2.");
  assert.equal(lines.find((l) => l.text.includes("temp_ok")).note, "The name is from step 9. You wrote the sentence in step 5.");
  assert.equal(lines.find((l) => l.text.includes("time_ok")).note, "The name is from step 9. You wrote the sentence in step 6.");
  assert.equal(lines.find((l) => l.text.includes("description")).note, "Your heading from step 10.");
  assert.equal(lines.find((l) => l.text.includes("from:")).step, 11);
});

test("YAML only appears in step 12", () => {
  const text = JSON.stringify(steps.map((s) => s.goal));
  assert.equal(/yaml/i.test(text), false);
});

test("saved progress for steps 9 to 11 keeps the typed fields, and bad fields are dropped", () => {
  const drafts = {
    8: { sentence: "", input: steps[8].input, fields: { name: "no_nuts" } },
    9: { sentence: "", input: steps[9].input, fields: { heading: "Safe", tapped: "time_ok" } },
    10: { sentence: "", input: steps[10].input, fields: { from: "batches", id: "id" } },
  };
  const back = restoreProgress(JSON.parse(JSON.stringify(serializeProgress(11, drafts))));
  assert.equal(back.pos, 11);
  assert.deepEqual(back.drafts[8].fields, { name: "no_nuts" });
  assert.deepEqual(back.drafts[9].fields, { heading: "Safe", tapped: "time_ok" });
  assert.deepEqual(back.drafts[10].fields, { from: "batches", id: "id" });
  const bad = restoreProgress({ pos: 10, drafts: { 8: { sentence: "", input: "{}", fields: { name: 5, extra: "x" } }, 9: { sentence: "", input: "{}" } } });
  assert.deepEqual(bad.drafts[8].fields, { name: "" });
  assert.deepEqual(bad.drafts[9].fields, { heading: "", tapped: "" });
  assert.deepEqual(freshDraft({}, 8).fields, { name: "" });
  assert.equal(freshDraft({}, 0).fields, undefined);
});

test("an old save from the eight step tutorial still loads", () => {
  const old = restoreProgress({ pos: 8, drafts: { 1: { sentence: nutFree, input: steps[1].input }, 7: { sentence: 'some tasters.verdict is "approved"', input: steps[7].input } } });
  assert.equal(old.pos, 8);
  assert.equal(old.drafts[7].sentence, 'some tasters.verdict is "approved"');
  assert.equal(old.drafts[7].fields, undefined);
  const older = restoreProgress({ pos: 8, drafts: { 6: { sentences: ["every ingredients.certified is true", 'some tasters.verdict is "approved"'], input: steps[6].input } } });
  assert.equal(older.drafts[7].sentence, 'some tasters.verdict is "approved"');
});

test("the default names are what the steps fall back on", () => {
  assert.deepEqual(defaultNames, { name: "nut_free", heading: "Safe to sell", from: "batches", id: "id" });
  assert.deepEqual(checkLines("a").map((l) => l.name), ["a", "temp_ok", "time_ok"]);
});

test("steps 9 and 10 show their batch on one flat line, with the same keys the checks read", () => {
  for (const si of [8, 9]) {
    assert.equal(steps[si].flat, true);
    const value = JSON.parse(steps[si].input);
    const flat = jsonSegments(value, { flat: true });
    assert.equal(flat.map((s) => s.text).join(""), steps[si].input);
    assert.equal(layoutLines(flat).length, 1);
    for (const line of checkLines("nut_free")) {
      const [hl] = fieldHighlights(line.sentence, value);
      const marked = flat.filter((s) => segmentClasses(s, hl).includes("is-field")).map((s) => s.text);
      assert.deepEqual(marked, [line.sentence.startsWith("allergens") ? '"allergens"' : line.sentence.includes("temp_c") ? '"temp_c"' : '"minutes"']);
    }
  }
  assert.equal(isPretty(JSON.parse(steps[8].input)), true);
});

test("step 1 says why the check should pass when milk is there", () => {
  assert.equal(steps[0].goal.ask, "This is a milk loaf, so its allergen list must warn about milk. Write a check that passes when the allergens contain milk.");
});

test("step 6 says the carried temperature check still passes and the minutes are missing", () => {
  const carried = steps[4].goal.answer.sentence;
  const r = grade(steps[5].goal, check, carried, steps[5].input);
  assert.equal(r.shown.passed, true);
  assert.equal(r.met, false);
  assert.equal(JSON.parse(steps[5].input).bake.minutes, 45);
  assert.equal(steps[5].goal.ask, "This batch baked for 45 minutes, and it must bake for 25 to 40. Your check still passes it. Add the minutes, joined with `and`.");
});

test("step 8 says some means at least one", () => {
  assert.match(steps[7].goal.start, /`some` means at least one/);
  assert.match(steps[7].goal.done, /^`some` means at least one/);
});

test("step 9 says what a check's name is for before asking for one", () => {
  assert.equal(steps[8].goal.ask, "In the report, each check is a row, and its name tells people which row failed. The other two have names. Name the first one.");
});

test("step 11 asks which key holds the batches and which field tells them apart", () => {
  assert.deepEqual(steps[10].goal.questions, { from: "Which key holds the list of batches?", id: "Which field tells the batches apart?" });
});
