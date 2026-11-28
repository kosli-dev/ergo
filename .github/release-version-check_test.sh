#!/bin/bash
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/release-version-check.sh
hash=0123456789abcdef0123456789abcdef01234567

passes() {
  local version=$1 line=$2 out
  if ! out=$(printf '%b' "$line" | bash "$script" "$version" 2>&1); then
    echo "release-version-check.sh should pass for $version and \"$line\", and said: $out" >&2
    exit 1
  fi
}

fails() {
  local version=$1 line=$2
  if printf '%b' "$line" | bash "$script" "$version" >/dev/null 2>&1; then
    echo "release-version-check.sh should fail for $version and \"$line\", and passed" >&2
    exit 1
  fi
}

passes 0.5.0 "ergo 0.5.0 (commit $hash)\n"
passes 0.5.0 "ergo 0.5.0 (commit unknown)\n"
passes 0.5.0 "ergo 0.5.0\n"
passes 0.5.0 "ergo 0.5.0 (commit $hash)\r\n"
passes 0.5.0 "ergo 0.5.0"
fails 0.5.0 "ergo 0.5.0-dev (commit $hash)\n"
fails 0.5.0 "ergo 0.5.1 (commit $hash)\n"
fails 0.5.0 "ergo 0.5.10\n"
fails 0.5.0 "something 0.5.0\n"
fails 0.5.0 "ergo0.5.0\n"
fails 0.5.0 " ergo 0.5.0\n"
fails 0.5.0 ""
fails 0.5.0 "\n"

out=$(printf 'ergo 0.5.1 (commit x)\n' | bash "$script" 0.5.0 2>&1 || true)
case $out in
  *"ergo 0.5.1 (commit x)"*"0.5.0"*) ;;
  *) echo "release-version-check.sh should say the line and the version it wanted, and said: $out" >&2; exit 1 ;;
esac
