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

6 new tests (4 Rust, 2 Rego): 3 pass, 3 fail on the old source (good), 0 could not run.

Pass on the old source:
- engines/rego/tests/x_test.rego test_green_rule
- engines/rust/foo/src/tests.rs green_one
- engines/rust/foo/tests/api.rs api_new

<details>
<summary>Tests checked (6)</summary>

- engines/rego/tests/x_test.rego test_green_rule: passes
- engines/rego/tests/x_test.rego test_red_rule: fails
- engines/rust/foo/src/tests.rs green_one: passes
- engines/rust/foo/src/tests.rs red_one: fails
- engines/rust/foo/tests/api.rs api_new: passes
- engines/rust/foo/tests/api.rs red_api: fails

</details>"
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
  *"1 could not run."*"- engines/rust/foo/src/tests.rs none_one: could not run"*) ;;
  *)
    echo "red-check.sh should list the test that did not run, and printed: $out" >&2
    exit 1
    ;;
esac

if command -v opa > /dev/null 2>&1; then
  echo "red-check.sh runs a Rego test with opa and lists it when it passes"
  real=$dir/real
  mkdir -p "$real/.github" "$real/engines/rego/tests"
  cp "$here/red-check.sh" "$real/.github/red-check.sh"
  git -C "$real" init --quiet
  git -C "$real" config user.email t@example.com
  git -C "$real" config user.name t
  printf 'package ergo_test\n\nimport rego.v1\n\ntest_old if true\n' > "$real/engines/rego/tests/x_test.rego"
  git -C "$real" add -A
  git -C "$real" commit --quiet -m base
  realbase=$(git -C "$real" rev-parse HEAD)
  printf '\ntest_real_one if true\n' >> "$real/engines/rego/tests/x_test.rego"
  git -C "$real" commit --quiet -am head
  out=$(cd "$real" && RED_CHECK_BUILD_CMD='mkdir -p dist spec examples' env -u RED_CHECK_REGO_CMD -u RED_CHECK_RUST_CMD sh .github/red-check.sh "$realbase")
  case $out in
    *"Could not run"*)
      echo "red-check.sh could not run a passing Rego test, and printed: $out" >&2
      exit 1
      ;;
    *"- engines/rego/tests/x_test.rego test_real_one"*) ;;
    *)
      echo "red-check.sh should list test_real_one, and printed: $out" >&2
      exit 1
      ;;
  esac
else
  echo "opa is not on PATH, skipping the real Rego test"
fi

echo "red-check.sh runs cargo with the pinned Rust version, an exact test name and one touch per source"
fake=$dir/fake
mkdir -p "$fake/bin" "$fake/repo/.github" "$fake/repo/engines/rust/foo/src"
cp "$here/red-check.sh" "$fake/repo/.github/red-check.sh"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$ASDF_RUST_VERSION" "$*" "$(stat -f %%m foo/src/lib.rs 2>/dev/null || stat -c %%Y foo/src/lib.rs)" >> "$FAKE_LOG"\nsleep 1\nprintf "test tests::%%s ... ok\\ntest result: ok. 1 passed\\n" "${FAKE_RAN:-$(for a; do :; done; echo $a)}"\n' > "$fake/bin/cargo"
chmod +x "$fake/bin/cargo"
git -C "$fake/repo" init --quiet
git -C "$fake/repo" config user.email t@example.com
git -C "$fake/repo" config user.name t
printf '[toolchain]\nchannel = "1.2.3"\n' > "$fake/repo/engines/rust/rust-toolchain.toml"
printf '[package]\nname = "foo"\n' > "$fake/repo/engines/rust/foo/Cargo.toml"
printf 'fn main() {}\n' > "$fake/repo/engines/rust/foo/src/lib.rs"
printf '#[test]\nfn foo_bar() {}\n' > "$fake/repo/engines/rust/foo/src/tests.rs"
git -C "$fake/repo" add -A
git -C "$fake/repo" commit --quiet -m base
fakebase=$(git -C "$fake/repo" rev-parse HEAD)
printf '\n#[test]\nfn foo() {}\n\n#[test]\nfn foo_two() {}\n' >> "$fake/repo/engines/rust/foo/src/tests.rs"
git -C "$fake/repo" commit --quiet -am head
export FAKE_LOG=$fake/log
: > "$FAKE_LOG"
(cd "$fake/repo" && PATH=$fake/bin:$PATH env -u RED_CHECK_REGO_CMD -u RED_CHECK_RUST_CMD sh .github/red-check.sh "$fakebase" > /dev/null)
if [ "$(wc -l < "$FAKE_LOG" | tr -d ' ')" != 2 ]; then
  echo "cargo should have run twice, and ran: $(cat "$FAKE_LOG")" >&2
  exit 1
fi
if [ "$(cut -d'|' -f1 "$FAKE_LOG" | sort -u)" != 1.2.3 ]; then
  echo "cargo should run with the version in rust-toolchain.toml, and ran: $(cat "$FAKE_LOG")" >&2
  exit 1
fi
if grep -q -e '--exact' "$FAKE_LOG"; then
  echo "cargo should not get --exact, which needs the whole module path, and got: $(cat "$FAKE_LOG")" >&2
  exit 1
fi
if [ "$(cut -d'|' -f3 "$FAKE_LOG" | sort -u | wc -l | tr -d ' ')" != 1 ]; then
  echo "the sources should be touched once, and cargo saw: $(cat "$FAKE_LOG")" >&2
  exit 1
fi

echo "red-check.sh does not list a test that cargo did not run by that exact name"
out=$(cd "$fake/repo" && FAKE_RAN=foo_bar PATH=$fake/bin:$PATH env -u RED_CHECK_REGO_CMD -u RED_CHECK_RUST_CMD sh .github/red-check.sh "$fakebase")
case $out in
  *"0 pass"*"2 could not run."*) ;;
  *)
    echo "red-check.sh should count both tests as not run, and printed: $out" >&2
    exit 1
    ;;
esac
