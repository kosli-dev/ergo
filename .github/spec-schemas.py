import json, subprocess, sys
import jsonschema

query = '[{"where": concat(" / ", [t, g.description, c.description]), "policy": g.policy, "report": data.ergo.report(c.input, g.policy, object.get(g, "params", {}))} | some t, gs in data.spec.cases; some g in gs; some c in g.cases]'
opa = subprocess.run(["opa", "eval", "-d", ".", "--ignore", ".github", "--ignore", "ports", "--format", "json", query], stdout=subprocess.PIPE, text=True)
if opa.returncode != 0:
    sys.exit(f"opa eval failed:\n{opa.stdout}")
cases = json.loads(opa.stdout)["result"][0]["expressions"][0]["value"]
if not cases:
    sys.exit("found no cases in spec/cases")
policy = jsonschema.Draft202012Validator(json.load(open("spec/policy/schema.json")))
report = jsonschema.Draft202012Validator(json.load(open("spec/report/schema.json")))
problems = []
for case in cases:
    for e in report.iter_errors(case["report"]):
        problems.append(f"{case['where']}: report doesn't match report/schema.json at /{'/'.join(map(str, e.absolute_path))}: {e.message}")
    for r in case["report"]["results"]:
        if r["check"] == "$well_formed" and not r["passed"] and not any(isinstance(i["value"], list) for i in r["inputs"]):
            problems.append(f"{case['where']}: $well_formed fails for requirement {r['requirement']} without naming a problem")
    well_formed = all(r["passed"] for r in case["report"]["results"] if r["check"] == "$well_formed")
    if well_formed:
        for e in policy.iter_errors(case["policy"]):
            problems.append(f"{case['where']}: Ergo reads the policy as written correctly, but it doesn't match policy/schema.json at /{'/'.join(map(str, e.absolute_path))}: {e.message}")
for p in problems:
    print(p)
print(f"{len(cases)} cases, {len(problems)} problems")
sys.exit(1 if problems else 0)
