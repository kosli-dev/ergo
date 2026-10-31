#!/bin/bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/changelog-version.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

git init --quiet "$dir/work"
cd "$dir/work"
git config user.name test
git config user.email test@example.com
mkdir -p engines/rego engines/rust
git commit --quiet --allow-empty -m setup

setup() {
  printf '%s\n' "version := \"$1-dev\"" > engines/rego/ergo.rego
  printf '%s\n' '# Changes' '' "## $2" '' ${3:+"$3"} 'Text.' > CHANGELOG.md
  printf '%s\n' '[workspace.package]' "version = \"$1-dev\"" > engines/rust/Cargo.toml
  printf '%s\n' '# Changes' '' "## $2 (not released yet)" '' ${3:+"$3"} 'Text.' > engines/rust/CHANGELOG.md
}

tag() {
  git update-ref "refs/tags/rego-v$1" HEAD
  git update-ref "refs/tags/rust-v$1" HEAD
}

passes() {
  for kind in rego rust; do
    if ! out=$(bash "$script" $kind 2>&1); then
      echo "changelog-version.sh $kind should pass for $*, and said: $out" >&2
      exit 1
    fi
  done
}

fails() {
  local expected=$1 out
  for kind in rego rust; do
    if out=$(bash "$script" $kind 2>&1); then
      echo "changelog-version.sh $kind should fail with \"$expected\", and passed" >&2
      exit 1
    fi
    case $out in
      *"$expected"*) ;;
      *)
        echo "changelog-version.sh $kind should fail with \"$expected\", and said: $out" >&2
        exit 1
        ;;
    esac
  done
}

setup 0.1.0 0.1.0
passes "a first version with no tags"

tag 0.1.0
setup 0.1.1 0.1.0
passes "the patch after a release"

setup 0.2.0 0.1.0
fails "the version must be 0.1.1, and it is 0.2.0"

setup 0.1.0 0.1.0
for kind in rego rust; do
  out=$(bash "$script" $kind 2>&1) || { echo "changelog-version.sh $kind should only warn when the released version is still on main, and said: $out" >&2; exit 1; }
  case $out in
    "::warning::"*"Merge the pull request that moves main to the next patch version."*) ;;
    *) echo "changelog-version.sh $kind should warn when the released version is still on main, and said: $out" >&2; exit 1 ;;
  esac
done

setup 0.1.1 0.1.1
passes "a patch with a new heading"

setup 0.1.1 0.1.1 '### New'
passes "a patch with New and Fixed"

setup 0.1.1 0.1.1 '### Fixed'
passes "a patch with Fixed"

setup 0.1.2 0.1.1
fails "which isn't released yet, but the version is 0.1.2"

setup 0.1.1 0.1.2
fails "which isn't released yet, but the version is 0.1.1"

setup 0.1.1 0.1.1 '### Changed'
fails "the version must go above 0.1.0, to 0.2.0 or higher"

setup 0.1.1 0.1.1 '### Removed'
fails "the version must go above 0.1.0, to 0.2.0 or higher"

setup 0.2.0 0.2.0 '### Changed'
passes "a minor with Changed"

setup 0.2.0 0.2.0 '### Removed'
passes "a minor with Removed"

setup 1.0.0 1.0.0 '### Changed'
passes "a major with Changed"

tag 0.2.0
setup 0.2.1 0.2.0
passes "the patch after a second release"

setup 0.2.1 0.2.1 '### Changed'
fails "the version must go above 0.2.0, to 0.3.0 or higher"

tag 1.0.0
setup 1.1.0 1.1.0 '### Changed'
fails "the version must go above 1.0.0, to 2.0.0 or higher"

setup 2.0.0 2.0.0 '### Changed'
passes "a major from 1.0 with Changed"

setup 1.1.0 1.1.0 '### New'
passes "a minor with New"

setup 1.0.1 1.0.0
passes "the patch after 1.0.0"

setup 0.1.1 'Unreleased'
fails "must look like ## 0.3.1"

setup 0.1.1 0.1.1
printf '%s\n' 'version := "0.1.1"' > engines/rego/ergo.rego
if out=$(bash "$script" rego 2>&1); then
  echo "changelog-version.sh rego should fail without -dev, and passed" >&2
  exit 1
fi
case $out in
  *'version := "X.Y.Z-dev"'*) ;;
  *)
    echo "changelog-version.sh rego should say version := \"X.Y.Z-dev\", and said: $out" >&2
    exit 1
    ;;
esac

if out=$(bash "$script" other 2>&1); then
  echo "changelog-version.sh other should fail, and passed" >&2
  exit 1
fi
