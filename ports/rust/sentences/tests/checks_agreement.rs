mod oracle;
mod support;

use ergo_sentences::*;
use support::*;

fn without_self(all: Vec<String>) -> Vec<String> {
    all.into_iter()
        .filter(|m| !m.contains("compared with itself"))
        .collect()
}

fn only_self(all: Vec<String>) -> Vec<String> {
    all.into_iter()
        .filter(|m| m.contains("compared with itself"))
        .collect()
}

#[test]
fn checks_print_as_ergo_rego_prints_them() {
    for (line, want, _, _) in oracle::checks::CHECK_OK {
        assert_eq!(&printed_check(line), want, "{line:?}");
    }
}

#[test]
fn a_printed_check_reads_back_and_prints_the_same() {
    for (line, _, _, _) in oracle::checks::CHECK_OK {
        let once = printed_check(line);
        assert_eq!(printed_check(&once), once, "{line:?}");
    }
}

#[test]
fn checks_ergo_rego_reads_have_no_problems_but_the_self_ones_it_finds() {
    for (line, _, plain, with_aliases) in oracle::checks::CHECK_OK {
        let read = check(line);
        let all = check_problems(&read, &[]);
        assert_eq!(&only_self(all.clone()), plain, "{line:?}");
        assert_eq!(without_self(all), Vec::<String>::new(), "{line:?}");
        let aliased = check_problems(&read, &["pr", "x"]);
        assert_eq!(&only_self(aliased), with_aliases, "{line:?}");
    }
}

#[test]
fn checks_ergo_rego_rejects_get_its_messages() {
    for (line, want) in oracle::checks::CHECK_ERRORS {
        assert_eq!(&check_failure(line), want, "{line:?}");
    }
}

#[test]
fn checks_written_wrong_parse_and_give_ergo_rego_problems() {
    for (line, want) in oracle::checks::CHECK_WRITTEN_WRONG {
        assert_eq!(&without_self(problems(line)), want, "{line:?}");
    }
}

#[test]
fn for_lines_print_as_ergo_rego_prints_them() {
    for (line, want, _, _) in oracle::checks::FOR_OK {
        assert_eq!(&printed_for(line), want, "{line:?}");
    }
}

#[test]
fn a_printed_for_line_reads_back_and_prints_the_same() {
    for (line, _, _, _) in oracle::checks::FOR_OK {
        let once = printed_for(line);
        assert_eq!(printed_for(&once), once, "{line:?}");
    }
}

#[test]
fn for_lines_ergo_rego_reads_have_only_the_self_problems_it_finds() {
    for (line, _, plain, with_aliases) in oracle::checks::FOR_OK {
        let read = for_line(line);
        let all = for_problems(&read, &[]);
        assert_eq!(&only_self(all.clone()), plain, "{line:?}");
        assert_eq!(without_self(all), Vec::<String>::new(), "{line:?}");
        assert_eq!(
            &only_self(for_problems(&read, &["pr", "x"])),
            with_aliases,
            "{line:?}"
        );
    }
}

#[test]
fn for_lines_ergo_rego_rejects_get_its_messages() {
    for (line, want) in oracle::checks::FOR_ERRORS {
        assert_eq!(&for_failure(line), want, "{line:?}");
    }
}

#[test]
fn for_lines_written_wrong_parse_and_give_ergo_rego_problems() {
    for (line, want) in oracle::checks::FOR_WRITTEN_WRONG {
        assert_eq!(
            &without_self(for_problems(&for_line(line), &[])),
            want,
            "{line:?}"
        );
    }
}

#[test]
fn from_lines_have_the_problems_ergo_rego_gives() {
    for (line, want) in oracle::FROM_WRITTEN_WRONG {
        assert_eq!(&from_problems(&from(line), &[]), want, "{line:?}");
    }
}
