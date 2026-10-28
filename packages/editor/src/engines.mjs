/** The engines that can run a policy, in the order the picker lists them. */
export const ENGINES = ["opa", "rust"];

/** The name each engine shows. */
export const ENGINE_LABELS = { opa: "ergo.rego (OPA Wasm)", rust: "ergo-engine (Rust Wasm)" };

/** The engine used when nothing else was chosen. */
export const DEFAULT_ENGINE = "opa";

/** Reads an engine from its saved text. Anything that isn't one of `ENGINES` gives `DEFAULT_ENGINE`. */
export const readEngine = (text) => (ENGINES.includes(text) ? text : DEFAULT_ENGINE);

/** Says which engine made a report, from the report's `engine` field. Gives an empty string when the report doesn't say. */
export const engineNote = (report) => {
  const engine = report?.engine;
  if (typeof engine?.name !== "string") return "";
  return typeof engine.version === "string" ? `Report made by ${engine.name} ${engine.version}.` : `Report made by ${engine.name}.`;
};

/** Wraps the Rust Wasm `report` function so it takes the texts of the input and the params and the policy as an object, and returns the report, or `null` when there is none. The texts stay as typed, so big numbers aren't rounded on the way in. */
export const makeRustRunner = (report) => (inputText, policy, paramsText) => {
  const out = JSON.parse(report(inputText.trim(), JSON.stringify(policy), paramsText.trim()));
  return out ?? null;
};
