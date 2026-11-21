import json
import random
import sys

M = object()

KINDS = [
    ("ge", "x.v is at least {R}", "v", 3, "s"),
    ("in", "x.v is in {R}", "v", ["a", "b"], "s"),
    ("starts", "x.v starts with {R}", "v", "a", 3),
    ("every", "every x.ys.n is at least {R}", "ys", 3, "s"),
    ("count", "count of x.ys whose n is at least {R} is 0", "ys", 3, "s"),
    ("keyed", "count of x.es.v that is m named by {R} is 0", "es", "m", 3),
]
LITERALS = {"ge": "3", "in": '["a", "b"]', "starts": '"a"', "every": "3", "count": "3", "keyed": None}
POSITIONS = ["param", "input", "field", "none"]
ROOT_STATES = ["fine", "wrong", "missing", "null"]
ITEM_STATES = ["fine", "bad", "missing", "null", "semi"]
LINES = [
    ("plain", "every xs as x"),
    ("whose", "every xs whose w is at least $params.line as x"),
]
FINE = {"ge": 5, "in": "a", "starts": "a", "every": 5, "count": 5, "keyed": {"m": {"m": 1}}}
BAD = {"ge": "s", "in": 3, "starts": 3, "every": "s", "count": "s", "keyed": {"m": 3}}
SEMI = {"ge": "p; q", "in": "p; q, and r", "starts": "p; q, and r", "every": "p; q", "count": "p; q", "keyed": {"m": "p; q"}}


def item_field(kind, state):
    name = kind[0]
    if state == "fine":
        return FINE[name]
    if state == "bad":
        return BAD[name]
    if state == "null":
        return None
    if state == "semi":
        return SEMI[name]
    return M


def item_for(kind, state):
    value = item_field(kind, state)
    if kind[2] == "ys":
        return {"ys": [{}] if value is M else [{"n": value}]}
    if kind[2] == "es":
        return {"es": [{}] if value is M else [{"v": value}]}
    return {} if value is M else {"v": value}


def root_value(kind, state):
    if state == "fine":
        return kind[3]
    if state == "wrong":
        return kind[4]
    return None


def root_text(kind, position):
    if kind[0] == "in" and position == "none":
        return 'x.v is one of "a", "b"'
    root = {"param": "$params.r", "input": "$input.r", "field": "x.z", "none": LITERALS[kind[0]]}[position]
    return kind[1].replace("{R}", root)


def build(line, sentences, items, params, inp_extra):
    return {
        "policy": {
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": {"for": line, "assert": sentences}}}},
        },
        "input": dict({"things": [{"id": "t", "xs": items}]}, **inp_extra),
        "params": params,
    }


def one(i, kind, position, root_state, item_state, line_name, line):
    sentence = root_text(kind, position)
    params = {}
    inp_extra = {}
    value = root_value(kind, root_state)
    if position == "param" and root_state != "missing":
        params["r"] = value
    if position == "input" and root_state != "missing":
        inp_extra["r"] = value
    size = 5 if i % 3 == 0 else 2
    items = []
    for k in range(size):
        state = item_state if (k == 0 or size == 5) else "fine"
        thing = item_for(kind, state)
        if position == "field" and root_state != "missing":
            thing["z"] = value
        if line_name == "whose":
            thing["w"] = 9
        items.append(thing)
    if line_name == "whose":
        params["line"] = 1
    pair = build(line, sentence, items, params, inp_extra)
    pair["name"] = f"for/{line_name}/{kind[0]}/{position}/{root_state}/{item_state}/{size}"
    return pair


PARAM_STATES = {"fine": 3, "wrong": "s", "null": None}


def put(params, key, state):
    if state != "missing":
        params[key] = PARAM_STATES[state]


def mk(name, line, sentences, items, params, extra=None):
    pair = build(line, sentences, items, params, {})
    thing = pair["input"]["things"][0]
    thing.update(extra or {})
    pair["name"] = name
    return pair


