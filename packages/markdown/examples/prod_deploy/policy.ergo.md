# Production deployment approval

Nothing reaches production without a second pair of eyes, and nothing goes out
on a red build. Both of these have bitten us; the second one twice.

Staging is deliberately out of scope. We want the trail to record that a staging
deployment was *seen and not judged*, rather than silently skipped — an empty
report and a report full of exemptions mean very different things to an auditor.

## Subjects

A **deployment** is each of `deployments`, identified by its `name`.

| Property    | Path                     |
| ----------- | ------------------------ |
| environment | `environment`            |
| approver    | `approved_by`            |
| CI checks   | `ci_checks`              |
| conclusion  | `ci_checks[].conclusion` |

## Every production deployment `prod_deploy`

In scope:

- `is_prod` — the **environment** must be `prod`.

Must hold:

- `approved` — the **approver** must be a non-empty string.
  A named approver signed off on the deployment.

- `ci_green` — every **CI check** must have a **conclusion** of `success`.
  Every CI check on the deployment passed.

A deployment with no approver and a deployment with an approver who failed to
sign off are not the same failure, and the report distinguishes them: the first
is recorded as `absent`, the second as `value`. The first is a gap in the
evidence and the second is a breach, and different people fix them.
