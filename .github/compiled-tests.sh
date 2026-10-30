#!/usr/bin/env bash
set -euo pipefail

pattern=$(.github/tests.sh | .github/test-pattern.sh)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
git ls-files | grep -v -E '^(\.github|site|packages)/' | tar -cf - -T - | tar -xf - -C "$dir"

plain='} else := _run(doc, policy, _read(policy), params)'
if [ "$(grep -cxF "$plain" "$dir/ergo.rego")" -ne 1 ]; then
  echo "ergo.rego no longer has the line this script changes: $plain"
  exit 1
fi
python3 - "$dir/ergo.rego" "$plain" <<'PY'
import sys
path, plain = sys.argv[1], sys.argv[2]
text = open(path).read()
compiled = "} else := _run(doc, c.policy, _from_compiled(c), params) if {\n\tc := _compiled(compile(policy))\n" + plain + "\n"
open(path, "w").write(text.replace(plain + "\n", compiled))
PY

cd "$dir"
opa test . --ignore packages --ignore ports --timeout 120s -r "$pattern"
