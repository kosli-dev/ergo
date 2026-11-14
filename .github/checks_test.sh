#!/usr/bin/env bash
set -euo pipefail

script=$(cd "$(dirname "$0")" && pwd)/checks.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

tools=$dir/tools
repo=$dir/repo
mkdir -p "$tools" "$repo/.github" "$repo/spec"

for name in bash sh git cat sed grep mkdir dirname touch env tr date rm printf; do
  real=$(command -v "$name")
  ln -s "$real" "$tools/$name"
done

for name in opa regal jq python3 docker; do
  printf '#!/bin/sh\nif [ "$1" = fmt ] && [ -n "${FAKE_FMT_OUTPUT:-}" ]; then echo "$FAKE_FMT_OUTPUT"; fi\nif [ "$1" = eval ]; then echo true; fi\nif [ "$1" = test ] && [ -n "${FAKE_OPA_TEST_FAILS:-}" ]; then exit 1; fi\nexit 0\n' > "$dir/$name"
  chmod +x "$dir/$name"
done

mkdir -p "$dir/venv/bin"
for name in pip python; do
  printf '#!/bin/sh\nexit 0\n' > "$dir/venv/bin/$name"
  chmod +x "$dir/venv/bin/$name"
done
export ERGO_CHECKS_VENV="$dir/venv"

for name in build-ergo build-ergo_test no-inline-tests no-inline-tests_test rego-folders rego-folders_test rego-layers_test spec-placeholder spec-placeholder_test; do
  printf '#!/bin/sh\n[ ! -e "%s/fail-%s" ]\n' "$dir" "$name" > "$repo/.github/$name.sh"
  chmod +x "$repo/.github/$name.sh"
done
cp "$script" "$repo/.github/checks.sh"
git -C "$repo" init --quiet

with_all_tools() {
  mkdir -p "$dir/all"
  for name in opa regal jq python3 docker; do
    ln -sf "$dir/$name" "$dir/all/$name"
  done
}
with_all_tools

run() {
  (cd "$repo" && env PATH="$dir/all:$tools" "$@" bash .github/checks.sh "${FLAGS[@]}") 2>&1
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

FLAGS=()

echo "checks.sh passes when every check passes and says so"
out=$(run FAKE=1)
expect_in "All checks passed." "$out"
expect_not_in "== opa test" "$out"
expect_not_in "== spec schemas" "$out"
expect_not_in "== Rust checks in Docker" "$out"

echo "checks.sh --help prints the usage and what it leaves out, and exits 0"
FLAGS=(--help)
out=$(run FAKE=1)
expect_in "Usage: .github/checks.sh" "$out"
expect_in "Wasm" "$out"
expect_in "coverage" "$out"

echo "checks.sh fails on an unknown flag, prints the usage and runs no check"
FLAGS=(--nope)
if out=$(run FAKE=1); then
  echo "checks.sh should fail on an unknown flag" >&2
  exit 1
fi
expect_in "Unknown flag: --nope" "$out"
expect_in "Usage: .github/checks.sh" "$out"
expect_not_in "== " "$out"

echo "checks.sh --rego adds the opa test and the strict opa eval"
FLAGS=(--rego)
out=$(run FAKE=1)
expect_in "== opa test" "$out"
expect_in "== opa eval with --strict-builtin-errors" "$out"
expect_not_in "== spec schemas" "$out"

echo "checks.sh --spec adds the schema and grammar checks, and --rust the Docker ones"
FLAGS=(--spec)
out=$(run FAKE=1)
expect_in "== spec schemas" "$out"
expect_in "== spec grammar" "$out"
expect_not_in "== Rust checks in Docker" "$out"
FLAGS=(--rust)
out=$(run FAKE=1)
expect_in "== Rust checks in Docker" "$out"
expect_in "== spec grammar against Rust" "$out"
expect_not_in "== spec schemas" "$out"

echo "checks.sh --all and combined flags run every group"
FLAGS=(--all)
out=$(run FAKE=1)
for expected in "== opa test" "== spec schemas" "== Rust checks in Docker"; do
  expect_in "$expected" "$out"
done
FLAGS=(--rego --spec --rust)
out2=$(run FAKE=1)
if [ "$out" != "$out2" ]; then
  echo "--all and --rego --spec --rust should run the same checks" >&2
  exit 1
fi

echo "checks.sh keeps going after a failure, lists every failed check and exits non-zero"
touch "$dir/fail-rego-folders"
touch "$dir/fail-spec-placeholder"
FLAGS=(--rego)
if out=$(run FAKE_OPA_TEST_FAILS=1); then
  echo "checks.sh should fail when a check fails" >&2
  exit 1
fi
expect_in "FAILED: rego-folders.sh" "$out"
expect_in "FAILED: spec-placeholder.sh" "$out"
expect_in "FAILED: opa test" "$out"
expect_in "== opa eval with --strict-builtin-errors" "$out"
expect_in "3 check(s) failed:" "$out"
expect_in "  rego-folders.sh" "$out"
expect_in "  spec-placeholder.sh" "$out"
expect_in "  opa test" "$out"
expect_not_in "All checks passed." "$out"
rm -f "$dir/fail-rego-folders" "$dir/fail-spec-placeholder"

echo "checks.sh fails opa fmt when it prints a file name, and names the file"
FLAGS=()
if out=$(run FAKE_FMT_OUTPUT=engines/rego/src/demo.rego); then
  echo "checks.sh should fail when opa fmt prints a file" >&2
  exit 1
fi
expect_in "engines/rego/src/demo.rego" "$out"
expect_in "FAILED: opa fmt" "$out"
expect_in "1 check(s) failed:" "$out"

echo "checks.sh names the missing tool and the check that needs it"
mkdir -p "$dir/no-regal"
for name in opa jq python3 docker; do
  ln -sf "$dir/$name" "$dir/no-regal/$name"
done
FLAGS=()
if out=$( (cd "$repo" && env PATH="$dir/no-regal:$tools" bash .github/checks.sh) 2>&1 ); then
  echo "checks.sh should fail when a tool is missing" >&2
  exit 1
fi
expect_in "Missing tool: regal is needed for \"regal lint\" and is not on your PATH." "$out"
expect_in "1 check(s) failed:" "$out"
expect_not_in "FAILED:" "$out"

echo "checks.sh names a missing docker only for the Rust checks"
mkdir -p "$dir/no-docker"
for name in opa regal jq python3; do
  ln -sf "$dir/$name" "$dir/no-docker/$name"
done
if out=$( (cd "$repo" && env PATH="$dir/no-docker:$tools" bash .github/checks.sh --rust) 2>&1 ); then
  echo "checks.sh --rust should fail without docker" >&2
  exit 1
fi
expect_in "Missing tool: docker is needed for \"Rust checks in Docker\"" "$out"
expect_in "2 check(s) failed:" "$out"
out=$( (cd "$repo" && env PATH="$dir/no-docker:$tools" bash .github/checks.sh) 2>&1 )
expect_in "All checks passed." "$out"

echo "checks.sh tests passed"
