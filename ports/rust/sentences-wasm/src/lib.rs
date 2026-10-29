//! Reads Ergo's sentences in a browser, without the engine. Lines go in as strings and trees, names and problems cross as JSON text, so nothing but strings passes the boundary.

use ergo_sentences::SyntaxError;
use serde::Serialize;
use serde::de::DeserializeOwned;
use wasm_bindgen::prelude::*;

fn answer<T: Serialize>(read: Result<T, Vec<SyntaxError>>) -> String {
    match read {
        Ok(tree) => serde_json::json!({ "tree": tree }),
        Err(errors) => serde_json::json!({ "errors": errors }),
    }
    .to_string()
}

fn read<T: DeserializeOwned>(what: &str, text: &str) -> Result<T, String> {
    serde_json::from_str(text).map_err(|e| format!("{what} valid JSON: {e}"))
}

fn names(text: &str) -> Result<Vec<String>, String> {
    read("the names aren't", text)
}

fn refs(names: &[String]) -> Vec<&str> {
    names.iter().map(String::as_str).collect()
}

/// Reads a check sentence and returns `{"tree": ...}`, or `{"errors": [{"column": ..., "message": ...}]}` when it doesn't read. `column` is `null` when the message names none.
#[wasm_bindgen]
pub fn parse_check(line: &str) -> String {
    answer(ergo_sentences::parse_check(line))
}

/// Reads a `for` line and returns `{"tree": ...}` or `{"errors": [...]}`, like `parse_check`.
#[wasm_bindgen]
pub fn parse_for(line: &str) -> String {
    answer(ergo_sentences::parse_for(line))
}

/// Reads a `from` line and returns `{"tree": ...}` or `{"errors": [...]}`, like `parse_check`.
#[wasm_bindgen]
pub fn parse_from(line: &str) -> String {
    answer(ergo_sentences::parse_from(line))
}

/// Reads a path and returns `{"tree": ...}` or `{"errors": [...]}`, like `parse_check`.
#[wasm_bindgen]
pub fn parse_path(line: &str) -> String {
    answer(ergo_sentences::parse_path(line))
}

/// Lists what is written wrong in a check's tree, given as JSON text, as `{"problems": [...]}`. `aliases` is a JSON array of names. Fails when either isn't valid JSON.
pub fn check_problems_text(tree: &str, aliases: &str) -> Result<String, String> {
    let check = read("the tree isn't", tree)?;
    let aliases = names(aliases)?;
    let problems = ergo_sentences::check_problems(&check, &refs(&aliases));
    Ok(serde_json::json!({ "problems": problems }).to_string())
}

/// Lists what is written wrong in a `for` line's tree, given as JSON text, as `{"problems": [...]}`. `aliases` is a JSON array of names. Fails when either isn't valid JSON.
pub fn for_problems_text(tree: &str, aliases: &str) -> Result<String, String> {
    let line = read("the tree isn't", tree)?;
    let aliases = names(aliases)?;
    let problems = ergo_sentences::for_problems(&line, &refs(&aliases));
    Ok(serde_json::json!({ "problems": problems }).to_string())
}

/// Lists what is written wrong in a `from` line's tree, given as JSON text, as `{"problems": [...]}`. Fails when it isn't valid JSON.
pub fn from_problems_text(tree: &str) -> Result<String, String> {
    let line = read("the tree isn't", tree)?;
    let problems = ergo_sentences::from_problems(&line);
    Ok(serde_json::json!({ "problems": problems }).to_string())
}

/// Writes a check's tree, given as JSON text, back as a sentence. `aliases` is a JSON array of names. Fails when either isn't valid JSON.
pub fn print_check_text(tree: &str, aliases: &str) -> Result<String, String> {
    let check = read("the tree isn't", tree)?;
    let aliases = names(aliases)?;
    Ok(ergo_sentences::print_check(&check, &refs(&aliases)))
}

/// Writes a `for` line's tree, given as JSON text, back as a line. `aliases` is a JSON array of names. Fails when either isn't valid JSON.
pub fn print_for_text(tree: &str, aliases: &str) -> Result<String, String> {
    let line = read("the tree isn't", tree)?;
    let aliases = names(aliases)?;
    Ok(ergo_sentences::print_for(&line, &refs(&aliases)))
}

/// Writes a `from` line's tree, given as JSON text, back as a line. `aliases` and `parents` are JSON arrays of names. Fails when one isn't valid JSON.
pub fn print_from_text(tree: &str, aliases: &str, parents: &str) -> Result<String, String> {
    let line = read("the tree isn't", tree)?;
    let aliases = names(aliases)?;
    let parents = read::<Vec<String>>("the parents aren't", parents)?;
    Ok(ergo_sentences::print_from(
        &line,
        &refs(&aliases),
        &refs(&parents),
    ))
}

/// Lists what is written wrong in a check's tree, as `{"problems": [...]}`. Throws an `Error` when the tree or the aliases aren't valid JSON.
#[wasm_bindgen]
pub fn check_problems(tree: &str, aliases: &str) -> Result<String, JsError> {
    check_problems_text(tree, aliases).map_err(|m| JsError::new(&m))
}

/// Lists what is written wrong in a `for` line's tree, as `{"problems": [...]}`. Throws an `Error` when the tree or the aliases aren't valid JSON.
#[wasm_bindgen]
pub fn for_problems(tree: &str, aliases: &str) -> Result<String, JsError> {
    for_problems_text(tree, aliases).map_err(|m| JsError::new(&m))
}

/// Lists what is written wrong in a `from` line's tree, as `{"problems": [...]}`. Throws an `Error` when the tree isn't valid JSON.
#[wasm_bindgen]
pub fn from_problems(tree: &str) -> Result<String, JsError> {
    from_problems_text(tree).map_err(|m| JsError::new(&m))
}

/// Writes a check's tree back as a sentence. Throws an `Error` when the tree or the aliases aren't valid JSON.
#[wasm_bindgen]
pub fn print_check(tree: &str, aliases: &str) -> Result<String, JsError> {
    print_check_text(tree, aliases).map_err(|m| JsError::new(&m))
}

/// Writes a `for` line's tree back as a line. Throws an `Error` when the tree or the aliases aren't valid JSON.
#[wasm_bindgen]
pub fn print_for(tree: &str, aliases: &str) -> Result<String, JsError> {
    print_for_text(tree, aliases).map_err(|m| JsError::new(&m))
}

/// Writes a `from` line's tree back as a line. Throws an `Error` when the tree, the aliases or the parents aren't valid JSON.
#[wasm_bindgen]
pub fn print_from(tree: &str, aliases: &str, parents: &str) -> Result<String, JsError> {
    print_from_text(tree, aliases, parents).map_err(|m| JsError::new(&m))
}
