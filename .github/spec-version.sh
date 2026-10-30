#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail() {
  echo "$1"
  exit 1
}

defining=(
  spec/syntax.md
  spec/semantics.md
  spec/policy/schema.json
  spec/report/schema.json
  spec/sentences.abnf
  spec/cases
)

rego=$(sed -n 's/^_spec := "v\([0-9][0-9.]*\(-dev\)\{0,1\}\)"$/\1/p' engines/rego/ergo.rego)
[ -n "$rego" ] || fail 'ergo.rego must say _spec := "vX.Y" or _spec := "vX.Y-dev"'

for name in policy report; do
  id=$(sed -n "s|^ *\"\\\$id\": *\".*/spec/\\([^/]*\\)/$name.schema.json\",\{0,1\}\$|\\1|p" "spec/$name/schema.json")
  [ -n "$id" ] || fail "spec/$name/schema.json has no \$id that ends in /spec/X.Y/$name.schema.json"
  [ "$id" = "$rego" ] || fail "spec/$name/schema.json says $id in its \$id, but ergo.rego says _spec := \"v$rego\". They must match."
done

version=${rego%-dev}
if [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then :; else fail "The spec version v$rego must look like v0.2 or v0.2-dev"; fi

latest=$(git tag --list 'spec-v*' | grep -E '^spec-v[0-9]+\.[0-9]+$' | sed 's/^spec-v//' | sort -V | tail -n 1 || true)

dev=false
[ "$rego" != "$version" ] && dev=true
next=
[ -n "$latest" ] && next="${latest%%.*}.$((10#${latest#*.} + 1))"

if [ -n "$latest" ] && [ "$version" != "$latest" ]; then
  [ "$version" = "$next" ] || fail "The spec says v$rego, but the latest release is spec-v$latest, so it must say v$next-dev, or v$next when it's ready to release"
fi

if $dev || { [ -n "$latest" ] && [ "$version" != "$latest" ]; }; then
  grep -qxF "## $version" spec/CHANGELOG.md || fail "spec/CHANGELOG.md has no \"## $version\" heading for v$rego"
  exit 0
fi

[ -n "$latest" ] || exit 0

if ! git diff --quiet "spec-v$latest" -- "${defining[@]}"; then
  echo "Changed since spec-v$latest:"
  git diff --name-only "spec-v$latest" -- "${defining[@]}" | sed 's/^/  /'
  fail "spec/ changed since spec-v$latest, so move the spec to v${latest%%.*}.$((10#${latest#*.} + 1))-dev"
fi
