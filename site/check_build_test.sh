#!/bin/sh
set -eu
check=$(cd "$(dirname "$0")" && pwd)/check_build.py
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

build() {
  rm -rf "$dir/public" "$dir/site"
  mkdir -p "$dir/public/js/tutorial" "$dir/site/prepared/data" "$dir/site/data"
  echo '{"source": "rego-v0.1.0", "rego": "0.1.0", "spec": "0.1", "ergo_spec": "v0.1"}' > "$dir/site/prepared/data/release.json"
  printf 'demo:\n  input: |-\n    {"a": 1}\n  policy: |-\n    subjects: {}\n' > "$dir/site/data/examples.yaml"
  echo 'const p={ergo_spec:"v0.1"};' > "$dir/public/js/tutorial/main.abc.js"
  printf '%s\n' '<pre class="code"><code>{<span class="k">"a"</span>: 1}</code></pre>' '<pre class="code"><code><span class="k">ergo_spec</span>: v0.1' 'subjects: {}</code></pre>' > "$dir/public/index.html"
  mkdir -p "$dir/site/layouts" "$dir/site/content" "$dir/site/assets/css" "$dir/public/tutorial" "$dir/public/css"
  echo '<div class="tut" data-wasm="{{ . }}" data-step></div>' > "$dir/site/layouts/tutorial.html"
  printf -- '---\ntitle: "Learn Ergo"\n---\n' > "$dir/site/content/tutorial.md"
  echo '.tut { } .tut__bar { }' > "$dir/site/assets/css/tutorial.css"
  echo '<title>Learn Ergo · Ergo</title><div class=tut data-wasm=/e.wasm data-step></div>' > "$dir/public/tutorial/index.html"
  echo '.tut{}.tut__bar{}' > "$dir/public/css/tutorial.123.css"
}

fits() {
  python3 "$check" "$dir/public" "$dir/site" > /dev/null || {
    echo "check_build.py should pass: $1" >&2
    exit 1
  }
}

fails() {
  if out=$(python3 "$check" "$dir/public" "$dir/site"); then
    echo "check_build.py should fail with \"$1\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$1"*) ;;
    *)
      echo "check_build.py should fail with \"$1\", and said: $out" >&2
      exit 1
      ;;
  esac
}

build
fits "the build shows what was prepared"

build
echo 'const p={ergo_spec:"v0.2-dev"};' > "$dir/public/js/tutorial/main.abc.js"
fails "the tutorial's policies say ergo_spec v0.2-dev, and the Ergo it runs reads v0.1"

build
rm "$dir/public/js/tutorial/main.abc.js"
fails "the build has no tutorial script"

build
printf 'demo:\n  input: |-\n    {"a": 2}\n  policy: |-\n    subjects: {}\n' > "$dir/site/prepared/data/examples.yaml"
fails "the home page doesn't show the input of demo from $dir/site/prepared/data/examples.yaml"

build
printf 'demo:\n  input: |-\n    {"a": 1}\n  policy: |-\n    subjects: []\n' > "$dir/site/data/examples.yaml"
fails "the home page doesn't show the policy of demo"

build
mkdir -p "$dir/site/prepared/layouts"
echo '<div class="tut" data-wasm="{{ . }}" data-step data-menu></div>' > "$dir/site/prepared/layouts/tutorial.html"
fails "the tutorial page has no data-menu, which $dir/site/prepared/layouts/tutorial.html writes"

build
mkdir -p "$dir/site/prepared/layouts"
echo '<div class="tut" data-wasm="{{ . }}"></div>' > "$dir/site/prepared/layouts/tutorial.html"
fails "the tutorial page has data-step, which only $dir/site/layouts/tutorial.html writes"

build
mkdir -p "$dir/site/prepared/content"
printf -- '---\ntitle: "Learn Ergo 0.1"\n---\n' > "$dir/site/prepared/content/tutorial.md"
fails "the tutorial page's title isn't \"Learn Ergo 0.1\""

build
mkdir -p "$dir/site/prepared/assets/css"
echo '.tut { } .tut__old { }' > "$dir/site/prepared/assets/css/tutorial.css"
fails "the built tutorial.css doesn't have the classes of $dir/site/prepared/assets/css/tutorial.css"

echo "check_build.py fails when the built site doesn't show what was prepared"
