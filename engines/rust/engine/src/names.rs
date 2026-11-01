const EMPTY_NAME: &str = "a name can't be empty";
const DOLLAR_NAME: &str = "a name can't start with $";
const EDGE_NAME: &str = "a name can't start or end with a space or an invisible character";

const EDGE_RANGES: [(u32, u32); 31] = [
    (0x9, 0xD),
    (0x20, 0x20),
    (0x85, 0x85),
    (0xA0, 0xA0),
    (0x1680, 0x1680),
    (0x2000, 0x200A),
    (0x2028, 0x2029),
    (0x202F, 0x202F),
    (0x205F, 0x205F),
    (0x3000, 0x3000),
    (0xAD, 0xAD),
    (0x600, 0x605),
    (0x61C, 0x61C),
    (0x6DD, 0x6DD),
    (0x70F, 0x70F),
    (0x890, 0x891),
    (0x8E2, 0x8E2),
    (0x180E, 0x180E),
    (0x200B, 0x200F),
    (0x202A, 0x202E),
    (0x2060, 0x2064),
    (0x2066, 0x206F),
    (0xFEFF, 0xFEFF),
    (0xFFF9, 0xFFFB),
    (0x110BD, 0x110BD),
    (0x110CD, 0x110CD),
    (0x13430, 0x1343F),
    (0x1BCA0, 0x1BCA3),
    (0x1D173, 0x1D17A),
    (0xE0001, 0xE0001),
    (0xE0020, 0xE007F),
];

fn edge_char(c: char) -> bool {
    let c = c as u32;
    EDGE_RANGES
        .iter()
        .any(|(low, high)| (*low..=*high).contains(&c))
}

/// What is wrong with a name a user wrote: it is empty, it starts with `$`, or starts or ends with a space or an invisible character. Sorted, so the same names give the same list in every report.
pub fn written_name_problems(name: &str) -> Vec<&'static str> {
    let mut found = Vec::new();
    if name.is_empty() {
        found.push(EMPTY_NAME);
    }
    let edge =
        name.chars().next().is_some_and(edge_char) || name.chars().last().is_some_and(edge_char);
    if edge {
        found.push(EDGE_NAME);
    }
    if name.starts_with('$') {
        found.push(DOLLAR_NAME);
    }
    found
}

#[cfg(test)]
mod tests {
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
}
