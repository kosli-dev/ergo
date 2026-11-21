#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/body-facts.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

printf '## Rust report changes\n\n6 case reports changed between base and the working tree.\n\n- t 1-4\n- u 1, 3\n\nPassing cases whose report changed: 4 (information only).\n' > "$dir/reports-changed.md"
printf '## Rust report changes\n\nNo case report changed between base and the working tree.\n' > "$dir/reports-same.md"
printf 'CASES THAT PASSED ON base AND FAIL OR ARE GONE NOW: 2\n- t / g / d\n- w / g / v (gone)\n\n## Rust report changes\n\n1 case report changed between base and the working tree.\n' > "$dir/reports-one.md"
printf 'CASES THAT PASSED ON abc1234 AND FAIL OR ARE GONE NOW: 3\n- t / g / d\n\ncargo test exited with 101 on the working tree.\n\n## Rust report changes\n\nNo case report changed between abc1234 and the working tree.\n' > "$dir/reports-cargo-failed.md"
printf 'cargo test exited with 2 on the working tree.\n\n## Rust report changes\n\nNo case report changed between abc1234 and the working tree.\n' > "$dir/reports-cargo-failed-plain.md"
printf 'PAIRS THAT MOVED AWAY FROM REGO OR FROM THEIR WANT: 1\n\n- apart: p -> z\n\n## Pairs\n\n1 of 5 pairs differ between Rego and Rust.\n\nPairs that say their want message: Rego 3 of 3, Rust 3 of 3.\n\nRust output changed on 3 pairs between base and the working tree.\n\n- apart: p -> z (Rust equals Rego: no)\n' > "$dir/pairs-changed.md"
printf '## Pairs\n\n1 of 5 pairs differ between Rego and Rust.\n\nNo pair'"'"'s Rust output changed between base and the working tree.\n' > "$dir/pairs-same.md"
printf '## Pairs\n\n1 of 5 pairs differ between Rego and Rust.\n\nRust output changed on 1 pair between base and the working tree.\n' > "$dir/pairs-one.md"
printf 'No file under engines/rust, engines/rego or spec changed.\n' > "$dir/pairs-skipped.md"

run() {
  BODY_FACTS_BODY=$1 sh "$script" "$2" "$3"
}

expect_in() {
  case $2 in
    *"$1"*) ;;
    *)
      echo "expected \"$1\" in the output, got: $2" >&2
      exit 1
      ;;
  esac
}

expect_not_in() {
  case $2 in
    *"$1"*)
      echo "did not expect \"$1\" in the output, got: $2" >&2
      exit 1
      ;;
  esac
}

echo "body-facts.sh prints the counts to paste"
out=$(run "text" "$dir/reports-changed.md" "$dir/pairs-changed.md")
expect_in "Rust case reports changed: 6" "$out"
expect_in "Pairs whose Rust output changed: 3, of them moved away from Rego or their want: 1" "$out"
expect_in "Changes the report: 6 Rust case reports changed, Rust output changed on 3 pairs (1 moved away from Rego or its want)." "$out"

echo "body-facts.sh counts one report and no pair"
out=$(run "text" "$dir/reports-one.md" "$dir/pairs-same.md")
expect_in "Rust case reports changed: 1" "$out"
expect_in "Changes the report: 1 Rust case report changed." "$out"

