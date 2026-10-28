import { parseDocument } from "yaml";
import { compile, apply, render, normalise } from "@kosli/ergo-markdown";

const same = (a, b) => {
  if (a === b) return true;
  if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => Object.hasOwn(b, k) && same(a[k], b[k]));
};

export const readYaml = (text) => {
  const doc = parseDocument(text);
  if (doc.errors.length) {
    return {
      policy: null,
      problems: doc.errors.map((e) => ({
        path: "line " + (e.linePos?.[0]?.line ?? 1),
        message: e.message.split("\n")[0].replace(/ at line \d+, column \d+:?$/, ""),
      })),
    };
  }
  const policy = doc.toJS();
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    return { policy: null, problems: [{ path: "line 1", message: "a policy is a YAML mapping, starting with ergo_spec: v0.2" }] };
  }
  return { policy, problems: [] };
};

const attempt = (run) => {
  try {
    return run();
  } catch (e) {
    return { markdown: null, changes: [], problems: [{ path: "policy", message: "Ergo couldn't write this policy as Markdown: " + (e?.message ?? e) }] };
  }
};

export const editFromYaml = (source, text) => {
  const read = readYaml(text);
  if (!read.policy) return { markdown: null, changes: [], problems: read.problems };
  return attempt(() => {
    if (!source.trim()) {
      const out = render(read.policy);
      return { markdown: out.markdown, changes: out.markdown ? ["wrote a new document from the YAML"] : [], problems: out.problems };
    }
    const current = compile(source);
    if (current.policy && same(normalise(current.policy), normalise(read.policy))) return { markdown: source, changes: [], problems: [] };
    return apply(source, read.policy);
  });
};

export const markdownFromPaste = (text) => {
  const read = readYaml(text);
  if (!read.policy || !Object.hasOwn(read.policy, "ergo_spec")) return null;
  return attempt(() => render(read.policy)).markdown;
};
