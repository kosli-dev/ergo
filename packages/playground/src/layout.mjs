/** The views the playground can show, in the order the pickers list them. */
export const VIEWS = ["yaml", "report", "policy", "markdown", "blocks", "doc"];

/** The name each view shows. */
export const LABELS = { yaml: "YAML", report: "Report", policy: "Policy", markdown: "Markdown (experimental)", blocks: "Blocks", doc: "Document" };

/** The views shown when nothing else was chosen: YAML on the left and the Report on the right. */
export const DEFAULT_LAYOUT = { left: "yaml", right: "report" };

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

/** Gives the view the note under the page is about: the pane you edit (`"yaml"` or `"markdown"`, the left one when both), else the right pane. */
export const noteView = (layout) => [layout.left, layout.right].find((v) => v === "yaml" || v === "markdown") ?? layout.right;

/** Says whether the colour legend is worth showing: some open pane shows Markdown or Blocks, the views that colour lines the way it says. */
export const showsLegend = (layout) => [layout.left, layout.right].some((v) => v === "markdown" || v === "blocks");
