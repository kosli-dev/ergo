import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".github/workflows/release.yml")
text = path.read_text()
jobs = dict(re.findall(r"^  ([\w-]+):\n((?:(?:    .*)?\n)*)", text.split("\njobs:\n", 1)[1], re.M))
want = {"release-rego": "--latest", "release-spec": "--latest=false"}
problems = []
for job, body in jobs.items():
    creates = re.findall(r"gh release create(?:[^\n]*\\\n)*[^\n]*", body)
    flags = [set(re.findall(r"--latest(?:=\w+)?", c)) for c in creates]
    if job in want:
        if not creates:
            problems.append(f"{job} creates no release")
        for f in flags:
            if f != {want[job]}:
                problems.append(f"{job} must create its release with {want[job]} only, and has {', '.join(sorted(f)) or 'no --latest'}")
    elif creates:
        problems.append(f"{job} creates a release, and only release-rego and release-spec may")
for job in want:
    if job not in jobs:
        problems.append(f"{path} has no {job} job")
if problems:
    print("\n".join(problems))
    raise SystemExit(1)
print("Only ergo.rego releases can be the latest release, so releases/latest/download/ergo.rego keeps working")
