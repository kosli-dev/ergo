import argparse
import collections
import json
import os
import random
import re
import shlex
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "spec"))
import sweep

USAGE = """\
property-check.py run --main-bin ERGO --branch-bin ERGO [--main-tree DIR] [--branch-tree DIR] [--rego FILE] [--opa CMD]
                      [--probes 600] [--seed 1] [--out DIR] [--clean]
property-check.py show --out DIR TAG [N]
property-check.py new OUT_BEFORE OUT_AFTER [N]
property-check.py cover OUT [OUT ...]
property-check.py order OUT --main-bin ERGO --branch-bin ERGO

run builds one random policy with a few dozen checks, one random input and a few random params. It gives each check
to the Rego engine (ergo.rego, through opa eval) and to the Rust engine on main and on the branch, and prints how many
rows (one check on one subject, with one set of params) each flag below was raised on. It reports and never fails on
a flag, and it fails on a missing option, a binary it can't run and a binary built from another commit than its tree.
The same seed gives the same policy, input and params, so a run can be repeated on another branch. A run is a few
minutes of work for the cap of 600 probes: start it under nice -n 19 and run one at a time.

Flags, each on a row of the branch's report:
  PASS_WHERE_REGO_FAILS         the branch passes a row that the Rego engine fails.
  CAUSE_DOWN_VS_MAIN            both fail, and the branch gives a cause nearer to satisfied than main does (so a
                                doubt is now called something milder). _LIKE_REGO is added when the Rego engine
                                gives the same cause as the branch.
  SAID_TWICE                    the message says one problem twice.
  ROOT_AGAIN_UNDER_ITEM         the message says a problem on its own and again under an item.
  DROPS_REGO_PROBLEM            the Rego engine's message says a problem that the branch's doesn't, and main's did.
                                _ALSO_ON_MAIN is added when main's doesn't either. Cut-off ("and N more") messages
                                are left out.
  ORDER_FREE                    the problems of the sentences that don't read the for-line's name come in a different
                                order from the sentences, or are mixed with the ones that do.
  ORDER_ROOTS                   the problems about the roots (the names a sentence reads outside the items) are not in
                                the order of the sentences that read them, or come after a problem under an item.

Other commands read the folder a run wrote with --out (default dist/property-check, which Git ignores):
  show   prints the first N (6) groups of rows with one flag: the line, the sentences, the params, the subject and
         the three reports (main, br, rego).
  new    prints the rows that have a flag in OUT_AFTER that they didn't have in OUT_BEFORE, from two runs of one seed.
  cover  counts the probes of each shape the generator was meant to reach (for example a list that holds a
         non-object beside a named by), so a run can be judged on what it covered.
  order  runs the policy in OUT again on main and on the branch and counts the rows whose message changed only in
         order, in another way, or not at all, and the rows whose verdict or cause changed under the same message.
"""

FREE = [
    "z is 1", "w exists", "w is 1", "z is at least 1", "zb is at least 1", "count of es is 1",
    "count of es whose zz is 1 is 1", "sum of es.zz is 3", "$params.min is 1", "every es.zz is 1",
    "count of es whose zz is at least $params.min is 1", "z is in $params.l",
    "count of es whose zz is m named by $params.k is 0", "count of es whose zz is at least z is 0",
    "$params.k is \"a\"", "count of es is count of zb", "every es.m named by $params.k is 1",
]
X = [
    "x.v is 1", "x.v is at least z", "x.v is at least zb", "x.v is at least $params.min", "x.v is in $params.l",
    "x.k is \"a\"", "count of x.ys is 2", "sum of x.ys.n is 3", "every x.ys.n is 1", "count of es whose zz is x.v is 1",
    "count of es whose zz is m named by x.k is 0", "x.m named by $params.k is 1", "x.m named by z is 1",
    "x exists", "x.v exists", "every x.ys.n is at least $params.min", "count of x.ys whose n is 1 is 1",
    "x.v is at least count of es", "some x.ys.n is 2", "x.m named by x.k is 1", "every x.ys, if any, exists",
    "x.w is at least $params.a",
]
K = ["count of es whose zz is m named by k is 0", "k is \"a\"", "count of es.m named by k is 1",
     "sum of es.m named by k is 1", "every es.m named by k is 1"]
