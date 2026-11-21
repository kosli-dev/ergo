#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/docs-run-release.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"

mkdir bin
cat > bin/fake-gh <<'GH'
#!/bin/sh
echo "$2" >> "$FAKE_CALLS"
if [ -n "${FAKE_FAILS:-}" ]; then
  n=$(cat "$FAKE_COUNT" 2> /dev/null || echo 0)
  if [ "$n" -lt "$FAKE_FAILS" ]; then
    echo $((n + 1)) > "$FAKE_COUNT"
    echo "HTTP 502" >&2
    exit 1
  fi
fi
case $2 in
  list)
    filter=
    while [ $# -gt 0 ]; do
      if [ "$1" = --jq ]; then filter=$2; fi
      shift
    done
    printf '%s\n' "${FAKE_JSON:-[]}" | jq -r "$filter"
    ;;
  download)
    if [ "${FAKE_EMPTY:-}" = 1 ]; then : > "$9/ergo.rego"; else printf '_spec := "v7.7"\n' > "$9/ergo.rego"; fi
    ;;
esac
GH
chmod +x bin/fake-gh
cat > bin/fake-docs-run <<'RUN'
#!/bin/sh
echo "got $DOCS_RUN_REQUIRE_RELEASE $(cat "$DOCS_RUN_RELEASE_ERGO_REGO")"
echo "note $DOCS_RUN_RELEASE_NOTE"
RUN
chmod +x bin/fake-docs-run
export DOCS_RUN_GH="$dir/bin/fake-gh"
export DOCS_RUN_RETRY_SLEEP=0
export FAKE_CALLS=$dir/calls
export FAKE_COUNT=$dir/count

fake=$dir/fake
mkdir -p "$fake/.github" "$fake/engines/rego/src/shared" "$fake/dist"
cp -f bin/fake-docs-run "$fake/.github/docs-run.sh"
cp -f "$script" "$fake/.github/docs-run-release.sh"
printf '_spec := "built"\n' > "$fake/dist/ergo.rego"
script=$fake/.github/docs-run-release.sh

basics() {
  printf 'version := "%s"\n_spec := "%s"\n' "$1" "$2" > "$fake/engines/rego/src/shared/basics.rego"
}

reset() {
  /bin/rm -f "$dir/calls" "$dir/count"
}

basics 0.7.0-dev v0.7-dev
latest='[{"tagName":"rego-v0.6.1","isLatest":false},{"tagName":"rego-v0.6.0","isLatest":true}]'

echo "docs-run-release.sh downloads the release marked Latest and requires the release groups to run"
reset
FAKE_JSON=$latest sh "$script" > out.txt
grep -qF 'got 1 _spec := "v7.7"' out.txt || {
  echo "docs-run-release.sh should pass the release file and the require flag, and said: $(cat out.txt)" >&2
  exit 1
}
grep -qF 'checking against ergo.rego from rego-v0.6.0' out.txt || {
  echo "docs-run-release.sh should say it used rego-v0.6.0 and not the older fix release listed first, and said: $(cat out.txt)" >&2
  exit 1
}
grep -qF 'from rego-v0.6.0 (the latest release); when preparing a release, _spec and version in basics.rego have no -dev and it compares with dist/ergo.rego' out.txt || {
  echo "docs-run-release.sh should pass the release note, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run-release.sh fails when there is no Latest release"
reset
if FAKE_JSON='[{"tagName":"rego-v0.6.0","isLatest":false}]' sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail with no Latest release, and passed" >&2
  exit 1
fi

echo "docs-run-release.sh fails with a clear message when the Latest release is not a rego release"
reset
if FAKE_JSON='[{"tagName":"rego-v0.6.0","isLatest":false},{"tagName":"spec-v0.6","isLatest":true}]' sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail when Latest is spec-v0.6, and passed" >&2
  exit 1
fi
grep -qF 'spec-v0.6' out.txt || {
  echo "docs-run-release.sh should name the Latest release, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run-release.sh fails when the release has an empty ergo.rego"
reset
if FAKE_JSON=$latest FAKE_EMPTY=1 sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail on an empty file, and passed" >&2
  exit 1
fi

echo "docs-run-release.sh retries once when gh fails, and says what to do"
reset
FAKE_FAILS=1 FAKE_JSON=$latest sh "$script" > out.txt 2> err.txt
grep -qF 'got 1 _spec := "v7.7"' out.txt || {
  echo "docs-run-release.sh should pass after one gh failure, and said: $(cat out.txt) $(cat err.txt)" >&2
  exit 1
}
grep -qF 'could not get the latest release: re-run the job if GitHub had an error' err.txt || {
  echo "docs-run-release.sh should say it could not get the release, and said: $(cat err.txt)" >&2
  exit 1
}

echo "docs-run-release.sh fails after gh fails twice"
reset
if FAKE_FAILS=2 FAKE_JSON=$latest sh "$script" > out.txt 2> err.txt; then
  echo "docs-run-release.sh should fail when gh fails twice, and passed" >&2
  exit 1
fi
grep -qF 'could not get the latest release: re-run the job if GitHub had an error' err.txt || {
  echo "docs-run-release.sh should say it could not get the release, and said: $(cat err.txt)" >&2
  exit 1
}
[ "$(grep -c list "$dir/calls")" = 2 ] || {
  echo "docs-run-release.sh should try the list twice, and called gh: $(cat "$dir/calls")" >&2
  exit 1
}

echo "docs-run-release.sh uses dist/ergo.rego without calling gh when _spec has no -dev"
reset
basics 0.7.0-dev v0.7
FAKE_JSON=$latest sh "$script" > out.txt
grep -qF 'got 1 _spec := "built"' out.txt || {
  echo "docs-run-release.sh should use the built file when preparing a spec release, and said: $(cat out.txt)" >&2
  exit 1
}
grep -qF 'dist/ergo.rego' out.txt || {
  echo "docs-run-release.sh should say it used dist/ergo.rego, and said: $(cat out.txt)" >&2
  exit 1
}
[ ! -e "$dir/calls" ] || {
  echo "docs-run-release.sh should not call gh when preparing a release" >&2
  exit 1
}

echo "docs-run-release.sh uses dist/ergo.rego when version has no -dev"
reset
basics 0.7.0 v0.7-dev
FAKE_JSON=$latest sh "$script" > out.txt
grep -qF 'got 1 _spec := "built"' out.txt || {
  echo "docs-run-release.sh should use the built file when preparing an ergo.rego release, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run-release.sh fails when preparing a release and dist/ergo.rego is missing"
/bin/rm -f "$fake/dist/ergo.rego"
if sh "$script" > out.txt 2>&1; then
  echo "docs-run-release.sh should fail without dist/ergo.rego, and passed" >&2
  exit 1
fi
