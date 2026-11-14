#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/rego-layers.py
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/src/shared" "$dir/src/reading" "$dir/src/report"
printf 'package ergo\n\nimport rego.v1\n\n_base(x) := x\n' > "$dir/src/shared/a.rego"
printf 'package ergo\n\nimport rego.v1\n\n_read(x) := _base(x)\n' > "$dir/src/reading/b.rego"
printf 'package ergo\n\nimport rego.v1\n\nreport(x) := _read(x)\n' > "$dir/src/report/c.rego"
: > "$dir/known.txt"

echo "rego-layers.py passes when every call goes to the same folder or an earlier one"
python3 "$script" "$dir/src" "$dir/known.txt"

printf 'package ergo\n\nimport rego.v1\n\n_base(x) := _read(x)\n' > "$dir/src/shared/a.rego"
echo "rego-layers.py fails on a call to a later folder and names it"
if out=$(python3 "$script" "$dir/src" "$dir/known.txt" 2>&1); then
  echo "rego-layers.py should fail, and passed" >&2
  exit 1
fi
case $out in
  *"a.rego:5 _base -> _read (shared -> reading)"*) ;;
  *)
    echo "rego-layers.py should name the call, and said: $out" >&2
    exit 1
    ;;
esac

echo "_base -> _read" > "$dir/known.txt"
echo "rego-layers.py passes when the backward call is on the list"
python3 "$script" "$dir/src" "$dir/known.txt"

printf 'package ergo\n\nimport rego.v1\n\n_base(x) := x\n' > "$dir/src/shared/a.rego"
echo "rego-layers.py fails when a listed call no longer exists"
if out=$(python3 "$script" "$dir/src" "$dir/known.txt" 2>&1); then
  echo "rego-layers.py should fail on a stale line, and passed" >&2
  exit 1
fi
case $out in
  *"_base -> _read is listed but no longer exists"*) ;;
  *)
    echo "rego-layers.py should name the stale line, and said: $out" >&2
    exit 1
    ;;
esac

printf 'package ergo\n\nimport rego.v1\n\n_base(x) := data.ergo._read(x)\n' > "$dir/src/shared/a.rego"
: > "$dir/known.txt"
echo "rego-layers.py sees a data.ergo reference to a later folder"
if python3 "$script" "$dir/src" "$dir/known.txt" > /dev/null 2>&1; then
  echo "rego-layers.py should fail on a data.ergo reference, and passed" >&2
  exit 1
fi
echo "ok"
