#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/status-block.sh
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT

cat > "$dir/grid.txt" << 'DOC'
running 5440 cells
rust engine: ergo 0.1.0
a-shape [x]: 3 of 10 differ, written wrong: rego 0, rust 0
2919 of 5440 cells differ
type 1 (verdict differs): 2
type 2 (a row's cause differs): 204
type 3 (anything else): 2713

Type 1 cells:

- part-every-if-any [pl.name] | k=missing es=empty | cell c22bbd68
- part-every-if-any [pl.name] | k=missing es=empty | cell 15f2d9c4

Type 2 cells:

- b | cell 1
DOC
cat > "$dir/pairs.txt" << 'DOC'
rust engine: ergo 0.1.0
210 of 307 pairs differ
type 1 (verdict differs): 0
type 2 (a row's cause differs): 50
type 3 (anything else): 160
DOC
cat > "$dir/types.txt" << 'DOC'
## Rust engine: known failures: 579

- type 1 (verdict differs): 0
- type 2 (a row's cause differs): 9
- type 3 (anything else): 570
- by family (type 1 / type 2 / type 3):
  - any_of: 0 / 0 / 1
  - for: 0 / 3 / 173
  - messages: 0 / 0 / 67
  - walks: 0 / 5 / 73
  - sentences: 0 / 0 / 68
  - derived: 0 / 0 / 33
  - subjects: 0 / 0 / 34
  - list_items: 0 / 0 / 45
- violations are not compared; 2 known failures pin them

## ergo.rego: known_differences rows: 13

- type 1 (verdict differs): 0
- type 2 (a row's cause differs): 0
- type 3 (anything else): 13
- by family (type 1 / type 2 / type 3):
  - derived: 0 / 0 / 8
DOC
cat > "$dir/facts.txt" << 'DOC'
## How far the engines are from the spec

### Branch

- lines in `engines/rust/known-failures.txt`: 579
- entries in `spec/OPEN.md`:
  - Where ergo.rego and the Rust engine differ: 19
  - Where both engines differ from a rule: 1
  - Differs from the general rules: 68
  - Differs from the decisions: 25
- spec cases: 3753, failing in the Rust engine: 15.4%

### main

- entries in `spec/OPEN.md`:
  - Where ergo.rego and the Rust engine differ: 1
DOC

out=$dir/out
fail() {
  echo "status-block_test: $1" >&2
  cat "$out" >&2
  exit 1
}
has() {
  grep -qF -- "$1" "$out" || fail "missing: $1"
}

STATUS_DATE=2026-11-23 sh "$script" failure "$dir/grid.txt" "$dir/pairs.txt" "$dir/types.txt" "$dir/facts.txt" > "$out" || fail "should exit 0"
has "### Status on 2026-11-23 (UTC)"
has "Nightly run: failure"
has "Rust engine against the cases: 579 known failures"
has "- type 2 (a row's cause differs): 9"
has "biggest families: for 176, walks 78, sentences 68, messages 67, list_items 45"
has "ergo.rego against the cases: 13 known differences"
has "Engine against engine, grid: 2919 of 5440 cells differ"
has "- type 1 (verdict differs): 2"
has "- part-every-if-any [pl.name] | k=missing es=empty | cell c22bbd68"
has "Engine against engine, fixed pairs: 210 of 307 pairs differ"
has "- Where ergo.rego and the Rust engine differ: 19"
has "- Differs from the decisions: 25"
if grep -qF -- "- b | cell 1" "$out"; then fail "type 2 cells should not be listed"; fi
if grep -q "differ: 1$" "$out"; then fail "only the block of the branch should be read"; fi

STATUS_DATE=2026-11-23 sh "$script" failure "$dir/grid.txt" "$dir/pairs.txt" "$dir/types.txt" "$dir/facts.txt" > "$dir/again" || fail "second run should exit 0"
cmp -s "$out" "$dir/again" || fail "the same inputs should give the same block"

: > "$dir/empty"
STATUS_DATE=2026-11-24 sh "$script" cancelled "$dir/empty" "$dir/empty" "$dir/empty" "$dir/empty" > "$out" || fail "empty inputs should exit 0"
has "Nightly run: cancelled"
has "Engine against engine, grid: not found"

if sh "$script" only-one > "$out" 2>&1; then
  fail "a missing argument should exit non-zero"
fi
echo "status-block_test: ok"
