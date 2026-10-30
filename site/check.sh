#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"

[ -f site/prepared/source ] || {
  echo "Run site/prepare.sh first" >&2
  exit 1
}
source=$(cat site/prepared/source)

if [ "$source" = "working tree" ]; then
  node --test site/assets/js/tutorial/lib.test.mjs
  python3 site/check_examples.py site/data/examples.yaml engines/rego/ergo.rego
  exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
git archive --output "$dir/tag.tar" "$source" site/assets/js/tutorial examples
tar -x -f "$dir/tag.tar" -C "$dir"
mkdir -p "$dir/site/assets/tutorial"
cp -R site/assets/tutorial/. "$dir/site/assets/tutorial/"
node --test "$dir/site/assets/js/tutorial/lib.test.mjs"

examples=site/prepared/data/examples.yaml
[ -f "$examples" ] || examples=site/data/examples.yaml
python3 site/check_examples.py "$examples" site/prepared/ergo.rego.txt
python3 site/check_fit.py
