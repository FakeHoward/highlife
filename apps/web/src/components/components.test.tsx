import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { RoomListItem, TimelineItem } from "@highlife/ui-contracts";
import { LocaleProvider } from "../i18n";
import { sendMessage } from "../matrix/service";
import { Avatar } from "./Avatar";
import { Composer } from "./Composer";
import { LoginScreen } from "./LoginScreen";
import { MessageTimeline } from "./MessageTimeline";
import { RoomSidebar } from "./RoomSidebar";
import { Modal, RoomDetails } from "./Surfaces";

vi.mock("../matrix/service", () => ({
  mediaUrl: (url: string) => url,
  react: vi.fn(),
  toggleReaction: vi.fn(),
  redact: vi.fn(),
  sendCallback: vi.fn(),
  sendMessage: vi.fn(),
  votePoll: vi.fn(),
  endPoll: vi.fn(),
  resolveMediaObjectUrl: vi.fn(async () => ""),
  createPoll: vi.fn(),
  setTyping: vi.fn(),
  uploadFile: vi.fn(),
  login: vi.fn(),
  register: vi.fn(),
  getJoinedMembers: () => ([
    { userId: "@alice:example.org", displayName: "Alice", membership: "join", powerLevel: 50 },
    { userId: "@bob:example.org", displayName: "Bob", membership: "join", powerLevel: 0 },
  ]),
  invite: vi.fn(),
  leaveRoom: vi.fn(),
  listSpaces: () => [],
  addRoomToSpace: vi.fn(),
  getRoomAliases: () => ({ canonicalAlias: "#highlife:example.org", aliases: ["#highlife:example.org"] }),
  setCanonicalAlias: vi.fn(),
  removeRoomAlias: vi.fn(),
  setRoomAvatar: vi.fn(),
}));

vi.mock("../matrix/oidc", () => ({
  beginOidcOrSsoLogin: vi.fn(),
  maybeCompleteAuthCallback: vi.fn(async () => ({ handled: false, error: null })),
  isAuthCallbackUrl: () => false,
}));

const room: RoomListItem = {
  roomId: "!room:example.org",
  name: "HighLife QA",
  unread: 0,
  highlight: 0,
  isDirect: false,
  isEncrypted: true,
  isSpace: false,
  membership: "join",
  lastActive: 1,
};

const message: TimelineItem = {
  eventId: "$message",
  roomId: room.roomId,
  senderId: "@me:example.org",
  senderName: "Me",
  timestamp: 1,
  body: "Hello",
  kind: "text",
  isOwn: true,
  edited: false,
  redacted: false,
  reactions: [],
  rawContent: {},
};

function wrap(ui: React.ReactNode) {
  return render(<LocaleProvider>{ui}</LocaleProvider>);
}

afterEach(() => {
  cleanup();
  document.body.innerHTML = "";
});

describe("deployment defaults", () => {
  it("uses the configured production homeserver", () => {
    vi.stubEnv(
      "VITE_DEFAULT_HOMESERVER",
      "https://testhighlife.strangled.net",
    );

    wrap(<LoginScreen initialError={null} />);

    expect(screen.getByRole("textbox", { name: "Homeserver" })).toHaveValue(
      "https://testhighlife.strangled.net",
    );
    expect(screen.getByRole("tab", { name: "Create account" })).toBeInTheDocument();
    vi.unstubAllEnvs();
  });

  it("leaves homeserver empty when env is unset", () => {
    vi.stubEnv("VITE_DEFAULT_HOMESERVER", "");

    wrap(<LoginScreen initialError={null} />);

    const field = screen.getByRole("textbox", { name: "Homeserver" });
    expect(field).toHaveValue("");
    expect(field).toHaveAttribute("placeholder", "https://matrix.example.org");
    vi.unstubAllEnvs();
  });
});

describe("responsive room navigation", () => {
  it("selects a room through the real room list control", () => {
    const select = vi.fn();
    wrap(
      <RoomSidebar
        rooms={[room]}
        activeId={null}
        query=""
        onQuery={vi.fn()}
        onSelect={select}
        onNew={vi.fn()}
        onNewSpace={vi.fn()}
        onSettings={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /HighLife QA/i }));
    expect(select).toHaveBeenCalledWith(room.roomId);
  });

  it("uses a narrow space rail and exposes a dismissible selected-space panel", () => {
    const selectSpace = vi.fn();
    wrap(
      <RoomSidebar
        rooms={[room]}
        activeId={null}
        query=""
        onQuery={vi.fn()}
        onSelect={vi.fn()}
        onNew={vi.fn()}
        onNewSpace={vi.fn()}
        onSettings={vi.fn()}
        spaces={[{
          roomId: "!space:example.org",
          name: "Work",
          topic: "Project rooms",
          childRoomIds: [room.roomId],
        }]}
        selectedSpaceId="!space:example.org"
        onSelectSpace={selectSpace}
      />,
    );

    expect(screen.getByRole("navigation", { name: "Spaces" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Work" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("complementary", { name: "Work" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Close Work" }));
    expect(selectSpace).toHaveBeenCalledWith(null);
  });
});

