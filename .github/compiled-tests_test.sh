#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
real=$(command -v opa)

fake() {
  cat >"$dir/$1" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = parse ]; then
  exec "$real" "\$@"
fi
$2
FAKE
  chmod +x "$dir/$1"
}

fake counting 'pattern=${@: -1}
echo "${#pattern}" >>"'"$dir"'/lengths"
count=$(tr "|" "\n" <<<"$pattern" | wc -l | tr -d " ")
echo "PASS: $count/$count"'
fake skipping 'echo "PASS: 1/1"'
fake failing 'echo "FAIL: 1/2"; exit 2'

total=$(.github/tests.sh | wc -l | tr -d ' ')
expected=$(((total + 39) / 40))
[ "$expected" -gt 1 ] || { echo "expected more than one batch"; exit 1; }

out=$(BATCH_SIZE=40 .github/compiled-tests.sh "$dir/counting")
[ "$(wc -l <"$dir/lengths" | tr -d ' ')" -eq "$expected" ] || { echo "expected $expected batches"; exit 1; }
grep -qx "Ran $total of $total tests compiled" <<<"$out" || { tail -3 <<<"$out"; exit 1; }
longest=$(sort -n "$dir/lengths" | tail -1)
[ "$longest" -lt 8000 ] || { echo "a pattern is $longest characters"; exit 1; }

if BATCH_SIZE=40 .github/compiled-tests.sh "$dir/skipping" >/dev/null 2>&1; then
  echo "a skipped test went unnoticed"
  exit 1
fi

if BATCH_SIZE=40 .github/compiled-tests.sh "$dir/failing" >/dev/null 2>&1; then
  echo "a failing batch went unnoticed"
  exit 1
fi

echo "ok"
