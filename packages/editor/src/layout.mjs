/** The views the editor can show, in the order the pickers list them. */
export const VIEWS = ["markdown", "blocks", "policy", "doc", "yaml", "report"];

/** The name each view shows. */
export const LABELS = { markdown: "Markdown", blocks: "Blocks", policy: "Policy", doc: "Document", yaml: "YAML", report: "Report" };

/** The views shown when nothing else was chosen: Markdown on the left and Blocks on the right. */
export const DEFAULT_LAYOUT = { left: "markdown", right: "blocks" };

/** Shows `view` on `side` (`"left"` or `"right"`) and returns the new layout. When the other side already shows it, the two sides swap. */
export const pick = (layout, side, view) => {
  const other = side === "left" ? "right" : "left";
  if (layout[side] === view) return layout;
  if (layout[other] === view) return { [side]: view, [other]: layout[side] };
  return { ...layout, [side]: view };
};

/** Reads a layout from its JSON text. Anything that isn't two different views gives `DEFAULT_LAYOUT`. */
export const readLayout = (text) => {
  try {
    const { left, right } = JSON.parse(text);
    if (VIEWS.includes(left) && VIEWS.includes(right) && left !== right) return { left, right };
  } catch {
    return DEFAULT_LAYOUT;
  }
  return DEFAULT_LAYOUT;
};

/** Writes a layout as JSON text, for storing. */
export const layoutText = (layout) => JSON.stringify({ left: layout.left, right: layout.right });
