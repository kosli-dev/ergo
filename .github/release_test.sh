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

setup() {
  printf '%s\n' 'version := "0.1.0-dev"' '_spec := "v0.1"' > engines/rego/ergo.rego
  printf '%s\n' '## 0.1.0' 'First.' > CHANGELOG.md
  printf '%s\n' '## 0.1' 'First.' > spec/CHANGELOG.md
  : > spec/policy/schema.json
  : > spec/report/schema.json
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

echo "release.sh refuses a rust tag with -dev, with a version that isn't the workspace's, and without notes"
