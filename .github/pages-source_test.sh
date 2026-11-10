#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/pages-source.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init -q
git config commit.gpgsign false
git config core.hooksPath /dev/null
git config user.name test
git config user.email test@example.com
printf 'tested\n' > page
git add page
git commit -qm tested
tested=$(git rev-parse HEAD)
printf 'newer main\n' > page
git commit -qam newer
main=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$main"
git checkout --quiet --detach "$tested"
printf 'unmerged\n' > page
git commit -qam unmerged
unmerged=$(git rev-parse HEAD)
git checkout --quiet --detach "$main"
"$script" "$tested"
[ "$(git rev-parse HEAD)" = "$tested" ]
grep -qxF tested page
for rejected in "$unmerged" --help unknown 0000000000000000000000000000000000000000; do
  if "$script" "$rejected" > "$dir/out" 2>&1; then
    echo "pages-source.sh should reject $rejected" >&2
    exit 1
  fi
  [ "$(git rev-parse HEAD)" = "$tested" ]
done
printf '%s\n' 'pages-source.sh keeps the tested main commit and rejects unmerged or malformed revisions'
