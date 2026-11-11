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

echo "build-ergo.sh tests passed"
