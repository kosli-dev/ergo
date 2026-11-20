#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
repo=$dir/repo
mkdir -p "$repo/.github" "$repo/engines/rust/foo/src" "$repo/engines/rust/foo/tests" "$repo/engines/rego/tests"
cp "$here/red-check.sh" "$repo/.github/red-check.sh"
git -C "$repo" init --quiet
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t

printf '[package]\nname = "foo"\n' > "$repo/engines/rust/foo/Cargo.toml"
printf '#[test]\nfn old_one() {}\n' > "$repo/engines/rust/foo/src/tests.rs"
printf '#[test]\nfn api_old() {}\n' > "$repo/engines/rust/foo/tests/api.rs"
printf 'package ergo_test\n\ntest_old if true\n' > "$repo/engines/rego/tests/x_test.rego"
printf 'fn main() {}\n' > "$repo/engines/rust/foo/src/lib.rs"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m base
base=$(git -C "$repo" rev-parse HEAD)

printf '#[test]\nfn old_one() {}\n\n#[test]\nfn red_one() {}\n\n#[test]\nfn green_one() {}\n' > "$repo/engines/rust/foo/src/tests.rs"
printf '#[test]\nfn api_old() {}\n\n#[test]\nfn api_new() {}\n\n#[test]\nfn red_api() {}\n' > "$repo/engines/rust/foo/tests/api.rs"
printf 'package ergo_test\n\ntest_old if true\n\ntest_red_rule if true\n\ntest_green_rule if true\n' > "$repo/engines/rego/tests/x_test.rego"
printf 'fn main() {}\n\n#[test]\nfn inline_one() {}\n' > "$repo/engines/rust/foo/src/lib.rs"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m head

printf '#!/bin/sh\nshift\nfor a; do name=$a; done\ncase "$name" in red*) exit 1 ;; none*) exit 3 ;; esac\nprintf "%%s\\n" "$*" >> "$RED_CHECK_LOG"\nexit 0\n' > "$dir/rust.sh"
printf '#!/bin/sh\ncase "$2" in test_red*) exit 1 ;; esac\nprintf "%%s\\n" "$2" >> "$RED_CHECK_LOG"\nexit 0\n' > "$dir/rego.sh"
chmod +x "$dir/rust.sh" "$dir/rego.sh"
export RED_CHECK_LOG=$dir/log
: > "$RED_CHECK_LOG"
export RED_CHECK_RUST_CMD=$dir/rust.sh
export RED_CHECK_REGO_CMD=$dir/rego.sh
export RED_CHECK_BUILD_CMD=true

run() {
  (cd "$repo" && sh .github/red-check.sh "$1")
}

echo "red-check.sh lists the new tests that pass on the old source and skips the ones that fail"
out=$(run "$base")
expected="## New tests that already pass on the old source

6 new tests (4 Rust, 2 Rego), 3 pass on $base:
- engines/rego/tests/x_test.rego test_green_rule
- engines/rust/foo/src/tests.rs green_one
- engines/rust/foo/tests/api.rs api_new"
if [ "$out" != "$expected" ]; then
  echo "red-check.sh should print:" >&2
  echo "$expected" >&2
  echo "and printed:" >&2
  echo "$out" >&2
  exit 1
fi

echo "red-check.sh runs each test in the crate and target its file belongs to"
log=$(sort "$RED_CHECK_LOG" | tr '\n' ';')
case $log in
  *"foo --lib green_one"*"foo --test api api_new"*"test_green_rule"*) ;;
  *)
    echo "red-check.sh ran the wrong tests: $log" >&2
    exit 1
    ;;
esac

echo "red-check.sh removes its worktree"
count=$(git -C "$repo" worktree list | wc -l | tr -d ' ')
if [ "$count" != 1 ]; then
  echo "red-check.sh left a worktree behind" >&2
  exit 1
fi

echo "red-check.sh says so when no test was added"
out=$(run "HEAD")
if [ "$out" != "## New tests that already pass on the old source

No test was added." ]; then
  echo "red-check.sh should say no test was added, and printed: $out" >&2
  exit 1
fi

echo "red-check.sh lists a test that could not run"
printf '\n#[test]\nfn none_one() {}\n' >> "$repo/engines/rust/foo/src/tests.rs"
git -C "$repo" commit --quiet -am more
out=$(run "$base")
case $out in
  *"Could not run: 1"*"- engines/rust/foo/src/tests.rs none_one"*) ;;
  *)
    echo "red-check.sh should list the test that did not run, and printed: $out" >&2
    exit 1
    ;;
esac
