#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"

stray=$(git ls-files '*.rego' | grep -v -E '^(engines/rego|spec|examples)/|^engines/rust/sentences/tests/oracle/oracle_test\.rego$' || true)
if [ -n "$stray" ]; then
  echo "These Rego files are in a folder no OPA command loads:"
  printf '%s\n' "$stray" | sed 's/^/  /'
  echo "Add their folder to the OPA commands in .github/workflows/test.yml and AGENTS.md, and to .github/rego-folders.sh."
  exit 1
fi
