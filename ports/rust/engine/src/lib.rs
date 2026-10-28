pub const NAME: &str = "ergo-engine";

pub fn sentences_crate() -> &'static str {
    ergo_sentences::NAME
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_the_sentences_crate() {
        assert_eq!(sentences_crate(), "ergo-sentences");
    }
}
