#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/latest-release.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
git -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty --message test

check() {
  actual=$("$script" "$1")
  if [ "$actual" != "$2" ]; then
    echo "the latest $1 release should be \"$2\", and is \"$actual\"" >&2
    exit 1
  fi
}

check rego ""
check spec ""
for tag in rego-v0.10.0 rego-v0.9.0 rego-v0.2.0 rego-v1.0.0-rc1 rego-v2 rego-vlatest spec-v0.10 spec-v0.9 spec-v1.0.0 spec-v2 spec-v1.0-dev; do
  git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag "$tag"
done
check rego rego-v0.10.0
check spec spec-v0.10
echo "latest-release.sh picks the highest version and ignores other tags"
