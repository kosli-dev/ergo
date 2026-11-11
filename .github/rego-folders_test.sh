#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/rego-folders.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
mkdir -p engines/rego/src engines/rego/tests spec/cases examples/baking/ergo engines/rust/sentences/tests/oracle
for file in engines/rego/src/package.rego engines/rego/tests/spec_test.rego examples/baking/ergo/policy.rego engines/rust/sentences/tests/oracle/oracle_test.rego; do
  echo "package demo" > "$file"
done
echo "{}" > spec/cases/cases.json
git add .

echo "rego-folders.sh passes when every Rego file is in a folder OPA loads"
sh "$script"

mkdir -p tools engines/rust/other
echo "package tools" > tools/helper.rego
echo "package other" > engines/rust/other/other_test.rego
echo "package stray" > spec/stray.rego
git add .
echo "rego-folders.sh fails and names each Rego file outside those folders"
if out=$(sh "$script" 2>&1); then
  echo "rego-folders.sh should fail, and passed" >&2
  exit 1
fi
for expected in "tools/helper.rego" "engines/rust/other/other_test.rego" "spec/stray.rego" ".github/rego-folders.sh"; do
  case $out in
    *"$expected"*) ;;
    *)
      echo "rego-folders.sh should say \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
done
case $out in
  *"engines/rego/src/package.rego"* | *"spec_test.rego"* | *"oracle_test.rego"*)
    echo "rego-folders.sh should not name the allowed files, and said: $out" >&2
    exit 1
    ;;
esac

echo "rego-folders.sh fails on Rego under a folder named src other than engines/rego/src, which --ignore src would skip"
git rm --quiet --cached tools/helper.rego engines/rust/other/other_test.rego spec/stray.rego
/bin/rm -f tools/helper.rego engines/rust/other/other_test.rego spec/stray.rego
sh "$script"
mkdir -p engines/rego/tests/src examples/baking/src
echo "package hidden" > engines/rego/tests/src/hidden_test.rego
echo "package hidden" > examples/baking/src/hidden.rego
git add .
if out=$(sh "$script" 2>&1); then
  echo "rego-folders.sh should fail on Rego under a src folder, and passed" >&2
  exit 1
fi
for expected in "engines/rego/tests/src/hidden_test.rego" "examples/baking/src/hidden.rego"; do
  case $out in
    *"$expected"*) ;;
    *)
      echo "rego-folders.sh should say \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
done
case $out in
  *"engines/rego/src/package.rego"*)
    echo "rego-folders.sh should not name engines/rego/src/package.rego, and said: $out" >&2
    exit 1
    ;;
esac
