#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
both=$(opa eval -d . --ignore .github --format raw 'json.marshal([data.conformance, data.conformance_test.generated])')
echo "$both" | jq -e '.[0] | [.[][][] | .cases | length] == ($both | fromjson | .[1] | [.[][][] | .cases | length])' --arg both "$both" > /dev/null || {
	echo "Some cases give no report. Run: opa eval -d . --ignore .github 'data.conformance_test.failures'" >&2
	exit 1
}
echo "$both" | jq -r '.[1] | to_entries[] | .key as $a | .value | keys[] | "\($a)/\(.)"' | while read -r file; do
	echo "$both" | jq --arg f "$file" '($f | split("/")) as [$a, $t] | .[1][$a][$t]' > "conformance/$file/cases.json"
done
