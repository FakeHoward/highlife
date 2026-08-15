import { describe, expect, it } from "vitest";
import { dicebearAvatarUrl, dicebearSeed } from "./dicebear";

describe("dicebear", () => {
  it("keeps a stable hashed seed for the same Matrix id", () => {
    expect(dicebearSeed("@alice:example.org")).toBe(dicebearSeed("@alice:example.org"));
    expect(dicebearSeed("@alice:example.org")).not.toBe(dicebearSeed("@bob:example.org"));
    expect(dicebearSeed("@alice:example.org")).toBe(dicebearSeed(" @ALICE:example.org "));
  });

  it("builds a DiceBear PNG URL without the raw MXID", () => {
    expect(dicebearSeed("@alice:example.org")).toBe("f7d6ffc5");
    const url = dicebearAvatarUrl("@alice:example.org", 96);
    expect(url).toContain("https://api.dicebear.com/9.x/notionists-neutral/png?");
    expect(url).toContain("size=96");
    expect(url).toContain("backgroundColor=");
    expect(url).not.toContain("alice");
    expect(url).toContain(`seed=${dicebearSeed("@alice:example.org")}`);
  });
});
