mod oracle;

use ergo_sentences::*;
use support_text::matches_line;

mod support_text {
    pub fn matches_line(pattern: &str) -> String {
        let mut quoted = String::from("\"");
        for ch in pattern.chars() {
            match ch {
                '"' => quoted.push_str("\\\""),
                '\\' => quoted.push_str("\\\\"),
                '\n' => quoted.push_str("\\n"),
                ch => quoted.push(ch),
            }
        }
        quoted.push('"');
        format!("y matches {quoted}")
    }
}

#[test]
fn patterns_are_valid_as_re2_says() {
    assert!(oracle::checks::PATTERNS.len() > 50);
    for (pattern, valid) in oracle::checks::PATTERNS {
        let line = matches_line(pattern);
        let found = check_problems(&parse_check(&line).unwrap(), &[]);
        let invalid = found.iter().any(|m| m.starts_with("invalid pattern"));
        assert_eq!(!invalid, *valid, "{pattern:?}");
    }
}

#[test]
fn a_brace_that_is_not_a_repeat_is_a_literal() {
    for pattern in ["a{1", "x{,3}", "a{", "{", "a{b}", "a{1,2"] {
        let line = matches_line(pattern);
        assert!(
            check_problems(&parse_check(&line).unwrap(), &[]).is_empty(),
            "{pattern:?}"
        );
    }
}

#[test]
fn a_repeat_over_a_thousand_is_invalid_alone_or_nested() {
    for pattern in [
        "a{1001}",
        "a{1,1001}",
        "(a{1000}){2}",
        "(a{2}){501}",
        "(?:a{100}){11}",
    ] {
        let line = matches_line(pattern);
        let found = check_problems(&parse_check(&line).unwrap(), &[]);
        assert_eq!(found.len(), 1, "{pattern:?}");
    }
    for pattern in ["a{1000}", "(a{10}){100}", "(a{1000})", "a{1000,}"] {
        let line = matches_line(pattern);
        assert!(
            check_problems(&parse_check(&line).unwrap(), &[]).is_empty(),
            "{pattern:?}"
        );
    }
}

#[test]
fn a_repeat_of_a_repeat_is_invalid_unless_it_is_lazy() {
    for pattern in ["a**", "a++", "a?+", "a*+", "a{2}*", "a*??"] {
        let line = matches_line(pattern);
        assert_eq!(
            check_problems(&parse_check(&line).unwrap(), &[]).len(),
            1,
            "{pattern:?}"
        );
    }
    for pattern in ["a*?", "a+?", "a??", "a{2}?"] {
        let line = matches_line(pattern);
        assert!(
            check_problems(&parse_check(&line).unwrap(), &[]).is_empty(),
            "{pattern:?}"
        );
    }
}

#[test]
fn only_the_flags_re2_has_are_valid() {
    for pattern in [
        "(?i)a", "(?s).", "(?m)^a", "(?U)a", "(?i:a)", "(?-i)a", "(?im-s)a",
    ] {
        let line = matches_line(pattern);
        assert!(
            check_problems(&parse_check(&line).unwrap(), &[]).is_empty(),
            "{pattern:?}"
        );
    }
    for pattern in ["(?x)a", "(?u)a", "(?R)a", "(?x:a)"] {
        let line = matches_line(pattern);
        assert_eq!(
            check_problems(&parse_check(&line).unwrap(), &[]).len(),
            1,
            "{pattern:?}"
        );
    }
}

#[test]
fn quoted_text_and_class_ranges_are_read_as_re2_reads_them() {
    for pattern in [
        "\\Qa.b\\E",
        "\\Qa(",
        "[\\d-z]",
        "[a-z\\d]",
        "\\pL",
        "\\p{Greek}",
        "\\x{10FFFF}",
        "[[:alpha:]]",
    ] {
        let line = matches_line(pattern);
        assert!(
            check_problems(&parse_check(&line).unwrap(), &[]).is_empty(),
            "{pattern:?}"
        );
    }
    for pattern in [
        "\\C",
        "\\Z",
        "(?=a)",
        "\\1(a)",
        "[z-a]",
        "\\p{Nope}",
        "\\x{110000}",
    ] {
        let line = matches_line(pattern);
        assert_eq!(
            check_problems(&parse_check(&line).unwrap(), &[]).len(),
            1,
            "{pattern:?}"
        );
    }
}
