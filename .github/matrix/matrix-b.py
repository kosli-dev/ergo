import json
import random
import sys

rnd = random.Random(694710)
MISSING = object()

KIND_FINE_ITEM = {"num": 3, "str": "abc", "list": ["a", "b"], "time": "2026-01-01T00:00:00Z"}
KIND_WRONG_ITEM = {"num": ["s", True], "str": [3, {"a": 1}], "list": [3, {"a": 1}], "time": [3, "nope"]}
KIND_FINE_ROOT = {"num": 2, "str": "a", "list": ["a", "b"], "time": "2026-06-01T00:00:00Z", "regex": "^a"}
KIND_WRONG_ROOT = {"num": "s", "str": 3, "list": "s", "time": 7, "regex": 5}

OPS = [
    ("is at least {R}", "num", "num"),
    ("is more than {R}", "num", "num"),
    ("is {R}", "str", "str"),
    ("is not {R}", "str", "str"),
    ("does not equal {R}", "num", "num"),
    ("is {R} within 1", "num", "num"),
    ("is in {R}", "str", "list"),
    ("is not in {R}", "str", "list"),
    ("contains {R}", "list", "str"),
    ("does not contain {R}", "list", "str"),
    ("contains all of {R}", "list", "list"),
    ("contains some of {R}", "list", "list"),
    ("matches {R}", "str", "regex"),
    ("does not match {R}", "str", "regex"),
    ("starts with {R}", "str", "str"),
    ("ends with {R}", "str", "str"),
    ("is alphabetically before {R}", "str", "str"),
    ("is at most {R}", "num", "num"),
    ("is less than {R}", "num", "num"),
    ("is before {R}", "time", "time"),
    ("is on or after {R}", "time", "time"),
]

LEFT_OPS = [
    ("is at least {I}", "num", "num"),
    ("is {I}", "str", "str"),
    ("is not {I}", "str", "str"),
    ("is in {I}", "str", "list"),
    ("contains {I}", "list", "str"),
    ("contains all of {I}", "list", "list"),
    ("matches {I}", "str", "str"),
    ("starts with {I}", "str", "str"),
    ("is alphabetically before {I}", "str", "str"),
    ("is before {I}", "time", "time"),
    ("is at most {I}", "num", "num"),
]

NO_ROOT_OPS = ["exists", "does not exist", "is a non-empty string", "is a list", "is empty", "is not empty", "is true"]

ROOT_STATES = ["missing", "null", "wrong", "mixed", "object", "fine"]
ITEM_STATES = ["fine", "missing", "null", "wrong", "notobj", "mixed", "empty", "nested"]
COUNTS = [0, 1, 2, 4, 5]
SOURCES = ["params", "input", "subject", "part"]


def root_value(state, kind):
    return {
        "missing": MISSING,
        "null": None,
        "wrong": KIND_WRONG_ROOT[kind],
        "mixed": [1, "a", None, {"b": 2}],
        "object": {"a": 1},
        "fine": KIND_FINE_ROOT[kind],
    }[state]


def item_value(state, kind):
    if state == "fine":
        return KIND_FINE_ITEM[kind]
    if state == "missing":
        return MISSING
    if state == "null":
        return None
    if state == "wrong":
        return rnd.choice(KIND_WRONG_ITEM[kind])
    if state == "mixed":
        return [1, "a", None]
    if state == "empty":
        return []
    if state == "nested":
        return [[1]]
    raise ValueError(state)


def make_items(n, kind, field="v", focus_is_value=False, states=None, extra=None):
    out, used = [], []
    for i in range(n):
        st = states[i] if states else rnd.choice(ITEM_STATES)
        used.append(st)
        if st == "notobj":
            out.append(rnd.choice([3, "s", None, ["x"]]))
            continue
        val = item_value(st, kind)
        it = {}
        if val is not MISSING:
            it[field] = val
        if extra:
            it.update(extra(i))
        out.append(it)
    return out, used


def token(source, ctx):
    if source == "params":
        return "$params.x"
    if source == "input":
        return "$input.x"
    if source == "subject":
        return "x" if ctx == "flat" else "thing.x"
    return "p.x"


def token2(source, ctx):
    return token(source, ctx)[:-1] + "y"


