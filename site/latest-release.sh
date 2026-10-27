#!/bin/sh
set -eu
case ${1:-} in
  rego) pattern='^rego-v[0-9]+\.[0-9]+\.[0-9]+$' ;;
  spec) pattern='^spec-v[0-9]+\.[0-9]+$' ;;
  *)
    echo "usage: site/latest-release.sh rego|spec < tag names" >&2
    exit 2
    ;;
esac
matching=$(grep -E "$pattern") || [ $? -eq 1 ]
[ -n "$matching" ] || exit 0
sorted=$(printf '%s\n' "$matching" | sort -V)
printf '%s\n' "$sorted" | tail -n 1
