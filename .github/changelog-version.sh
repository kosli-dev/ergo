#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail() {
  echo "$1"
  exit 1
}

kind=${1:-}
case $kind in
  rego)
    tagprefix=rego-v
    changelog=CHANGELOG.md
    files='engines/rego/ergo.rego, README.md and REFERENCE.md'
    version=$(sed -n 's/^version := "\([0-9]*\.[0-9]*\.[0-9]*\)-dev"$/\1/p' engines/rego/ergo.rego)
    [ -n "$version" ] || fail 'ergo.rego must say version := "X.Y.Z-dev" on main'
    ;;
  rust)
    tagprefix=rust-v
    changelog=engines/rust/CHANGELOG.md
    files='the Cargo.toml files of engines/rust and README.md'
    version=$(sed -n 's/^version = "\([0-9]*\.[0-9]*\.[0-9]*\)\(-dev\)\{0,1\}"$/\1/p' engines/rust/Cargo.toml | head -n 1)
    [ -n "$version" ] || fail 'engines/rust/Cargo.toml must say version = "X.Y.Z" or "X.Y.Z-dev" under [workspace.package]'
    ;;
  *) fail "usage: changelog-version.sh rego|rust" ;;
esac

heading=$(sed -n 's/^## \(.*\)$/\1/p' "$changelog" | head -n 1)
heading=${heading% (not released yet)}
[[ $heading =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "The first heading of $changelog must look like ## 0.3.1, and says ## $heading"

tags=$(git tag --list "$tagprefix*" | grep -E "^${tagprefix}[0-9]+\.[0-9]+\.[0-9]+\$" | sed "s/^$tagprefix//" || true)

if printf '%s\n' "$tags" | grep -qxF "$heading"; then
  expected="${heading%.*}.$((10#${heading##*.} + 1))"
  [ "$version" = "$expected" ] || fail "$changelog has no heading above $heading, which is released as $tagprefix$heading, so nothing has changed since and the version must be $expected, and it is $version. Change the version in $files to $expected. The first change after a release adds its heading and moves the version to match."
  exit 0
fi

[ "$version" = "$heading" ] || fail "$changelog starts with ## $heading, which isn't released yet, but the version is $version. They must be the same. Change the heading, or the version in $files."

previous=$(printf '%s\n' "$tags" | sort -V | while read -r t; do
  if [ -n "$t" ] && [ "$(printf '%s\n%s\n' "$t" "$heading" | sort -V | head -n 1)" = "$t" ]; then echo "$t"; fi
done | tail -n 1)
[ -n "$previous" ] || exit 0

section=$(awk '/^## / { n++ } n == 1' "$changelog")
if printf '%s\n' "$section" | grep -qE '^### (Changed|Removed)$'; then
  pmajor=${previous%%.*}
  rest=${previous#*.}
  pminor=${rest%%.*}
  major=${version%%.*}
  rest=${version#*.}
  minor=${rest%%.*}
  if [ "$pmajor" = 0 ]; then
    if [ "$major" -gt "$pmajor" ] || [ "$minor" -gt "$pminor" ]; then exit 0; fi
    needed="0.$((pminor + 1)).0"
  else
    if [ "$major" -gt "$pmajor" ]; then exit 0; fi
    needed="$((pmajor + 1)).0.0"
  fi
  fail "$changelog lists a change under ### Changed or ### Removed for $heading, which can break a policy or a report, so the version must go above $previous, to $needed or higher. Change the heading and the version in $files."
fi
