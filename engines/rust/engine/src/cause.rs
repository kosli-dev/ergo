#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Cause {
    Satisfied,
    NotAnObject,
    Ambiguous,
    Unusable,
    Absent,
    Null,
    Value,
}

impl Cause {
    pub fn name(self) -> &'static str {
        match self {
            Cause::Satisfied => "satisfied",
            Cause::NotAnObject => "not_an_object",
            Cause::Ambiguous => "ambiguous",
            Cause::Unusable => "unusable",
            Cause::Absent => "absent",
            Cause::Null => "null",
            Cause::Value => "value",
        }
    }

    /// Whether this cause is a failure: anything but `Satisfied` and `Value`.
    pub fn is_failure(self) -> bool {
        !matches!(self, Cause::Satisfied | Cause::Value)
    }

    pub fn worst<I: IntoIterator<Item = Cause>>(causes: I) -> Option<Cause> {
        causes.into_iter().filter(|c| *c != Cause::Satisfied).min()
    }
}

#[cfg(test)]
mod tests;
