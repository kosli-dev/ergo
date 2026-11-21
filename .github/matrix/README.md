# Matrix generators

Each file here writes a JSON list of pairs for `python3 spec/sweep.py --pairs FILE`. A pair is a `name`, a `policy`, an `input` and `params`. Every generator is deterministic: the same command writes the same file, so nothing it makes is kept in the repo.

The pairs run through `ergo.rego` and the Rust engine, and a pair is interesting where they differ, or where a change moves one of them.

| Generator     | What it makes                                                                                                                                                                                       |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `matrix-a.py` | One `count of xs whose ... is 1` or `count of xs.f that ... is 1` check for each operator, with the other side read from `$params` or `$input`, on the left or the right, and with items that are missing, `null`, of the wrong type or not objects. About 590 pairs. |
| `matrix-b.py` | Many check forms (`count of ... whose`, `that`, `sum of`, `every`, `some`, `plus`, `for` lines, `named by` keys, lists that are missing or the wrong type) with each operator, a random but fixed mix of root and item states, and parts of the subject. About 570 pairs. |
| `walk.py`     | `every` and `some` on a list with each operator, with a keyed read (`m named by $params.k`) and with `whose`, on lists of 0 to 5 items. About 180 pairs.                                              |

## Run one by hand

Build the Rust command once, without Docker, from the root of the repo:

```sh
(cd engines/rust && cargo build -j 4 -p ergo-policy-cli)
```

Then write the pairs and run them:

```sh
python3 .github/matrix/matrix-a.py /tmp/pairs.json
PATH=engines/rust/target/debug:$PATH python3 spec/sweep.py --pairs /tmp/pairs.json
```

`sweep.py` runs `ergo.rego` with `opa` and the `ergo` on `PATH`, and prints each pair where they differ. If your target folder is somewhere else, put its `debug` folder in `PATH`.

## See what a change did to one generator

`.github/matrix-facts.sh BASE NAME...` runs each generator `NAME` (`matrix-a`, `matrix-b`, `walk`) on `BASE` (a ref, like `origin/main`) and on the working tree, and prints a Markdown summary with one heading per generator and three lists. Each list is about the pairs where the working tree's Rust row differs from `BASE`'s Rust row, one pair on each line with the pair's name and the values:

- Cause went down (usually a bug): the cause comes later in the order of [Causes](../../REFERENCE.md#causes) than on `BASE`, or than the one `ergo.rego` gives on the working tree. A pair that was already lower than Rego's on `BASE` says `already on base`.
- Says less than `BASE` (usually a bug): the `BASE` row failed and a problem it said is gone from the whole report. It splits every message of the row and of its `failures`, at every depth, into its problems, at `; ` and at `, and ` (leaving out `and N more`), and drops the `item N of x: ` prefix to know which item a problem is about. A problem counts as gone when no message of the working tree's row says it for that item, or once for all items, or for no item. When the working tree's row cuts a message with `and N more` and has no entry for any item, nothing is listed, because the problem may be in the part that was cut. A row that has no `failures` is read from its message alone. A row that is gone, or a report that now gives an error, counts too. A message that is cut at another place is not a problem that is gone.
- Cause went up (usually the rule `problems.all_said`; list for the Rego steps): the cause comes earlier in the order than on `BASE`, or than the one `ergo.rego` gives.

The order is `not_an_object`, `ambiguous`, `unusable`, `absent`, `null`, `value`, and a passed row comes after all of them. The rule `problems.all_said` takes the worst cause of all, so a cause that goes up is usually the rule and one that goes down is usually a bug. Rows are compared by requirement, check and subject. A list with nothing in it says `None.`

It builds both Rust commands with `cargo`, so it needs Rust and `opa` on your machine, and it only informs: it fails only when a tool fails. The `matrix-facts` job runs it on pull requests for all three generators, `matrix-a`, `matrix-b` and `walk`, in one run that builds `BASE` and the working tree once, with one heading for each generator in the job summary.
