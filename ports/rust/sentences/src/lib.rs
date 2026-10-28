pub const NAME: &str = "ergo-sentences";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_itself() {
        assert_eq!(NAME, "ergo-sentences");
    }
}