def n_item(state):
    return {} if state == "missing" else {"n": {"fine": 5, "bad": "s", "null": None}[state]}


def v_item(state):
    return {} if state == "missing" else {"v": {"fine": 5, "bad": "s", "null": None}[state]}


def two_lists():
    out = []
    for nested in (True, False):
        line = "every ws as w, every w.ys as y" if nested else "every ws as w, every ys as y"
        for read in ("alias", "free"):
            sentence = "y.n is at least w.z" if read == "alias" else "y.n is at least $params.r"
            variants = (
                [(w, y, "fine") for w in ("fine", "bad", "missing") for y in ("fine", "missing")]
                if read == "alias"
                else [("fine", y, r) for y in ("fine", "missing") for r in ("fine", "wrong", "missing")]
            )
            for w, y, r in variants:
                ys = [n_item(y), n_item("fine")]
                z = {} if w == "missing" else {"z": 1 if w == "fine" else "s"}
                params = {}
                put(params, "r", r)
                items = [dict(z, ys=ys), dict({"z": 1}, ys=[n_item("fine")])]
                name = f"for/lists/{'nested' if nested else 'apart'}/{read}/{w}/{y}/{r}"
                out.append(mk(name, line, sentence, items, params, {"ys": ys}))
    return out


def picks():
    out = []
    for line in ("some xs as x", "first of xs as x", "first of xs sorted by n as x"):
        for r in ("fine", "wrong", "missing"):
            for state in ("fine", "bad"):
                params = {}
                put(params, "r", r)
                items = [dict(v_item(state), n=1), dict(v_item("bad"), n=2)]
                name = f"for/pick/{line.replace(' xs', '').replace(' as x', '').replace(' ', '-')}/{r}/{state}"
                out.append(mk(name, line, "x.v is at least $params.r", items, params))
    return out


def sums():
    out = []
    for read in ("alias", "free"):
        for r in ("fine", "wrong", "missing", "null"):
            for state in ("fine", "bad"):
                params = {}
                put(params, "r", r)
                sentence = "sum of x.ys.n is at least $params.r" if read == "alias" else "sum of zs.n is at least $params.r"
                items = [{"ys": [n_item(state), n_item("fine")]}, {"ys": [n_item("fine")]}]
                out.append(mk(f"for/sum/{read}/{r}/{state}", "every xs as x", sentence, items, params, {"zs": [n_item(state)]}))
    return out


def twice():
    out = []
    forms = {
        "every": ["x.v is at least $params.r", "every xs.v is at least $params.r"],
        "count": ["x.v is at least $params.r", "count of xs whose v is at least $params.r is 0"],
    }
    for form, sentences in forms.items():
        for r in ("fine", "wrong", "missing", "null"):
            for state in ("fine", "bad"):
                params = {}
                put(params, "r", r)
                items = [v_item(state), v_item("fine")]
                out.append(mk(f"for/twice/{form}/{r}/{state}", "every xs as x", sentences, items, params))
    return out


def left():
    out = []
    for position, root in (("param", "$params.r"), ("input", "$input.r"), ("field", "x.z")):
        for r in ("fine", "wrong", "missing", "null"):
            for state in ("fine", "bad"):
                params, extra, items = {}, {}, [v_item(state), v_item("fine")]
                if r != "missing":
                    value = PARAM_STATES[r]
                    if position == "param":
                        params["r"] = value
                    elif position == "input":
                        extra["r"] = value
                    else:
                        for item in items:
                            item["z"] = value
                pair = mk(f"for/left/{position}/{r}/{state}", "every xs as x", f"{root} is at most x.v", items, params)
                pair["input"].update(extra)
                out.append(pair)
    return out