Y = ["y.n is 1", "y.n is at least x.v", "y.n is at least z", "y.n is at least $params.min", "y exists"]
E = ["e.zz is x.v", "e.zz is 1", "e.zz is at least $params.min", "e.zz is at least z", "e exists"]
LINES = [
    ("every xs as x", "x", ["xs"]), ("every xs, if any, as x", "x", ["xs"]), ("some xs as x", "x", ["xs"]),
    ("every xs whose v is 1 as x", "x", ["xs"]), ("every xs whose v is at least $params.min as x", "x", ["xs"]),
    ("every xs whose v is at least zb as x", "x", ["xs"]), ("first of xs sorted by v as x", "x", ["xs"]),
    ("first of xs sorted by m named by $params.k as x", "x", ["xs"]), ("every xs whose v is in $params.l as x", "x", ["xs"]),
    ("every o named by $params.k as x", "x", ["o"]), ("last of xs whose v is at least 1 as x", "x", ["xs"]),
    ("every xs as x, every x.ys as y", "xy", ["xs", "x.ys"]), ("every xs as x, every x.ys, if any, as y", "xy", ["xs", "x.ys"]),
    ("some xs as x, every x.ys as y", "xy", ["xs", "x.ys"]),
    ("every xs as x, every x.ys whose n is at least x.v as y", "xy", ["xs", "x.ys"]),
    ("every xs as x, every es as e", "xe", ["xs", "es"]), ("some xs as x, every es, if any, as e", "xe", ["xs", "es"]),
    ("every xs as x, every es whose zz is x.v as e", "xe", ["xs", "es"]),
    ("every xs as x, every es whose zz is at least $params.min as e", "xe", ["xs", "es"]),
    ("every ks as k", "k", ["ks"]), ("every ks, if any, as k", "k", ["ks"]), ("some ks as k", "k", ["ks"]),
]
PARAMS = [{}, {"min": 1, "k": "v", "l": [1, 2], "a": 1}, {"min": "s", "k": 3, "l": None, "a": "s"},
          {"min": None, "k": "a", "l": "s"}, 3, {"k": None, "a": None, "min": 1}]
SUBJECTS = 5
PARAM_SETS = 3

KNOWN_WORDING = [r"the check is false", r".*\}, which isn't text", r"item \d+ of \w+ is .*, which isn't text"]
RANK = {"satisfied": 0, "value": 1, "null": 2, "absent": 3, "unusable": 4, "ambiguous": 5, "not_an_object": 6}
PFX = re.compile(r"^((?:item \d+(?: and item \d+)? of [^:;]+?: )+)")
MORE = re.compile(r"^and \d+ more$")


def reads_alias(sentence, kind):
    return any(re.search(r"(?<![\w.$])" + a + r"(?![\w])", sentence) for a in kind)


