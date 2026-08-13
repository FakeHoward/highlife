import { afterEach, describe, expect, it } from "vitest";
import { applyStoredTheme, THEME_STORAGE_KEY } from "./theme";

describe("theme bootstrap", () => {
  afterEach(() => {
    localStorage.removeItem(THEME_STORAGE_KEY);
    delete document.documentElement.dataset.theme;
  });

  it("restores a saved theme before the application renders", () => {
    localStorage.setItem(THEME_STORAGE_KEY, "dark");

    expect(applyStoredTheme()).toBe("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");
  });

  it("uses system mode for missing or invalid stored values", () => {
    localStorage.setItem(THEME_STORAGE_KEY, "sepia");

    expect(applyStoredTheme()).toBe("system");
    expect(document.documentElement.dataset.theme).toBe("system");
  });
});
