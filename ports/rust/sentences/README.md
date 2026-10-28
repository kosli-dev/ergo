# ergo-sentences

Reads Ergo's check sentences, `for` lines, `from` lines and paths into a tree, and prints a tree back as a canonical sentence. It doesn't build reports and has no dependencies, so an editor or a linter can use it without the engine. It builds for `wasm32-unknown-unknown`.

This part reads `from` lines and paths and prints them. Checks and `for` lines come next, and their types are already in the tree.

## What it gives

```rust
pub fn parse_from(line: &str) -> Result<From, Vec<SyntaxError>>;
pub fn parse_path(line: &str) -> Result<Path, Vec<SyntaxError>>;

pub fn print_from(line: &From, aliases: &[&str]) -> String;
pub fn print_from_condition(condition: &FromCondition, aliases: &[&str]) -> String;
pub fn print_condition(condition: &Condition, aliases: &[&str]) -> String;
pub fn print_term(term: &Term, aliases: &[&str]) -> String;
pub fn print_path(path: &Path, side: Side, aliases: &[&str]) -> String;
```

- `parse_from` and `parse_path` read what [`spec/sentences.abnf`](../../../spec/sentences.abnf) allows and nothing else. Spaces at both ends are dropped, and a tab isn't a space. A bare first key is never a word of the grammar: write `.empty` for a field called `empty`.
- When the grammar allows two readings, the tree is the one `ergo.rego` picks, and a line that the first choice can't finish is read the other way.
- A failed read gives the messages `ergo.rego` gives for the same line, in its order, as `SyntaxError { column, message }`. `column` counts characters of the trimmed line from 1, and is only set when the message names a column. For a `from` line the columns count from the text after a leading `every`, as `ergo.rego` does.
- Keys and strings are decoded. Numbers, positions and bracket indexes keep their digits as written, so the caller decides what a number that is too big means.
- The printed sentence is canonical: one space between words, `equals` before a field and `is` before a value, `is in` before a path and `is one of` before values, numbers in plain decimal form, keys bare when they can be, strings in single quotes when they hold a backslash and nothing that needs escaping, and a bracket index that ends a path as `item N of`.
- `aliases` are the names that shadow a field, like a `for` alias or a part. A field written with a dot and called like one of them keeps its dot when printed.

Rules that only need the tree, like `min above max` or `invalid pattern`, come with the checks. Until then a line that is written wrong in that way still parses.

## The tree

Every type derives `Debug`, `Clone`, `PartialEq`, `Eq` and `Hash`. With the `serde` feature, which is off by default, they also derive `Serialize` and `Deserialize`.

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
| `For`           | `for-line`                      | `every xs as x, last of ys as y`                             |
| `ForItem`       | `for-item`                      | `some xs whose a is 1 as x`, `last of ys sorted by d as y`   |
| `SortedBy`      | `sorted-by`                     | `sorted by created alphabetically`                           |
| `From`          | `from-line`                     | `every a.b named by each of $params.l whose c is 1`          |
| `FromCondition` | `from-condition`                | `c is 1`, `some d.e, if any, exists`                         |
| `Side`          | none                            | where a path is printed: left of a phrase, or right of it    |
| `SyntaxError`   | none                            | `unclosed quote at column 14`                                |

The tree is not part of the spec and carries no promise of staying the same yet.

## Testing

Run the checks in [`ports/rust/README.md`](../README.md) from the root of the repo. They use `--all-features`, so the `serde` tests run too.

`tests/oracle/mod.rs` holds what `ergo.rego` printed or said for a few hundred lines, taken by running it. To make it again, run `data.ergo._from_line` and `data.ergo._s_from_line_text` on the lines with `opa eval`.
