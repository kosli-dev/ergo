# ergo-sentences

Reads Ergo's check sentences, `for` lines, `from` lines and paths into a tree, and prints a tree back as a canonical sentence. It doesn't build reports, and its only dependency is `regex-syntax`, which it uses to check the patterns of `matches`, so an editor or a linter can use it without the engine. It builds for `wasm32-unknown-unknown`.

## What it gives

```rust,ignore
pub fn parse_check(line: &str) -> Result<Check, Vec<SyntaxError>>;
pub fn parse_for(line: &str) -> Result<ForLine, Vec<SyntaxError>>;
pub fn parse_from(line: &str) -> Result<FromLine, Vec<SyntaxError>>;
pub fn parse_path(line: &str) -> Result<Path, Vec<SyntaxError>>;

pub fn check_problems(check: &Check, aliases: &[&str]) -> Vec<String>;
pub fn for_problems(line: &ForLine, aliases: &[&str]) -> Vec<String>;
pub fn from_problems(line: &FromLine) -> Vec<String>;

pub fn print_check(check: &Check, aliases: &[&str]) -> String;
pub fn print_assertion(assertion: &Assertion, aliases: &[&str]) -> String;
pub fn print_for(line: &ForLine, aliases: &[&str]) -> String;
pub fn print_for_item(item: &ForItem, aliases: &[&str]) -> String;
pub fn print_from(line: &FromLine, aliases: &[&str], parents: &[&str]) -> String;
pub fn print_from_condition(condition: &FromCondition, aliases: &[&str], parents: &[&str]) -> String;
pub fn print_condition(condition: &Condition, aliases: &[&str]) -> String;
pub fn print_term(term: &Term, aliases: &[&str]) -> String;
pub fn print_left_term(term: &Term, aliases: &[&str], parents: &[&str]) -> String;
pub fn print_path(path: &Path, side: Side, aliases: &[&str]) -> String;

pub fn rust_pattern(pattern: &str) -> Option<String>;
```

## Using it

```rust
use ergo_sentences::{check_problems, parse_check, print_check};

let check = parse_check("approvals   is at least 2").unwrap();
assert!(check_problems(&check, &[]).is_empty());
assert_eq!(print_check(&check, &[]), "approvals is at least 2");

let wrong = parse_check("x is not null").unwrap();
assert_eq!(check_problems(&wrong, &[]), [r#""is not null" is written "exists""#]);

let errors = parse_check("x is \"a").unwrap_err();
assert_eq!(errors[0].message, "unclosed quote at column 6");
assert_eq!(errors[0].column, Some(6));
```

An editor reads each line with the `parse_` function for its kind, shows the `SyntaxError`s of a line that doesn't read, and the `_problems` of one that does.

- `parse_check`, `parse_for`, `parse_from` and `parse_path` read what [`spec/sentences.abnf`](../../../spec/sentences.abnf) allows and nothing else. Whitespace at both ends is dropped: every character with Unicode's `White_Space` property, as [sentence.ends](../../../spec/syntax.md#the-grammar) lists them, which is what Rust's `str::trim` drops. Between words only spaces count, so a tab there doesn't read. A bare first key is never a word of the grammar: write `.empty` for a field called `empty`. A quoted first key, like `"empty"`, is read as `.empty`, and prints that way.
- When the grammar allows two readings, the tree is the one `ergo.rego` picks, and a line that the first choice can't finish is read the other way.
- A failed read gives the messages `ergo.rego` gives for the same line, in its order, as `SyntaxError { column, message }`. `column` counts characters of the trimmed line from 1, and is only set when the message names a column. For a `from` line the columns count from the text after a leading `every`, as `ergo.rego` does.
- A `$<word>` other than `$params` and `$input` reads as a start or a reference, as `Start::Unknown` and `Reference::Unknown`, and the line is written wrong with `unknown name`. `parse_path` is the exception: it rejects a path that holds one. Keys and strings are decoded. Numbers, positions and bracket indexes keep their digits as written, so the caller decides what a number that is too big means.
- The printed sentence is canonical: one space between words, `equals` before a field and `is` before a value, `is in` before a path and `is one of` before values, numbers in plain decimal form, keys bare when they can be, strings in single quotes when they hold a backslash and nothing that needs escaping, and a bracket index that ends a path as `item N of`. A bracket index too big to be a list position, which is written wrong, prints as written.
- `aliases` are the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot when printed.
- `parents` are the names of a child subject's parents, for `print_from` and `print_from_condition`. On the left of a `whose`, a key named like a parent reads the item's own field, so it prints with a dot, like `b.kids whose .b.x equals v`. A `for` alias or a part named the same way doesn't get one there.

