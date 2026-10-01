---
title: "ergo - Rego says no. ergo says why."

hero:
  title: Explainable controls that run on Open Policy Agent and Rego.
  lede: ==ergo== is an open source language for defining explainable controls. Instead of a binary result, every decision returns an audit report of what was checked, and why it passed or failed.
  primary: Get started
  secondary: GitHub
  verdict: d-3 is out of scope. d-2 was never approved... and the report says so.

problem:
  title: A decision nobody can inspect
  muted: isn't a control.
  lede: With Rego you can block a deployment, but you can't show later why. When you define controls with ==ergo== you have records of why it was blocked, or why the others weren't.
  body: In regulated settings, someone else has to be able to check that a control behaved as it should. A yes or no can't be validated. You don't just tell the auditor the decision. You hand over the workings.
  without:
    label: Rego provides decisions
    note: Useful. But why was it false?
  with:
    label: With ==ergo== you get explanations
    note: Same decision. Now you can see why.

declaration:
  title: Write the control.
  muted: Not the machinery.
  notes:
    - title: What you're judging
      body: "`subject_type`, `from` and `id` say what the subjects are and where to find them."
    - title: What's in scope
      body: "`applies_to` keeps only the subjects this control is about. The rest are recorded, not dropped."
    - title: What must hold
      body: "`checks` are the rules each subject must pass. ==ergo== does the looping, the evaluation and the report."

shape:
  title: One report shape.
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

causes:
  title: Failure isn't one state.
  lede: A missing field, a field set to `null` and a selector that matched nothing all read as `null`. They're different problems with different fixes. The `cause` tells them apart.
  items:
    - name: satisfied
      passes: true
      body: The check passed.
    - name: substituted
      passes: true
      body: The check failed, but its substitute passed.
    - name: ambiguous
      body: A selector matched more than one item.
    - name: unmatched
      body: A selector matched nothing, although the list was there.
    - name: absent
      body: A field the check reads isn't there.
    - name: "null"
      body: The field is there, but `null`.
    - name: value
      body: Everything was read fine. The values just don't pass.
  absent: The evidence was never recorded.
  value: The evidence exists, and it says no.
  tag: Different problem. Different owner. Different fix.

manifesto:
  lines:
    - Nothing disappears.
    - Nothing is implied.
    - Nothing is decorative.
    - Everything has a reason.
    - Everything has a state.
  intro: You didn't write the checks that start with <code class="sys">$</code>. ==ergo== adds them, so that whenever a requirement isn't met, at least one row explains why.
  checks:
    - name: $well_formed
      body: "The requirement itself makes sense: it has at least one check and a valid `require`."
    - name: $min_subjects
      body: At least one subject was found. A typo in `from` fails, instead of passing with nothing checked.
    - name: $applies
      body: Whether each subject was in scope. Out-of-scope subjects stay in the report, with the reason.

architecture:
  title: Rego underneath.
  muted: ==ergo== on top.
  lede: ==ergo== doesn't replace OPA. It's a single Rego file you copy into your policies. The control is expressed as data, and ==ergo== provides one evaluation and reporting model for all of them.

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
      code: report := ergo.report(input, requirements)
    - title: Read the report
      body: Ask OPA for the report, or just the violations.
      code: |-
        opa eval -d policy -i deployments.json \
          'data.deploy.report'
  primary: Read the walkthrough
  secondary: View ergo.rego

name:
  lede: Therefore. As a result. A conclusion that comes with its premises.
  body: Not *computer says no*. Here is the decision, and here is what produced it.

close:
  title: Show the working.
  primary: Fork ergo
  secondary: Get started
---
