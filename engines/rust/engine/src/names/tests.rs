use super::*;

const EDGE: &str = "a name can't start or end with a space or an invisible character";

#[test]
fn a_name_that_starts_or_ends_with_a_space_or_an_invisible_character_is_listed() {
    for name in [
        " x",
        "x ",
        "\tx",
        "x\t",
        "\u{a0}x",
        "x\u{a0}",
        "\u{200b}x",
        "x\u{200b}",
        "\u{feff}x",
        "x\u{feff}",
        "\u{2060}x",
        "x\u{200d}",
        "\u{3000}x",
        "x\u{110bd}",
        "x\u{e0001}",
        " ",
        "\n",
    ] {
        assert_eq!(written_name_problems(name), vec![EDGE], "{name:?}");
    }
}

#[test]
fn an_empty_name_is_listed_and_a_name_with_text_is_not() {
    assert_eq!(written_name_problems(""), vec!["a name can't be empty"]);
    assert!(written_name_problems("a").is_empty());
}

#[test]
fn spaces_inside_a_name_and_a_full_width_dollar_sign_are_fine() {
    for name in ["x y", "\u{ff04}x", "a$b", "x\u{1f600}", "x"] {
        assert!(written_name_problems(name).is_empty(), "{name:?}");
    }
}

#[test]
fn a_name_with_both_problems_lists_both_sorted() {
    assert_eq!(
        written_name_problems("$x "),
        vec![EDGE, "a name can't start with $"]
    );
    assert_eq!(
        written_name_problems("$x"),
        vec!["a name can't start with $"]
    );
}
