import { describe, expect, it } from "vitest";
import {
  buildPollResponseContent,
  buildPollStartContent,
  parsePollStartContent,
  tallyPollVotes,
} from "./polls";
import { encryptAttachment, decryptAttachment } from "./encryptedMedia";

describe("polls", () => {
  it("builds and parses MSC3381 poll start content", () => {
    const content = buildPollStartContent({
      question: "Lunch?",
      answers: ["Pizza", "Salad"],
    });
    const parsed = parsePollStartContent(content);
    expect(parsed?.question).toBe("Lunch?");
    expect(parsed?.answers.map((a) => a.text)).toEqual(["Pizza", "Salad"]);
  });

  it("tallies latest vote per sender", () => {
    const start = buildPollStartContent({
      question: "Lunch?",
      answers: ["Pizza", "Salad"],
    });
    const parsed = parsePollStartContent(start)!;
    const response = buildPollResponseContent("$poll", ["answer0"]);
    expect(response["m.relates_to"]).toEqual({
      rel_type: "m.reference",
      event_id: "$poll",
    });
    const tally = tallyPollVotes({
      responses: [
        { senderId: "@a:x", timestamp: 1, answers: ["answer0"] },
        { senderId: "@a:x", timestamp: 2, answers: ["answer1"] },
        { senderId: "@b:x", timestamp: 3, answers: ["answer0"] },
      ],
      validAnswerIds: new Set(parsed.answers.map((a) => a.id)),
      maxSelections: 1,
      ownUserId: "@a:x",
    });
    expect(tally.counts.answer0).toBe(1);
    expect(tally.counts.answer1).toBe(1);
    expect(tally.mySelections).toEqual(["answer1"]);
    expect(tally.totalVoters).toBe(2);
  });
});

describe("encryptedMedia", () => {
  it("round-trips attachment bytes", async () => {
    const plain = new TextEncoder().encode("secret-bytes").buffer;
    const { ciphertext, info } = await encryptAttachment(plain);
    expect(ciphertext.byteLength).toBeGreaterThan(0);
    const restored = await decryptAttachment(ciphertext, info);
    expect(new TextDecoder().decode(restored)).toBe("secret-bytes");
  });
});
