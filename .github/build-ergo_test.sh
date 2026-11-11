#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/build-ergo.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p engines/rego/src/b engines/rego/src/a
printf '# License\n\npackage ergo\n\nimport rego.v1\n' > engines/rego/src/package.rego
printf 'package ergo\n\nimport rego.v1\n\nb := 2\n' > engines/rego/src/b/two.rego
printf 'package ergo\n\nimport rego.v1\n\na := 1\n\nc := 3\n' > engines/rego/src/a/one.rego

echo "build-ergo.sh puts package.rego first, then each part sorted by path, without its package and import lines"
sh "$script" "$dir"
expected='# DO NOT EDIT. Built by .github/build-ergo.sh from engines/rego/src.
# Change the parts there, then run the build again. This file is not committed.

# License

package ergo

import rego.v1

a := 1

c := 3

b := 2'
[ "$(cat dist/ergo.rego)" = "$expected" ] || fail "dist/ergo.rego should be:
$expected
and is:
$(cat dist/ergo.rego)"

echo "build-ergo.sh gives the same bytes when it builds twice"
cp dist/ergo.rego first.rego
sh "$script" "$dir"
cmp -s first.rego dist/ergo.rego || fail "two builds gave different files"

every_line_maps() {
  kind=$1
  total=$(wc -l < dist/ergo.rego | tr -d ' ')
  rows=$(wc -l < dist/ergo.rego.map | tr -d ' ')
  [ "$total" = "$rows" ] || fail "the $kind map has $rows rows for $total lines"
  n=1
  while [ "$n" -le "$total" ]; do
    mapped=$(printf 'dist/ergo.rego:%s\n' "$n" | sh "$script" where "$dir")
    case $mapped in
      -) ;;
      *:*)
        file=${mapped%:*}
        row=${mapped##*:}
        want=$(sed -n "${n}p" dist/ergo.rego)
        got=$(sed -n "${row}p" "$file")
        if [ "$want" != "$got" ]; then
          case $want in
            'version := '*) ;;
            *) fail "$kind line $n says \"$want\" and its part $mapped says \"$got\"" ;;
          esac
        fi ;;
    esac
    n=$((n + 1))
  done
}

echo "every line of the default build maps to the same line of its part"
every_line_maps default

echo "build-ergo.sh where maps a line of dist/ergo.rego back to its part, and leaves other lines alone"
out=$(printf 'dist/ergo.rego:4\ndist/ergo.rego:12\ndist/ergo.rego:14\nother.rego:4\n' | sh "$script" where "$dir")
expected='engines/rego/src/package.rego:1
engines/rego/src/a/one.rego:7
engines/rego/src/b/two.rego:5
other.rego:4'
[ "$out" = "$expected" ] || fail "where should print:
$expected
and printed:
$out"

mkdir -p engines/rego/src/shared
printf 'package ergo\n\nimport rego.v1\n\nversion := "0.6.1-dev"\n\n_spec := "v0.6"\n' > engines/rego/src/shared/basics.rego
printf '# Copyright 2026 Kosli, Inc\n# SPDX-License-Identifier: Apache-2.0\n\n# METADATA\n# scope: package\npackage ergo\n\nimport rego.v1\n' > engines/rego/src/package.rego

echo "build-ergo.sh --release writes a release header, stamps the version and leaves the license and METADATA alone"
SOURCE_DATE_EPOCH=1700000000 sh "$script" --release 0.6.1 abc123 "$dir"
expected_head='# Ergo 0.6.1, the Rego engine. Implements spec v0.6.
# Built from commit abc123 on 2023-11-14T22:13:20Z.
# Project: https://github.com/kosli-dev/ergo
# Read about it in OPA.md in the project.
# License: Apache-2.0. The notice below holds the license text.
# This is a release file. If you edit your copy, the changes are yours.

# Copyright 2026 Kosli, Inc
# SPDX-License-Identifier: Apache-2.0

# METADATA
# scope: package'
[ "$(head -n 12 dist/ergo.rego)" = "$expected_head" ] || fail "the release header should be:
$expected_head
and is:
$(head -n 12 dist/ergo.rego)"
[ "$(sed -n 13p dist/ergo.rego)" = "package ergo" ] || fail "package ergo should come right after METADATA"
grep -qxF 'version := "0.6.1"' dist/ergo.rego || fail "the release should say version := \"0.6.1\""
! grep -q 'DO NOT EDIT' dist/ergo.rego || fail "the release file should not say DO NOT EDIT"
! grep -q "version := .*-dev" dist/ergo.rego || fail "the release file should not say -dev"
cp dist/ergo.rego first.rego
SOURCE_DATE_EPOCH=1700000000 sh "$script" --release 0.6.1 abc123 "$dir"
cmp -s first.rego dist/ergo.rego || fail "two release builds with the same epoch gave different files"

echo "every line of the release build maps to the same line of its part"
every_line_maps release

echo "build-ergo.sh --release fails when the source does not say the version with -dev"
if sh "$script" --release 0.7.0 abc123 "$dir" > /dev/null 2>&1; then
  fail "--release 0.7.0 should fail when the source says 0.6.1-dev, and passed"
fi
[ ! -e dist/ergo.rego ] || fail "a failed release build left dist/ergo.rego in place"
if sh "$script" --release 0.6.1-dev abc123 "$dir" > /dev/null 2>&1; then
  fail "--release should refuse a version with -dev, and passed"
