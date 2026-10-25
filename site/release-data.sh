#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"

rego=$(git tag --list 'rego-v*' | grep -E '^rego-v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^rego-v//' | sort -V | tail -n 1 || true)
spec=$(git tag --list 'spec-v*' | grep -E '^spec-v[0-9]+\.[0-9]+$' | sed 's/^spec-v//' | sort -V | tail -n 1 || true)

mkdir -p site/data
json=
[ -z "$rego" ] || json="\"rego\": \"$rego\""
[ -z "$spec" ] || json="${json:+$json, }\"spec\": \"$spec\""
printf '{%s}\n' "$json" > site/data/release.json
