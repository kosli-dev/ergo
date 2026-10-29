import glob, json, os, random, re, subprocess, sys, tempfile, time
from abnf.parser import ParseError, Rule

SEED = 231
GENERATED = {"check": 2500, "for-line": 300, "from-line": 300}
MUTATIONS_PER_SAMPLE = 1
RULES = {"check": "_sentence", "for-line": "_for_line", "from-line": "_from_line"}

NON_SYNTAX = [
    re.compile(p)
    for p in [
        r" is a word of the grammar: write \.",
        r" can't be an alias$",
        r" is given twice$",
        r"^if any can't go with some$",
        r"^unknown name ",
        r"^unknown alias ",
        r"^min above max$",
        r"^number out of range: ",
        r" can't be a list position$",
        r"^invalid pattern ",
        r'^"is not null" is written "exists"$',
        r'^"[^"]*" takes text$',
        r'^"[^"]*" takes a time or a number$',
        r'^"[^"]*" takes a number$',
        r"^\"[^\"]*\" after every or some would check each item of the last list",
        r'^"within" only compares numbers$',
        r'^"within" needs a number of 0 or more$',
        r'^"sorted by" reads a field of the item, not ',
        r"^it is the whole subject: ",
        r"^it can only start an assertion: ",
        r"^it can't name a key$",
    ]
]

LATER = re.compile(r" is compared with itself")
WHITE_SPACE = "\t\n\x0b\x0c\r \x85\xa0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000"
NOT_WHITE_SPACE = ["\ufeff", "\u200b", "\x1c"]
EDGED_EVERY = 5

VOCABULARY = ["x", "y", "items", "status", "a_b", "k-1", "_id", "Count", "env", "sha", "pr", "commits", "owner"]
GRAMMAR_WORDS = re.findall(
    r"`([a-z]+)`",
    re.search(r"^\*\*\[sentence\.words\]\*\* [^:]*: (.*?)\. Without", open("spec/syntax.md").read(), re.M).group(1),
)
ASCII_POOL = [chr(c) for c in range(0x20, 0x7F) if chr(c) != "`"]
OTHER_POOL = [0xE9, 0x65E5, 0x1F600, 0xFEFF, 0x2028, 0xA0]

EXTRA = [
    ("check", " x is 1"),
    ("check", "\tx is 1\n"),
    ("check", "\n\tx is 1 \r\n"),
    ("check", "\u3000x is 1\u2028"),
    ("check", "\ufeffx is 1"),
    ("check", "x is 1\u200b"),
    ("for-line", "\tevery xs as x\n"),
    ("from-line", "\n\tevery xs whose y is 1\t\n"),
    ("from-line", "\x85xs whose y is 1\xa0"),
    ("check", "x is 1 "),
    ("check", "x  is 1"),
    ("check", "x is  1"),
    ("check", "x is  not empty"),
    ("check", "x is not  empty"),
    ("check", "every x, if  any, is 1"),
    ("check", "x named  by y is 1"),
    ("check", "x\tis 1"),
    ("check", "x is\t1"),
    ("for-line", "every xs whose days elapsed from p to q is 1 as x"),
    ("for-line", "t[0] as i"),
    ("for-line", "t.u[1] as i"),
    ("for-line", "every t as x, t[0] as i"),
    ("for-line", "every t as x, t.u[1] as i"),
    ("check", "x is 1 plus days elapsed from p to q"),
    ("check", "every xs whose days elapsed from p to q is 1 is not empty"),
    ("check", 'x is "\\ud800"'),
    ("check", "x is '\\ud800'"),
    ("check", 'x is "\\udc00\\ud800"'),
    ("check", 'x is "﻿"'),
]


def load_grammar():
    text = re.sub(r";[^\n]*", "", open("spec/sentences.abnf").read())
    text = re.sub(r'"[^"]*"', lambda m: "%s" + m.group(0), text)
    handle = tempfile.NamedTemporaryFile("w", suffix=".abnf", delete=False)
    handle.write(text)
    handle.close()

    class Grammar(Rule):
        pass

    Grammar.from_file(handle.name)
    os.unlink(handle.name)
    return Grammar


