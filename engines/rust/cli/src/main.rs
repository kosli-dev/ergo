use std::io::Write;
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.is_empty() {
        eprint!(
            "{}",
            ergo_policy_cli::usage(&ergo_policy_cli::Terminal::read())
        );
        return ExitCode::from(2);
    }
    let (text, code) = match ergo_policy_cli::run_with(
        &arguments,
        &ergo_policy_cli::Environment::read(),
        &ergo_policy_cli::Terminal::read(),
    ) {
        Ok(ergo_policy_cli::Outcome::Print(text)) => (text, 0),
        Ok(ergo_policy_cli::Outcome::PrintAndFail(text, code)) => (text, code),
        Err(failure) => {
            eprintln!("ergo: {}", failure.message());
            return ExitCode::from(failure.code() as u8);
        }
    };
    let mut stdout = std::io::stdout().lock();
    match stdout
        .write_all(text.as_bytes())
        .and_then(|()| stdout.flush())
    {
        Ok(()) => ExitCode::from(code),
        Err(_) => ExitCode::from(2),
    }
}
