#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

fails() {
  sed "$1" site/data/examples.yaml > "$dir/examples.yaml"
  if cmp -s site/data/examples.yaml "$dir/examples.yaml"; then
    echo "the change $1 doesn't apply to site/data/examples.yaml" >&2
    exit 1
  fi
  if out=$(python3 site/check_examples.py "$dir/examples.yaml" engines/rego/ergo.rego); then
    echo "check_examples.py should fail with \"$2\", and passed" >&2
    exit 1
  fi
  case $out in
    *"$2"*) ;;
    *)
      echo "check_examples.py should fail with \"$2\", and said: $out" >&2
      exit 1
      ;;
  esac
}

python3 site/check_examples.py > /dev/null
fails 's/"deny": \["d-2: no approval"\]/"deny": ["d-3: no approval"]/' 'deploy: plain Rego gives'
fails 's/{"id": "e-3", "amount": 35}/{"id": "e-3", "amount": 35, "receipt": "r-1.pdf"}/' 'expenses, row 8: passed is true in the report, and false on the page'
fails 's/inputs: \[{name: amount, value: 68}\]/inputs: [{name: amount, value: 67}]/' 'expenses, row 7: the report has no input amount = 67'
fails 's/assert: amount is at most 50/assert: amount is at most 70/' 'expenses, row 7: passed is true in the report, and false on the page'
fails 's/      check: approved$/      check: approval/' 'deploy, row 7: check is "approved" in the report, and "approval" on the page'
fails '/subject: e-3/,/cause: satisfied/d' 'expenses: the report has 9 rows, and the page shows 7'
fails 's/, list: username}/, list: login}/' 'review, row 4: the page lists the login of each item of approvers[], and not every item has one'
echo "check_examples.py fails when the page shows something the report doesn't say"
