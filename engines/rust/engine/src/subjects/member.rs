use super::*;

pub(super) struct Walked<'a> {
    pub(super) entries: Vec<Entry<'a>>,
    pub(super) broken: Vec<Broken>,
    pub(super) lists: bool,
}

pub(super) fn member_walk<'a>(
    _base: &Located<'a>,
    _segs: &[walk::Seg],
    _root: &str,
    _child: bool,
) -> Walked<'a> {
    Walked {
        entries: Vec::new(),
        broken: Vec::new(),
        lists: false,
    }
}

#[cfg(test)]
mod tests;
