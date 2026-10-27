import json
import pathlib
import re
import subprocess
import sys
import tempfile


def opa_eval(args):
    out = subprocess.run(["opa", "eval", "--format", "json", *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(out.stdout + out.stderr)
    result = json.loads(out.stdout).get("result")
    if not result:
        raise SystemExit("opa eval " + " ".join(args) + " gave no result")
    return result[0]["expressions"][0]["value"]


def check_rego(name, example, tmp, problems):
    rego = example.get("rego")
    if rego is None:
        return
    policy = tmp / f"{name}.rego"
    policy.write_text(rego["policy"] + "\n")
    data = tmp / f"{name}.json"
    data.write_text(example["input"])
    actual = opa_eval(["-d", str(policy), "-i", str(data), rego["query"]])
    if actual != json.loads(rego["result"]):
        problems.append(f"{name}: plain Rego gives {json.dumps(actual)}, and the page shows {rego['result']}")


def check_report(name, example, ergo, spec, tmp, problems):
    payload = tmp / f"{name}-payload.json"
    payload.write_text(json.dumps({"input": example["input"], "policy": f"ergo_spec: {spec}\n{example['policy']}"}))
    report = opa_eval(["-d", str(ergo), "-i", str(payload), "data.ergo.report(json.unmarshal(input.input), yaml.unmarshal(input.policy), {})"])
    if report.get("ergo") != spec:
        problems.append(f"{name}: the report says spec {report.get('ergo')}, and the page shows {spec}")
    rows = report.get("results", [])
    shown = example["report"]
    if len(rows) != len(shown):
        problems.append(f"{name}: the report has {len(rows)} rows, and the page shows {len(shown)}")
    for i, (row, want) in enumerate(zip(rows, shown), 1):
        actual_id = row.get("subject", {}).get("id")
        for key, actual in (("subject", actual_id), ("check", row.get("check")), ("passed", row.get("passed")), ("cause", row.get("cause"))):
            if want.get(key) != actual:
                problems.append(f"{name}, row {i}: {key} is {json.dumps(actual)} in the report, and {json.dumps(want.get(key))} on the page")
        inputs = [{"name": x.get("name"), "value": x.get("value")} for x in row.get("inputs", [])]
        for x in want.get("inputs", []):
            if {"name": x["name"], "value": x.get("value")} not in inputs:
                problems.append(f"{name}, row {i}: the report has no input {x['name']} = {json.dumps(x.get('value'))}")


def main():
    examples_path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "site/data/examples.yaml")
    ergo = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "ergo.rego")
    match = re.search(r'^_spec := "(v[^"]+)"$', ergo.read_text(), re.M)
    if not match:
        raise SystemExit(f"{ergo} has no _spec")
    spec = match.group(1)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        examples = opa_eval(["-i", str(examples_path), "input"])
        rego_copy = tmp / "ergo.rego"
        rego_copy.write_text(ergo.read_text())
        problems = []
        for name in sorted(examples):
            check_rego(name, examples[name], tmp, problems)
            check_report(name, examples[name], rego_copy, spec, tmp, problems)
    if problems:
        print("\n".join(problems))
        raise SystemExit(1)
    print(f"The {len(examples)} examples in {examples_path} match what {ergo} and plain Rego give")


main()
