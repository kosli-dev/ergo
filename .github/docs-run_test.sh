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
