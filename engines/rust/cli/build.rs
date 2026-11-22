use std::process::Command;

fn git(arguments: &[&str]) -> Option<String> {
    let output = Command::new("git").args(arguments).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    Some(text.trim().to_string())
}

fn main() {
    let in_this_repo = git(&["rev-parse", "--show-prefix"]).as_deref() == Some("engines/rust/cli/");
    let commit = if in_this_repo {
        git(&["rev-parse", "HEAD"])
    } else {
        None
    };
    if in_this_repo {
        if let Some(path) = git(&["rev-parse", "--git-path", "HEAD"]) {
            println!("cargo:rerun-if-changed={path}");
        }
        if let Some(reference) = git(&["symbolic-ref", "-q", "HEAD"])
            && let Some(path) = git(&["rev-parse", "--git-path", &reference])
        {
            println!("cargo:rerun-if-changed={path}");
        }
    }
    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rustc-env=ERGO_BUILD_COMMIT={}",
        commit.unwrap_or_else(|| "unknown".to_string())
    );
}
