#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

version=$(sed -n 's/^_spec := "\(v[0-9][0-9.]*\(-dev\)\{0,1\}\)"$/\1/p' engines/rego/ergo.rego)
[ -n "$version" ] || { echo 'ergo.rego must say _spec := "vX.Y" or _spec := "vX.Y-dev"'; exit 1; }

pattern="(^|[^A-Za-z0-9._-])$(printf '%s' "$version" | sed 's/\./\\./g')([^A-Za-z0-9._-]|\$)"

found=$(grep -rnE "$pattern" spec/cases engines/rust/engine/tests/regressions engines/rego/ergo_test.rego engines/rego/spec_test.rego | cut -c1-120 || true)
if [ -n "$found" ]; then
  echo "$found"
  echo "These tests write the spec version $version. Write {{spec}} instead (ergo._spec in ergo_test.rego), so moving the spec version edits no test."
  exit 1
fi
