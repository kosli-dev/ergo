#!/bin/sh
set -eu
if [ $# -gt 1 ]; then
  echo "usage: pr-facts.sh [BASE]" >&2
  exit 2
fi
base=${1:-origin/main}
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
tree=
cleanup() {
  if [ -n "$tree" ]; then
    git -C "$here" worktree remove --force "$tree" > /dev/null 2>&1 || true
  fi
  /bin/rm -rf "$work"
}
trap cleanup EXIT

if [ -n "${PR_FACTS_BASE_DUMP:-}" ]; then
  base_dump=$PR_FACTS_BASE_DUMP
  head_dump=$PR_FACTS_HEAD_DUMP
  base_known=$PR_FACTS_BASE_KNOWN
  head_known=$PR_FACTS_HEAD_KNOWN
else
  root=$(git -C "$here" rev-parse --show-toplevel)
  export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/ergo-cargo-target}
  export ASDF_RUST_VERSION=1.99.0
  tree=$work/base
  git -C "$root" worktree add --detach "$tree" "$base" > /dev/null 2>&1
  if ! grep -q index.txt "$tree/engines/rust/engine/tests/cases.rs"; then
    cp "$root/engines/rust/engine/tests/cases.rs" "$tree/engines/rust/engine/tests/cases.rs"
  fi
  dump() {
    find "$1/engines/rust" -name '*.rs' -exec touch {} +
    (cd "$1/engines/rust" && ERGO_DUMP=$2 cargo test -j 4 -p ergo-policy-engine --test cases every_case > /dev/null)
  }
  dump "$tree" "$work/base-dump"
  dump "$root" "$work/head-dump"
  base_dump=$work/base-dump
  head_dump=$work/head-dump
  git -C "$root" show "$base:engines/rust/known-failures.txt" > "$work/base-known.txt"
  base_known=$work/base-known.txt
  head_known=$root/engines/rust/known-failures.txt
fi

export LC_ALL=C
tab=$(printf '\t')

