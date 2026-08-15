import { describe, expect, it } from "vitest";
import {
  attachMentions,
  belongsOnMainTimeline,
  completeCommand,
  conversationReplyContent,
  filterCommandSuggestions,
  intentionalMentions,
  locationContent,
  openStreetMapUrl,
  parseCommandsState,
  parseGeoUri,
  parseImagePack,
  parseLocationContent,
  parseMsc4139Prompts,
  parseRoomSummary,
  slidingSyncSupported,
  stickerContent,
  threadRelation,
  threadRootId,
  threadSubscriptionPath,
} from "./specFeatures";

describe("intentional mentions (MSC3952)", () => {
  it("collects mentioned mxids and @room", () => {
    expect(
      intentionalMentions("hey @alice:example.org and @room", [
        "@alice:example.org",
        "@bob:example.org",
      ]),
    ).toEqual({ user_ids: ["@alice:example.org"], room: true });
  });

  it("still writes m.mentions when nobody is tagged", () => {
    expect(attachMentions({ msgtype: "m.text", body: "hi" }, "hi", ["@alice:example.org"])).toEqual({
      msgtype: "m.text",
      body: "hi",
      "m.mentions": { user_ids: [] },
    });
  });
});

describe("threads (MSC3440)", () => {
  it("builds an m.thread relation with fallback for the main timeline", () => {
    expect(threadRelation("$root")).toEqual({
      rel_type: "m.thread",
      event_id: "$root",
      is_falling_back: true,
      "m.in_reply_to": { event_id: "$root" },
    });
    expect(threadRelation("$root", "$root", false).is_falling_back).toBe(false);
  });

  it("keeps in-thread replies off the main timeline unless they are fallbacks", () => {
    const inThread = {
      "m.relates_to": { rel_type: "m.thread", event_id: "$root", is_falling_back: false },
    };
    const fallback = {
      "m.relates_to": { rel_type: "m.thread", event_id: "$root", is_falling_back: true },
    };
    expect(belongsOnMainTimeline(inThread)).toBe(false);
    expect(belongsOnMainTimeline(fallback)).toBe(true);
    expect(threadRootId(inThread)).toBe("$root");
  });
});

describe("location (MSC3488)", () => {
  it("writes geo_uri plus the extensible location block", () => {
    const content = locationContent(55.75, 37.62, "Red Square");
    expect(content.msgtype).toBe("m.location");
    expect(content.geo_uri).toBe("geo:55.75,37.62");
    expect(parseLocationContent(content)).toEqual({
      lat: 55.75,
      lon: 37.62,
      geoUri: "geo:55.75,37.62",
      description: "Red Square",
    });
    expect(parseGeoUri("geo:1,2;u=30")).toEqual({ lat: 1, lon: 2 });
    expect(openStreetMapUrl(1, 2)).toContain("mlat=1");
  });
});

describe("image packs (MSC2545)", () => {
  it("reads pack images and builds m.sticker content", () => {
    const items = parseImagePack({
      images: {
        wave: { url: "mxc://example.org/abc", body: "wave", usage: ["sticker"] },
        skip: { url: "https://evil.example/x.png" },
      },
    });
    expect(items).toEqual([
      { shortcode: "wave", url: "mxc://example.org/abc", body: "wave", usage: ["sticker"] },
    ]);
    expect(stickerContent(items[0]!)).toMatchObject({ body: "wave", url: "mxc://example.org/abc" });
  });
});

describe("bot commands (MSC4332) and prompts (MSC4139)", () => {
  it("parses vendor and MSC command state", () => {
    const vendor = parseCommandsState({
      commands: [{ name: "start", aliases: ["go"], description: "Begin" }],
    });
    const msc = parseCommandsState({
      "org.matrix.msc4332.commands": {
        commands: [{ name: "roll", aliases: ["dice"] }],
      },
    });
    expect(vendor[0]?.name).toBe("start");
    expect(msc[0]?.name).toBe("roll");
    expect(filterCommandSuggestions([...vendor, ...msc], "/r").map((c) => c.name)).toEqual(["roll"]);
    expect(completeCommand(vendor[0]!, "!st")).toBe("!start ");
  });

  it("parses MSC4139 prompts and builds a conversation reply", () => {
    const parsed = parseMsc4139Prompts({
      "org.matrix.msc4139.prompts": {
        intro: { content: { "m.text": [{ body: "Pick a die" }] } },
        scope: ["@alice:example.org"],
        prompts: [
          { type: "preset", id: "1d6", label: { "m.text": [{ body: "1d6" }] } },
          { type: "input", id: "custom", validator: "[0-9]+d[0-9]+", label: { "m.text": [{ body: "Other" }] } },
        ],
      },
    });
    expect(parsed?.prompts).toHaveLength(2);
    expect(parsed?.prompts[0]).toEqual({ id: "1d6", type: "preset", label: "1d6" });
    const reply = conversationReplyContent("1d6", "1d6", "$welcome");
    expect(reply["org.matrix.msc4139.used_prompt"]).toEqual({ id: "1d6" });
    expect((reply["m.relates_to"] as { rel_type: string }).rel_type).toBe("m.thread");
  });
});

describe("homeserver helpers", () => {
  it("detects simplified sliding sync flags", () => {
    expect(slidingSyncSupported({ "org.matrix.simplified_msc3575": true })).toBe(true);
    expect(slidingSyncSupported({ "org.matrix.msc4186": true })).toBe(true);
    expect(slidingSyncSupported({})).toBe(false);
  });

  it("builds the MSC4306 subscription path and room summary", () => {
    expect(threadSubscriptionPath("!r:ex", "$t")).toContain("msc4306");
    expect(parseRoomSummary({ name: "Lobby", num_joined_members: 4 }, "!x:ex")).toMatchObject({
      roomId: "!x:ex",
      name: "Lobby",
      numJoinedMembers: 4,
    });
  });
});
