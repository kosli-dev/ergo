use std::io::Write;
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.is_empty() {
        eprint!("{}", ergo_cli::USAGE);
        return ExitCode::from(2);
    }
    match ergo_cli::run(&arguments) {
        Ok(ergo_cli::Outcome::Print(text)) => {
            let mut stdout = std::io::stdout().lock();
            match stdout
                .write_all(text.as_bytes())
                .and_then(|()| stdout.flush())
            {
                Ok(()) => ExitCode::SUCCESS,
                Err(_) => ExitCode::from(1),
            }
        }
        Err(failure) => {
            eprintln!("ergo: {}", failure.message());
            ExitCode::from(failure.code() as u8)
        }
    }
}
