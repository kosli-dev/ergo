# ergo-policy-engine

**Experimental.** This crate may change without notice. Use [`ergo.rego`](https://github.com/kosli-dev/ergo) for real policies.

Part of [Ergo](https://github.com/kosli-dev/ergo), which turns policy evaluation into a report that says what was checked, what failed and why. This crate is the Rust engine: it builds the same report as `ergo.rego`, the Rego engine, from a policy, an input and params, all as JSON.

```rust
use ergo_policy_engine::{report, violations};
use serde_json::json;

let policy = json!({
    "ergo_spec": "v0.7-dev",
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

## Order of the modules

Lowest layer first. A module may use the modules earlier in this list, and never one later in it.

| module     | what it holds                                                                                                                                                   |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cause`    | the `Cause` of a row: `satisfied`, `absent`, `null`, `unusable` and the others                                                                                  |
| `names`    | the rules for how a name in a policy may be written                                                                                                             |
| `value`    | numbers and JSON values: `Decimal`, comparing and printing them                                                                                                 |
| `path`     | where a name reads: `Path`, `Start`, `Step`, and `read`, which follows a path through the input and params                                                      |
| `name`     | the text of a name for messages, like `name` and `key_text`                                                                                                     |
| `policy`   | the policy as written: `Policy::read`, `Subject`, `Requirement`, and the `Problems` found while reading it                                                      |
| `lower`    | turns a sentence into a `Check`, with the `Scope` it is written in                                                                                              |
| `checks`   | reads the checks of a requirement into a `Plan` and lists the `$refs` a check reads                                                                             |
| `reading`  | `Reading`, everything read from the policy before any input is looked at: sources, filters, parts and their problems                                            |
| `evaluate` | runs a check on the input: the evaluators under `ops/` (`compare`, `lists`, `for_line`, `tally`, `walk` and others) and `subjects.rs`, which finds each subject |
| `report`   | builds the rows and the report from the evaluations                                                                                                             |

`evaluate` isn't a module in the code: `lib.rs` has `mod ops` and `mod subjects`, and this list gives the name `evaluate` to the two together.

### Where the code doesn't follow this yet

Checked with `git grep` for `crate::` in each file:

- `checks` and `report` use each other: `checks.rs` calls `written_expression` from `report`, and `report.rs` calls `read_checks`, `refs_of`, `refs_of_checks` and `refs_read` from `checks`.
- `checks` and `reading` use each other: `checks.rs` takes a `Reading`, and `reading.rs` calls `crate::checks::read_checks`.
- `checks` and `reading` call up into `ops`: `checks.rs` uses `ops::Check` and `ops::any_of::AnyOf` at the top and `ops::lists::walked` in `refs_walked`, and `reading.rs` uses `ops::Check`.
- `lower` and `ops` use each other: `lower.rs` uses `ops::Check`, `ops::walk`, `ops::tally` and calls `for_line::lower_for`, `compare::lower_phrase` and `lists::lower_phrase`, and the evaluators use `lower::Scope`, `lower::in_place` and `lower::walk_too_long`. `ops/tally.rs` also uses `lower::UNSUPPORTED_SUFFIX` and `lower::lower_tally_condition`.
- `subjects` uses `report` for the row builders (`row_of`, `no_subjects`, `min_subjects_row` and others), and `report` uses `ops`.
- `ops` calls up into `subjects`: `ops/any_of.rs` calls `crate::subjects::merge_inputs`, and `ops/for_line.rs` calls `crate::subjects::order`.
- Inside `ops`, the evaluators call helpers in `ops/message.rs` (`isnt`, `prefixed`, `root_fault`, `root_flaw` and others), and `message.rs` calls back into `lists`, `tally`, `compare` and `run_full`, so the helpers sit on top of the evaluators and underneath them at once.
