#!/bin/sh
set -eu
[ $# -eq 1 ] || { echo "usage: site/prepare-playground.sh <empty folder>" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"
out=$1
repo=kosli-dev/ergo
releases=$(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases --limit 1000 --json tagName --jq '.[].tagName')
rego=$(printf '%s\n' "$releases" | site/latest-release.sh rego)
rust=$(printf '%s\n' "$releases" | site/latest-release.sh rust)
[ -n "$rego" ] && [ -n "$rust" ] || { echo "The playground needs published Rego and Rust releases" >&2; exit 1; }
mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || { echo "$out must be empty" >&2; exit 1; }
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
git archive --output "$dir/ui.tar" HEAD packages README.md
tar -xf "$dir/ui.tar" -C "$out"
/bin/rm -rf "$out/packages/markdown/cases"
git archive --output "$dir/rego.tar" "$rego" packages/markdown/cases
tar -xf "$dir/rego.tar" -C "$out"
git show "$rego:packages/playground/build.mjs" > "$out/packages/playground/released-build.mjs"
git archive --output "$dir/rust.tar" "$rust" engines/rust spec/sentences-corpus.json
tar -xf "$dir/rust.tar" -C "$out"
gh release download "$rego" --repo "$repo" --pattern ergo.rego --dir "$dir/asset"
grep -qxF "version := \"${rego#rego-v}\"" "$dir/asset/ergo.rego" || { echo "The ergo.rego asset doesn't match $rego" >&2; exit 1; }
mkdir -p "$out/dist"
/bin/cp -f "$dir/asset/ergo.rego" "$out/dist/ergo.rego"
printf '%s\n' "The playground uses $rego and $rust"
