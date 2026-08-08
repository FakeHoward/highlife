import { useEffect, useState, type FormEvent } from "react";
import { useI18n } from "../i18n";
import { beginOidcOrSsoLogin } from "../matrix/oidc";
import { login, probeSsoAvailable, register } from "../matrix/service";
import { IconEye, IconEyeOff } from "./Icons";

type Mode = "login" | "register";

function defaultHomeserver(): string {
  return (import.meta.env.VITE_DEFAULT_HOMESERVER as string | undefined)?.trim() || "";
}

function serverFromMxid(value: string): string | null {
  const match = value.trim().match(/^@?[^:]+:(.+)$/);
  const host = match?.[1]?.trim();
  return host || null;
}

export function LoginScreen({ initialError }: { initialError: string | null }) {
  const { t, locale, setLocale } = useI18n();
  const [mode, setMode] = useState<Mode>("login");
  const [homeserver, setHomeserver] = useState(defaultHomeserver);
  const [userId, setUserId] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(initialError);
  const [ssoAvailable, setSsoAvailable] = useState(false);

  useEffect(() => {
    const hs = homeserver.trim();
    if (!hs || mode !== "login") {
      setSsoAvailable(false);
      return;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      void probeSsoAvailable(hs).then((available) => {
        if (!cancelled) setSsoAvailable(available);
      });
    }, 350);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [homeserver, mode]);

  function applyMxidHomeserver(value: string) {
    const host = serverFromMxid(value);
    if (!host) return;
    if (!homeserver.trim()) {
      setHomeserver(`https://${host}`);
    }
  }

  function mapAuthError(reason: unknown, forRegister: boolean): string {
    const code =
      reason && typeof reason === "object" && "code" in reason
        ? String((reason as { code?: string }).code)
        : "";
    if (code === "USERNAME_REQUIRED") return t("login.usernameRequired");
    if (code === "REGISTER_DISABLED") return t("login.registerDisabled");
    if (code === "REGISTER_NEEDS_EXTRA") return t("login.registerNeedsExtra");
    if (reason instanceof Error && reason.message) return reason.message;
    return forRegister ? t("login.registerFailed") : t("login.failed");
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!homeserver.trim()) {
      setError(t("login.homeserverRequired"));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (mode === "register") {
        await register({ homeserver, username, password });
      } else {
        await login({ homeserver, userId, password });
      }
    } catch (reason) {
      setError(mapAuthError(reason, mode === "register"));
    } finally {
      setBusy(false);
    }
  }

  async function startSso() {
    if (!homeserver.trim()) {
      setError(t("login.homeserverRequired"));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await beginOidcOrSsoLogin(homeserver);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("login.oidcFailed"));
      setBusy(false);
    }
  }

  return (
    <main className="login">
      <section className="login-intro">
        <div className="brand-lockup">
          <span className="brand-symbol" aria-hidden="true">H</span>
          <strong>HighLife</strong>
        </div>
        <h1>{t("login.headline")}</h1>
        <p>{t("login.blurb")}</p>
      </section>
      <form className="login-form" onSubmit={submit}>
        <div className="login-form-top">
          <div>
            <h2>{mode === "register" ? t("login.registerTitle") : t("login.title")}</h2>
            <p className="muted">
              {mode === "register" ? t("login.registerHint") : t("login.hint")}
            </p>
          </div>
          <div className="segmented login-locale" role="group" aria-label={t("login.language")}>
            <button
              type="button"
              className={locale === "en" ? "active" : ""}
              onClick={() => setLocale("en")}
            >
              {t("settings.languageEn")}
            </button>
            <button
              type="button"
              className={locale === "ru" ? "active" : ""}
              onClick={() => setLocale("ru")}
            >
              {t("settings.languageRu")}
            </button>
          </div>
        </div>
        <div className="login-mode" role="tablist" aria-label={t("login.mode")}>
          <button
            type="button"
            role="tab"
            aria-selected={mode === "login"}
            className={mode === "login" ? "is-active" : undefined}
            onClick={() => {
              setMode("login");
              setError(null);
            }}
          >
            {t("login.title")}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === "register"}
            className={mode === "register" ? "is-active" : undefined}
            onClick={() => {
              setMode("register");
              setError(null);
            }}
          >
            {t("login.registerTitle")}
          </button>
        </div>
        <label>
          <span>{t("login.homeserver")}</span>
          <input
            value={homeserver}
            onChange={(event) => setHomeserver(event.target.value)}
            placeholder={t("login.homeserverPlaceholder")}
            autoComplete="url"
            required
          />
        </label>
        {mode === "login" ? (
          <label>
            <span>{t("login.userId")}</span>
            <input
              value={userId}
              onChange={(event) => {
                const next = event.target.value;
                setUserId(next);
                applyMxidHomeserver(next);
              }}
              placeholder={t("login.userIdPlaceholder")}
              autoComplete="username"
              required
            />
          </label>
        ) : (
          <label>
            <span>{t("login.username")}</span>
            <input
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder={t("login.usernamePlaceholder")}
              autoComplete="username"
              required
            />
          </label>
        )}
        <label className="password-field">
          <span>{t("login.password")}</span>
          <div className="password-input">
            <input
              type={showPassword ? "text" : "password"}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete={mode === "register" ? "new-password" : "current-password"}
              required
              minLength={mode === "register" ? 8 : undefined}
            />
            <button
              type="button"
              className="icon-button"
              aria-label={showPassword ? t("login.hidePassword") : t("login.showPassword")}
              onClick={() => setShowPassword((value) => !value)}
            >
              {showPassword ? <IconEyeOff /> : <IconEye />}
            </button>
          </div>
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="button primary" disabled={busy}>
          {busy
            ? t("login.connecting")
            : mode === "register"
              ? t("login.createAccount")
              : t("login.continue")}
        </button>
        {mode === "login" && ssoAvailable && (
          <button
            type="button"
            className="button"
            disabled={busy}
            onClick={() => void startSso()}
          >
            {t("login.signInWithSso")}
          </button>
        )}
        <p className="form-note">{t("login.note")}</p>
      </form>
    </main>
  );
}
