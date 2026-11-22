#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/property-check.py
root=$(git -C "$here" rev-parse --show-toplevel)
head=$(git -C "$root" rev-parse HEAD)
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT

cat > "$dir/fake.py" <<'PY'
import json
import os
import sys

if sys.argv[1] == "--version":
    print("ergo 0.0.0 (commit " + os.environ["FAKE_COMMIT"] + ")")
    sys.exit(0)
args = dict(zip(sys.argv[2::2], sys.argv[3::2]))
policy = json.load(open(args["--policy"]))
data = json.load(open(args["--input"]))
order = os.environ.get("FAKE_ORDER")
results = []
for requirement in policy["requirements"].values():
    problems = {}
    for name, check in requirement["checks"].items():
        if "for" not in check:
            problem = "item 1 of es: z" + name + " is missing"
            if order == "same":
                problem += "; item 1 of es: zshared is missing"
            problems[check["assert"]] = problem
    for name, check in requirement["checks"].items():
        said = os.environ.get("FAKE_MESSAGE", "")
        if order:
            sentences = check["assert"] if isinstance(check["assert"], list) else [check["assert"]]
            if order == "reversed":
                sentences = sentences[::-1]
            said = "; ".join(problems[x] for x in sentences if x in problems)
        for subject in data["things"]:
            results.append({"requirement": "r", "check": name, "subject": {"id": subject["id"]},
                            "passed": os.environ.get("FAKE_PASSED") == "1", "cause": "satisfied", "message": said})
print(json.dumps({"results": results}))
PY
printf '#!/bin/sh\nexec python3 %s "$@"\n' "$dir/fake.py" > "$dir/ergo"
chmod +x "$dir/ergo"

cat > "$dir/fake.rego" <<'REGO'
package ergo

import rego.v1

report(inp, pol, _) := {"results": [{"requirement": "r", "check": name, "subject": {"id": subject.id}, "passed": false, "cause": "absent", "message": ""} |
	some requirement in pol.requirements
	some name, _ in requirement.checks
	some subject in inp.things
]}
REGO

run() {
  FAKE_COMMIT=${FAKE_COMMIT:-$head} python3 "$tool" run --out "$dir/out" --main-bin "$dir/ergo" --branch-bin "$dir/ergo" --main-tree "$root" --branch-tree "$root" --rego "$dir/fake.rego" "$@"
}

echo "property-check.py runs a few probes and finds nothing when both builds agree with the Rego engine"
FAKE_PASSED=0 run --probes 30 > "$dir/first.txt"
grep -q "^seed 1: 30 probes {}" "$dir/first.txt" || { echo "unexpected output: $(cat "$dir/first.txt")" >&2; exit 1; }

echo "property-check.py gives the same output twice for the same seed"
FAKE_PASSED=0 run --probes 30 > "$dir/second.txt"
cmp "$dir/first.txt" "$dir/second.txt"

echo "property-check.py flags a pass where the Rego engine fails"
FAKE_PASSED=1 run --probes 30 > "$dir/flag.txt"
grep -q "PASS_WHERE_REGO_FAILS" "$dir/flag.txt" || { echo "no flag: $(cat "$dir/flag.txt")" >&2; exit 1; }

echo "property-check.py refuses a binary built from another commit"
if out=$(FAKE_COMMIT=0000000000000000000000000000000000000000 run --probes 30 2>&1); then
  echo "property-check.py should refuse a stale binary, and passed" >&2
  exit 1
fi
case $out in
  *"was built from commit"*) ;;
  *) echo "property-check.py should say which commit the binary was built from, and said: $out" >&2; exit 1 ;;
esac

echo "property-check.py says what is missing"
if out=$(python3 "$tool" run 2>&1); then
  echo "property-check.py should fail without binaries, and passed" >&2
  exit 1
fi
case $out in
  *"--main-bin"*) ;;
  *) echo "property-check.py should name --main-bin, and said: $out" >&2; exit 1 ;;
esac

echo "property-check.py shows the rows of a flag"
FAKE_PASSED=1 run --probes 30 > /dev/null
python3 "$tool" show --out "$dir/out" PASS_WHERE_REGO_FAILS | grep -q "^## "

echo "property-check.py makes another policy for another seed"
FAKE_PASSED=0 run --probes 30 --seed 2 --out "$dir/out2" > "$dir/seed2.txt"
grep -q "^seed 2: " "$dir/seed2.txt"
if cmp -s "$dir/out/pol.json" "$dir/out2/pol.json"; then
  echo "seeds 1 and 2 made the same policy" >&2
  exit 1
fi

echo "property-check.py flags a problem said twice"
FAKE_PASSED=0 FAKE_MESSAGE="x; x" run --probes 30 --out "$dir/out3" > "$dir/twice.txt"
grep -q "SAID_TWICE" "$dir/twice.txt" || { echo "no flag: $(cat "$dir/twice.txt")" >&2; exit 1; }

echo "property-check.py doesn't flag sentences that say one problem between them, in the order they are written"
FAKE_PASSED=0 FAKE_ORDER=same run --probes 600 --out "$dir/same" > "$dir/same.txt"
if grep -q "ORDER_FREE" "$dir/same.txt"; then
  echo "flagged: $(cat "$dir/same.txt")" >&2
  exit 1
fi

echo "property-check.py still flags problems that come in another order from the sentences"
FAKE_PASSED=0 FAKE_ORDER=reversed run --probes 600 --out "$dir/reversed" > "$dir/reversed.txt"
grep -q "ORDER_FREE" "$dir/reversed.txt" || { echo "no flag: $(cat "$dir/reversed.txt")" >&2; exit 1; }

echo "property-check.py lists the rows that gained a flag between two runs"
FAKE_PASSED=0 run --probes 30 --out "$dir/before" > /dev/null
FAKE_PASSED=1 run --probes 30 --out "$dir/after" > /dev/null
python3 "$tool" new "$dir/before" "$dir/after" | grep -q "^== PASS_WHERE_REGO_FAILS: [1-9]"
python3 "$tool" new "$dir/before" "$dir/before" | grep -q "no row gained a flag"

echo "property-check.py counts the probes it covered"
python3 "$tool" cover "$dir/before" | grep -q "probes$"

echo "property-check.py compares the two builds row by row"
FAKE_COMMIT=$head python3 "$tool" order "$dir/before" --main-bin "$dir/ergo" --branch-bin "$dir/ergo" --main-tree "$root" --branch-tree "$root" | grep -q "rows$"

echo "property-check.py answers a missing command or tag in one short line"
for args in "" "show"; do
  out=$(python3 "$tool" $args 2>&1 || true)
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || { echo "expected one line for '$args', got: $out" >&2; exit 1; }
  case $out in
    *"see --help"*) ;;
    *) echo "expected 'see --help' for '$args', got: $out" >&2; exit 1 ;;
  esac
done