class Generator:
    def __init__(self, seed, clean):
        self.rnd = random.Random(seed)
        self.clean = clean

    def sentences(self, kind):
        pool = list(FREE)
        for k, extra in (("x", X), ("y", Y), ("e", E)):
            if k in kind:
                pool += extra * 2
        if kind == "k":
            pool += K * 3
        n = self.rnd.choice([1, 1, 2] if self.clean else [1, 2, 2, 3, 3])
        picked = []
        while len(picked) < n:
            s = self.rnd.choice(pool)
            if s not in picked:
                picked.append(s)
        return picked

    def num(self):
        if self.clean:
            return self.rnd.choice([1, 1, 1, 1, 2, None, "s", "MISSING"])
        return self.rnd.choice([1, 2, 1, None, "s", "MISSING", 3])

    @staticmethod
    def maybe(d, key, v):
        if v != "MISSING":
            d[key] = v

    def ys(self):
        r = self.rnd.random()
        if r < 0.1:
            return None
        if r < 0.2:
            return "MISSING"
        if r < 0.3:
            return []
        out = []
        for _ in range(self.rnd.choice([1, 2, 2, 3])):
            if self.rnd.random() < 0.1:
                out.append(self.rnd.choice([None, 3]))
                continue
            y = {}
            self.maybe(y, "n", self.num())
            out.append(y)
        return out

    def item(self):
        if self.rnd.random() < (0.04 if self.clean else 0.15):
            return self.rnd.choice([None, 3, "str", [1]])
        it = {}
        self.maybe(it, "v", self.num())
        self.maybe(it, "w", self.num())
        self.maybe(it, "k", self.rnd.choice(["v", "a", 3, None, "MISSING"]))
        self.maybe(it, "m", self.rnd.choice([{"v": 1, "a": 2}, {"v": "s"}, [5], None, "MISSING", {"a": 1}]))
        self.maybe(it, "ys", self.ys())
        return it

    def lst(self, gen):
        r = self.rnd.random()
        if r < 0.06:
            return None
        if r < 0.12:
            return "MISSING"
        if r < 0.15:
            return "s"
        if r < 0.25:
            return []
        return [gen() for _ in range(self.rnd.choice([1, 2, 2, 3, 4]))]

    def e_item(self):
        if self.rnd.random() < 0.12:
            return self.rnd.choice([None, 3])
        e = {}
        self.maybe(e, "zz", self.num())
        self.maybe(e, "m", self.rnd.choice([{"v": 1, "a": 1}, {"v": "s"}, None, "MISSING", 3]))
        return e

    def subject(self, i):
        s = {"id": f"s{i}"}
        self.maybe(s, "xs", self.lst(self.item))
        self.maybe(s, "es", self.lst(self.e_item))
        self.maybe(s, "ks", self.lst(lambda: self.rnd.choice(["v", "a", 3, None, "m", {"q": 1}])))
        self.maybe(s, "z", self.rnd.choice([1, 3, "s", None, "MISSING", 1]))
        self.maybe(s, "zb", self.rnd.choice([1, "s", None, "MISSING", [1]]))
        self.maybe(s, "w", self.rnd.choice([1, "MISSING", 2]))
        self.maybe(s, "o", self.rnd.choice([{"v": [self.item(), self.item()], "a": []}, {"v": None}, "MISSING", {"a": [self.item()]}, "s"]))
        return s

    def build(self, n_checks, spec):
        checks, meta, seen = {}, {}, set()
        while len(checks) < n_checks:
            line, kind, lists = self.rnd.choice(LINES)
            ss = self.sentences(kind)
            orders = [ss] + ([list(reversed(ss))] if len(ss) > 1 else [])
            for o in orders:
                key = json.dumps([line, o])
                if key in seen:
                    continue
                seen.add(key)
                name = f"c{len(checks):03d}"
                checks[name] = {"for": line, "assert": o if len(o) > 1 else o[0]}
                meta[name] = {"line": line, "kind": kind, "lists": lists, "sentences": o}
        free = sorted({x for m in meta.values() for x in m["sentences"] if not reads_alias(x, m["kind"])})
        alone = {f"a{i:03d}": [x] for i, x in enumerate(free)}
        for m in meta.values():
            m["alone"] = [k for x in m["sentences"] if not reads_alias(x, m["kind"]) for k, v in alone.items() if v == [x]]
        policy = {"ergo_spec": spec, "subjects": {"thing": {"from": "things", "identified_by": "id"}},
                  "requirements": {"r": {"subject": "thing", "min_subjects": 0,
                                         "checks": dict(checks, **{n: {"assert": s if len(s) > 1 else s[0]} for n, s in alone.items()})}}}
        data = {"things": [self.subject(i) for i in range(SUBJECTS)]}
        params = self.rnd.sample(PARAMS, PARAM_SETS)
        return policy, data, params, meta, alone


def capped(message):
    return bool(message) and any(MORE.match(p) for p in message.split("; "))


