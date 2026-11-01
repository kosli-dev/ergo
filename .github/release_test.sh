#!/bin/bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/release.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

git init --quiet --bare "$dir/origin.git"
git clone --quiet "$dir/origin.git" "$dir/work" 2> /dev/null
cd "$dir/work"
git config user.name test
git config user.email test@example.com
mkdir -p .github bin engines/rego spec/policy spec/report engines/rust/engine engines/rust/cli engines/rust/sentences-wasm
cp "$script" .github/release.sh
printf '%s\n' '#!/bin/sh' 'echo 1' > bin/gh
chmod +x bin/gh
export PATH="$dir/work/bin:$PATH"

readme() {
  printf '%s\n' '```json' '  "engine": {' '    "name": "'"$1"'",' '    "version": "'"$2"'"' '  },' '  "ergo": "v0.1",' '```' > OPA.md
  printf '%s\n' 'curl -L https://github.com/kosli-dev/ergo/releases/download/rust-v'"$4"'/ergo-'"$4"'-macos-arm64.tar.gz | tar xz' 'On Linux, the file is `ergo-'"$4"'-linux-x86_64.tar.gz`.' 'The CLI gives {"name": "'"$3"'", "version": "'"$4"'"}.' > CLI.md
  printf '%s\n' 'ergo_spec: v0.1' '  "ergo": "v0.1",' > README.md
  printf '%s\n' 'ergo_spec: v0.1' > REFERENCE.md
}

setup() {
  readme ergo-rego 0.1.0 ergo-rust 0.1.0
  printf '%s\n' 'version := "0.1.0-dev"' '_spec := "v0.1"' > engines/rego/ergo.rego
  printf '%s\n' '## 0.1.0' 'First.' > CHANGELOG.md
  printf '%s\n' '## 0.1' 'First.' > spec/CHANGELOG.md
  printf '%s\n' '{' '  "$id": "https://ergo.kosli.com/spec/0.1/policy.schema.json"' '}' > spec/policy/schema.json
  printf '%s\n' '{' '  "$id": "https://ergo.kosli.com/spec/0.1/report.schema.json"' '}' > spec/report/schema.json
  printf '%s\n' '[workspace]' 'members = ["engine"]' '' '[workspace.package]' 'version = "'"$1"'"' 'edition = "2024"' '' '[profile.wasm]' 'version = "9.9.9"' > engines/rust/Cargo.toml
  printf '%s\n' '[dependencies]' 'ergo-policy-sentences = { path = "../sentences", version = "'"$1"'" }' 'regex = "1"' > engines/rust/engine/Cargo.toml
  printf '%s\n' '[[bin]]' 'name = "ergo"' 'path = "src/main.rs"' '' '[dependencies]' 'ergo-policy-engine = { path = "../engine", version = "'"$1"'" }' > engines/rust/cli/Cargo.toml
  printf '%s\n' '[dependencies]' 'ergo-policy-sentences = { path = "../sentences", version = "'"$1"'", features = ["serde"] }' > engines/rust/sentences-wasm/Cargo.toml
  printf '%s\n' '# Changes' '' '## '"$2" 'Something changed.' > engines/rust/CHANGELOG.md
  git add -A
  git commit --quiet --allow-empty -m "setup"
  git push --quiet --force origin HEAD:main 2> /dev/null
}

refuses() {
  local expected=$1 out
  shift
  if out=$(echo n | .github/release.sh "$@" 2>&1); then
    echo "release.sh $* should fail with \"$expected\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$expected"*) ;;
    *)
      echo "release.sh $* should fail with \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
}

setup 0.1.0 0.1.0
refuses "Nothing pushed." rust-v0.1.0
refuses "Tags look like" rust-v0.1
refuses "Tags look like" rust-v0.1.0-rc.1
refuses "must say version = \"0.2.0\" under [workspace.package], and says version = \"0.1.0\"" rust-v0.2.0
refuses "has -dev in it" rust-v0.1.0-dev

setup 0.1.0-dev 0.1.0
refuses "has -dev in it" rust-v0.1.0-dev
refuses "must say version = \"0.1.0\" under [workspace.package], and says version = \"0.1.0-dev\"" rust-v0.1.0

setup 0.1.0 0.1.0
sed -i.bak 's/path = "..\/engine", version = "0.1.0"/path = "..\/engine", version = "0.1.0-dev"/' engines/rust/cli/Cargo.toml
git commit --quiet -am "stale dependency"
git push --quiet origin HEAD:main 2> /dev/null
refuses "engines/rust/cli/Cargo.toml has a path dependency that doesn't say version = \"0.1.0\"" rust-v0.1.0

setup 0.1.0 "0.1.0 (not released yet)"
refuses "engines/rust/CHANGELOG.md on main has no \"## 0.1.0\" heading" rust-v0.1.0

