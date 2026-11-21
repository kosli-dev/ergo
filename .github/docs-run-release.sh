#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
gh=${DOCS_RUN_GH:-gh}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

tag=$("$gh" release list --repo kosli-dev/ergo --limit 100 --json tagName --jq '[.[].tagName | select(startswith("rego-v"))][0] // empty')
if [ -z "$tag" ]; then
  echo "docs-run-release.sh: no rego-v release found" >&2
  exit 1
fi
mkdir "$dir/release"
"$gh" release download "$tag" --repo kosli-dev/ergo --pattern ergo.rego --dir "$dir/release"
if [ ! -s "$dir/release/ergo.rego" ]; then
  echo "docs-run-release.sh: $tag has no ergo.rego" >&2
  exit 1
fi
echo "docs-run-release.sh: checking against ergo.rego from $tag"
DOCS_RUN_RELEASE_ERGO_REGO="$dir/release/ergo.rego" DOCS_RUN_REQUIRE_RELEASE=1 "$here/.github/docs-run.sh" "$@"
