#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/pr-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
a=$dir/a
b=$dir/b
mkdir -p "$a/t" "$a/u" "$a/w" "$b/t" "$b/u"

printf '1\tt / g / a\n2\tt / g / b\n3\tt / g / c\n4\tt / g / d\n5\tt / g / e\n' > "$a/t/index.txt"
cp "$a/t/index.txt" "$b/t/index.txt"
printf '1\tu / g / x\n2\tu / g / f\n3\tu / g / h\n' > "$a/u/index.txt"
printf '1\tu / g / x\n2\tu / g / f2\n3\tu / g / h2\n' > "$b/u/index.txt"
printf '1\tw / g / v\n2\tw / g / k\n' > "$a/w/index.txt"
for n in 1 2 3 4 5; do
  printf '{"n":%s}\n' "$n" > "$a/t/$n.json"
  cp "$a/t/$n.json" "$b/t/$n.json"
done
for n in 1 2 3; do
  printf '{"n":%s}\n' "$n" > "$a/u/$n.json"
  cp "$a/u/$n.json" "$b/u/$n.json"
done
for n in 1 2; do
  printf '{"n":%s}\n' "$n" > "$a/w/$n.json"
done
for n in 1 2 3 4; do
  printf '{"n":%s,"new":true}\n' "$n" > "$b/t/$n.json"
done
printf '{"n":1,"new":true}\n' > "$b/u/1.json"
printf '{"n":3,"new":true}\n' > "$b/u/3.json"

printf 't / g / b\nt / g / c\nu / g / f\nw / g / k\n' > "$dir/known-a.txt"
printf 't / g / c\nt / g / d\nu / g / f2\n' > "$dir/known-b.txt"

run() {
  PR_FACTS_BASE_DUMP=$a PR_FACTS_HEAD_DUMP=$b \
    PR_FACTS_BASE_KNOWN=$dir/known-a.txt PR_FACTS_HEAD_KNOWN=$dir/known-b.txt \
    sh "$script" base
}

expect() {
  expected=$1
  out=$(run)
  if [ "$out" != "$expected" ]; then
    echo "pr-facts.sh should print:" >&2
    echo "$expected" >&2
    echo "and printed:" >&2
    echo "$out" >&2
    exit 1
  fi
}

echo "pr-facts.sh counts changed reports, follows renamed keys, and puts cases that stopped passing first"
expect "## Rust report changes

6 case reports changed between base and the working tree.

- t 1-4
- u 1, 3

Passing cases whose report changed: 4 (information only: a case compares the fields it lists, so a passing case can change a field it doesn't list).

Cases only on one side: 0 new, 2 removed.

## Known failures

known-failures.txt had 4 lines and has 3 now.

CASES THAT PASSED ON base AND FAIL OR ARE GONE NOW: 2
- t / g / d
- w / g / v (gone)

Pass now, and did not before: 1
- t / g / b

Fail now, and did not before: 1
- t / g / d

Renamed keys: 2
- u / g / f -> u / g / f2
- u / g / h -> u / g / h2

Removed from known-failures.txt because the case is gone: 1
- w / g / k"

echo "pr-facts.sh says so when nothing changed"
/bin/rm -rf "$b"
cp -R "$a" "$b"
cp "$dir/known-a.txt" "$dir/known-b.txt"
expect "## Rust report changes

No case report changed between base and the working tree.

## Known failures

known-failures.txt had 4 lines and has 4 now.

No case started or stopped passing."

echo "pr-facts.sh counts cases that only one side has"
printf '6\tt / g / z\n' >> "$b/t/index.txt"
printf '{"n":6}\n' > "$b/t/6.json"
out=$(run)
case $out in
  *"Cases only on one side: 1 new, 0 removed."*) ;;
  *)
    echo "pr-facts.sh should count new cases, and printed: $out" >&2
    exit 1
    ;;
esac
