#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/clean-worktrees.sh
dir=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$dir"' EXIT
repo=$dir/repo
mkdir -p "$repo"
cd "$repo"
git init --quiet -b main
git config user.email t@example.com
git config user.name t
echo one > file.txt
git add file.txt
git commit --quiet -m first
wt=$repo/.claude/worktrees
mkdir -p "$wt"

git worktree add --quiet -b merged-branch "$wt/merged"
git worktree add --quiet -b open-branch "$wt/open"
git -C "$wt/open" commit --quiet --allow-empty -m work
git worktree add --quiet -b dirty-branch "$wt/dirty"
echo two > "$wt/dirty/file.txt"
git worktree add --quiet --detach "$wt/detached"
git worktree add --quiet -b target-branch "$wt/withtarget"
git -C "$wt/withtarget" commit --quiet --allow-empty -m work
mkdir -p "$wt/withtarget/engines/rust/target/debug" "$wt/merged/target"
git worktree add --quiet -b space-branch "$wt/sp ace"
mkdir -p "$wt/sp ace/target"
git worktree add --quiet -b locked-branch "$wt/locked"
mkdir -p "$wt/locked/target"
git worktree lock "$wt/locked"
git worktree add --quiet -b feat/slash "$wt/slash"
git -C "$wt/slash" commit --quiet --allow-empty -m work
git worktree add --quiet -b failing-branch "$wt/failing"
git -C "$wt/failing" commit --quiet --allow-empty -m work
mkdir -p "$wt/failing/target"
echo x > "$wt/withtarget/engines/rust/target/debug/out"
git worktree add --quiet -b closed-branch "$wt/closed"
git -C "$wt/closed" commit --quiet --allow-empty -m work
git worktree add --quiet -b untracked-branch "$wt/untracked"
echo new > "$wt/untracked/scratch.txt"

printf '#!/bin/sh\ncase "$1" in closed-branch) echo CLOSED;; feat/slash) echo MERGED;; target-branch) echo OPEN;; open-branch) echo OPEN;; esac\n' > "$dir/pr-state"
chmod +x "$dir/pr-state"

printf '#!/bin/sh\ncase "$1" in failing-branch) exit 1;; *) "%s/pr-state" "$1";; esac\n' "$dir" > "$dir/pr-state-failing"
chmod +x "$dir/pr-state-failing"

run() {
  CLEAN_WORKTREES_BASE=main CLEAN_WORKTREES_PR_STATE_CMD="$dir/pr-state-failing" sh "$script" "$@"
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

expect_exists() {
  if [ ! -e "$1" ]; then
    echo "$1 should exist" >&2
    exit 1
  fi
}

expect_gone() {
  if [ -e "$1" ]; then
    echo "$1 should be gone" >&2
    exit 1
  fi
}

echo "clean-worktrees.sh without --yes says what it would remove and removes nothing"
out=$(run 2>&1)
expect_in "would remove worktree $wt/merged" "$out"
expect_in "would remove worktree $wt/closed" "$out"
expect_in "kept: $wt/open" "$out"
expect_in "kept: $wt/dirty" "$out"
expect_in "kept: no branch: $wt/detached" "$out"
expect_in "kept: $wt/withtarget" "$out"
expect_in "would remove target folder $wt/merged/target" "$out"
case $out in
  *"target folder $wt/withtarget"*)
    echo "target folders of kept worktrees should not be listed, got: $out" >&2
    exit 1
    ;;
esac
expect_in "would remove worktree $wt/slash" "$out"
expect_in "kept: $wt/failing" "$out"
expect_in "kept: $wt/locked (locked)" "$out"
count=$(printf '%s\n' "$out" | grep -cF "would remove target folder $wt/sp ace/target" || true)
if [ "$count" != 1 ]; then
  echo "expected the target folder of \"sp ace\" once, got $count in: $out" >&2
  exit 1
fi
expect_in "would remove worktree $wt/sp ace" "$out"
expect_exists "$wt/locked/target"
for name in merged open dirty detached withtarget closed untracked "sp ace" locked slash failing; do
  expect_exists "$wt/$name"
done
expect_exists "$wt/withtarget/engines/rust/target/debug/out"

echo "clean-worktrees.sh --yes removes merged and closed worktrees and target folders, and keeps the rest, including one git refuses to remove"
out=$(run --yes 2>&1)
expect_in "removed worktree $wt/merged" "$out"
expect_gone "$wt/merged"
expect_gone "$wt/closed"
expect_exists "$wt/untracked/scratch.txt"
expect_gone "$wt/sp ace"
expect_gone "$wt/slash"
expect_exists "$wt/withtarget/engines/rust/target/debug/out"
expect_exists "$wt/locked/target"
for name in open dirty detached withtarget locked failing; do
  expect_exists "$wt/$name"
done
expect_exists "$wt/dirty/file.txt"

echo "clean-worktrees.sh never deletes a branch"
for branch in merged-branch open-branch dirty-branch target-branch closed-branch untracked-branch space-branch locked-branch feat/slash failing-branch main; do
  git show-ref --verify --quiet "refs/heads/$branch" || {
    echo "branch $branch should still exist" >&2
    exit 1
  }
done

echo "clean-worktrees.sh leaves the main checkout alone"
expect_exists "$repo/file.txt"

echo "clean-worktrees.sh rejects an unknown flag"
if run --force >/dev/null 2>&1; then
  echo "clean-worktrees.sh should fail on --force, and passed" >&2
  exit 1
fi
