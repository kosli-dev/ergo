import argparse
import itertools
import json
import os
import random
import shlex
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "dist", "sweep")
ABSENT = "<missing>"

KEYS = [ABSENT, None, "a", 3, True, [], {}]
LISTS = ["empty", "one", "two", "missing", "null", "text"]
INPUTS = ["object", "list"]
PARAMS = ["plain", "3"]


def spec_version():
    with open(os.path.join(ROOT, "engines", "rego", "src", "shared", "basics.rego")) as handle:
        for line in handle:
            if line.startswith("_spec := "):
                return line.split('"')[1]
    sys.exit("engines/rego/src/shared/basics.rego has no _spec line")


def label(value):
    return "missing" if value == ABSENT else json.dumps(value)


def items_for(name, k):
    def item(zz, v):
        made = {"zz": zz, "v": v}
        if k != ABSENT:
            made["k"] = k
        return made

    return {
        "empty": [],
        "one": [item(2, 2)],
        "two": [item(2, 2), item(1, 3)],
        "null": None,
        "text": "s",
    }.get(name, ABSENT)


def expand_all(value, expand):
    if isinstance(value, str):
        return expand(value)
    if isinstance(value, dict):
        return {name: expand_all(inner, expand) for name, inner in value.items()}
    return value


def build_cell(shape, key, k, es, input_shape, params_shape):
    things = "things" if input_shape == "object" else "$input"
    two = key.replace("k", "j") if key.startswith("$") else "j"

    def expand(text):
        return text.replace("{key2}", two).replace("{key}", key).replace("{things}", things)

    from_line = shape.get("from")
    subject = {"from": expand(from_line) if from_line else things, "identified_by": "id"}
    check = shape.get("check", "id exists")
    check = expand_all(check, expand)
    policy = {
        "ergo_spec": spec_version(),
        "subjects": {"thing": subject},
        "requirements": {"s": {"subject": "thing", "checks": {"c": check}}},
    }
    thing = {"id": "t", "m": {"a": 2}}
    if k != ABSENT:
        thing["k"] = k
    items = items_for(es, k)
    if items != ABSENT:
        thing["es"] = items
    if input_shape == "object":
        data = {"things": [thing], "j": "a"}
        if k != ABSENT and key.startswith("$input"):
            data["k"] = k
    else:
        data = [thing]
    if params_shape == "3":
        params = 3
    elif key.startswith("$params"):
        params = {"j": "a"}
        if k != ABSENT:
            params["k"] = k
    else:
        params = {}
    return policy, data, params


def cells(shapes, only):
    out = []
    for shape in shapes:
        if only and shape["name"] not in only:
            continue
        for key in shape["keys"]:
            for k, es, input_shape, params_shape in itertools.product(KEYS, LISTS, INPUTS, PARAMS):
                out.append({
                    "shape": f"{shape['name']} [{key}]",
                    "values": f"k={label(k)} es={es} input={input_shape} params={params_shape}",
                    "build": (shape, key, k, es, input_shape, params_shape),
                })
    return out


