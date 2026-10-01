import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, copyFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";

const here = new URL(".", import.meta.url).pathname;
const html = readFileSync(join(here, "report.html"), "utf8");

function viewer() {
  const script = html.match(/<script id="ergo-viewer">([\s\S]*?)<\/script>/)[1];
  const context = vm.createContext({ window: { addEventListener() {} } });
  vm.runInContext(script, context);
  return context;
}

const { page, render } = viewer();

function report() {
  return {
    compliant: false,
    requirements: {
      prod_deploy: {
        checks: {
          $applies: { description: "subject is in scope", expression: "environment == prod" },
          approved: { description: "Someone approved the deployment", expression: "approved_by is a non-empty string" },
        },
        require: "every",
        satisfied: false,
        subjects: { matching: 1, total: 2 },
      },
    },
    results: [
      { requirement: "prod_deploy", subject: { type: "deployment", id: "d-1" }, check: "$applies", inputs: [{ name: "environment", value: "prod" }], passed: true, cause: "satisfied" },
      { requirement: "prod_deploy", subject: { type: "deployment", id: "d-2" }, check: "$applies", inputs: [{ name: "environment", value: "staging" }], passed: false, cause: "value" },
      { requirement: "prod_deploy", subject: { type: "deployment", id: "d-1" }, check: "approved", inputs: [{ name: "approved_by", value: null }], passed: false, cause: "absent" },
    ],
  };
}

function compliantReport() {
  const r = report();
  r.compliant = true;
  r.requirements.prod_deploy.satisfied = true;
  r.results[2].inputs[0].value = "alice";
  r.results[2].passed = true;
  r.results[2].cause = "satisfied";
  return r;
}

function refused(r) {
  return render(r).includes("This report can't be shown");
}

test("test_compliant_report_says_compliant", () => {
  const out = render(compliantReport());
  assert.match(out, /<h1>Compliant<\/h1>/);
  assert.match(out, /1 of 1 requirements met/);
});

test("test_non_compliant_report_says_not_compliant", () => {
  const out = render(report());
  assert.match(out, /<h1>Not compliant<\/h1>/);
  assert.match(out, /0 of 1 requirements met/);
  assert.match(out, /Not met/);
});

test("test_rows_show_subject_check_value_and_cause", () => {
  const out = render(report());
  assert.match(out, /<td>d-1<\/td><td>Someone approved the deployment<small><code>approved_by is a non-empty string<\/code><\/small><\/td><td><code>approved_by = null<\/code><\/td><td><span class="badge failed">Failed<\/span><\/td><td><code>absent<\/code><\/td>/);
});

test("test_string_values_are_quoted_so_they_differ_from_null", () => {
  const r = report();
  r.results[2].inputs[0].value = "null";
  assert.match(render(r), /approved_by = &quot;null&quot;/);
});

test("test_out_of_scope_subject_is_shown_but_not_as_a_failure", () => {
  assert.match(render(report()), /<td>d-2<\/td>.*?Out of scope/);
});

test("test_applies_row_that_could_not_be_read_is_a_failure_not_out_of_scope", () => {
  const r = report();
  r.results[1].cause = "absent";
  const out = render(r);
  assert.doesNotMatch(out, /Out of scope/);
  assert.match(out, /<td>d-2<\/td>.*?Failed/);
});

test("test_requirement_level_rows_have_no_subject_id", () => {
  const r = report();
  r.requirements.prod_deploy.checks.$min_subjects = { description: "at least 1", expression: "count >= 1" };
  r.results.unshift({ requirement: "prod_deploy", subject: { type: "deployment", id: null }, check: "$min_subjects", inputs: [{ name: "count", value: 1 }], passed: true, cause: "satisfied" });
  assert.match(render(r), /<tr><td><\/td><td>at least 1/);
});

test("test_non_string_subject_id_is_shown_as_json", () => {
  const r = report();
  r.results[0].subject.id = 7;
  assert.match(render(r), /<td>7<\/td>/);
});

