import json
import random
import sys

out = sys.argv[1]
random.seed(1)

for n in (1000, 10000):
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
    json.dump({"deployments": deployments}, open(f"{out}/input-{n}.json", "w"))

requirements = {"prod_deploy": {
    "subject_type": "deployment",
    "from": ["deployments"],
    "id": ["id"],
    "min_subjects": 0,
    "applies_to": {"is_prod": {"op": "equals", "path": ["environment"], "value": "prod"}},
    "checks": {
        "approver_recorded": {"op": "present", "path": ["approved_by"]},
        "signed": {"op": "all", "path": ["commits"], "check": {"op": "equals", "path": ["signed"], "value": True}},
        "approved": {"op": "any", "path": ["approvers"], "check": {"op": "equals", "path": ["state"], "value": "APPROVED"}},
    },
}}
json.dump(requirements, open(f"{out}/requirements.json", "w"))
json.dump({"requirements": requirements}, open(f"{out}/data.json", "w"))
open(f"{out}/bench.rego", "w").write("package bench\n\nimport data.ergo\n\nreport := ergo.report(input, data.requirements)\n")
