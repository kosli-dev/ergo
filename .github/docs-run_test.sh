#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/docs-run.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"

mkdir bin
printf '#!/bin/sh\nshift\ncat "$@"\n' > bin/fake-opa
chmod +x bin/fake-opa
printf '_spec := "v9.9"\n' > ergo.rego
export DOCS_RUN_OPA="$dir/bin/fake-opa"
export DOCS_RUN_ERGO_REGO="$dir/ergo.rego"

fence='```'

group() {
  cat <<DOC
Some text.

<!-- ergo-run: g role=file path=policy.yaml $1 -->

${fence}yaml
ergo_spec: $2
a: 1
${fence}

<!-- ergo-run: g role=command -->

${fence}sh
opa eval policy.yaml
${fence}

<!-- ergo-run: g role=output -->

${fence}yaml
ergo_spec: v9.9
a: 1
${fence}
DOC
}

echo "docs-run.sh passes when the command prints what the output block shows"
group "" v9.9 > good.md
sh "$script" good.md > out.txt
case $(cat out.txt) in
  *"ok"*"g"*) ;;
  *)
    echo "docs-run.sh should say g is ok, and said: $(cat out.txt)" >&2
    exit 1
    ;;
esac

echo "docs-run.sh fails on a mismatch, names the group and shows the difference"
group "" v1.0 > bad.md
if sh "$script" bad.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a mismatch, and passed" >&2
  exit 1
fi
for want in "bad.md" "group g" "-ergo_spec: v9.9" "+ergo_spec: v1.0"; do
  if ! grep -qF -- "$want" out.txt; then
    echo "docs-run.sh should print $want, and said: $(cat out.txt)" >&2
    exit 1
  fi
done

echo "docs-run.sh with normalise=ergo_spec swaps the version line for the one ergo.rego follows"
group "normalise=ergo_spec" v1.0 > normalised.md
sh "$script" normalised.md > /dev/null

echo "docs-run.sh lists every mismatching group, not only the first"
{
  group "" v1.0 | sed 's/ergo-run: g /ergo-run: one /'
  group "" v2.0 | sed 's/ergo-run: g /ergo-run: two /'
} > two.md
if sh "$script" two.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on two mismatches, and passed" >&2
  exit 1
fi
for want in "one" "two"; do
  if ! grep -q "group $want" out.txt; then
    echo "docs-run.sh should name group $want, and said: $(cat out.txt)" >&2
    exit 1
  fi
done

echo "docs-run.sh joins the blocks of one group from different files"
group "" v9.9 > all.md
awk '/role=command/ {exit} {print}' all.md > first.md
awk '/role=command/ {f=1} f' all.md > second.md
sh "$script" first.md second.md > /dev/null

echo "docs-run.sh fails on a marker that isn't followed by a code block"
printf '<!-- ergo-run: g role=output -->\n\nplain text\n' > loose.md
if sh "$script" loose.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a marker with no code block, and passed" >&2
  exit 1
fi
grep -q "loose.md:1" out.txt || {
  echo "docs-run.sh should name loose.md:1, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh fails on a group with no output block"
awk '/role=output/ {exit} {print}' good.md > nooutput.md
if sh "$script" nooutput.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a group with no output, and passed" >&2
  exit 1
fi

echo "docs-run.sh fails on a file path that leaves the folder"
group "" v9.9 | sed 's|path=policy.yaml|path=../policy.yaml|' > escape.md
if sh "$script" escape.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a path with .., and passed" >&2
  exit 1
fi

echo "docs-run.sh fails on a role it doesn't know"
group "" v9.9 | sed 's|role=command|role=comand|' > role.md
if sh "$script" role.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on an unknown role, and passed" >&2
  exit 1
fi

echo "docs-run.sh passes on a file with no markers and says so"
printf 'Just text.\n' > plain.md
sh "$script" plain.md > out.txt
grep -q "no marked blocks" out.txt || {
  echo "docs-run.sh should say there are no marked blocks, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh reads a file with CRLF line endings"
group "" v9.9 | sed 's/$/\r/' > crlf.md
sh "$script" crlf.md > out.txt
case $(cat out.txt) in
  *"ok"*"g"*) ;;
  *)
    echo "docs-run.sh should say g is ok for a CRLF file, and said: $(cat out.txt)" >&2
    exit 1
    ;;
esac

echo "docs-run.sh fails on a CRLF file whose output differs"
group "" v1.0 | sed 's/$/\r/' > crlf-bad.md
if sh "$script" crlf-bad.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a CRLF file with a changed output, and passed" >&2
  exit 1