fi
if sh "$script" --release 0.6.1 > /dev/null 2>&1; then
  fail "--release without a commit should fail, and passed"
fi
sh "$script" "$dir"
! grep -q '^# Ergo ' dist/ergo.rego || fail "a default build should not carry the release header"

printf 'package ergo\n\nimport rego.v1\n\nversion := "0.6.1-dev"\n' > engines/rego/src/shared/basics.rego
if sh "$script" --release 0.6.1 abc123 "$dir" > /dev/null 2>&1; then
  fail "--release should fail without a _spec line, and passed"
fi
/bin/rm -f engines/rego/src/shared/basics.rego
printf '# License\n\npackage ergo\n\nimport rego.v1\n' > engines/rego/src/package.rego

echo "build-ergo.sh fails when a part doesn't start with package ergo and import rego.v1"
printf 'package other\n\nimport rego.v1\n\nd := 4\n' > engines/rego/src/b/three.rego
if out=$(sh "$script" "$dir" 2>&1); then
  fail "build-ergo.sh should fail on a part in another package, and passed"
fi
case $out in
  *"engines/rego/src/b/three.rego"*) ;;
  *) fail "build-ergo.sh should name the part, and said: $out" ;;
esac

echo "build-ergo.sh fails when a part has a second package or import line"
printf 'package ergo\n\nimport rego.v1\n\nimport data.x\n' > engines/rego/src/b/three.rego
if sh "$script" "$dir" > /dev/null 2>&1; then
  fail "build-ergo.sh should fail on a second import, and passed"
fi
[ ! -e dist/ergo.rego ] || fail "a failed build should not leave an older dist/ergo.rego in place"

refuses() {
  name=$1
  file=$2
  content=$3
  echo "build-ergo.sh fails on $name and names the file"
  sh "$script" "$dir" > /dev/null
  [ -f dist/ergo.rego ] || fail "the build before $name should have worked"
  printf "$content" > "$file"
  if out=$(sh "$script" "$dir" 2>&1); then
    fail "build-ergo.sh should fail on $name, and passed"
  fi
  case $out in
    *"$file"*) ;;
    *) fail "build-ergo.sh should name $file for $name, and said: $out" ;;
  esac
  [ ! -e dist/ergo.rego ] || fail "a build that failed on $name left dist/ergo.rego in place"
  /bin/rm -f "$file"
}

/bin/rm -f engines/rego/src/b/three.rego
refuses "an empty part" engines/rego/src/b/three.rego ''
refuses "a part that is only the package line" engines/rego/src/b/three.rego 'package ergo\n'
refuses "a part without the import line" engines/rego/src/b/three.rego 'package ergo\n\nd := 4\n'
refuses "a part with an indented import" engines/rego/src/b/three.rego 'package ergo\n\nimport rego.v1\n\nd := 4\n  import data.x\n'
refuses "a part with a second package line" engines/rego/src/b/three.rego 'package ergo\n\nimport rego.v1\n\nd := 4\npackage ergo\n'
refuses "a part with a space in its path" "engines/rego/src/b/a b.rego" 'package ergo\n\nimport rego.v1\n\nd := 4\n'

package_text=$(cat engines/rego/src/package.rego)
for bad in 'package other\n\nimport rego.v1\n' 'package ergo\n' 'package ergo\n\nimport rego.v1\n\nimport data.x\n' 'package ergo\n\nimport rego.v1\n\n  package ergo\n' '# License\n\nimport rego.v1\n'; do
  echo "build-ergo.sh fails on a package.rego that breaks the rules, and names it"
  sh "$script" "$dir" > /dev/null
  printf "$bad" > engines/rego/src/package.rego
  if out=$(sh "$script" "$dir" 2>&1); then
    fail "build-ergo.sh should fail on a package.rego like $bad, and passed"
  fi
  case $out in
    *"engines/rego/src/package.rego"*) ;;
    *) fail "build-ergo.sh should name package.rego, and said: $out" ;;
  esac
  [ ! -e dist/ergo.rego ] || fail "a build that failed on package.rego left dist/ergo.rego in place"
  printf '%s\n' "$package_text" > engines/rego/src/package.rego
done

root=$(cd "$(dirname "$script")/.." && pwd)
real=$(sed -n 's/^version := "\(.*\)-dev"$/\1/p' "$root/engines/rego/src/shared/basics.rego")
for kind in default release; do
  echo "opa check --strict passes on the $kind build of the real parts, and METADATA stays above package ergo"
  rdir=$(mktemp -d)
  mkdir -p "$rdir/engines" "$rdir/.github"
  cp -R "$root/engines/rego" "$rdir/engines/rego"
  if [ "$kind" = default ]; then
    sh "$script" "$rdir"
  else
    sh "$script" --release "$real" abc123 "$rdir"
  fi
  opa check --strict --schema "$root/.github/closed-input-schema.json" "$rdir/dist/ergo.rego" || fail "opa check failed on the $kind build"
  [ "$(grep -n '^package ergo$' "$rdir/dist/ergo.rego" | cut -d: -f1)" -gt 0 ] || fail "no package line"
  before=$(grep -B1 '^package ergo$' "$rdir/dist/ergo.rego" | head -n 1)
  [ "$before" = "#   - input[\"ergo/names\"]: {\"type\": \"object\"}" ] || fail "METADATA should be directly above package ergo, and the line above is: $before"
  /bin/rm -rf "$rdir"
done

echo "build-ergo.sh tests passed"
