#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
cd "$dir"
git init -q
git config tag.gpgsign false
mkdir -p site packages/playground packages/markdown/cases engines/rego engines/rust spec bin
/bin/cp -f "$root/site/prepare-playground.sh" "$root/site/latest-release.sh" site/
printf 'released samples\n' > packages/markdown/cases/samples
printf 'released readme\n' > README.md
printf 'old interface\n' > packages/interface
printf 'export const sampleCases = { bakery: "baking" };\n' > packages/playground/build.mjs
printf 'version := "0.9.0-dev"\n' > engines/rego/ergo.rego
printf 'old rust\n' > engines/rust/source
printf 'released corpus\n' > spec/sentences-corpus.json
git add .
git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.com commit -qm release
git tag rego-v0.9.0
git tag rego-v0.8.0
printf 'released rust\n' > engines/rust/source
printf 'released rust corpus\n' > spec/sentences-corpus.json
git add .
git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.com commit -qm rust
git tag rust-v0.10.0
git tag rust-v0.9.0
printf 'current interface\n' > packages/interface
git add packages/interface
git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.com commit -qm interface
printf 'unreleased corpus\n' > spec/sentences-corpus.json
printf 'unreleased samples\n' > packages/markdown/cases/samples
printf 'unreleased rego\n' > engines/rego/ergo.rego
printf 'unreleased rust\n' > engines/rust/source
cat > bin/gh <<'GH'
#!/bin/sh
set -eu
case $2 in
  list)
    [ "$*" = 'release list --repo kosli-dev/ergo --exclude-drafts --exclude-pre-releases --limit 1000 --json tagName --jq .[].tagName' ]
    printf '%s\n' ${RELEASES-rego-v0.8.0 rust-v0.9.0 rego-v0.9.0 rust-v0.10.0 rego-v1.0.0-rc1 rust-v1.0.0-rc1}
    ;;
  download)
    [ "$3" = rego-v0.9.0 ]
    while [ "$1" != --dir ]; do shift; done
    mkdir -p "$2"
    printf 'version := "%s"\n' "${ASSET_VERSION-0.9.0}" > "$2/ergo.rego"
    ;;
  *) exit 1 ;;
esac
GH
chmod +x bin/gh
export PATH="$dir/bin:$PATH"
site/prepare-playground.sh "$dir/out"
grep -qxF 'released samples' out/packages/markdown/cases/samples
grep -qxF 'current interface' out/packages/interface
grep -qxF 'export const sampleCases = { bakery: "baking" };' out/packages/playground/released-build.mjs
grep -qxF 'released rust' out/engines/rust/source
grep -qxF 'released rust corpus' out/spec/sentences-corpus.json
grep -qxF 'version := "0.9.0"' out/engines/rego/ergo.rego
if RELEASES=rego-v0.9.0 site/prepare-playground.sh "$dir/missing"; then exit 1; fi
if ASSET_VERSION=0.9.0-dev site/prepare-playground.sh "$dir/wrong"; then exit 1; fi
if site/prepare-playground.sh "$dir/out"; then exit 1; fi
printf '%s\n' 'prepare-playground.sh stages published engines and samples with the current interface'
