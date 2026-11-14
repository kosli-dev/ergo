#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

found=$(git ls-files '*.rs' | grep -v -E '(^|/)tests\.rs$' | while read -r file; do
  awk -v file="$file" '
    { line[NR] = $0 }
    /^[[:space:]]*(#\[cfg\(test\)\][[:space:]]*)?(pub(\([a-z]+\))? )?mod [A-Za-z_0-9]+[[:space:]]*\{/ {
      inline = ($0 ~ /#\[cfg\(test\)\]/ || $0 ~ /mod tests[[:space:]]*\{/)
      for (back = 1; back <= 2 && NR - back >= 1; back++) {
        if (line[NR - back] ~ /^[[:space:]]*#\[cfg\(test\)\]/) inline = 1
      }
      if (inline) print file ":" NR
    }
  ' "$file"
done)

if [ -n "$found" ]; then
  echo "These lines start a test module inside a source file:"
  printf '%s\n' "$found" | sed 's/^/  /'
  echo "Move its tests to <file>/tests.rs, with #[cfg(test)] mod tests; left in the source file, or to the crate's tests/ folder."
  exit 1
fi
echo "ok: no Rust source file holds an inline test module"