- A line that the grammar reads can still be written wrong. `check_problems`, `for_problems` and `from_problems` give the rules that need only the tree and, for the first two, the names in `aliases`, in `ergo.rego`'s words and sorted: `min above max`, `invalid pattern`, `<n> can't be a list position`, `number out of range: <n>`, `"is not null" is written "exists"`, the `takes a number`, `takes text` and `takes a time or a number` rules, the `within` rules, `unknown name $<word>` for a `$` name other than `$params` and `$input`, a misplaced `it`, `if any can't go with some`, a `for` alias that is a word or is given twice, `"sorted by"` reading an alias, and every `compared with itself`. `check_problems` and `for_problems` add `compared with itself`, for the names in `aliases` too, only when nothing else is wrong or every other problem is an `unknown name`, as `ergo.rego` does. Rules that need the policy's names, like an alias named like a subject, stay in the engine.
- When a line fails to read, the messages also hold the rules above that the loose reading of the line finds, as `ergo.rego` lists them.
- When a line is only a path, the message is what's wrong with the path, like `and is a word of the grammar: write .and`, or `nothing after the path at column N` when nothing is. A `from` line that reads as a `for` item says `an item starts with "every", "some" or a position`. Both are what `ergo.rego` says.
- Reading takes time in proportion to the length of the line, so a long pasted line doesn't stall an editor.
- `invalid pattern` follows RE2, which `ergo.rego` uses: `regex-syntax` does the parsing, with fixes for the places where RE2 differs (`\Q...\E`, a `{` that is not a repeat, flags other than `i`, `m`, `s` and `U`, a repeat of a repeat, and repeat counts above 1000). `rust_pattern` gives the pattern as the `regex` crate should read it, or `None` when RE2 rejects it, with RE2's ASCII-only `\d`, `\w`, `\s` and `\b`. The engine matches with it.

## The tree

Every type derives `Debug`, `Clone`, `PartialEq`, `Eq` and `Hash`, and `SyntaxError` is also a `std::error::Error` whose `Display` is its message. With the `serde` feature, which is off by default, they also derive `Serialize` and `Deserialize`.