echo "body-facts.sh warns when reports changed and the body has no Changes the report line"
out=$(run "Fixes a thing." "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING: reports or pairs changed, and the body has no line starting with \`Changes the report:\`." "$out"

echo "body-facts.sh warns when only pairs changed"
out=$(run "Fixes a thing." "$dir/reports-same.md" "$dir/pairs-changed.md")
expect_in "WARNING" "$out"

echo "body-facts.sh does not warn when the body has the line, even with a CR at the end"
out=$(run "$(printf 'Fixes a thing.\n\nChanges the report: yes, 6.\r\n')" "$dir/reports-changed.md" "$dir/pairs-changed.md")
expect_not_in "WARNING" "$out"
expect_not_in "NOTE" "$out"

echo "body-facts.sh needs the line at the start of a line"
out=$(run "We say Changes the report: no." "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"

echo "body-facts.sh notes a Changes the report line when nothing changed"
out=$(run "Changes the report: yes." "$dir/reports-same.md" "$dir/pairs-same.md")
expect_in "NOTE: the body has a line starting with \`Changes the report:\`, and no report or pair changed." "$out"
expect_not_in "WARNING" "$out"

echo "body-facts.sh has no warning or note when nothing changed and the body has no line"
out=$(run "Fixes a thing." "$dir/reports-same.md" "$dir/pairs-skipped.md")
expect_not_in "WARNING" "$out"
expect_not_in "NOTE" "$out"
expect_in "Rust case reports changed: 0" "$out"
expect_in "Pairs whose Rust output changed: 0" "$out"

echo "body-facts.sh says when it cannot read a count and does not warn on that alone"
out=$(run "Fixes a thing." "$dir/missing.md" "$dir/pairs-same.md")
expect_in "Rust case reports changed: unknown" "$out"
expect_not_in "WARNING" "$out"

echo "body-facts.sh warns on a known change even when the other count is unknown"
out=$(run "Fixes a thing." "$dir/missing.md" "$dir/pairs-changed.md")
expect_in "WARNING" "$out"

echo "body-facts.sh does not call the reports 0 when cargo failed, and warns"
out=$(run "Fixes a thing." "$dir/reports-cargo-failed.md" "$dir/pairs-same.md")
expect_in "Rust case reports changed: unknown" "$out"
expect_in "WARNING: cargo test exited with 101 on the working tree." "$out"
expect_in "the report counts could not be read because cargo failed" "$out"
expect_in "- Cases that passed and now fail or are gone: 3" "$out"
out=$(run "Fixes a thing." "$dir/reports-cargo-failed-plain.md" "$dir/pairs-same.md")
expect_in "Rust case reports changed: unknown" "$out"
expect_in "WARNING: cargo test exited with 2 on the working tree." "$out"
expect_not_in "Cases that passed and now fail" "$out"

echo "body-facts.sh warnings say the body is read at the last push"
out=$(run "Fixes a thing." "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "(the body is read at the last push: push or re-run after editing it)" "$out"
out=$(run "Fixes a thing." "$dir/reports-cargo-failed.md" "$dir/pairs-same.md")
expect_in "tree. So the report counts could not be read because cargo failed (the body is read at the last push: push or re-run after editing it)." "$out"

echo "body-facts.sh ignores a Changes the report line inside a code fence"
out=$(run "$(printf 'Example:\n\n```\nChanges the report: yes.\n```\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"
out=$(run "$(printf 'Example:\n\n~~~\nChanges the report: yes.\n~~~\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"
out=$(run "$(printf '```\ncode\n```\n\nChanges the report: yes.\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_not_in "WARNING" "$out"

echo "body-facts.sh ignores an unfilled Changes the report placeholder"
out=$(run "$(printf 'Changes the report: <!-- say what changed -->\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"
out=$(run "$(printf 'Changes the report:   \n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"
out=$(run "$(printf 'Changes the report: <!-- x --> yes.\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_not_in "WARNING" "$out"
out=$(run "$(printf 'Changes the report: yes.\nChanges the report: <!-- x -->\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_not_in "WARNING" "$out"

echo "body-facts.sh reads the body from a file"
printf 'Changes the report: yes.\n' > "$dir/body.md"
out=$(BODY_FACTS_BODY_FILE=$dir/body.md sh "$script" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_not_in "WARNING" "$out"

echo "body-facts.sh treats an empty body as having no line"
out=$(BODY_FACTS_BODY= sh "$script" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_in "WARNING" "$out"

printf '## Rust report changes\n\n6 case reports changed between base and the working tree.\n\n## Known failures\n\nknown-failures.txt had 1 line and has 3 now.\n' > "$dir/reports-known.md"
printf '## Rust report changes\n\nNo case report changed between base and the working tree.\n\n## Known failures\n\nknown-failures.txt had 2 lines and has 2 now.\n' > "$dir/reports-known-same.md"
printf 'garbled\n' > "$dir/garbled.md"

fails_with() {
  if out=$(BODY_FACTS_BODY=$1 sh "$script" "$2" "$3" 2>&1); then
    echo "expected a failure for: $1, got: $out" >&2
    exit 1
  fi
}

echo "body-facts.sh passes when the numbers in the body match"
body=$(printf 'Changes the report: 6 Rust case reports changed, Rust output changed on 3 pairs.\n\nknown-failures.txt had 1 line and has 3 now.\n\n1 of 5 pairs differ between Rego and Rust.\n\nPairs that say their want message: Rego 3 of 3, Rust 3 of 3.\n')
out=$(run "$body" "$dir/reports-known.md" "$dir/pairs-changed.md")
expect_not_in "MISMATCH" "$out"
expect_in "Checked 5 numbers" "$out"

echo "body-facts.sh fails and names each case report count that differs"
fails_with "Changes the report: 7 Rust case reports changed." "$dir/reports-changed.md" "$dir/pairs-same.md"
expect_in "MISMATCH: the body says 7 case reports changed, the facts say 6" "$out"

echo "body-facts.sh fails on a pair count that differs"
fails_with "Rust output changed on 4 pairs." "$dir/reports-same.md" "$dir/pairs-changed.md"
expect_in "MISMATCH: the body says Rust output changed on 4 pairs, the facts say 3" "$out"

echo "body-facts.sh fails on the known failures line and names both numbers"
fails_with "known-failures.txt had 1 line and has 4 now." "$dir/reports-known.md" "$dir/pairs-same.md"
expect_in "MISMATCH: the body says known-failures.txt had 1 and has 4, the facts say had 1 and has 3" "$out"

echo "body-facts.sh fails on the want and differ lines"
fails_with "Pairs that say their want message: Rego 3 of 3, Rust 2 of 3." "$dir/reports-same.md" "$dir/pairs-changed.md"
expect_in "MISMATCH" "$out"
fails_with "2 of 5 pairs differ between Rego and Rust." "$dir/reports-same.md" "$dir/pairs-changed.md"
expect_in "MISMATCH: the body says 2 of 5 pairs differ, the facts say 1 of 5" "$out"

echo "body-facts.sh lists every mismatch, not only the first"
fails_with "$(printf '9 Rust case reports changed\n\nRust output changed on 8 pairs\n')" "$dir/reports-changed.md" "$dir/pairs-changed.md"
expect_in "the body says 9 case reports changed" "$out"
expect_in "the body says Rust output changed on 8 pairs" "$out"

echo "body-facts.sh reads the singular forms"
out=$(run "$(printf 'Changes the report: 1 Rust case report changed, Rust output changed on 1 pair.\n\nknown-failures.txt had 1 line and has 1 now.\n')" "$dir/reports-one.md" "$dir/pairs-one.md")
expect_not_in "MISMATCH" "$out"
fails_with "1 Rust case report changed." "$dir/reports-changed.md" "$dir/pairs-same.md"

echo "body-facts.sh checks a zero against a file that says nothing changed"
out=$(run "0 case reports changed" "$dir/reports-same.md" "$dir/pairs-same.md")
expect_not_in "MISMATCH" "$out"
fails_with "0 case reports changed" "$dir/reports-changed.md" "$dir/pairs-same.md"

echo "body-facts.sh fails with unknown when a number is needed and the file cannot be read"
fails_with "Rust output changed on 3 pairs." "$dir/reports-same.md" "$dir/garbled.md"
expect_in "MISMATCH: the body says Rust output changed on 3 pairs, the facts say unknown" "$out"
fails_with "6 Rust case reports changed." "$dir/missing.md" "$dir/pairs-same.md"
expect_in "the facts say unknown" "$out"
fails_with "known-failures.txt had 1 line and has 3 now." "$dir/garbled.md" "$dir/pairs-same.md"
expect_in "the facts say unknown" "$out"

echo "body-facts.sh passes with a note when the body has no such line, even if the files cannot be read"
out=$(run "Fixes a thing. About 6 case reports are nice." "$dir/garbled.md" "$dir/missing.md")
expect_in "NOTE: no number in the body was checked" "$out"
expect_not_in "MISMATCH" "$out"

echo "body-facts.sh ignores these sentences inside a code fence"
out=$(run "$(printf '```\n7 Rust case reports changed\n```\n')" "$dir/reports-changed.md" "$dir/pairs-same.md")
expect_not_in "MISMATCH" "$out"
expect_in "NOTE: no number in the body was checked" "$out"

echo "body-facts.sh fails with usage on the wrong arguments"
if sh "$script" one > /dev/null 2>&1; then
  echo "body-facts.sh should fail with one argument" >&2
  exit 1
fi

echo "body-facts.sh tests passed"
