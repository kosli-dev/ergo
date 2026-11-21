import json
import sys

ABSENT = object()

KIND = {
    "num": {"fine": 3, "wrong": "s"},
    "str": {"fine": "a", "wrong": 3},
    "time": {"fine": "2026-01-01T00:00:00Z", "wrong": True},
    "any": {"fine": "a", "wrong": 3},
    "scalar": {"fine": "a", "wrong": 3},
    "list": {"fine": ["a", "b"], "wrong": "s", "mixed": [1, "x"]},
    "pats": {"fine": ["^a"], "wrong": "s", "mixed": [1, "x"], "bad": [1]},
}

OPS = [
    ("equals", "equals", "any", "any"),
    ("does_not_equal", "does not equal", "any", "any"),
    ("within", "equals {R} within 1", "num", "num"),
    ("at_least", "is at least", "num", "num"),
    ("less_than", "is less than", "num", "num"),
    ("starts_with", "starts with", "str", "str"),
    ("ends_with", "does not end with", "str", "str"),
    ("alpha_before", "is alphabetically before", "str", "str"),
    ("before", "is before", "time", "time"),
    ("after", "is on or after", "time", "time"),
    ("in", "is in", "scalar", "list"),
    ("not_in", "is not in", "scalar", "list"),
    ("contains", "contains", "list", "scalar"),
    ("not_contains", "does not contain", "list", "scalar"),
    ("contains_all", "contains all of", "list", "list"),
    ("contains_some", "contains some of", "list", "list"),
    ("contains_none", "contains none of", "list", "list"),
    ("matches", "matches", "str", "pats"),
    ("not_matches", "does not match", "str", "pats"),
]

POSITIONS = ["params_left", "params_right", "input_left", "input_right", "that_right"]
ROOT_STATES = ["missing", "null", "wrong", "fine"]
ITEM_STATES = ["fine", "missing", "null", "wrong", "mixed", "notobj", "deep"]


def sentence(op, root, field, left_is_root):
    phrase = op[1]
    if "{R}" in phrase:
        left, right = (root, field) if left_is_root else (field, root)
        return f"{left} " + phrase.replace("{R}", right)
    return f"{root} {phrase} {field}" if left_is_root else f"{field} {phrase} {root}"


def value_of(role, state):
    table = KIND[role]
    if state in ("missing",):
        return ABSENT
    if state == "null":
        return None
    if state in table:
        return table[state]
    return table["wrong"]


def item_for(role, state):
    if state == "notobj":
        return "s"
    if state == "deep":
        return {"f": "s"}
    v = value_of(role, state)
    return {} if v is ABSENT else {"f": v}


def build(op, position, root_state, item_state, size):
    name_op, _, lrole, rrole = op
    left_is_root = position.endswith("_left")
    root_role, item_role = (lrole, rrole) if left_is_root else (rrole, lrole)
    if item_state == "mixed" and item_role not in ("list", "pats"):
        return None
    if position == "that_right" and item_state in ("deep",):
        return None
    start = "$input" if position.startswith("input") else "$params"
    root = f"{start}.r"
    field = "f.w" if item_state == "deep" else "f"
    rv = value_of(root_role, root_state)
    check = "count of xs whose " + sentence(op, root, field, left_is_root) + " is 1"
    state_cycle = [item_state, "fine", item_state, item_state, item_state][:size]
    items = [item_for(item_role, s) for s in state_cycle]
    thing = {"id": "t", "xs": items}
    inp = {"things": [thing]}
    params = {}
    if rv is not ABSENT:
        if start == "$input":
            inp["r"] = rv
        else:
            params["r"] = rv
    return {
        "name": f"{name_op}/{position}/root={root_state}/item={item_state}/n={size}",
        "policy": {
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": check}}},
        },
        "input": inp,
        "params": params,
    }


def that_sentence(op, root):
    phrase = op[1]
    if "{R}" in phrase:
        return phrase.replace("{R}", root)
    return f"{phrase} {root}"


def build_that(op, root_state, item_state, size):
    name_op, _, lrole, rrole = op
    if item_state in ("deep",):
        return None
    if item_state == "mixed" and lrole not in ("list", "pats"):
        return None
    rv = value_of(rrole, root_state)
    check = f"count of xs.f that {that_sentence(op, '$params.r')} is 1"
    state_cycle = [item_state, "fine", item_state, item_state, item_state][:size]
    items = []
    for s in state_cycle:
        if s == "notobj":
            items.append("s")
            continue
        v = value_of(lrole, s)
        items.append({} if v is ABSENT else {"f": v})
    params = {} if rv is ABSENT else {"r": rv}
    return {
        "name": f"{name_op}/that_right/root={root_state}/item={item_state}/n={size}",
        "policy": {
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": check}}},
        },
        "input": {"things": [{"id": "t", "xs": items}]},
        "params": params,
    }


def main():
    offset = 0
    out = sys.argv[1]
    pairs = []
    i = offset
    for op in OPS:
        for position in POSITIONS:
            for item_state in ITEM_STATES:
                root_state = ["missing", "null", "wrong", "missing", "wrong", "fine"][i % 6]
                size = [1, 5][(i // 6) % 2] if (i % 7) else 5
                i += 1
                if position == "that_right":
                    pair = build_that(op, root_state, item_state, size)
                else:
                    pair = build(op, position, root_state, item_state, size)
                if pair:
                    pairs.append(pair)
    extra = [
        (OPS[14], "params_left", "missing", "mixed", n) for n in (1, 3, 4, 5)
    ] + [
        (OPS[17], "params_left", "missing", "bad", 1),
        (OPS[12], "params_left", "missing", "missing", 2),
        (OPS[12], "params_left", "missing", "deep", 1),
        (OPS[15], "params_left", "missing", "mixed", 1),
    ]
    for op, position, rs, its, n in extra:
        pair = build(op, position, rs, its, n)
        pair["name"] = "finding/" + pair["name"]
        pairs.append(pair)
    matches_v = build(OPS[17], "params_left", "missing", "fine", 1)
    matches_v["name"] = "finding/matches/params_left/three_items"
    matches_v["input"]["things"][0]["xs"] = [{"f": 3}, {"f": "["}, {}]
    pairs.append(matches_v)
    with open(out, "w") as handle:
        json.dump(pairs, handle, indent=1)
    print(len(pairs), "pairs", file=sys.stderr)


if __name__ == "__main__":
    main()
