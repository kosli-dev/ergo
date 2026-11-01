#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

mkdir "$dir/bin"
cat > "$dir/bin/gh" <<'GH'
#!/bin/sh
[ -z "${FAKE_GH_FAILS:-}" ] || exit 1
case "$1 $2" in
  "release list")
    case " $* " in *" --exclude-pre-releases "*) ;; *) printf '%s\n' ${FAKE_PRE_RELEASES:-} ;; esac
    case " $* " in *" --exclude-drafts "*) ;; *) printf '%s\n' ${FAKE_DRAFTS:-} ;; esac
    printf '%s\n' $FAKE_RELEASES
    ;;
  "release download")
    while [ $# -gt 0 ]; do
      [ "$1" = --dir ] && out=$2
      shift
    done
    mkdir -p "$out"
    printf 'package ergo\n\nversion := "%s"\n\n_spec := "%s"\n' "$FAKE_ASSET_VERSION" "${FAKE_ASSET_SPEC:-v0.1}" > "$out/ergo.rego"
    ;;
  *) exit 1 ;;
esac
GH
cat > "$dir/bin/opa" <<'OPA'
#!/bin/sh
while [ $# -gt 0 ]; do
  [ "$1" = -o ] && out=$2
  shift
done
python3 -c 'import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as t:
    info = tarfile.TarInfo("/policy.wasm")
    info.size = 4
    t.addfile(info, io.BytesIO(b"wasm"))' "$out"
OPA
cat > "$dir/bin/curl" <<'CURL'
#!/bin/sh
while [ $# -gt 0 ]; do
  [ "$1" = -o ] && out=$2
  shift
done
python3 -c 'import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as t:
    info = tarfile.TarInfo("package/dist/opa-wasm-browser.esm.js")
    info.size = 2
    t.addfile(info, io.BytesIO(b"js"))' "$out"
CURL
cat > "$dir/bin/openssl" <<'SSL'
#!/bin/sh
python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode("ymR/nFS3nO9o24j9xowGGQaf+Gmb813QcxUpVZkfRlJkawKWqSIllnEH15agyWjijmOIyhA+OBErenx6N3jphw=="))'
SSL
chmod +x "$dir/bin/"*
PATH=$dir/bin:$PATH
export PATH

repo=$dir/repo
mkdir -p "$repo/site/assets/js/tutorial" "$repo/site/assets/css" "$repo/site/layouts" "$repo/site/content" "$repo/examples/demo" "$repo/engines/rego" "$repo/spec/policy" "$repo/spec/report"
cd "$repo"
git init --quiet
cp "$root/site/prepare.sh" "$root/site/latest-release.sh" "$root/site/spec-schemas.sh" site/
printf '%s\n' '# Readme' '"version": "0.1.0-dev"' '10.1.0-dev' '0.1.0-devX' '0.1.0-dev-rc' 'v0.1.0-dev' '0.1.0-dev 0.1.0-dev' 'Ergo is at 0.1.0-dev.' 'x.0.1.0-dev' > README.md
echo 'expected ergo.rego 0.1.0-dev' > REFERENCE.md
echo "package demo" > examples/demo/demo.rego
echo "{}" > examples/demo/input.json
for file in lib.mjs main.mjs lib.test.mjs; do echo "export {};" > "site/assets/js/tutorial/$file"; done
echo ".tut {}" > site/assets/css/tutorial.css
echo ":root {}" > site/assets/css/ergo.css
echo "<div></div>" > site/layouts/tutorial.html
echo "---" > site/content/tutorial.md
printf 'package ergo\n\nversion := "0.1.0-dev"\n\n_spec := "v0.1"\n' > engines/rego/ergo.rego
for name in policy report; do
  printf '{\n  "$id": "https://ergo.kosli.com/spec/0.1/%s.schema.json"\n}\n' "$name" > "spec/$name/schema.json"
done
git add .
git -c user.name=test -c user.email=test@example.com -c commit.gpgSign=false commit --quiet --message release
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rego-v0.1.0
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag spec-v0.1
printf 'package ergo\n\nversion := "0.2.0-dev"\n\n_spec := "v0.2-dev"\n' > engines/rego/ergo.rego

fails() {
  if out=$(site/prepare.sh "$@" 2>&1); then
    echo "prepare.sh should fail with \"$expected\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$expected"*) ;;
    *)
      echo "prepare.sh should fail with \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
}

has() {
  [ -e "$1" ] || {
    echo "prepare.sh should write $1" >&2
    exit 1
  }
}

lacks() {
  [ ! -e "$1" ] || {
    echo "prepare.sh shouldn't write $1" >&2
    exit 1
  }
}

says() {
  [ "$(cat "$1")" = "$2" ] || {
    echo "$1 should say $2, and says $(cat "$1")" >&2
    exit 1
  }
}

FAKE_RELEASES="rego-v0.1.0 rego-v0.3.0-rc1 rego-vlatest spec-v0.1"
FAKE_ASSET_VERSION=0.1.0
export FAKE_RELEASES FAKE_ASSET_VERSION

