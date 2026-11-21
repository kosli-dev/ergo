#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=$here/message-cuts.sh
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
root=$dir/root
mkdir -p "$root/engines/rust/engine/src/ops/inner" "$root/engines/rust/engine/src/tests" "$root/engines/rego/src/messages"
cat > "$root/engines/rust/engine/src/a.rs" <<'RS'
fn a(text: &str) {
    for piece in text.split("; ") {}
    let rest = text.strip_prefix("item ");
    let both = text.split("; ").count();
}
RS
cat > "$root/engines/rust/engine/src/ops/inner/b.rs" <<'RS'
fn b(text: &str) -> bool {
    text.starts_with("item ")
}
RS
cat > "$root/engines/rust/engine/src/tests.rs" <<'RS'
fn t(text: &str) {
    text.split("; ");
    text.split("; ");
}
RS
cat > "$root/engines/rust/engine/src/tests/c.rs" <<'RS'
fn c(text: &str) {
    text.split("; ");
}
RS
cat > "$root/engines/rego/src/messages/m.rego" <<'RG'
package ergo

x := split(said, "; ")
y := [z | some z in split(x, ", and ")]
w if startswith(p, "item ")
RG
baseline=$dir/baseline
run() {
  MESSAGE_CUTS_ROOT=$root MESSAGE_CUTS_BASELINE=$baseline sh "$script" "$@" 2>&1
}
expect_in() {
  case $2 in
    *"$1"*) ;;
    *)
      echo "expected \"$1\" in the output, got: $2" >&2
      exit 1
      ;;
  esac
}
expect_not_in() {
  case $2 in
    *"$1"*)
      echo "did not expect \"$1\" in the output, got: $2" >&2
      exit 1
      ;;
  esac
}

echo "message-cuts.sh --update writes a baseline and counts per pattern and per file, leaving out tests"
out=$(run --update)
expect_in "rust-split-semicolon engines/rust/engine/src/a.rs 2" "$out"
expect_in "rust-item-prefix-starts engines/rust/engine/src/ops/inner/b.rs 1" "$out"
expect_in "rust-item-prefix-strips engines/rust/engine/src/a.rs 1" "$out"
expect_in "rego-split-semicolon engines/rego/src/messages/m.rego 1" "$out"
expect_in "rego-split-and engines/rego/src/messages/m.rego 1" "$out"
expect_in "rego-item-prefix engines/rego/src/messages/m.rego 1" "$out"
expect_not_in "tests.rs" "$out"
expect_not_in "tests/c.rs" "$out"
expect_in "rust-split-semicolon total 2" "$out"
expect_in "total 7" "$out"
grep -q '^rust-split-semicolon 2$' "$baseline"
grep -q '^total 7$' "$baseline"

echo "message-cuts.sh passes when the counts equal the baseline"
out=$(run)
expect_in "total 7" "$out"
expect_not_in "lower than baseline" "$out"

echo "message-cuts.sh fails on an increase and prints the lines that match"
printf 'fn d(t: &str) { t.split("; "); }\n' >> "$root/engines/rust/engine/src/ops/inner/b.rs"
if out=$(run); then
  echo "message-cuts.sh should fail on an increase" >&2
  exit 1
fi
expect_in "rust-split-semicolon went from 2 to 3" "$out"
expect_in "engines/rust/engine/src/ops/inner/b.rs:4:" "$out"
expect_in "total went from 7 to 8" "$out"

echo "message-cuts.sh fails when one pattern goes up and another down, although the total is the same"
sed -i.bak '/split("; ")/d' "$root/engines/rust/engine/src/a.rs"
/bin/rm -f "$root/engines/rust/engine/src/a.rs.bak"
for n in 1 2 3 4; do
  printf 'fn e%s(t: &str) { t.starts_with("item "); }\n' "$n" >> "$root/engines/rust/engine/src/a.rs"
done
if out=$(run); then
  echo "message-cuts.sh should fail when a pattern goes up" >&2
  exit 1
fi
expect_in "rust-item-prefix-starts went from 1 to 5" "$out"

echo "message-cuts.sh passes on a decrease and says to update the baseline"
run --update > /dev/null
sed -i.bak '/starts_with/d' "$root/engines/rust/engine/src/ops/inner/b.rs"
/bin/rm -f "$root/engines/rust/engine/src/ops/inner/b.rs.bak"
out=$(run)
expect_in "lower than baseline, run message-cuts.sh --update" "$out"

echo "message-cuts.sh --update lowers the baseline"
run --update > /dev/null
out=$(run)
expect_not_in "lower than baseline" "$out"

echo "message-cuts.sh fails when the baseline is missing"
/bin/rm -f "$baseline"
if out=$(run); then
  echo "message-cuts.sh should fail without a baseline" >&2
  exit 1
fi
expect_in "no baseline" "$out"

echo "message-cuts.sh fails on an unknown argument"
if run --other > /dev/null; then
  echo "message-cuts.sh should fail on an unknown argument" >&2
  exit 1
fi

echo "message-cuts.sh tests passed"
