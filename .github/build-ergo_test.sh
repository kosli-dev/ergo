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
expected='# License

package ergo

import rego.v1

a := 1

c := 3

b := 2'
[ "$(cat dist/ergo.rego)" = "$expected" ] || fail "dist/ergo.rego should be:
$expected
and is:
$(cat dist/ergo.rego)"

echo "build-ergo.sh where maps a line of dist/ergo.rego back to its part, and leaves other lines alone"
out=$(printf 'dist/ergo.rego:1\ndist/ergo.rego:9\ndist/ergo.rego:11\nother.rego:4\n' | sh "$script" where "$dir")
expected='engines/rego/src/package.rego:1
engines/rego/src/a/one.rego:7
engines/rego/src/b/two.rego:5
other.rego:4'
[ "$out" = "$expected" ] || fail "where should print:
$expected
and printed:
$out"

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
[ "$(cat dist/ergo.rego)" = "$(printf '# License\n\npackage ergo\n\nimport rego.v1\n\na := 1\n\nc := 3\n\nb := 2')" ] || fail "a failed build should leave the last dist/ergo.rego alone"

echo "build-ergo.sh tests passed"
