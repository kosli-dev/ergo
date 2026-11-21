#!/bin/sh
set -eu
if [ $# -ne 2 ]; then
  echo "usage: body-facts.sh PR_FACTS_OUTPUT PAIRS_FACTS_OUTPUT" >&2
  exit 2
fi
reports_file=$1
pairs_file=$2
work=$(mktemp -d)
trap '/bin/rm -rf "$work"' EXIT

if [ -n "${BODY_FACTS_BODY_FILE:-}" ]; then
  tr -d '\r' < "$BODY_FACTS_BODY_FILE" > "$work/body"
else
  printf '%s\n' "${BODY_FACTS_BODY:-}" | tr -d '\r' > "$work/body"
fi

count_from() {
  if [ ! -f "$1" ]; then
    echo unknown
    return
  fi
  sed -n "$2" "$1" | head -n 1
}

cargo_line=
passed_now_fail=
if [ -f "$reports_file" ]; then
  cargo_line=$(grep -m 1 '^cargo test exited with' "$reports_file" || true)
  passed_now_fail=$(sed -n 's/^CASES THAT PASSED ON .* AND FAIL OR ARE GONE NOW: \([0-9][0-9]*\)$/\1/p' "$reports_file" | head -n 1)
fi

reports=$(count_from "$reports_file" 's/^\([0-9][0-9]*\) case reports\{0,1\} changed between.*/\1/p')
if [ -z "$reports" ]; then
  if [ -n "$cargo_line" ]; then
    reports=unknown
  elif [ -f "$reports_file" ] && grep -q '^No case report changed between' "$reports_file"; then
    reports=0
  else
    reports=unknown
  fi
fi

pairs=$(count_from "$pairs_file" "s/^Rust output changed on \([0-9][0-9]*\) pairs\{0,1\} between.*/\1/p")
if [ -z "$pairs" ]; then
  if [ -f "$pairs_file" ] && grep -q -e "^No pair's Rust output changed between" -e '^No file under' "$pairs_file"; then
    pairs=0
  else
    pairs=unknown
  fi
fi

away=0
if [ -f "$pairs_file" ]; then
  away=$(sed -n 's/^PAIRS THAT MOVED AWAY FROM REGO OR FROM THEIR WANT: \([0-9][0-9]*\)$/\1/p' "$pairs_file" | head -n 1)
  away=${away:-0}
fi

plural() {
  if [ "$1" = 1 ]; then echo "$2"; else echo "$3"; fi
}

changed=no
[ "$reports" != unknown ] && [ "$reports" != 0 ] && changed=yes
[ "$pairs" != unknown ] && [ "$pairs" != 0 ] && changed=yes

has_line=no
awk '
  /^(```|~~~)/ { infence = !infence; next }
  !infence { print }
' "$work/body" > "$work/body-open"
if sed -n 's/^Changes the report://p' "$work/body-open" | sed 's/<!--[^>]*-->//g' | grep -q '[^[:space:]]'; then
  has_line=yes
fi

snapshot='(the body is read at the last push: push or re-run after editing it)'

echo "## Report facts for the pull request body"
echo
echo "- Rust case reports changed: $reports"
echo "- Pairs whose Rust output changed: $pairs, of them moved away from Rego or their want: $away"
if [ -n "$passed_now_fail" ]; then
  echo "- Cases that passed and now fail or are gone: $passed_now_fail"
fi
if [ -n "$cargo_line" ]; then
  echo
  echo "WARNING: $cargo_line So the report counts could not be read because cargo failed $snapshot."
fi

if [ "$changed" = yes ]; then
  parts=
  if [ "$reports" != unknown ] && [ "$reports" != 0 ]; then
    parts="$reports Rust case $(plural "$reports" report reports) changed"
  fi
  if [ "$pairs" != unknown ] && [ "$pairs" != 0 ]; then
    pair_part="Rust output changed on $pairs $(plural "$pairs" pair pairs)"
    if [ "$away" != 0 ]; then
      pair_part="$pair_part ($away moved away from Rego or its want)"
    fi
    parts="${parts:+$parts, }$pair_part"
  fi
  echo
  echo "To paste into the body:"
  echo
  echo '```'
  echo "Changes the report: $parts."
  echo '```'
fi

if [ "$changed" = yes ] && [ "$has_line" = no ]; then
  echo
  echo 'WARNING: reports or pairs changed, and the body has no line starting with `Changes the report:`. '"$snapshot"
fi
if [ "$changed" = no ] && [ "$has_line" = yes ] && [ "$reports" != unknown ] && [ "$pairs" != unknown ]; then
  echo
  echo 'NOTE: the body has a line starting with `Changes the report:`, and no report or pair changed.'
fi
