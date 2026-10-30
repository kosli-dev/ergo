#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/latest-release.sh

check() {
  actual=$(printf '%s\n' "$3" | "$script" "$1")
  if [ "$actual" != "$2" ]; then
    echo "$4: the latest $1 release should be \"$2\", and is \"$actual\"" >&2
    exit 1
  fi
}

all='rego-v0.10.0
rego-v0.9.0
rego-v0.2.0
rego-v1.0.0-rc1
rego-v2
rego-vlatest
rust-v0.2.0
rust-v0.10.1
rust-v0.9.0
rust-v1.0.0-rc1
rust-v2
rust-vlatest
spec-v0.10
spec-v0.9
spec-v1.0.0
spec-v2
spec-v1.0-dev'
bad='rego-v1.0.0-rc1
rego-v2
rego-vlatest
rust-v1.0.0-rc1
rust-v2
rust-vlatest
spec-v1.0.0
spec-v2
spec-v1.0-dev'

check rego "" "" "no tags"
check rust "" "" "no tags"
check spec "" "" "no tags"
check rego "" "$bad" "only bad-shaped tags"
check rust "" "$bad" "only bad-shaped tags"
check spec "" "$bad" "only bad-shaped tags"
check rego rego-v0.10.0 "$all" "mixed tags"
check rust rust-v0.10.1 "$all" "mixed tags"
check spec spec-v0.10 "$all" "mixed tags"
echo "latest-release.sh picks the highest version and ignores other tags"
