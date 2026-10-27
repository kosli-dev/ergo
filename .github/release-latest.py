import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".github")
release = root / "workflows/release.yml"
problems = []

text = release.read_text()
jobs = dict(re.findall(r"^  ([\w-]+):\n((?:(?:    .*)?\n)*)", text.split("\njobs:\n", 1)[1], re.M))


def creates(body):
    return re.findall(r"gh release create(?:[^\n]*\\\n)*[^\n]*", body)


rego = jobs.get("release-rego")
if rego is None:
    problems.append(f"{release} has no release-rego job")
else:
    if not creates(rego):
        problems.append("release-rego creates no release")
    for command in creates(rego):
        flags = re.findall(r'"?\$latest"?|--latest(?:=\w+)?', command)
        if flags != ['"$latest"']:
            problems.append(f"release-rego must create its release with \"$latest\" only, and has {', '.join(flags) or 'no --latest'}")
    for line in ('highest=$(git tag --list \'rego-v*\' | grep -E \'^rego-v[0-9]+\\.[0-9]+\\.[0-9]+$\' | sort -V | tail -n 1)',
                 'if [ "$TAG" = "$highest" ]; then', "latest=--latest", "else", "latest=--latest=false"):
        if not re.search(r"^\s*" + re.escape(line) + r"\s*$", rego, re.M):
            problems.append(f"release-rego must mark its release as the latest only when it's the highest rego-v version, and has no line {line}")

spec = jobs.get("release-spec")
if spec is None:
    problems.append(f"{release} has no release-spec job")
else:
    if not creates(spec):
        problems.append("release-spec creates no release")
    for command in creates(spec):
        flags = re.findall(r'"?\$latest"?|--latest(?:=\w+)?', command)
        if flags != ["--latest=false"]:
            problems.append(f"release-spec must create its release with --latest=false only, and has {', '.join(flags) or 'no --latest'}")

for job, body in jobs.items():
    if job not in ("release-rego", "release-spec") and creates(body):
        problems.append(f"{job} creates a release, and only release-rego and release-spec may")

for path in sorted(p for p in root.rglob("*") if p.is_file() and p.suffix in (".yml", ".yaml", ".sh", ".py", ".cjs", ".js") and p.name not in ("release-latest.py", "release-latest_test.sh")):
    body = path.read_text()
    if path != release and creates(body):
        problems.append(f"{path} creates a release, and only release.yml may")
    if re.search(r"gh release edit[^\n]*--latest", body) or "make_latest" in body:
        problems.append(f"{path} changes which release is the latest, and only release.yml's release-rego may")

if problems:
    print("\n".join(problems))
    raise SystemExit(1)
print("Only the highest ergo.rego release can be the latest release, so releases/latest/download/ergo.rego keeps working")
