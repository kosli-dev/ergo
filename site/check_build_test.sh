#!/bin/sh
set -eu
check=$(cd "$(dirname "$0")" && pwd)/check_build.py
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

build() {
  rm -rf "$dir/public" "$dir/site"
  mkdir -p "$dir/public/js/tutorial" "$dir/site/prepared/data" "$dir/site/data"
  echo '{"source": "rego-v0.1.0", "rego": "0.1.0", "rust": "0.1.0", "spec": "0.1", "ergo_spec": "v0.1"}' > "$dir/site/prepared/data/release.json"
  printf 'demo:\n  input: |-\n    {"a": 1}\n  policy: |-\n    subjects: {}\n' > "$dir/site/data/examples.yaml"
  mkdir -p "$dir/site/assets/js/tutorial"
  echo 'export const step = { title: "Name the check", spec: "v0.1" };' > "$dir/site/assets/js/tutorial/lib.mjs"
  echo 'import { step } from "./lib.mjs";' > "$dir/site/assets/js/tutorial/main.mjs"
  echo 'const p={ergo_spec:"v0.1"},s={title:"Name the check",spec:"v0.1"};' > "$dir/public/js/tutorial/main.abc.js"
  printf '%s\n' '<pre class="code"><code>{<span class="k">"a"</span>: 1}</code></pre>' '<pre class="code"><code><span class="k">ergo_spec</span>: v0.1' 'subjects: {}</code></pre>' > "$dir/public/index.html"
  echo '<a href="/playground/">Playground</a>' >> "$dir/public/index.html"
  mkdir -p "$dir/site/layouts" "$dir/site/content" "$dir/site/assets/css" "$dir/public/tutorial" "$dir/public/css"
  echo '<div class="tut" data-wasm="{{ . }}" data-step></div>' > "$dir/site/layouts/tutorial.html"
  printf -- '---\ntitle: "Learn Ergo"\n---\n' > "$dir/site/content/tutorial.md"
  echo '.tut { color: #FFF; padding: 0.5rem 0; } .tut__bar { }' > "$dir/site/assets/css/tutorial.css"
  echo '<title>Learn Ergo · Ergo</title><div class=tut data-wasm=/e.wasm data-step></div>' > "$dir/public/tutorial/index.html"
  echo '.tut{color:#fff;padding:.5rem 0}.tut__bar{}' > "$dir/public/css/tutorial.123.css"
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
echo 'const p={ergo_spec:"v0.2-dev"},s={title:"Name the check",spec:"v0.1"};' > "$dir/public/js/tutorial/main.abc.js"
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
echo '.tut { color: #FFF; padding: 0.5rem 0; } .tut__old { }' > "$dir/site/prepared/assets/css/tutorial.css"
fails "the built tutorial.css doesn't have the classes, properties, colours and lengths of $dir/site/prepared/assets/css/tutorial.css"

build
mkdir -p "$dir/site/prepared/assets/css"
echo '.tut { color: #EEE; padding: 0.5rem 0; } .tut__bar { }' > "$dir/site/prepared/assets/css/tutorial.css"
fails "the built tutorial.css doesn't have the classes, properties, colours and lengths of $dir/site/prepared/assets/css/tutorial.css"

build
mkdir -p "$dir/site/prepared/assets/js/tutorial"
echo 'export const step = { title: "Name your check", spec: "v0.1" };' > "$dir/site/prepared/assets/js/tutorial/lib.mjs"
cp "$dir/site/assets/js/tutorial/main.mjs" "$dir/site/prepared/assets/js/tutorial/"
fails "the tutorial script doesn't have \"Name your check\", from $dir/site/prepared/assets/js/tutorial"

build
mkdir -p "$dir/site/prepared/assets/js/tutorial"
echo 'export const step = { title: "Name your check", spec: "v0.1" };' > "$dir/site/prepared/assets/js/tutorial/lib.mjs"
cp "$dir/site/assets/js/tutorial/main.mjs" "$dir/site/prepared/assets/js/tutorial/"
echo 'const p={ergo_spec:"v0.1"},s={title:"Name your check",t:"Name the check",spec:"v0.1"};' > "$dir/public/js/tutorial/main.abc.js"
fails "the tutorial script has \"Name the check\", which only $dir/site/assets/js/tutorial has"

build
mkdir -p "$dir/site/prepared/content"
printf -- '---\ntitle: ""\n---\n' > "$dir/site/prepared/content/tutorial.md"
fails "the tutorial page's title isn't \"\""

build
mkdir -p "$dir/public/playground"
echo '<html><head><meta name="robots" content="noindex"></head><body><a href="/">Home</a></body></html>' > "$dir/public/playground/index.html"
echo '<a href="/docs/">Docs</a>' > "$dir/public/docs.html"
fits "the playground page is there with noindex and the home page links to it"

build
mkdir -p "$dir/public/playground"
echo '<html><head></head></html>' > "$dir/public/playground/index.html"
fails "the playground page has no noindex meta"

build
sed -i.bak 's|<a href="/playground/">Playground</a>||' "$dir/public/index.html"
rm "$dir/public/index.html.bak"
fails "the home page doesn't link to the playground"

build
sed -i.bak 's|<a href="/playground/">Playground</a>|<a href="/playgroundial/">Playground</a>|' "$dir/public/index.html"
rm "$dir/public/index.html.bak"
fails "the home page doesn't link to the playground"

build
sed -i.bak 's|<a href="/playground/">Playground</a>|<a href=/playground/>Playground</a>|' "$dir/public/index.html"
rm "$dir/public/index.html.bak"
fits "a minified link to the playground without quotes"

build
sed -i.bak 's|href="/playground/"|href="/ergo/playground"|' "$dir/public/index.html"
rm "$dir/public/index.html.bak"
fits "a link to the playground under a base path"

build
echo '<urlset><url><loc>https://ergo.kosli.com/</loc></url><url><loc>https://ergo.kosli.com/playground/</loc></url></urlset>' > "$dir/public/sitemap.xml"
fails "sitemap.xml lists the playground"

build
echo '<urlset><url><loc>https://ergo.kosli.com/</loc></url><url><loc>https://ergo.kosli.com/editor/</loc></url></urlset>' > "$dir/public/sitemap.xml"
fails "sitemap.xml lists the old editor page"

build
mkdir -p "$dir/public/editor"
echo '<html><head></head></html>' > "$dir/public/editor/index.html"
fails "the old editor page has no noindex meta"

build
mkdir -p "$dir/public/docs"
echo '<a href="/docs/">Docs</a>' > "$dir/public/docs/index.html"
fits "the playground page is missing"

echo "check_build.py fails when the built site doesn't show what was prepared"
