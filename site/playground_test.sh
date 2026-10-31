#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/playground.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

echo '<!doctype html><html><head><title>Playground</title></head><body>hi</body></html>' > "$dir/playground.html"
mkdir "$dir/public"
"$script" "$dir/playground.html" "$dir/public"
grep -q '<head><meta name="robots" content="noindex"><title>Playground</title>' "$dir/public/playground/index.html" || {
  echo "playground.sh should put the noindex meta inside <head>" >&2
  exit 1
}
grep -q '<body>hi</body>' "$dir/public/playground/index.html" || {
  echo "playground.sh should keep the rest of the page" >&2
  exit 1
}

old="$dir/public/editor/index.html"
[ -f "$old" ] || {
  echo "playground.sh should write the page at /editor/ that sends visitors on" >&2
  exit 1
}
for want in '<!doctype html>' '<meta charset="utf-8">' '<meta name="robots" content="noindex">' '<meta http-equiv="refresh" content="0; url=../playground/">' '<link rel="canonical" href="../playground/">' '<a href="../playground/">The playground has moved to /playground/</a>'; do
  grep -qF "$want" "$old" || {
    echo "the /editor/ page should contain $want" >&2
    exit 1
  }
done
if grep -q '<body>hi</body>' "$old"; then
  echo "the /editor/ page should be a small page of its own, not the playground" >&2
  exit 1
fi

echo '<html lang="en"><HEAD data-x="1"><title>Playground</title></HEAD></html>' > "$dir/attrs.html"
"$script" "$dir/attrs.html" "$dir/public"
grep -q 'data-x="1"><meta name="robots" content="noindex">' "$dir/public/playground/index.html" || {
  echo "playground.sh should find <head> with attributes, in any case" >&2
  exit 1
}

echo '<html><body>no head</body></html>' > "$dir/nohead.html"
if "$script" "$dir/nohead.html" "$dir/public2" 2> "$dir/err"; then
  echo "playground.sh should fail when the page has no <head>" >&2
  exit 1
fi
grep -q 'has no <head>' "$dir/err" || {
  echo "playground.sh should say the page has no <head>" >&2
  exit 1
}

if "$script" "$dir/missing.html" "$dir/public" 2> /dev/null; then
  echo "playground.sh should fail when the page doesn't exist" >&2
  exit 1
fi

echo "playground.sh adds noindex to the playground page, writes the /editor/ redirect and fails without a <head>"
