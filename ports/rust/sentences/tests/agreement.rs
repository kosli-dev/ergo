mod oracle;
mod support;

use ergo_sentences::*;
use support::*;

#[test]
fn from_lines_print_as_ergo_rego_prints_them() {
    for (line, want) in oracle::FROM_OK {
        assert_eq!(&printed(line), want, "{line:?}");
    }
}

#[test]
fn a_printed_from_line_reads_back_and_prints_the_same() {
    for (line, _) in oracle::FROM_OK {
        let once = printed(line);
        assert_eq!(printed(&once), once, "{line:?}");
    }
}

#[test]
fn from_lines_ergo_rego_rejects_get_its_messages() {
    for (line, want) in oracle::FROM_ERRORS {
        assert_eq!(&failure(line), want, "{line:?}");
    }
}

#[test]
fn from_lines_written_wrong_still_parse() {
    for (line, problems) in oracle::FROM_WRITTEN_WRONG {
        assert!(
            parse_from(line).is_ok(),
            "{line:?} is written wrong ({problems:?}) but the grammar reads it"
        );
    }
}

#[test]
fn messages_for_lines_with_other_problems_too_are_among_ergo_rego_messages() {
    for (line, want) in oracle::FROM_PARTIAL {
        let got = failure(line);
        assert!(!got.is_empty(), "{line:?}");
        for message in &got {
            assert!(
                want.contains(&message.as_str()),
                "{line:?}: {message:?} is not in {want:?}"
            );
        }
    }
}

#[test]
fn paths_print_as_ergo_rego_prints_them() {
    for (line, want) in oracle::PATH_OK {
        assert_eq!(&print_path(&path(line), Side::Left, &[]), want, "{line:?}");
    }
}

#[test]
fn paths_that_ergo_rego_does_not_read_as_a_bare_path_fail() {
    for line in oracle::PATH_ERRORS {
        assert!(parse_path(line).is_err(), "{line:?}");
    }
}
