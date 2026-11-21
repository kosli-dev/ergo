#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
gh=${DOCS_RUN_GH:-gh}
pause=${DOCS_RUN_RETRY_SLEEP:-5}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

gh_retry() {
  if "$gh" "$@" 2> "$dir/gh-error"; then
    return 0
  fi
  echo "docs-run-release.sh: could not get the latest release: re-run the job if GitHub had an error" >&2
  cat "$dir/gh-error" >&2
  sleep "$pause"
  if "$gh" "$@"; then
    return 0
  fi
  echo "docs-run-release.sh: could not get the latest release: re-run the job if GitHub had an error" >&2
  return 1
}

basics=$here/engines/rego/src/shared/basics.rego
if grep -q '^_spec := ".*-dev"' "$basics" && grep -q '^version := ".*-dev"' "$basics"; then
  preparing=
else
  preparing=1
fi

if [ -n "$preparing" ]; then
  if [ ! -s "$here/dist/ergo.rego" ]; then
    echo "docs-run-release.sh: a release is being prepared, so it needs dist/ergo.rego, and there is none: run .github/build-ergo.sh first" >&2
    exit 1
  fi
  ergo=$here/dist/ergo.rego
  echo "docs-run-release.sh: checking against dist/ergo.rego, because _spec or version in basics.rego has no -dev, so a release is being prepared and it is what the tag will contain"
  note="this compares README with dist/ergo.rego, because _spec or version in basics.rego has no -dev (a release is being prepared)"
else
  tag=$(gh_retry release list --repo kosli-dev/ergo --limit 100 --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName')
  case $tag in
    "")
      echo "docs-run-release.sh: GitHub marks no release as Latest" >&2
      exit 1
      ;;
    rego-v*) ;;
    *)
      echo "docs-run-release.sh: the Latest release is $tag, not a rego-v release" >&2
      exit 1
      ;;
  esac
  mkdir "$dir/release"
  gh_retry release download "$tag" --repo kosli-dev/ergo --pattern ergo.rego --dir "$dir/release"
  if [ ! -s "$dir/release/ergo.rego" ]; then
    echo "docs-run-release.sh: $tag has no ergo.rego" >&2
    exit 1
  fi
  ergo=$dir/release/ergo.rego
  echo "docs-run-release.sh: checking against ergo.rego from $tag"
  note="this compares README with ergo.rego from $tag (the latest release); when preparing a release, _spec and version in basics.rego have no -dev and it compares with dist/ergo.rego"
fi
DOCS_RUN_RELEASE_ERGO_REGO=$ergo DOCS_RUN_REQUIRE_RELEASE=1 DOCS_RUN_RELEASE_NOTE=$note "$here/.github/docs-run.sh" "$@"
