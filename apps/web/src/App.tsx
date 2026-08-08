import { LoginScreen } from "./components/LoginScreen";
import { Workspace } from "./components/Workspace";
import { useI18n } from "./i18n";
import { useBootstrap, useMatrix } from "./matrix/hooks";

export function App() {
  const ready = useBootstrap();
  const matrix = useMatrix();
  const { t } = useI18n();

  if (!ready) {
    return (
      <main className="boot" aria-live="polite">
        <span className="brand-symbol" aria-hidden="true">H</span>
        <strong>{t("app.opening")}</strong>
        <span>{t("app.preparing")}</span>
      </main>
    );
  }

  return matrix.client ? <Workspace /> : <LoginScreen initialError={matrix.error} />;
}
