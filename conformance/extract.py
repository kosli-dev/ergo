import base64
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, "conformance", "from_tests")

trace = '''report_with_params(doc, params, policy) := r if {
	print(json.marshal({"doc": doc, "params": params, "params_given": _trace_params_given, "policy": policy, "rego_only": _trace_rego_only([doc, params, policy])}))
	r := _untraced_report_with_params(doc, params, policy)
}

default _trace_params_given := false

_trace_params_given if _ = data.params

default _trace_rego_only(_) := false

_trace_rego_only(x) if {
	walk(x, [_, v])
	is_set(v)
}

_trace_rego_only(x) if {
	walk(x, [_, v])
	is_object(v)
	some k in object.keys(v)
	not is_string(k)
}

_untraced_report_with_params(doc, params, policy) := r if {'''

custom_ops = set()
for f in subprocess.run(["git", "ls-files", "*.rego"], cwd=root, capture_output=True, text=True, check=True).stdout.split():
    custom_ops |= set(re.findall(r'^operators contains "(\w+)"', open(os.path.join(root, f)).read(), re.M))


def traced_calls():
    with tempfile.TemporaryDirectory() as tmp:
        files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split("\n")
        for f in files:
            if f and not f.startswith(("conformance", "site/", "ports/", ".github/")):
                os.makedirs(os.path.join(tmp, os.path.dirname(f)), exist_ok=True)
                shutil.copy(os.path.join(root, f), os.path.join(tmp, f))
        path = os.path.join(tmp, "ergo.rego")
        source = open(path).read()
        head = "report_with_params(doc, params, policy) := r if {"
        assert source.count(head) == 1
        open(path, "w").write(source.replace(head, trace))
        run = subprocess.run(["opa", "test", ".", "--timeout", "300s", "--format", "json"], cwd=tmp, capture_output=True, text=True)
        results = json.loads(run.stdout)
    failed = [r["name"] for r in results if r.get("fail") or r.get("error")]
    if failed:
        sys.exit(f"these tests failed with the trace: {failed}")
    for r in results:
        if r["package"].startswith("data.conformance"):
            continue
        for line in base64.b64decode(r.get("output", "")).decode().splitlines():
            yield r["name"], json.loads(line)


def uses(policy, ops):
    if isinstance(policy, dict):
        return (isinstance(policy.get("op"), str) and policy["op"] in ops) or any(uses(v, ops) for v in policy.values())
    if isinstance(policy, list):
        return any(uses(v, ops) for v in policy)
    return False


def has_infinity(x):
    if isinstance(x, float):
        return math.isinf(x)
    if isinstance(x, dict):
        return any(has_infinity(v) for v in x.values())
    if isinstance(x, list):
        return any(has_infinity(v) for v in x)
    return False


def ops_of(policy):
    found = set()
    if isinstance(policy, dict):
        for req in policy.values():
            if isinstance(req, dict):
                for field in ("checks", "applies_to"):
                    checks = req.get(field)
                    if isinstance(checks, dict):
                        found |= {c["op"] for c in checks.values() if isinstance(c, dict) and isinstance(c.get("op"), str)}
    return found


built_in = set(re.search(r"^_leaf_ops := \{(.*)\}$", open(os.path.join(root, "ergo.rego")).read(), re.M).group(1).replace('"', "").split(", ")) | {"all", "any", "any_of"}


def topic_of(policy):
    ops = ops_of(policy)
    if ops - built_in:
        return "unknown_op"
    if len(ops) == 1:
        return next(iter(ops))
    return "mixed" if ops else "requirements"


def description_of(test):
    return test.removeprefix("test_").replace("_", " ")


skipped = {"Rego-only values": 0, "policies that aren't objects": 0, "custom operators": 0, "numbers too big for a float": 0, "repeated calls": 0}
seen = set()
groups = {}
for test, call in traced_calls():
    if call["rego_only"]:
        skipped["Rego-only values"] += 1
        continue
    if not isinstance(call["policy"], dict):
        skipped["policies that aren't objects"] += 1
        continue
    if uses(call["policy"], custom_ops):
        skipped["custom operators"] += 1
        continue
    if has_infinity(call):
        skipped["numbers too big for a float"] += 1
        continue
    params = call["params"] if call["params_given"] or call["params"] != {} else None
    key = json.dumps([call["doc"], params, call["policy"]], sort_keys=True)
    if key in seen:
        skipped["repeated calls"] += 1
        continue
    seen.add(key)
    group_key = (test, json.dumps([params, call["policy"]], sort_keys=True))
    topic = topic_of(call["policy"])
    topic_groups = groups.setdefault(topic, {})
    if group_key not in topic_groups:
        group = {"description": description_of(test), "requirements": call["policy"], "cases": []}
        if params is not None:
            group["params"] = params
        topic_groups[group_key] = group
    cases = topic_groups[group_key]["cases"]
    cases.append({"description": f"input {len(cases) + 1}", "input": call["doc"], "violations": []})

shutil.rmtree(out, ignore_errors=True)
for topic, topic_groups in sorted(groups.items()):
    os.makedirs(os.path.join(out, topic))
    named = {}
    for group in topic_groups.values():
        n = named.get(group["description"], 0) + 1
        named[group["description"]] = n
        if n > 1:
            group["description"] = f"{group['description']} ({n})"
    json.dump(list(topic_groups.values()), open(os.path.join(out, topic, "cases.json"), "w"))

total = sum(len(g["cases"]) for t in groups.values() for g in t.values())
print(f"{total} cases in {sum(len(t) for t in groups.values())} groups, {len(groups)} topics")
for reason, n in skipped.items():
    print(f"left out for {reason}: {n}")
