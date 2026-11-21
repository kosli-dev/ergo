use super::{Entry, ItemAt, Raw, Seg, Val, failed};
use crate::name;
use crate::path::{Located, Path, Step};
use serde_json::{Value, json};

pub(super) const WANTS: &str = "an object";

pub(super) fn expand<'a>(entries: Vec<Entry<'a>>, empty_ok: bool) -> (Vec<Entry<'a>>, Vec<Raw>) {
    let mut next = Vec::new();
    let mut raws = Vec::new();
    for entry in entries {
        let Val::Found(Value::Object(map)) = entry.val else {
            raws.push(failed(&entry, entry.val.cause(), entry.val.shown(), WANTS));
            continue;
        };
        if map.is_empty() && !empty_ok {
            raws.push(failed(&entry, crate::cause::Cause::Value, json!({}), WANTS));
        }
        let mut keys: Vec<&String> = map.keys().collect();
        keys.sort();
        for key in keys {
            let value = &map[key];
            let mut segs = entry.segs.clone();
            segs.push(Seg::Member(key.clone()));
            let location = entry.location.key(key);
            next.push(Entry {
                segs: segs.clone(),
                val: Val::Found(value),
                location: location.clone(),
                item: Some(ItemAt {
                    segs,
                    at: Located { value, location },
                }),
                rest: Vec::new(),
                unaliased: entry.unaliased,
            });
        }
    }
    (next, raws)
}

pub(super) fn stop_before_end(trail: &[(Vec<Seg>, Val, crate::path::Location)]) -> Option<usize> {
    let before_end = trail.len().saturating_sub(1);
    trail[..before_end]
        .iter()
        .position(|(_, val, _)| !val.container())
}

pub(super) fn split(path: &Path) -> (Path, bool) {
    match path.steps.split_last() {
        Some((Step::Members, before)) => (
            Path {
                start: path.start.clone(),
                steps: before.to_vec(),
            },
            true,
        ),
        _ => (path.clone(), false),
    }
}

pub(super) fn named(key: &str, list: &str) -> String {
    format!("member {} of {list}", name::key_text(key))
}

#[cfg(test)]
mod tests;
