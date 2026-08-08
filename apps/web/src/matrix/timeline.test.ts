import { describe, expect, it } from "vitest";
import { normalizeTimeline } from "./timeline";

const base = {
  roomId: "!room:example.org",
  ownUserId: "@me:example.org",
  memberNames: { "@bot:example.org": "HighLife Bot" },
};

describe("normalizeTimeline", () => {
  it("applies edits and preserves reply metadata", () => {
    const events = [
      {
        eventId: "$parent",
        type: "m.room.message",
        sender: "@me:example.org",
        timestamp: 0,
        content: { msgtype: "m.text", body: "Original question" },
      },
      {
        eventId: "$one",
        type: "m.room.message",
        sender: "@bot:example.org",
        timestamp: 1,
        content: {
          msgtype: "m.text",
          body: "> <@me:example.org> old\n\nOriginal",
          "m.relates_to": { "m.in_reply_to": { event_id: "$parent" } },
        },
      },
      {
        eventId: "$edit",
        type: "m.room.message",
        sender: "@bot:example.org",
        timestamp: 2,
        content: {
          msgtype: "m.text",
          body: "* Updated",
          "m.new_content": { msgtype: "m.text", body: "Updated" },
          "m.relates_to": { rel_type: "m.replace", event_id: "$one" },
        },
      },
    ];

    expect(normalizeTimeline(events, base)).toEqual([
      expect.objectContaining({ eventId: "$parent" }),
      expect.objectContaining({
        eventId: "$one",
        body: "Updated",
        edited: true,
        replyToEventId: "$parent",
        replyPreview: {
          senderId: "@me:example.org",
          senderName: "@me:example.org",
          body: "Original question",
        },
      }),
    ]);
  });

  it("aggregates reactions and hides redacted content", () => {
    const events = [
      {
        eventId: "$one",
        type: "m.room.message",
        sender: "@bot:example.org",
        timestamp: 1,
        content: { msgtype: "m.text", body: "Secret" },
        redacted: true,
      },
      {
        eventId: "$reaction",
        type: "m.reaction",
        sender: "@me:example.org",
        timestamp: 2,
        content: {
          "m.relates_to": {
            rel_type: "m.annotation",
            event_id: "$one",
            key: "👍",
          },
        },
      },
    ];

    expect(normalizeTimeline(events, base)[0]).toEqual(
      expect.objectContaining({
        body: "Message removed",
        redacted: true,
        reactions: [{ key: "👍", count: 1, reactedByMe: true, ownEventId: "$reaction" }],
      }),
    );
  });

  it("skips redacted reactions and dedupes one sender per key", () => {
    const events = [
      {
        eventId: "$one",
        type: "m.room.message",
        sender: "@bot:example.org",
        timestamp: 1,
        content: { msgtype: "m.text", body: "Hi" },
      },
      {
        eventId: "$r1",
        type: "m.reaction",
        sender: "@me:example.org",
        timestamp: 2,
        content: {
          "m.relates_to": { rel_type: "m.annotation", event_id: "$one", key: "👍" },
        },
      },
      {
        eventId: "$r2",
        type: "m.reaction",
        sender: "@me:example.org",
        timestamp: 3,
        content: {
          "m.relates_to": { rel_type: "m.annotation", event_id: "$one", key: "👍" },
        },
      },
      {
        eventId: "$r-gone",
        type: "m.reaction",
        sender: "@other:example.org",
        timestamp: 4,
        redacted: true,
        content: {
          "m.relates_to": { rel_type: "m.annotation", event_id: "$one", key: "❤️" },
        },
      },
    ];

    expect(normalizeTimeline(events, base)[0]?.reactions).toEqual([
      { key: "👍", count: 1, reactedByMe: true, ownEventId: "$r2" },
    ]);
  });

  it("keeps undecrypted ciphertext visible as a notice placeholder", () => {
    const events = [
      {
        eventId: "$cipher",
        type: "m.room.encrypted",
        sender: "@bot:example.org",
        timestamp: 1,
        content: { algorithm: "m.megolm.v1.aes-sha2", ciphertext: "…" },
      },
    ];

    expect(normalizeTimeline(events, base)[0]).toEqual(
      expect.objectContaining({
        eventId: "$cipher",
        kind: "notice",
        body: "Unable to decrypt this message",
        senderName: "HighLife Bot",
      }),
    );
  });

  it("ignores https MiniApp launch URLs as media attachments", () => {
    const events = [
      {
        eventId: "$mini",
        type: "m.room.message",
        sender: "@bot:example.org",
        timestamp: 1,
        content: {
          msgtype: "m.text",
          body: "Open builder: https://example.org/miniapp/#x",
          url: "https://example.org/miniapp/#x",
          title: "FormSpace builder",
          "dev.aiomatrix.mini_app": {
            url: "https://example.org/miniapp/#x",
            title: "FormSpace builder",
          },
        },
      },
    ];

    expect(normalizeTimeline(events, base)[0]?.media).toBeUndefined();
    expect(normalizeTimeline(events, base)[0]?.body).toBe("FormSpace builder");
  });

  it("humanizes MiniApp data JSON bodies in the timeline", () => {
    const raw = JSON.stringify({
      action: "publish",
      kind: "rsvp",
      title: "Event RSVP",
      fields: [],
    });
    const events = [
      {
        eventId: "$data",
        type: "m.room.message",
        sender: "@me:example.org",
        timestamp: 1,
        content: {
          msgtype: "dev.aiomatrix.mini_app_data",
          body: raw,
          "dev.aiomatrix.mini_app_data": { version: 1, data: raw },
        },
      },
    ];
    expect(normalizeTimeline(events, base)[0]?.body).toBe("Published RSVP: Event RSVP");
  });

  it("normalizes media and thread metadata", () => {
    const events = [
      {
        eventId: "$image",
        type: "m.room.message",
        sender: "@me:example.org",
        timestamp: 1,
        content: {
          msgtype: "m.image",
          body: "photo.jpg",
          url: "mxc://example.org/media",
          info: { mimetype: "image/jpeg", size: 1200, w: 800, h: 600 },
          "m.relates_to": {
            rel_type: "m.thread",
            event_id: "$root",
            is_falling_back: true,
          },
        },
      },
    ];

    expect(normalizeTimeline(events, base)[0]).toEqual(
      expect.objectContaining({
        kind: "image",
        media: expect.objectContaining({ mxcUrl: "mxc://example.org/media" }),
        threadRootId: "$root",
      }),
    );
  });

  it("renders membership system events", () => {
    const events = [
      {
        eventId: "$join",
        type: "m.room.member",
        sender: "@bot:example.org",
        timestamp: 1,
        content: { membership: "join", displayname: "HighLife Bot" },
      },
    ];
    expect(normalizeTimeline(events, base)[0]).toEqual(
      expect.objectContaining({
        kind: "system",
        body: "HighLife Bot joined",
      }),
    );
  });
});
