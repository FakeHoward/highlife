import { describe, expect, it } from "vitest";
import { AIOMATRIX_CALLBACK_EVENT_TYPE } from "@highlife/ui-contracts";
import {
  buildCallbackEvent,
  buildCallbackContent,
  buildMiniAppDataContent,
  extractMiniAppInitData,
  formatMessagePreview,
  humanizeStructuredPayload,
  isAllowedMiniAppUrl,
  miniAppAllowedOrigins,
  parseAiomatrixPayload,
  stripKeyboardFallbackHtml,
  stripKeyboardFallbackText,
  stripMiniAppUrlFallback,
} from "./aiomatrix";

describe("aiomatrix protocol", () => {
  it("allowlists MiniApp iframe origins from homeserver and env", () => {
    expect(
      miniAppAllowedOrigins({
        homeserver: "https://testhighlife.strangled.net",
        allowedOrigins: "https://forms.example.org, example.net",
        dev: false,
      }),
    ).toEqual(
      expect.arrayContaining([
        "https://forms.example.org",
        "https://example.net",
        "https://testhighlife.strangled.net",
      ]),
    );
    expect(
      isAllowedMiniAppUrl("https://testhighlife.strangled.net/miniapp/", {
        homeserver: "https://testhighlife.strangled.net",
        dev: false,
      }),
    ).toBe(true);
    expect(
      isAllowedMiniAppUrl("https://evil.example/app", {
        homeserver: "https://testhighlife.strangled.net",
        dev: false,
      }),
    ).toBe(false);
    expect(
      isAllowedMiniAppUrl("http://localhost:4173/", {
        homeserver: "https://testhighlife.strangled.net",
        dev: true,
      }),
    ).toBe(true);
  });

  it("rejects unsafe keyboard URLs while preserving callback buttons", () => {
    const parsed = parseAiomatrixPayload({
      "ru.studnovsu.inline_keyboard": [
        [
          { text: "Run", callback_data: "go" },
          { text: "Bad", url: "javascript:alert(1)" },
        ],
      ],
    });

    expect(parsed.keyboard).toEqual([
      [expect.objectContaining({ kind: "callback", data: "go" })],
    ]);
  });

  it("parses signed callback tokens from keyboard buttons", () => {
    const parsed = parseAiomatrixPayload({
      "dev.aiomatrix.keyboard": {
        inline: [[{ text: "Go", data: "go", token: "signed.token" }]],
      },
    });
    expect(parsed.keyboard).toEqual([
      [expect.objectContaining({ kind: "callback", data: "go", token: "signed.token" })],
    ]);
  });

  it("builds unsigned callbacks with contract field names", () => {
    expect(buildCallbackContent("go", "$message")).toEqual({
      data: "go",
      message_id: "$message",
    });
  });

  it("prefers signed tokens in callback events", () => {
    expect(buildCallbackEvent("go", "$message", "tok")).toEqual({
      eventType: "dev.aiomatrix.callback",
      content: {
        token: "tok",
        message_id: "$message",
      },
    });
    expect(AIOMATRIX_CALLBACK_EVENT_TYPE).toBe("dev.aiomatrix.callback");
  });

  it("builds canonical MiniApp data messages", () => {
    expect(
      buildMiniAppDataContent({ data: "ok", queryId: "query", appId: null }),
    ).toEqual({
      msgtype: "dev.aiomatrix.mini_app_data",
      body: "MiniApp data",
      "dev.aiomatrix.mini_app_data": {
        version: 1,
        data: "ok",
        query_id: "query",
      },
    });
  });

  it("humanizes FormSpace MiniApp publish JSON for display and previews", () => {
    const raw = JSON.stringify({
      action: "publish",
      kind: "rsvp",
      title: "Event RSVP",
      description: "Built with FormSpace on your Matrix homeserver.",
      fields: [{ id: "f1", type: "single", label: "Attendance", required: true }],
      policy: "public",
      anonymous: false,
      oneResponse: true,
      deadlineMs: null,
    });
    expect(humanizeStructuredPayload(raw)).toBe("Published RSVP: Event RSVP");
    expect(
      formatMessagePreview({
        msgtype: "dev.aiomatrix.mini_app_data",
        body: raw,
        "dev.aiomatrix.mini_app_data": { version: 1, data: raw },
      }),
    ).toBe("Published RSVP: Event RSVP");
    expect(
      formatMessagePreview({
        body: "**FormSpace** welcome\n\n1. Survey → !cb aaa.bbb.ccc",
        "dev.aiomatrix.keyboard": { inline: [] },
      }),
    ).toBe("FormSpace welcome");
  });

  it("extracts initData from signed launch URL fragments", () => {
    expect(
      extractMiniAppInitData(
        "https://example.com/miniapp/#matrixWebAppData=auth_date%3D1%26hash%3Dx&matrixWebAppHost=https%3A%2F%2Fapp.example",
      ),
    ).toBe("auth_date=1&hash=x");
  });

  it("strips aiomatrix keyboard fallback from plain and HTML bodies", () => {
    const body = [
      "**FormSpace** welcome",
      "",
      "1. Survey → !cb aaa.bbb.ccc",
      "2. Help → /help",
    ].join("\n");
    expect(stripKeyboardFallbackText(body)).toBe("**FormSpace** welcome");

    const html =
      "<p>**FormSpace** welcome</p><ol><li>Survey: <code>!cb aaa.bbb.ccc</code></li></ol>";
    expect(stripKeyboardFallbackHtml(html)).toBe("<p>**FormSpace** welcome</p>");
  });

  it("strips MiniApp launch URL fallback lines", () => {
    expect(
      stripMiniAppUrlFallback(
        "FormSpace builder · rsvp\nDesign fields.\nOpen builder: https://example.org/miniapp/#matrixWebAppData=abc",
      ),
    ).toBe("FormSpace builder · rsvp\nDesign fields.");
  });
});
