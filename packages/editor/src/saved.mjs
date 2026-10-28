const PREFIX = "ergo-editor:";

/** A short fixed hash of a text, as 8 hexadecimal digits. It tells one shipped text from another and isn't meant for anything else. */
export const hashText = (text) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
};

/** The storage key for the edit of the example `name`, tied to the text it shipped with (`shipped`), so a new shipped text starts from a clean slate. */
export const editKey = (name, shipped) => `${PREFIX}edit:${name}:${hashText(shipped)}`;

const attempt = (run, fallback) => {
  try {
    return run();
  } catch {
    return fallback;
  }
};

const dropOthers = (storage, name, keep) => {
  const stale = [];
  for (let i = 0; i < storage.length; i++) {
    const key = storage.key(i);
    if (key !== keep && (key === PREFIX + name || key.startsWith(`${PREFIX}edit:${name}:`))) stale.push(key);
  }
  for (const key of stale) storage.removeItem(key);
  return stale.length > 0;
};

/** Reads the edit saved for the example `name` from `storage`. Returns `{text, edited, dropped}`: the saved text, or `shipped` when there is none; whether the text was edited; and whether edits saved for an older shipped text were removed. Never throws: when the storage fails, it gives `shipped`. */
export const savedEdit = (storage, name, shipped) =>
  attempt(
    () => {
      const key = editKey(name, shipped);
      const dropped = dropOthers(storage, name, key);
      const text = storage.getItem(key);
      return { text: text ?? shipped, edited: text !== null, dropped };
    },
    { text: shipped, edited: false, dropped: false },
  );

/** Saves `text` as the edit of the example `name`. Saving the shipped text itself removes the edit. Returns `true` when saved, or `false` when the storage failed (and the saved edit is removed). */
export const saveEdit = (storage, name, shipped, text) => {
  const key = editKey(name, shipped);
  const saved = attempt(() => {
    if (text === shipped) storage.removeItem(key);
    else storage.setItem(key, text);
    return true;
  }, false);
  if (!saved) attempt(() => storage.removeItem(key), undefined);
  return saved;
};

/** Removes the edit saved for the example `name`. Never throws. */
export const forgetEdit = (storage, name, shipped) => attempt(() => storage.removeItem(editKey(name, shipped)), undefined);
