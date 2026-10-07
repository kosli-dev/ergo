#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
files=$(mktemp)
trap 'rm -f "$files"' EXIT
opa eval -d . --ignore .github --format raw 'json.marshal({"counts": [[count(g.cases) | some _, t in data.conformance; some _, gs in t; some g in gs], [count(g.cases) | some _, t in data.conformance_test.generated; some _, gs in t; some g in gs]], "files": {concat("/", [a, t]): json.marshal_with_options(groups, {"pretty": true, "indent": "  "}) | some a, topics in data.conformance_test.generated; some t, groups in topics}})' > "$files"
jq -e '.counts[0] == .counts[1]' "$files" > /dev/null || {
	echo "Some cases give no report. Run: opa eval -d . --ignore .github 'data.conformance_test.failures'" >&2
	exit 1
}
jq -r '.files | keys[]' "$files" | while read -r file; do
	jq -r --arg f "$file" '.files[$f]' "$files" > "conformance/$file/cases.json"
done
