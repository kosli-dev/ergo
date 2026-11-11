#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"

stray=$(git ls-files '*.rego' | grep -v -E '^(engines/rego|examples)/|^engines/rust/sentences/tests/oracle/oracle_test\.rego$' || true)
if [ -n "$stray" ]; then
  echo "These Rego files are in a folder no OPA command loads:"
  printf '%s\n' "$stray" | sed 's/^/  /'
  echo "Add their folder to the OPA commands in .github/workflows/test.yml and AGENTS.md, and to .github/rego-folders.sh."
  exit 1
fi

hidden=$(git ls-files '*.rego' | grep -E '(^|/)src/' | grep -v -E '^engines/rego/src/' || true)
if [ -n "$hidden" ]; then
  echo "These Rego files are in a folder named src, which the OPA commands skip with --ignore src:"
  printf '%s\n' "$hidden" | sed 's/^/  /'
  echo "Only engines/rego/src may hold Rego in a folder named src. Rename the folder."
  exit 1
fi