fi
grep -q "group g" out.txt || {
  echo "docs-run.sh should name group g, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh fails on a file with ergo-run text and no marker, naming each line"
printf 'Text.\n<!--ergo-run: g role=output -->\nMore.\n<!-- ergo_run: g role=output -->\n' > typo.md
if sh "$script" typo.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on text that is not a marker, and passed" >&2
  exit 1
fi
for want in "typo.md:2" "typo.md:4"; do
  if ! grep -qF -- "$want" out.txt; then
    echo "docs-run.sh should name $want, and said: $(cat out.txt)" >&2
    exit 1
  fi
done
if grep -q "no marked blocks" out.txt; then
  echo "docs-run.sh should not say there are no marked blocks for typo.md" >&2
  exit 1
fi

echo "docs-run.sh fails on an attribute with no equals sign, naming the word"
group "" v9.9 | sed 's|role=command|role=command bogus|' > bare.md
if sh "$script" bare.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on an attribute with no =, and passed" >&2
  exit 1
fi
grep -q "bogus" out.txt || {
  echo "docs-run.sh should name bogus, and said: $(cat out.txt)" >&2
  exit 1
}
if grep -q "^ok" out.txt; then
  echo "docs-run.sh should not print ok for group g with a bad attribute" >&2
  exit 1
fi

echo "docs-run.sh says a group name is used in more than one file"
group "" v9.9 > dup1.md
group "" v9.9 > dup2.md
if sh "$script" dup1.md dup2.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a group in two files, and passed" >&2
  exit 1
fi
for want in "used in more than one file" "dup1.md" "dup2.md"; do
  if ! grep -qF -- "$want" out.txt; then
    echo "docs-run.sh should print $want, and said: $(cat out.txt)" >&2
    exit 1
  fi
done

fake_release() {
  printf '_spec := "v8.8"\n' > release-ergo.rego
}

inline_group() {
  cat <<DOC
<!-- ergo-run: r role=file path=policy.yaml -->

${fence}yaml
a: 1
${fence}

<!-- ergo-run: r role=command $1 run=\`opa eval policy.yaml\` -->

<!-- ergo-run: r role=output -->

${fence}yaml
a: 1
${fence}
DOC
}

release_group() {
  cat <<DOC
<!-- ergo-run: r role=file path=policy.yaml -->

${fence}yaml
a: 1
${fence}

<!-- ergo-run: r role=command use=release -->

${fence}sh
opa eval policy.yaml
${fence}

<!-- ergo-run: r role=output -->

${fence}yaml
a: 1
${fence}
DOC
}

echo "docs-run.sh runs the command given in a run attribute when the group has no command block"
inline_group "" > inline.md
sh "$script" inline.md > out.txt
grep -q "^ok.*group r" out.txt || {
  echo "docs-run.sh should say r is ok for a run attribute, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh fails on a run attribute in a group that also has a command block"
{
  inline_group ""
  printf '\n<!-- ergo-run: r role=command -->\n\n%ssh\nopa eval policy.yaml\n%s\n' "$fence" "$fence"
} > both.md
if sh "$script" both.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a run attribute beside a command block, and passed" >&2
  exit 1
fi

echo "docs-run.sh fails on a run attribute that is not on a command marker"
inline_group "" | sed 's|role=command|role=output|' > inline-role.md
if sh "$script" inline-role.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on run outside a command marker, and passed" >&2
  exit 1
fi

echo "docs-run.sh skips a use=release group when no release file is given, and does not say ok"
release_group > release.md
env -u DOCS_RUN_RELEASE_ERGO_REGO -u DOCS_RUN_REQUIRE_RELEASE sh "$script" release.md > out.txt 2>&1
grep -q "^skip.*group r" out.txt || {
  echo "docs-run.sh should say skip for r, and said: $(cat out.txt)" >&2
  exit 1
}
if grep -q "^ok" out.txt; then
  echo "docs-run.sh should not say ok for a skipped group" >&2
  exit 1
fi

echo "docs-run.sh fails on a skipped group when DOCS_RUN_REQUIRE_RELEASE is 1"
if env -u DOCS_RUN_RELEASE_ERGO_REGO DOCS_RUN_REQUIRE_RELEASE=1 sh "$script" release.md > out.txt 2>&1; then
  echo "docs-run.sh should fail a skip when the release is required, and passed" >&2
  exit 1
fi

echo "docs-run.sh runs a use=release group with the release file"
fake_release
DOCS_RUN_RELEASE_ERGO_REGO="$dir/release-ergo.rego" sh "$script" release.md > out.txt
grep -q "^ok.*group r" out.txt || {
  echo "docs-run.sh should say r is ok with the release file, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh fails a use=release group when the release file is missing"
if DOCS_RUN_RELEASE_ERGO_REGO="$dir/nothing.rego" sh "$script" release.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a missing release file, and passed" >&2
  exit 1
fi

echo "docs-run.sh fails a use=release group whose output differs from the release's"
sed 's|^a: 1$|a: 2|' release.md | awk '/role=output/ {f=1} f && /^a: 2$/ {print "a: 3"; next} {print}' > release-bad.md
if DOCS_RUN_RELEASE_ERGO_REGO="$dir/release-ergo.rego" sh "$script" release-bad.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a release mismatch, and passed" >&2
  exit 1
fi

echo "docs-run.sh fails on a use value it doesn't know"
release_group | sed 's|use=release|use=latest|' > use.md
if sh "$script" use.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on an unknown use, and passed" >&2
  exit 1
fi

echo "docs-run.sh prints the release note when a use=release group fails"
if DOCS_RUN_RELEASE_NOTE="note about the release" DOCS_RUN_RELEASE_ERGO_REGO="$dir/release-ergo.rego" sh "$script" release-bad.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a release mismatch, and passed" >&2
  exit 1
fi
grep -qF 'note about the release' out.txt || {
  echo "docs-run.sh should print the release note on a release failure, and said: $(cat out.txt)" >&2
  exit 1
}

echo "docs-run.sh leaves the release note out when a group that is not use=release fails"
sed 's|use=release||' release-bad.md > plain-bad.md
if DOCS_RUN_RELEASE_NOTE="note about the release" sh "$script" plain-bad.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a mismatch, and passed" >&2
  exit 1
fi
if grep -qF 'note about the release' out.txt; then
  echo "docs-run.sh should not print the release note for a group that is not use=release" >&2
  exit 1
fi

echo "docs-run.sh says a run attribute cannot contain a backtick"
inline_group "" | sed 's|run=`opa eval policy.yaml`|run=`echo `date``|' > tick.md
if sh "$script" tick.md > out.txt 2>&1; then
  echo "docs-run.sh should fail on a backtick in run=, and passed" >&2
  exit 1
fi
grep -qF 'run= cannot contain a backtick' out.txt || {
  echo "docs-run.sh should say run= cannot contain a backtick, and said: $(cat out.txt)" >&2
  exit 1
}
