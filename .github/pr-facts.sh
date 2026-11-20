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
  head_cargo_exit=${PR_FACTS_HEAD_CARGO_EXIT:-0}
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
    dump_exit=0
    (cd "$1/engines/rust" && ERGO_DUMP=$2 cargo test -j 4 -p ergo-policy-engine --test cases every_case > /dev/null) || dump_exit=$?
  }
  dump "$tree" "$work/base-dump"
  dump "$root" "$work/head-dump"
  head_cargo_exit=$dump_exit
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

awk -F'\t' -v only_base="$work/only-base.txt" -v only_head="$work/only-head.txt" '
  FILENAME == ARGV[1] {
    bkey[$3] = 1; bat[$1 "\t" $2] = $3; bpos[$3] = $1 "\t" $2; bn[$1]++
    next
  }
  {
    hkey[$3] = 1; hn[$1]++; hrow[++rows] = $0
  }
  END {
    for (i = 1; i <= rows; i++) {
      split(hrow[i], f, "\t")
      topic = f[1]; num = f[2]; key = f[3]
      if (key in bkey) {
        split(bpos[key], b, "\t")
        print key "\t" key "\t" b[1] "\t" b[2] "\t" topic "\t" num
        paired[key] = 1
      } else {
        old = bat[topic "\t" num]
        if (old != "" && !(old in hkey) && bn[topic] == hn[topic]) {
          split(bpos[old], b, "\t")
          print old "\t" key "\t" b[1] "\t" b[2] "\t" topic "\t" num
          paired[old] = 1
          paired[key] = 1
        } else {
          print key > only_head
        }
      }
    }
    for (k in bkey) if (!(k in paired)) print k > only_base
  }
' "$work/base.idx" "$work/head.idx" | sort > "$work/pairs.tsv"
touch "$work/only-base.txt" "$work/only-head.txt"
sort -o "$work/only-base.txt" "$work/only-base.txt"
sort -o "$work/only-head.txt" "$work/only-head.txt"

: > "$work/changed.tsv"
: > "$work/changed.keys"
while IFS="$tab" read -r bkey hkey btopic bn htopic hn; do
  if ! cmp -s "$base_dump/$btopic/$bn.json" "$head_dump/$htopic/$hn.json"; then
    printf '%s\t%s\t%s\n' "$htopic" "$hn" "$hkey" >> "$work/changed.tsv"
    printf '%s\n' "$bkey" >> "$work/changed.keys"
  fi
done < "$work/pairs.tsv"
sort -t "$tab" -k1,1 -k2,2n "$work/changed.tsv" > "$work/changed.sorted"
sort "$work/changed.keys" | comm -23 - "$work/base.known" > "$work/changed-passing.keys"

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
new_count=$(count_lines "$work/only-head.txt")
removed_count=$(count_lines "$work/only-base.txt")
changed_passing=$(count_lines "$work/changed-passing.keys")

awk -F'\t' -v out="$work" '
  FILENAME == ARGV[1] { was[$0] = 1; next }
  FILENAME == ARGV[2] { now[$0] = 1; next }
  FILENAME == ARGV[3] {
    if ($1 != $2) print $1 "\t" $2 > (out "/renamed.tsv")
    if (!($1 in was) && ($2 in now)) print $2 > (out "/regress.txt")
    if (($1 in was) && !($2 in now)) print $2 > (out "/pass.txt")
    if (!($1 in was) && ($2 in now)) print $2 > (out "/joined.txt")
    next
  }
  FILENAME == ARGV[4] { if ($0 in now) print $0 > (out "/joined.txt"); next }
  FILENAME == ARGV[5] {
    if ($0 in was) print $0 > (out "/gone-known.txt")
    else print $0 " (gone)" > (out "/regress.txt")
  }
' "$work/base.known" "$work/head.known" "$work/pairs.tsv" "$work/only-head.txt" "$work/only-base.txt"
for name in renamed.tsv regress.txt pass.txt joined.txt gone-known.txt; do
  touch "$work/$name"
  sort -o "$work/$name" "$work/$name"
done

list() {
  sed 's/^/- /' "$1"
}

if [ -s "$work/regress.txt" ]; then
  echo "CASES THAT PASSED ON $base AND FAIL OR ARE GONE NOW: $(count_lines "$work/regress.txt")"
  list "$work/regress.txt"
  echo
fi
if [ "$head_cargo_exit" != 0 ]; then
  echo "cargo test exited with $head_cargo_exit on the working tree."
  echo
fi
echo "## Rust report changes"
echo
if [ "$changed_count" = 0 ]; then
  echo "No case report changed between $base and the working tree."
else
  echo "$changed_count case $(plural "$changed_count" report reports) changed between $base and the working tree."
  echo
  ranges "$work/changed.sorted"
  echo
  echo "Passing cases whose report changed: $changed_passing (information only: a case compares the fields it lists, so a passing case can change a field it doesn't list)."
fi
if [ "$new_count" != 0 ] || [ "$removed_count" != 0 ]; then
  echo
  echo "Cases only on one side: $new_count new, $removed_count removed."
fi

echo
echo "## Known failures"
echo
echo "known-failures.txt had $(count_lines "$work/base.known") $(plural "$(count_lines "$work/base.known")" line lines) and has $(count_lines "$work/head.known") now."
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
if [ -s "$work/gone-known.txt" ]; then
  echo
  echo "Removed from known-failures.txt because the case is gone: $(count_lines "$work/gone-known.txt")"
  list "$work/gone-known.txt"
fi
if [ ! -s "$work/regress.txt" ] && [ ! -s "$work/pass.txt" ] && [ ! -s "$work/joined.txt" ] && [ ! -s "$work/renamed.tsv" ] && [ ! -s "$work/gone-known.txt" ]; then
  echo
  echo "No case started or stopped passing."
fi
