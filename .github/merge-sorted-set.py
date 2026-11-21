import sys


def read(path):
    with open(path) as f:
        return {line.rstrip("\n") for line in f if line.strip()}


base, ours, theirs = (read(path) for path in sys.argv[1:4])
removed = (base - ours) | (base - theirs)
added = (ours - base) | (theirs - base)
merged = sorted((base - removed) | added)
with open(sys.argv[2], "w") as f:
    f.write("".join(line + "\n" for line in merged))
