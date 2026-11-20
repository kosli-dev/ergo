#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/no-array-data.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
mkdir -p engines/rego spec/cases examples/a dist other
echo '{"a": 1}' > spec/cases/cases.json
echo '{}' > examples/a/input.json
echo '[1]' > other/list.json
echo '[{"id": 1}]' > spec/cases/list.json
git add .

echo "no-array-data.sh passes when every JSON file at the top of a folder OPA loads is an object, and ignores lists in subfolders and other folders"
sh "$script"

echo "no-array-data.sh fails on a JSON array in spec and names the file"
echo '[{"name": "x"}]' > spec/pairs.json
git add .
if out=$(sh "$script" 2>&1); then
  echo "no-array-data.sh should fail, and passed" >&2
  exit 1
fi
case $out in
  *"spec/pairs.json"*) ;;
  *)
    echo "no-array-data.sh should name spec/pairs.json, and said: $out" >&2
    exit 1
    ;;
esac

echo "no-array-data.sh fails on a JSON array in examples"
git rm --quiet --cached spec/pairs.json
/bin/rm -f spec/pairs.json
echo '[]' > examples/list.json
git add .
if sh "$script" >/dev/null 2>&1; then
  echo "no-array-data.sh should fail on examples, and passed" >&2
  exit 1
fi

echo "no-array-data.sh passes again once it is gone"
git rm --quiet --cached examples/list.json
/bin/rm -f examples/list.json
sh "$script"
