import {
  InlineKeyboard,
  buildCommandsStateContent,
  buildMiniAppContent,
  buildMiniAppDataContent,
  type CommandSpec,
  type KeyboardContent,
} from "aiomatrix";

export const FORMSPACE_COMMANDS: CommandSpec[] = [
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
];

/** @deprecated use FORMSPACE_COMMANDS */
export const HIGH_LIFE_COMMANDS = FORMSPACE_COMMANDS;

export function buildShowcaseKeyboard(): InlineKeyboard {
  return new InlineKeyboard()
    .callback("RSVP Going", "fs:rsvp:demo:going", "primary")
    .url("Docs", "https://example.org/formspace", "link")
    .row()
    .miniApp("Open form", "https://example.org/formspace/app", "fill:demo", "primary")
    .command("Help", "/help", "default");
}

export interface ProtocolFixtures {
  keyboard: KeyboardContent;
  callback: Record<string, unknown>;
  commands: Record<string, unknown>;
  miniApp: Record<string, unknown>;
  miniAppData: Record<string, unknown>;
}

export function createProtocolFixtures(): ProtocolFixtures {
  return {
    keyboard: buildShowcaseKeyboard().toContent(),
    callback: {
      token: "signed-callback-token",
      data: "fs:rsvp:demo:going",
      message_id: "$keyboard-message",
    },
    commands: buildCommandsStateContent(FORMSPACE_COMMANDS),
    miniApp: buildMiniAppContent({
      url: "https://example.org/formspace/app",
      title: "FormSpace MiniApp",
      description: "Builder, filler and results for Matrix forms",
      buttonText: "Open FormSpace",
      appId: "formspace.app",
      botId: "@formspace:example.org",
      startParam: "build:survey",
      display: "sheet",
    }),
    miniAppData: buildMiniAppDataContent({
      data: "{\"action\":\"publish\",\"kind\":\"survey\"}",
      queryId: "query-example",
      appId: "formspace.app",
      messageId: "$miniapp-card",
    }),
  };
}