def line_roots():
    out = []
    for line_state in ("fine", "wrong", "missing", "null"):
        for r in ("fine", "wrong", "missing"):
            for state in ("fine", "bad"):
                params = {}
                put(params, "line", line_state)
                put(params, "r", r)
                items = [dict(v_item(state), w=9), dict(v_item("fine"), w=9)]
                line = "every xs whose w is at least $params.line as x"
                out.append(mk(f"for/lineroot/{line_state}/{r}/{state}", line, "x.v is at least $params.r", items, params))
    return out


def not_objects():
    out = []
    shapes = {"number": [1, 2], "text": ["s", "t"], "null": [None, None], "list": [[], [1]], "mixed": [1, "s", None, [], {"v": 1, "ys": []}]}
    sentences = {"field": "x.v is at least 1", "every": "every x.ys.n is at least 1"}
    for line_name, line in LINES:
        for shape, items in shapes.items():
            for form, sentence in sentences.items():
                params = {"line": 1} if line_name == "whose" else {}
                out.append(mk(f"for/items/{line_name}/{shape}/{form}", line, sentence, list(items), params))
    return out


def empty():
    out = []
    sentences = {
        "field": "x.v is at least $params.r",
        "every": "every x.ys.n is at least $params.r",
        "count": "count of x.ys whose n is at least $params.r is 0",
    }
    for line_name, line in LINES:
        for form, sentence in sentences.items():
            for r in ("fine", "wrong", "missing"):
                params = {"line": 1} if line_name == "whose" else {}
                put(params, "r", r)
                out.append(mk(f"for/empty/{line_name}/{form}/{r}", line, sentence, [], params))
    for nested in (True, False):
        line = "every ws as w, every w.ys as y" if nested else "every ws as w, every ys as y"
        for which in ("ws", "ys"):
            for read in ("alias", "free"):
                sentence = "y.n is at least w.z" if read == "alias" else "y.n is at least $params.r"
                ws = [] if which == "ws" else [{"z": 1, "ys": []}]
                params = {} if read == "alias" else {"r": "s"}
                name = f"for/empty/lists/{'nested' if nested else 'apart'}/{which}/{read}"
                out.append(mk(name, line, sentence, ws, params, {"ys": []}))
    return out


def main(path):
    pairs = []
    i = 0
    for line_name, line in LINES:
        for kind in KINDS:
            for position in POSITIONS:
                if kind[0] == "keyed" and position == "none":
                    continue
                states = ROOT_STATES if position != "none" else ["fine"]
                for root_state in states:
                    for item_state in ITEM_STATES:
                        i += 1
                        if line_name == "whose" and (i % 3 != 0 or position == "field"):
                            continue
                        pairs.append(one(i, kind, position, root_state, item_state, line_name, line))
    rng = random.Random(694)
    second = [k for k in KINDS if k[0] in ("ge", "in", "starts")]
    for n in range(60):
        first, other = rng.sample(second, 2)
        first_state = rng.choice(ROOT_STATES)
        other_state = rng.choice(ROOT_STATES)
        item_state = rng.choice(ITEM_STATES)
        params = {}
        if first_state != "missing":
            params["a"] = root_value(first, first_state)
        if other_state != "missing":
            params["b"] = root_value(other, other_state)
        sentences = [
            first[1].replace("{R}", "$params.a"),
            other[1].replace("{R}", "$params.b").replace("x.v", "x.w"),
        ]
        item = {}
        for kind, field, state in ((first, "v", item_state), (other, "w", "fine")):
            value = item_field(kind, state)
            if value is not M:
                item[field] = value
        pair = build("every xs as x", sentences, [item, dict(item)], params, {})
        pair["name"] = f"for/two/{first[0]}-{first_state}/{other[0]}-{other_state}/{item_state}/{n}"
        pairs.append(pair)
    for family in (two_lists, picks, sums, twice, left, line_roots, not_objects, empty):
        pairs.extend(family())
    with open(path, "w") as handle:
        json.dump(pairs, handle, indent=1)
    print(len(pairs), "pairs")


main(sys.argv[1])
