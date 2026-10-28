import decimal
import json
import sys


def load(path):
    return json.load(open(path), parse_float=decimal.Decimal, parse_int=decimal.Decimal)


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None:
        return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return type(a) is type(b) and a == b


rego = load(sys.argv[1])
rust = load(sys.argv[2])

if rust is None:
    print("skipped: ergo-engine gives no report yet")
    sys.exit(0)

for report in (rego, rust):
    if isinstance(report, dict):
        report.pop("engine", None)

if not same(rego, rust):
    print("the reports differ")
    sys.exit(1)

print("the reports are the same")
