# The Rego engine's parts

This page is for people who change `ergo.rego`. If you only want to use it, read [`OPA.md`](../../OPA.md).

The engine is written as parts under `src/`, one folder per layer, and `.github/build-ergo.sh` joins them into the single file `dist/ergo.rego`. Every part is in `package ergo`, so Rego lets any rule call any other, but the folders have an order.

## The order of the folders

From the lowest layer to the highest:

1. `shared/` holds helpers every other folder uses: paths and names, the engine version and spec constants, and the side forms.
2. `reading/` reads a name or path from the input and gives its read states (value, absent and so on), and builds the `$refs` listing.
3. `sentences/` reads a sentence into a policy object and writes one back.
4. `policy/` reads a whole policy, resolves its subjects, finds what is written wrong in it and compiles it into checks.
5. `checks/` judges each check: the operators, and the compare, number and time maths.
6. `lines/` works out the roots, items and failed items of `from` and `for` lines.
7. `messages/` writes the text of each cause.
8. `report/` builds the evaluation, the requirements, the chains of parent rows and the violations.

A rule may call rules in its own folder and in the folders above it in this list, which are the earlier ones. A call to a rule in a later folder points backwards.

## What CI checks

`.github/rego-layers.py` finds every call that points backwards and fails on one that isn't in [`layers-known.txt`](layers-known.txt). That file lists the calls the engine makes today that break the order, one `from-rule -> to-rule` per line, sorted. The list may only shrink: the script also fails when a listed call no longer exists, so a fix has to remove its line. A new backward call can't be added to it.
