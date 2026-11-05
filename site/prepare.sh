#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"

fail() {
  echo "$1" >&2
  exit 1
}

case ${1:-} in
  "") mode=release ;;
  --working-tree) mode=working-tree ;;
  *)
    echo "usage: site/prepare.sh [--working-tree]" >&2
    exit 2
    ;;
esac

repo=kosli-dev/ergo
prepared=site/prepared
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

has_tag() {
  git rev-parse --quiet --verify "refs/tags/$1" > /dev/null || fail "There's no $1 tag here. Fetch the tags with: git fetch --tags"
}

if [ "$mode" = release ]; then
  if ! releases=$(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases --limit 1000 --json tagName --jq '.[].tagName'); then
    fail "Listing Ergo's releases needs the GitHub CLI, logged in. To build from this working tree instead, run: site/prepare.sh --working-tree"
  fi
  specs=$releases
  rusts=$releases
  where="$repo has no published spec-vX.Y release"
else
  specs=$(git tag --list 'spec-v*')
  rusts=$(git tag --list 'rust-v*')
  where="There's no spec-vX.Y tag here. Fetch the tags with: git fetch --tags"
fi
spec_tag=$(printf '%s\n' "$specs" | site/latest-release.sh spec)
[ -n "$spec_tag" ] || fail "$where"
rust_tag=$(printf '%s\n' "$rusts" | site/latest-release.sh rust)
[ -z "$rust_tag" ] || has_tag "$rust_tag"
spec_tags=$(printf '%s\n' "$specs" | grep -E '^spec-v[0-9]+\.[0-9]+$')
for spec in $spec_tags; do
  has_tag "$spec"
done

rm -rf "$prepared"
mkdir -p "$prepared/data"

if [ "$mode" = release ]; then
  rego_tag=$(printf '%s\n' "$releases" | site/latest-release.sh rego)
  [ -n "$rego_tag" ] || fail "$repo has no published rego-vX.Y.Z release"
  has_tag "$rego_tag"

  in_tag() {
    git cat-file -e "$1:$2" 2> /dev/null
  }
  rego_version_of() {
    git show "$1:engines/rego/ergo.rego" 2> /dev/null | sed -n 's/^version := "\(.*\)"$/\1/p'
  }
  spec_of() {
    { git show "$1:engines/rego/ergo.rego" 2> /dev/null || git show "$1:ergo.rego" 2> /dev/null; } | sed -n 's/^_spec := "\(v[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p'
  }

  found_spec=
  found_ergo=
  for candidate_spec in $(printf '%s\n' $spec_tags | sort -V -r); do
    for candidate in $(printf '%s\n' "$releases" | grep -E '^rego-v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V -r); do
      has_tag "$candidate"
      if [ "$(spec_of "$candidate")" = "v${candidate_spec#spec-v}" ]; then
        found_spec=$candidate_spec
        found_ergo=$candidate
        break 2
      fi
    done
  done
  docs_tag=$rego_tag
  ergo_tag=$rego_tag
  opa_source=
  cli_source=
  if [ -n "$found_spec" ] && in_tag "$found_spec" OPA.md && in_tag "$rego_tag" OPA.md; then
    docs_tag=$found_spec
    ergo_tag=$found_ergo
    opa_source=$rego_tag
    [ "$found_spec" = "$spec_tag" ] || echo "No published rego release reads $spec_tag yet, so the docs and the tutorial come from $found_spec, which $found_ergo reads"
  elif in_tag "$rego_tag" OPA.md; then
    opa_source=$rego_tag
    echo "No published spec release has OPA.md yet, so the docs come from $rego_tag, which has it"
  else
    echo "The latest releases don't have OPA.md yet, so the site keeps the old layout, from $rego_tag, with no OPA or CLI page"
  fi
  if [ -n "$opa_source" ]; then
    if [ -n "$rust_tag" ] && in_tag "$rust_tag" CLI.md; then
      cli_source=$rust_tag
    else
      echo "The latest Rust release has no CLI.md yet, so the site has no CLI page"
    fi
  fi
  if in_tag "$docs_tag" OPA.md; then
    [ -n "$opa_source" ] || fail "The docs come from $docs_tag, which has the short README, and there is no OPA page for it to link to"
  else
    [ -z "$opa_source" ] || fail "The docs come from $docs_tag, which has the long README, and an OPA page would repeat it"
  fi
  tag=$docs_tag
  version=${ergo_tag#rego-v}

  gh release download "$ergo_tag" --repo "$repo" --pattern ergo.rego --dir "$dir/asset"
  rego=$dir/asset/ergo.rego
  grep -qxF "version := \"$version\"" "$rego" || fail "The ergo.rego of release $ergo_tag should say version := \"$version\""

  paths="README.md REFERENCE.md examples site/assets/js/tutorial site/assets/css/tutorial.css site/assets/css/ergo.css site/layouts/tutorial.html site/content/tutorial.md"
  if git cat-file -e "$tag:site/data/examples.yaml" 2> /dev/null; then
    paths="$paths site/data/examples.yaml"
  else
    echo "$tag has no site/data/examples.yaml, so the home page's examples come from this working tree"
  fi
  mkdir "$dir/tag"
  git archive --output "$dir/tag.tar" "$tag" $paths
  tar -x -f "$dir/tag.tar" -C "$dir/tag"

  mkdir -p "$prepared/assets/js" "$prepared/assets/css" "$prepared/layouts" "$prepared/content"
  cp -R "$dir/tag/site/assets/js/tutorial" "$prepared/assets/js/"
  rm -f "$prepared"/assets/js/tutorial/*.test.mjs
  cp "$dir/tag/site/assets/css/tutorial.css" "$prepared/assets/css/"
  mkdir -p "$prepared/reference"
  cp "$dir/tag/site/assets/css/ergo
