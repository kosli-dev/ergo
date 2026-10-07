# ergo for Python

An experiment: the [Rust port](../rust/README.md) packaged for Python with [PyO3](https://pyo3.rs) and [maturin](https://www.maturin.rs). One wheel works on every Python from 3.9 up, on the platform it was built for.

```python
import ergo

report = ergo.report(input, requirements, params={"env": "prod"})
violations = ergo.violations(report)

operators = ergo.Operators(definitions)
report = ergo.report(input, requirements, operators=operators)
```

Python objects go to Rust as JSON text and the report comes back the same way. `ergo.Operators` raises `ValueError` when the definitions are written wrong.

Build the wheel and run the conformance suite from Python, both in Docker, from the root of the repo:

```sh
mkdir -p /tmp/ergo-dist
docker run --rm -v "$PWD":/io -v /tmp/ergo-dist:/dist -v ergo-py-target:/target -e CARGO_TARGET_DIR=/target \
  ghcr.io/pyo3/maturin build --release -m ports/python/Cargo.toml -o /dist
docker run --rm -v "$PWD":/io:ro -v /tmp/ergo-dist:/dist:ro -w /io python:3.12-slim \
  sh -c 'pip install -q /dist/*.whl pytest && python -m pytest -q -p no:cacheprovider ports/python/tests'
```

`tests/test_conformance.py` turns every case in [`conformance/`](../../conformance/README.md) into its own test. On 7 October 2026: `1710 passed, 1 xfailed in 0.84s`. The expected failure is the case whose report was made with OPA 1.19's number bug. The same benchmark as the Rust port, run from Python with the conversion to and from JSON included, took 21 to 24 ms for 1,000 deployments and 305 to 376 ms for 10,000.
