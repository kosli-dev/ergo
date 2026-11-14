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

echo "no-inline-tests.sh fails on a test module after three attribute lines"
printf 'fn a() {}\n\n#[cfg(test)]\n#[allow(dead_code)]\n#[allow(unused)]\n\n#[allow(clippy::all)]\nmod x {\n}\n' > src/inline_long.rs
check_fails "a test module after a long run of attributes" src/inline_long.rs "src/inline_long.rs:8"

echo "no-inline-tests.sh fails on a bare test function"
printf 'fn a() {}\n\n#[test]\nfn t() {}\n' > src/inline_bare.rs
check_fails "a bare test function" src/inline_bare.rs "src/inline_bare.rs:3"

echo "no-inline-tests.sh fails on an async test function"
printf '#[tokio::test]\nasync fn t() {}\n' > src/inline_async.rs
check_fails "a tokio test function" src/inline_async.rs "src/inline_async.rs:1"

echo "no-inline-tests.sh fails on a wasm_bindgen_test function"
printf '    #[wasm_bindgen_test]\n    fn t() {}\n' > src/inline_wasm.rs
check_fails "a wasm_bindgen_test function" src/inline_wasm.rs "src/inline_wasm.rs:1"

echo "no-inline-tests.sh passes on attributes that only end in the letters test"
printf '#[attest]\n#[contest(x)]\n#[latest]\n#[my::latest]\n#[derive(Debug, PartialEq)]\n#[should_panic]\nfn a() {}\n' > src/lookalikes.rs
git add .
sh "$script"
git rm --quiet --cached src/lookalikes.rs
/bin/rm -f src/lookalikes.rs

echo "no-inline-tests.sh fails on a test attribute with arguments, spaces or a comment after it"
printf '#[tokio::test(flavor = "x")]\nasync fn t() {}\n' > src/inline_args.rs
check_fails "a tokio test with arguments" src/inline_args.rs "src/inline_args.rs:1"
printf '#[test]   \nfn t() {}\n' > src/inline_spaces.rs
check_fails "a test attribute with trailing spaces" src/inline_spaces.rs "src/inline_spaces.rs:1"
printf '#[test] // c\nfn t() {}\n' > src/inline_comment.rs
check_fails "a test attribute with a comment" src/inline_comment.rs "src/inline_comment.rs:1"

echo "no-inline-tests.sh fails on a cfg_attr that adds a test attribute"
printf '#[cfg_attr(test, test)]\nfn t() {}\n' > src/inline_cfg_attr.rs
check_fails "a cfg_attr test" src/inline_cfg_attr.rs "src/inline_cfg_attr.rs:1"

echo "no-inline-tests.sh fails on a test module after a doc comment"
printf '#[cfg(test)]\n/// doc\n//! inner\n// plain\nmod x {\n}\n' > src/inline_doc.rs
check_fails "a test module after doc comments" src/inline_doc.rs "src/inline_doc.rs:5"

echo "no-inline-tests.sh passes on a module after a function that followed a cfg(test) and a doc comment"
printf '#[cfg(test)]\n/// doc\nfn helper() {}\n\nmod helpers {\n}\n' > src/doc_then_fn.rs
git add .
sh "$script"
git rm --quiet --cached src/doc_then_fn.rs
/bin/rm -f src/doc_then_fn.rs

echo "no-inline-tests.sh passes on the word test in a comment and in a cfg attribute"
printf '/// #[test]\n// #[test]\n#[cfg(test)]\nfn only() {}\n' > src/comments.rs
sh "$script"

echo "no-inline-tests.sh passes on test functions in a tests folder and in a tests.rs file"
mkdir -p tests
printf '#[test]\nfn t() {}\n\nmod helpers {\n}\n' > tests/api.rs
sh "$script"

echo "no-inline-tests.sh passes on a tests.rs file with a tests module and test function"
printf '#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {}\n}\n' > src/tests.rs
git add .
sh "$script"

echo "no-inline-tests.sh fails on the same content in another file"
printf '#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {}\n}\n' > src/other.rs
check_fails "a test module in other.rs" src/other.rs "src/other.rs:2"

echo "no-inline-tests.sh passes on a repository with no Rust files and on one with only tests.rs files"
empty=$(mktemp -d)
trap 'rm -rf "$dir" "$empty"' EXIT
cd "$empty"
git init --quiet
sh "$script"
mkdir src
printf '#[test]\nfn t() {}\n' > src/tests.rs
git add .
sh "$script"

echo "no-inline-tests.sh still fails with a message on a repository with a tests.rs file and a bad file"
printf '#[test]\nfn t() {}\n' > src/bad.rs
check_fails "a bad file next to tests.rs" src/bad.rs "src/bad.rs:1"

echo "no-inline-tests.sh says what is wrong outside a git repository"
outside=$(mktemp -d)
trap 'rm -rf "$dir" "$empty" "$outside"' EXIT
cd "$outside"
if out=$(GIT_CEILING_DIRECTORIES=$(dirname "$outside") sh "$script" 2>&1); then
  echo "no-inline-tests.sh should fail outside a git repository, and passed" >&2
  exit 1
fi
case $out in
  *"must run inside a git repository"*) ;;
  *)
    echo "no-inline-tests.sh should say it must run inside a git repository, and said: $out" >&2
    exit 1
    ;;
esac
