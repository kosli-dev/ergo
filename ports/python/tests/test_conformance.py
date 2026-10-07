import json
import pathlib

import pytest

import ergo

ROOT = pathlib.Path(__file__).resolve().parents[3] / "conformance"

KNOWN = {
    "from_tests/present / a min subjects whose value is a whole number is well formed however it is written (2) / input 1":
        "the expected report was made with OPA 1.19, which compares 100.0 wrongly; see conformance/FINDINGS.md",
}


def cases():
    for file in sorted(ROOT.rglob("cases.json")):
        topic = file.parent.relative_to(ROOT).as_posix()
        for group in json.loads(file.read_text()):
            for case in group["cases"]:
                name = f"{topic} / {group['description']} / {case['description']}"
                marks = [pytest.mark.xfail(reason=KNOWN[name], strict=True)] if name in KNOWN else []
                yield pytest.param(group, case, id=name, marks=marks)


@pytest.mark.parametrize("group,case", list(cases()))
def test_case(group, case):
    report = ergo.report(case["input"], group["requirements"], params=group.get("params"))
    assert report == case["report"]
    if "violations" in case:
        assert ergo.violations(report) == case["violations"]


def test_custom_operators_are_supplied_by_the_caller():
    operators = ergo.Operators({
        "min_length_at": {
            "params": {"path": {"kind": "path", "type": "list"}, "min_path": {"kind": "path", "type": "number"}},
            "expression": "count({path}) >= {min_path}",
            "passes": "size(path) >= min_path",
        }
    })
    report = ergo.report(
        {"items": [{"id": 1, "files": ["a"], "total_files": 2}]},
        {"s": {"from": ["items"], "id": ["id"], "checks": {"c": {"op": "min_length_at", "path": ["files"], "min_path": ["total_files"]}}}},
        operators=operators,
    )
    row = next(r for r in report["results"] if r["check"] == "c")
    assert (row["passed"], row["cause"]) == (False, "value")
    assert report["requirements"]["s"]["checks"]["c"]["expression"] == "count(files) >= total_files"


def test_broken_definitions_raise_when_loaded():
    with pytest.raises(ValueError, match="isn't one of its params"):
        ergo.Operators({"x": {"params": {"a": "number"}, "passes": "b > 1"}})
