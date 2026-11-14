#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "no-inline-tests.sh must run inside a git repository" >&2; exit 1; }
cd "$root"
files=$(git ls-files '*.rs') || { echo "no-inline-tests.sh could not list the files with git ls-files" >&2; exit 1; }

found=$(printf '%s\n' "$files" | while read -r file; do
  [ -n "$file" ] || continue
  case $file in
    (tests.rs | */tests.rs) continue ;;
  esac
  exempt=0
  case $file in
    (tests/* | */tests/*) exempt=1 ;;
  esac
  awk -v file="$file" -v exempt="$exempt" '
    /^[[:space:]]*(#\[cfg\(test\)\][[:space:]]*)?(pub(\([a-z]+\))? )?mod [A-Za-z_0-9]+[[:space:]]*\{/ {
      if (armed || $0 ~ /#\[cfg\(test\)\]/ || $0 ~ /mod tests[[:space:]]*\{/) print file ":" NR
      armed = 0
      next
    }
    /^[[:space:]]*#\[cfg\(test\)\][[:space:]]*$/ { armed = 1; next }
    /^[[:space:]]*#\[/ || /^[[:space:]]*$/ {
      if (!exempt && $0 ~ /^[[:space:]]*#\[[A-Za-z_0-9:]*test(\(.*\))?\]/) print file ":" NR
      next
    }
    { armed = 0 }
  ' "$file"
done)

if [ -n "$found" ]; then
  echo "These lines start a test module or a test function inside a source file:"
  printf '%s\n' "$found" | sed 's/^/  /'
  echo "Move the tests to <file>/tests.rs, with #[cfg(test)] mod tests; left in the source file, or to the crate's tests/ folder."
  exit 1
fi
echo "ok: no Rust source file holds an inline test module or test function"
