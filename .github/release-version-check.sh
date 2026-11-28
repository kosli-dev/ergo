#!/bin/bash
set -euo pipefail
wanted=${1:?usage: release-version-check.sh VERSION, with the output of ergo --version on stdin}
IFS= read -r says || true
says=${says%$'\r'}
case $says in
  "ergo "*) ;;
  *)
    echo "ergo --version says \"$says\", and should start with \"ergo \"" >&2
    exit 1
    ;;
esac
rest=${says#ergo }
word=${rest%% *}
if [ "$word" != "$wanted" ]; then
  echo "ergo --version says \"$says\", and its version should be \"$wanted\"" >&2
  exit 1
fi
