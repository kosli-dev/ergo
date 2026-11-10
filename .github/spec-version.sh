#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail() {
  echo "$1"
  exit 1
}

swept_paths=(
  engines/rego/ergo.rego
  engines/rust/engine
  REFERENCE.md
  OPA.md
  spec
  packages
  site/assets/js/tutorial
  .github/wasm-js.cjs
  examples
)

swept_files() {
  git ls-files -- "${swept_paths[@]}" |
    grep -v -E '(^|/)CHANGELOG\.md$|^spec/sentences-corpus' |
    grep -v -E '_test\.sh$|\.(svg|png|ico|wasm)$' || true
}

version_pattern() {
  printf '(?<![\\w.])(v?)%s(?!\\w|\\.\\d|-\\w)' "$(printf '%s' "${1#v}" | sed 's/\./\\./g')"
}

files_with() {
  local pattern f
  pattern=$(version_pattern "$1")
  for f in $(swept_files); do
    if PATTERN=$pattern perl -ne 'BEGIN { $p = qr/$ENV{PATTERN}/ } $found = 1 if /$p/; END { exit($found ? 0 : 1) }' "$f"; then
      echo "$f"
    fi
  done
}

if [ "${1:-}" = set ]; then
  new=${2:-}
  [[ $new =~ ^v[0-9]+\.[0-9]+(-dev)?$ ]] || fail "Usage: .github/spec-version.sh set vX.Y or vX.Y-dev"
  old=$(sed -n 's/^_spec := "\(v[0-9][0-9.]*\(-dev\)\{0,1\}\)"$/\1/p' engines/rego/ergo.rego)
  [ -n "$old" ] || fail 'ergo.rego must say _spec := "vX.Y" or _spec := "vX.Y-dev"'
  [ "$new" != "$old" ] || fail "The spec already says $old"
  pattern=$(version_pattern "$old")
  for f in $(files_with "$old"); do
    PATTERN=$pattern NEW=${new#v} perl -i -pe 'BEGIN { $p = qr/$ENV{PATTERN}/ } s/$p/$1$ENV{NEW}/g' "$f"
    echo "$f"
  done
  echo "Not changed, by hand: README.md, CLI.md, the engine versions"
  heading=${new#v}
  echo "spec/CHANGELOG.md needs a \"## ${heading%-dev}\" heading"
  exit 0
fi

check_leftovers() {
  local current=${rego%-dev} previous leftovers
  [ "${current#*.}" -gt 0 ] || return 0
  previous="v${current%%.*}.$((10#${current#*.} - 1))-dev"
  leftovers=$(files_with "$previous")
  [ -z "$leftovers" ] || {
    echo "These files still write $previous, the previous dev version:"
    echo "$leftovers" | sed 's/^/  /'
    fail "The spec is at v$rego, so $previous should be gone. Run .github/spec-version.sh set v$rego, or edit them by hand."
  }
}

defining=(
  spec/syntax.md
  spec/semantics.md
  spec/policy/schema.json
  spec/report/schema.json
  spec/sentences.abnf
  spec/cases
)

rego=$(sed -n 's/^_spec := "v\([0-9][0-9.]*\(-dev\)\{0,1\}\)"$/\1/p' engines/rego/ergo.rego)
[ -n "$rego" ] || fail 'ergo.rego must say _spec := "vX.Y" or _spec := "vX.Y-dev"'

for name in policy report; do
  id=$(sed -n "s|^ *\"\\\$id\": *\".*/spec/\\([^/]*\\)/$name.schema.json\",\{0,1\}\$|\\1|p" "spec/$name/schema.json")
  [ -n "$id" ] || fail "spec/$name/schema.json has no \$id that ends in /spec/X.Y/$name.schema.json"
  [ "$id" = "$rego" ] || fail "spec/$name/schema.json says $id in its \$id, but ergo.rego says _spec := \"v$rego\". They must match."
done

version=${rego%-dev}
if [[ $version =~ ^[0-9]+\.[0-9]+$ ]]; then :; else fail "The spec version v$rego must look like v0.2 or v0.2-dev"; fi

latest=$(git tag --list 'spec-v*' | grep -E '^spec-v[0-9]+\.[0-9]+$' | sed 's/^spec-v//' | sort -V | tail -n 1 || true)

dev=false
[ "$rego" != "$version" ] && dev=true
next=
[ -n "$latest" ] && next="${latest%%.*}.$((10#${latest#*.} + 1))"

if [ -n "$latest" ] && [ "$version" != "$latest" ]; then
  [ "$version" = "$next" ] || fail "The spec says v$rego, but the latest release is spec-v$latest, so it must say v$next-dev, or v$next when it's ready to release"
fi

if $dev || { [ -n "$latest" ] && [ "$version" != "$latest" ]; }; then
  grep -qxF "## $version" spec/CHANGELOG.md || fail "spec/CHANGELOG.md has no \"## $version\" heading for v$rego"
  check_leftovers
  exit 0
fi

[ -n "$latest" ] || { check_leftovers; exit 0; }

if ! git diff --quiet "spec-v$latest" -- "${defining[@]}"; then
  echo "Changed since spec-v$latest:"
  git diff --name-only "spec-v$latest" -- "${defining[@]}" | sed 's/^/  /'
  fail "spec/ changed since spec-v$latest, so move the spec to v${latest%%.*}.$((10#${latest#*.} + 1))-dev"
fi
check_leftovers
