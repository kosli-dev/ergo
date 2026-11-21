#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/matrix-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

cat > "$dir/pairs.json" <<'JSON'
[
 {"name": "same", "policy": {}, "input": {}},
 {"name": "passes_now", "policy": {}, "input": {}},
 {"name": "cause_moved", "policy": {}, "input": {}},
 {"name": "always_lower", "policy": {}, "input": {}},
 {"name": "fixed", "policy": {}, "input": {}},
 {"name": "higher", "policy": {}, "input": {}}
]
JSON

row() {
  if [ "$1" = satisfied ]; then
    printf '{"requirement":"r","check":"c","subject":"t","passed":true,"cause":"satisfied"}'
  else
    printf '{"requirement":"r","check":"c","subject":"t","passed":false,"cause":"%s"}' "$1"
  fi
}
report() {
  printf '{"results":[%s]}' "$(row "$1")"
}
six() {
  printf '[%s,%s,%s,%s,%s,%s]' "$(report "$1")" "$(report "$2")" "$(report "$3")" "$(report "$4")" "$(report "$5")" "$(report "$6")"
}

six value value absent absent absent absent > "$dir/rego.json"
six value satisfied value value absent unusable > "$dir/head.json"
six value value absent value value absent > "$dir/base.json"

run() {
  MATRIX_FACTS_PAIRS=$dir/pairs.json MATRIX_FACTS_REGO=$dir/rego.json \
    MATRIX_FACTS_RUST=$1 MATRIX_FACTS_BASE_RUST=$2 sh "$script" matrix-a base
}

expect() {
  out=$(run "$1" "$2")
  if [ "$out" != "$3" ]; then
    echo "matrix-facts.sh should print:" >&2
    echo "$3" >&2
    echo "and printed:" >&2
    echo "$out" >&2
    exit 1
  fi
}

echo "matrix-facts.sh lists the pairs that got worse than the base and the Rust causes that are lower than Rego's"
expect "$dir/head.json" "$dir/base.json" "## Matrix matrix-a

PAIRS WORSE THAN base: 3

- passes_now: r/c: base value, working tree satisfied, Rego value
- cause_moved: r/c: base absent, working tree value, Rego absent
- higher: r/c: base absent, working tree unusable, Rego absent

RUST CAUSES LOWER THAN REGO'S: 2

- cause_moved: r/c: Rust value, Rego absent
- always_lower: r/c: Rust value, Rego absent (already on base)"

echo "matrix-facts.sh says when nothing got worse and no cause is lower"
out=$(MATRIX_FACTS_PAIRS=$dir/pairs.json MATRIX_FACTS_REGO=$dir/rego.json MATRIX_FACTS_RUST=$dir/rego.json MATRIX_FACTS_BASE_RUST=$dir/base.json sh "$script" matrix-a base)
expect_out="## Matrix matrix-a

No pair is worse than base.

No Rust cause is lower than Rego's."
if [ "$out" != "$expect_out" ]; then
  echo "matrix-facts.sh should say nothing is worse, and printed: $out" >&2
  exit 1
fi

echo "matrix-facts.sh refuses a generator that does not exist"
if sh "$script" nothing-here > /dev/null 2>&1; then
  echo "matrix-facts.sh should fail for an unknown generator" >&2
  exit 1
fi
