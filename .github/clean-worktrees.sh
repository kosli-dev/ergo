#!/bin/sh
set -eu
yes=0
for arg in "$@"; do
  case $arg in
    --yes) yes=1 ;;
    *)
      echo "usage: clean-worktrees.sh [--yes]" >&2
      exit 1
      ;;
  esac
done
base=${CLEAN_WORKTREES_BASE:-origin/main}
pr_state_cmd=${CLEAN_WORKTREES_PR_STATE_CMD:-}
here=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "clean-worktrees.sh must run inside a git repository" >&2
  exit 1
}
records=$(git worktree list --porcelain | awk '
  /^worktree / { if (path != "") print path "\t" branch; path = substr($0, 10); branch = "" }
  /^branch refs\/heads\// { branch = substr($0, 19) }
  END { if (path != "") print path "\t" branch }
')
main=$(printf '%s\n' "$records" | head -n 1 | cut -f 1)
tab=$(printf '\t')

pr_states() {
  if [ -n "$pr_state_cmd" ]; then
    "$pr_state_cmd" "$1"
  else
    gh pr list --head "$1" --state all --json state --jq '.[].state'
  fi
}

verb_remove="would remove"
verb_removed="would remove"
if [ "$yes" = 1 ]; then
  verb_removed="removed"
fi

remove_targets() {
  for target in $(find "$1" -maxdepth 4 -name target -type d -prune 2>/dev/null | sort); do
    if [ "$yes" = 1 ]; then
      /bin/rm -rf "$target"
      echo "removed target folder $target (build output)"
    else
      echo "$verb_remove target folder $target (build output)"
    fi
  done
}

printf '%s\n' "$records" | while IFS=$tab read -r path branch; do
  case $path in
    "$main"/.claude/worktrees/*) ;;
    *) continue ;;
  esac
  if [ "$path" = "$here" ]; then
    echo "kept: $path (the worktree this script runs in)"
    remove_targets "$path"
    continue
  fi
  if [ -z "$branch" ]; then
    echo "kept: no branch: $path"
    remove_targets "$path"
    continue
  fi
  if [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
    echo "kept: $path (branch $branch has uncommitted tracked changes)"
    remove_targets "$path"
    continue
  fi
  reason=
  if git merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
    reason="branch $branch is merged into $base"
  elif pr_states "$branch" | grep -Eq '^(MERGED|CLOSED)$'; then
    reason="the pull request of branch $branch is merged or closed"
  fi
  if [ -z "$reason" ]; then
    echo "kept: $path (branch $branch is not merged and has no merged or closed pull request)"
    remove_targets "$path"
    continue
  fi
  remove_targets "$path"
  if [ "$yes" = 1 ]; then
    if git worktree remove "$path" 2>/dev/null; then
      echo "removed worktree $path ($reason)"
    else
      echo "kept: $path (git refused to remove it, likely untracked files)"
    fi
  else
    echo "$verb_removed worktree $path ($reason)"
  fi
done
