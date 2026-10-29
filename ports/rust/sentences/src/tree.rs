/// The `check` rule: one or more assertions joined by `and`.
///
/// ```text
/// a is 1 and b exists
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Check {
    /// The assertions, in the order written.
    pub assertions: Vec<Assertion>,
}

/// The `assertion` rule: one statement a check makes.
///
/// ```text
/// x is 1
/// every xs whose y is 1 exists
/// count of xs is 2
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Assertion {
    /// A path followed by a phrase, like `x is 1`.
    Plain {
        /// The path being checked.
        path: Path,
        /// What is said about it.
        phrase: Phrase,
    },
    /// A walk over a list, like `every xs whose y is 1 exists`.
    Quantified {
        /// `every` or `some`.
        quantifier: Quantifier,
        /// The list walked.
        path: Path,
        /// The `whose` conditions that pick items.
        whose: Vec<Condition>,
        /// True when `if any` is written.
        if_any: bool,
        /// What must hold for the items.
        phrase: Phrase,
    },
    /// A value worked out from a list, like `count of xs is 2`.
    Derived {
        /// The terms that make up the left side.
        terms: Vec<Term>,
        /// What is said about the result.
        phrase: Phrase,
    },
}

/// The `quantifier` rule: how many items must match.
///
/// ```text
/// every
/// some
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Quantifier {
    /// `every`.
    Every,
    /// `some`.
    Some,
}

/// The `condition` rule: a left side and a phrase, used after `whose`.
///
/// ```text
/// y is 1
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Condition {
    /// What the condition looks at.
    pub left: Left,
    /// What is said about it.
    pub phrase: Phrase,
}

/// The left side of a condition.
///
/// ```text
/// y
/// count of ys
/// days elapsed from a to b
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Left {
    /// A path.
    Path(Path),
    /// A `count` or `sum`.
    Derived(Derived),
    /// A time between two paths.
    Elapsed(Elapsed),
}

/// The `term` rule: one part of a left side or an operand.
///
/// ```text
/// y
/// 1
/// count of ys
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Term {
    /// A path.
    Path(Path),
    /// A number, with its digits as written.
    Number(String),
    /// A `count` or `sum`.
    Derived(Derived),
    /// A time between two paths.
    Elapsed(Elapsed),
}

/// The `derived` and `derived-left` rules: a `count` or `sum` of a list.
///
/// ```text
/// sum of ys
/// count of ys whose z is 1
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Derived {
    /// `count` or `sum`.
    pub kind: DerivedKind,
    /// The list.
    pub path: Path,
    /// The `whose` conditions that pick items.
    pub whose: Vec<Condition>,
}

/// The `derived` rule's choice of word.
///
/// ```text
/// count
/// sum
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum DerivedKind {
    /// `count`.
    Count,
    /// `sum`.
    Sum,
}

/// The `elapsed` rule: the time between two paths.
///
/// ```text
/// hours elapsed from started to ended
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Elapsed {
    /// The unit of time.
    pub unit: Unit,
    /// The path for the start.
    pub from: Path,
    /// The path for the end.
    pub to: Path,
}

/// The `elapsed` rule's unit of time.
///
/// ```text
/// seconds
/// minutes
/// hours
/// days
/// weeks
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Unit {
    /// `seconds`.
    Seconds,
    /// `minutes`.
    Minutes,
    /// `hours`.
    Hours,
    /// `days`.
    Days,
    /// `weeks`.
    Weeks,
}