out=$(site/prepare.sh)
case $out in
  *"rego-v0.1.0 has no site/data/examples.yaml"*) ;;
  *)
    echo "prepare.sh should say the home page's examples come from the working tree, and said: $out" >&2
    exit 1
    ;;
esac
says site/prepared/source rego-v0.1.0
says site/prepared/data/release.json '{"source": "rego-v0.1.0", "rego": "0.1.0", "rust": "", "spec": "0.1", "ergo_spec": "v0.1", "opa": "", "cli": ""}'
says site/prepared/repo/README.md '# Readme
"version": "0.1.0"
10.1.0-dev
0.1.0-devX
0.1.0-dev-rc
v0.1.0-dev
0.1.0 0.1.0
Ergo is at 0.1.0.
x.0.1.0-dev'
says site/prepared/repo/REFERENCE.md 'expected ergo.rego 0.1.0'
has site/prepared/examples/demo/demo.rego.txt
has site/prepared/examples/demo/input.json.txt
lacks site/prepared/examples/demo/demo.rego
has site/prepared/assets/js/tutorial/lib.mjs
has site/prepared/assets/js/tutorial/main.mjs
lacks site/prepared/assets/js/tutorial/lib.test.mjs
has site/prepared/assets/css/tutorial.css
has site/prepared/reference/ergo.css
has site/prepared/layouts/tutorial.html
has site/prepared/content/tutorial.md
lacks site/prepared/data/examples.yaml
has site/assets/tutorial/ergo.wasm
has site/assets/tutorial/vendor/opa-wasm.mjs
has site/static/spec/0.1/policy.schema.json
grep -qxF 'version := "0.1.0"' site/prepared/ergo.rego.txt || {
  echo "prepare.sh should copy the release's ergo.rego, which says 0.1.0" >&2
  exit 1
}

mkdir -p site/data
echo "deploy: {}" > site/data/examples.yaml
git add site/data/examples.yaml
git -c user.name=test -c user.email=test@example.com -c commit.gpgSign=false commit --quiet --message examples
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rego-v0.10.0
FAKE_RELEASES="rego-v0.9.0 rego-v0.10.0 rego-v0.1.0 spec-v0.1" FAKE_ASSET_VERSION=0.10.0 site/prepare.sh > /dev/null
says site/prepared/source rego-v0.10.0
has site/prepared/data/examples.yaml

FAKE_RELEASES="rego-v0.1.0 spec-v0.1" FAKE_PRE_RELEASES="rego-v0.10.0 spec-v0.9" FAKE_DRAFTS="rego-v0.10.0 spec-v0.9" site/prepare.sh > /dev/null
says site/prepared/source rego-v0.1.0
says site/prepared/data/release.json '{"source": "rego-v0.1.0", "rego": "0.1.0", "rust": "", "spec": "0.1", "ergo_spec": "v0.1", "opa": "", "cli": ""}'

git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rust-v0.2.0
FAKE_RELEASES="rego-v0.1.0 spec-v0.1 rust-v0.1.0 rust-v0.2.0 rust-v0.10.0-rc1" site/prepare.sh > /dev/null
says site/prepared/data/release.json '{"source": "rego-v0.1.0", "rego": "0.1.0", "rust": "0.2.0", "spec": "0.1", "ergo_spec": "v0.1", "opa": "", "cli": ""}'

git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag spec-v0.2
FAKE_RELEASES="rego-v0.10.0 spec-v0.1" FAKE_ASSET_VERSION=0.10.0 site/prepare.sh > /dev/null
has site/static/spec/0.1/policy.schema.json
lacks site/static/spec/0.2
(FAKE_RELEASES="rego-v0.10.0"; FAKE_ASSET_VERSION=0.10.0; expected="kosli-dev/ergo has no published spec-vX.Y release"; fails)
(FAKE_RELEASES="rego-v0.10.0 spec-v0.1 spec-v0.3"; FAKE_ASSET_VERSION=0.10.0; expected="There's no spec-v0.3 tag here. Fetch the tags with: git fetch --tags"; fails)
(FAKE_RELEASES="rego-v0.10.0 spec-v0.1"; FAKE_ASSET_VERSION=0.10.0; export FAKE_ASSET_SPEC=v0.2; expected="The ergo.rego of rego-v0.10.0 reads spec v0.2, and spec-v0.2 isn't published, so the site would link to schemas it doesn't have"; fails)
(FAKE_RELEASES="rego-v0.10.0 spec-v0.1 rust-v0.3.0"; FAKE_ASSET_VERSION=0.10.0; expected="There's no rust-v0.3.0 tag here. Fetch the tags with: git fetch --tags"; fails)
git tag --delete spec-v0.2 rust-v0.2.0 > /dev/null

