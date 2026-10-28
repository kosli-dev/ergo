import json
import re
import sys

rows = [l for l in open("spec/sentences-corpus.md", encoding="utf-8") if l.startswith("| `")]
lines = []
for row in rows:
    cells = [c.strip() for c in row.strip().strip("|").split(" | ")]
    if len(cells) < 3:
        continue
    for part in cells[2].split("<br>"):
        m = re.match(r"^`(.*)`$", part.strip())
        if not m or m.group(1) == "assert:":
            continue
        text = m.group(1).replace("\\|", "|")
        if text.startswith("for: "):
            text = text[5:]
        elif text.startswith("assert: "):
            text = text[8:]
        elif text.startswith("  - "):
            text = text[4:]
        lines.append(text)

want = json.dumps({"sentence_corpus": lines}, indent=0, ensure_ascii=False) + "\n"
path = "spec/sentences-corpus.json"
if "--check" in sys.argv:
    if open(path, encoding="utf-8").read() != want:
        sys.exit(f"{path} is out of date: run python3 spec/sentences_corpus.py")
else:
    open(path, "w", encoding="utf-8").write(want)
