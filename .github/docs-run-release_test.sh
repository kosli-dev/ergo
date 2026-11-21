#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/docs-run-release.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"

mkdir bin
cat > bin/fake-gh <<'GH'
#!/bin/sh
case $2 in
  list)
    if [ -n "${FAKE_TAGS:-}" ]; then printf '%s\n' "$FAKE_TAGS"; fi
    ;;
  download)
    if [ "${FAKE_EMPTY:-}" = 1 ]; then : > "$8/ergo.rego"; else printf '_spec := "v7.7"\n' > "$8/ergo.rego"; fi
    ;;
esac
GH
chmod +x bin/fake-gh
cat > bin/fake-docs-run <<'RUN'
#!/bin/sh
echo "got $DOCS_RUN_REQUIRE_RELEASE $(cat "$DOCS_RUN_RELEASE_ERGO_REGO")"
RUN
chmod +x bin/fake-docs-run
export DOCS_RUN_GH="$dir/bin/fake-gh"

cp -f "$script" docs-run-release.sh
mkdir -p .github fake/.github
cp -f bin/fake-docs-run fake/.github/docs-run.sh
cp -f "$script" fake/.github/docs-run-release.sh
script=$dir/fake/.github/docs-run-release.sh

echo "docs-run-release.sh downloads the latest rego release and requires the release groups to run"
FAKE_TAGS=rego-v0.6.0 sh "$script" > out.txt
grep -qF 'got 1 _spec := "v7.7"' out.txt || {
  echo "docs-run-release.sh should pass the release file and the require flag, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run-release.sh fails when there is no rego release"
if FAKE_TAGS= sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail with no release, and passed" >&2
  exit 1
fi

echo "docs-run-release.sh fails when the release has an empty ergo.rego"
if FAKE_TAGS=rego-v0.6.0 FAKE_EMPTY=1 sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail on an empty file, and passed" >&2
  exit 1
fi
