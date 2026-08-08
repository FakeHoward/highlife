import { describe, expect, it } from "vitest";
import { escapeHtml, markdownToHtml, markdownToPlain } from "./markdown";

describe("markdownToHtml", () => {
  it("escapes HTML before formatting", () => {
    expect(escapeHtml(`<script>"x"&`)).toBe("&lt;script&gt;&quot;x&quot;&amp;");
  });

  it("renders bold, italic, code and paragraphs", () => {
    expect(markdownToHtml("**FormSpace** — try `/start`\n\nnext")).toBe(
      "<p><strong>FormSpace</strong> — try <code>/start</code></p><p>next</p>",
    );
    expect(markdownToHtml("say *hi* now")).toContain("<em>hi</em>");
  });

  it("strips markdown markers for plain previews", () => {
    expect(markdownToPlain("**FormSpace** — try `/start`")).toBe("FormSpace — try /start");
  });
});
