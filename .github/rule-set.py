import re
import sys

START = re.compile(r"^(?:default )?([A-Za-z_][A-Za-z0-9_]*)")


def split(text):
    lines = text.split("\n")
    header, rules, current = [], [], None
    for line in lines:
        m = START.match(line)
        if m and m.group(1) not in ("package", "import", "else"):
            current = [line]
            rules.append(current)
        elif current is None:
            header.append(line)
        else:
            current.append(line)
    tidy = lambda block: "\n".join(block).rstrip("\n")
    return tidy(header), sorted(tidy(r) for r in rules)


def main(a, b):
    header_a, rules_a = split(open(a).read())
    header_b, rules_b = split(open(b).read())
    ok = True
    if header_a != header_b:
        print(f"The lines above the first rule differ:\n--- {a}\n{header_a}\n--- {b}\n{header_b}")
        ok = False
    only_a = sorted(set(rules_a) - set(rules_b))
    only_b = sorted(set(rules_b) - set(rules_a))
    for path, only in ((a, only_a), (b, only_b)):
        for rule in only:
            print(f"Only in {path}:\n{rule}\n")
    if rules_a != rules_b and not only_a and not only_b:
        print("The same rules appear a different number of times.")
    ok = ok and rules_a == rules_b
    print(f"{len(rules_a)} rules in {a}, {len(rules_b)} in {b}: {'same' if ok else 'different'}")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: rule-set.py OLD.rego NEW.rego")
    sys.exit(main(sys.argv[1], sys.argv[2]))
