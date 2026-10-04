import yaml from "../../playground/vendor/js-yaml.mjs";

export const byCodePoint = (a, b) => {
  const x = [...a], y = [...b];
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d !== 0) return d;
  }
  return x.length - y.length;
};

export const sortKeys = (v) => {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v === null || typeof v !== "object") return v;
  return Object.fromEntries(Object.keys(v).sort(byCodePoint).map((k) => [k, sortKeys(v[k])]));
};

const isScalar = (v) => v === null || typeof v !== "object";
const isFlat = (v) => isScalar(v) || (Array.isArray(v) && v.every(isScalar)) || Object.keys(v).length === 0;

export const parseRego = (text) => {
  let i = 0;
  const fail = (msg) => {
    const before = text.slice(0, i).split("\n");
    throw new Error(`${msg} at line ${before.length}, column ${before.at(-1).length + 1}`);
  };
  const skip = () => {
    for (let m; (m = /^(?:\s+|#[^\n]*)/.exec(text.slice(i))); ) i += m[0].length;
  };
  const peek = () => { skip(); return text[i]; };
  const eat = (re) => {
    skip();
    const m = re.exec(text.slice(i));
    if (m) i += m[0].length;
    return m;
  };
  const expect = (ch) => { if (peek() !== ch) fail(`expected ${ch}`); i++; };
  const list = (close, item) => {
    const out = [];
    while (peek() !== close) {
      out.push(item());
      if (peek() === ",") i++;
      else if (peek() !== close) fail(`expected , or ${close}`);
    }
    i++;
    return out;
  };
  const value = () => {
    let m;
    if (eat(/^\{/)) {
      if (peek() === "}") { i++; return {}; }
      const first = value();
      if (peek() !== ":") {
        const rest = peek() === "," ? (i++, list("}", value)) : (expect("}"), []);
        return [first, ...rest];
      }
      const obj = {};
      const entry = (key) => {
        if (typeof key !== "string") fail("keys must be strings");
        if (Object.hasOwn(obj, key)) fail(`${JSON.stringify(key)} is given twice`);
        expect(":");
        Object.defineProperty(obj, key, { value: value(), enumerable: true, writable: true, configurable: true });
      };
      entry(first);
      if (peek() === ",") { i++; list("}", () => entry(value())); } else expect("}");
      return obj;
    }
    if (eat(/^\[/)) return list("]", value);
    if (eat(/^set\(\s*\)/)) return [];
    if ((m = eat(/^"(?:[^"\\\n]|\\.)*"/))) return JSON.parse(m[0]);
    if ((m = eat(/^`[^`]*`/))) return m[0].slice(1, -1);
    if ((m = eat(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w.])/))) return Number(m[0]);
    if ((m = eat(/^(?:true|false|null)\b/))) return JSON.parse(m[0]);
    fail(i >= text.length ? "unexpected end" : "unexpected input");
  };
  eat(/^[A-Za-z_]\w*\s*:?=/);
  const v = value();
  skip();
  if (i < text.length) fail("unexpected input after the value");
  return v;
};

const regoValue = (v, ind) => {
  if (isScalar(v)) return JSON.stringify(v);
  const inner = ind + "\t";
  if (Array.isArray(v)) {
    if (isFlat(v)) return `[${v.map((x) => regoValue(x, inner)).join(", ")}]`;
    return `[\n${v.map((x) => `${inner}${regoValue(x, inner)},\n`).join("")}${ind}]`;
  }
  if (isFlat(v)) return "{}";
  return `{\n${Object.keys(v).map((k) => `${inner}${JSON.stringify(k)}: ${regoValue(v[k], inner)},\n`).join("")}${ind}}`;
};

export const toRego = (v) => `requirements := ${regoValue(v, "")}\n`;

const flow = (v) => yaml.dump(v, { flowLevel: 0, lineWidth: -1 }).trimEnd();

const yamlBlock = (v, ind) => {
  const inner = ind + "  ";
  if (Array.isArray(v)) {
    return v.map((x) => `${ind}- ${(isFlat(x) ? inner + flow(x) : yamlBlock(x, inner)).slice(inner.length)}`).join("\n");
  }
  return Object.entries(v).map(([k, x]) => {
    const key = `${ind}${flow(k)}:`;
    if (isFlat(x)) return `${key} ${flow(x)}`;
    return `${key}\n${yamlBlock(x, Array.isArray(x) ? ind : inner)}`;
  }).join("\n");
};

export const toYaml = (v) => `${isFlat(v) ? flow(v) : yamlBlock(v, "")}\n`;

export const formats = {
  yaml: { parse: (t) => yaml.load(t) ?? null, write: toYaml },
  json: { parse: (t) => JSON.parse(t), write: (v) => JSON.stringify(v, null, 2) + "\n" },
  rego: { parse: parseRego, write: toRego },
};

export const bakeryRequirements = (fileText) => toYaml(yaml.load(fileText).baking.requirements);

export const parseTime = (v) => {
  if (!JSON.rawJSON) throw new Error("this browser can't hold a time in nanoseconds exactly, so compare_time can't run here");
  const [, time, fraction = "", zone] = /^(.{19})(?:\.(\d+))?(.*)$/.exec(v);
  return JSON.rawJSON(String(BigInt(Date.parse(time + zone)) / 1000n * 1000000000n + BigInt(fraction.padEnd(9, "0").slice(0, 9))));
};

const b64 = {
  encode: (bytes) => btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join("")).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, ""),
  decode: (s) => Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0)),
};

const pipe = async (bytes, stream) => new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(stream)).arrayBuffer());

export const encodeState = async (state) => b64.encode(await pipe(new TextEncoder().encode(JSON.stringify(state)), new CompressionStream("deflate-raw")));

export const decodeState = async (hash) => {
  const s = JSON.parse(new TextDecoder().decode(await pipe(b64.decode(hash), new DecompressionStream("deflate-raw"))));
  if (typeof s?.r !== "string" || typeof s.i !== "string" || !Object.hasOwn(formats, s.rf) || !["json", "yaml"].includes(s.if)) throw new Error("not a playground link");
  return s;
};
