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
  if [ "$version" = "$heading" ]; then
    echo "::warning::$changelog and the version both say $heading, but $tagprefix$heading is already released. Merge the pull request that moves main to the next patch version."
    exit 0
  fi
  expected="${heading%.*}.$((10#${heading##*.} + 1))"
  [ "$version" = "$expected" ] || fail "$changelog has no heading above $heading, which is released as $tagprefix$heading, so nothing has changed since and the version must be $expected, and it is $version. Change the version in $files to $expected. The first change after a release adds its heading and moves the version to match."
  exit 0
fi

[ "$version" = "$heading" ] || fail "$changelog starts with ## $heading, which isn't released yet, but the version is $version. They must be the same. Change the heading, or the version in $files."

previous=$(printf '%s\n' "$tags" | sort -V | tail -n 1)
[ -n "$previous" ] || exit 0

pmajor=${previous%%.*}
rest=${previous#*.}
pminor=${rest%%.*}
patch="$pmajor.$pminor.$((10#${previous##*.} + 1))"
minor="$pmajor.$((10#$pminor + 1)).0"
major="$((10#$pmajor + 1)).0.0"
if [ "$version" != "$patch" ] && [ "$version" != "$minor" ] && [ "$version" != "$major" ]; then
  fail "$changelog starts with ## $heading, but the latest release is $tagprefix$previous, so the next version must be $patch, $minor or $major. Change the heading and the version in $files."
fi

section=$(awk '/^## / { n++ } n == 1' "$changelog")
if printf '%s\n' "$section" | grep -qE '^### (Changed|Removed)$'; then
  if [ "$pmajor" = 0 ]; then
    [ "$version" != "$patch" ] && exit 0
    needed=$minor
  else
    [ "$version" = "$major" ] && exit 0
    needed=$major
  fi
  fail "$changelog lists a change under ### Changed or ### Removed for $heading, which can break a policy or a report, so the version must go above $previous, to $needed or higher. Change the heading and the version in $files."
fi
