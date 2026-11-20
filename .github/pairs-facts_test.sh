#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/pairs-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

cat > "$dir/pairs.json" <<'JSON'
[
 {"name": "same", "policy": {}, "input": {}, "want": "m1"},
 {"name": "fixed", "policy": {}, "input": {}, "want": "m2"},
 {"name": "broken", "policy": {}, "input": {}, "want": "m3"},
 {"name": "apart", "policy": {}, "input": {}},
 {"name": "quiet", "policy": {}, "input": {}}
]
JSON

row() {
  printf '{"requirement":"r","check":"c","subject":"t","passed":false,"message":"%s"}' "$1"
}
report() {
  printf '{"results":[%s]}' "$(row "$1")"
}
five() {
  printf '[%s,%s,%s,%s,%s]' "$(report "$1")" "$(report "$2")" "$(report "$3")" "$(report "$4")" "$(report "$5")"
}

five m1 m2 m3 p q > "$dir/rego.json"
five m1 m2 m3 z q > "$dir/head.json"
five m1 old m3 z q > "$dir/base-toward.json"
five m1 m2 m3 p q > "$dir/base-away.json"
five m1 x m3 p q > "$dir/head-broken.json"

run() {
  PAIRS_FACTS_PAIRS=$dir/pairs.json PAIRS_FACTS_REGO=$dir/rego.json \
    PAIRS_FACTS_RUST=${2:-$dir/head.json} PAIRS_FACTS_BASE_RUST=$1 \
    sh "$script" base
}

expect() {
  out=$(run "$1")
  if [ "$out" != "$2" ]; then
    echo "pairs-facts.sh should print:" >&2
    echo "$2" >&2
    echo "and printed:" >&2
    echo "$out" >&2
    exit 1
  fi
}

echo "pairs-facts.sh counts differences and wants, and lists a pair whose Rust output moved toward Rego and its want"
expect "$dir/base-toward.json" "## Pairs

1 of 5 pairs differ between Rego and Rust.

Pairs that say their want message: Rego 3 of 3, Rust 3 of 3.

Rust output changed on 1 pair between base and the working tree.

- fixed: old -> m2 (Rust equals Rego: yes, says want: yes)"

echo "pairs-facts.sh puts a pair that moved away from Rego in capitals first"
expect "$dir/base-away.json" "PAIRS THAT MOVED AWAY FROM REGO OR FROM THEIR WANT: 1

- apart: p -> z

## Pairs

1 of 5 pairs differ between Rego and Rust.

Pairs that say their want message: Rego 3 of 3, Rust 3 of 3.

Rust output changed on 1 pair between base and the working tree.

- apart: p -> z (Rust equals Rego: no)"

echo "pairs-facts.sh puts a pair that stopped saying its want in capitals first"
out=$(run "$dir/base-away.json" "$dir/head-broken.json")
case $out in
  "PAIRS THAT MOVED AWAY FROM REGO OR FROM THEIR WANT: 1
"*) ;;
  *) echo "pairs-facts.sh should start with the capitals line, and printed: $out" >&2; exit 1 ;;
esac

echo "pairs-facts.sh says when no Rust output changed"
out=$(PAIRS_FACTS_PAIRS=$dir/pairs.json PAIRS_FACTS_REGO=$dir/rego.json PAIRS_FACTS_RUST=$dir/head.json PAIRS_FACTS_BASE_RUST=$dir/head.json sh "$script" base)
case $out in
  *"No pair's Rust output changed between base and the working tree."*) ;;
  *) echo "pairs-facts.sh should say no pair changed, and printed: $out" >&2; exit 1 ;;
esac
