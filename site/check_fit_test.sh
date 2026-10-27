#!/bin/sh
set -eu
check=$(cd "$(dirname "$0")" && pwd)/check_fit.py
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

site() {
  rm -rf "$dir/site"
  mkdir -p "$dir/site/assets/css" "$dir/site/layouts/_partials" "$dir/site/assets/vendor" "$dir/site/prepared/reference" "$dir/site/prepared/layouts" "$dir/site/prepared/assets/css" "$dir/site/prepared/assets/js/tutorial"
  echo ':root { --paper: #fff; } .lockup { }' > "$dir/site/assets/css/ergo.css"
  cp "$dir/site/assets/css/ergo.css" "$dir/site/prepared/reference/ergo.css"
  echo '<svg></svg>' > "$dir/site/layouts/_partials/wordmark.html"
  echo 'export default {};' > "$dir/site/assets/vendor/opa.mjs"
  echo '.tut { color: var(--paper); width: var(--cols); }' > "$dir/site/prepared/assets/css/tutorial.css"
  printf '%s\n' '<a class="lockup tut tut__hook">{{ partial "wordmark.html" . }}</a>' '{{ resources.Get "tutorial/ergo.wasm" }}{{ resources.Get "css/ergo.css" }}' > "$dir/site/prepared/layouts/tutorial.html"
  echo 'import opa from "../../vendor/opa.mjs";' > "$dir/site/prepared/assets/js/tutorial/main.mjs"
}

fits() {
  python3 "$check" "$dir/site" > /dev/null || {
    echo "check_fit.py should pass: $1" >&2
    exit 1
  }
}

fails() {
  if out=$(python3 "$check" "$dir/site"); then
    echo "check_fit.py should fail with \"$1\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$1"*) ;;
    *)
      echo "check_fit.py should fail with \"$1\", and said: $out" >&2
      exit 1
      ;;
  esac
}

site
fits "the released tutorial needs nothing main lacks"

site
echo ':root { } .lockup { }' > "$dir/site/assets/css/ergo.css"
fails "the released tutorial uses the CSS variable --paper from css/ergo.css, which no longer defines it"

site
echo ':root { --paper: #fff; }' > "$dir/site/assets/css/ergo.css"
fails "the released tutorial layout uses the class lockup from css/ergo.css, which no longer styles it"

site
rm "$dir/site/layouts/_partials/wordmark.html"
fails "the released tutorial layout uses the partial wordmark.html, which layouts/_partials doesn't have"

site
rm "$dir/site/assets/vendor/opa.mjs"
fails "the released main.mjs imports ../../vendor/opa.mjs, which doesn't exist"

echo "check_fit.py fails when main's site no longer has what the released tutorial uses"
