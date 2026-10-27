#!/bin/sh
set -eu
case ${1:-} in
  rego) pattern='^rego-v[0-9]+\.[0-9]+\.[0-9]+$' ;;
  spec) pattern='^spec-v[0-9]+\.[0-9]+$' ;;
  *)
    echo "usage: site/latest-release.sh rego|spec" >&2
    exit 2
    ;;
esac
git tag --list "$1-v*" | grep -E "$pattern" | sort -V | tail -n 1 || true
