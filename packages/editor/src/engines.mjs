/** The engines that can run a policy, in the order the picker lists them. */
export const ENGINES = ["opa", "rust"];

/** The name each engine shows. */
export const ENGINE_LABELS = { opa: "Rego engine", rust: "Rust engine (experimental)" };

const RUST_ENGINE_NAME = "ergo-policy-engine";

/** The engine used when nothing else was chosen. */
export const DEFAULT_ENGINE = "opa";

/** Reads an engine from its saved text. Anything that isn't one of `ENGINES` gives `DEFAULT_ENGINE`. */
export const readEngine = (text) => (ENGINES.includes(text) ? text : DEFAULT_ENGINE);

/** Writes a time in milliseconds with one decimal under 10 ms and as a whole number from 10 ms on. */
export const formatMs = (ms) => {
  const tenths = Math.round(ms * 10) / 10;
  return tenths < 10 ? `${tenths.toFixed(1)} ms` : `${Math.round(ms)} ms`;
};

/** Says which engine made a report, from the report's `engine` field, and how long the report took when `ms` is a number. Gives an empty string when the report doesn't say. */
export const engineNote = (report, ms) => {
  const engine = report?.engine;
  if (typeof engine?.name !== "string") return "";
  const made = typeof engine.version === "string" ? `${engine.name} ${engine.version}` : engine.name;
  const took = typeof ms === "number" ? ` in ${formatMs(ms)}` : "";
  if (engine.name === RUST_ENGINE_NAME) return `Report made by the Rust engine (${made})${took}.`;
  if (engine.name === "ergo.rego") return `Report made by the Rego engine (${made})${took}.`;
  return `Report made by ${made}${took}.`;
};

/** Wraps `fn` so each call records how many milliseconds it took in the wrapper's `ms`, read from `clock`. `ms` is `null` until the first call ends. */
export const timed = (fn, clock = () => performance.now()) => {
  const wrapped = (...args) => {
    const start = clock();
    try {
      return fn(...args);
    } finally {
      wrapped.ms = clock() - start;
    }
  };
  wrapped.ms = null;
  return wrapped;
};

const attempt = (fn) => {
  try {
    return fn();
  } catch (e) {
    return e;
  }
};

/** Runs `run` once on an empty input, policy and params, so the first report people see isn't slowed by the browser compiling the engine's code, then puts it in `runners` under `name`. Whatever that run gives or throws is ignored. */
export const loadEngine = (runners, name, run) => {
  attempt(() => run("{}", {}, "{}"));
  runners[name] = run;
};

/** Says that the engine is still loading, didn't load or couldn't run, naming the engine that was picked. `detail` is the error's message and ends the text for `"failed"` and `"run"`. */
export const engineMessage = (engine, kind, detail = "") => {
  const name = engine === "rust" ? "The Rust engine" : "The Rego engine";
  if (kind === "loading") return `${name} is still loading.`;
  if (kind === "failed") return `${name} didn't load: ${detail}`;
  if (kind === "stopped") return `${name} stopped after an internal error. Reload the page to use it again.`;
  return `${name} couldn't run this: ${detail}`;
};

/** Returns a runner that calls `run` until a call throws a `WebAssembly.RuntimeError`, which is a panic that leaves the module half way through a call. That call and every later one throw an error marked `stopped` that says to reload the page, and `run` isn't called again. Other errors reach the caller as they are. */
export const stopOnPanic = (engine, run) => {
  let stopped = false;
  const stop = () => Object.assign(new Error(engineMessage(engine, "stopped")), { stopped: true });
  return (...args) => {
    if (stopped) throw stop();
    try {
      return run(...args);
    } catch (e) {
      if (!(e instanceof WebAssembly.RuntimeError)) throw e;
      stopped = true;
      throw stop();
    }
  };
};

/** Wraps the Rust Wasm `report` function so it takes the texts of the input and the params and the policy as an object, and returns the report, or `null` when there is none. The texts stay as typed, so big numbers aren't rounded on the way in. */
export const makeRustRunner = (report) => (inputText, policy, paramsText) => {
  const out = JSON.parse(report(inputText.trim(), JSON.stringify(policy), paramsText.trim()));
  return out ?? null;
};
