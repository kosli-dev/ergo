#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/editor.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

echo '<!doctype html><html><head><title>Editor</title></head><body>hi</body></html>' > "$dir/editor.html"
mkdir "$dir/public"
"$script" "$dir/editor.html" "$dir/public"
grep -q '<head><meta name="robots" content="noindex"><title>Editor</title>' "$dir/public/editor/index.html" || {
  echo "editor.sh should put the noindex meta inside <head>" >&2
  exit 1
}
grep -q '<body>hi</body>' "$dir/public/editor/index.html" || {
  echo "editor.sh should keep the rest of the page" >&2
  exit 1
}

echo '<html lang="en"><HEAD data-x="1"><title>Editor</title></HEAD></html>' > "$dir/attrs.html"
"$script" "$dir/attrs.html" "$dir/public"
grep -q 'data-x="1"><meta name="robots" content="noindex">' "$dir/public/editor/index.html" || {
  echo "editor.sh should find <head> with attributes, in any case" >&2
  exit 1
}

echo '<html><body>no head</body></html>' > "$dir/nohead.html"
if "$script" "$dir/nohead.html" "$dir/public2" 2> "$dir/err"; then
  echo "editor.sh should fail when the page has no <head>" >&2
  exit 1
fi
grep -q 'has no <head>' "$dir/err" || {
  echo "editor.sh should say the page has no <head>" >&2
  exit 1
}

if "$script" "$dir/missing.html" "$dir/public" 2> /dev/null; then
  echo "editor.sh should fail when the page doesn't exist" >&2
  exit 1
fi

echo "editor.sh adds noindex to the editor page and fails without a <head>"
