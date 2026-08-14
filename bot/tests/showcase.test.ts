import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import {
  CallbackRegistry,
  COMMANDS_STATE_EVENT_TYPE,
  KEYBOARD_CONTENT_KEY,
  buildCommandsStateContent,
  buildMediaInfo,
  buildMessageContent,
  buildMiniAppContent,
  buildMiniAppDataContent,
  parseKeyboardContent,
  parseMiniAppContent,
  parseMiniAppDataContent,
} from "aiomatrix";
import Ajv from "ajv";

import {
  FORMSPACE_COMMANDS,
  buildShowcaseKeyboard,
  createProtocolFixtures,
} from "../src/showcase.js";

const contractsUrl = new URL("../../contracts/", import.meta.url);

async function json(path: string): Promise<unknown> {
  return JSON.parse(await readFile(new URL(path, contractsUrl), "utf8")) as unknown;
}

test("formspace commands emit aliases, args and categories for advertisement", () => {
  const content = buildCommandsStateContent(FORMSPACE_COMMANDS);

  assert.equal(COMMANDS_STATE_EVENT_TYPE, "dev.aiomatrix.commands");
  assert.deepEqual(content, {
    version: 1,
    prefixes: ["/", "!"],
    commands: [
      {
        name: "start",
        aliases: ["старт"],
        description: "FormSpace welcome and scenario menu",
        category: "general",
      },
      {
        name: "form",
        description: "FormSpace control: new|list|close|results|export|...",
        args: "<subcommand>",
        category: "forms",
      },
      {
        name: "media",
        description: "Inspect an attached media message",
        category: "media",
      },
      {
        name: "menu",
        description: "FormSpace scenario menu",
        category: "general",
      },
    ],
  });
});

test("showcase keyboard emits callback, token, url, mini-app and command styles", () => {
  const callbacks = new CallbackRegistry({ ttlMs: 60_000 });
  const keyboard = buildShowcaseKeyboard();
  const { content, tokens } = buildMessageContent(
    { text: "FormSpace protocol showcase" },
    { keyboard },
    {
      client: {} as never,
      roomId: "!showcase:example.org",
      callbacks,
      callbackUserId: "@alice:example.org",
    },
  );

  assert.equal(tokens.length, 1);
  assert.deepEqual(callbacks.peek(tokens[0]!), {
    data: "fs:rsvp:demo:going",
    roomId: "!showcase:example.org",
    messageEventId: "",
    userId: "@alice:example.org",
    expiresAtMs: callbacks.peek(tokens[0]!)?.expiresAtMs,
    answered: false,
    singleUse: false,
  });

  const parsed = parseKeyboardContent(content);
  assert.equal(parsed?.inline?.[0]?.[0]?.kind, "callback");
  assert.equal(parsed?.inline?.[1]?.[0]?.kind, "mini_app");
  assert.equal(parsed?.inline?.[1]?.[1]?.kind, "command");
});

test("protocol fixture builders match aiomatrix parsers and media shape", () => {
  const fixtures = createProtocolFixtures();

  assert.equal(parseKeyboardContent({ [KEYBOARD_CONTENT_KEY]: fixtures.keyboard })?.version, 1);
  assert.deepEqual(parseMiniAppContent(fixtures.miniApp), {
    version: 1,
    url: "https://example.org/formspace/app",
    title: "FormSpace MiniApp",
    description: "Builder, filler and results for Matrix forms",
    button_text: "Open FormSpace",
    app_id: "formspace.app",
    bot_id: "@formspace:example.org",
    start_param: "build:survey",
  });
  assert.deepEqual(parseMiniAppDataContent(fixtures.miniAppData), {
    data: "{\"action\":\"publish\",\"kind\":\"survey\"}",
    queryId: "query-example",
    appId: "formspace.app",
    messageId: "$miniapp-card",
  });
  assert.deepEqual(
    buildMediaInfo({
      mimetype: "image/png",
      sizeBytes: 2048,
      width: 640,
      height: 480,
    }),
    { mimetype: "image/png", size: 2048, w: 640, h: 480 },
  );
});

test("all published fixtures validate against language-neutral schemas", async () => {
  const ajv = new Ajv({ allErrors: true, strict: true });
  const names = [
    "keyboard",
    "callback",
    "commands",
    "mini_app",
    "mini_app_data",
    "callback_answer",
    "toast",
    "progress",
    "host",
  ] as const;

  for (const name of names) {
    const schema = await json(`schemas/dev.aiomatrix.${name}.schema.json`);
    const fixture = await json(`fixtures/dev.aiomatrix.${name}.json`);
    const validate = ajv.compile(schema);
    assert.equal(validate(fixture), true, `${name}: ${ajv.errorsText(validate.errors)}`);
  }
});

test("checked-in fixtures equal payloads emitted by showcase builders", async () => {
  const fixtures = createProtocolFixtures();
  const expected = {
    keyboard: await json("fixtures/dev.aiomatrix.keyboard.json"),
    callback: await json("fixtures/dev.aiomatrix.callback.json"),
    commands: await json("fixtures/dev.aiomatrix.commands.json"),
    miniApp: await json("fixtures/dev.aiomatrix.mini_app.json"),
    miniAppData: await json("fixtures/dev.aiomatrix.mini_app_data.json"),
  };

  assert.deepEqual(fixtures, expected);
  assert.deepEqual(
    fixtures.miniApp,
    buildMiniAppContent({
      url: "https://example.org/formspace/app",
      title: "FormSpace MiniApp",
      description: "Builder, filler and results for Matrix forms",
      buttonText: "Open FormSpace",
      appId: "formspace.app",
      botId: "@formspace:example.org",
      startParam: "build:survey",
      display: "sheet",
    }),
  );
  assert.deepEqual(
    fixtures.miniAppData,
    buildMiniAppDataContent({
      data: "{\"action\":\"publish\",\"kind\":\"survey\"}",
      queryId: "query-example",
      appId: "formspace.app",
      messageId: "$miniapp-card",
    }),
  );
});