/// The `phrase` rule: what a check says about a value.
///
/// ```text
/// is empty
/// is one of 1, 2
/// is 1 within 2
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Phrase {
    /// `is` or `is not` a value, with an optional `within`.
    Is {
        /// True for `is not`.
        not: bool,
        /// The value compared with.
        operand: Operand,
        /// The `within` number, with its digits as written.
        within: Option<String>,
    },
    /// `is at least`, `is at most`, `is more than` or `is less than`.
    Order {
        /// Which comparison.
        order: Order,
        /// The value compared with.
        operand: Operand,
    },
    /// `is between` two numbers.
    Between {
        /// The lower number, with its digits as written.
        min: String,
        /// The upper number, with its digits as written.
        max: String,
    },
    /// `is one of` or `is not one of` a list.
    OneOf {
        /// True for `is not one of`.
        not: bool,
        /// The list of choices.
        list: List,
    },
    /// `exists` or `does not exist`.
    Exists {
        /// True for `does not exist`.
        not: bool,
    },
    /// `is empty` or `is not empty`.
    Empty {
        /// True for `is not empty`.
        not: bool,
    },
    /// `is a non-empty string`.
    NonEmptyString,
    /// `is a` followed by a type, like `is a list`.
    Type(Type),
    /// `contains` or `does not contain` a value.
    Contains {
        /// True for `does not contain`.
        not: bool,
        /// The value looked for.
        operand: Operand,
    },
    /// `contains all of` a list.
    ContainsAll(List),
    /// `contains none of` a list.
    ContainsNone(List),
    /// `matches` or `does not match` one or more patterns.
    Matches {
        /// True for `does not match`.
        not: bool,
        /// The patterns.
        list: List,
    },
    /// `starts with` a value.
    StartsWith(Operand),
    /// `ends with` a value.
    EndsWith(Operand),
    /// `is alphabetically before` or `is alphabetically after` a value.
    Alphabetically {
        /// True for `after`, false for `before`.
        after: bool,
        /// The value compared with.
        operand: Operand,
    },
    /// A time comparison, like `is before`.
    Time {
        /// Which comparison.
        time: TimeOrder,
        /// The value compared with.
        operand: Operand,
    },
}

/// The `order-phrase` rule: a comparison of numbers.
///
/// ```text
/// is at least
/// is at most
/// is more than
/// is less than
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Order {
    /// `is at least`.
    AtLeast,
    /// `is at most`.
    AtMost,
    /// `is more than`.
    MoreThan,
    /// `is less than`.
    LessThan,
}

/// The `time-phrase` rule: a comparison of times.
///
/// ```text
/// is before
/// is after
/// is on or after
/// is on or before
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum TimeOrder {
    /// `is before`.
    Before,
    /// `is after`.
    After,
    /// `is on or after`.
    OnOrAfter,
    /// `is on or before`.
    OnOrBefore,
}

/// The `type` rule: a kind of value.
///
/// ```text
/// list
/// string
/// number
/// boolean
/// object
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Type {
    /// `list`.
    List,
    /// `string`.
    String,
    /// `number`.
    Number,
    /// `boolean`.
    Boolean,
    /// `object`.
    Object,
}

/// The `operand` rule: what a phrase compares with.
///
/// ```text
/// 1
/// y
/// y plus 1
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Operand {
    /// A written value.
    Value(Value),
    /// A field, or fields added with `plus`.
    Field(Vec<Term>),
}

/// The `list` rule: values written out, or a path to a list.
///
/// ```text
/// 1, 2
/// $params.allowed
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum List {
    /// Values written out.
    Values(Vec<Value>),
    /// A path to a list.
    Path(Path),
}

/// The `value` rule: a written value.
///
/// ```text
/// "a"
/// 'a'
/// -1.5e3
/// true
/// null
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Value {
    /// A string, decoded.
    String(String),
    /// A number, with its digits as written.
    Number(String),
    /// `true`.
    True,
    /// `false`.
    False,
    /// `null`.
    Null,
}

/// The `path`, `right-path` and `it-path` rules: where to find a value.
///
/// ```text
/// a.b[1]
/// item 2 of xs
/// .empty
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Path {
    /// The `item N of`, `first of` or `last of` part, if any.
    pub position: Option<Position>,
    /// Where the path starts.
    pub start: Start,
    /// The steps after the start.
    pub steps: Vec<Step>,
}

