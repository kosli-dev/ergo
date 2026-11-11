#!/bin/sh
set -eu

src=engines/rego/src
out=dist/ergo.rego
map=dist/ergo.rego.map

if [ "${1:-}" = "where" ]; then
  cd "${2:-$(dirname "$0")/..}"
  [ -f "$map" ] || { echo "No $map. Run .github/build-ergo.sh first." >&2; exit 1; }
  awk -v out="$out" '
    NR == FNR { at[FNR] = $0; next }
    index($0, out ":") == 1 { row = substr($0, length(out) + 2); if (row in at) { print at[row]; next } }
    { print }
  ' "$map" -
  exit 0
fi

cd "${1:-$(dirname "$0")/..}"
/bin/rm -f "$out" "$map"
[ -f "$src/package.rego" ] || { echo "No $src/package.rego in $PWD." >&2; exit 1; }
parts=$(find "$src" -name '*.rego' ! -path "$src/package.rego" | LC_ALL=C sort)
[ -n "$parts" ] || { echo "No parts in $src." >&2; exit 1; }
spaced=$(printf '%s\n' "$parts" | grep '[[:blank:]]' | head -n 1 || true)
[ -z "$spaced" ] || { echo "A part path has a space in it: $spaced" >&2; exit 1; }
for part in $parts; do
  [ -s "$part" ] || { echo "$part is empty." >&2; exit 1; }
done

awk -v file="$src/package.rego" '
  /^[[:space:]]*package([[:space:]]|$)/ { if ($0 == "package ergo") packages++; else { bad = file ":" FNR ": the only package line must be \"package ergo\""; exit 1 } }
  /^[[:space:]]*import([[:space:]]|$)/ { if ($0 == "import rego.v1") imports++; else { bad = file ":" FNR ": the only import line must be \"import rego.v1\""; exit 1 } }
  END {
    if (bad == "" && packages != 1) bad = file ": must have exactly one \"package ergo\" line"
    if (bad == "" && imports != 1) bad = file ": must have exactly one \"import rego.v1\" line"
    if (bad != "") { print bad > "/dev/stderr"; exit 1 }
  }
' "$src/package.rego"

mkdir -p dist
tmp_out=$(mktemp)
tmp_map=$(mktemp)
trap 'rm -f "$tmp_out" "$tmp_map"' EXIT

awk -v map="$tmp_map" -v head="$src/package.rego" '
  function emit(line, from) { print line; print from > map }
  function fail(msg) { bad = msg; exit 1 }
  function short(name) { return name ": must start with package ergo, an empty line, import rego.v1 and an empty line" }
  FNR == 1 && NR > 1 { if (last != head && lines < 4) fail(short(last)); emit("", "-") }
  FNR == 1 { last = FILENAME }
  { lines = FNR }
  FILENAME == head { emit($0, FILENAME ":" FNR); next }
  FNR == 1 && $0 != "package ergo" { fail(FILENAME ": line 1 must be \"package ergo\"") }
  FNR == 2 && $0 != "" { fail(FILENAME ": line 2 must be empty") }
  FNR == 3 && $0 != "import rego.v1" { fail(FILENAME ": line 3 must be \"import rego.v1\"") }
  FNR == 4 && $0 != "" { fail(FILENAME ": line 4 must be empty") }
  FNR <= 4 { next }
  $0 ~ /^[[:space:]]*(package|import)([[:space:]]|$)/ { fail(FILENAME ":" FNR ": only lines 1 and 3 may say package or import") }
  { emit($0, FILENAME ":" FNR) }
  END {
    if (bad == "" && last != head && lines < 4) bad = short(last)
    if (bad != "") { print bad > "/dev/stderr"; exit 1 }
  }
' "$src/package.rego" $parts > "$tmp_out"

/bin/mv -f "$tmp_out" "$out"
/bin/mv -f "$tmp_map" "$map"
