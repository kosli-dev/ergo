import glob, json, os, re, subprocess, sys
import jsonschema

query = '[{"where": concat(" / ", [t, g.description, c.description]), "rules": object.get(c, "rules", []), "policy": g.policy, "report": data.ergo.report(c.input, g.policy, object.get(g, "params", {}))} | some t, gs in input; some g in gs; some c in g.cases]'
examples_policy = {
    "subjects": {"deployment": {"from": "deployments", "identified_by": "id"}},
    "requirements": {"approved": {"subject": "deployment", "checks": {"approver_set": "approver is a non-empty string"}}},
    "example_params": {"max": 1},
    "examples": [
        {
            "name": "a deployment needs an approver",
            "description": "Shows both lines.",
            "input": {"deployments": [{"id": "d1"}, {"id": "d2", "approver": "bob"}]},
            "params": {"max": 2},
            "outcome": [
                "not compliant",
                {"approved is not met": ["deployment d1 fails approver_set because approver is missing", "deployment d2 passes approver_set"]},
            ],
        },
        {"name": "met", "input": {"deployments": [{"id": "d1", "approver": "ann"}]}, "outcome": [{"approved is met": None}]},
    ],
}
bad_examples = [
    [],
    [{"input": {}, "outcome": ["compliant"]}],
    [{"name": "", "input": {}, "outcome": ["compliant"]}],
    [{"name": "a", "outcome": ["compliant"]}],
    [{"name": "a", "input": {}}],
    [{"name": "a", "input": {}, "outcome": "compliant"}],
    [{"name": "a", "input": {}, "outcome": []}],
    [{"name": "a", "input": {}, "outcome": [5]}],
    [{"name": "a", "input": {}, "outcome": [{"approved": [5]}]}],
    [{"name": "a", "input": {}, "outcome": [{"a": [], "b": []}]}],
    [{"name": "a", "input": {}, "outcome": ["compliant"], "description": 1}],
    [{"name": "a", "input": {}, "outcome": ["compliant"], "extra": 1}],
]
spec = re.search(r'^_spec := "(v[^"]+)"$', open("engines/rego/src/shared/basics.rego").read(), re.M).group(1)
subprocess.run([".github/build-ergo.sh"], check=True)
topics = "{" + ",".join(json.dumps(os.path.basename(os.path.dirname(f))) + ": " + open(f).read().replace("{{spec}}", spec) for f in sorted(glob.glob("spec/cases/*/cases.json"))) + "}"
opa = subprocess.run(["opa", "eval", "-d", "dist/ergo.rego", "-I", "--format", "json", query], input=topics, stdout=subprocess.PIPE, text=True)
if opa.returncode != 0:
    sys.exit(f"opa eval failed:\n{opa.stdout}")
cases = json.loads(opa.stdout)["result"][0]["expressions"][0]["value"]
if not cases:
    sys.exit("found no cases in spec/cases")
policy = jsonschema.Draft202012Validator(json.load(open("spec/policy/schema.json")))
report = jsonschema.Draft202012Validator(json.load(open("spec/report/schema.json")))
problems = []
examples_policy = {"ergo_spec": spec, **examples_policy}
for e in policy.iter_errors(examples_policy):
    problems.append(f"examples that are written correctly don't match policy/schema.json at /{'/'.join(map(str, e.absolute_path))}: {e.message}")
for bad in bad_examples:
    if policy.is_valid({**examples_policy, "examples": bad}):
        problems.append(f"examples written wrong match policy/schema.json: {json.dumps(bad)}")
for case in cases:
    for e in report.iter_errors(case["report"]):
        problems.append(f"{case['where']}: report doesn't match report/schema.json at /{'/'.join(map(str, e.absolute_path))}: {e.message}")
    for r in case["report"]["results"]:
        if r["check"] == "$well_formed" and not r["passed"] and not any(isinstance(i["value"], list) for i in r["inputs"]):
            problems.append(f"{case['where']}: $well_formed fails for requirement {r['requirement']} without naming a problem")
    well_formed = all(r["passed"] for r in case["report"]["results"] if r["check"] == "$well_formed")
    if well_formed:
        checked = case["policy"]
        if "examples.ignored" in case["rules"]:
            checked = {k: v for k, v in checked.items() if k not in ("examples", "example_params")}
        for e in policy.iter_errors(checked):
            problems.append(f"{case['where']}: Ergo reads the policy as written correctly, but it doesn't match policy/schema.json at /{'/'.join(map(str, e.absolute_path))}: {e.message}")
for p in problems:
    print(p)
print(f"{len(cases)} cases, {len(problems)} problems")
sys.exit(1 if problems else 0)
