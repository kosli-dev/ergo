export const VIEWS = ["markdown", "blocks", "policy", "doc", "yaml", "report"];

export const LABELS = { markdown: "Markdown", blocks: "Blocks", policy: "Policy", doc: "Document", yaml: "YAML", report: "Report" };

export const DEFAULT_LAYOUT = { left: "markdown", right: "blocks" };

export const pick = (layout, side, view) => {
  const other = side === "left" ? "right" : "left";
  if (layout[side] === view) return layout;
  if (layout[other] === view) return { [side]: view, [other]: layout[side] };
  return { ...layout, [side]: view };
};

export const readLayout = (text) => {
  try {
    const { left, right } = JSON.parse(text);
    if (VIEWS.includes(left) && VIEWS.includes(right) && left !== right) return { left, right };
  } catch {
    return DEFAULT_LAYOUT;
  }
  return DEFAULT_LAYOUT;
};

export const layoutText = (layout) => JSON.stringify({ left: layout.left, right: layout.right });
