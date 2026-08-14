import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { LocaleProvider } from "./i18n/locale";
import { applyStoredTheme } from "./theme";
import "./styles.css";

applyStoredTheme();

if ("serviceWorker" in navigator && window.isSecureContext) {
  void navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`);
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <LocaleProvider>
      <App />
    </LocaleProvider>
  </StrictMode>,
);
