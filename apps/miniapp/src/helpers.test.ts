import { describe, expect, it } from "vitest";
import { escapeHtml, parseStartParam, seedFields } from "./helpers";

describe("formspace helpers", () => {
  it("reads start_param from the query string", () => {
    expect(parseStartParam({ search: "?start=fill:abc" })).toBe("fill:abc");
    expect(parseStartParam({ search: "", bridgeParam: "build:rsvp" })).toBe("build:rsvp");
    expect(parseStartParam({ search: "" })).toBe("build:survey");
  });

  it("seeds RSVP vs survey fields", () => {
    let n = 0;
    const id = () => `id${n++}`;
    expect(seedFields("rsvp", id).map((field) => field.label)).toEqual([
      "Attendance",
      "Comment (optional)",
    ]);
    expect(seedFields("survey", id).some((field) => field.type === "scale")).toBe(true);
  });

  it("escapes HTML attribute text", () => {
    expect(escapeHtml(`<img src="x" onerror="alert(1)">`)).toBe(
      "&lt;img src=&quot;x&quot; onerror=&quot;alert(1)&quot;&gt;",
    );
  });
});
