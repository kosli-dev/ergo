#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${MESSAGE_CUTS_ROOT:-$(cd "$here/.." && pwd)}
against=
case ${1:-} in
  "") ;;
  --against)
    [ -n "${2:-}" ] || { echo "usage: message-cuts.sh [--against REF]" >&2; exit 2; }
    against=$2
    ;;
  *)
    echo "usage: message-cuts.sh [--against REF]" >&2
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

scan() {
  (
    cd "$1"
    out=$2
    find engines/rust/engine/src -name '*.rs' ! -name tests.rs ! -path '*/tests/*' 2>/dev/null | LC_ALL=C sort > "$out.rust.files"
    find engines/rego/src -name '*.rego' 2>/dev/null | LC_ALL=C sort > "$out.rego.files"
    tab=$(printf '\t')
    : > "$out.counts"
    : > "$out.lines"
    while IFS=$tab read -r name lang mode pattern; do
      flag=-F
      [ "$mode" = E ] && flag=-E
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        n=$(grep -c $flag -e "$pattern" "$file" || true)
        [ "$n" != 0 ] || continue
        echo "$name $file $n" >> "$out.counts"
        grep -n $flag -e "$pattern" "$file" | sed "s|^|$name $file:|" >> "$out.lines"
      done < "$out.$lang.files"
    done < "$work/patterns"
    awk '{ t[$1] += $3; total += $3 } END { for (k in t) print k, t[k]; print "total", total }' "$out.counts" | LC_ALL=C sort > "$out.totals"
    : > "$out.full"
    for name in $(cut -f1 "$work/patterns"); do
      n=$(awk -v k="$name" '$1 == k { print $2 }' "$out.totals")
      echo "$name ${n:-0}" >> "$out.full"
    done
    echo "total $(awk '$1 == "total" { print $2 }' "$out.totals")" >> "$out.full"
  )
}

scan "$root" "$work/head"

echo "Places where engine code cuts a message as text, per pattern and file:"
LC_ALL=C sort "$work/head.counts"
echo
echo "Per pattern:"
awk '$1 == "total" { print; next } { print $1, "total", $2 }' "$work/head.full"

[ -n "$against" ] || exit 0

mkdir "$work/base"
git -C "$root" archive "$against" engines/rust/engine/src engines/rego/src | tar -x -C "$work/base" || {
  echo "message-cuts.sh: cannot read $against" >&2
  exit 1
}
scan "$work/base" "$work/base"

allow=$root/.github/message-cuts.allow
allowed() {
  [ -f "$allow" ] && grep -qx -e "$1" "$allow"
}

failed=0
extra=0
while read -r name now; do
  was=$(awk -v k="$name" '$1 == k { print $2 }' "$work/base.full")
  was=${was:-0}
  [ "$name" = total ] && continue
  [ "$now" -gt "$was" ] || continue
  if allowed "$name"; then
    extra=$((extra + now - was))
    continue
  fi
  failed=1
  echo
  echo "$name went from $was to $now. Lines added:"
  sed 's/^\([^ ]*\) \([^:]*\):\([0-9]*\):/\1\t\2\t\3\t/' "$work/base.lines" | awk -F'\t' -v k="$name" '$1 == k { seen[$2 "\t" $4]++ }
    END { for (x in seen) print x "\t" seen[x] }' | LC_ALL=C sort > "$work/base.keys"
  sed 's/^\([^ ]*\) \([^:]*\):\([0-9]*\):/\1\t\2\t\3\t/' "$work/head.lines" | awk -F'\t' -v k="$name" -v keys="$work/base.keys" '
    BEGIN { while ((getline l < keys) > 0) { split(l, f, "\t"); left[f[1] "\t" f[2]] = f[3] } }
    $1 == k { key = $2 "\t" $4; if (left[key] > 0) left[key]--; else print "  " $2 ":" $3 ": " $4 }'
done < "$work/head.full"

was=$(awk '$1 == "total" { print $2 }' "$work/base.full")
now=$(awk '$1 == "total" { print $2 }' "$work/head.full")
if [ $((now - extra)) -gt "$was" ]; then
  failed=1
  echo
  echo "total went from $was to $now"
fi

if [ "$failed" = 1 ]; then
  echo >&2
  echo "FAILED: message-cuts.sh found more places that cut a message as text than $against has. Carry the parts instead, or, when a cut is truly needed, list its pattern in .github/message-cuts.allow and say why in the pull request." >&2
  exit 1
fi
