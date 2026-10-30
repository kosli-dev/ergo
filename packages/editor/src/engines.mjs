/** The engines that can run a policy, in the order the picker lists them. */
export const ENGINES = ["opa", "rust"];

/** The name each engine shows. */
export const ENGINE_LABELS = { opa: "Rego engine", rust: "Rust engine (experimental)" };

const RUST_ENGINE_NAME = "ergo-engine";

/** The engine used when nothing else was chosen. */
export const DEFAULT_ENGINE = "opa";

/** Reads an engine from its saved text. Anything that isn't one of `ENGINES` gives `DEFAULT_ENGINE`. */
export const readEngine = (text) => (ENGINES.includes(text) ? text : DEFAULT_ENGINE);

/** Says which engine made a report, from the report's `engine` field. Gives an empty string when the report doesn't say. */
export const engineNote = (report) => {
  const engine = report?.engine;
  if (typeof engine?.name !== "string") return "";
  const made = typeof engine.version === "string" ? `${engine.name} ${engine.version}` : engine.name;
  if (engine.name === RUST_ENGINE_NAME) return `Report made by the Rust engine (${made}).`;
  if (engine.name === "ergo.rego") return `Report made by the Rego engine (${made}).`;
  return `Report made by ${made}.`;
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