def sample(all_cells, limit):
    if len(all_cells) <= limit:
        return all_cells
    groups = {}
    for cell in all_cells:
        groups.setdefault(cell["shape"], []).append(cell)
    quota = max(1, limit // len(groups))
    chosen = []
    for group in groups.values():
        if len(group) <= quota:
            chosen.extend(group)
        else:
            chosen.extend(random.Random(group[0]["shape"]).sample(group, quota))
    return chosen[:limit]


def run_rego(opa, count):
    query = "[object.remove(data.ergo.report(c.input, c.policy, c.params), [\"engine\"]) | some c in data.cases]"
    out = subprocess.run(
        shlex.split(opa) + ["eval", "-d", "dist/ergo.rego", "-d", os.path.join(WORK, "cases.json"), "--format", "raw", query],
        cwd=ROOT, capture_output=True, text=True,
    )
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    reports = json.loads(out.stdout)
    if len(reports) != count:
        sys.exit(f"opa answered {len(reports)} reports for {count} cells")
    return reports


def run_rust(command, count):
    script = "\n".join([
        "cd dist/sweep/c",
        "for d in *; do",
        "  ergo report --compact --policy $d/policy.json --input $d/input.json --params $d/params.json > $d/report.json 2> $d/error.txt",
        "done",
    ])
    out = subprocess.run(command, shell=True, cwd=ROOT, input=script, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    reports = []
    for i in range(count):
        folder = os.path.join(WORK, "c", f"{i:05d}")
        with open(os.path.join(folder, "report.json")) as handle:
            text = handle.read().strip()
        if text:
            report = json.loads(text)
        else:
            with open(os.path.join(folder, "error.txt")) as handle:
                report = {"error": handle.read().strip()[:300]}
        report.pop("engine", None)
        reports.append(report)
    return reports


def rows(report):
    found = {}
    for row in report.get("results", []):
        key = (row.get("requirement"), row.get("check"), json.dumps(row.get("subject"), sort_keys=True))
        found[key] = row
    return found


def short(value):
    text = json.dumps(value, sort_keys=True)
    return text if len(text) <= 160 else text[:157] + "..."


def differences(rego, rust):
    if rego == rust:
        return []
    found = []
    a, b = rows(rego), rows(rust)
    for key in sorted(set(a) | set(b)):
        if a.get(key) == b.get(key):
            continue
        left, right = a.get(key), b.get(key)
        fields = sorted(f for f in set(left or {}) | set(right or {}) if (left or {}).get(f) != (right or {}).get(f))
        if left is None or right is None:
            fields = ["entry"]
        found.append((f"{key[0]}/{key[1]}", fields, left, right))
    top = sorted(f for f in set(rego) | set(rust) if f != "results" and rego.get(f) != rust.get(f))
    if top and not found:
        found.append(("report", top, {f: rego.get(f) for f in top}, {f: rust.get(f) for f in top}))
    return found


def main():
    parser = argparse.ArgumentParser(description="Run check shapes over a grid of inputs through both engines and print the cells where they differ.")
    parser.add_argument("--shape", action="append", help="run only this shape (repeatable)")
    parser.add_argument("--limit", type=int, default=500, help="most cells to run, spread evenly over the shapes (default 500)")
    parser.add_argument("--opa", default="opa", help="command that runs OPA (default: opa)")
    parser.add_argument("--rust", default="sh -s", help="command that reads a shell script on stdin and runs it from the root of the repo with the ergo command on PATH (default: sh -s)")
    parser.add_argument("--list", action="store_true", help="print the shape names and stop")
    args = parser.parse_args()

    with open(os.path.join(ROOT, "spec", "sweep-shapes.json")) as handle:
        shapes = json.load(handle)["shapes"]
    names = {s["name"] for s in shapes}
    if args.list:
        print("\n".join(sorted(names)))
        return
    for name in args.shape or []:
        if name not in names:
            sys.exit(f"no shape called {name}; --list shows them")

    all_cells = cells(shapes, set(args.shape or []))
    chosen = sample(all_cells, args.limit)
    note = "" if len(chosen) == len(all_cells) else f" (sampled from {len(all_cells)}; raise --limit or pick a --shape for the rest)"
    print(f"running {len(chosen)} cells{note}", file=sys.stderr)

    subprocess.run([os.path.join(ROOT, ".github", "build-ergo.sh")], cwd=ROOT, check=True)
    shutil.rmtree(WORK, ignore_errors=True)
    built = []
    for i, cell in enumerate(chosen):
        policy, data, params = build_cell(*cell["build"])
        built.append({"policy": policy, "input": data, "params": params})
        folder = os.path.join(WORK, "c", f"{i:05d}")
        os.makedirs(folder)
        for name, value in (("policy", policy), ("input", data), ("params", params)):
            with open(os.path.join(folder, name + ".json"), "w") as handle:
                json.dump(value, handle)
    with open(os.path.join(WORK, "cases.json"), "w") as handle:
        json.dump({"cases": built}, handle)

    rego = run_rego(args.opa, len(chosen))
    rust = run_rust(args.rust, len(chosen))

    per_shape = {}
    total = 0
    for i, cell in enumerate(chosen):
        tally = per_shape.setdefault(cell["shape"], [0, 0, 0])
        tally[1] += 1
        if any(r.get("check") == "$well_formed" and not r.get("passed") for r in rego[i].get("results", [])):
            tally[2] += 1
        found = differences(rego[i], rust[i])
        if not found:
            continue
        tally[0] += 1
        total += 1
        print(f"{cell['shape']} | {cell['values']} | cell {i:05d}")
        for where, fields, left, right in found:
            print(f"  {where} differs in {', '.join(fields)}")
            if fields == ["entry"]:
                print(f"    rego: {short(left)}")
                print(f"    rust: {short(right)}")
                continue
            for field in fields:
                print(f"    {field}:")
                print(f"      rego: {short((left or {}).get(field))}")
                print(f"      rust: {short((right or {}).get(field))}")
    print()
    for shape, (differ, ran, wrong) in per_shape.items():
        print(f"{shape}: {differ} of {ran} differ, {wrong} written wrong")
    print(f"{total} of {len(chosen)} cells differ")


if __name__ == "__main__":
    main()
