#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${MESSAGE_CUTS_ROOT:-$(cd "$here/.." && pwd)}
baseline=${MESSAGE_CUTS_BASELINE:-$here/message-cuts.baseline}
update=no
case ${1:-} in
  "") ;;
  --update) update=yes ;;
  *)
    echo "usage: message-cuts.sh [--update]" >&2
    exit 2
    ;;
esac
work=$(mktemp -d)
trap '/bin/rm -rf "$work"' EXIT
cd "$root"

pat() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$work/patterns"
}

pat rust-split-semicolon rust F '.split("; ")'
pat rust-split-outside-quotes rust F 'split_outside_quotes('
pat rust-split-and rust F '.split(", and ")'
pat rust-split-of rust F '.split_once(" of ")'
pat rust-split-of-the-subject rust F '.split_once(" of the subject")'
pat rust-find-of rust F '.find(" of ")'
pat rust-split-marker rust F '.split_once(MARK)'
pat rust-split-bracket rust E 'split_once\((.\[.|"\[\]"|.\].)\)'
pat rust-item-prefix-starts rust F 'starts_with("item ")'
pat rust-item-prefix-strips rust F 'strip_prefix("item ")'
pat rust-subject-prefix-strips rust F 'strip_prefix("the subject ")'
pat rust-count-or-sum-prefix rust E 'starts_with\("(count|sum) of "\)'
pat rust-ran-said rust F 'ran_said('
pat rust-free-mark-removed rust F '.replace(FREE'
pat rego-split-semicolon rego E 'split\([^)]*"; "'
pat rego-split-and rego E 'split\([^)]*", and "'
pat rego-quote-split rego E '_m_(quote|top)_split\('
pat rego-cut-helpers rego E '_m_cuts\(|_for_cut\('
pat rego-item-prefix rego E '(startswith|trim_prefix)\([^)]*"item '
pat rego-subject-prefix rego E '(startswith|trim_prefix)\([^)]*"the subject '
pat rego-indexof-of rego E 'indexof\([^)]*" of "'
pat rego-indexof-and rego E 'indexof\(.*", and "'

find engines/rust/engine/src -name '*.rs' ! -name tests.rs ! -path '*/tests/*' 2>/dev/null | LC_ALL=C sort > "$work/rust.files"
find engines/rego/src -name '*.rego' 2>/dev/null | LC_ALL=C sort > "$work/rego.files"

tab=$(printf '\t')
: > "$work/counts"
: > "$work/lines"
while IFS=$tab read -r name lang mode pattern; do
  flag=-F
  [ "$mode" = E ] && flag=-E
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    n=$(grep -c $flag -e "$pattern" "$file" || true)
    [ "$n" != 0 ] || continue
    echo "$name $file $n" >> "$work/counts"
    grep -n $flag -e "$pattern" "$file" | sed "s|^|$name $file:|" >> "$work/lines"
  done < "$work/$lang.files"
done < "$work/patterns"

awk '{ t[$1] += $3; total += $3 } END { for (k in t) print k, t[k]; print "total", total }' "$work/counts" | LC_ALL=C sort > "$work/totals"
names=$(cut -f1 "$work/patterns")
: > "$work/full"
for name in $names; do
  n=$(awk -v k="$name" '$1 == k { print $2 }' "$work/totals")
  echo "$name ${n:-0}" >> "$work/full"
done
echo "total $(awk '$1 == "total" { print $2 }' "$work/totals")" >> "$work/full"

echo "Places where engine code cuts a message as text, per pattern and file:"
LC_ALL=C sort "$work/counts"
echo
echo "Per pattern:"
awk '$1 == "total" { print; next } { print $1, "total", $2 }' "$work/full"

if [ "$update" = yes ]; then
  cp -f "$work/full" "$baseline"
  echo
  echo "Wrote $baseline."
  exit 0
fi

if [ ! -f "$baseline" ]; then
  echo "message-cuts.sh: no baseline at $baseline: run message-cuts.sh --update" >&2
  exit 1
fi

failed=0
lower=0
while read -r name now; do
  was=$(awk -v k="$name" '$1 == k { print $2 }' "$baseline")
  was=${was:-0}
  if [ "$now" -gt "$was" ]; then
    failed=1
    echo
    echo "$name went from $was to $now"
    if [ "$name" != total ]; then
      grep "^$name " "$work/lines" | head -n 5 | sed 's/^[^ ]* /  /'
    fi
  elif [ "$now" -lt "$was" ]; then
    lower=1
  fi
done < "$work/full"

if [ "$failed" = 1 ]; then
  echo >&2
  echo "FAILED: message-cuts.sh found more places that cut a message as text than the baseline allows. Carry the parts instead, or, when a cut is truly needed, say why in the pull request." >&2
  exit 1
fi
if [ "$lower" = 1 ]; then
  echo
  echo "lower than baseline, run message-cuts.sh --update"
fi