class Generator:
    def __init__(self, grammar, seed):
        self.grammar = grammar
        self.rng = random.Random(seed)
        self.costs = {}
        self.limit = 12
        for name in RULES:
            self.cost(grammar(name))

    def cost(self, node):
        kind = type(node).__name__
        if kind == "Literal":
            return 1
        if kind == "Prose":
            return 1
        if kind == "Concatenation":
            return sum(self.cost(p) for p in node.parsers)
        if kind == "Alternation":
            return min(self.cost(p) for p in node.parsers)
        if kind == "Repetition":
            return node.repeat.min * self.cost(node.element)
        if kind == "Option":
            return 0
        name = node.name.casefold()
        if name not in self.costs:
            self.costs[name] = 10**9
            self.costs[name] = self.cost(node.definition)
        return self.costs[name]

    def char(self, low, high):
        pool = [c for c in ASCII_POOL if low <= ord(c) <= high]
        if self.rng.random() < 0.15:
            pool += [chr(c) for c in OTHER_POOL if low <= c <= high]
        return self.rng.choice(pool)

    def gen(self, node, depth=0):
        kind = type(node).__name__
        if kind == "Literal":
            if isinstance(node.value, tuple):
                return self.char(ord(node.value[0]), ord(node.value[1]))
            return node.value
        if kind == "Concatenation":
            return "".join(self.gen(p, depth) for p in node.parsers)
        if kind == "Alternation":
            parsers = node.parsers
            if depth > self.limit:
                best = min(self.cost(p) for p in parsers)
                parsers = [p for p in parsers if self.cost(p) == best]
            return self.gen(self.rng.choice(parsers), depth)
        if kind == "Repetition":
            low, high = node.repeat.min, node.repeat.max
            count = low
            chance = 0.5 if depth < self.limit / 2 else 0.2
            while depth <= self.limit and (high is None or count < high) and count < low + 3 and self.rng.random() < chance:
                count += 1
            return "".join(self.gen(node.element, depth) for _ in range(count))
        if kind == "Option":
            if depth > self.limit or self.rng.random() < 0.5:
                return ""
            return self.gen(node.alternation, depth)
        name = node.name.casefold()
        if name == "bare-key":
            return self.rng.choice(VOCABULARY)
        if name == "key" and self.rng.random() < 0.5:
            return self.rng.choice(VOCABULARY + GRAMMAR_WORDS)
        return self.gen(node.definition, depth + 1)


def has_surrogate_escape(text):
    return re.search(r"\\u[dD][89a-fA-F][0-9a-fA-F]{2}", text) is not None


def mutate(rng, text):
    words = text.split()
    kind = rng.choice(["drop_quote", "swap_words", "cut_end", "delete_char", "duplicate_word", "insert_punctuation", "replace_word", "uppercase_word", "bracket_pick"])
    if kind == "drop_quote":
        spots = [i for i, c in enumerate(text) if c in "\"'"]
        if not spots:
            return None
        i = rng.choice(spots)
        return text[:i] + text[i + 1 :]
    if kind == "swap_words":
        if len(words) < 2:
            return None
        i = rng.randrange(len(words) - 1)
        words[i], words[i + 1] = words[i + 1], words[i]
        return " ".join(words)
    if kind == "cut_end":
        if len(words) > 1 and rng.random() < 0.5:
            return " ".join(words[: rng.randrange(1, len(words))])
        return text[: rng.randrange(1, max(2, len(text)))]
    if kind == "delete_char":
        i = rng.randrange(len(text))
        return text[:i] + text[i + 1 :]
    if kind == "duplicate_word":
        i = rng.randrange(len(words))
        return " ".join(words[: i + 1] + words[i:])
    if kind == "insert_punctuation":
        i = rng.randrange(len(text) + 1)
        return text[:i] + rng.choice(",.[]'\"$-") + text[i:]
    if kind == "bracket_pick":
        options = []
        for m in re.finditer(r"\bitem +([1-9][0-9]*) +of +([^\s,]+)", text):
            options.append(text[: m.start()] + m.group(2) + "[" + str(int(m.group(1)) - 1) + "]" + text[m.end() :])
        for m in re.finditer(r"\bfirst +of +([^\s,]+)", text):
            options.append(text[: m.start()] + m.group(1) + "[0]" + text[m.end() :])
        for m in re.finditer(r"(?:^|, +)(every|some) +", text):
            options.append(text[: m.start(1)] + text[m.end() :])
        if not options:
            return None
        return rng.choice(options)
    if kind == "replace_word":
        i = rng.randrange(len(words))
        words[i] = rng.choice(GRAMMAR_WORDS + VOCABULARY)
        return " ".join(words)
    i = rng.randrange(len(words))
    words[i] = words[i].upper()
    return " ".join(words)


def padded(text):
    return text != text.strip()


