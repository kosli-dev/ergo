#!/bin/sh
set -eu
if [ $# -gt 1 ]; then
  echo "usage: mutants-facts.sh [BASE]" >&2
  exit 2
fi
base=${1:-origin/main}
cap=${MUTANTS_FACTS_TIMEOUT:-900}
per=${MUTANTS_FACTS_MUTANT_TIMEOUT:-120}
cargo=${MUTANTS_FACTS_CARGO:-cargo}
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d)
trap '/bin/rm -rf "$work"' EXIT

git -C "$root" diff -U0 --relative=engines/rust "$base...HEAD" -- 'engines/rust/*.rs' ':(exclude)*/tests.rs' ':(exclude)*/tests/*' > "$work/diff"
if [ ! -s "$work/diff" ]; then
  echo "No line of Rust source changed, so there is nothing to mutate."
  exit 0
fi

if [ -z "${MUTANTS_FACTS_CARGO:-}" ]; then
  ASDF_RUST_VERSION=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$root/engines/rust/rust-toolchain.toml")
  export ASDF_RUST_VERSION
fi

cd "$root/engines/rust"
"$cargo" mutants --workspace --in-diff "$work/diff" --output "$work/out" --timeout "$per" --minimum-test-timeout 20 -j 2 > "$work/log" 2>&1 &
pid=$!
waited=0
stopped=
while kill -0 "$pid" 2> /dev/null; do
  if [ "$waited" -ge "$cap" ]; then
    kill "$pid" 2> /dev/null || true
    stopped=1
    break
  fi
  sleep 1
  waited=$((waited + 1))
done
status=0
wait "$pid" 2> /dev/null || status=$?

if [ -z "$stopped" ] && [ "$status" -ne 0 ] && [ "$status" -ne 2 ] && [ "$status" -ne 3 ]; then
  echo "cargo-mutants failed with status $status:" >&2
  tail -n 20 "$work/log" >&2
  exit 1
fi

found=$work/out/mutants.out
count() {
  if [ -f "$found/$1.txt" ]; then
    wc -l < "$found/$1.txt" | tr -d ' '
  else
    echo 0
  fi
}

echo "| outcome  | mutants |"
echo "| -------- | ------- |"
echo "| caught   | $(count caught) |"
echo "| missed   | $(count missed) |"
echo "| unviable | $(count unviable) |"
echo "| timeout  | $(count timeout) |"
if [ -n "$stopped" ]; then
  echo
  echo "Stopped after $cap seconds, so the counts cover only the mutants that ran."
fi
if [ -s "$found/missed.txt" ]; then
  echo
  echo "Missed mutants, which no test notices:"
  echo
  sed 's/^/- /' "$found/missed.txt"
fi
