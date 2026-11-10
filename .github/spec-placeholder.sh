#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

version=$(sed -n 's/^_spec := "\(v[0-9][0-9.]*\(-dev\)\{0,1\}\)"$/\1/p' engines/rego/ergo.rego)
[ -n "$version" ] || { echo 'ergo.rego must say _spec := "vX.Y" or _spec := "vX.Y-dev"'; exit 1; }

policy=engines/rust/engine/src/policy.rs
[ -r "$policy" ] || { echo "$policy is missing or not readable"; exit 1; }
rust=$(sed -n 's/^pub const SPEC: &str = "\(v[0-9][0-9.]*\(-dev\)\{0,1\}\)";$/\1/p' "$policy")
[ -n "$rust" ] || { echo "$policy must say pub const SPEC: &str = \"vX.Y\"; or \"vX.Y-dev\";"; exit 1; }
if [ "$rust" != "$version" ]; then
  echo "SPEC in $policy is $rust and _spec in engines/rego/ergo.rego is $version. They must be the same."
  exit 1
fi

paths="spec/cases engines/rust/engine/tests/regressions engines/rego/ergo_test.rego engines/rego/spec_test.rego"
for path in $paths; do
  [ -r "$path" ] || { echo "$path is missing or not readable, so the check can't look at it"; exit 1; }
done

pattern="(^|[^A-Za-z0-9.-])$(printf '%s' "$version" | sed 's/\./\\./g')(\$|[^A-Za-z0-9.-]|_|\\.(\$|[^0-9]))"

status=0
found=$(grep -rnE "$pattern" $paths | cut -c1-120) || status=$?
if [ "$status" -gt 1 ]; then
  echo "grep failed with status $status"
  exit 1
fi
if [ -n "$found" ]; then
  echo "$found"
  echo "These tests write the spec version $version. Write {{spec}} instead (ergo._spec in ergo_test.rego), so moving the spec version edits no test."
  exit 1
fi