def case_sentences():
    found = []

    def walk(value, key=None):
        if isinstance(value, dict):
            for k, v in value.items():
                walk(v, k)
        elif isinstance(value, list):
            for v in value:
                walk(v, key)
        elif isinstance(value, str):
            kind = {"assert": "check", "for": "for-line", "from": "from-line"}.get(key)
            if kind:
                found.append((kind, value))

    for path in sorted(glob.glob("spec/cases/*/cases.json")):
        for group in json.load(open(path)):
            policy = group.get("policy", {})
            walk(policy)
            requirements = policy.get("requirements")
            for requirement in requirements.values() if isinstance(requirements, dict) else []:
                checks = requirement.get("checks") if isinstance(requirement, dict) else None
                for check in checks.values() if isinstance(checks, dict) else []:
                    if isinstance(check, str):
                        found.append(("check", check))
    return found


def bare_word_keys(node):
    if node.name in ("first-key", "plain-right") and node.children and node.children[0].name == "bare-key":
        if node.children[0].value in GRAMMAR_WORDS:
            yield node.children[0].value
    for child in node.children:
        yield from bare_word_keys(child)


def abnf_accepts(grammar, rules, text):
    for rule in rules:
        try:
            tree = grammar(rule).parse_all(text.strip(WHITE_SPACE))
        except ParseError:
            continue
        if not any(bare_word_keys(tree)):
            return True
    return False


def is_syntax(problem):
    return not any(p.search(problem) for p in NON_SYNTAX)


PROBE = """package probe

read("check", text) := data.ergo._sentence(text)

read("for-line", text) := data.ergo._for_line(text)

read("from-line", text) := data.ergo._from_line(text)

out := [[{"kind": kind, "problems": object.get(read(kind, item.text), "problems", [])} | some kind in item.kinds] | some item in input.rows]
"""


def ergo_reads(samples):
    rows = [{"kinds": kinds, "text": text} for _, text, kinds in samples]
    probe_file = tempfile.NamedTemporaryFile("w", suffix=".rego", delete=False)
    probe_file.write(PROBE)
    probe_file.close()
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump({"rows": rows}, handle)
    handle.close()
    try:
        out = subprocess.run(
            ["opa", "eval", "--format", "json", "-d", "ergo.rego", "-d", probe_file.name, "--input", handle.name, "data.probe.out"],
            capture_output=True, text=True,
        )
    finally:
        os.unlink(handle.name)
        os.unlink(probe_file.name)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    result = json.loads(out.stdout)["result"][0]["expressions"][0]["value"]
    assert len(result) == len(rows)
    return result


