# The Rego engine's parts

This page is for people who change `ergo.rego`. If you only want to use it, read [`OPA.md`](../../OPA.md).

The engine is written as parts under `src/`, one folder per layer, and `.github/build-ergo.sh` joins them into the single file `dist/ergo.rego`. Every part is in `package ergo`, so Rego lets any rule call any other, but the folders have an order.

## The order of the folders

From the lowest layer to the highest:

1. `shared/` holds the small helpers everything else uses: basic value tests, names and paths of fields, JSON text, and the forms a reference can take.
2. `reading/` reads values out of `input`, `$params` and the policy, and says in what state a read ended (found, missing, null, wrong type).
3. `sentences/` reads a sentence into its parts and writes a parsed sentence back as text.
4. `policy/` reads a whole policy, finds what is written wrong in it and compiles it into checks.
5. `checks/` decides the outcome of a single check: the operators, the causes and the inputs a check read.
6. `lines/` works out the lines of a check that runs over a list, with `for` and `from` and the walk down a path.
7. `messages/` writes the plain English messages for what a check found.
8. `report/` builds the entries of the report, the evaluation, the requirements and the violations.

A rule may call rules in its own folder and in the folders above it in this list, which are the earlier ones. A call to a rule in a later folder points backwards.

## What CI checks

`.github/rego-layers.py` finds every call that points backwards and fails on one that isn't in [`layers-known.txt`](layers-known.txt). That file lists the calls the engine makes today that break the order, one `from-rule -> to-rule` per line, sorted. The list may only shrink: the script also fails when a listed call no longer exists, so a fix has to remove its line. A new backward call can't be added to it.