setup 0.1.0 0.1.0
printf '%s\n' '# Changes' '' '## 0.1.0' '' '## 0.0.9' 'Old.' > engines/rust/CHANGELOG.md
git commit --quiet -am "empty notes"
git push --quiet origin HEAD:main 2> /dev/null
refuses "has nothing under \"## 0.1.0\"" rust-v0.1.0

setup 0.1.0 0.1.0
refuses "Nothing pushed." rego-v0.1.0
sed -i.bak 's/"version": "0.1.0"$/"version": "0.2.0"/' OPA.md
git commit --quiet -am "stale rego version"
git push --quiet origin HEAD:main 2> /dev/null
refuses "OPA.md on main must show the report's engine as \"name\": \"ergo-rego\" with \"version\": \"0.1.0\"" rego-v0.1.0
refuses "Nothing pushed." rust-v0.1.0

setup 0.1.0 0.1.0
readme ergo.rego 0.1.0 ergo-rust 0.1.0
git commit --quiet -am "old rego name"
git push --quiet origin HEAD:main 2> /dev/null
refuses "OPA.md on main must show the report's engine" rego-v0.1.0

setup 0.1.0 0.1.0
readme ergo-rego 0.1.0 ergo-rust 0.2.0
git commit --quiet -am "stale rust version"
git push --quiet origin HEAD:main 2> /dev/null
refuses "CLI.md on main must show the CLI's engine as {\"name\": \"ergo-rust\", \"version\": \"0.1.0\"}" rust-v0.1.0
refuses "Nothing pushed." rego-v0.1.0

setup 0.1.0 0.1.0
readme ergo-rego 0.1.0 ergo-policy-engine 0.1.0
git commit --quiet -am "old rust name"
git push --quiet origin HEAD:main 2> /dev/null
refuses "CLI.md on main must show the CLI's engine" rust-v0.1.0

setup 0.1.0 0.1.0
refuses "Nothing pushed." spec-v0.1
readme ergo-rego 0.1.0 ergo-rust 0.1.0
printf '%s\n' 'ergo_spec: v0.2' '  "ergo": "v0.1",' > README.md
git commit --quiet -am "stale spec in the example policy"
git push --quiet origin HEAD:main 2> /dev/null
refuses "README.md on main must show the policy with the line ergo_spec: v0.1" spec-v0.1
printf '%s\n' 'ergo_spec: v0.1' '  "ergo": "v0.2",' > README.md
git commit --quiet -am "stale spec in the report"
git push --quiet origin HEAD:main 2> /dev/null
refuses "README.md on main must show the report's \"ergo\": \"v0.1\"" spec-v0.1

setup 0.1.0 0.1.0
sed -i.bak 's/rust-v0.1.0\/ergo-0.1.0-macos/rust-v0.0.9\/ergo-0.0.9-macos/' CLI.md
git commit --quiet -am "stale download"
git push --quiet origin HEAD:main 2> /dev/null
refuses "CLI.md on main must have the download releases/download/rust-v0.1.0/ergo-0.1.0-macos-arm64.tar.gz" rust-v0.1.0

setup 0.1.0 0.1.0
sed -i.bak 's/linux-x86_64/linux-aarch64/' CLI.md
git commit --quiet -am "stale linux file"
git push --quiet origin HEAD:main 2> /dev/null
refuses "CLI.md on main must have the download ergo-0.1.0-linux-x86_64.tar.gz" rust-v0.1.0

setup 0.1.0 0.1.0
sed -i.bak 's/"ergo": "v0.1"/"ergo": "v0.0"/' OPA.md
git commit --quiet -am "stale spec in the OPA page"
git push --quiet origin HEAD:main 2> /dev/null
refuses "OPA.md on main must show the report's \"ergo\": \"v0.1\", the spec ergo.rego reads" rego-v0.1.0

setup 0.1.0 0.1.0
echo 'ergo_spec: v0.1-dev' >> OPA.md
git commit --quiet -am "a dev spec left in the OPA page"
git push --quiet origin HEAD:main 2> /dev/null
refuses "OPA.md on main still says v0.1-dev, the spec being released" rego-v0.1.0
refuses "OPA.md on main still says v0.1-dev, the spec being released" spec-v0.1

setup 0.1.0 0.1.0
echo 'ergo_spec: v0.1-dev' >> REFERENCE.md
git commit --quiet -am "a dev spec left in the reference"
git push --quiet origin HEAD:main 2> /dev/null
refuses "REFERENCE.md on main still says v0.1-dev, the spec being released" rego-v0.1.0
refuses "REFERENCE.md on main still says v0.1-dev, the spec being released" spec-v0.1

echo "release.sh refuses a rust tag with -dev, with a version that isn't the workspace's, without notes, and until CLI.md shows the engine and the download, OPA.md the spec, and README.md the spec of the example, and until no page says the spec is -dev"
