#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
script=$here/rules.sh
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT
mkdir -p "$dir/spec/cases/one" "$dir/spec/cases/two"
cat > "$dir/spec/semantics.md" <<'DOC'
# Title

## Alpha section

**[alpha.first]** An item alias names the item. It is read once. A third sentence.

**[alpha.second]** A message says every problem.

## Beta section

**[beta.third]** A member of a list is an item. Aliases are not members.
DOC
cat > "$dir/spec/syntax.md" <<'DOC'
# Syntax

## Names

**[names.key]** A key is named by text.
DOC
cat > "$dir/spec/cases/one/cases.json" <<'DOC'
[{"description": "g1", "cases": [
  {"description": "c1", "rules": ["alpha.first", "alpha.second"]},
  {"description": "c2", "rules": ["alpha.first"]}]}]
DOC
cat > "$dir/spec/cases/two/cases.json" <<'DOC'
[{"description": "g2", "cases": [{"description": "c3", "rules": ["alpha.first"]}]}]
DOC
run() { RULES_SPEC_DIR=$dir/spec sh "$script" "$@"; }

echo "rules.sh prints the rules that contain every word, with section, two sentences and the cases that cite it"
out=$(run item alias)
case $out in
  *"alpha.first"*"Alpha section"*"An item alias names the item. It is read once."*"cited by 3 cases"*"one"*"two"*) ;;
  *) echo "unexpected: $out" >&2; exit 1 ;;
esac
case $out in
  *"A third sentence"* | *"beta.third"*) echo "too much: $out" >&2; exit 1 ;;
esac

echo "rules.sh matches a word in a rule name"
out=$(run first)
case $out in *"alpha.first"*) ;; *) echo "unexpected: $out" >&2; exit 1 ;; esac

echo "rules.sh matches whole words only, so alias does not match aliases"
out=$(run members aliases)
case $out in *"beta.third"*) ;; *) echo "unexpected: $out" >&2; exit 1 ;; esac
if out=$(run alias member 2>&1); then
  echo "alias member should match nothing: $out" >&2
  exit 1
fi

echo "rules.sh --any matches one word, and lists the rule with more matched words first"
out=$(run --any item message)
first=$(printf '%s\n' "$out" | grep 'alpha.first\|alpha.second\|beta.third' | head -1)
case $first in *"alpha.first"*) ;; *) echo "alpha.first should come first: $out" >&2; exit 1 ;; esac
case $out in *"alpha.second"*"beta.third"*) ;; *) echo "unexpected: $out" >&2; exit 1 ;; esac

echo "rules.sh reads the syntax file too"
out=$(run named key)
case $out in *"names.key"*"Names"*) ;; *) echo "unexpected: $out" >&2; exit 1 ;; esac

echo "rules.sh says no rule contains the words and exits 1 when nothing matches"
set +e
out=$(run zzzz qqqq 2>&1)
status=$?
set -e
[ "$status" = 1 ] || { echo "exit $status, wanted 1" >&2; exit 1; }
[ "$out" = "no rule contains: zzzz qqqq" ] || { echo "unexpected: $out" >&2; exit 1; }

echo "rules.sh --name prints one rule in full and the titles of the cases that cite it"
out=$(run --name alpha.first)
case $out in
  *"A third sentence."*"g1 / c1"*"g1 / c2"*"g2 / c3"*) ;;
  *) echo "unexpected: $out" >&2; exit 1 ;;
esac
if run --name nope >/dev/null 2>&1; then
  echo "--name nope should fail" >&2
  exit 1
fi

echo "rules.sh with no words prints the usage and fails"
if out=$(run 2>&1); then
  echo "should fail" >&2
  exit 1
fi
case $out in *"check the spec rules first"*) ;; *) echo "usage should say so: $out" >&2; exit 1 ;; esac

echo "rules.sh treats a hyphen like a space, so named-by finds what named by finds"
out=$(run named-by)
case $out in *"names.key"*) ;; *) echo "named-by should find names.key: $out" >&2; exit 1 ;; esac
[ "$out" = "$(run named by)" ] || { echo "named-by and named by differ" >&2; exit 1; }

echo "rules.sh prints no traceback when its output is cut short by head"
mkdir -p "$dir/big/cases"
{
  echo "# Big"
  i=0
  while [ "$i" -lt 3000 ]; do
    printf '**[big.rule%s]** The item has a long text so the output is large enough to fill a pipe. Second sentence.\n\n' "$i"
    i=$((i + 1))
  done
} > "$dir/big/semantics.md"
err=$( { RULES_SPEC_DIR=$dir/big sh "$script" item | head -n 1 > /dev/null; } 2>&1 )
[ -z "$err" ] || { echo "unexpected stderr: $err" >&2; exit 1; }

echo "rules.sh runs from another folder against the real spec and finds problems.all_said with a case"
cd "$dir"
out=$(sh "$script" all said)
case $out in *"problems.all_said"*) ;; *) echo "problems.all_said missing: $out" >&2; exit 1 ;; esac
cited=$(printf '%s\n' "$out" | grep -A8 'problems.all_said' | grep 'cited by' | head -1)
case $cited in
  *"cited by 0 "* | "") echo "no case cites problems.all_said: $out" >&2; exit 1 ;;
esac
