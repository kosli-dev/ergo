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
};

export const savedEdit = (storage, name, shipped) =>
  attempt(() => {
    const key = editKey(name, shipped);
    dropOthers(storage, name, key);
    return storage.getItem(key) ?? shipped;
  }, shipped);

export const saveEdit = (storage, name, shipped, text) =>
  attempt(() => {
    const key = editKey(name, shipped);
    if (text === shipped) storage.removeItem(key);
    else storage.setItem(key, text);
  }, undefined);

export const forgetEdit = (storage, name, shipped) => attempt(() => storage.removeItem(editKey(name, shipped)), undefined);