def units(msg):
    out = []
    for i, part in enumerate((msg or "").split("; ")):
        if not part or MORE.match(part):
            continue
        m = PFX.match(part)
        pre = m.group(1) if m else ""
        for c in part[len(pre):].split(", and "):
            q = PFX.match(c)
            p2 = pre + (q.group(1) if q else "")
            c = c[len(q.group(1)):] if q else c
            o = re.match(r"^(item \d+ of [^:;]+?) (is .*, which isn't an object)$", c)
            if o:
                p2, c = p2 + o.group(1) + ": ", "* " + o.group(2)
            elif c.endswith(", which isn't an object") and p2 and " is " in c:
                c = "* " + c[c.index(" is ") + 1:]
            out.append((i, p2, c))
    return out


def name_of(c):
    m = re.match(r"^(.*?)(?: is |: | tie on | holds )", c)
    return m.group(1) if m else c


def token_in(name, text):
    return re.search(r"(?<![\w.$])" + re.escape(name) + r"(?![\w])", text) is not None


def tag_row(row, m):
    br, mn, rg = row["br"], row["main"], row["rego"]
    tags = []
    if br["passed"] and rg and not rg["passed"]:
        tags.append("PASS_WHERE_REGO_FAILS")
    if mn and not br["passed"] and not mn["passed"] and RANK[br["cause"]] < RANK[mn["cause"]]:
        tags.append("CAUSE_DOWN_VS_MAIN" + ("_LIKE_REGO" if rg and rg["cause"] == br["cause"] else ""))
    bm = br.get("message")
    ub = units(bm)
    parts = (bm or "").split("; ")
    if len(parts) != len(set(parts)) or any(len(set(u)) != len(u) for u in
                                            [[c for i, _, c in ub if i == j] for j in range(len(parts))]):
        tags.append("SAID_TWICE")
    roots = {c for _, pre, c in ub if not pre}
    if any(pre and c in roots for _, pre, c in ub):
        tags.append("ROOT_AGAIN_UNDER_ITEM")
    if rg and not rg["passed"] and not capped(rg.get("message")) and not capped(bm) and not br["passed"]:
        have = {c for _, _, c in ub}
        lost = sorted({c for _, _, c in units(rg.get("message")) if c not in have})
        lost = [c for c in lost if not any(re.fullmatch(k, c) for k in KNOWN_WORDING)
                and not (re.fullmatch(r".* named by (\w+) is null", c) and re.sub(r".* named by (\w+) is null", r"\1 is null", c) in have)]
        if lost:
            had = {c for _, _, c in units(mn.get("message"))} if mn and not mn["passed"] else set()
            tags.append("DROPS_REGO_PROBLEM" + ("" if any(x in had for x in lost) else "_ALSO_ON_MAIN"))
            row["lost"] = lost
    if not br["passed"] and bm:
        tags += order_tags(row, m, ub)
    return tags


def first_hit(last, tiers):
    for start in (max(last, 0), 0):
        for hits in tiers:
            at = next((j for j in range(start, len(hits)) if hits[j]), None)
            if at is not None:
                return at
    return None


def order_tags(row, m, ub):
    tags = []
    frees = [s for s in m["sentences"] if not reads_alias(s, m["kind"])]
    sets = []
    for k in m["alone"]:
        a = row["alone"].get(k)
        us = units(a.get("message")) if a and not a["passed"] else []
        sets.append(({pre + c for _, pre, c in us}, {pre + name_of(c) for _, pre, c in us}))
    fseq = set().union(*[n for _, n in sets]) if sets else set()
    seq = [pre + name_of(c) for _, pre, c in ub]
    last, ended, bad = -1, False, False
    for (_, pre, c), x in zip(ub, seq):
        tiers = [[pre + c in ex for ex, _ in sets], [x in nm for _, nm in sets]]
        if not pre and name_of(c) not in m["lists"]:
            tiers.append([token_in(name_of(c), f) for f in frees])
        at = first_hit(last, tiers)
        if at is None:
            ended = True
        elif ended or at < last:
            bad = True
        else:
            last = at
    if bad:
        tags.append("ORDER_FREE")
    consumers = [(j, x) for j, x in enumerate(frees)] + [(len(frees), m["line"])] + [
        (len(frees) + 1 + j, x) for j, x in enumerate(x for x in m["sentences"] if reads_alias(x, m["kind"]))]
    lastg, seen_walk, bad = -1, False, False
    for (_, pre, c), nm in zip(ub, seq):
        if nm in fseq:
            continue
        listed = name_of(c) in m["lists"] and (c.endswith(" is []") or not any(token_in(name_of(c), x) for x in m["sentences"]))
        if pre or listed or name_of(c).startswith("item "):
            seen_walk = True
            continue
        gs = [g for g, t in consumers if token_in(name_of(c), t) and not (t == m["line"] and name_of(c) in m["lists"])]
        if not gs:
            continue
        g = min(gs)
        if seen_walk or g < lastg:
            bad = True
        lastg = max(lastg, g)
    if bad:
        tags.append("ORDER_ROOTS")
    return tags


