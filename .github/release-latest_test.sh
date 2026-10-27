#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

copy() {
  rm -rf "$dir/.github"
  mkdir -p "$dir/.github/workflows"
  cp .github/workflows/release.yml "$dir/.github/workflows/"
}

check() {
  if out=$(python3 .github/release-latest.py "$dir/.github"); then
    echo "release-latest.py should fail with \"$1\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$1"*) ;;
    *)
      echo "release-latest.py should fail with \"$1\", and said: $out" >&2
      exit 1
      ;;
  esac
}

fails() {
  copy
  sed "$1" .github/workflows/release.yml > "$dir/.github/workflows/release.yml"
  if cmp -s .github/workflows/release.yml "$dir/.github/workflows/release.yml"; then
    echo "the change $1 doesn't apply to release.yml" >&2
    exit 1
  fi
  check "$2"
}

python3 .github/release-latest.py > /dev/null
copy
python3 .github/release-latest.py "$dir/.github" > /dev/null
fails 's/--latest=false \\$/--latest \\/' "release-spec must create its release with --latest=false only, and has --latest"
fails '/--latest=false \\$/d' "release-spec must create its release with --latest=false only, and has no --latest"
fails 's/"$latest" \\$/--latest \\/' "release-rego must create its release with \"\$latest\" only, and has --latest"
fails '/"$latest" \\$/d' "release-rego must create its release with \"\$latest\" only, and has no --latest"
fails 's/if \[ "$TAG" = "$highest" \]; then/if true; then/' "release-rego must mark its release as the latest only when it's the highest rego-v version"
fails 's/| sort -V |/| sort |/' "release-rego must mark its release as the latest only when it's the highest rego-v version"
fails 's/^  release-spec:$/  publish-spec:/' "has no release-spec job"
fails 's/^  release-rego:$/  publish-rego:/' "publish-rego creates a release, and only release-rego and release-spec may"

copy
printf '%s\n' 'jobs:' '  edit:' '    steps:' '      - run: gh release edit rego-v0.1.0 --latest' > "$dir/.github/workflows/other.yml"
check "other.yml changes which release is the latest"
copy
printf '%s\n' 'gh api repos/kosli-dev/ergo/releases -f tag_name=spec-v0.2 -f make_latest=true' > "$dir/.github/publish.sh"
check "publish.sh changes which release is the latest"
copy
printf '%s\n' 'gh release create spec-v0.2 --latest=false' > "$dir/.github/publish.sh"
check "publish.sh creates a release, and only release.yml may"
echo "release-latest.py fails unless only the highest ergo.rego release can be the latest"
