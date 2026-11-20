#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/dump-diff.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/a/t" "$dir/b/t"
printf '{"x":1}\n' > "$dir/a/t/1.json"
printf '{"y":2}\n' > "$dir/a/t/2.json"
cp "$dir/a/t/1.json" "$dir/b/t/1.json"
cp "$dir/a/t/2.json" "$dir/b/t/2.json"

echo "dump-diff.sh prints nothing for two identical folders"
out=$(sh "$script" "$dir/a" "$dir/b")
if [ -n "$out" ]; then
  echo "dump-diff.sh should print nothing, and printed: $out" >&2
  exit 1
fi

check_says() {
  expected=$1
  out=$(sh "$script" "$dir/a" "$dir/b")
  if [ "$out" != "$expected" ]; then
    echo "dump-diff.sh should print \"$expected\", and printed: $out" >&2
    exit 1
  fi
}

echo "dump-diff.sh names a file whose content differs"
printf '{"y":3}\n' > "$dir/b/t/2.json"
check_says "t/2.json"

echo "dump-diff.sh names a file only one folder has"
cp "$dir/a/t/2.json" "$dir/b/t/2.json"
printf '{}\n' > "$dir/b/t/3.json"
check_says "t/3.json"
/bin/rm -f "$dir/b/t/3.json" "$dir/a/t/1.json"
check_says "t/1.json"
