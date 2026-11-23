#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/sync-facts.sh
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
repo=$dir/repo
mkdir -p "$repo/.github" "$repo/engines/rust" "$repo/engines/rego/tests" "$repo/spec/cases/t" "$repo/spec/cases/u"
cp "$script" "$repo/.github/sync-facts.sh"
cd "$repo"
git init -q
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false

printf '[{"description":"g","cases":[{"description":"a"},{"description":"b"}]}]\n' > spec/cases/t/cases.json
printf '[{"description":"g","cases":[{"description":"x"}]},{"description":"h","cases":[{"description":"y"},{"description":"z"}]}]\n' > spec/cases/u/cases.json
printf 't / g / a\nu / h / y\n' > engines/rust/known-failures.txt
printf 'package spec_test\n\nknown_differences := {\n\t# not a row\n\t"t / g / a",\n}\n' > engines/rego/tests/spec_test.rego
cat > spec/OPEN.md << 'DOC'
# Open questions

## Where ergo.rego and the Rust engine differ

- plain text, not an entry
- **One.** Text.
- **Two.** Text.

## Where both engines differ from a rule

- **One.** Text.

## Differs from the general rules

- **One.** Text.

## Differs from the decisions

### Left for a later PR

- **One.** Text.
- **Two.** Text.
DOC
git add -A
git commit -q -m base
git branch -M main
git checkout -q -b feature

printf '[{"description":"g","cases":[{"description":"a"},{"description":"b"},{"description":"c"}]}]\n' > spec/cases/t/cases.json
printf 't / g / a\nt / g / c\nu / h / y\nu / h / z\n' > engines/rust/known-failures.txt
printf 'package spec_test\n\nknown_differences := {\n\t# not a row\n\t"t / g / a",\n\t"t / g / c",\n}\n' > engines/rego/tests/spec_test.rego
python3 - << 'PY'
text = open("spec/OPEN.md").read().replace("- **Two.** Text.\n\n## Where both", "- **Two.** Text.\n- **Three.** Text.\n\n## Where both")
open("spec/OPEN.md", "w").write(text)
PY
git add -A
git commit -q -m branch

expect() {
  expected=$1
  out=$(sh .github/sync-facts.sh main)
  if [ "$out" != "$expected" ]; then
    echo "sync-facts.sh should print:" >&2
    echo "$expected" >&2
    echo "and printed:" >&2
    echo "$out" >&2
    exit 1
  fi
}

expect "## How far the engines are from the spec

### Branch

- lines in \`engines/rust/known-failures.txt\`: 4
  - t: 2
  - u: 2
- \`known_differences\` rows in \`engines/rego/tests/spec_test.rego\`: 2
- entries in \`spec/OPEN.md\`:
  - Where ergo.rego and the Rust engine differ: 3
  - Where both engines differ from a rule: 1
  - Differs from the general rules: 1
  - Differs from the decisions: 2
- spec cases: 6, failing in the Rust engine: 66.7%

### main

- lines in \`engines/rust/known-failures.txt\`: 2
  - t: 1
  - u: 1
- \`known_differences\` rows in \`engines/rego/tests/spec_test.rego\`: 1
- entries in \`spec/OPEN.md\`:
  - Where ergo.rego and the Rust engine differ: 2
  - Where both engines differ from a rule: 1
  - Differs from the general rules: 1
  - Differs from the decisions: 2
- spec cases: 5, failing in the Rust engine: 40.0%

### Change against main

- known failures: +2
  - t: +1
  - u: +1
- \`known_differences\` rows: +1
- Where ergo.rego and the Rust engine differ: +1
- Where both engines differ from a rule: 0
- Differs from the general rules: 0
- Differs from the decisions: 0
- spec cases: +1
- failing share: 40.0% to 66.7%"

sh .github/sync-facts.sh main > /dev/null
echo "exits 0 on a change"

git checkout -q -b same main
sh .github/sync-facts.sh main | grep -q -- '- known failures: 0'
sh .github/sync-facts.sh main | grep -q -- '- spec cases: 0'
if sh .github/sync-facts.sh main | grep -q -- ': +'; then
  echo "a branch with no change should show no change" >&2
  exit 1
fi

git checkout -q -b gone main
grep -v 'Differs from the general rules' spec/OPEN.md > spec/OPEN.new
/bin/mv -f spec/OPEN.new spec/OPEN.md
out=$(sh .github/sync-facts.sh main)
echo "$out" | grep -q -- '  - Differs from the general rules: section not found'
echo "$out" | grep -q -- '- Differs from the general rules: n/a'

if sh .github/sync-facts.sh a b 2> /dev/null; then
  echo "two arguments should be a usage error" >&2
  exit 1
fi
if sh .github/sync-facts.sh nope 2> /dev/null; then
  echo "an unknown base should be an error" >&2
  exit 1
fi
