import json
import pathlib
import random
import re
import sys

out = pathlib.Path(sys.argv[1])
n = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
root = pathlib.Path(__file__).resolve().parents[3]
spec = re.search(r'^_spec := "(.*)"$', (root / "engines/rego/ergo.rego").read_text(), re.M).group(1)
random.seed(1)

deployments = [
    {
        "id": f"d{i}",
        "environment": random.choice(["prod", "prod", "staging"]),
        "approved_by": random.choice(["alice", "bob", None, ""]),
        "commits": [{"sha": f"c{i}-{j}", "signed": random.random() < 0.97} for j in range(10)],
        "approvers": [{"username": u, "state": random.choice(["APPROVED", "COMMENTED"])} for u in ("alice", "bob", "carol")],
    }
    for i in range(n)
]

policy = {
    "ergo_spec": spec,
    "subjects": {"deployment": {"from": 'deployments whose environment is "prod"', "identified_by": "id"}},
    "requirements": {
        "prod_deploy": {
            "subject": "deployment",
            "min_subjects": 0,
            "checks": {
                "approver_recorded": "approved_by is a non-empty string",
                "signed": "every commits.signed is true",
                "approved": 'some approvers.state is "APPROVED"',
            },
        }
    },
}

out.mkdir(parents=True, exist_ok=True)
(out / f"input-{n}.json").write_text(json.dumps({"deployments": deployments}))
(out / "policy.json").write_text(json.dumps(policy))
(out / "data.json").write_text(json.dumps({"bench_policy": policy}))
(out / "bench.rego").write_text("package bench\n\nimport data.ergo\n\nreport := ergo.report(input, data.bench_policy, {})\n")
