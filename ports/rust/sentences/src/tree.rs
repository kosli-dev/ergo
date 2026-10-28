#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Check {
    pub assertions: Vec<Assertion>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Assertion {
    Plain {
        path: Path,
        phrase: Phrase,
    },
    Quantified {
        quantifier: Quantifier,
        path: Path,
        whose: Vec<Condition>,
        if_any: bool,
        phrase: Phrase,
    },
    Derived {
        terms: Vec<Term>,
        phrase: Phrase,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Quantifier {
    Every,
    Some,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Condition {
    pub left: Left,
    pub phrase: Phrase,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Left {
    Path(Path),
    Derived(Derived),
    Elapsed(Elapsed),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Term {
    Path(Path),
    Number(String),
    Derived(Derived),
    Elapsed(Elapsed),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Derived {
    pub kind: DerivedKind,
    pub path: Path,
    pub whose: Vec<Condition>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum DerivedKind {
    Count,
    Sum,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Elapsed {
    pub unit: Unit,
    pub from: Path,
    pub to: Path,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Unit {
    Seconds,
    Minutes,
    Hours,
    Days,
    Weeks,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Phrase {
    Is {
        not: bool,
        operand: Operand,
        within: Option<String>,
    },
    Order {
        order: Order,
        operand: Operand,
    },
    Between {
        min: String,
        max: String,
    },
    OneOf {
        not: bool,
        list: List,
    },
    Exists {
        not: bool,
    },
    Empty {
        not: bool,
    },
    NonEmptyString,
    Type(Type),
    Contains {
        not: bool,
        operand: Operand,
    },
    ContainsAll(List),
    ContainsNone(List),
    Matches {
        not: bool,
        list: List,
    },
    StartsWith(Operand),
    EndsWith(Operand),
    Alphabetically {
        after: bool,
        operand: Operand,
    },
    Time {
        time: TimeOrder,
        operand: Operand,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Order {
    AtLeast,
    AtMost,
    MoreThan,
    LessThan,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum TimeOrder {
    Before,
    After,
    OnOrAfter,
    OnOrBefore,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Type {
    List,
    String,
    Number,
    Boolean,
    Object,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Operand {
    Value(Value),
    Field(Vec<Term>),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum List {
    Values(Vec<Value>),
    Path(Path),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Value {
    String(String),
    Number(String),
    True,
    False,
    Null,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Path {
    pub position: Option<Position>,
    pub start: Start,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Position {
    Item { number: String, from_last: bool },
    First,
    Last,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Start {
    It,
    Params,
    Input,
    Field { key: String, dot: bool },
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Step {
    Key(String),
    NamedBy(Reference),
    Brackets(Reference),
    BracketKey(String),
    Index(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Reference {
    Params(String),
    Input(String),
    Name(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct For {
    pub items: Vec<ForItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum ForItem {
    Walk {
        quantifier: Quantifier,
        path: Path,
        whose: Vec<Condition>,
        if_any: bool,
        alias: String,
    },
    Pick {
        position: Position,
        path: Path,
        whose: Vec<Condition>,
        sorted_by: Option<SortedBy>,
        alias: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct SortedBy {
    pub path: Path,
    pub alphabetically: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct From {
    pub every: bool,
    pub path: Path,
    pub named_by_each_of: Option<Path>,
    pub whose: Vec<FromCondition>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum FromCondition {
    Condition(Condition),
    Quantified {
        quantifier: Quantifier,
        path: Path,
        if_any: bool,
        phrase: Phrase,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Side {
    Left,
    Right,
}
