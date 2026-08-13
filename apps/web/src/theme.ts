export const THEME_STORAGE_KEY = "highlife.theme";
export type Theme = "system" | "light" | "dark";

export function applyTheme(theme: Theme): void {
  document.documentElement.dataset.theme = theme;
}

export function applyStoredTheme(): Theme {
  let stored: string | null = null;
  try {
    stored = localStorage.getItem(THEME_STORAGE_KEY);
  } catch {
    // Storage can be unavailable in privacy-restricted contexts.
  }
  const theme: Theme = stored === "light" || stored === "dark" ? stored : "system";
  applyTheme(theme);
  return theme;
}
