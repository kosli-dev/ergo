#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
out=site/assets/playground
mkdir -p "$out/vendor"

mkdir "$dir/src"
cp ergo.rego "$dir/src/"
printf 'package playground\n\nimport data.ergo\n\nreport := ergo.report(input.input, input.policy, input.params)\n' > "$dir/src/playground.rego"
opa build -t wasm -e playground/report -o "$dir/bundle.tar.gz" "$dir/src"
tar -xzf "$dir/bundle.tar.gz" -C "$dir" /policy.wasm 2>/dev/null
mv "$dir/policy.wasm" "$out/ergo.wasm"
chmod 644 "$out/ergo.wasm"
git describe --always --dirty --abbrev=7 > "$out/commit.txt"

fetch() {
  curl -fsSL "$1" -o "$dir/pkg.tgz"
  actual="sha512-$(openssl dgst -sha512 -binary "$dir/pkg.tgz" | base64 | tr -d '\n')"
  if [ "$actual" != "$2" ]; then
    echo "$1 doesn't match its pinned hash" >&2
    exit 1
  fi
  tar -xzf "$dir/pkg.tgz" -C "$dir" "package/$3"
  mv "$dir/package/$3" "$out/vendor/$4"
  rm -rf "$dir/package" "$dir/pkg.tgz"
}

fetch https://registry.npmjs.org/@open-policy-agent/opa-wasm/-/opa-wasm-1.10.0.tgz \
  'sha512-ymR/nFS3nO9o24j9xowGGQaf+Gmb813QcxUpVZkfRlJkawKWqSIllnEH15agyWjijmOIyhA+OBErenx6N3jphw==' \
  dist/opa-wasm-browser.esm.js opa-wasm.mjs
fetch https://registry.npmjs.org/js-yaml/-/js-yaml-4.1.0.tgz \
  'sha512-wpxZs9NoxZaJESJGIZTyDEaYpl0FKSA+FB9aJiyemKhMwkxQg63h4T1KJgUGHpTqPDNRcmmYLugrRjJlBtWvRA==' \
  dist/js-yaml.mjs js-yaml.mjs