describe("avatars", () => {
  it("uses an image when an avatar URL is available", () => {
    wrap(<Avatar id="@alice:example.org" name="Alice" src="https://example.org/alice.png" />);
    expect(screen.getByRole("img", { name: "Alice" })).toHaveAttribute(
      "src",
      "https://example.org/alice.png",
    );
  });

  it("uses a deterministic accessible fallback based on the id", () => {
    const { rerender } = wrap(<Avatar id="@alice:example.org" name="Alice" />);
    const first = screen.getByRole("img", { name: "Alice" });
    const color = first.getAttribute("style");
    expect(first).toHaveTextContent("A");

    rerender(<LocaleProvider><Avatar id="@alice:example.org" name="Changed name" /></LocaleProvider>);
    expect(screen.getByRole("img", { name: "Changed name" }).getAttribute("style")).toBe(color);
  });
});

describe("composer", () => {
  it("keeps poll creation out of the message row and sends /poll as text", () => {
    wrap(<Composer roomId={room.roomId} mode={null} onMode={vi.fn()} />);
    expect(screen.queryByRole("button", { name: "Poll" })).not.toBeInTheDocument();

    const input = screen.getByRole("textbox", { name: "Message" });
    fireEvent.change(input, { target: { value: "/poll" } });
    fireEvent.click(screen.getByRole("button", { name: "Send message" }));

    expect(screen.queryByText("Poll question")).not.toBeInTheDocument();
    expect(vi.mocked(sendMessage)).toHaveBeenCalledWith(room.roomId, "/poll", {
      editEventId: undefined,
      replyEventId: undefined,
    });
  });
});

describe("message actions", () => {
  it("keeps grouped non-own messages in the content column with an avatar spacer", () => {
    const first: TimelineItem = {
      ...message,
      senderId: "@bot:example.org",
      senderName: "Bot",
      isOwn: false,
    };
    const second: TimelineItem = {
      ...first,
      eventId: "$two",
      timestamp: first.timestamp + 1_000,
      body: "follow-up from the same sender",
    };
    const { container } = wrap(
      <MessageTimeline
        items={[first, second]}
        roomId={room.roomId}
        onComposeMode={vi.fn()}
        onMiniApp={vi.fn()}
        history={{ loading: false, exhausted: true, error: null }}
        onLoadOlder={vi.fn()}
      />,
    );
    const grouped = container.querySelector("article.message.grouped");
    expect(grouped).not.toBeNull();
    expect(grouped?.querySelector(".message-avatar-spacer")).not.toBeNull();
    expect(grouped?.querySelector(".message-stack")).not.toBeNull();
  });

  it("opens reply mode for the selected message", () => {
    const compose = vi.fn();
    wrap(
      <MessageTimeline
        items={[message]}
        roomId={room.roomId}
        onComposeMode={compose}
        onMiniApp={vi.fn()}
        history={{ loading: false, exhausted: true, error: null }}
        onLoadOlder={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Reply" }));
    expect(compose).toHaveBeenCalledWith({ type: "reply", item: message });
  });

  it("renders foreign thread relations as replies without thread controls", () => {
    wrap(
      <MessageTimeline
        items={[{
          ...message,
          isOwn: false,
          senderId: "@alice:example.org",
          senderName: "Alice",
          replyToEventId: "$root",
          replyPreview: {
            senderId: "@bob:example.org",
            senderName: "Bob",
            body: "Root message",
          },
        }]}
        roomId={room.roomId}
        onComposeMode={vi.fn()}
        onMiniApp={vi.fn()}
        history={{ loading: false, exhausted: true, error: null }}
        onLoadOlder={vi.fn()}
      />,
    );

    expect(screen.getByText("Root message")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Thread" })).not.toBeInTheDocument();
  });

  it("does not render unsafe MiniApp content", () => {
    wrap(
      <MessageTimeline
        items={[{
          ...message,
          rawContent: {
            msgtype: "ru.studnovsu.mini_app",
            url: "javascript:alert(1)",
            title: "Unsafe",
          },
        }]}
        roomId={room.roomId}
        onComposeMode={vi.fn()}
        onMiniApp={vi.fn()}
        history={{ loading: false, exhausted: true, error: null }}
        onLoadOlder={vi.fn()}
      />,
    );

    expect(screen.queryByRole("button", { name: /Unsafe/i })).not.toBeInTheDocument();
  });
});

describe("room member list", () => {
  it("renders joined members from the service API", () => {
    wrap(<RoomDetails room={room} onClose={vi.fn()} onLeft={vi.fn()} />);
    expect(screen.getByTestId("member-list")).toBeInTheDocument();
    expect(screen.getByText("Alice")).toBeInTheDocument();
    expect(screen.getByText("@alice:example.org")).toBeInTheDocument();
    expect(screen.getByText("Bob")).toBeInTheDocument();
    expect(screen.getByText("#highlife:example.org")).toBeInTheDocument();
    expect(screen.getAllByRole("button", { name: "Copy address" })).not.toHaveLength(0);
  });
});

describe("modal focus", () => {
  it("moves focus into the modal and restores it after close", () => {
    const opener = document.createElement("button");
    document.body.append(opener);
    opener.focus();
    const { unmount } = wrap(
      <Modal title="Settings" onClose={vi.fn()}>
        <button>Save changes</button>
      </Modal>,
    );

    expect(screen.getByRole("button", { name: "Close" })).toHaveFocus();
    unmount();
    expect(opener).toHaveFocus();
    opener.remove();
  });
});
