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

/** Reads a policy from YAML text. Returns `{policy, problems}`: when the text isn't YAML, or isn't a mapping, `policy` is `null` and each problem has a `path` like `line 3` and a message. */
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
    return { policy: null, problems: [{ path: "line 1", message: "a policy is a YAML mapping, starting with ergo_spec: v0.3" }] };
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

/** Changes the Markdown `source` so it matches the policy written in the YAML `text`. Returns `{markdown, changes, problems}` like `apply`. An empty `source` gets a new document, and a YAML policy that already matches `source` leaves it as it is. Never throws. */
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

/** Turns pasted YAML into Markdown. Returns `null` unless the text is a policy (it has `ergo_spec`) that can be written as Markdown. */
export const markdownFromPaste = (text) => {
  const read = readYaml(text);
  if (!read.policy || !Object.hasOwn(read.policy, "ergo_spec")) return null;
  return attempt(() => render(read.policy)).markdown;
};
