---
title: "ergo - Explainable policies that run on Open Policy Agent and Rego."

hero:
  title: Explainable policies that run on Open Policy Agent and Rego.
  lede: ==ergo== is an open source language for writing explainable policies. Instead of a binary result, every decision returns an audit report of what was checked, and why it passed or failed.
  primary: Get started
  secondary: GitHub
  verdict: d-3 is out of scope. d-2 was never approved... and the report says so.
  fromto:
    label: The same policy written in Rego and in ergo, and what each returns
    steps: [Rego policy, Rego result, ergo policy, evaluation, report]
    # Set to true to bring back the Rego policy and Rego result steps.
    show_rego: false
    examples:
      - key: deploy
        label: Deploy approval
        input_caption: Three deployments. d-2 has no approved_by field at all, and d-3 is in staging.
        rego_caption: Rego says no. Nothing about d-1, or why d-3 was skipped.
        ergo_caption: d-3 is out of scope. d-2 was never approved... and the report says so.
      - key: review
        label: Four eyes
        input_caption: Three pull requests. PR 2 was approved only by its author, and PR 3 has no author recorded.
        rego_caption: Two failures, one message. Which is which?
        ergo_caption: PR 2 was only approved by its author. PR 3 has no author recorded. Different problems, different fixes.

problem:
  title: A decision nobody can inspect
  muted: isn't evidence.
  lede: With Rego you can block a deployment, but you can't show later why. When you write policies with ==ergo== you have records of why decisions were made.
  body: In regulated settings, someone else has to be able to check that a policy behaved as it should. A yes or no can't be validated. You don't just tell the auditor the decision. You hand over the workings.
  without:
    label: "**Rego** provides decisions"
    note: Useful. But why was it false?
  with:
    label: With **ergo** you get explanations
    note: Same decision. Now you can see why.

declaration:
  title: Write the policy.
  muted: Not the sorcery.
  notes_title: Defined in YAML or Rego
  notes_intro: Write the policy as a YAML file or as a Rego object. ==ergo== reads both the same way and gives the same report.
  notes:
    - title: Define the subjects
      body: "Each subject gets a name, and `from` and `id` say where to find them."
    - title: Filter the scope
      body: "`applies_to` keeps only the subjects the policy is about. The rest are recorded, not dropped."
    - title: Test the values
      body: "A requirement names its subject, and its `checks` are the rules each one must pass. ==ergo== does the looping, the evaluation and the report."

shape:
  title: One report format.
  muted: Every policy.
  lede: "A deployment policy. A code-review policy. A vulnerability policy. Different checks, same evidence: one row per subject and check. Passing and failing rows have the same fields."
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
  title: OPA is the engine.
  muted: ==ergo== is a rego library.
  lede: ==ergo== doesn't replace OPA. Copy a single rego file into your policies. The policy is expressed as YAML, JSON or rego and ==ergo== provides a single evaluation and reporting model.

vocabulary:
  title: Auditor says why
  muted: Computer says ==ergo==
  lede: "Learn how to write self-explaining automated policies in this tutorial:"
  link: The bakery example

start:
  title: One file. No lock-in.
  steps:
    - title: Copy the library
      body: Copy `ergo.rego` next to your policies. That's the install.
      code: |-
        policy/
          ergo.rego
    - title: Write a policy
      body: Say what you're judging, what's in scope and what must hold.
      code: |-
        report := ergo.report(input, {
          "subjects": data.subjects,
          "requirements": data.requirements,
        }, {})
    - title: Read the report
      body: Ask OPA for the report, or just the violations.
      code: |-
        opa eval -d policy -i deployments.json \
          'data.deploy.report'
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
