#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
out=site/assets/tutorial
mkdir -p "$out/vendor"

mkdir "$dir/src"
cp ergo.rego "$dir/src/"
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