class ShortParser(argparse.ArgumentParser):
    def error(self, message):
        sys.exit(f"property-check.py: {message}; see --help")


def fail(message):
    sys.exit(f"property-check.py: {message}")


def run_command(argv, what, env=None):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, env=env, cwd=ROOT)
    except OSError as error:
        fail(f"cannot run {what}: {error}")
    if out.returncode != 0:
        fail(f"`{shlex.join(argv)}` exited with code {out.returncode}: {sweep.tail(out.stderr or out.stdout) or 'no output'}")
    return out.stdout


def check_binary(path, tree, which):
    version = run_command([path, "--version"], f"the {which} binary").strip()
    sweep.check_commit(version, tree)


def run_ergo(path, policy, data, params):
    out = run_command([path, "report", "--policy", policy, "--input", data, "--params", params, "--compact"], f"{path} report")
    try:
        return json.loads(out)
    except ValueError:
        fail(f"{path} printed something that isn't JSON: {sweep.tail(out)}")


def run_rego(opa, rego, folder, policy, params, index):
    path = f"{folder}/data{index}.json"
    with open(path, "w") as handle:
        json.dump({"t": {"pol": policy, "par": params}}, handle)
    argv = shlex.split(opa) + ["eval", "-d", rego, "-d", path, "-i", f"{folder}/in.json", "--format", "raw",
                               "data.ergo.report(input, data.t.pol, data.t.par)"]
    out = run_command(argv, "opa", dict(os.environ, GOMAXPROCS="2"))
    try:
        return json.loads(out)
    except ValueError:
        fail(f"`{shlex.join(argv)}` printed something that isn't JSON: {sweep.tail(out)}")


def index_results(report):
    return {(x["check"], x["subject"]["id"]): x for x in report["results"] if not x["check"].startswith("$")}


def need(args, *names):
    for name in names:
        if getattr(args, name) is None:
            fail(f"missing --{name.replace('_', '-')}; see --help")


