---
title: "Ergo - An open language for explainable policies."

hero:
  title: An open language for explainable policies.
  lede: ==ergo== is an open source language for writing policies that explain themselves. Instead of a yes or no, every decision returns an audit report of what was checked, and why it passed or failed. Run your policies on Open Policy Agent with `ergo.rego`, or with the `ergo` CLI.
  primary: Get started
  secondary: GitHub
  verdict: d-3 is out of scope. d-2 was never approved... and the report says so.
  fromto:
    label: The same policy written in Rego and in Ergo, and what each returns
    steps: [Rego policy, Rego result, Ergo policy, evaluation, report]
    # Set to true to bring back the Rego policy and Rego result steps.
    show_rego: false
    examples:
      - key: deploy
        holds: [6000, 5800, 6500, 6000, 8500]
        label: Deploy approval
        input_caption: Three deployments. d-2 has no approved_by field at all, and d-3 is in staging.
        rego_caption: Rego says no. Nothing about d-1, or why d-3 was skipped.
        ergo_caption: d-3 is out of scope. d-2 was never approved... and the report says so.
      - key: review
        holds: [6400, 6200, 6500, 6000, 8500]
        label: Four eyes
        input_caption: Three pull requests. PR 2 was approved only by its author, and PR 3 has no author recorded.
        rego_caption: Two failures, one message. Which is which?
        ergo_caption: PR 2 was only approved by its author. PR 3 has no author recorded. Different problems, different fixes.
      - key: expenses
        holds: [6000, 5800, 6500, 6000, 8500]
        label: Expenses
        input_caption: Three meal expenses. e-2 is over the €50 limit, and e-3 has no receipt.
        ergo_caption: e-2 costs too much and e-3 has no receipt, so whoever claimed them knows exactly what to fix.

problem:
  title: A decision nobody can inspect
  muted: isn't evidence.
  lede: With Rego you can block a deployment, but you can't show later why. When you write policies with ==ergo== you have records of why decisions were made.
  body: When a decision matters, someone else has to be able to check that the policy behaved as it should. A yes or no can't be validated. You don't just tell an auditor, a customer or a colleague the decision. You hand over the workings.
  without:
    label: "**Rego** provides decisions"
    note: Useful. But why was it false?
  with:
    label: With **Ergo** you get explanations
    note: Same decision. Now you can see why.
    out_of_scope: (out of scope, recorded)

declaration:
  marks: {subjects: 1, from: 1, whose: 2, identified_by: 1, subject: 3, checks: 3}
  title: Write the policy.
  muted: Not the sorcery.
  notes_title: Defined in YAML or Rego
  notes_intro: Write the policy as a YAML file or as a Rego object. ==ergo== reads both the same way and gives the same report.
  notes:
    - title: Define the subjects
      body: "Each subject gets a name. `from` says where the subjects are in the input, and `identified_by` names the field that tells them apart."
    - title: Filter the scope
      body: "`whose` keeps only the subjects the policy is about, here the production deployments. The rest are recorded, not dropped."
    - title: Test the values
      body: "A requirement names its subject, and its `checks` are the rules each one must pass, each written as a sentence. ==ergo== does the looping, the evaluation and the report."

shape:
  title: One report format.
  muted: Every policy.
  lede: "A deployment policy. An expense policy. A loan eligibility policy. Different checks, same evidence: one row per subject and check. Passing and failing rows have the same fields."
  fields:
    - name: requirement
      body: Which requirement produced the row.
    - name: subject
      body: The thing that was judged, with its type and id.
    - name: check
      body: The rule that ran.
    - name: inputs
      body: The values the check actually read.
    - name: passed
      class: t
      body: The result. Always `true` or `false`.
    - name: cause
      body: Why it reached that result.
  aside: Same policy + same input = the same report, byte for byte. Hash it. Diff it. Store it.

manifesto:
  muted:
    - Nothing disappears.
    - Nothing is implied.
  bright:
    - Everything is reproducible.
    - Everything has a reason.

architecture:
  title: One language.
  muted: Two engines.
  lede: Two engines can run your policies, and both follow the same spec. `ergo.rego` runs on Open Policy Agent, so it runs wherever OPA does. The Rust engine runs in the `ergo` CLI and in the playground in your browser, and is still experimental. Both pass every case in the spec.
  engines:
    - name: ergo.rego
      runs: runs on OPA
      opa: true
    - name: Rust engine
      note: (experimental)
      runs: runs in the ergo CLI and the playground

vocabulary:
  title: Auditor says why
  muted: Computer says ==ergo==
  lede: "Learn how to write self-explaining automated policies in this tutorial:"
  link: The bakery example

start:
  title: No lock-in.
  steps:
    - title: Write a policy
      body: Say what you're judging, what's in scope and what must hold, in `policy.yaml`.
      policy: true
    - title: Pick an engine
      body: Either one runs the same policy.
      options:
        - engine: OPA with ergo.rego
          body: Copy it next to the policy, with a few lines of Rego that hand the policy to it. [Get started](/docs/getting-started/) shows how to run it.
          code: |-
            policy/
              policy.yaml
              ergo.rego
              deploy.rego
        - engine: ergo CLI
          body: Build it with Cargo, or download it for Linux (x86_64) or macOS (arm64) from the [latest release of the CLI](https://github.com/kosli-dev/ergo/releases?q=rust-v).
          code: cargo install --locked ergo-policy-cli
    - title: Read the report
      body: Every check, with what it read and why it passed or failed.
      options:
        - engine: OPA with ergo.rego
          body: Ask OPA for the report, or for `data.deploy.violations` to see only what failed.
          code: |-
            opa eval -d policy -i deployments.json \
              'data.deploy.report'
        - engine: ergo CLI
          body: Run `ergo report`, or `ergo violations` to see only what failed.
          code: |-
            ergo report --policy policy/policy.yaml \
              --input deployments.json
  editor:
    lead: "Or try it in the browser, with nothing to install:"
    link: the playground
    note: (experimental)
  primary: Read the walkthrough
  secondary: GitHub

name:
  lede: Therefore. As a result. A conclusion that comes with its premises.
  body: Not *computer says no*. Here is the decision, and here is what produced it.

close:
  lead: Rego says no. ==ergo== says why.
  title: Show the working.
  primary: GitHub
  secondary: Get started
---