test("test_check_without_description_shows_its_name", () => {
  const r = report();
  delete r.requirements.prod_deploy.checks.approved.description;
  delete r.requirements.prod_deploy.checks.approved.expression;
  assert.match(render(r), /<td><code>approved<\/code><\/td><td><code>approved_by = null/);
});

test("test_requirements_are_shown_in_name_order_whatever_the_json_order", () => {
  const r = report();
  const b = structuredClone(r.requirements.prod_deploy);
  r.requirements = { zeta: b, alpha: r.requirements.prod_deploy };
  r.results = [...r.results.map((row) => ({ ...row, requirement: "zeta" })), ...r.results.map((row) => ({ ...row, requirement: "alpha" }))];
  const out = render(r);
  assert.ok(out.indexOf("<span>alpha</span>") < out.indexOf("<span>zeta</span>"));
});

test("test_values_from_the_input_are_escaped", () => {
  const r = report();
  r.results[2].inputs[0].value = "<img src=x onerror=alert(1)>";
  r.results[2].subject.id = "<b>d-1</b>";
  const out = render(r);
  assert.doesNotMatch(out, /<img|<b>/);
  assert.match(out, /&lt;img src=x onerror=alert\(1\)&gt;/);
});

test("test_invalid_json_is_refused", () => {
  assert.match(page("{not json"), /This report can't be shown.*isn&#39;t valid JSON/);
});

test("test_opa_default_output_is_refused", () => {
  assert.ok(refused({ result: [{ expressions: [{ value: report() }] }] }));
});

for (const [name, value] of [["missing", undefined], ["null", null], ["a string", "true"]]) {
  test(`test_compliant_${name.replace(" ", "_")}_is_refused`, () => {
    const r = compliantReport();
    r.compliant = value;
    assert.ok(refused(r));
  });
}

for (const bad of [null, [], "report", 1]) {
  test(`test_report_that_is_${JSON.stringify(bad)}_is_refused`, () => {
    assert.ok(refused(bad));
  });
}

test("test_requirements_that_is_not_an_object_is_refused", () => {
  for (const value of [undefined, null, [], "x"]) {
    const r = report();
    r.requirements = value;
    assert.ok(refused(r));
  }
});

test("test_results_that_is_not_a_list_is_refused", () => {
  for (const value of [undefined, null, {}, "x"]) {
    const r = report();
    r.results = value;
    assert.ok(refused(r));
  }
});

test("test_compliant_report_with_no_requirements_is_refused_because_ergo_never_says_that", () => {
  assert.ok(refused({ compliant: true, requirements: {}, results: [] }));
});

test("test_compliant_report_with_an_unmet_requirement_is_refused", () => {
  const r = compliantReport();
  r.requirements.prod_deploy.satisfied = false;
  assert.ok(refused(r));
});

test("test_requirement_with_no_rows_is_refused_so_it_cannot_look_empty_and_fine", () => {
  const r = compliantReport();
  r.requirements.other = structuredClone(r.requirements.prod_deploy);
  assert.match(render(r), /Requirement &quot;other&quot; has no rows/);
});

test("test_broken_requirement_entries_are_refused", () => {
  const breakers = [
    (req) => null,
    (req) => ({ ...req, satisfied: "yes" }),
    (req) => ({ ...req, satisfied: undefined }),
    (req) => ({ ...req, checks: null }),
    (req) => ({ ...req, subjects: undefined }),
    (req) => ({ ...req, subjects: { matching: "1", total: 2 } }),
    (req) => ({ ...req, subjects: { matching: 1 } }),
  ];
  for (const breaker of breakers) {
    const r = compliantReport();
    r.requirements.prod_deploy = breaker(r.requirements.prod_deploy);
    assert.ok(refused(r), breaker.toString());
  }
});

test("test_broken_rows_are_refused", () => {
  const breakers = [
    () => null,
    (row) => ({ ...row, requirement: "missing" }),
    (row) => ({ ...row, requirement: "toString" }),
    (row) => ({ ...row, requirement: undefined }),
    (row) => ({ ...row, check: "missing" }),
    (row) => ({ ...row, check: "toString" }),
    (row) => ({ ...row, passed: "true" }),
    (row) => ({ ...row, passed: null }),
    (row) => ({ ...row, cause: undefined }),
    (row) => ({ ...row, subject: null }),
    (row) => ({ ...row, subject: { id: "d-1" } }),
    (row) => ({ ...row, subject: { type: "deployment" } }),
    (row) => ({ ...row, inputs: null }),
    (row) => ({ ...row, inputs: [{ value: 1 }] }),
    (row) => ({ ...row, inputs: [{ name: "x" }] }),
    (row) => ({ ...row, inputs: [null] }),
  ];
  for (const breaker of breakers) {
    const r = compliantReport();
    r.results[2] = breaker(r.results[2]);
    assert.ok(refused(r), breaker.toString());
  }
});

test("test_every_problem_is_listed_not_just_the_first", () => {
  const r = compliantReport();
  r.results[0].passed = null;
  r.results[1].cause = 3;
  const out = render(r);
  assert.match(out, /results\[0\] has no passed value/);
  assert.match(out, /results\[1\] has no cause/);
});

function ergoReport(dir) {
  mkdirSync(join(dir, "policy"));
  copyFileSync(join(here, "..", "..", "ergo.rego"), join(dir, "policy", "ergo.rego"));
  writeFileSync(
    join(dir, "policy", "deploy.rego"),
    `package deploy

import data.ergo

requirements := {"prod_deploy": {
	"subject_type": "deployment",
	"from": ["deployments"],
	"id": ["id"],
	"applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
	"checks": {"approved": {
		"description": "Someone approved the deployment </script>",
		"op": "non_empty_string",
		"path": ["approved_by"],
	}},
}}

report := ergo.report(input, requirements)
`,
  );
  writeFileSync(
    join(dir, "deployments.json"),
    JSON.stringify({
      deployments: [
        { id: "d-1", environment: "prod", approved_by: "alice" },
        { id: "d-2", environment: "prod" },
        { id: "d-3", environment: "staging" },
      ],
    }),
  );
  return execFileSync("opa", ["eval", "-d", "policy", "-i", "deployments.json", "--format=raw", "data.deploy.report"], { cwd: dir, encoding: "utf8" });
}

test("test_real_ergo_report_is_shown", () => {
  const out = page(ergoReport(mkdtempSync(join(tmpdir(), "ergo-"))));
  assert.doesNotMatch(out, /can't be shown/);
  assert.match(out, /Not compliant/);
  assert.match(out, /2 of 3 deployment subjects in scope/);
  assert.match(out, /<td>d-3<\/td>.*?Out of scope/);
  assert.match(out, /approved_by = null/);
});

test("test_embedded_report_survives_values_that_would_close_the_script_tag", () => {
  const dir = mkdtempSync(join(tmpdir(), "ergo-"));
  const json = ergoReport(dir);
  writeFileSync(join(dir, "report.json"), json);
  copyFileSync(join(here, "report.html"), join(dir, "report.html"));
  execFileSync("sh", ["-c", `sed 's/</\\\\u003c/g' report.json > safe.json && sed '/id="ergo-report"/r safe.json' report.html > deploy-report.html`], { cwd: dir });
  const embedded = readFileSync(join(dir, "deploy-report.html"), "utf8");
  const slot = embedded.match(/<script type="application\/json" id="ergo-report">([\s\S]*?)<\/script>/)[1];
  assert.deepEqual(JSON.parse(slot), JSON.parse(json));
  assert.equal(embedded.match(/<script id="ergo-viewer">/g).length, 1);
});
