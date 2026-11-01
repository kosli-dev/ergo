#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: .github/release.sh rego-vX.Y.Z [spec-vX.Y] [rust-vX.Y.Z]"
  echo "Tags the commit at origin/main and pushes the tags. The release workflow does the rest."
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"
git fetch --quiet origin main
git fetch --quiet --tags origin
commit=$(git rev-parse origin/main)
files=$(mktemp -d)
trap 'rm -rf "$files"' EXIT
git archive "$commit" README.md OPA.md CLI.md engines/rego/ergo.rego CHANGELOG.md spec/CHANGELOG.md spec/policy/schema.json spec/report/schema.json engines/rust/Cargo.toml engines/rust/CHANGELOG.md engines/rust/engine/Cargo.toml engines/rust/cli/Cargo.toml engines/rust/sentences-wasm/Cargo.toml | tar -x -C "$files"

fail() {
  echo "$1"
  exit 1
}

page_shows() {
  tr -d '[:space:]' < "$files/$1" | grep -qF "$(tr -d '[:space:]' <<<"$2")"
}

check_rego() {
  local version=$1 tag=rego-v$1
  grep -qxF "version := \"$version-dev\"" "$files/engines/rego/ergo.rego" || fail "ergo.rego on main must say version := \"$version-dev\", and says $(grep -m 1 '^version := ' "$files/engines/rego/ergo.rego")"
  if grep -q '^_spec := "v.*-dev"$' "$files/engines/rego/ergo.rego"; then
    fail "ergo.rego on main says $(grep -m 1 '^_spec := ' "$files/engines/rego/ergo.rego"), a spec that isn't released. Release the spec first, or in this call: drop -dev from the spec in a pull request, then add its tag, like $tag spec-vX.Y"
  fi
  grep -qxF "## $version" "$files/CHANGELOG.md" || fail "CHANGELOG.md on main has no \"## $version\" heading"
  notes=$(awk -v h="## $version" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$files/CHANGELOG.md")
  spec=$(sed -n 's/^_spec := "\(v[0-9.]*\)"$/\1/p' "$files/engines/rego/ergo.rego")
  grep -qF "\"ergo\": \"$spec\"" "$files/OPA.md" || fail "OPA.md on main must show the report's \"ergo\": \"$spec\", the spec ergo.rego reads. Change it in a pull request first."
  page_shows OPA.md "\"name\": \"ergo-rego\", \"version\": \"$version\"" || fail "OPA.md on main must show the report's engine as \"name\": \"ergo-rego\" with \"version\": \"$version\". Change it in a pull request, from a run of that commit's ergo.rego."
  grep -q '[^[:space:]]' <<<"$notes" || fail "CHANGELOG.md has nothing under \"## $version\", so there are no release notes"
}

check_spec() {
  local version=$1 name
  if grep -q '^_spec := "v.*-dev"$' "$files/engines/rego/ergo.rego"; then
    fail "ergo.rego on main says $(grep -m 1 '^_spec := ' "$files/engines/rego/ergo.rego"), so spec-v$version can't be tagged. Drop -dev from the spec everywhere in a pull request first."
  fi
  for name in policy report; do
    grep -q "^ *\"\\\$id\": *\".*/spec/$version/$name.schema.json\"" "$files/spec/$name/schema.json" || fail "spec/$name/schema.json has a \$id that doesn't end in /spec/$version/$name.schema.json"
  done
  grep -qxF "_spec := \"v$version\"" "$files/engines/rego/ergo.rego" || fail "ergo.rego on main must say _spec := \"v$version\", and says $(grep -m 1 '^_spec := ' "$files/engines/rego/ergo.rego")"
  grep -qxF "## $version" "$files/spec/CHANGELOG.md" || fail "spec/CHANGELOG.md on main has no \"## $version\" heading"
  grep -qxF "ergo_spec: v$version" "$files/README.md" || fail "README.md on main must show the policy with the line ergo_spec: v$version. Change it in a pull request first."
  grep -qF "\"ergo\": \"v$version\"" "$files/README.md" || fail "README.md on main must show the report's \"ergo\": \"v$version\". Change it in a pull request first."
}

check_rust() {
  local version=$1 says dep
  if [[ $version == *-dev ]]; then
    fail "rust-v$version has -dev in it. Crates are released without -dev: set the version to ${version%-dev} in a pull request first."
  fi
  says=$(awk '/^\[workspace\.package\]$/ { on = 1; next } /^\[/ { on = 0 } on && /^version = / { print }' "$files/engines/rust/Cargo.toml")
  [ "$says" = "version = \"$version\"" ] || fail "engines/rust/Cargo.toml on main must say version = \"$version\" under [workspace.package], and says ${says:-no version}"
  for dep in engine/Cargo.toml cli/Cargo.toml sentences-wasm/Cargo.toml; do
    if grep '{.*path = "[^"]*"' "$files/engines/rust/$dep" | grep -qv "version = \"$version\""; then
      fail "engines/rust/$dep has a path dependency that doesn't say version = \"$version\""
    fi
  done
  grep -qxF "## $version" "$files/engines/rust/CHANGELOG.md" || fail "engines/rust/CHANGELOG.md on main has no \"## $version\" heading"
  page_shows CLI.md "{\"name\": \"ergo-rust\", \"version\": \"$version\"}" || fail "CLI.md on main must show the CLI's engine as {\"name\": \"ergo-rust\", \"version\": \"$version\"}. Change it in a pull request first."
  for file in "releases/download/rust-v$version/ergo-$version-macos-arm64.tar.gz" "ergo-$version-linux-x86_64.tar.gz"; do
    grep -qF "$file" "$files/CLI.md" || fail "CLI.md on main must have the download $file. Change it in a pull request first."
  done
  notes=$(awk -v h="## $version" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$files/engines/rust/CHANGELOG.md")
  grep -q '[^[:space:]]' <<<"$notes" || fail "engines/rust/CHANGELOG.md has nothing under \"## $version\", so there are no release notes"
}

for tag in "$@"; do
  if [[ $tag =~ ^rust-v[0-9]+\.[0-9]+\.[0-9]+(-dev)?$ ]]; then
    check_rust "${tag#rust-v}"
  elif [[ $tag =~ ^rego-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    check_rego "${tag#rego-v}"
  elif [[ $tag =~ ^spec-v[0-9]+\.[0-9]+$ ]]; then
    check_spec "${tag#spec-v}"
  else
    fail "Tags look like rego-v0.1.0, spec-v0.1 or rust-v0.1.0, not $tag"
  fi
  if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
    if [ -n "$(git ls-remote --tags origin "refs/tags/$tag")" ]; then
      fail "The tag $tag already exists on origin, on $(git rev-parse "$tag^{commit}")"
    fi
    fail "The tag $tag exists here but not on origin. Delete it with git tag -d $tag, then run this again."
  fi
done

passed=$(gh run list --workflow test.yml --commit "$commit" --status success --json databaseId --jq length)
if [ "${passed:-0}" -le 0 ]; then
  fail "The test workflow hasn't passed on $commit yet. Wait for it, then run this again."
fi

echo "Tag $(git log -1 --format='%h %s' "$commit") with: $*"
printf 'Push? [y/N] '
read -r answer
[ "$answer" = y ] || fail "Nothing pushed."

for tag in "$@"; do
  git tag --annotate --message "$tag" "$tag" "$commit"
done
git push origin "$@"
echo "Pushed. The release workflow is at $(gh repo view --json url --jq .url)/actions/workflows/release.yml"
