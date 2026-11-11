#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/spec-placeholder.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
mkdir -p engines/rego/src/shared engines/rego/tests engines/rust/engine/src engines/rust/engine/tests spec/cases/demo engines/rust/engine/tests/regressions/demo
echo '_spec := "v0.6-dev"' > engines/rego/src/shared/basics.rego
echo 'pub const SPEC: &str = "v0.6-dev";' > engines/rust/engine/src/policy.rs
echo 'fn t() { let _ = SPEC; }' > engines/rust/engine/tests/demo.rs
echo 'package ergo_test' > engines/rego/tests/ergo_test.rego
echo 'package spec_test' > engines/rego/tests/spec_test.rego
echo '[{"policy": {"ergo_spec": "{{spec}}"}, "other": "v0.5", "rc": "v0.6-dev-rc", "close": "v0.6-dev2", "longer": "xv0.6-dev", "wide": "v0.60-dev", "suffix": "v0.6-devx", "minor": "v0.6-dev.1", "bare": "0.6-dev"}]' > spec/cases/demo/cases.json
echo '[{"policy": {"ergo_spec": "{{spec}}"}}]' > engines/rust/engine/tests/regressions/demo/regressions.json
git add .

fails() {
  if out=$(sh "$script" 2>&1); then
    echo "spec-placeholder.sh should fail, and passed" >&2
    exit 1
  fi
  for expected in "$@"; do
    case $out in
      *"$expected"*) ;;
      *)
        echo "spec-placeholder.sh should say \"$expected\", and said: $out" >&2
        exit 1
        ;;
    esac
  done
}

echo "spec-placeholder.sh passes when tests write the placeholder or another version"
sh "$script"

echo "spec-placeholder.sh fails and names each file that writes the current version"
echo '[{"report": {"ergo": "v0.6-dev"}}]' > engines/rust/engine/tests/regressions/demo/regressions.json
echo 'x := {"ergo_spec": "v0.6-dev"}' >> engines/rego/tests/ergo_test.rego
echo '[{"policy": {"ergo_spec": "v0.6-dev"}}]' > spec/cases/demo/cases.json
git add .
fails "spec/cases/demo/cases.json" "engines/rust/engine/tests/regressions/demo/regressions.json" "engines/rego/tests/ergo_test.rego" "Write {{spec}} instead"

echo "spec-placeholder.sh fails when the version is followed or preceded by punctuation"
echo 'package ergo_test' > engines/rego/tests/ergo_test.rego
echo '[{"report": {"ergo": "ok"}}]' > engines/rust/engine/tests/regressions/demo/regressions.json
for text in 'expected v0.6-dev.' 'v0.6-dev_a' 'a_v0.6-dev' 'v0.6-dev, then' '(v0.6-dev)' 'v0.6-dev'; do
  printf '[{"text": "%s"}]\n' "$text" > spec/cases/demo/cases.json
  fails "spec/cases/demo/cases.json"
done

echo "spec-placeholder.sh leaves other versions alone"
for text in 'v0.6-dev-rc' 'v0.60-dev' 'v0.6-devx' 'v0.6-dev.1' 'xv0.6-dev' '0.6-dev' 'v0.6'; do
  printf '[{"text": "%s"}]\n' "$text" > spec/cases/demo/cases.json
  sh "$script"
done

echo "spec-placeholder.sh does not treat a dot in the version as any character"
for text in 'v0x6-dev' 'v006-dev' 'v0-6-dev'; do
  printf '[{"text": "%s"}]\n' "$text" > spec/cases/demo/cases.json
  sh "$script"
done
printf '[{"text": "%s"}]\n' 'v0.6-dev' > spec/cases/demo/cases.json
fails "spec/cases/demo/cases.json"

echo "spec-placeholder.sh does the same when _spec has no -dev"
echo '_spec := "v0.6"' > engines/rego/src/shared/basics.rego
echo 'pub const SPEC: &str = "v0.6";' > engines/rust/engine/src/policy.rs
for text in 'v0.6.' 'v0.6_a' 'a_v0.6' 'v0.6'; do
  printf '[{"text": "%s"}]\n' "$text" > spec/cases/demo/cases.json
  fails "spec/cases/demo/cases.json"
done
for text in 'v0.6-dev' 'v0.60' 'v0.6.1' 'v0.6x' 'v0.6-rc'; do
  printf '[{"text": "%s"}]\n' "$text" > spec/cases/demo/cases.json
  sh "$script"
done
echo '_spec := "v0.6-dev"' > engines/rego/src/shared/basics.rego
echo 'pub const SPEC: &str = "v0.6-dev";' > engines/rust/engine/src/policy.rs
echo '[{"text": "{{spec}}"}]' > spec/cases/demo/cases.json

echo "spec-placeholder.sh fails and names a Rust file that writes the current version"
echo 'fn t() { let _ = "ergo_spec: v0.6-dev"; }' > engines/rust/engine/tests/demo.rs
git add .
fails "engines/rust/engine/tests/demo.rs" "Write {{spec}} instead"
echo 'fn t() { let _ = "v0.5"; }' > engines/rust/engine/tests/demo.rs
git add .
sh "$script"
echo 'fn t() { let _ = SPEC; }' > engines/rust/engine/tests/demo.rs
git add .

echo "spec-placeholder.sh fails when no Rust file is tracked besides policy.rs"
git rm --quiet --cached engines/rust/engine/tests/demo.rs
fails "no Rust files are tracked"
git add .

echo "spec-placeholder.sh fails when Rust SPEC differs from _spec and names both"
echo 'pub const SPEC: &str = "v0.5";' > engines/rust/engine/src/policy.rs
fails "v0.5" "v0.6-dev" "engines/rust/engine/src/policy.rs"

echo "spec-placeholder.sh fails when policy.rs has no SPEC line or is missing"
echo 'pub const OTHER: &str = "v0.6-dev";' > engines/rust/engine/src/policy.rs
fails "must say pub const SPEC"
/bin/rm -f engines/rust/engine/src/policy.rs
fails "policy.rs is missing"
echo 'pub const SPEC: &str = "v0.6-dev";' > engines/rust/engine/src/policy.rs

echo "spec-placeholder.sh fails when a path it scans is missing"
for path in spec/cases engines/rust/engine/tests/regressions engines/rego/tests; do
  /bin/mv -f "$path" "$path.away"
  fails "$path is missing"
  /bin/mv -f "$path.away" "$path"
done

echo "spec-placeholder.sh fails when a file it scans cannot be read"
if [ "$(id -u)" -eq 0 ]; then
  echo "skipped: root can read any file"
else
  echo '[{"text": "ok"}]' > spec/cases/demo/cases.json
  chmod 000 spec/cases/demo/cases.json
  fails "grep failed with status"
  chmod 644 spec/cases/demo/cases.json
fi

sh "$script"
