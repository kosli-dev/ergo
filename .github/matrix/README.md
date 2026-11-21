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

`.github/matrix-facts.sh [NAME [BASE]]` runs the generator `NAME` (`matrix-a` by default) on `BASE` (`origin/main` by default) and on the working tree, and prints a Markdown summary:

- the pairs that are worse than `BASE`: a row where `BASE` had the same verdict and cause as `ergo.rego` and the working tree doesn't;
- the pairs where the Rust cause is lower than the one `ergo.rego` gives.

A row's cause is lower when it comes later in the order of [Causes](../../REFERENCE.md#causes): `not_an_object`, `ambiguous`, `unusable`, `absent`, `null`, `value`. A pair that was already lower on `BASE` says `already on BASE`. Rows are compared by requirement, check and subject.

It builds both Rust commands with `cargo`, so it needs Rust and `opa` on your machine, and it only informs: it fails only when a tool fails. The `matrix-facts` job runs it on pull requests for all three generators, `matrix-a`, `matrix-b` and `walk`, each in its own step and under its own heading in the job summary.
