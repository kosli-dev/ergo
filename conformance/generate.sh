#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
both=$(mktemp)
trap 'rm -f "$both"' EXIT
opa eval -d . --ignore .github --format raw 'json.marshal([data.conformance, data.conformance_test.generated])' > "$both"
jq -e '[.[0][][][] | .cases | length] == [.[1][][][] | .cases | length]' "$both" > /dev/null || {
	echo "Some cases give no report. Run: opa eval -d . --ignore .github 'data.conformance_test.failures'" >&2
	exit 1
}
jq -r '.[1] | to_entries[] | .key as $a | .value | keys[] | "\($a)/\(.)"' "$both" | while read -r file; do
	jq --arg f "$file" '($f | split("/")) as [$a, $t] | .[1][$a][$t]' "$both" > "conformance/$file/cases.json"
done