def rust_reads(command, samples):
    rows = [{"kinds": kinds, "text": text} for _, text, kinds in samples]
    out = subprocess.run(command, shell=True, input=json.dumps({"rows": rows}), capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    try:
        result = json.loads(out.stdout)
    except ValueError as error:
        sys.exit(f"the Rust command did not print JSON: {error}")
    if not isinstance(result, list) or len(result) != len(rows):
        sys.exit(f"the Rust command answered {len(result) if isinstance(result, list) else 'something that is not a list'} rows for {len(rows)}")
    for row, answers in zip(rows, result):
        kinds = [a.get("kind") if isinstance(a, dict) else None for a in answers] if isinstance(answers, list) else None
        if kinds != row["kinds"]:
            sys.exit(f"the Rust command answered {json.dumps(kinds)} for {json.dumps(row['text'])}, which asked for {json.dumps(row['kinds'])}")
    return result


def rust_command(argv):
    if not argv:
        return None
    if len(argv) != 2 or argv[0] != "--rust":
        sys.exit("usage: check_grammar.py [--rust <command>]")
    if not argv[1].strip():
        sys.exit("--rust needs a command to run")
    return argv[1]


def main():
    command = rust_command(sys.argv[1:])
    started = time.time()
    grammar = load_grammar()
    generator = Generator(grammar, SEED)
    rng = random.Random(SEED + 1)

    samples = []
    seen = set()

    def add(origin, kind, text, kinds):
        if (kind, text) in seen:
            return
        seen.add((kind, text))
        samples.append((origin, text, kinds, kind))

    corpus = json.load(open("spec/sentences-corpus.json"))["sentence_corpus"]
    for line in corpus:
        add("corpus", "any", line, ["check", "for-line", "from-line"])
    cases = case_sentences()
    for kind, text in cases:
        add("case", kind, text, [kind])
    for kind, text in EXTRA:
        add("extra", kind, text, [kind])

    bad_generated = 0
    generated = []
    for kind, count in GENERATED.items():
        made = 0
        tries = 0
        while made < count and tries < count * 20:
            tries += 1
            text = generator.gen(grammar(kind))
            if has_surrogate_escape(text) or any(0xD800 <= ord(c) <= 0xDFFF for c in text):
                continue
            if not abnf_accepts(grammar, [kind], text):
                bad_generated += 1
                continue
            if (kind, text) in seen:
                continue
            add("generated", kind, text, [kind])
            generated.append((kind, text))
            made += 1

    mutated = 0
    for kind, text in generated:
        for _ in range(MUTATIONS_PER_SAMPLE):
            changed = mutate(rng, text)
            if changed is None or padded(changed) or changed == text or (kind, changed) in seen:
                continue
            add("mutated", kind, changed, [kind])
            mutated += 1

    edged = 0
    for n, (kind, text) in enumerate(generated):
        if n % EDGED_EVERY:
            continue
        pool = list(WHITE_SPACE) + NOT_WHITE_SPACE
        left = "".join(rng.choice(pool) for _ in range(rng.randint(0, 2)))
        right = "".join(rng.choice(pool) for _ in range(rng.randint(0, 2)))
        changed = left + text + right
        if changed == text or (kind, changed) in seen:
            continue
        add("edges", kind, changed, [kind])
        edged += 1

    flat = [(o, t, k) for o, t, k, _ in samples]
    results = ergo_reads(flat)

    disagreements = []
    semantic = 0
    for (origin, text, kinds, kind), per_kind in zip(samples, results):
        theirs = abnf_accepts(grammar, kinds, text)
        accepted = any(not r["problems"] for r in per_kind)
        syntax = [r["problems"] for r in per_kind if r["problems"] and any(is_syntax(p) for p in r["problems"])]
        rejected_by_syntax = not accepted and len(syntax) == len(per_kind)
        if not accepted and not rejected_by_syntax:
            semantic += 1
        problems = sorted({p for r in per_kind for p in r["problems"]})
        if theirs and rejected_by_syntax:
            disagreements.append((kind, text, origin, "the ABNF accepts and ergo.rego rejects", problems))
        elif not theirs and accepted:
            disagreements.append((kind, text, origin, "ergo.rego accepts and the ABNF rejects", problems))

    rust_disagreements = []
    if command is not None:
        for (origin, text, kinds, kind), per_kind, ergo in zip(samples, rust_reads(command, flat), results):
            theirs = abnf_accepts(grammar, kinds, text)
            accepted = any(not r["syntax"] for r in per_kind)
            problems = sorted({p for r in per_kind for p in r["syntax"]})
            if theirs and not accepted:
                rust_disagreements.append((kind, text, origin, "the ABNF accepts and Rust rejects", problems))
            elif not theirs and accepted:
                rust_disagreements.append((kind, text, origin, "Rust accepts and the ABNF rejects", problems))
            for rust_kind, ergo_kind in zip(per_kind, ergo):
                mine = sorted(p for p in rust_kind["problems"] if not LATER.search(p))
                if mine != sorted(ergo_kind["problems"]):
                    said = mine, sorted(ergo_kind["problems"])
                    rust_disagreements.append((rust_kind["kind"], text, origin, "Rust and ergo.rego give different problems", [f"Rust {said[0]}", f"ergo.rego {said[1]}"]))

    section = open("spec/OPEN.md").read().split("\n## Sentences the ABNF and ergo.rego read differently\n", 1)[1].split("\n## ", 1)[0]
    listed = set()
    for kind, raw in re.findall(r"^- (\w[\w-]*) `(.+?)`", section, re.M):
        listed.add((kind, json.loads(raw)))
    found = {(kind, text) for kind, text, *_ in disagreements}

    problems = []
    for kind, text, origin, side, why in sorted(disagreements, key=lambda d: (d[0], d[1])):
        if (kind, text) not in listed:
            said = f": {'; '.join(why)}" if why else ""
            problems.append(f"{kind} {json.dumps(text)} ({origin}): {side}{said}")
    for kind, text in sorted(listed - found):
        problems.append(f"spec/OPEN.md lists {kind} {json.dumps(text)}, but the two read it alike now")

    for kind, text, origin, side, why in sorted(rust_disagreements, key=lambda d: (d[0], d[1])):
        said = f": {'; '.join(why)}" if why else ""
        problems.append(f"{kind} {json.dumps(text)} ({origin}): {side}{said}")

    rust_summary = f", {len(rust_disagreements)} Rust disagreements" if command is not None else ""
    origins = {o: sum(1 for s in samples if s[0] == o) for o in ["corpus", "case", "extra", "generated", "mutated", "edges"]}
    print(f"read {len(samples)} sentences ({origins}) in {time.time() - started:.1f}s; {len(disagreements)} disagreements, {len(listed)} listed{rust_summary}; ergo.rego rejected {semantic} for reasons that aren't syntax; {bad_generated} generated sentences the ABNF parser itself refused")
    for line in problems:
        print(line)
    sys.exit(1 if problems else 0)


main()
