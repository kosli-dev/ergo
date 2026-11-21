#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
opa=${DOCS_RUN_OPA:-opa}
ergo=${DOCS_RUN_ERGO_REGO:-$here/dist/ergo.rego}
export DOCS_RUN_OPA="$opa"

if [ "$#" -eq 0 ]; then
  set -- "$here/OPA.md" "$here/REFERENCE.md" "$here/README.md" "$here/CLI.md"
fi

tab=$(printf '\t')
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/index"
: > "$work/errors"

k=0
for file in "$@"; do
  k=$((k + 1))
  awk -v file="$file" -v work="$work" -v k="$k" '
    function fail(line, text) {
      print file ":" line ": " text >> (work "/errors")
    }
    function finish() {
      close(out)
      printf "%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n", out, file, mline, names, role, path, ergo, normalise >> (work "/index")
      open = 0
    }
    {
      if (open) {
        if ($0 ~ /^```/) {
          finish()
        } else {
          print $0 >> out
        }
        next
      }
      if (pending && $0 ~ /^[ \t]*$/) next
      if (pending) {
        pending = 0
        if ($0 ~ /^```/) {
          out = work "/block." k "." (++n)
          printf "" > out
          open = 1
          next
        }
        fail(mline, "the ergo-run marker is not followed by a code block")
      }
      if ($0 ~ /^<!-- ergo-run: .* -->[ \t]*$/) {
        line = $0
        sub(/^<!-- ergo-run: /, "", line)
        sub(/[ \t]*-->[ \t]*$/, "", line)
        count = split(line, parts, / +/)
        names = parts[1]
        role = "-"
        path = "-"
        ergo = "-"
        normalise = "-"
        for (i = 2; i <= count; i++) {
          eq = index(parts[i], "=")
          key = substr(parts[i], 1, eq - 1)
          value = substr(parts[i], eq + 1)
          if (key == "role") role = value
          else if (key == "path") path = value
          else if (key == "ergo") ergo = value
          else if (key == "normalise") normalise = value
          else fail(NR, "unknown ergo-run attribute " key)
        }
        mline = NR
        pending = 1
      }
    }
    END {
      if (pending) fail(mline, "the ergo-run marker is not followed by a code block")
      if (open) fail(mline, "the code block after the ergo-run marker is never closed")
    }
  ' "$file"
done

if [ ! -s "$work/index" ] && [ ! -s "$work/errors" ]; then
  echo "docs-run.sh: no marked blocks in $*"
  exit 0
fi

status=0
if [ -s "$work/errors" ]; then
  cat "$work/errors" >&2
  status=1
fi

awk -F'\t' '{ n = split($4, a, ","); for (i = 1; i <= n; i++) print a[i] "\t" $0 }' "$work/index" | sort -s -t "$tab" -k1,1 > "$work/by-name"
cut -f1 "$work/by-name" | uniq > "$work/groups"

spec=
if [ -f "$ergo" ]; then
  spec=$(sed -n 's/^_spec := "\(.*\)"$/\1/p' "$ergo")
fi

gi=0
while IFS= read -r name; do
  gi=$((gi + 1))
  rows=$(awk -F'\t' -v n="$name" '$1 == n' "$work/by-name")
  where=$(printf '%s\n' "$rows" | head -n 1 | cut -f3,4 | tr "$tab" ':')
  bad=0
  command_row=
  output_row=
  ncommand=0
  noutput=0
  run="$work/run.$gi"
  mkdir -p "$run"
  while IFS="$tab" read -r _ block bfile bline _ role path attr_ergo normalise; do
    [ -n "$block" ] || continue
    case $role in
      file)
        case $path in
          - | /* | ../* | */../* | */.. | ..)
            echo "$bfile:$bline: group $name: a file block needs a path inside the folder, not '$path'" >&2
            bad=1
            continue
            ;;
        esac
        mkdir -p "$run/$(dirname "$path")"
        if [ "$normalise" = ergo_spec ]; then
          sed "s/^ergo_spec: v[0-9][^ ]*\$/ergo_spec: $spec/" "$block" > "$run/$path"
        elif [ "$normalise" != - ]; then
          echo "$bfile:$bline: group $name: unknown normalise=$normalise" >&2
          bad=1
        else
          cp -f "$block" "$run/$path"
        fi
        ;;
      command)
        ncommand=$((ncommand + 1))
        command_row="$block${tab}$attr_ergo${tab}$bfile:$bline"
        ;;
      output)
        noutput=$((noutput + 1))
        output_row="$block${tab}$bfile:$bline"
        ;;
      *)
        echo "$bfile:$bline: group $name: unknown role '$role'" >&2
        bad=1
        ;;
    esac
  done <<ROWS
$rows
ROWS
  if [ "$ncommand" -ne 1 ]; then
    echo "$where: group $name needs one command block, and has $ncommand" >&2
    bad=1
  fi
  if [ "$noutput" -ne 1 ]; then
    echo "$where: group $name needs one output block, and has $noutput" >&2
    bad=1
  fi
  if [ "$bad" -ne 0 ]; then
    status=1
    continue
  fi
  command_block=$(printf '%s' "$command_row" | cut -f1)
  command_ergo=$(printf '%s' "$command_row" | cut -f2)
  command_at=$(printf '%s' "$command_row" | cut -f3)
  output_block=$(printf '%s' "$output_row" | cut -f1)
  output_at=$(printf '%s' "$output_row" | cut -f2)
  [ "$command_ergo" != - ] || command_ergo=ergo.rego
  mkdir -p "$run/$(dirname "$command_ergo")"
  cp -f "$ergo" "$run/$command_ergo"
  if (cd "$run" && sh -c 'opa() { "$DOCS_RUN_OPA" "$@"; }; . "$1"' sh "$command_block" > "$work/actual.$gi" 2> "$work/stderr.$gi"); then
    :
  else
    echo "group $name: the command at $command_at failed" >&2
    cat "$work/stderr.$gi" >&2
    status=1
    continue
  fi
  printf '%s\n' "$(cat "$output_block")" > "$work/expected.$gi"
  printf '%s\n' "$(cat "$work/actual.$gi")" > "$work/actual-norm.$gi"
  if diff -u "$work/expected.$gi" "$work/actual-norm.$gi" > "$work/diff.$gi"; then
    echo "ok   group $name ($command_at, output at $output_at)"
  else
    echo "group $name: the output at $output_at is not what the command at $command_at prints (- is the docs, + is the run):" >&2
    tail -n +3 "$work/diff.$gi" >&2
    status=1
  fi
done < "$work/groups"

exit $status
