#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=$here/message-cuts.sh
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
root=$dir/root
mkdir -p "$root/.github" "$root/engines/rust/engine/src/ops/inner" "$root/engines/rust/engine/src/tests" "$root/engines/rego/src/messages"
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
run() {
  (cd "$root" && MESSAGE_CUTS_ROOT=$root sh "$script" "$@" 2>&1)
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
g() {
  git -C "$root" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"
}
commit() {
  g add -A
  g commit -q -m "$1"
}

echo "message-cuts.sh counts per pattern and per file, leaving out tests"
out=$(run)
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

g init -q -b main
commit base

echo "message-cuts.sh --against passes when the counts equal the base"
out=$(run --against main)
expect_in "total 7" "$out"

echo "message-cuts.sh --against fails when a cut is added and prints the lines the author added"
g checkout -q -b add
printf 'fn d(t: &str) { t.split("; "); }\n' >> "$root/engines/rust/engine/src/ops/inner/b.rs"
if out=$(run --against main); then
  echo "message-cuts.sh should fail on an increase" >&2
  exit 1
fi
expect_in "rust-split-semicolon went from 2 to 3" "$out"
expect_in "engines/rust/engine/src/ops/inner/b.rs:4:" "$out"
expect_in 'fn d(t: &str) { t.split("; "); }' "$out"
expect_not_in "engines/rust/engine/src/a.rs" "$out"
expect_in "total went from 7 to 8" "$out"

echo "message-cuts.sh --against lists the added line, not the first lines by file"
printf 'fn e(t: &str) { t.split("; "); }\n' >> "$root/engines/rust/engine/src/z.rs"
out=$(run --against main || true)
expect_in "engines/rust/engine/src/z.rs:1:" "$out"
expect_in "engines/rust/engine/src/ops/inner/b.rs:4:" "$out"

echo "message-cuts.sh --against passes when an allowed pattern goes up"
printf 'rust-split-semicolon\n' > "$root/.github/message-cuts.allow"
out=$(run --against main)
expect_in "total 9" "$out"
/bin/rm -f "$root/.github/message-cuts.allow"
g checkout -q -f main
g clean -fdq

echo "message-cuts.sh --against fails when one pattern goes up and another down, although the total is the same"
g checkout -q -b swap
sed -i.bak '/split("; ")/d' "$root/engines/rust/engine/src/a.rs"
/bin/rm -f "$root/engines/rust/engine/src/a.rs.bak"
for n in 1 2 3 4; do
  printf 'fn e%s(t: &str) { t.starts_with("item "); }\n' "$n" >> "$root/engines/rust/engine/src/a.rs"
done
if out=$(run --against main); then
  echo "message-cuts.sh should fail when a pattern goes up" >&2
  exit 1
fi
expect_in "rust-item-prefix-starts went from 1 to 5" "$out"
g checkout -q -f main
g clean -fdq

echo "message-cuts.sh --against passes when a cut is removed"
g checkout -q -b remove
sed -i.bak '/starts_with/d' "$root/engines/rust/engine/src/ops/inner/b.rs"
/bin/rm -f "$root/engines/rust/engine/src/ops/inner/b.rs.bak"
out=$(run --against main)
expect_in "total 6" "$out"
commit remove
g checkout -q main

echo "message-cuts.sh --against judges a branch that is behind main by its own change"
g checkout -q -b behind
g checkout -q main
printf 'fn m(t: &str) { t.find(" of "); }\n' >> "$root/engines/rust/engine/src/m.rs"
commit "main adds a cut"
g checkout -q behind
sed -i.bak '/starts_with/d' "$root/engines/rust/engine/src/ops/inner/b.rs"
/bin/rm -f "$root/engines/rust/engine/src/ops/inner/b.rs.bak"
out=$(run --against main)
expect_in "total 6" "$out"
printf 'fn n(t: &str) { t.split("; "); }\n' >> "$root/engines/rust/engine/src/n.rs"
if out=$(run --against main); then
  echo "message-cuts.sh should fail on the cut the branch added" >&2
  exit 1
fi
expect_in "rust-split-semicolon went from 2 to 3" "$out"
expect_not_in "rust-find-of went" "$out"
g checkout -q -f main
g clean -fdq

echo "message-cuts.sh fails when the ref does not exist"
if out=$(run --against nowhere); then
  echo "message-cuts.sh should fail without the ref" >&2
  exit 1
fi

echo "message-cuts.sh fails on an unknown argument"
if run --update > /dev/null; then
  echo "message-cuts.sh should fail on an unknown argument" >&2
  exit 1
fi

echo "message-cuts.sh tests passed"