| Type            | ABNF rule                       | Example                                                      |
| --------------- | ------------------------------- | ------------------------------------------------------------ |
| `Check`         | `check`                         | `a is 1 and b exists`                                        |
| `Assertion`     | `assertion`                     | `x is 1`, `every xs whose y is 1 exists`, `count of xs is 2` |
| `Quantifier`    | `quantifier`                    | `every`, `some`                                              |
| `Condition`     | `condition`                     | `y is 1`                                                     |
| `Left`          | `condition`                     | `y`, `count of ys`, `days elapsed from a to b`               |
| `Term`          | `term`                          | `y`, `1`, `count of ys`                                      |
| `Derived`       | `derived`, `derived-left`       | `sum of ys`, `count of ys whose z is 1`                      |
| `DerivedKind`   | `derived`                       | `count`, `sum`                                               |
| `Elapsed`       | `elapsed`                       | `hours elapsed from started to ended`                        |
| `Unit`          | `elapsed`                       | `seconds`, `minutes`, `hours`, `days`, `weeks`               |
| `Phrase`        | `phrase`                        | `is empty`, `is one of 1, 2`, `is 1 within 2`                |
| `Order`         | `order-phrase`                  | `is at least`, `is at most`, `is more than`, `is less than`  |
| `TimeOrder`     | `time-phrase`                   | `is before`, `is after`, `is on or after`, `is on or before` |
| `Type`          | `type`                          | `list`, `string`, `number`, `boolean`, `object`              |
| `Operand`       | `operand`                       | `1`, `y`, `y plus 1`                                         |
| `List`          | `list`                          | `1, 2`, `$params.allowed`                                    |
| `Value`         | `value`                         | `"a"`, `'a'`, `-1.5e3`, `true`, `false`, `null`              |
| `Path`          | `path`, `right-path`, `it-path` | `a.b[1]`, `item 2 of xs`, `.empty`                           |
| `Position`      | `position`                      | `item 3`, `item 2 from last`, `first`, `last`                |
| `Start`         | `start`, `plain-right`, `it`    | `it`, `$params`, `$input`, `name`, `.name`                   |
| `Step`          | `step`                          | `.key`, `named by k`, `[k]`, `["a b"]`, `[2]`                |
| `Reference`     | `reference`                     | `$params.k`, `$input.k`, `k`                                 |
| `ForLine`       | `for-line`                      | `every xs as x, last of ys as y`                             |
| `ForItem`       | `for-item`                      | `some xs whose a is 1 as x`, `last of ys sorted by d as y`   |
| `SortedBy`      | `sorted-by`                     | `sorted by created alphabetically`                           |
| `FromLine`      | `from-line`                     | `every a.b named by each of $params.l whose c is 1`          |
| `FromCondition` | `from-condition`                | `c is 1`, `some d.e, if any, exists`                         |
| `Side`          | none                            | where a path is printed: left of a phrase, or right of it    |
| `SyntaxError`   | none                            | `unclosed quote at column 14`                                |

The tree is not part of the spec and carries no promise of staying the same yet.

## Testing

`spec/check_grammar.py --rust <command>` reads thousands of sentences with this crate, `ergo.rego` and the ABNF, and fails when Rust and the ABNF disagree on whether a line reads, or when Rust and `ergo.rego` give a line different problems. `<command>` runs `examples/read.rs`. `compared with itself` is left out of that comparison, because `ergo.rego` raises it later, from its check model. The tests in `tests/rules.rs` pin it instead.

Run the checks in [`ports/rust/README.md`](../README.md) from the root of the repo. They use `--all-features`, so the `serde` tests run too.

`tests/oracle/mod.rs` holds what `ergo.rego` printed or said for a few hundred `from` lines and paths, taken by running it.

`tests/oracle/checks.rs` holds the same for checks and `for` lines. `tests/oracle/validate.py` runs `ergo.rego` with the queries in `tests/oracle/oracle_test.rego` on every line in both files, and on every check, `for` line, `from` line and path in `spec/cases`. It fails when a row no longer matches what `ergo.rego` gives, and prints a row for each line of the cases that the oracle doesn't have yet. Run it from the root of the repo, with OPA 1.20.2, the version CI uses:

```sh
python3 ports/rust/sentences/tests/oracle/validate.py docker run --rm -i -v "$PWD":/src:ro -w /src openpolicyagent/opa:1.20.2
```

Without arguments it runs `opa`. Paste each printed row at the top of the table it names. A line `ergo.rego` rejects goes in `CHECK_ERRORS` or `FOR_ERRORS` when this crate fails to parse it, and in `CHECK_WRITTEN_WRONG` or `FOR_WRITTEN_WRONG` when it parses and its problems come from `check_problems` or `for_problems`. A `from` line it rejects goes in `FROM_ERRORS` when this crate fails to parse it, in `FROM_WRITTEN_WRONG` when it parses and its problems come from `from_problems`, and in `FROM_PARTIAL` when this crate's messages are only some of `ergo.rego`'s. A path goes in `PATH_OK` or `PATH_ERRORS`. A path counts as read when `ergo.rego` reads it as a `from` line that is only a path, whatever names it uses. Then run `cargo fmt`. The file's name ends in `_test.rego` because it calls rules of `ergo.rego` whose names start with `_`, which Regal only allows in test files.
