#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

fails() {
  sed "$1" .github/workflows/release.yml > "$dir/release.yml"
  if cmp -s .github/workflows/release.yml "$dir/release.yml"; then
    echo "the change $1 doesn't apply to release.yml" >&2
    exit 1
  fi
  if out=$(python3 .github/release-latest.py "$dir/release.yml"); then
    echo "release-latest.py should fail with \"$2\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$2"*) ;;
    *)
      echo "release-latest.py should fail with \"$2\", and said: $out" >&2
      exit 1
      ;;
  esac
}

python3 .github/release-latest.py > /dev/null
fails 's/--latest=false/--latest/' "release-spec must create its release with --latest=false only, and has --latest"
fails '/--latest=false/d' "release-spec must create its release with --latest=false only, and has no --latest"
fails 's/^            --latest \\$/            --latest=false \\/' "release-rego must create its release with --latest only, and has --latest=false"
fails '/^            --latest \\$/d' "release-rego must create its release with --latest only, and has no --latest"
fails 's/^  release-spec:$/  publish-spec:/' "has no release-spec job"
echo "release-latest.py fails unless only ergo.rego releases can be the latest"
