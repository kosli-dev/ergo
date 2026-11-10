#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/spec-placeholder.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
mkdir -p engines/rego spec/cases/demo engines/rust/engine/tests/regressions/demo
echo '_spec := "v0.6-dev"' > engines/rego/ergo.rego
echo 'package ergo_test' > engines/rego/ergo_test.rego
echo 'package spec_test' > engines/rego/spec_test.rego
echo '[{"policy": {"ergo_spec": "{{spec}}"}, "other": "v0.5", "close": "v0.6-dev2", "longer": "xv0.6-dev"}]' > spec/cases/demo/cases.json
echo '[{"policy": {"ergo_spec": "{{spec}}"}}]' > engines/rust/engine/tests/regressions/demo/regressions.json
git add .

echo "spec-placeholder.sh passes when tests write the placeholder or another version"
sh "$script"

echo '[{"report": {"ergo": "v0.6-dev"}}]' > engines/rust/engine/tests/regressions/demo/regressions.json
echo 'x := {"ergo_spec": "v0.6-dev"}' >> engines/rego/ergo_test.rego
echo '[{"policy": {"ergo_spec": "v0.6-dev"}}]' > spec/cases/demo/cases.json
git add .
echo "spec-placeholder.sh fails and names each file that writes the current version"
if out=$(sh "$script" 2>&1); then
  echo "spec-placeholder.sh should fail, and passed" >&2
  exit 1
fi
for expected in "spec/cases/demo/cases.json" "engines/rust/engine/tests/regressions/demo/regressions.json" "engines/rego/ergo_test.rego" "Write {{spec}} instead"; do
  case $out in
    *"$expected"*) ;;
    *)
      echo "spec-placeholder.sh should say \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
done
