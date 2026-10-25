#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"
rm -rf site/static/spec

for tag in $(git tag --list 'spec-v[0-9]*.[0-9]*'); do
  version=${tag#spec-v}
  printf '%s\n' "$version" | grep -qxE '[0-9]+\.[0-9]+' || continue
  dir=site/static/spec/$version
  mkdir -p "$dir"
  for name in policy report; do
    file=$name.schema.json
    git show "$tag:spec/$name/schema.json" > "$dir/$file"
    id=$(sed -n 's/^ *"\$id": *"\(.*\)",\{0,1\}$/\1/p' "$dir/$file" | head -n 1)
    case $id in
      */spec/"$version"/"$file") ;;
      *)
        echo "$tag: spec/$name/schema.json has \$id \"$id\", which should end in /spec/$version/$file" >&2
        rm -rf "$dir"
        exit 1
        ;;
    esac
  done
done
