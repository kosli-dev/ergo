#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: .github/checks.sh [--rego] [--spec] [--rust] [--all]

Runs the checks most changes need, one at a time, from the root of the repo.
It keeps going after a failure and lists the failed checks at the end.

With no flag it runs the quick checks: building dist/ergo.rego, opa check,
opa fmt, regal lint, the folder, folder-order, placeholder and no-comment checks, and the
spec rules and sentences corpus checks.

  --rego   also run opa test and the opa eval with --strict-builtin-errors
  --spec   also run the spec schema and grammar checks, in a Python
           virtual environment at /tmp/ergo-venv
  --rust   also run the Rust checks in Docker (the ergo-rust image from
           engines/rust/README.md) and the grammar check against Rust
  --all    same as --rego --spec --rust
  --help   show this text

The commands are the ones in the "Checks" section of AGENTS.md.

It leaves out the tests compiled to Wasm, the tests in OPA's JavaScript
runtime, the coverage run and the packages checks. Run those by hand, as
AGENTS.md says, or leave them to CI.
USAGE
}

rego=0
spec=0
rust=0
for arg in "$@"; do
  case $arg in
    --rego) rego=1 ;;
    --spec) spec=1 ;;
    --rust) rust=1 ;;
    --all) rego=1; spec=1; rust=1 ;;
    --help | -h) usage; exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=()

check() {
  local title=$1 tools=$2 command=$3 tool
  echo
  echo "== $title"
  for tool in $tools; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Missing tool: $tool is needed for \"$title\" and is not on your PATH."
      failed+=("$title")
      return 0
    fi
  done
  if bash -c "set -euo pipefail; $command"; then
    echo "ok"
  else
    echo "FAILED: $title"
    failed+=("$title")
  fi
}

venv=${ERGO_CHECKS_VENV:-/tmp/ergo-venv}

fmt_command='files=$(opa fmt --list engines/rego examples engines/rust/sentences/tests/oracle); if [ -n "$files" ]; then echo "$files"; echo "Run opa fmt -w on these files."; exit 1; fi'

comments_command=$(cat <<'COMMAND'
comments=$(git ls-files '*.rego' | while read -r f; do opa parse "$f" --format json --json-include comments,locations | jq -r --arg f "$f" '.package.location.row as $p | .comments[]? | .Location.row as $r | select(($f == "engines/rego/src/package.rego" and $r < $p) | not) | "\($f):\($r)"'; done)
if [ -n "$comments" ]; then echo "These lines have comments:"; echo "$comments"; exit 1; fi
COMMAND
)

deterministic_command=$(cat <<'COMMAND'
opa capabilities --current | jq '.builtins |= map(select(.nondeterministic != true))' > /tmp/ergo-deterministic.json && opa check --strict --capabilities /tmp/ergo-deterministic.json dist/ergo.rego
COMMAND
)

strict_command=$(cat <<'COMMAND'
out=$(opa eval --strict-builtin-errors -d engines/rego -d dist -d spec:spec -d examples:examples --ignore src --format raw 'count(data) > 0'); echo "$out"; [ "$out" = true ]
COMMAND
)

rust_command=$(cat <<'COMMAND'
docker run --rm -v "$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust sh -c '
  find . -name "*.rs" -exec touch {} + &&
  cargo fmt --check &&
  cargo clippy -j 4 --locked --all-targets --all-features -- -D warnings &&
  cargo test -j 4 --locked --all-features -- --show-output &&
  RUSTDOCFLAGS="-D warnings" cargo doc -j 4 --locked --no-deps --all-features &&
  cargo test -j 4 --locked -p ergo-policy-engine --features serde_json/preserve_order --test key_order &&
  cargo build -j 4 --locked -p ergo-policy-sentences --target wasm32-unknown-unknown'
COMMAND
)

rust_grammar_command=$(cat <<COMMAND
$venv/bin/python spec/check_grammar.py --rust 'docker run --rm -i -v "\$PWD":/src -v ergo-rust-target:/target -v ergo-cargo-registry:/usr/local/cargo/registry ergo-rust cargo run --locked -q --release -p ergo-policy-sentences --example read'
COMMAND
)

check "build dist/ergo.rego" "" '.github/build-ergo.sh'
check "build-ergo.sh test" "" '.github/build-ergo_test.sh'
check "opa check" "opa" 'opa check --strict engines/rego dist spec:spec examples:examples --ignore src'
check "opa check with the closed input schema" "opa" 'opa check --strict --schema .github/closed-input-schema.json dist/ergo.rego'
check "opa check without nondeterministic built-ins" "opa jq" "$deterministic_command"
check "opa fmt" "opa" "$fmt_command"
check "regal lint" "regal" 'regal lint --disable-all --enable-category bugs --disable redundant-existence-check engines/rego examples engines/rust/sentences/tests/oracle'
check "rego-folders.sh" "git" '.github/rego-folders.sh'
check "rego-folders.sh test" "git" '.github/rego-folders_test.sh'
check "rego-layers.py" "python3" 'python3 .github/rego-layers.py'
check "rego-layers.py test" "git" '.github/rego-layers_test.sh'
check "spec-placeholder.sh" "git" '.github/spec-placeholder.sh'
check "spec-placeholder.sh test" "git" '.github/spec-placeholder_test.sh'
check "spec rules" "python3" 'python3 spec/check_rules.py'
check "sentences corpus" "python3" 'python3 spec/sentences_corpus.py --check'
check "no comments in Rego" "opa jq git" "$comments_command"

if [ "$rego" = 1 ]; then
  check "opa test" "opa" 'opa test engines/rego dist spec:spec examples:examples --ignore src --timeout 120s'
  check "opa eval with --strict-builtin-errors" "opa" "$strict_command"
fi

if [ "$spec" = 1 ] || [ "$rust" = 1 ]; then
  check "Python virtual environment" "python3" "python3 -m venv $venv && $venv/bin/pip install --quiet jsonschema==4.26.0 abnf==2.9.0"
fi

if [ "$spec" = 1 ]; then
  check "spec schemas" "python3" "$venv/bin/python .github/spec-schemas.py"
  check "spec grammar" "python3" "$venv/bin/python spec/check_grammar.py"
fi

if [ "$rust" = 1 ]; then
  check "Rust checks in Docker" "docker" "$rust_command"
  check "spec grammar against Rust" "docker python3" "$rust_grammar_command"
fi

echo
if [ "${#failed[@]}" -gt 0 ]; then
  echo "${#failed[@]} check(s) failed:"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
echo "All checks passed."
