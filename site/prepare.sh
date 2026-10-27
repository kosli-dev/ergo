#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"
tag=$(site/latest-release.sh rego)
if [ -z "$tag" ]; then
  echo "The site shows the latest release of ergo.rego, and there's no rego-vX.Y.Z tag here. Fetch the tags with: git fetch --tags" >&2
  exit 1
fi
version=${tag#rego-v}
spec_tag=$(site/latest-release.sh spec)

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
git archive "$tag" ergo.rego README.md REFERENCE.md examples | tar -x -C "$dir"
dev=$(printf '%s' "$version-dev" | sed 's/\./\\./g')
for file in ergo.rego README.md REFERENCE.md; do
  sed "s/$dev/$version/g" "$dir/$file" > "$dir/$file.tmp"
  mv "$dir/$file.tmp" "$dir/$file"
done
if ! grep -qxF "version := \"$version\"" "$dir/ergo.rego"; then
  echo "$tag: ergo.rego should say version := \"$version-dev\"" >&2
  exit 1
fi
ergo_spec=$(sed -n 's/^_spec := "\(v[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$dir/ergo.rego")
if [ -z "$ergo_spec" ]; then
  echo "$tag: ergo.rego should say _spec := \"vX.Y\"" >&2
  exit 1
fi

release=site/release
rm -rf "$release"
mkdir -p "$release"
cp "$dir/README.md" "$dir/REFERENCE.md" "$release/"
(cd "$dir" && find examples -type f) | while read -r file; do
  mkdir -p "$release/$(dirname "$file")"
  cp "$dir/$file" "$release/$file.txt"
done

mkdir -p site/data
printf '{"rego": "%s", "spec": "%s", "ergo_spec": "%s"}\n' "$version" "${spec_tag#spec-v}" "$ergo_spec" > site/data/release.json

out=site/assets/tutorial
rm -rf "$out"
mkdir -p "$out/vendor"
printf 'export const ergoSpec = "%s";\n' "$ergo_spec" > "$out/release.mjs"

mkdir "$dir/src"
cp "$dir/ergo.rego" "$dir/src/"
printf 'package tutorial\n\nimport data.ergo\n\nreport := ergo.report(input.input, input.policy, {})\n' > "$dir/src/tutorial.rego"
opa build -t wasm -e tutorial/report -o "$dir/bundle.tar.gz" "$dir/src"
tar -xzf "$dir/bundle.tar.gz" -C "$dir" /policy.wasm 2>/dev/null
mv "$dir/policy.wasm" "$out/ergo.wasm"
chmod 644 "$out/ergo.wasm"

curl -fsSL https://registry.npmjs.org/@open-policy-agent/opa-wasm/-/opa-wasm-1.10.0.tgz -o "$dir/pkg.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$dir/pkg.tgz" | base64 | tr -d '\n')"
if [ "$actual" != 'sha512-ymR/nFS3nO9o24j9xowGGQaf+Gmb813QcxUpVZkfRlJkawKWqSIllnEH15agyWjijmOIyhA+OBErenx6N3jphw==' ]; then
  echo "opa-wasm doesn't match its pinned hash" >&2
  exit 1
fi
tar -xzf "$dir/pkg.tgz" -C "$dir" package/dist/opa-wasm-browser.esm.js
mv "$dir/package/dist/opa-wasm-browser.esm.js" "$out/vendor/opa-wasm.mjs"

site/spec-schemas.sh
echo "The site now shows $tag"
