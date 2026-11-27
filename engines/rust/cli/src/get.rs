//! Says how to get `ergo.rego` when `--engine rego` can't find it.

/// The tag of the latest release of `ergo.rego`. Move it to the new tag after each `rego-v*` release.
pub const LATEST_ERGO_REGO: &str = "rego-v0.6.0";

fn how_to_get(command: &str) -> String {
    format!(
        "Get the release you run in production and pass its path. For the current release:\n  curl -fsSL -o ergo.rego https://github.com/kosli-dev/ergo/releases/download/{LATEST_ERGO_REGO}/ergo.rego\n  ergo {command} --engine rego --ergo-rego ergo.rego ..."
    )
}

/// The message for `command` when no path of `ergo.rego` was given.
pub fn missing(command: &str) -> String {
    format!(
        "--engine rego needs ergo.rego, and it was not found.\n{}",
        how_to_get(command)
    )
}

/// `problem`, which says why the `ergo.rego` that was named can't be read, followed by how to get it for `command`.
pub fn unreadable(problem: &str, command: &str) -> String {
    format!("{problem}\n{}", how_to_get(command))
}
