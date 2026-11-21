use super::*;

pub(super) struct Walked<'a> {
    pub(super) entries: Vec<Entry<'a>>,
    pub(super) broken: Vec<Broken>,
    pub(super) lists: bool,
    pub(super) gone: bool,
}

fn walk_level<'a>(
    entries: Vec<Fe<'a>>,
    seg: &walk::Seg,
    root: &str,
    child: bool,
    broken: &mut Vec<Broken>,
    notes: &mut Vec<Note>,
) -> (Vec<Fe<'a>>, bool) {
    let lists = !matches!(seg, walk::Seg::Index(_)) && entries.iter().any(|e| fv_list(&e.v));
    if lists
        && let (Some(first), Some(other)) = (
            entries.iter().find(|e| fv_list(&e.v)),
            entries.iter().find(|e| !fv_list(&e.v) && !fv_gone(&e.v)),
        )
    {
        notes.push(mixed_note(first, other, root, child));
    }
    let mut expanded = Vec::new();
    for e in entries {
        if lists && let Fv::Val(Value::Array(items)) = e.v {
            for (j, item) in items.iter().enumerate() {
                let mut here = e.segs.clone();
                here.push(walk::Seg::Index(j as u64));
                let at = here.len();
                expanded.push(Fe {
                    segs: here,
                    item: at,
                    v: Fv::Val(item),
                    listed: true,
                    at: e.at.index(j as u64),
                    why: None,
                });
            }
        } else if lists && fv_gone(&e.v) {
            broken.push(fl_broken(&e, fv_cause(&e.v), root, child));
        } else {
            expanded.push(e);
        }
    }
    let mut next = Vec::new();
    for x in expanded {
        let item_read = matches!(seg, walk::Seg::Key(_))
            && x.listed
            && matches!(x.v, Fv::Val(v) if !v.is_object() && !v.is_null());
        if item_read {
            let cause = if fv_list(&x.v) {
                Cause::NotAnObject
            } else {
                Cause::Unusable
            };
            let mut said = x.clone();
            said.why = Some(Why {
                segs: x.segs.clone(),
                value: fv_shown(&x.v),
                kind: "an object",
            });
            broken.push(fl_broken(&said, cause, root, child));
        } else {
            next.push(fl_read(&x, seg));
        }
    }
    (next, lists)
}

fn members<'a>(
    ends: Vec<Fe<'a>>,
    root: &str,
    child: bool,
    broken: &mut Vec<Broken>,
) -> Vec<Fe<'a>> {
    let mut kept = Vec::new();
    for e in ends {
        match e.v {
            Fv::Val(Value::Object(map)) => {
                let mut keys: Vec<&String> = map.keys().collect();
                keys.sort();
                for key in keys {
                    let mut segs = e.segs.clone();
                    segs.push(walk::Seg::Key(key.clone()));
                    kept.push(Fe {
                        segs,
                        item: e.item,
                        v: Fv::Val(&map[key]),
                        listed: true,
                        at: e.at.key(key),
                        why: None,
                    });
                }
            }
            Fv::Val(value) if !value.is_null() => {
                let mut said = e.clone();
                said.why = Some(Why {
                    segs: e.segs.clone(),
                    value: value.clone(),
                    kind: "an object",
                });
                broken.push(fl_broken(&said, Cause::Unusable, root, child));
            }
            _ => broken.push(fl_broken(&e, fv_cause(&e.v), root, child)),
        }
    }
    kept
}

pub(super) fn member_walk<'a>(
    base: &Located<'a>,
    segs: &[walk::Seg],
    root: &str,
    child: bool,
) -> Walked<'a> {
    let mut ends = vec![Fe {
        segs: Vec::new(),
        item: 0,
        v: Fv::Val(base.value),
        listed: false,
        at: base.location.clone(),
        why: None,
    }];
    let mut broken: Vec<Broken> = Vec::new();
    let mut notes: Vec<Note> = Vec::new();
    let mut any = false;
    for seg in segs {
        let (next, lists) = walk_level(ends, seg, root, child, &mut broken, &mut notes);
        any |= lists;
        ends = next;
    }
    let gone = ends.iter().any(|e| fv_gone(&e.v));
    let kept = members(ends, root, child, &mut broken);
    if let Some(note) = types_note(
        kept.iter().filter_map(|e| match e.v {
            Fv::Val(value) => Some((e.segs.clone(), value, e.at.clone())),
            _ => None,
        }),
        root,
        child,
        false,
    ) {
        notes.push(note);
    }
    for note in notes {
        broken.extend(note.brokens(root, child));
    }
    broken.sort_by(|a, b| a.order.cmp(&b.order));
    broken.dedup_by(|a, b| {
        a.listed
            && b.listed
            && a.msg.is_empty()
            && a.order == b.order
            && a.cause == b.cause
            && a.value == b.value
            && a.location == b.location
    });
    let entries = kept
        .into_iter()
        .filter_map(|e| match (e.v, e.segs.last()) {
            (Fv::Val(value), Some(walk::Seg::Key(key))) => Some(Entry {
                key: Some(key.clone()),
                at: Located {
                    value,
                    location: e.at,
                },
                copies: Vec::new(),
            }),
            _ => None,
        })
        .collect();
    Walked {
        entries,
        broken,
        lists: any,
        gone,
    }
}

pub(super) fn member_entries<'a>(
    env: &Env<'a>,
    empty: &'a Value,
    lowered: &Lowered,
    anc: &[Anc<'a>],
) -> Read<'a> {
    let (Source::Root { path, .. } | Source::Child { path, .. }) = &lowered.source;
    let child = matches!(lowered.source, Source::Child { .. });
    let path = &flat_path(path);
    let base = if child {
        let Some(parent) = anc.last() else {
            return Read::Failed(Cause::Unusable);
        };
        if std::ptr::eq(parent.at.value, empty) {
            return Read::Failed(Cause::Absent);
        }
        match (parent.at.value, path.steps.first()) {
            (Value::Object(_), _) | (Value::Array(_), Some(_)) => {}
            (Value::Null, Some(Step::Index(_))) => return Read::Failed(Cause::Absent),
            (_, Some(Step::Index(_))) => return Read::Failed(Cause::Unusable),
            _ => return Read::Failed(Cause::NotAnObject),
        }
        parent.at.clone()
    } else {
        input_root(env)
    };
    let ctx = context(env, input_root(env), anc);
    let Some(segs) = resolved_segs(&path.steps, &ctx) else {
        return Read::Failed(Cause::Unusable);
    };
    let root = root_name(child, anc);
    let walked = member_walk(&base, &segs, &root, child);
    let (mut entries, broken) = if !walked.lists && walked.gone {
        match walk_from(env, path, anc, base) {
            Read::Entries { mut broken, .. } => {
                if child {
                    for each in &mut broken {
                        each.path = start_name(&each.order, &root, true);
                    }
                }
                (Vec::new(), broken)
            }
            failed => return failed,
        }
    } else {
        (walked.entries, walked.broken)
    };
    if lowered.id.is_some() {
        for entry in &mut entries {
            entry.key = None;
        }
    }
    Read::Entries { entries, broken }
}

#[cfg(test)]
mod tests;
