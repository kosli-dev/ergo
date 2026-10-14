import glob, json, re, sys

docs = {f: open(f).read() for f in ["spec/semantics.md", "spec/syntax.md", "spec/sentences.md"]}
rules = {}
for f, text in docs.items():
    for name in re.findall(r"\*\*\[([a-z_.]+)\]\*\*", text):
        if name in rules:
            sys.exit(f"rule {name} is in both {rules[name]} and {f}")
        rules[name] = f
cited = set()
problems = []
for f in sorted(glob.glob("spec/cases/*/cases.json")):
    for group in json.load(open(f)):
        for case in group["cases"]:
            for name in case["rules"]:
                cited.add(name)
                if name not in rules:
                    problems.append(f"{f}: {group['description']} / {case['description']} cites {name}")
section = open("spec/OPEN.md").read().split("\n## Rules without cases\n", 1)[1].split("\n## ", 1)[0]
waiting = set(re.findall(r"^- `([a-z_.]+)`$", section, re.M))
problems += [f"{rules[name]}: no case cites {name}" for name in sorted(set(rules) - cited - waiting)]
problems += [f"spec/OPEN.md: {name} is listed without cases, but it isn't a rule" for name in sorted(waiting - set(rules))]
problems += [f"spec/OPEN.md: {name} is listed without cases, but a case cites it" for name in sorted(waiting & cited)]
for line in problems:
    print(line)
sys.exit(1 if problems else 0)
