const PREFIX = "ergo-editor:";

export const hashText = (text) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, "0");
};

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

export const forgetEdit = (storage, name, shipped) => attempt(() => storage.removeItem(editKey(name, shipped)), undefined);
