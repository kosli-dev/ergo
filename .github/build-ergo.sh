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
[ -f "$src/package.rego" ] || { echo "No $src/package.rego in $PWD." >&2; exit 1; }
parts=$(find "$src" -name '*.rego' ! -path "$src/package.rego" | LC_ALL=C sort)
[ -n "$parts" ] || { echo "No parts in $src." >&2; exit 1; }

mkdir -p dist
tmp_out=$(mktemp)
tmp_map=$(mktemp)
trap 'rm -f "$tmp_out" "$tmp_map"' EXIT

awk -v map="$tmp_map" -v head="$src/package.rego" '
  function emit(line, from) { print line; print from > map }
  FNR == 1 && NR > 1 { emit("", "-") }
  FILENAME == head { emit($0, FILENAME ":" FNR); next }
  FNR == 1 && $0 != "package ergo" { bad = FILENAME ": line 1 must be \"package ergo\""; exit 1 }
  FNR == 2 && $0 != "" { bad = FILENAME ": line 2 must be empty"; exit 1 }
  FNR == 3 && $0 != "import rego.v1" { bad = FILENAME ": line 3 must be \"import rego.v1\""; exit 1 }
  FNR == 4 && $0 != "" { bad = FILENAME ": line 4 must be empty"; exit 1 }
  FNR <= 4 { next }
  $0 ~ /^(package|import) / { bad = FILENAME ":" FNR ": only lines 1 and 3 may say package or import"; exit 1 }
  { emit($0, FILENAME ":" FNR) }
  END { if (bad != "") { print bad > "/dev/stderr"; exit 1 } }
' "$src/package.rego" $parts > "$tmp_out"

/bin/cp -f "$tmp_out" "$out"
/bin/cp -f "$tmp_map" "$map"
