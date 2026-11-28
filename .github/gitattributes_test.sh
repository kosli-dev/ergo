#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
dir=$(mktemp -d)
trap '/bin/rm -rf "$dir"' EXIT

echo ".gitattributes sends engines/rust/known-failures.txt to the sorted-set merge driver and leaves the changelogs alone"
grep -qx 'engines/rust/known-failures.txt merge=sorted-set' "$repo_root/.gitattributes"
if grep -q 'CHANGELOG' "$repo_root/.gitattributes"; then
  echo ".gitattributes should not name a changelog" >&2
  exit 1
fi
check_attr=$(git -C "$repo_root" check-attr merge engines/rust/known-failures.txt)
case $check_attr in
  *"merge: sorted-set") ;;
  *) echo "git check-attr says: $check_attr" >&2; exit 1 ;;
esac

echo ".gitattributes keeps shell scripts on LF line ends, so a Windows checkout can run them"
check_attr=$(git -C "$repo_root" check-attr eol .github/release-version-check.sh)
case $check_attr in
  *"eol: lf") ;;
  *) echo "git check-attr says: $check_attr" >&2; exit 1 ;;
esac

repo=$dir/repo
mkdir -p "$repo/.github" "$repo/engines/rust"
cp "$repo_root/.gitattributes" "$repo/.gitattributes"
cp "$here/merge-sorted-set.py" "$here/setup-merge-drivers.sh" "$repo/.github/"
cd "$repo"
git init --quiet -b main
git config user.email t@example.com
git config user.name t
sh .github/setup-merge-drivers.sh
file=engines/rust/known-failures.txt
printf 'a\nb\nc\nd\ne\nf\ng\n' > "$file"
git add .
git commit --quiet -m base

branch() {
  git checkout --quiet main
  git checkout --quiet -b "$1"
}
change() {
  case $1 in
    delete) grep -vx "$2" "$file" > "$file.new"; /bin/mv -f "$file.new" "$file" ;;
    add) printf '%s\n' "$2" >> "$file"; LC_ALL=C sort -o "$file" "$file" ;;
  esac
  git commit --quiet -am "$1 $2"
}
merged() {
  git merge --quiet "$1" -m merge >/dev/null 2>&1 || {
    echo "merge conflicted: $(cat "$file" | tr '\n' ' ')" >&2
    exit 1
  }
  got=$(tr '\n' ' ' < "$file")
  if [ "$got" != "$2" ]; then
    echo "wanted '$2' and got '$got'" >&2
    exit 1
  fi
}

echo "two branches adding different lines in the same place merge with both lines, sorted"
branch add1; change add c1
branch add2; change add c2
merged add1 "a b c c1 c2 d e f g "

echo "two branches deleting adjacent lines merge with both gone"
branch del1; change delete c
branch del2; change delete d
merged del1 "a b e f g "

echo "one branch deleting a line and one adding next to it merge with the line gone and the new one in"
branch mix1; change delete d
branch mix2; change add d2
merged mix1 "a b c d2 e f g "

echo "both branches adding the same line keep it once"
branch same1; change add x
branch same2; change add x
merged same1 "a b c d e f g x "

echo "both branches deleting the same line and adding another merge with that line gone"
branch both1; change delete b
branch both2; change delete b; change add h
merged both1 "a c d e f g h "
