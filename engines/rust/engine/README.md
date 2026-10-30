# ergo-policy-engine

**Experimental.** This crate may change without notice. Use [`ergo.rego`](https://github.com/kosli-dev/ergo) for real policies.

Part of [Ergo](https://github.com/kosli-dev/ergo), which turns policy evaluation into a report that says what was checked, what failed and why. This crate is the Rust engine: it builds the same report as `ergo.rego`, the Rego engine, from a policy, an input and params, all as JSON.

```rust
use ergo_policy_engine::{report, violations};
use serde_json::json;

let policy = json!({
    "ergo_spec": "v0.3-dev",
    "subjects": {"deployment": {"from": "deployments"}},
    "requirements": {
        "approved": {
            "subject": "deployment",
            "checks": {"has approvals": "approvals is at least 2"}
        }
    }
});
let input = json!({"deployments": [{"approvals": 1}]});

let report = report(&input, &policy, &json!({}));
assert_eq!(report["compliant"], json!(false));
assert_eq!(violations(&report).as_array().unwrap().len(), 1);
```

`report` gives the whole report and `violations` lists only what failed. It reads sentences with [`ergo-policy-sentences`](https://crates.io/crates/ergo-policy-sentences). To run it from a terminal, use [`ergo-policy-cli`](https://crates.io/crates/ergo-policy-cli).