echo "# Working" > README.md
site/prepare.sh --working-tree > /dev/null
says site/prepared/source "working tree"
says site/prepared/repo/README.md "# Working"
says site/prepared/data/release.json '{"source": "working tree", "rego": "", "rust": "", "spec": "0.1", "ergo_spec": "v0.2-dev", "opa": "", "cli": ""}'
has site/prepared/repo/README.md
has site/prepared/examples/demo/demo.rego.txt
lacks site/prepared/assets
has site/assets/tutorial/ergo.wasm

git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rust-v0.4.1
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rust-v0.4.0
site/prepare.sh --working-tree > /dev/null
says site/prepared/data/release.json '{"source": "working tree", "rego": "", "rust": "0.4.1", "spec": "0.1", "ergo_spec": "v0.2-dev", "opa": "", "cli": ""}'
git tag --delete rust-v0.4.1 rust-v0.4.0 > /dev/null

printf 'package ergo\n\nversion := "0.3.0-dev"\n\n_spec := "v0.3"\n' > engines/rego/ergo.rego
site/prepare.sh --working-tree > /dev/null
says site/prepared/data/release.json '{"source": "working tree", "rego": "", "rust": "", "spec": "0.1", "ergo_spec": "v0.3", "opa": "", "cli": ""}'
printf 'package ergo\n\nversion := "0.2.0-dev"\n\n_spec := "v0.2-dev"\n' > engines/rego/ergo.rego

(expected="usage: site/prepare.sh [--working-tree]"; fails --release)
(FAKE_RELEASES="rego-v1.0.0-rc1 rego-vlatest spec-v0.1"; expected="kosli-dev/ergo has no published rego-vX.Y.Z release"; fails)
(FAKE_RELEASES="rego-v0.4.0 spec-v0.1"; expected="There's no rego-v0.4.0 tag here. Fetch the tags with: git fetch --tags"; fails)
(FAKE_RELEASES="rego-v0.10.0 spec-v0.1"; FAKE_ASSET_VERSION=0.1.0-dev; expected='The ergo.rego of release rego-v0.10.0 should say version := "0.10.0"'; fails)
(export FAKE_GH_FAILS=1; expected="To build from this working tree instead, run: site/prepare.sh --working-tree"; fails)
echo "# OPA" > OPA.md
echo "# CLI" > CLI.md
git add OPA.md CLI.md
git -c user.name=test -c user.email=test@example.com -c commit.gpgSign=false commit --quiet --message "the engine pages"
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag --force spec-v0.1 > /dev/null
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rego-v0.11.0
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag rust-v0.5.0
FAKE_RELEASES="rego-v0.11.0 rust-v0.5.0 spec-v0.1" FAKE_ASSET_VERSION=0.11.0 FAKE_ASSET_SPEC=v0.1 site/prepare.sh > /dev/null
says site/prepared/source spec-v0.1
says site/prepared/data/release.json '{"source": "spec-v0.1", "rego": "0.11.0", "rust": "0.5.0", "spec": "0.1", "ergo_spec": "v0.1", "opa": "rego-v0.11.0", "cli": "rust-v0.5.0"}'
has site/prepared/repo/README.md
has site/prepared/repo/REFERENCE.md
says site/prepared/repo/OPA.md "# OPA"
says site/prepared/repo/CLI.md "# CLI"
grep -qxF 'version := "0.11.0"' site/prepared/ergo.rego.txt || {
  echo "prepare.sh should run the ergo.rego of the newest release that reads the spec, which says 0.11.0" >&2
  exit 1
}
out=$(FAKE_RELEASES="rego-v0.11.0 spec-v0.1" FAKE_ASSET_VERSION=0.11.0 FAKE_ASSET_SPEC=v0.1 site/prepare.sh)
case $out in
  *"don't all have OPA.md and CLI.md yet"*) ;;
  *)
    echo "prepare.sh should say the docs come from the old layout when there is no Rust release, and said: $out" >&2
    exit 1
    ;;
esac
says site/prepared/source rego-v0.11.0
says site/prepared/data/release.json '{"source": "rego-v0.11.0", "rego": "0.11.0", "rust": "", "spec": "0.1", "ergo_spec": "v0.1", "opa": "", "cli": ""}'
lacks site/prepared/repo/OPA.md
git -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag spec-v0.2
(FAKE_RELEASES="rego-v0.11.0 rust-v0.5.0 spec-v0.1 spec-v0.2"; FAKE_ASSET_VERSION=0.11.0; FAKE_ASSET_SPEC=v0.1; expected="No published rego-vX.Y.Z release reads spec v0.2, so the tutorial has no ergo.rego to run"; fails)
git tag --delete spec-v0.2 rego-v0.11.0 rust-v0.5.0 > /dev/null
git tag --delete spec-v0.1 > /dev/null
(FAKE_RELEASES="rego-v0.10.0 spec-v0.1"; FAKE_ASSET_VERSION=0.10.0; expected="There's no spec-v0.1 tag here. Fetch the tags with: git fetch --tags"; fails)
(expected="There's no spec-vX.Y tag here. Fetch the tags with: git fetch --tags"; fails --working-tree)

echo "prepare.sh builds from the latest published release, or from the working tree"
