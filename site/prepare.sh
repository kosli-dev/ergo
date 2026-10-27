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
  where="$repo has no published spec-vX.Y release"
else
  specs=$(git tag --list 'spec-v*')
  where="There's no spec-vX.Y tag here. Fetch the tags with: git fetch --tags"
fi
spec_tag=$(printf '%s\n' "$specs" | site/latest-release.sh spec)
[ -n "$spec_tag" ] || fail "$where"
spec_tags=$(printf '%s\n' "$specs" | grep -E '^spec-v[0-9]+\.[0-9]+$')
for spec in $spec_tags; do
  has_tag "$spec"
done

rm -rf "$prepared"
mkdir -p "$prepared/data"

if [ "$mode" = release ]; then
  tag=$(printf '%s\n' "$releases" | site/latest-release.sh rego)
  [ -n "$tag" ] || fail "$repo has no published rego-vX.Y.Z release"
  version=${tag#rego-v}
  has_tag "$tag"

  gh release download "$tag" --repo "$repo" --pattern ergo.rego --dir "$dir/asset"
  rego=$dir/asset/ergo.rego
  grep -qxF "version := \"$version\"" "$rego" || fail "The ergo.rego of release $tag should say version := \"$version\""

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
  cp "$dir/tag/site/assets/css/ergo.css" "$prepared/reference/"
  cp "$dir/tag/site/layouts/tutorial.html" "$prepared/layouts/"
  cp "$dir/tag/site/content/tutorial.md" "$prepared/content/"
  if [ -f "$dir/tag/site/data/examples.yaml" ]; then
    cp "$dir/tag/site/data/examples.yaml" "$prepared/data/"
  fi
  cp "$rego" "$prepared/ergo.rego.txt"
  for file in README.md REFERENCE.md; do
    VERSION=$version perl -pe 's/(?<![\w.])\Q$ENV{VERSION}\E-dev(?![\w-])/$ENV{VERSION}/g' "$dir/tag/$file" > "$dir/tag/$file.tmp"
    mv "$dir/tag/$file.tmp" "$dir/tag/$file"
  done
  docs=$dir/tag
  source=$tag
else
  rego=ergo.rego
  version=
  docs=.
  source="working tree"
fi

mkdir -p "$prepared/repo"
cp "$docs/README.md" "$docs/REFERENCE.md" "$prepared/repo/"
(cd "$docs" && find examples -type f) > "$dir/examples.txt"
while IFS= read -r file; do
  mkdir -p "$prepared/$(dirname "$file")"
  cp "$docs/$file" "$prepared/$file.txt"
done < "$dir/examples.txt"

ergo_spec=$(sed -n 's/^_spec := "\(v[0-9][0-9]*\.[0-9][0-9]*\(-dev\)\{0,1\}\)"$/\1/p' "$rego")
[ -n "$ergo_spec" ] || fail "$rego should say _spec := \"vX.Y\" or _spec := \"vX.Y-dev\""
case $ergo_spec in
  *-dev) ;;
  *)
    printf '%s\n' $spec_tags | grep -qxF "spec-$ergo_spec" || fail "The ergo.rego of $source reads spec $ergo_spec, and spec-$ergo_spec isn't published, so the site would link to schemas it doesn't have"
    ;;
esac
printf '{"source": "%s", "rego": "%s", "spec": "%s", "ergo_spec": "%s"}\n' "$source" "$version" "${spec_tag#spec-v}" "$ergo_spec" > "$prepared/data/release.json"

out=site/assets/tutorial
rm -rf "$out"
mkdir -p "$out/vendor" "$dir/src"
cp "$rego" "$dir/src/ergo.rego"
printf 'package tutorial\n\nimport data.ergo\n\nreport := ergo.report(input.input, input.policy, {})\n' > "$dir/src/tutorial.rego"
opa build -t wasm -e tutorial/report -o "$dir/bundle.tar.gz" "$dir/src"
tar -xzf "$dir/bundle.tar.gz" -C "$dir" /policy.wasm 2> /dev/null
mv "$dir/policy.wasm" "$out/ergo.wasm"
chmod 644 "$out/ergo.wasm"

curl -fsSL --retry 3 https://registry.npmjs.org/@open-policy-agent/opa-wasm/-/opa-wasm-1.10.0.tgz -o "$dir/pkg.tgz"
digest=$(openssl dgst -sha512 -binary "$dir/pkg.tgz" | base64)
if [ "sha512-$(printf '%s' "$digest" | tr -d '\n')" != 'sha512-ymR/nFS3nO9o24j9xowGGQaf+Gmb813QcxUpVZkfRlJkawKWqSIllnEH15agyWjijmOIyhA+OBErenx6N3jphw==' ]; then
  fail "opa-wasm doesn't match its pinned hash"
fi
tar -xzf "$dir/pkg.tgz" -C "$dir" package/dist/opa-wasm-browser.esm.js
mv "$dir/package/dist/opa-wasm-browser.esm.js" "$out/vendor/opa-wasm.mjs"

site/spec-schemas.sh $spec_tags
printf '%s\n' "$source" > "$prepared/source"
echo "The site is built from: $source. Check it with: site/check.sh"
