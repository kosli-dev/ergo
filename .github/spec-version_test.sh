#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/spec-version.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
git config user.email test@example.com
git config user.name test
mkdir -p engines/rego engines/rust/engine/src spec/policy spec/report spec/cases packages/a site/assets/js/tutorial .github examples/x

reset_files() {
  echo '_spec := "v0.6-dev"' > engines/rego/ergo.rego
  echo 'version := "0.6.0-dev"' >> engines/rego/ergo.rego
  echo 'pub const SPEC: &str = "v0.6-dev";' > engines/rust/engine/src/policy.rs
  printf '{\n  "$id": "https://ergo.kosli.com/spec/0.6-dev/policy.schema.json",\n  "const": "v0.6-dev"\n}\n' > spec/policy/schema.json
  printf '{\n  "$id": "https://ergo.kosli.com/spec/0.6-dev/report.schema.json",\n  "ergo": {"const": "v0.6-dev"}\n}\n' > spec/report/schema.json
  printf 'ergo_spec: v0.6-dev\nexpected ergo-rego 0.6.0-dev\nold v0.5 and v0.60-dev and v0.6-devx and v0.6\n' > REFERENCE.md
  echo 'ergo_spec: v0.6-dev' > OPA.md
  echo 'ergo_spec: v0.6-dev' > spec/syntax.md
  echo 'ergo_spec: v0.6-dev' > spec/semantics.md
  echo 'ergo_spec: v0.6-dev' > packages/a/case.md
  echo 'ergo_spec: "v0.6-dev"' > site/assets/js/tutorial/lib.mjs
  echo 'ergo_spec: "v0.6-dev"' > .github/wasm-js.cjs
  echo 'ergo_spec: v0.6-dev' > examples/x/policy.yaml
  echo 'ergo_spec: v0.6-dev' > README.md
  echo 'v0.6-dev' > CLI.md
  echo '## 0.6' > spec/CHANGELOG.md
  echo 'v0.6-dev' > packages/CHANGELOG.md
  echo 'v0.6-dev' > .github/other_test.sh
  git add .
}

reset_files

fails() {
  if out=$(bash "$script" "$@" 2>&1); then
    echo "spec-version.sh $* should fail, and passed" >&2
    exit 1
  fi
}

says() {
  case $out in
    *"$1"*) ;;
    *)
      echo "spec-version.sh should say \"$1\", and said: $out" >&2
      exit 1
      ;;
  esac
}

echo "set refuses a version that is not vX.Y or vX.Y-dev"
fails set 0.7-dev
fails set v0.7.1
fails set v0.7-rc
fails set
says "Usage"

echo "set refuses the version it already has"
fails set v0.6-dev
says "already says v0.6-dev"

echo "set moves every file that writes the spec version"
bash "$script" set v0.7-dev > "$dir/out"
for f in engines/rego/ergo.rego engines/rust/engine/src/policy.rs spec/policy/schema.json spec/report/schema.json REFERENCE.md OPA.md spec/syntax.md spec/semantics.md packages/a/case.md site/assets/js/tutorial/lib.mjs .github/wasm-js.cjs examples/x/policy.yaml; do
  grep -qx "$f" "$dir/out" || { echo "set should list $f" >&2; exit 1; }
  if grep -q '0\.6-dev' "$f" && [ "$f" != REFERENCE.md ]; then
    echo "$f still says 0.6-dev" >&2
    exit 1
  fi
done
grep -qF '_spec := "v0.7-dev"' engines/rego/ergo.rego
grep -qF 'pub const SPEC: &str = "v0.7-dev";' engines/rust/engine/src/policy.rs
grep -qF '"https://ergo.kosli.com/spec/0.7-dev/policy.schema.json"' spec/policy/schema.json
grep -qF '"const": "v0.7-dev"' spec/policy/schema.json
grep -qF '"https://ergo.kosli.com/spec/0.7-dev/report.schema.json"' spec/report/schema.json
grep -qF '"ergo": {"const": "v0.7-dev"}' spec/report/schema.json

echo "set leaves README.md, CLI.md, changelogs, tests and engine versions alone"
grep -qx 'ergo_spec: v0.6-dev' README.md
grep -qx 'v0.6-dev' CLI.md
grep -qx 'v0.6-dev' packages/CHANGELOG.md
grep -qx 'v0.6-dev' .github/other_test.sh
grep -qx '## 0.6' spec/CHANGELOG.md
grep -qF 'version := "0.6.0-dev"' engines/rego/ergo.rego
grep -qF 'expected ergo-rego 0.6.0-dev' REFERENCE.md

echo "set matches the exact version, not a longer one"
grep -qF 'v0.60-dev and v0.6-devx and v0.6' REFERENCE.md
grep -qF 'old v0.5 ' REFERENCE.md

echo "set says what is left to do by hand"
grep -qF 'README.md, CLI.md' "$dir/out"
grep -qF '"## 0.7" heading' "$dir/out"

echo "set also moves a version that is not a dev one"
git add .
bash "$script" set v0.8 > "$dir/out"
grep -qF '_spec := "v0.8"' engines/rego/ergo.rego
grep -qF 'spec/0.8/policy.schema.json' spec/policy/schema.json
grep -qF 'v0.60-dev and v0.6-devx and v0.6' REFERENCE.md

echo "set only matches v0.6 as a whole version"
reset_files
echo '_spec := "v0.6"' > engines/rego/ergo.rego
echo 'a v0.6 b v0.60 c v0.6.1 d v0.6-dev e xv0.6' > REFERENCE.md
git add .
bash "$script" set v0.7 > /dev/null
grep -qxF 'a v0.7 b v0.60 c v0.6.1 d v0.6-dev e xv0.6' REFERENCE.md

echo "the check fails and names a file that still writes the previous dev version"
reset_files
echo '## 0.7' > spec/CHANGELOG.md
echo '_spec := "v0.7-dev"' > engines/rego/ergo.rego
sed -i.bak 's/0\.6-dev/0.7-dev/' spec/policy/schema.json spec/report/schema.json
rm -f spec/policy/schema.json.bak spec/report/schema.json.bak
git add .
git -c commit.gpgSign=false commit --quiet -m one
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag --no-sign spec-v0.6
fails
says "REFERENCE.md"
says "v0.6-dev"
says "set v0.7-dev"
if echo "$out" | grep -qE 'CLI.md|README.md|CHANGELOG|other_test'; then
  echo "the check should not name README.md, CLI.md, changelogs or tests, and said: $out" >&2
  exit 1
fi

echo "the check passes once set has moved the version"
reset_files
echo '## 0.7' > spec/CHANGELOG.md
echo '_spec := "v0.6-dev"' > engines/rego/ergo.rego
git add .
bash "$script" set v0.7-dev > /dev/null
echo '## 0.7' > spec/CHANGELOG.md
bash "$script"
