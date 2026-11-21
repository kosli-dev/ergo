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
    ("keyed", 'x.v that is m named by {R} is "a"', "v", "m", 3),
]
LITERALS = {"ge": "3", "in": '["a", "b"]', "starts": '"a"', "every": "3", "count": "3", "keyed": '"m"'}
POSITIONS = ["param", "input", "field", "none"]
ROOT_STATES = ["fine", "wrong", "missing", "null"]
ITEM_STATES = ["fine", "bad", "missing", "null", "semi"]
LINES = [
    ("plain", "every xs as x"),
    ("whose", "every xs whose w is at least $params.line as x"),
]
FINE = {"ge": 5, "in": "a", "starts": "a", "every": 5, "count": 5, "keyed": {"m": "a"}}
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
    return {} if value is M else {"v": value}


def root_value(kind, state):
    if state == "fine":
        return kind[3]
    if state == "wrong":
        return kind[4]
    return None


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
    root = {"param": "$params.r", "input": "$input.r", "field": "x.z", "none": LITERALS[kind[0]]}[position]
    sentence = kind[1].replace("{R}", root)
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


def main(path):
    pairs = []
    i = 0
    for line_name, line in LINES:
        for kind in KINDS:
            for position in POSITIONS:
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
    with open(path, "w") as handle:
        json.dump(pairs, handle, indent=1)
    print(len(pairs), "pairs")


main(sys.argv[1])
