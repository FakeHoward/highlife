import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { RoomListItem, TimelineItem } from "@highlife/ui-contracts";
import { LocaleProvider } from "../i18n";
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
        onOpenThread={vi.fn()}
      />,
    );
    const grouped = container.querySelector("article.message.grouped");
    expect(grouped).not.toBeNull();
    expect(grouped?.querySelector(".message-avatar.spacer")).not.toBeNull();
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
        onOpenThread={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Reply" }));
    expect(compose).toHaveBeenCalledWith({ type: "reply", item: message });
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
        onOpenThread={vi.fn()}
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
