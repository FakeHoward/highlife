/** Escape text before applying a small Markdown subset to HTML. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Strip a small Markdown subset down to plain text (room-list previews). */
export function markdownToPlain(source: string): string {
  if (!source) return "";
  return source
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/\*\*([^*\n]+)\*\*/g, "$1")
    .replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)/g, "$1$2")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .trim();
}

/**
 * Lightweight Markdown → HTML for chat bodies.
 * Order: escape → code → bold → italic → paragraphs/breaks.
 */
export function markdownToHtml(source: string): string {
  if (!source) return "";
  let html = escapeHtml(source);
  html = html.replace(/`([^`\n]+)`/g, "<code>$1</code>");
  html = html.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>");
  html = html.replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,!?:;]|$)/g, "$1<em>$2</em>");
  html = html.replace(
    /\[([^\]]+)\]\((https?:[^)\s]+)\)/g,
    '<a href="$2" rel="noreferrer noopener" target="_blank">$1</a>',
  );
  return html
    .split(/\n{2,}/)
    .map((block) => `<p>${block.replace(/\n/g, "<br/>")}</p>`)
    .join("");
}