def command_run(args):
    need(args, "main_bin", "branch_bin")
    if args.probes < 1:
        fail("--probes must be 1 or more")
    rego = args.rego or os.path.join(ROOT, "dist", "ergo.rego")
    if not os.path.exists(rego):
        fail(f"{rego} doesn't exist; run .github/build-ergo.sh first, or pass --rego")
    check_binary(args.main_bin, args.main_tree, "main")
    check_binary(args.branch_bin, args.branch_tree, "branch")
    out = args.out
    os.makedirs(out, exist_ok=True)
    n_checks = max(1, args.probes // (SUBJECTS * PARAM_SETS))
    policy, data, pars, meta, alone = Generator(args.seed, args.clean).build(n_checks, sweep.spec_version())
    with open(f"{out}/pol.json", "w") as handle:
        json.dump(policy, handle, indent=1)
    with open(f"{out}/in.json", "w") as handle:
        json.dump(data, handle)
    with open(f"{out}/meta.json", "w") as handle:
        json.dump({"meta": meta, "alone": alone, "pars": pars}, handle)
    reports = {}
    for qi, par in enumerate(pars):
        qp = f"{out}/par{qi}.json"
        with open(qp, "w") as handle:
            json.dump(par, handle)
        for b, path in (("br", args.branch_bin), ("main", args.main_bin)):
            reports[(qi, b)] = run_ergo(path, f"{out}/pol.json", f"{out}/in.json", qp)
        reports[(qi, "rego")] = run_rego(args.opa, rego, out, policy, par, qi)
    rows = []
    for qi in range(len(pars)):
        idx = {b: index_results(reports[(qi, b)]) for b in ("br", "main", "rego")}
        for (c, s), br in idx["br"].items():
            if c in meta:
                rows.append({"q": qi, "check": c, "subject": s, "br": br, "main": idx["main"].get((c, s)),
                             "rego": idx["rego"].get((c, s)), "alone": {n: idx["br"].get((n, s)) for n in alone}})
    flags = collections.defaultdict(list)
    for row in rows:
        row["tags"] = tag_row(row, meta[row["check"]])
        for t in row["tags"]:
            flags[t].append(row)
    with open(f"{out}/rows.json", "w") as handle:
        json.dump(rows, handle, indent=1)
    print(f"seed {args.seed}: {len(rows)} probes", {t: len(v) for t, v in sorted(flags.items())})


def load(out):
    try:
        with open(f"{out}/rows.json") as handle:
            rows = json.load(handle)
        with open(f"{out}/meta.json") as handle:
            meta = json.load(handle)
        with open(f"{out}/in.json") as handle:
            data = json.load(handle)
    except OSError as error:
        fail(f"cannot read a run in {out}: {error}")
    return rows, meta, {t["id"]: t for t in data["things"]}


def print_row(label, x):
    if x:
        print(f"   {label:6}", x["passed"], x.get("cause"), "|", x.get("message"))


def command_show(args):
    rows, meta, inp = load(args.out)
    by = collections.defaultdict(list)
    for r in rows:
        if args.tag in r["tags"]:
            m = meta["meta"][r["check"]]
            by[(m["line"], json.dumps(m["sentences"]))].append(r)
    for k, rs in sorted(by.items(), key=lambda kv: -len(kv[1]))[:args.n]:
        r = rs[0]
        print("##", k[0], "|", k[1], f"({len(rs)} rows)", "params", json.dumps(meta["pars"][r["q"]]))
        print("   subj", json.dumps({a: v for a, v in inp[r["subject"]].items() if a != "id"}))
        for n in ("main", "br", "rego"):
            print_row(n, r[n])
        if r.get("lost"):
            print("   lost", r["lost"])


def command_new(args):
    before, _, _ = load(args.before)
    rows, meta, inp = load(args.after)
    ra = {(r["q"], r["check"], r["subject"]): r for r in before}
    gained = collections.defaultdict(list)
    for r in rows:
        a = ra.get((r["q"], r["check"], r["subject"]))
        for t in set(r["tags"]) - set(a["tags"] if a else []):
            gained[t].append((a, r))
    for t, rs in gained.items():
        print(f"== {t}: {len(rs)} rows gained")
        for a, r in rs[:args.n]:
            m = meta["meta"][r["check"]]
            print("##", m["line"], "|", json.dumps(m["sentences"]), "params", json.dumps(meta["pars"][r["q"]]))
            print("   subj", json.dumps({k: v for k, v in inp[r["subject"]].items() if k != "id"}))
            for n, x in (("before", a["br"] if a else None), ("after", r["br"]), ("main", r["main"]), ("rego", r["rego"])):
                print_row(n, x)
            if r.get("lost"):
                print("   lost", r["lost"])
    if not gained:
        print("no row gained a flag")


def command_cover(args):
    c = collections.Counter()
    for d in args.outs:
        rows, meta, inp = load(d)
        for r in rows:
            m = meta["meta"][r["check"]]
            s = inp[r["subject"]]
            c["probes"] += 1
            if m["kind"] == "xe" and isinstance(s.get("es"), list) and any(not isinstance(e, dict) for e in s["es"]) and any("named by" in x for x in m["sentences"]):
                c["pairs not objects beside a named by"] += 1
            if "sorted by m named by" in m["line"] and isinstance(s.get("xs"), list) and any(not isinstance(i, dict) for i in s["xs"]):
                c["sort key line, item not an object"] += 1
            if len(m["sentences"]) > 1:
                c["two or more sentences"] += 1
            if not r["br"]["passed"]:
                c["failed rows"] += 1
    for k, v in c.items():
        print(f"{v:6} {k}")


def message_units(msg):
    out = []
    for part in (msg or "").split("; "):
        if not part:
            continue
        m = PFX.match(part)
        pre = m.group(1) if m else ""
        for c in part[len(pre):].split(", and "):
            out.append(pre + c)
    return out


def command_order(args):
    need(args, "main_bin", "branch_bin")
    check_binary(args.main_bin, args.main_tree, "main")
    check_binary(args.branch_bin, args.branch_tree, "branch")
    g = args.out
    c = collections.Counter()
    for p in sorted(f for f in os.listdir(g) if re.fullmatch(r"pol.*\.json", f)):
        for q in sorted(f for f in os.listdir(g) if re.fullmatch(r"par\d+\.json", f)):
            a = index_results(run_ergo(args.main_bin, f"{g}/{p}", f"{g}/in.json", f"{g}/{q}"))
            b = index_results(run_ergo(args.branch_bin, f"{g}/{p}", f"{g}/in.json", f"{g}/{q}"))
            for k in a:
                x, y = a[k], b.get(k)
                c["rows"] += 1
                if y is None:
                    c["row gone"] += 1
                    continue
                if x.get("message") == y.get("message"):
                    if x["passed"] != y["passed"] or x.get("cause") != y.get("cause"):
                        c["same message, verdict or cause differs"] += 1
                    continue
                ux, uy = message_units(x.get("message")), message_units(y.get("message"))
                if sorted(ux) == sorted(uy):
                    c["order only"] += 1
                elif any(MORE.match(u) for u in ux + uy):
                    c["other, capped"] += 1
                else:
                    c["other"] += 1
    for k, v in c.items():
        print(f"{v:7} {k}")


def add_binaries(parser):
    parser.add_argument("--main-bin", help="the ergo command built from main")
    parser.add_argument("--branch-bin", help="the ergo command built from the branch")
    parser.add_argument("--main-tree", default=ROOT, help="the tree main's binary was built from (default: this repo)")
    parser.add_argument("--branch-tree", default=ROOT, help="the tree the branch's binary was built from (default: this repo)")


def main():
    parser = ShortParser(usage=USAGE)
    sub = parser.add_subparsers(dest="command", required=True, parser_class=ShortParser)
    p = sub.add_parser("run")
    add_binaries(p)
    p.add_argument("--rego", help="the built ergo.rego (default: dist/ergo.rego)")
    p.add_argument("--opa", default="opa", help="command that runs OPA (default: opa)")
    p.add_argument("--probes", type=int, default=600, help="about how many rows to run (default 600)")
    p.add_argument("--seed", type=int, default=1, help="seed of the generator (default 1)")
    p.add_argument("--out", default=os.path.join(ROOT, "dist", "property-check"))
    p.add_argument("--clean", action="store_true", help="make fewer malformed values and shorter checks")
    p.set_defaults(run=command_run)
    p = sub.add_parser("show")
    p.add_argument("--out", default=os.path.join(ROOT, "dist", "property-check"))
    p.add_argument("tag")
    p.add_argument("n", nargs="?", type=int, default=6)
    p.set_defaults(run=command_show)
    p = sub.add_parser("new")
    p.add_argument("before")
    p.add_argument("after")
    p.add_argument("n", nargs="?", type=int, default=5)
    p.set_defaults(run=command_new)
    p = sub.add_parser("cover")
    p.add_argument("outs", nargs="+")
    p.set_defaults(run=command_cover)
    p = sub.add_parser("order")
    p.add_argument("out")
    add_binaries(p)
    p.set_defaults(run=command_order)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
