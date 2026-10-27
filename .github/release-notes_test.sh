#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/release-notes.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
base=https://github.com/kosli-dev/ergo/blob/spec-v0.2/spec/

cat > "$dir/CHANGELOG.md" <<'MD'
# Changelog

## 0.2

See [custom operators](OPEN.md#custom-operators) and [the syntax](syntax.md).
Read [the README](../README.md#install), [the site](https://ergo.kosli.com/x.md) and [a heading](#paths).
Not a link: syntax.md.

## 0.1

The first version, see [semantics](semantics.md#every-and-some).

## 0.0

## -1

See [the syntax](syntax.md "Syntax") and [the semantics](<semantics.md>).

MD

actual=$(sh "$script" "$dir/CHANGELOG.md" 0.2 "$base")
expected="
See [custom operators](${base}OPEN.md#custom-operators) and [the syntax](${base}syntax.md).
Read [the README](${base}../README.md#install), [the site](https://ergo.kosli.com/x.md) and [a heading](#paths).
Not a link: syntax.md."
if [ "$actual" != "$expected" ]; then
  printf 'release-notes.sh should print:\n%s\nand printed:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

actual=$(sh "$script" "$dir/CHANGELOG.md" 0.1 "$base")
expected="
The first version, see [semantics](${base}semantics.md#every-and-some)."
if [ "$actual" != "$expected" ]; then
  printf 'release-notes.sh should print:\n%s\nand printed:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

for version in 0.0 0.3; do
  if out=$(sh "$script" "$dir/CHANGELOG.md" "$version" "$base" 2>&1); then
    echo "release-notes.sh should fail for ## $version, and printed: $out" >&2
    exit 1
  fi
  case $out in
    *"has nothing under \"## $version\""*) ;;
    *)
      echo "release-notes.sh should say there's nothing under ## $version, and said: $out" >&2
      exit 1
      ;;
  esac
done
if out=$(sh "$script" "$dir/CHANGELOG.md" -1 "$base" 2>&1); then
  echo "release-notes.sh should fail on links it can't point at the tag, and printed: $out" >&2
  exit 1
fi
case $out in
  *"still link to .md files without the tag"*'See [the syntax](syntax.md "Syntax") and [the semantics](<semantics.md>).'*) ;;
  *)
    echo "release-notes.sh should name the links it left relative, and said: $out" >&2
    exit 1
    ;;
esac
echo "release-notes.sh takes a version's notes and links their .md files to the tag"