/// The `position` rule: which item of a list.
///
/// ```text
/// item 3
/// item 2 from last
/// first
/// last
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Position {
    /// `item N` or `item N from last`.
    Item {
        /// The number, with its digits as written.
        number: String,
        /// True for `from last`.
        from_last: bool,
    },
    /// `first`.
    First,
    /// `last`.
    Last,
}

/// The `start`, `plain-right` and `it` rules: the first word of a path.
///
/// ```text
/// it
/// $params
/// $input
/// name
/// .name
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Start {
    /// `it`.
    It,
    /// `$params`.
    Params,
    /// `$input`.
    Input,
    /// A field name.
    Field {
        /// The name, decoded.
        key: String,
        /// True when written with a leading dot, like `.name`.
        dot: bool,
    },
}

/// The `step` rule: one move along a path.
///
/// ```text
/// .key
/// named by k
/// [k]
/// ["a b"]
/// [2]
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Step {
    /// `.key`.
    Key(String),
    /// `named by` a reference.
    NamedBy(Reference),
    /// A reference in brackets, like `[k]`.
    Brackets(Reference),
    /// A quoted key in brackets, like `["a b"]`.
    BracketKey(String),
    /// A list index in brackets, like `[2]`, with its digits as written.
    Index(String),
}

/// The `reference` rule: a name looked up in params, in the input or among the aliases.
///
/// ```text
/// $params.k
/// $input.k
/// k
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Reference {
    /// `$params.k`.
    Params(String),
    /// `$input.k`.
    Input(String),
    /// A bare name.
    Name(String),
}

/// The `for-line` rule: the items a check is run for.
///
/// ```text
/// every xs as x, last of ys as y
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct ForLine {
    /// The items, in the order written.
    pub items: Vec<ForItem>,
}

/// The `for-item` rule: one item of a `for` line.
///
/// ```text
/// some xs whose a is 1 as x
/// last of ys sorted by d as y
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum ForItem {
    /// `every` or `some` of a list.
    Walk {
        /// `every` or `some`.
        quantifier: Quantifier,
        /// The list walked.
        path: Path,
        /// The `whose` conditions that pick items.
        whose: Vec<Condition>,
        /// True when `if any` is written.
        if_any: bool,
        /// The name given with `as`.
        alias: String,
    },
    /// One item at a position, like `last of ys`.
    Pick {
        /// Which item.
        position: Position,
        /// The list.
        path: Path,
        /// The `whose` conditions that pick items.
        whose: Vec<Condition>,
        /// The sort order, if written.
        sorted_by: Option<SortedBy>,
        /// The name given with `as`.
        alias: String,
    },
}

/// The `sorted-by` rule: how a list is ordered before an item is picked.
///
/// ```text
/// sorted by created alphabetically
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct SortedBy {
    /// The path to sort on.
    pub path: Path,
    /// True when `alphabetically` is written.
    pub alphabetically: bool,
}

/// The `from-line` rule: where a subject's items come from.
///
/// ```text
/// every a.b named by each of $params.l whose c is 1
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct FromLine {
    /// True when the line starts with `every`.
    pub every: bool,
    /// The path to the items.
    pub path: Path,
    /// The path of the names, if `named by each of` is written.
    pub named_by_each_of: Option<Path>,
    /// The `whose` conditions.
    pub whose: Vec<FromCondition>,
}

/// The `from-condition` rule: one `whose` condition of a `from` line.
///
/// ```text
/// c is 1
/// some d.e, if any, exists
/// ```
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum FromCondition {
    /// A plain condition.
    Condition(Condition),
    /// A condition on some or every item of a list.
    Quantified {
        /// `every` or `some`.
        quantifier: Quantifier,
        /// The list.
        path: Path,
        /// True when `if any` is written.
        if_any: bool,
        /// What must hold.
        phrase: Phrase,
    },
}

/// Where a path is printed. It has no ABNF rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub enum Side {
    /// On the left of a phrase.
    Left,
    /// On the right of a phrase.
    Right,
}
