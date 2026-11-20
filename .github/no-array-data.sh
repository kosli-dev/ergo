#!/bin/sh
set -eu
root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "no-array-data.sh must run inside a git repository" >&2
  exit 1
}
cd "$root"
status=0
for file in $(git ls-files ':(glob)engines/rego/*.json' ':(glob)spec/*.json' ':(glob)examples/*.json' ':(glob)dist/*.json'); do
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    echo "$file is not a JSON object. OPA loads a file at the top of a folder as the data of that folder, where a list conflicts with the other files. Move it to a folder OPA does not load, like .github." >&2
    status=1
  fi
done
for file in $(git ls-files ':(glob)engines/rego/*.yaml' ':(glob)spec/*.yaml' ':(glob)examples/*.yaml' ':(glob)dist/*.yaml' ':(glob)engines/rego/*.yml' ':(glob)spec/*.yml' ':(glob)examples/*.yml' ':(glob)dist/*.yml'); do
  if ! ruby -ryaml -e 'exit(YAML.safe_load(File.read(ARGV[0]), aliases: true).is_a?(Hash) ? 0 : 1)' "$file" >/dev/null 2>&1; then
    echo "$file is not a YAML mapping. OPA loads a file at the top of a folder as the data of that folder, where a list conflicts with the other files. Move it to a folder OPA does not load, like .github." >&2
    status=1
  fi
done
exit $status
