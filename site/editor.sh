#!/bin/sh
set -eu
[ $# -eq 2 ] || { echo "usage: site/editor.sh <editor.html> <public folder>" >&2; exit 2; }
[ -f "$1" ] || { echo "$1 isn't a file" >&2; exit 1; }
mkdir -p "$2/editor"
python3 - "$1" "$2/editor/index.html" <<'PY'
import re
import sys

page = open(sys.argv[1], encoding="utf-8").read()
page, n = re.subn(r"<head(\s[^>]*)?>", lambda m: m.group(0) + '<meta name="robots" content="noindex">', page, count=1, flags=re.I)
if n == 0:
    sys.exit(f"{sys.argv[1]} has no <head>")
open(sys.argv[2], "w", encoding="utf-8").write(page)
PY
