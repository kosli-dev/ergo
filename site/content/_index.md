---
title: "ergo - Explainable controls that run on Open Policy Agent and Rego."

hero:
  title: Explainable controls that run on Open Policy Agent and Rego.
  lede: ==ergo== is an open source language for defining explainable controls. Instead of a binary result, every decision returns an audit report of what was checked, and why it passed or failed.
  primary: Get started
  secondary: GitHub
  verdict: d-3 is out of scope. d-2 was never approved... and the report says so.

problem:
  title: A decision nobody can inspect
  muted: isn't a control.
  lede: With Rego you can block a deployment, but you can't show later why. When you define controls with ==ergo== you have records of why decisions were made.
  body: In regulated settings, someone else has to be able to check that a control behaved as it should. A yes or no can't be validated. You don't just tell the auditor the decision. You hand over the workings.
  without:
    label: Rego provides decisions
    note: Useful. But why was it false?
  with:
    label: With ==ergo== you get explanations
    note: Same decision. Now you can see why.

declaration:
  title: Write the control.
  muted: Not the sorcery.
  switch: Show the requirement as
  formats:
    - key: yaml
      label: YAML
    - key: rego
      label: Rego
  notes_title: Defined in YAML or Rego
  notes_intro: Write the requirement as a YAML file or as a Rego object. ==ergo== reads both the same way and gives the same report.
  notes:
    - title: Define the subjects
      body: "`subject_type`, `from` and `id` say what the subjects are and where to find them."
    - title: Filter the scope
      body: "`applies_to` keeps only the subjects this control is about. The rest are recorded, not dropped."
    - title: Test the values
      body: "`checks` are the rules each subject must pass. ==ergo== does the looping, the evaluation and the report."

shape:
  title: One report format.
  muted: Every control.
  lede: "A deployment control. A code-review control. A vulnerability control. Different policy, same evidence: one row per subject and check. Passing and failing rows have the same fields."
  fields:
    - name: requirement
      body: Which control produced the row.
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
  lede: ==ergo== doesn't replace OPA. Copy a single rego file into your policies. The control is expressed as yaml, JSON or rego and ==ergo== provides a single evaluation and reporting model.

vocabulary:
  title: Readable by machines.
  muted: Readable by people.
  lede: The vocabulary is small on purpose. Every check gets a plain-language expression, like `approved_by is a non-empty string`, rendered from the requirement itself. Controls are data, so they can be validated, diffed and tested like code.
  link: Every field, operator and cause

start:
  title: One file. No lock-in.
  steps:
    - title: Copy the library
      body: Copy `ergo.rego` next to your policies. That's the install.
      code: |-
        policy/
          ergo.rego
    - title: Write a requirement
      body: Say what you're judging, what's in scope and what must hold.
      code: report := ergo.report(input, data.requirements)
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
  title: Show the working.
  primary: GitHub
  secondary: Get started
---
