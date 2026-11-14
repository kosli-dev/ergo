#!/bin/sh
set -eu
script=$(cd "$(dirname "$0")" && pwd)/no-inline-tests.sh
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
git init --quiet
mkdir -p src/declared
printf 'fn one() {}\n\n#[cfg(test)]\nmod tests;\n' > src/declared.rs
printf '#[test]\nfn two() {}\n\nmod helpers {\n}\n' > src/declared/tests.rs
printf '#[cfg(test)]\npub fn only_in_tests() {}\n\n#[cfg(test)]\nfn also() {}\n' > src/helper.rs
git add .

echo "no-inline-tests.sh passes on a declared test module, a tests.rs file and test-only functions"
sh "$script"

check_fails() {
  name=$1
  file=$2
  expected=$3
  git add .
  if out=$(sh "$script" 2>&1); then
    echo "no-inline-tests.sh should fail on $name, and passed" >&2
    exit 1
  fi
  case $out in
    *"$expected"*) ;;
    *)
      echo "no-inline-tests.sh should say \"$expected\", and said: $out" >&2
      exit 1
      ;;
  esac
  git rm --quiet --cached "$file"
  /bin/rm -f "$file"
}

echo "no-inline-tests.sh fails on a test module with a body and names the file and line"
printf 'fn a() {}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {}\n}\n' > src/inline_two_lines.rs
check_fails "a test module on two lines" src/inline_two_lines.rs "src/inline_two_lines.rs:4"

echo "no-inline-tests.sh fails on the attribute and the module on one line"
printf 'fn a() {}\n\n#[cfg(test)] mod tests {\n}\n' > src/inline_one_line.rs
check_fails "a test module on one line" src/inline_one_line.rs "src/inline_one_line.rs:3"

echo "no-inline-tests.sh fails on a test module with another name"
printf 'fn a() {}\n\n#[cfg(test)]\nmod checks {\n}\n' > src/inline_checks.rs
check_fails "a test module named checks" src/inline_checks.rs "src/inline_checks.rs:4"

echo "no-inline-tests.sh fails on an indented test module"
printf 'mod outer {\n    #[cfg(test)]\n    mod tests {\n    }\n}\n' > src/inline_nested.rs
check_fails "an indented test module" src/inline_nested.rs "src/inline_nested.rs:3"

echo "no-inline-tests.sh passes again once they are gone"
sh "$script"
