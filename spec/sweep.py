import argparse
import hashlib
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
GROUP_QUOTA = 12


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


def build_cell(shape, key, k, j, es, input_shape, params_shape):
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
        data = {"things": [thing]}
        if j != ABSENT:
            data["j"] = j
        if k != ABSENT and key.startswith("$input"):
            data["k"] = k
    else:
        data = [thing]
    if params_shape == "3":
        params = 3
    elif key.startswith("$params"):
        params = {}
        if j != ABSENT:
            params["j"] = j
        if k != ABSENT:
            params["k"] = k
    else:
        params = {}
    return policy, data, params


def has_two_keys(shape):
    return "{key2}" in json.dumps([shape.get("check"), shape.get("from")])


def root_is_dead(key, input_shape, params_shape):
    return (key.startswith("$input") and input_shape == "list") or (key.startswith("$params") and params_shape == "3")


def cells(shapes, only):
    out = []
    for shape in shapes:
        if only and shape["name"] not in only:
            continue
        two = has_two_keys(shape)
        for key in shape["keys"]:
            combos = [(k, "a") for k in KEYS]
            if two:
                combos += [("a", j) for j in KEYS if j != "a"]
            seen = {}
            for (k, j), es, input_shape, params_shape in itertools.product(combos, LISTS, INPUTS, PARAMS):
                dead = root_is_dead(key, input_shape, params_shape)
                shown = {"k": "any" if dead else label(k), "es": "any" if dead else es}
                if two:
                    shown["j"] = "any" if dead else label(j)
                if dead:
                    k, j, es = "a", "a", "two"
                parts = [f"k={shown['k']}"] + ([f"j={shown['j']}"] if two else []) + [f"es={shown['es']}", f"input={input_shape}", f"params={params_shape}"]
                values = " ".join(parts)
                name = f"{shape['name']} [{key}] {values}"
                seen.setdefault(name, {
                    "group": f"{shape['name']} [{key}]",
                    "name": name,
                    "values": values,
                    "id": hashlib.sha1(name.encode()).hexdigest()[:8],
                    "bucket": (shown["k"], shown.get("j")),
                    "rank": (input_shape != "object", params_shape != "3"),
                    "build": (shape, key, k, j, es, input_shape, params_shape),
                })
            out.extend(seen.values())
    ids = [cell["id"] for cell in out]
    if len(set(ids)) != len(ids):
        sys.exit("two cells have the same id")
    return out