index_of() {
  for file in "$1"/*/index.txt; do
    topic=$(basename "$(dirname "$file")")
    awk -F'\t' -v topic="$topic" '{ print topic "\t" $1 "\t" $2 }' "$file"
  done | sort -t "$tab" -k3,3
}

index_of "$base_dump" > "$work/base.idx"
index_of "$head_dump" > "$work/head.idx"
sort -u "$base_known" > "$work/base.known"
sort -u "$head_known" > "$work/head.known"

join -t "$tab" -1 3 -2 3 -o 0,1.1,1.2,2.1,2.2 "$work/base.idx" "$work/head.idx" > "$work/both.tsv"
join -t "$tab" -1 3 -2 3 -v 2 -o 2.1,2.2,0 "$work/base.idx" "$work/head.idx" > "$work/new.tsv"
join -t "$tab" -1 3 -2 3 -v 1 -o 1.1,1.2,0 "$work/base.idx" "$work/head.idx" > "$work/removed.tsv"

: > "$work/changed.tsv"
while IFS="$tab" read -r key btopic bn htopic hn; do
  if ! cmp -s "$base_dump/$btopic/$bn.json" "$head_dump/$htopic/$hn.json"; then
    printf '%s\t%s\t%s\n' "$htopic" "$hn" "$key" >> "$work/changed.tsv"
  fi
done < "$work/both.tsv"
sort -t "$tab" -k1,1 -k2,2n "$work/changed.tsv" > "$work/changed.sorted"

ranges() {
  awk -F'\t' '
    function close_run() {
      out = out (out == "" ? "" : ", ") (start == last ? start : start "-" last)
    }
    {
      if ($1 != topic) {
        if (topic != "") { close_run(); print "- " topic " " out; out = "" }
        topic = $1; start = $2; last = $2
      } else if ($2 == last + 1) {
        last = $2
      } else {
        close_run(); start = $2; last = $2
      }
    }
    END { if (topic != "") { close_run(); print "- " topic " " out } }
  ' "$1"
}

plural() {
  if [ "$1" = 1 ]; then echo "$2"; else echo "$3"; fi
}

count_lines() {
  wc -l < "$1" | tr -d ' '
}

changed_count=$(count_lines "$work/changed.sorted")
new_count=$(count_lines "$work/new.tsv")
removed_count=$(count_lines "$work/removed.tsv")

echo "## Rust report changes"
echo
if [ "$changed_count" = 0 ]; then
  echo "No case report changed between $base and the working tree."
else
  echo "$changed_count case $(plural "$changed_count" report reports) changed between $base and the working tree."
  echo
  ranges "$work/changed.sorted"
fi
if [ "$new_count" != 0 ] || [ "$removed_count" != 0 ]; then
  echo
  echo "Cases only on one side: $new_count new, $removed_count removed."
fi

awk -F'\t' '
  FILENAME == ARGV[1] { pos[$3] = $1 "\t" $2; next }
  FILENAME == ARGV[2] { at[$1 "\t" $2] = $3; next }
  FILENAME == ARGV[3] { was[$0] = 1; next }
  FILENAME == ARGV[4] { now[$0] = 1; next }
  END {
    for (k in was) {
      if (k in now) continue
      if (!(k in pos)) continue
      k2 = at[pos[k]]
      if (k2 != "" && k2 != k && (k2 in now) && !(k2 in was)) print k "\t" k2
    }
  }
' "$work/base.idx" "$work/head.idx" "$work/base.known" "$work/head.known" | sort > "$work/renamed.tsv"

cut -f1 "$work/renamed.tsv" | sort > "$work/renamed.old"
cut -f2 "$work/renamed.tsv" | sort > "$work/renamed.new"
comm -23 "$work/base.known" "$work/head.known" | comm -23 - "$work/renamed.old" > "$work/left.txt"
comm -13 "$work/base.known" "$work/head.known" | comm -23 - "$work/renamed.new" > "$work/joined.txt"
cut -f3 "$work/head.idx" | sort > "$work/head.keys"
cut -f3 "$work/base.idx" | sort > "$work/base.keys"
comm -12 "$work/left.txt" "$work/head.keys" > "$work/pass.txt"
comm -23 "$work/left.txt" "$work/head.keys" > "$work/gone.txt"
comm -12 "$work/joined.txt" "$work/base.keys" > "$work/regress.txt"

list() {
  sed 's/^/- /' "$1"
}

echo
echo "## Known failures"
echo
echo "known-failures.txt had $(count_lines "$work/base.known") $(plural "$(count_lines "$work/base.known")" line lines) and has $(count_lines "$work/head.known") now."
if [ -s "$work/regress.txt" ]; then
  echo
  echo "CASES THAT PASSED ON $base AND FAIL NOW: $(count_lines "$work/regress.txt")"
  list "$work/regress.txt"
fi
if [ -s "$work/pass.txt" ]; then
  echo
  echo "Pass now, and did not before: $(count_lines "$work/pass.txt")"
  list "$work/pass.txt"
fi
if [ -s "$work/joined.txt" ]; then
  echo
  echo "Fail now, and did not before: $(count_lines "$work/joined.txt")"
  list "$work/joined.txt"
fi
if [ -s "$work/renamed.tsv" ]; then
  echo
  echo "Renamed keys: $(count_lines "$work/renamed.tsv")"
  sed 's/\t/ -> /; s/^/- /' "$work/renamed.tsv"
fi
if [ -s "$work/gone.txt" ]; then
  echo
  echo "Removed from known-failures.txt because the case is gone: $(count_lines "$work/gone.txt")"
  list "$work/gone.txt"
fi
if [ ! -s "$work/pass.txt" ] && [ ! -s "$work/joined.txt" ] && [ ! -s "$work/renamed.tsv" ] && [ ! -s "$work/gone.txt" ]; then
  echo
  echo "No case started or stopped passing."
fi

awk -F'\t' '
  FILENAME == ARGV[1] { was[$0] = 1; next }
  !($3 in was) { print $1 "\t" $2 "\t" $3 }
' "$work/base.known" "$work/changed.sorted" > "$work/problems.tsv"

echo
echo "## Passing cases that changed"
echo
if [ -s "$work/problems.tsv" ]; then
  problems=$(count_lines "$work/problems.tsv")
  echo "$problems $(plural "$problems" case cases) passed on $base and changed their report. That is a problem."
  echo
  awk -F'\t' '{ print "- " $1 " " $2 ": " $3 }' "$work/problems.tsv"
else
  echo "None. No case that passed on $base changed its report."
fi
