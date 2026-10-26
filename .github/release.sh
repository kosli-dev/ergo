#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: .github/release.sh rego-vX.Y.Z [spec-vX.Y]"
  echo "Tags the commit at origin/main and pushes the tags. The release workflow does the rest."
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"
git fetch --quiet origin main
git fetch --quiet --tags origin
commit=$(git rev-parse origin/main)
files=$(mktemp -d)
trap 'rm -rf "$files"' EXIT
git archive "$commit" ergo.rego CHANGELOG.md spec/CHANGELOG.md spec/policy/schema.json spec/report/schema.json | tar -x -C "$files"

fail() {
  echo "$1"
  exit 1
}

check_rego() {
  local version=$1 tag=rego-v$1
  grep -qxF "version := \"$version-dev\"" "$files/ergo.rego" || fail "ergo.rego on main must say version := \"$version-dev\", and says $(grep -m 1 '^version := ' "$files/ergo.rego")"
  if grep -q '^_spec := "v.*-dev"$' "$files/ergo.rego"; then
    fail "ergo.rego on main says $(grep -m 1 '^_spec := ' "$files/ergo.rego"), a spec that isn't released. Release the spec first, or in this call: drop -dev from the spec in a pull request, then add its tag, like $tag spec-vX.Y"
  fi
  grep -qxF "## $version" "$files/CHANGELOG.md" || fail "CHANGELOG.md on main has no \"## $version\" heading"
  notes=$(awk -v h="## $version" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$files/CHANGELOG.md")
  grep -q '[^[:space:]]' <<<"$notes" || fail "CHANGELOG.md has nothing under \"## $version\", so there are no release notes"
}

check_spec() {
  local version=$1 name
  if grep -q '^_spec := "v.*-dev"$' "$files/ergo.rego"; then
    fail "ergo.rego on main says $(grep -m 1 '^_spec := ' "$files/ergo.rego"), so spec-v$version can't be tagged. Drop -dev from the spec everywhere in a pull request first."
  fi
  for name in policy report; do
    grep -q "^ *\"\\\$id\": *\".*/spec/$version/$name.schema.json\"" "$files/spec/$name/schema.json" || fail "spec/$name/schema.json has a \$id that doesn't end in /spec/$version/$name.schema.json"
  done
  grep -qxF "_spec := \"v$version\"" "$files/ergo.rego" || fail "ergo.rego on main must say _spec := \"v$version\", and says $(grep -m 1 '^_spec := ' "$files/ergo.rego")"
  grep -qxF "## $version" "$files/spec/CHANGELOG.md" || fail "spec/CHANGELOG.md on main has no \"## $version\" heading"
}

for tag in "$@"; do
  if [[ $tag =~ ^rego-v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    check_rego "${tag#rego-v}"
  elif [[ $tag =~ ^spec-v[0-9]+\.[0-9]+$ ]]; then
    check_spec "${tag#spec-v}"
  else
    fail "Tags look like rego-v0.1.0 or spec-v0.1, not $tag"
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