def sample(all_cells, limit):
    if len(all_cells) <= limit:
        return sorted(all_cells, key=lambda c: c["name"])
    groups = {}
    for cell in all_cells:
        groups.setdefault(cell["group"], []).append(cell)
    quota = min(GROUP_QUOTA, max(1, limit // len(groups)))
    chosen = []
    for group in groups.values():
        buckets = {}
        for cell in sorted(group, key=lambda c: (c["rank"], c["id"])):
            buckets.setdefault(cell["bucket"], []).append(cell)
        lines = [buckets[b] for b in sorted(buckets, key=str)]
        taken = []
        while len(taken) < quota and any(lines):
            for line in lines:
                if line and len(taken) < quota:
                    taken.append(line.pop(0))
        chosen.extend(taken)
    return sorted(chosen, key=lambda c: c["name"])


def tail(text):
    text = text.strip()
    return text if len(text) <= 600 else "..." + text[-600:]


def run_command(argv, shell, script):
    shown = argv if shell else shlex.join(argv)
    try:
        out = subprocess.run(argv, shell=shell, cwd=ROOT, input=script, capture_output=True, text=True)
    except OSError as error:
        sys.exit(f"cannot run `{shown}`: {error}")
    if out.returncode != 0:
        sys.exit(f"`{shown}` exited with code {out.returncode}: {tail(out.stderr or out.stdout) or 'no output'}")
    return out


def run_rego(opa, ids):
    query = "[object.remove(data.ergo.report(c.input, c.policy, c.params), [\"engine\"]) | some c in data.cases]"
    argv = shlex.split(opa) + ["eval", "-d", "dist/ergo.rego", "-d", os.path.join(WORK, "cases.json"), "--format", "raw", query]
    out = run_command(argv, False, None)
    try:
        reports = json.loads(out.stdout)
    except ValueError:
        sys.exit(f"`{shlex.join(argv)}` printed something that isn't JSON: {tail(out.stdout)}")
    if not isinstance(reports, list) or len(reports) != len(ids):
        sys.exit(f"`{shlex.join(argv)}` answered the wrong number of reports for {len(ids)} cells")
    return [r if isinstance(r, dict) else {"error": f"report is {json.dumps(r)}"} for r in reports]


def run_rust(command, ids):
    script = "\n".join([
        "cd dist/sweep/c",
        "ergo --version > ../version.txt || exit 1",
        "for d in *; do",
        "  ergo report --compact --policy $d/policy.json --input $d/input.json --params $d/params.json > $d/report.json 2> $d/error.txt || {",
        "    code=$?",
        "    echo \"ergo exited with code $code on cell $d: $(cat $d/error.txt)\" >&2",
        "    exit 1",
        "  }",
        "done",
    ])
    run_command(command, True, script)
    with open(os.path.join(WORK, "version.txt")) as handle:
        version = handle.read().strip()
    reports = []
    for cell_id in ids:
        folder = os.path.join(WORK, "c", cell_id)
        with open(os.path.join(folder, "report.json")) as handle:
            text = handle.read().strip()
        if text:
            report = json.loads(text)
        else:
            with open(os.path.join(folder, "error.txt")) as handle:
                report = {"error": handle.read().strip()[:300] or "no output"}
        report.pop("engine", None)
        reports.append(report)
    return version, reports


def rows(report):
    found = {}
    for row in report.get("results", []):
        key = (row.get("requirement"), row.get("check"), json.dumps(row.get("subject"), sort_keys=True))
        found[key] = row
    return found


def short(value):
    text = json.dumps(value, sort_keys=True)
    return text if len(text) <= 160 else text[:157] + "..."


def written_wrong(report):
    return any(r.get("check") == "$well_formed" and not r.get("passed") for r in report.get("results", []))


def differences(rego, rust):
    if rego == rust:
        return []
    if "error" in rego or "error" in rust:
        return [("report", ["error"], rego, rust)]
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


def load_pairs(path):
    with open(path) as handle:
        pairs = json.load(handle)
    built = []
    names = set()
    for pair in pairs:
        if not all(key in pair for key in ("name", "policy", "input")):
            sys.exit(f"{path}: every pair needs a name, a policy and an input")
        if pair["name"] in names:
            sys.exit(f"{path}: two pairs are called {pair['name']}")
        names.add(pair["name"])
        built.append({
            "name": pair["name"],
            "policy": dict(pair["policy"], ergo_spec=spec_version()),
            "input": pair["input"],
            "params": pair.get("params", {}),
            "want": pair.get("want"),
        })
    return built


def says(report, want):
    return any(not r.get("passed") and r.get("message") == want for r in report.get("results", []))


def write_cells(built):
    shutil.rmtree(WORK, ignore_errors=True)
    for cell in built:
        folder = os.path.join(WORK, "c", cell["id"])
        os.makedirs(folder)
        for name in ("policy", "input", "params"):
            with open(os.path.join(folder, name + ".json"), "w") as handle:
                json.dump(cell[name], handle)
    with open(os.path.join(WORK, "cases.json"), "w") as handle:
        json.dump({"cases": [{key: cell[key] for key in ("policy", "input", "params")} for cell in built]}, handle)


def run_pairs(args):
    pairs = load_pairs(args.pairs)
    for i, pair in enumerate(pairs):
        pair["id"] = str(i)
    subprocess.run([os.path.join(ROOT, ".github", "build-ergo.sh")], cwd=ROOT, check=True)
    try:
        write_cells(pairs)
        ids = [pair["id"] for pair in pairs]
        rego = run_rego(args.opa, ids)
        version, rust = run_rust(args.rust, ids)
        print(f"rust engine: {version}")
        differ = 0
        for i, pair in enumerate(pairs):
            found = differences(rego[i], rust[i])
            differ += bool(found)
            wanted = ""
            if pair["want"] is not None:
                wanted = f" | rego {'says' if says(rego[i], pair['want']) else 'does not say'} it, rust {'says' if says(rust[i], pair['want']) else 'does not say'} it"
            if not found and not wanted:
                continue
            print(f"{pair['name']}{' | engines differ' if found else ''}{wanted}")
            for where, fields, left, right in found:
                print(f"  {where} differs in {', '.join(fields)}")
                for field in fields:
                    print(f"    {field}:")
                    print(f"      rego: {short((left or {}).get(field) if fields != ['entry'] else left)}")
                    print(f"      rust: {short((right or {}).get(field) if fields != ['entry'] else right)}")
        print(f"{differ} of {len(pairs)} pairs differ")
    finally:
        shutil.rmtree(WORK, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Run check shapes over a grid of inputs through both engines and print the cells where they differ.")
    parser.add_argument("--pairs", help="run the policy and input pairs in this JSON file instead of the grid and print the ones where the engines differ, and whether each says the pair's want message")
    parser.add_argument("--shape", action="append", help="run only this shape (repeatable)")
    parser.add_argument("--limit", type=int, default=500, help="most cells to run, spread evenly over the shapes (default 500)")
    parser.add_argument("--opa", default="opa", help="command that runs OPA (default: opa)")
    parser.add_argument("--rust", default="sh -s", help="command that reads a shell script on stdin and runs it from the root of the repo with the ergo command on PATH (default: sh -s)")
    parser.add_argument("--list", action="store_true", help="print the shape names and stop")
    args = parser.parse_args()

    if args.pairs:
        run_pairs(args)
        return

    with open(os.path.join(ROOT, "spec", "sweep-shapes.json")) as handle:
        shapes = json.load(handle)["shapes"]
    names = {s["name"] for s in shapes}
    if args.list:
        print("\n".join(sorted(names)))
        return
    for name in args.shape or []:
        if name not in names:
            sys.exit(f"no shape called {name}; --list shows them")

    if args.limit < 1:
        sys.exit("--limit must be 1 or more")

    all_cells = cells(shapes, set(args.shape or []))
    chosen = sample(all_cells, args.limit)
    note = "" if len(chosen) == len(all_cells) else f" (sampled from {len(all_cells)}; raise --limit or pick a --shape for the rest)"
    print(f"running {len(chosen)} cells{note}", file=sys.stderr)

    subprocess.run([os.path.join(ROOT, ".github", "build-ergo.sh")], cwd=ROOT, check=True)
    shutil.rmtree(WORK, ignore_errors=True)
    built = []
    for cell in chosen:
        policy, data, params = build_cell(*cell["build"])
        built.append({"policy": policy, "input": data, "params": params})
        folder = os.path.join(WORK, "c", cell["id"])
        os.makedirs(folder)
        for name, value in (("policy", policy), ("input", data), ("params", params)):
            with open(os.path.join(folder, name + ".json"), "w") as handle:
                json.dump(value, handle)
    with open(os.path.join(WORK, "cases.json"), "w") as handle:
        json.dump({"cases": built}, handle)

    ids = [cell["id"] for cell in chosen]
    rego = run_rego(args.opa, ids)
    version, rust = run_rust(args.rust, ids)
    print(f"rust engine: {version}")

    per_shape = {}
    total = 0
    wrong = [0, 0]
    for i, cell in enumerate(chosen):
        tally = per_shape.setdefault(cell["group"], [0, 0, 0, 0])
        tally[1] += 1
        flags = (written_wrong(rego[i]), written_wrong(rust[i]))
        tally[2] += flags[0]
        tally[3] += flags[1]
        wrong[0] += flags[0]
        wrong[1] += flags[1]
        found = differences(rego[i], rust[i])
        if flags[0] != flags[1] and not found:
            found.append(("report", ["written wrong"], {"written wrong": flags[0]}, {"written wrong": flags[1]}))
        if not found:
            continue
        tally[0] += 1
        total += 1
        print(f"{cell['group']} | {cell['values']} | cell {cell['id']}")
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
    for shape, (differ, ran, wrong_rego, wrong_rust) in per_shape.items():
        print(f"{shape}: {differ} of {ran} differ, written wrong: rego {wrong_rego}, rust {wrong_rust}")
    print(f"written wrong: rego {wrong[0]}, rust {wrong[1]}")
    print(f"{total} of {len(chosen)} cells differ")


if __name__ == "__main__":
    main()
