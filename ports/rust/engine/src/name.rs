use crate::path::{Path, Start, Step};

const WORDS: &[&str] = &[
    "a",
    "after",
    "alphabetically",
    "an",
    "and",
    "as",
    "at",
    "before",
    "between",
    "count",
    "days",
    "each",
    "empty",
    "equal",
    "every",
    "false",
    "first",
    "hours",
    "in",
    "it",
    "item",
    "last",
    "less",
    "minutes",
    "more",
    "named",
    "not",
    "null",
    "of",
    "on",
    "one",
    "or",
    "plus",
    "seconds",
    "some",
    "sorted",
    "sum",
    "to",
    "true",
    "weeks",
    "whose",
    "within",
];

pub fn is_word(key: &str) -> bool {
    WORDS.contains(&key)
}

fn is_bare(key: &str) -> bool {
    let mut bytes = key.bytes();
    match bytes.next() {
        Some(b) if b.is_ascii_alphabetic() || b == b'_' => {}
        _ => return false,
    }
    bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

pub fn key_text(key: &str) -> String {
    if is_bare(key) {
        key.to_string()
    } else {
        serde_json::to_string(key).unwrap_or_default()
    }
}

pub fn name(path: &Path) -> String {
    let mut out = match &path.start {
        Start::Subject => String::new(),
        Start::Input => "$input".to_string(),
        Start::Params => "$params".to_string(),
        Start::Alias(alias) => alias.clone(),
    };
    let last = path.steps.len().saturating_sub(1);
    for (at, step) in path.steps.iter().enumerate() {
        match step {
            Step::Key(key) => {
                if out.is_empty() {
                    if is_word(key) {
                        out.push('.');
                    }
                } else {
                    out.push('.');
                }
                out.push_str(&key_text(key));
            }
            Step::Index(index) => {
                if at == last {
                    let rest = if out.is_empty() { "it" } else { &out };
                    out = format!("item {} of {}", index.saturating_add(1), rest);
                } else {
                    out.push_str(&format!("[{index}]"));
                }
            }
            Step::Ref(reference) => {
                let ref_name = name(reference);
                let one_key = matches!(reference.start, Start::Input | Start::Params)
                    && matches!(reference.steps.as_slice(), [Step::Key(_)]);
                if one_key && !out.is_empty() {
                    out.push_str(&format!(" named by {ref_name}"));
                } else {
                    out.push_str(&format!("[{ref_name}]"));
                }
            }
        }
    }
    if out.is_empty() {
        "it".to_string()
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn k(s: &str) -> Step {
        Step::Key(s.to_string())
    }

    fn subject(steps: Vec<Step>) -> Path {
        Path {
            start: Start::Subject,
            steps,
        }
    }

    fn params(steps: Vec<Step>) -> Path {
        Path {
            start: Start::Params,
            steps,
        }
    }

    #[test]
    fn keys_are_joined_with_dots() {
        assert_eq!(name(&subject(vec![k("x"), k("b"), k("c")])), "x.b.c");
    }

    #[test]
    fn the_subject_alone_is_it() {
        assert_eq!(name(&subject(vec![])), "it");
    }

    #[test]
    fn dashes_and_underscores_need_no_quotes() {
        assert_eq!(
            name(&subject(vec![k("secrets-scan"), k("_x1")])),
            "secrets-scan._x1"
        );
    }

    #[test]
    fn a_key_that_does_not_fit_the_bare_form_is_quoted() {
        assert_eq!(
            name(&subject(vec![k("metadata"), k("app.kubernetes.io/name")])),
            "metadata.\"app.kubernetes.io/name\""
        );
        assert_eq!(name(&subject(vec![k("1a")])), "\"1a\"");
        assert_eq!(name(&subject(vec![k("-a")])), "\"-a\"");
        assert_eq!(name(&subject(vec![k("")])), "\"\"");
        assert_eq!(name(&subject(vec![k("é")])), "\"é\"");
    }

    #[test]
    fn a_key_with_a_dollar_is_quoted() {
        assert_eq!(name(&subject(vec![k("$schema"), k("x")])), "\"$schema\".x");
        assert_eq!(name(&subject(vec![k("x"), k("$b")])), "x.\"$b\"");
        assert_eq!(name(&subject(vec![k("foo$bar")])), "\"foo$bar\"");
    }

    #[test]
    fn quoted_keys_use_json_escapes() {
        assert_eq!(name(&subject(vec![k("a\"b\n")])), "\"a\\\"b\\n\"");
    }

    #[test]
    fn a_first_key_that_is_a_grammar_word_gets_a_dot() {
        assert_eq!(name(&subject(vec![k("empty")])), ".empty");
        assert_eq!(name(&subject(vec![k("a"), k("x")])), ".a.x");
        assert_eq!(name(&subject(vec![k("it")])), ".it");
    }

    #[test]
    fn a_word_is_a_plain_key_after_the_first() {
        assert_eq!(
            name(&subject(vec![k("review"), k("count")])),
            "review.count"
        );
    }

    #[test]
    fn a_word_after_an_alias_or_a_start_needs_no_dot() {
        let alias = Path {
            start: Start::Alias("pr".into()),
            steps: vec![k("empty")],
        };
        assert_eq!(name(&alias), "pr.empty");
        assert_eq!(name(&params(vec![k("true")])), "$params.true");
    }

    #[test]
    fn a_word_is_only_a_word_when_it_matches_exactly() {
        assert_eq!(name(&subject(vec![k("items")])), "items");
        assert_eq!(name(&subject(vec![k("It")])), "It");
    }

    #[test]
    fn input_and_params_start_with_their_names() {
        let input = Path {
            start: Start::Input,
            steps: vec![k("a"), k("b")],
        };
        assert_eq!(name(&input), "$input.a.b");
        assert_eq!(name(&params(vec![k("max")])), "$params.max");
        assert_eq!(name(&params(vec![])), "$params");
    }

    #[test]
    fn an_alias_start_is_kept() {
        let alias = Path {
            start: Start::Alias("pr".into()),
            steps: vec![k("author")],
        };
        assert_eq!(name(&alias), "pr.author");
        assert_eq!(
            name(&Path {
                start: Start::Alias("pr".into()),
                steps: vec![]
            }),
            "pr"
        );
    }

    #[test]
    fn an_index_at_the_end_is_item_counting_from_one() {
        assert_eq!(
            name(&subject(vec![k("xs"), Step::Index(1)])),
            "item 2 of xs"
        );
        assert_eq!(
            name(&subject(vec![k("x"), k("xs"), Step::Index(0)])),
            "item 1 of x.xs"
        );
    }

    #[test]
    fn an_index_on_a_subject_that_is_a_list_is_item_of_it() {
        assert_eq!(name(&subject(vec![Step::Index(0)])), "item 1 of it");
    }

    #[test]
    fn an_index_with_more_steps_after_it_is_in_brackets_from_zero() {
        assert_eq!(
            name(&subject(vec![k("xs"), Step::Index(1), k("k")])),
            "xs[1].k"
        );
        assert_eq!(name(&subject(vec![Step::Index(0), k("k")])), "[0].k");
    }

    #[test]
    fn two_indexes_in_a_row_use_brackets_then_item() {
        assert_eq!(
            name(&subject(vec![k("xs"), Step::Index(0), Step::Index(2)])),
            "item 3 of xs[0]"
        );
    }

    #[test]
    fn a_first_key_after_a_bracket_gets_no_word_dot() {
        assert_eq!(
            name(&subject(vec![Step::Index(0), k("empty")])),
            "[0].empty"
        );
    }

    #[test]
    fn an_index_after_an_input_start_names_the_start() {
        let input = Path {
            start: Start::Input,
            steps: vec![Step::Index(0)],
        };
        assert_eq!(name(&input), "item 1 of $input");
        let input = Path {
            start: Start::Input,
            steps: vec![Step::Index(0), k("a")],
        };
        assert_eq!(name(&input), "$input[0].a");
    }

    #[test]
    fn a_ref_of_one_string_key_reads_as_named_by() {
        let r = params(vec![k("k")]);
        assert_eq!(
            name(&subject(vec![k("obj"), Step::Ref(Box::new(r))])),
            "obj named by $params.k"
        );
        let r = Path {
            start: Start::Input,
            steps: vec![k("which")],
        };
        assert_eq!(
            name(&subject(vec![k("obj"), Step::Ref(Box::new(r))])),
            "obj named by $input.which"
        );
    }

    #[test]
    fn a_path_can_go_on_after_a_named_by() {
        let r = params(vec![k("k")]);
        assert_eq!(
            name(&subject(vec![k("obj"), Step::Ref(Box::new(r)), k("v")])),
            "obj named by $params.k.v"
        );
    }

    #[test]
    fn a_ref_of_several_keys_is_in_brackets() {
        let r = params(vec![k("a"), k("b")]);
        assert_eq!(
            name(&subject(vec![k("k"), Step::Ref(Box::new(r))])),
            "k[$params.a.b]"
        );
    }

    #[test]
    fn a_ref_with_an_index_is_in_brackets() {
        let r = params(vec![k("a"), Step::Index(0)]);
        assert_eq!(
            name(&subject(vec![k("k"), Step::Ref(Box::new(r))])),
            "k[item 1 of $params.a]"
        );
        let r = params(vec![Step::Index(0)]);
        assert_eq!(
            name(&subject(vec![k("k"), Step::Ref(Box::new(r))])),
            "k[item 1 of $params]"
        );
    }

    #[test]
    fn a_ref_that_starts_the_path_is_in_brackets() {
        let r = params(vec![k("key")]);
        assert_eq!(
            name(&subject(vec![Step::Ref(Box::new(r))])),
            "[$params.key]"
        );
    }

    #[test]
    fn a_ref_on_an_alias_reads_as_named_by() {
        let r = params(vec![k("k")]);
        let p = Path {
            start: Start::Alias("m".into()),
            steps: vec![Step::Ref(Box::new(r))],
        };
        assert_eq!(name(&p), "m named by $params.k");
    }

    #[test]
    fn a_ref_key_that_needs_quotes_is_quoted() {
        let r = params(vec![k("a.b")]);
        assert_eq!(
            name(&subject(vec![k("x"), Step::Ref(Box::new(r))])),
            "x named by $params.\"a.b\""
        );
    }
}
