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

release=""
if [ "${1:-}" = "--release" ]; then
  [ $# -ge 3 ] || { echo "Usage: build-ergo.sh --release VERSION COMMIT [DIR]" >&2; exit 1; }
  release=$2
  commit=$3
  shift 3
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
tmp_body=$(mktemp)
tmp_body_map=$(mktemp)
trap 'rm -f "$tmp_out" "$tmp_map" "$tmp_body" "$tmp_body_map"' EXIT

if [ -z "$release" ]; then
  printf '%s\n' \
    '# DO NOT EDIT. Built by .github/build-ergo.sh from engines/rego/src.' \
    '# Change the parts there, then run the build again. This file is not committed.' \
    '' > "$tmp_out"
else
  case $release in
    *[!0-9.]* | .* | *. | *..*) echo "The release version must be a plain number like 0.6.0, not $release." >&2; exit 1 ;;
  esac
  spec=$(sed -n 's/^_spec := "\(v[0-9][0-9.]*\)"$/\1/p' "$src/shared/basics.rego")
  [ -n "$spec" ] || { echo "$src/shared/basics.rego has no _spec := \"vX.Y\" line." >&2; exit 1; }
  grep -qxF "version := \"$release-dev\"" "$src/shared/basics.rego" || { echo "$src/shared/basics.rego must say version := \"$release-dev\"." >&2; exit 1; }
  epoch=${SOURCE_DATE_EPOCH:-$(date -u +%s)}
  built=$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' \
    "# Ergo $release, the Rego engine. Implements spec $spec." \
    "# Built from commit $commit on $built." \
    "# Project: https://github.com/kosli-dev/ergo" \
    "# Read about it in OPA.md in the project." \
    "# License: Apache-2.0. The notice below holds the license text." \
    "# This is a release file. If you edit your copy, the changes are yours." \
    '' > "$tmp_out"
fi
header_lines=$(wc -l < "$tmp_out" | tr -d ' ')
awk -v n="$header_lines" 'BEGIN { for (i = 0; i < n; i++) print "-" }' > "$tmp_map"

awk -v map="$tmp_body_map" -v head="$src/package.rego" '
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
' "$src/package.rego" $parts > "$tmp_body"

if [ -n "$release" ]; then
  sed "s/^version := \"$release-dev\"$/version := \"$release\"/" "$tmp_body" > "$tmp_body.stamped"
  /bin/mv -f "$tmp_body.stamped" "$tmp_body"
  grep -qxF "version := \"$release\"" "$tmp_body" || { echo "The build did not stamp version := \"$release\"." >&2; exit 1; }
fi
cat "$tmp_body" >> "$tmp_out"
cat "$tmp_body_map" >> "$tmp_map"

/bin/mv -f "$tmp_out" "$out"
/bin/mv -f "$tmp_map" "$map"