def place(source, name, value, thing, top, params, part_state=None):
    if source == "params":
        if value is not MISSING:
            params[name] = value
    elif source == "input":
        if value is not MISSING:
            top[name] = value
    elif source == "subject":
        if value is not MISSING:
            thing[name] = value
    else:
        if part_state == "partnull":
            thing["pp"] = None
            return
        if part_state == "partmissing":
            return
        pp = thing.setdefault("pp", {})
        if pp is None:
            return
        if value is not MISSING:
            pp[name] = value


def policy(check):
    return {
        "subjects": {"thing": {"from": "things", "identified_by": "id", "has": {"p": "pp"}}},
        "requirements": {"s": {"subject": "thing", "checks": {"c": check}}},
    }


pairs = []
names = set()


def emit(name, check, thing, top, params, tags):
    base = name
    k = 2
    while name in names:
        name = f"{base} #{k}"
        k += 1
    names.add(name)
    inp = dict({"things": [dict({"id": "t"}, **thing)]}, **top)
    pairs.append({"name": name, "policy": policy(check), "input": inp, "params": params, "tags": tags})


def counts_cycle(i):
    return COUNTS[i % len(COUNTS)]


def state_desc(used):
    return ",".join(used) if used else "none"


def gen_whose_item_left():
    i = 0
    for op, ik, rk in OPS:
        for rs in ROOT_STATES:
            src = SOURCES[i % 4]
            n = counts_cycle(i + (i // 5))
            i += 1
            thing, top, params = {}, {}, {}
            part_state = None
            if src == "part" and rs == "missing" and rnd.random() < 0.5:
                part_state = rnd.choice(["partnull", "partmissing"])
            place(src, "x", root_value(rs, rk), thing, top, params, part_state)
            items, used = make_items(n, ik)
            thing["es"] = items
            ph = op.replace("{R}", token(src, "clause"))
            check = f"count of es whose v {ph} is 0"
            emit(f"W {op} [{src}={part_state or rs}] items={state_desc(used)}", check, thing, top, params, ["count-whose", op, src, rs])


def gen_whose_root_left():
    i = 0
    for op, rk, ik in LEFT_OPS:
        for rs in ROOT_STATES:
            src = SOURCES[(i + 1) % 4]
            n = counts_cycle(i + 2)
            i += 1
            thing, top, params = {}, {}, {}
            place(src, "x", root_value(rs, rk), thing, top, params)
            items, used = make_items(n, ik)
            thing["es"] = items
            ph = op.replace("{I}", "v")
            check = f"count of es whose {token(src, 'clause')} {ph} is 0"
            emit(f"WL {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, ["count-whose-left", op, src, rs])


def gen_whose_both():
    i = 0
    for op, ik, rk in OPS[:: 2]:
        for _ in range(2):
            s1 = SOURCES[i % 4]
            s2 = SOURCES[(i + 1 + (i // 4)) % 4]
            if s2 == s1:
                s2 = SOURCES[(SOURCES.index(s1) + 1) % 4]
            r1, r2 = rnd.choice(ROOT_STATES), rnd.choice(ROOT_STATES)
            n = counts_cycle(i)
            i += 1
            thing, top, params = {}, {}, {}
            place(s1, "x", root_value(r1, ik), thing, top, params)
            place(s2, "y", root_value(r2, rk), thing, top, params)
            items, used = make_items(n, ik)
            thing["es"] = items
            ph = op.replace("{R}", token2(s2, "clause"))
            check = f"count of es whose {token(s1, 'clause')} {ph} is 0"
            emit(f"WB {op} [{s1}={r1},{s2}={r2}] items={state_desc(used)}", check, thing, top, params, ["count-whose-both", op])


def gen_that():
    i = 0
    for op, ik, rk in OPS:
        for rs in rnd.sample(ROOT_STATES, 4):
            src = SOURCES[(i + 2) % 4]
            n = counts_cycle(i + 1)
            i += 1
            thing, top, params = {}, {}, {}
            place(src, "x", root_value(rs, rk), thing, top, params)
            items, used = make_items(n, ik)
            thing["es"] = items
            ph = op.replace("{R}", token(src, "clause"))
            check = f"count of es.v that {ph} is 0"
            emit(f"T {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, ["count-that", op, src, rs])


def gen_sum():
    i = 0
    for op in ["is at least {R}", "is more than {R}", "is {R} within 1", "is at most {R}", "does not equal {R}"]:
        for rs in ROOT_STATES:
            src = SOURCES[i % 4]
            n = counts_cycle(i + 3)
            i += 1
            thing, top, params = {}, {}, {}
            place(src, "x", root_value(rs, "num"), thing, top, params)
            items, used = make_items(n, "num")
            thing["es"] = items
            ph = op.replace("{R}", token(src, "clause"))
            check = f"sum of es.v that {ph} is 0"
            emit(f"S {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, ["sum-that", op, src, rs])


def gen_two_conditions():
    for i in range(24):
        op, ik, rk = OPS[(i * 5) % len(OPS)]
        nr = NO_ROOT_OPS[i % len(NO_ROOT_OPS)]
        src = SOURCES[i % 4]
        rs = ROOT_STATES[(i * 7) % 6]
        n = counts_cycle(i + 4)
        thing, top, params = {}, {}, {}
        place(src, "x", root_value(rs, rk), thing, top, params)
        wkind = "list" if nr in ("is a list", "is empty", "is not empty") else ("str" if nr == "is a non-empty string" else "num")
        items, used = make_items(n, ik, extra=lambda j: {} if rnd.random() < 0.3 else {"w": rnd.choice([KIND_FINE_ITEM[wkind], None, 3, "", [], True])})
        thing["es"] = items
        ph = op.replace("{R}", token(src, "clause"))
        check = f"count of es whose w {nr} and whose v {ph} is 0" if i % 2 else f"count of es whose v {ph} and whose w {nr} is 0"
        emit(f"W2 {nr} / {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, ["count-whose-2", op, src, rs])


def gen_every_some():
    i = 0
    for op, ik, rk in OPS:
        for q in ["every", "some", "every-ifany"]:
            src = SOURCES[(i + 3) % 4]
            rs = ROOT_STATES[(i * 5) % 6]
            n = counts_cycle(i)
            i += 1
            thing, top, params = {}, {}, {}
            place(src, "x", root_value(rs, rk), thing, top, params)
            items, used = make_items(n, ik)
            thing["es"] = items
            ph = op.replace("{R}", token(src, "flat"))
            check = f"some es.v {ph}" if q == "some" else (f"every es.v, if any, {ph}" if q == "every-ifany" else f"every es.v {ph}")
            if "contain" in op:
                ph = op.replace("{R}", token(src, "clause"))
                check = f"some es whose v {ph} exists" if q == "some" else (f"every es whose v {ph}, if any, is an object" if q == "every-ifany" else f"every es whose v {ph} is an object")
            emit(f"E {q} {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, [q, op, src, rs])


def gen_plus():
    for i in range(24):
        op, ik, rk = OPS[(i * 3) % len(OPS)]
        src = SOURCES[i % 4]
        rs = ROOT_STATES[(i * 5 + 1) % 6]
        n = counts_cycle(i + 2)
        thing, top, params = {}, {}, {}
        place(src, "x", root_value(rs, rk), thing, top, params)
        items, used = make_items(n, ik)
        thing["es"] = items
        fs = rnd.choice(["missing", "null", "text", "list"])
        if fs == "null":
            thing["fs"] = None
        elif fs == "text":
            thing["fs"] = "s"
        elif fs == "list":
            thing["fs"] = [1, 2]
        ph = op.replace("{R}", token(src, "clause"))
        if i % 3 == 2:
            check = f"count of fs plus count of es.v that {ph} is 0"
        else:
            check = f"count of fs plus count of es whose v {ph} is 0"
        emit(f"PLUS fs={fs} {op} [{src}={rs}] items={state_desc(used)}", check, thing, top, params, ["plus", op, src, rs])


def gen_for():
    for i in range(36):
        op, ik, rk = OPS[(i * 4 + 1) % len(OPS)]
        src = SOURCES[i % 4]
        rs = ROOT_STATES[(i * 5 + 2) % 6]
        thing, top, params = {}, {}, {}
        place(src, "x", root_value(rs, rk), thing, top, params)
        gs = []
        desc = []
        for g in range(rnd.choice([1, 2, 3])):
            if rnd.random() < 0.15:
                gs.append(rnd.choice([3, None, {"es": None}, {}]))
                desc.append("bad")
                continue
            items, used = make_items(rnd.choice(COUNTS), ik)
            gs.append({"es": items})
            desc.append(state_desc(used))
        thing["gs"] = gs
        ph = op.replace("{R}", token(src, "clause"))
        inner = f"count of g.es whose v {ph} is 0" if i % 3 else f"count of g.es.v that {ph} is 0"
        check = {"for": "every gs as g", "assert": inner}
        emit(f"FOR {op} [{src}={rs}] gs={'|'.join(desc)}", check, thing, top, params, ["for", op, src, rs])


KEY_STATES = ["missing", "null", "num", "fine", "notfound", "list"]
MAP_STATES = ["fine", "missing", "null", "text", "list"]


def key_value(st):
    return {"missing": MISSING, "null": None, "num": 3, "fine": "a", "notfound": "zz", "list": ["a"]}[st]


def map_value(st):
    return {"fine": {"a": "abc", "b": 2}, "missing": MISSING, "null": None, "text": "s", "list": [1, "a"]}[st]


def gen_keys():
    maps = ["item", "params", "input", "part"]
    keys = ["params", "input", "item"]
    forms = ["whose", "that", "every", "whose-left"]
    i = 0
    for msrc in maps:
        for ksrc in keys:
            for kst in KEY_STATES:
                form = forms[i % 4]
                if form in ("that", "every") and (ksrc == "item" or msrc == "item"):
                    form = "whose"
                mst = MAP_STATES[(i * 3) % 5] if i % 3 == 0 else "fine"
                n = counts_cycle(i + 1)
                i += 1
                thing, top, params = {}, {}, {}
                kv = key_value(kst)
                mv = map_value(mst)
                ktok = {"params": "$params.k", "input": "$input.k", "item": "k"}[ksrc]
                mtok = {"item": "m", "params": "$params.m", "input": "$input.m", "part": "p.m"}[msrc]
                if ksrc == "params" and kv is not MISSING:
                    params["k"] = kv
                if ksrc == "input" and kv is not MISSING:
                    top["k"] = kv
                if msrc == "params" and mv is not MISSING:
                    params["m"] = mv
                if msrc == "input" and mv is not MISSING:
                    top["m"] = mv
                if msrc == "part" and mv is not MISSING:
                    thing["pp"] = {"m": mv}

                def extra(j):
                    e = {}
                    if ksrc == "item":
                        v = key_value(rnd.choice(KEY_STATES)) if rnd.random() < 0.5 else kv
                        if v is not MISSING:
                            e["k"] = v
                    if msrc == "item":
                        v = map_value(rnd.choice(MAP_STATES)) if rnd.random() < 0.4 else mv
                        if v is not MISSING:
                            e["m"] = v
                    return e

                items, used = make_items(n, "str", extra=extra)
                thing["es"] = items
                ref = f"{mtok} named by {ktok}"
                if form == "whose":
                    check = f"count of es whose v is {ref} is 0"
                elif form == "whose-left":
                    check = f"count of es whose {ref} is v is 0" if msrc != "item" else f"count of es whose v is not {ref} is 0"
                elif form == "that":
                    check = f"count of es.v that is {ref} is 0"
                else:
                    check = f"every es.v is {ref}"
                emit(f"K {form} map={msrc}:{mst} key={ksrc}:{kst} items={state_desc(used)}", check, thing, top, params, ["keys", form, msrc, ksrc, kst, mst])


def gen_list_states():
    for i in range(24):
        op, ik, rk = OPS[(i * 7 + 3) % len(OPS)]
        src = SOURCES[i % 4]
        rs = ["missing", "null", "wrong", "mixed", "fine", "object"][i % 6]
        thing, top, params = {}, {}, {}
        place(src, "x", root_value(rs, rk), thing, top, params)
        es = ["missing", "null", "text", "object", "nested"][i % 5]
        if es == "null":
            thing["es"] = None
        elif es == "text":
            thing["es"] = "s"
        elif es == "object":
            thing["es"] = {"v": KIND_FINE_ITEM[ik]}
        elif es == "nested":
            thing["es"] = [[{"v": KIND_FINE_ITEM[ik]}], {"v": None}]
        ph = op.replace("{R}", token(src, "clause" if i % 3 else "flat"))
        check = [f"count of es.v that {ph} is 0", f"count of es whose v {ph} is 0", f"every es.v {ph}"][i % 3]
        if i % 3 == 2:
            ph = op.replace("{R}", token(src, "flat"))
            check = f"every es.v {ph}"
        emit(f"L es={es} {op} [{src}={rs}]", check, thing, top, params, ["list-state", op, src, rs])


gen_whose_item_left()
gen_whose_root_left()
gen_whose_both()
gen_that()
gen_sum()
gen_two_conditions()
gen_every_some()
gen_plus()
gen_for()
gen_keys()
gen_list_states()

json.dump(pairs, open(sys.argv[1], "w"), indent=1)
print(len(pairs), file=sys.stderr)
