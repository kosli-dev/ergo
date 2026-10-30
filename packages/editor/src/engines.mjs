/** The engines that can run a policy, in the order the picker lists them. */
export const ENGINES = ["opa", "rust"];

/** The name each engine shows. */
export const ENGINE_LABELS = { opa: "ergo.rego", rust: "Rust port (experimental)" };

const RUST_ENGINE_NAME = "ergo-engine";

/** The engine used when nothing else was chosen. */
export const DEFAULT_ENGINE = "opa";

/** Reads an engine from its saved text. Anything that isn't one of `ENGINES` gives `DEFAULT_ENGINE`. */
export const readEngine = (text) => (ENGINES.includes(text) ? text : DEFAULT_ENGINE);

/** Says which engine made a report, from the report's `engine` field. Gives an empty string when the report doesn't say. */
export const engineNote = (report) => {
  const engine = report?.engine;
  if (typeof engine?.name !== "string") return "";
  if (engine.name === RUST_ENGINE_NAME) return typeof engine.version === "string" ? `Report made by the Rust port (${engine.name} ${engine.version}).` : `Report made by the Rust port (${engine.name}).`;
  return typeof engine.version === "string" ? `Report made by ${engine.name} ${engine.version}.` : `Report made by ${engine.name}.`;
};

/** Says that the engine is still loading, didn't load or couldn't run, naming the engine that was picked. `detail` is the error's message and ends the text for `"failed"` and `"run"`. */
export const engineMessage = (engine, kind, detail = "") => {
  const name = engine === "rust" ? "The Rust port" : "ergo.rego";
  if (kind === "loading") return `${name} is still loading.`;
  if (kind === "failed") return `${name} didn't load: ${detail}`;
  return `${name} couldn't run this: ${detail}`;
};

/** Makes a runner with `make` and returns one that calls it. When a call throws a `WebAssembly.RuntimeError`, which is a panic that leaves the module half way through a call, the runner is dropped and the next call makes a new one. Other errors keep it. Every error goes on to the caller. */
export const renewOnPanic = (make) => {
  let run = make();
  return (...args) => {
    run ??= make();
    try {
      return run(...args);
    } catch (e) {
      if (e instanceof WebAssembly.RuntimeError) run = null;
      throw e;
    }
  };
};

/** Wraps the Rust Wasm `report` function so it takes the texts of the input and the params and the policy as an object, and returns the report, or `null` when there is none. The texts stay as typed, so big numbers aren't rounded on the way in. */
export const makeRustRunner = (report) => (inputText, policy, paramsText) => {
  const out = JSON.parse(report(inputText.trim(), JSON.stringify(policy), paramsText.trim()));
  return out ?? null;
};
