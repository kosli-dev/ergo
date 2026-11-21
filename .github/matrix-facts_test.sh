#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/matrix-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

cat > "$dir/pairs.json" <<'JSON'
[
 {"name": "same", "policy": {}, "input": {}},
 {"name": "went_up", "policy": {}, "input": {}},
 {"name": "went_down", "policy": {}, "input": {}},
 {"name": "down_on_base", "policy": {}, "input": {}},
 {"name": "says_less", "policy": {}, "input": {}},
 {"name": "passes_now", "policy": {}, "input": {}}
]
JSON

row() {
  if [ "$1" = satisfied ]; then
    printf '{"requirement":"r","check":"c","subject":"t","passed":true,"cause":"satisfied"}'
  else
    printf '{"requirement":"r","check":"c","subject":"t","passed":false,"cause":"%s","message":"%s","failures":[{"message":"%s"}]}' "$1" "${2:-$1 problem}" "${2:-$1 problem}"
  fi
}
report() {
  printf '{"results":[%s]}' "$(row "$@")"
}
six() {
  printf '[%s,%s,%s,%s,%s,%s]' "$1" "$2" "$3" "$4" "$5" "$6"
}

six "$(report value)" "$(report absent)" "$(report absent)" "$(report absent)" "$(report value 'a is 1, and b is 2')" "$(report value)" > "$dir/rego.json"
six "$(report value)" "$(report unusable)" "$(report value)" "$(report value)" "$(report value 'a is 1')" "$(report satisfied)" > "$dir/head.json"
six "$(report value)" "$(report absent)" "$(report absent)" "$(report null)" "$(report value 'a is 1, and b is 2')" "$(report value)" > "$dir/base.json"

run() {
  MATRIX_FACTS_PAIRS=$dir/pairs.json MATRIX_FACTS_REGO=$dir/rego.json \
    MATRIX_FACTS_RUST=$1 MATRIX_FACTS_BASE_RUST=$2 sh "$script" base matrix-a
}

expect() {
  out=$(run "$1" "$2")
  if [ "$out" != "$3" ]; then
    echo "matrix-facts.sh should print:" >&2
    echo "$3" >&2
    echo "and printed:" >&2
    echo "$out" >&2
    exit 1
  fi
}

echo "matrix-facts.sh lists the causes that went down, the problems that are gone and the causes that went up"
expect "$dir/head.json" "$dir/base.json" "## Matrix matrix-a

### Cause went down (usually a bug): 3

- went_down: r/c: base absent, working tree value, Rego absent
- down_on_base: r/c: base null, working tree value, Rego absent (already on base)
- passes_now: r/c: base value, working tree satisfied, Rego value

### Says less than base (usually a bug): 2

- says_less: r/c: missing \"b is 2\"; base says \"a is 1, and b is 2\", working tree says \"a is 1\"
- passes_now: r/c: missing \"value problem\"; base says \"value problem\", working tree says \"none\"

### Cause went up (usually the rule problems.all_said; list for the Rego steps): 1

- went_up: r/c: base absent, working tree unusable, Rego absent"

echo "matrix-facts.sh says None. for each list that is empty"
out=$(MATRIX_FACTS_PAIRS=$dir/pairs.json MATRIX_FACTS_REGO=$dir/rego.json MATRIX_FACTS_RUST=$dir/base.json MATRIX_FACTS_BASE_RUST=$dir/base.json sh "$script" base matrix-a)
expect_out="## Matrix matrix-a

### Cause went down (usually a bug): 0

None.

### Says less than base (usually a bug): 0

None.

### Cause went up (usually the rule problems.all_said; list for the Rego steps): 0

None."
if [ "$out" != "$expect_out" ]; then
  echo "matrix-facts.sh should say None. three times, and printed: $out" >&2
  exit 1
fi

echo "matrix-facts.sh gives one heading for each generator it is given"
out=$(MATRIX_FACTS_PAIRS=$dir/pairs.json MATRIX_FACTS_REGO=$dir/rego.json MATRIX_FACTS_RUST=$dir/base.json MATRIX_FACTS_BASE_RUST=$dir/base.json sh "$script" base matrix-a walk)
if [ "$(printf '%s\n' "$out" | grep -c '^## Matrix ')" != 2 ] || ! printf '%s\n' "$out" | grep -q '^## Matrix walk$'; then
  echo "matrix-facts.sh should print a heading for matrix-a and one for walk, and printed: $out" >&2
  exit 1
fi

echo "matrix-facts.sh refuses a generator that does not exist"
if sh "$script" base nothing-here > /dev/null 2>&1; then
  echo "matrix-facts.sh should fail for an unknown generator" >&2
  exit 1
fi

repo=$(git -C "$(dirname "$script")" rev-parse --show-toplevel)

echo "matrix-facts.sh says when BASE is not a ref"
err=$(sh "$script" no-such-ref-here matrix-a 2>&1 >/dev/null) && {
  echo "matrix-facts.sh should fail for a BASE that is not a ref" >&2
  exit 1
}
case $err in
  *"cannot find BASE no-such-ref-here"*) ;;
  *)
    echo "matrix-facts.sh should say it cannot find BASE, and printed: $err" >&2
    exit 1
    ;;
esac

cat > "$dir/cargo" <<SH
#!/bin/sh
echo "\$ASDF_RUST_VERSION" >> "$dir/versions"
exit 1
SH
chmod +x "$dir/cargo"
tmp=$dir/tmp
mkdir "$tmp"
trees=$(git -C "$repo" worktree list | wc -l)

echo "matrix-facts.sh says the build failed on BASE, reads the Rust version from rust-toolchain.toml and removes what it made"
err=$(TMPDIR=$tmp MATRIX_FACTS_CARGO=$dir/cargo sh "$script" HEAD matrix-a 2>&1 >/dev/null) && {
  echo "matrix-facts.sh should fail when the build fails" >&2
  exit 1
}
case $err in
  *"the build failed on BASE HEAD"*) ;;
  *)
    echo "matrix-facts.sh should say the build failed on BASE HEAD, and printed: $err" >&2
    exit 1
    ;;
esac
want=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$repo/engines/rust/rust-toolchain.toml")
if [ "$(cat "$dir/versions")" != "$want" ]; then
  echo "matrix-facts.sh should build with Rust $want, and used: $(cat "$dir/versions")" >&2
  exit 1
fi
if [ -n "$(ls -A "$tmp")" ]; then
  echo "matrix-facts.sh should remove its temporary folder, and left: $(ls "$tmp")" >&2
  exit 1
fi
if [ "$(git -C "$repo" worktree list | wc -l)" != "$trees" ]; then
  echo "matrix-facts.sh should remove its worktree" >&2
  exit 1
fi
