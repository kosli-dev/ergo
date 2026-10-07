use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use serde_json::Value;

fn parse(text: &str) -> PyResult<Value> {
    serde_json::from_str(text).map_err(|e| PyValueError::new_err(e.to_string()))
}

fn operators(definitions: &str) -> PyResult<ergo::Operators> {
    ergo::Operators::load(&parse(definitions)?).map_err(|errors| PyValueError::new_err(errors.join("\n")))
}

#[pyfunction]
#[pyo3(signature = (input, requirements, params=None, definitions=None))]
fn report(input: &str, requirements: &str, params: Option<&str>, definitions: Option<&str>) -> PyResult<String> {
    let input = parse(input)?;
    let requirements = parse(requirements)?;
    let params = params.map(parse).transpose()?;
    let report = match definitions {
        Some(d) => ergo::report_with(&input, params.as_ref(), &requirements, &operators(d)?),
        None => ergo::report(&input, params.as_ref(), &requirements),
    };
    Ok(report.to_string())
}

#[pyfunction]
fn violations(report: &str) -> PyResult<String> {
    Ok(ergo::violations(&parse(report)?).to_string())
}

#[pyfunction]
fn check_operators(definitions: &str) -> PyResult<()> {
    operators(definitions).map(|_| ())
}

#[pymodule]
fn _ergo(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(report, m)?)?;
    m.add_function(wrap_pyfunction!(violations, m)?)?;
    m.add_function(wrap_pyfunction!(check_operators, m)?)?;
    Ok(())
}
