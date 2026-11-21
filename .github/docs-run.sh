#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
opa=${DOCS_RUN_OPA:-opa}
ergo=${DOCS_RUN_ERGO_REGO:-$here/dist/ergo.rego}
release=${DOCS_RUN_RELEASE_ERGO_REGO:-}
require_release=${DOCS_RUN_REQUIRE_RELEASE:-0}
export DOCS_RUN_OPA="$opa"
release_note() {
  if [ "$command_use" = release ] && [ -n "${DOCS_RUN_RELEASE_NOTE:-}" ]; then
    echo "$DOCS_RUN_RELEASE_NOTE" >&2
  fi
}

if [ "$#" -eq 0 ]; then
  cd "$here"
  set -- OPA.md REFERENCE.md README.md CLI.md
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
    function emit() {
      close(out)
      printf "%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", out, file, mline, names, role, path, ergo, normalise, use >> (work "/index")
    }
    function finish() {
      emit()
      open = 0
    }
    {
      sub(/\r$/, "")
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
        runcmd = ""
        if (match(line, /run=`[^`]*`/)) {
          runcmd = substr(line, RSTART + 5, RLENGTH - 6)
          line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
        }
        sub(/[ \t]+$/, "", line)
        if (index(line, "`") > 0) {
          fail(NR, "run= cannot contain a backtick")
        }
        count = split(line, parts, / +/)
        names = parts[1]
        role = "-"
        path = "-"
        ergo = "-"
        normalise = "-"
        use = "-"
        for (i = 2; i <= count; i++) {
          if (parts[i] == "") continue
          eq = index(parts[i], "=")
          if (eq == 0) {
            fail(NR, "the ergo-run attribute " parts[i] " has no =")
            role = "bad-attribute"
            continue
          }
          key = substr(parts[i], 1, eq - 1)
          value = substr(parts[i], eq + 1)
          if (key == "role") role = value
          else if (key == "path") path = value
          else if (key == "ergo") ergo = value
          else if (key == "normalise") normalise = value
          else if (key == "use") use = value
          else if (key == "run") {
            fail(NR, "the run attribute is written run=`COMMAND`")
            role = "bad-attribute"
          }
          else fail(NR, "unknown ergo-run attribute " key)
        }
        mline = NR
        markers++
        if (runcmd != "") {
          if (role != "command") {
            fail(NR, "a run attribute goes on a command marker")
          } else {
            out = work "/block." k "." (++n)
            print runcmd > out
            emit()
          }
        } else {
          pending = 1
        }
      } else if (tolower($0) ~ /ergo[-_ ]?run/) {
        stray[++nstray] = NR
      }
    }
    END {
      if (pending) fail(mline, "the ergo-run marker is not followed by a code block")
      if (open) fail(mline, "the code block after the ergo-run marker is never closed")
      if (markers == 0) {
        for (i = 1; i <= nstray; i++) fail(stray[i], "this ergo-run text is not a marker")
      }
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
  files=$(printf '%s\n' "$rows" | awk -F'\t' '$6 == "command" { print $3 }' | sort -u)
  if [ "$(printf '%s\n' "$files" | wc -l)" -gt 1 ]; then
    echo "group $name is used in more than one file: $(printf '%s' "$files" | tr '\n' ' ')" >&2
    status=1
    continue
  fi
  where=$(printf '%s\n' "$rows" | head -n 1 | cut -f3,4 | tr "$tab" ':')
  bad=0
  command_row=
  output_row=
  ncommand=0
  noutput=0
  run="$work/run.$gi"
  mkdir -p "$run"
  while IFS="$tab" read -r _ block bfile bline _ role path attr_ergo normalise use; do
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
        command_row="$block${tab}$attr_ergo${tab}$bfile:$bline${tab}$use"
        case $use in
          - | release) ;;
          *)
            echo "$bfile:$bline: group $name: unknown use=$use" >&2
            bad=1
            ;;
        esac
        ;;
      output)
        noutput=$((noutput + 1))
        output_row="$block${tab}$bfile:$bline"
        ;;
      bad-attribute)
        bad=1
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
  command_use=$(printf '%s' "$command_row" | cut -f4)
  group_ergo=$ergo
  if [ "$command_use" = release ]; then
    if [ -z "$release" ]; then
      if [ "$require_release" = 1 ]; then
        echo "group $name: the command at $command_at needs the latest release's ergo.rego, and DOCS_RUN_RELEASE_ERGO_REGO is not set" >&2
        status=1
      else
        echo "skip group $name ($command_at): DOCS_RUN_RELEASE_ERGO_REGO is not set, so it is not checked against the latest release"
      fi
      continue
    fi
    if [ ! -f "$release" ]; then
      echo "group $name: the release file $release does not exist" >&2
      status=1
      continue
    fi
    group_ergo=$release
  fi
  output_block=$(printf '%s' "$output_row" | cut -f1)
  output_at=$(printf '%s' "$output_row" | cut -f2)
  [ "$command_ergo" != - ] || command_ergo=ergo.rego
  mkdir -p "$run/$(dirname "$command_ergo")"
  cp -f "$group_ergo" "$run/$command_ergo"
  if (cd "$run" && sh -c 'opa() { command "$DOCS_RUN_OPA" "$@"; }; . "$1"' sh "$command_block" > "$work/actual.$gi" 2> "$work/stderr.$gi"); then
    :
  else
    echo "group $name: the command at $command_at failed" >&2
    cat "$work/stderr.$gi" >&2
    release_note
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
    release_note
    status=1
  fi
done < "$work/groups"

exit $status
