#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/pr-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
a=$dir/a
b=$dir/b
mkdir -p "$a/t" "$a/u" "$b/t" "$b/u"

printf '1\tt / g / a\n2\tt / g / b\n3\tt / g / c\n4\tt / g / d\n5\tt / g / e\n' > "$a/t/index.txt"
cp "$a/t/index.txt" "$b/t/index.txt"
printf '1\tu / g / x\n2\tu / g / f\n' > "$a/u/index.txt"
printf '1\tu / g / x\n2\tu / g / f2\n' > "$b/u/index.txt"
for n in 1 2 3 4 5; do
  printf '{"n":%s}\n' "$n" > "$a/t/$n.json"
  cp "$a/t/$n.json" "$b/t/$n.json"
done
printf '{"n":1}\n' > "$a/u/1.json"
printf '{"n":2}\n' > "$a/u/2.json"
cp "$a/u/1.json" "$b/u/1.json"
cp "$a/u/2.json" "$b/u/2.json"
for n in 1 2 3 4; do
  printf '{"n":%s,"new":true}\n' "$n" > "$b/t/$n.json"
done
printf '{"n":1,"new":true}\n' > "$b/u/1.json"

printf 't / g / b\nt / g / c\nu / g / f\n' > "$dir/known-a.txt"
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

echo "pr-facts.sh counts changed reports, joins runs, lists known-failures changes and flags changed passing cases"
expect "## Rust report changes

5 case reports changed between base and the working tree.

- t 1-4
- u 1

Cases only on one side: 1 new, 1 removed.

## Known failures

known-failures.txt had 3 lines and has 3 now.

CASES THAT PASSED ON base AND FAIL NOW: 1
- t / g / d

Pass now, and did not before: 1
- t / g / b

Fail now, and did not before: 1
- t / g / d

Renamed keys: 1
- u / g / f -> u / g / f2

## Passing cases that changed

3 cases passed on base and changed their report. That is a problem.

- t 1: t / g / a
- t 4: t / g / d
- u 1: u / g / x"

echo "pr-facts.sh says so when nothing changed"
/bin/rm -rf "$b"
cp -R "$a" "$b"
cp "$dir/known-a.txt" "$dir/known-b.txt"
expect "## Rust report changes

No case report changed between base and the working tree.

## Known failures

known-failures.txt had 3 lines and has 3 now.

No case started or stopped passing.

## Passing cases that changed

None. No case that passed on base changed its report."

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
