import json
import sys

M = object()

OPS = [
    ("is at least {R}", "num", 3, "s"),
    ("is less than {R}", "num", 3, "s"),
    ("is {R}", "str", "a", 3),
    ("is not {R}", "str", "a", 3),
    ("starts with {R}", "str", "a", 3),
    ("is in {R}", "str", ["a", "b"], "s"),
    ("is not in {R}", "str", ["a", "b"], "s"),
    ("contains {R}", "list", "a", 3),
    ("matches {R}", "str", "^a", 5),
    ("is before {R}", "time", "2026-06-01T00:00:00Z", 7),
]
FINE = {"num": 1, "str": "abc", "list": ["a"], "time": "2026-01-01T00:00:00Z"}
BAD = {"num": "s", "str": 3, "list": "s", "time": 3}
ITEM = ["fine", "bad", "missing", "null", "semi"]
ROOT = ["fine", "wrong", M, None]
SIZES = [0, 1, 3, 4, 5]
pairs = []


def item_value(kind, state):
    if state == "fine":
        return FINE[kind]
    if state == "bad":
        return BAD[kind]
    if state == "null":
        return None
    if state == "semi":
        return "p; q, and r"
    return M


def emit(name, sentence, items, params, inp_extra=None):
    thing = {"id": "t", "xs": items}
    inp = {"things": [thing]}
    if inp_extra:
        inp.update(inp_extra)
    pairs.append({
        "name": name,
        "policy": {
            "subjects": {"thing": {"from": "things", "identified_by": "id"}},
            "requirements": {"s": {"subject": "thing", "checks": {"c": sentence}}},
        },
        "input": inp,
        "params": params,
    })


def root_value(rs, fine, wrong):
    if rs == "wrong":
        return wrong
    if rs is None:
        return None
    return fine


i = 0
for quant in ["every", "some"]:
    for phrase, kind, fine, wrong in OPS:
        for position in ["param", "input", "none"]:
            for _ in range(2):
                i += 1
                rs = ROOT[i % 4]
                st = ITEM[i % 5]
                size = SIZES[(i // 3) % 5]
                params = {}
                inp_extra = None
                if position == "none":
                    lit = "2" if kind == "num" else '"zz"'
                    sentence = f"{quant} xs.f {phrase.replace('{R}', lit)}"
                elif position == "param":
                    sentence = f"{quant} xs.f {phrase.replace('{R}', '$params.r')}"
                    if rs is not M:
                        params = {"r": root_value(rs, fine, wrong)}
                else:
                    sentence = f"{quant} xs.f {phrase.replace('{R}', '$input.r')}"
                    if rs is not M:
                        inp_extra = {"r": root_value(rs, fine, wrong)}
                items = []
                for k in range(size):
                    s = st if k % 2 == 0 or size == 1 else "fine"
                    v = item_value(kind, s)
                    items.append({} if v is M else {"f": v})
                emit(f"walk/{quant}/{kind}/{position}/{i}", sentence, items, params, inp_extra)

for quant in ["every", "some"]:
    for key in ["$params.k", "$input.k"]:
        for ks in ["fine", "missing", "null", "num"]:
            for size in [1, 3, 5]:
                sentence = f'{quant} xs.v that is m named by {key} is "a"'
                kv = {"fine": "m", "num": 3, "null": None}.get(ks, M)
                params = {}
                inp_extra = None
                if kv is not M:
                    if key.startswith("$params"):
                        params = {"k": kv}
                    else:
                        inp_extra = {"k": kv}
                items = [
                    {"v": {"m": ("a" if k % 2 else "p; q")}} if k != 2 else {"v": {}}
                    for k in range(size)
                ]
                emit(f"walk/keyed/{quant}/{key}/{ks}/{size}", sentence, items, params, inp_extra)

for quant in ["every", "some"]:
    for rs in ["fine", "wrong", "missing"]:
        for size in [1, 4]:
            sentence = f'{quant} xs whose n is at least $params.r, f is "a"'
            params = {"fine": {"r": 1}, "wrong": {"r": "s"}, "missing": {}}[rs]
            items = [{"n": k, "f": "p; q" if k % 2 else "a"} for k in range(size)]
            emit(f"walk/whose/{quant}/{rs}/{size}", sentence, items, params)

json.dump(pairs, open(sys.argv[1], "w"), indent=1)
print(len(pairs), "pairs")
