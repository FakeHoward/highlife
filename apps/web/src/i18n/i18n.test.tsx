import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { LocaleProvider, useLocale } from "./locale";
import {
  DEFAULT_LOCALE,
  LOCALE_STORAGE_KEY,
  translate,
} from "./messages";

function Probe() {
  const { locale, setLocale, t } = useLocale();
  return (
    <div>
      <span data-testid="locale">{locale}</span>
      <span data-testid="sign-in">{t("login.title")}</span>
      <button type="button" onClick={() => setLocale("ru")}>to-ru</button>
      <button type="button" onClick={() => setLocale("en")}>to-en</button>
    </div>
  );
}

describe("i18n messages", () => {
  beforeEach(() => {
    localStorage.removeItem(LOCALE_STORAGE_KEY);
  });

  afterEach(() => {
    cleanup();
    localStorage.removeItem(LOCALE_STORAGE_KEY);
  });

  it("defaults to English and resolves Russian strings", () => {
    expect(DEFAULT_LOCALE).toBe("en");
    expect(translate("en", "login.title")).toBe("Sign in");
    expect(translate("ru", "login.title")).toBe("Вход");
    expect(translate("ru", "chat.inviteTitle", { name: "QA" })).toBe(
      "Вас пригласили в QA",
    );
    expect(translate("en", "rooms.copyAlias")).toBe("Copy address");
    expect(translate("ru", "rooms.copyAlias")).toBe("Копировать адрес");
    expect(translate("ru", "timeline.systemAliasSet", {
      name: "Alice",
      alias: "#team:example.org",
    })).toBe("Alice установил(а) адрес комнаты #team:example.org");
    expect(translate("en", "call.answer")).toBe("Answer");
    expect(translate("ru", "call.hangup")).toBe("Завершить");
    expect(translate("en", "call.dialog")).toBe("Voice call");
    expect(translate("en", "call.fallback")).toBe("Use Element Call");
    expect(translate("ru", "call.participants", { count: 3 })).toBe("В звонке: 3");
  });

  it("persists locale switches through the provider", () => {
    render(
      <LocaleProvider>
        <Probe />
      </LocaleProvider>,
    );

    expect(screen.getByTestId("locale")).toHaveTextContent("en");
    expect(screen.getByTestId("sign-in")).toHaveTextContent("Sign in");

    fireEvent.click(screen.getByRole("button", { name: "to-ru" }));
    expect(screen.getByTestId("locale")).toHaveTextContent("ru");
    expect(screen.getByTestId("sign-in")).toHaveTextContent("Вход");
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("ru");

    fireEvent.click(screen.getByRole("button", { name: "to-en" }));
    expect(screen.getByTestId("sign-in")).toHaveTextContent("Sign in");
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("en");
  });

  it("restores locale from localStorage on mount", () => {
    localStorage.setItem(LOCALE_STORAGE_KEY, "ru");
    render(
      <LocaleProvider>
        <Probe />
      </LocaleProvider>,
    );
    expect(screen.getByTestId("locale")).toHaveTextContent("ru");
    expect(screen.getByTestId("sign-in")).toHaveTextContent("Вход");
  });
});
