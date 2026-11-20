#!/bin/sh
set -eu
if [ $# -ne 1 ]; then
  echo "usage: red-check.sh BASE" >&2
  exit 2
fi
base=$1
head=${RED_CHECK_HEAD:-HEAD}
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
work=$(mktemp -d)
tree=
cleanup() {
  if [ -n "$tree" ]; then
    git -C "$root" worktree remove --force "$tree" > /dev/null 2>&1 || true
  fi
  /bin/rm -rf "$work"
}
trap cleanup EXIT
export LC_ALL=C
tab=$(printf '\t')

git -C "$root" diff -U1 --no-color "$base...$head" > "$work/diff.txt"
git -C "$root" diff --name-only --diff-filter=AM "$base...$head" > "$work/changed.txt"

awk -v added="$work/added.tsv" -v removed="$work/removed.txt" '
  /^\+\+\+ / { file = substr($0, 7); pending = 0; next }
  /^--- / { next }
  /^@@/ { pending = 0; next }
  /^ / {
    pending = (substr($0, 2) ~ /^[ \t]*#\[test\]/)
    next
  }
  /^\+/ {
    line = substr($0, 2)
    if (file ~ /_test\.rego$/) {
      if (match(line, /^test_[A-Za-z0-9_]+/)) print "rego\t" file "\t" substr(line, RSTART, RLENGTH) > added
    } else if (file ~ /\.rs$/ && (file ~ /(^|\/)tests\.rs$/ || file ~ /\/tests\//)) {
      if (line ~ /^[ \t]*#\[test\]/) pending = 1
      else if (pending && match(line, /fn [A-Za-z0-9_]+/)) {
        print "rust\t" file "\t" substr(line, RSTART + 3, RLENGTH - 3) > added
        pending = 0
      }
    }
    next
  }
  /^-/ {
    line = substr($0, 2)
    if (match(line, /^test_[A-Za-z0-9_]+/)) print substr(line, RSTART, RLENGTH) > removed
    else if (match(line, /fn [A-Za-z0-9_]+/)) print substr(line, RSTART + 3, RLENGTH - 3) > removed
  }
' "$work/diff.txt"
touch "$work/added.tsv" "$work/removed.txt"

awk -F'\t' '
  FILENAME == ARGV[1] { gone[$0] = 1; next }
  $3 in gone { moved++; next }
  { print }
  END { print moved + 0 > "/dev/stderr" }
' "$work/removed.txt" "$work/added.tsv" > "$work/new.tsv" 2> "$work/moved.txt"
sort -u -o "$work/new.tsv" "$work/new.tsv"
moved=$(cat "$work/moved.txt")

heading="## New tests that already pass on the old source"
total=$(wc -l < "$work/new.tsv" | tr -d ' ')
if [ "$total" = 0 ]; then
  echo "$heading"
  echo
  echo "No test was added."
  exit 0
fi

tree=$work/base
git -C "$root" worktree add --detach "$tree" "$base" > /dev/null 2>&1
while read -r path; do
  case $path in
    engines/rust/*/tests.rs | engines/rust/*/tests/* | *_test.rego)
      mkdir -p "$tree/$(dirname "$path")"
      git -C "$root" show "$head:$path" > "$tree/$path"
      ;;
  esac
done < "$work/changed.txt"

rust_cmd=${RED_CHECK_RUST_CMD:-}
rego_cmd=${RED_CHECK_REGO_CMD:-}
build_cmd=${RED_CHECK_BUILD_CMD:-.github/build-ergo.sh}

default_rust() {
  export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/.cache/ergo-cargo-target}
  export ASDF_RUST_VERSION=1.99.0
  find "$1/engines/rust" -name '*.rs' -exec touch {} +
  out=$work/cargo.out
  tree_dir=$1
  shift
  (cd "$tree_dir/engines/rust" && cargo test -j 4 -p "$@" > "$out" 2>&1) || return 1
  if grep -q '[1-9][0-9]* passed' "$out"; then return 0; fi
  return 3
}

default_rego() {
  out=$work/opa.out
  (cd "$1" && opa test engines/rego dist spec:spec examples:examples --ignore src --timeout 120s --run "^$2\$" > "$out" 2>&1) || return 1
  if grep -q 'PASS: [1-9]' "$out"; then return 0; fi
  return 3
}

crate_of() {
  dir=$(dirname "$1")
  while [ "$dir" != . ] && [ "$dir" != / ]; do
    if git -C "$root" cat-file -e "$head:$dir/Cargo.toml" 2> /dev/null; then
      name=$(git -C "$root" show "$head:$dir/Cargo.toml" | sed -n '/^\[package\]/,/^\[/{s/^name *= *"\(.*\)"/\1/p;}' | sed -n 1p)
      printf '%s\t%s\n' "$dir" "$name"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

: > "$work/pass.txt"
: > "$work/unrun.txt"
rust_count=0
rego_count=0
built=0
while IFS="$tab" read -r kind path name; do
  if [ "$kind" = rust ]; then
    rust_count=$((rust_count + 1))
    info=$(crate_of "$path") || { echo "no Cargo.toml above $path" >&2; exit 1; }
    cdir=${info%%"$tab"*}
    crate=${info#*"$tab"}
    rel=${path#"$cdir"/}
    case $rel in
      tests/*)
        target=${rel#tests/}
        target=${target%%/*}
        target=${target%.rs}
        set -- --test "$target"
        ;;
      *) set -- --lib ;;
    esac
    status=0
    if [ -n "$rust_cmd" ]; then
      "$rust_cmd" "$tree" "$crate" "$@" "$name" || status=$?
    else
      default_rust "$tree" "$crate" "$@" "$name" || status=$?
    fi
  else
    rego_count=$((rego_count + 1))
    if [ "$built" = 0 ]; then
      (cd "$tree" && sh -c "$build_cmd") > /dev/null
      built=1
    fi
    status=0
    if [ -n "$rego_cmd" ]; then
      "$rego_cmd" "$tree" "$name" || status=$?
    else
      default_rego "$tree" "$name" || status=$?
    fi
  fi
  case $status in
    0) printf -- '- %s %s\n' "$path" "$name" >> "$work/pass.txt" ;;
    3) printf -- '- %s %s\n' "$path" "$name" >> "$work/unrun.txt" ;;
  esac
done < "$work/new.tsv"

passing=$(wc -l < "$work/pass.txt" | tr -d ' ')
unrun=$(wc -l < "$work/unrun.txt" | tr -d ' ')
echo "$heading"
echo
if [ "$passing" = 0 ]; then
  echo "$total new tests ($rust_count Rust, $rego_count Rego), none passes on $base."
else
  echo "$total new tests ($rust_count Rust, $rego_count Rego), $passing pass on $base:"
  cat "$work/pass.txt"
fi
if [ "$unrun" != 0 ]; then
  echo
  echo "Could not run: $unrun"
  cat "$work/unrun.txt"
fi
if [ "$moved" != 0 ]; then
  echo
  echo "Left out because the diff also removes a test with the same name: $moved"
fi
