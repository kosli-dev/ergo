#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/mutants-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

repo=$dir/repo
mkdir -p "$repo/.github" "$repo/engines/rust/engine/src" "$repo/engines/rust/engine/tests"
cp "$script" "$repo/.github/mutants-facts.sh"
git -C "$repo" init --quiet
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
printf 'fn a() {}\n' > "$repo/engines/rust/engine/src/lib.rs"
printf 'fn t() {}\n' > "$repo/engines/rust/engine/tests/it.rs"
printf 'fn u() {}\n' > "$repo/engines/rust/engine/src/tests.rs"
git -C "$repo" add .
git -C "$repo" commit --quiet -m base
git -C "$repo" branch base

mkdir "$dir/bin"
cat > "$dir/bin/cargo" <<'SH'
#!/bin/sh
echo "$@" > "$FAKE_ARGS"
if [ engine/src/lib.rs -nt "$FAKE_MARK" ]; then echo yes > "$FAKE_TOUCHED"; fi
while [ $# -gt 0 ]; do
  case $1 in
    --output) out=$2; shift ;;
    --in-diff) cp "$2" "$FAKE_DIFF"; shift ;;
  esac
  shift
done
if [ -n "${FAKE_MUTATE:-}" ]; then echo mutated >> engine/src/lib.rs; fi
mkdir -p "$out/mutants.out"
printf 'a.rs:1:1: caught one\na.rs:2:1: caught two\n' > "$out/mutants.out/caught.txt"
printf 'engine/src/lib.rs:7:5: replace a with ()\n' > "$out/mutants.out/missed.txt"
printf 'a.rs:3:1: slow\n' > "$out/mutants.out/timeout.txt"
printf 'a.rs:4:1: no build\na.rs:5:1: no build\n' > "$out/mutants.out/unviable.txt"
if [ -n "${FAKE_SLEEP:-}" ]; then sleep "$FAKE_SLEEP"; fi
exit "${FAKE_EXIT:-2}"
SH
chmod +x "$dir/bin/cargo"

run() {
  (cd "$repo" && FAKE_MARK=$dir/mark FAKE_TOUCHED=$dir/touched FAKE_ARGS=$dir/args FAKE_DIFF=$dir/diff MUTANTS_FACTS_CARGO=$dir/bin/cargo sh .github/mutants-facts.sh "$@")
}

fail() {
  echo "mutants-facts.sh should $1, and printed: $out" >&2
  exit 1
}

echo "mutants-facts.sh says so and runs nothing when no Rust source line changed"
printf 'fn t() { 1; }\n' > "$repo/engines/rust/engine/tests/it.rs"
printf 'fn u() { 1; }\n' > "$repo/engines/rust/engine/src/tests.rs"
git -C "$repo" commit --quiet -am "tests only"
out=$(run base)
[ "$out" = "No line of Rust source changed, so there is nothing to mutate." ] || fail "say no source changed"
[ ! -e "$dir/args" ] || fail "not run cargo"

touch -t 200101010000 "$dir/mark"

echo "mutants-facts.sh counts mutants and lists the missed ones, and gives cargo only the source lines"
printf 'fn a() { 1; }\n' > "$repo/engines/rust/engine/src/lib.rs"
git -C "$repo" commit --quiet -am "source"
touch -t 200001010000 "$repo/engines/rust/engine/src/lib.rs"
out=$(run base)
for row in "| caught   | 2 |" "| missed   | 1 |" "| unviable | 2 |" "| timeout  | 1 |"; do
  case $out in
    *"$row"*) ;;
    *) fail "count the four outcomes, with $row" ;;
  esac
done
case $out in
  *"engine/src/lib.rs:7:5: replace a with ()"*) ;;
  *) fail "list the missed mutant" ;;
esac
[ -e "$dir/touched" ] || fail "touch the sources so that cargo rebuilds them in place"
grep -q '^+++ b/engine/src/lib.rs' "$dir/diff" || fail "pass the source file in the diff, with its path from engines/rust"
if grep -q 'tests' "$dir/diff"; then echo "mutants-facts.sh should leave test files out of the diff" >&2; exit 1; fi

echo "mutants-facts.sh stops at the time limit and says so"
out=$(FAKE_SLEEP=30 MUTANTS_FACTS_TIMEOUT=1 run base)
case $out in
  *"Stopped after 1 seconds"*) ;;
  *) fail "say it stopped at the limit" ;;
esac

echo "mutants-facts.sh fails when cargo-mutants itself fails"
if (FAKE_EXIT=4 run base > /dev/null 2>&1); then
  echo "mutants-facts.sh should exit non-zero when cargo-mutants exits 4" >&2
  exit 1
fi

echo "mutants-facts.sh puts the Rust sources back when cargo-mutants leaves one mutated, even when it fails"
(FAKE_MUTATE=1 FAKE_EXIT=4 run base > /dev/null 2>&1) || true
[ -z "$(git -C "$repo" status --porcelain engines/rust)" ] || {
  echo "mutants-facts.sh should restore engines/rust after a failed run, and git says: $(git -C "$repo" status --porcelain engines/rust)" >&2
  exit 1
}

echo "mutants-facts.sh puts the Rust sources back after a run that finishes"
out=$(FAKE_MUTATE=1 run base)
[ -z "$(git -C "$repo" status --porcelain engines/rust)" ] || fail "restore engines/rust after a finished run"

echo "mutants-facts.sh warns and leaves the Rust sources alone when they were changed before it started"
echo dirty >> "$repo/engines/rust/engine/src/lib.rs"
FAKE_MUTATE=1 run base > "$dir/out.txt" 2> "$dir/err.txt"
grep -qF 'uncommitted' "$dir/err.txt" || {
  echo "mutants-facts.sh should warn about uncommitted changes in engines/rust, and said: $(cat "$dir/err.txt")" >&2
  exit 1
}
grep -qx dirty "$repo/engines/rust/engine/src/lib.rs" || {
  echo "mutants-facts.sh should not restore engines/rust when it started dirty" >&2
  exit 1
}
