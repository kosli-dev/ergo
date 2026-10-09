import glob, json, re, sys

docs = {f: open(f).read() for f in ["spec/semantics.md", "spec/syntax.md"]}
rules = {}
for f, text in docs.items():
    for name in re.findall(r"\*\*\[([a-z_.]+)\]\*\*", text):
        if name in rules:
            sys.exit(f"rule {name} is in both {rules[name]} and {f}")
        rules[name] = f
cited = set()
unknown = []
for f in sorted(glob.glob("spec/cases/*/cases.json")):
    for group in json.load(open(f)):
        for case in group["cases"]:
            for name in case["rules"]:
                cited.add(name)
                if name not in rules:
                    unknown.append(f"{f}: {group['description']} / {case['description']} cites {name}")
for line in unknown:
    print(line)
for name in sorted(set(rules) - cited):
    print(f"{rules[name]}: no case cites {name}")
sys.exit(1 if unknown else 0)
