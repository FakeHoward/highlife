/**
 * Minimal Matrix Widget API host bridge for Element Call embeds.
 * Protocol: https://github.com/matrix-org/matrix-widget-api
 */

export type WidgetSendEventFn = (roomId: string, type: string, content: Record<string, unknown>, stateKey?: string) => Promise<{ event_id?: string }>;

export type WidgetOpenIdFn = () => Promise<{
  access_token: string;
  token_type: string;
  matrix_server_name: string;
  expires_in: number;
} | null>;

export type WidgetUploadFn = (file: Blob, filename: string, mimeType?: string) => Promise<{ content_uri: string }>;
export type WidgetDownloadFn = (mxcUrl: string) => Promise<{ filename?: string; contentType?: string; data: string }>;

export interface WidgetHostOptions {
  widgetId: string;
  roomId: string;
  targetOrigin: string;
  getContentWindow: () => Window | null | undefined;
  sendEvent?: WidgetSendEventFn;
  getOpenIdToken?: WidgetOpenIdFn;
  uploadContent?: WidgetUploadFn;
  downloadContent?: WidgetDownloadFn;
  onCapabilityChange?: (capabilities: string[]) => void;
}

interface WidgetApiMessage {
  api?: string;
  requestId?: string;
  action?: string;
  widgetId?: string;
  data?: Record<string, unknown>;
  response?: Record<string, unknown>;
}

const SUPPORTED_API_VERSIONS = [
  "0.0.1",
  "0.0.2",
  "org.matrix.msc2762",
  "org.matrix.msc2876",
  "org.matrix.msc2931",
  "org.matrix.msc2974",
  "org.matrix.msc4039",
];

const DEFAULT_CAPABILITIES = [
  "m.always_on_screen",
  "org.matrix.msc2762.timeline.*",
  "org.matrix.msc2762.send.event:m.room.message",
  "org.matrix.msc2762.receive.event:m.room.message",
  "org.matrix.msc2762.send.event:m.sticker",
  "org.matrix.msc2762.receive.event:m.sticker",
  "org.matrix.msc2762.send.state_event:org.matrix.msc3401.call.member",
  "org.matrix.msc2762.receive.state_event:org.matrix.msc3401.call.member",
  "org.matrix.msc2762.send.event:org.matrix.msc4075.rtc.notification",
  "org.matrix.msc2762.receive.event:org.matrix.msc4075.rtc.notification",
  "org.matrix.msc2762.send.to_device",
  "org.matrix.msc2762.receive.to_device",
  "org.matrix.msc4039.upload_file",
  "org.matrix.msc4039.download_file",
];

function isWidgetRequest(data: unknown): data is WidgetApiMessage {
  if (!data || typeof data !== "object") return false;
  const message = data as WidgetApiMessage;
  return message.api === "fromWidget" && typeof message.action === "string" && typeof message.requestId === "string";
}

export function attachElementCallWidgetHost(options: WidgetHostOptions): () => void {
  const approved = new Set(DEFAULT_CAPABILITIES);

  function reply(request: WidgetApiMessage, response: Record<string, unknown>): void {
    const win = options.getContentWindow();
    if (!win) return;
    win.postMessage(
      {
        ...request,
        response,
      },
      options.targetOrigin,
    );
  }

  function notifyCapabilities(): void {
    const win = options.getContentWindow();
    if (!win) return;
    win.postMessage(
      {
        api: "toWidget",
        requestId: `highlife_caps_${Date.now()}`,
        widgetId: options.widgetId,
        action: "notify_capabilities",
        data: {
          approved: [...approved],
          requested: [...approved],
        },
      },
      options.targetOrigin,
    );
    options.onCapabilityChange?.([...approved]);
  }

  async function handle(request: WidgetApiMessage): Promise<void> {
    if (request.widgetId && request.widgetId !== options.widgetId) return;
    const action = request.action ?? "";

    if (action === "content_loaded") {
      reply(request, {});
      notifyCapabilities();
      return;
    }

    if (action === "supported_api_versions") {
      reply(request, { supported_versions: SUPPORTED_API_VERSIONS });
      return;
    }

    if (action === "capabilities" || action === "org.matrix.msc2974.request_capabilities") {
      const requested = Array.isArray(request.data?.capabilities)
        ? (request.data!.capabilities as string[])
        : DEFAULT_CAPABILITIES;
      for (const capability of requested) approved.add(capability);
      reply(request, { capabilities: [...approved] });
      notifyCapabilities();
      return;
    }

    if (action === "set_always_on_screen") {
      reply(request, { success: true });
      return;
    }

    if (action === "get_openid") {
      if (!options.getOpenIdToken) {
        reply(request, { state: "blocked" });
        return;
      }
      try {
        const token = await options.getOpenIdToken();
        if (!token) {
          reply(request, { state: "blocked" });
          return;
        }
        reply(request, { state: "allowed", ...token });
      } catch {
        reply(request, { state: "blocked" });
      }
      return;
    }

    if (action === "send_event") {
      const type = typeof request.data?.type === "string" ? request.data.type : "";
      const content = (request.data?.content && typeof request.data.content === "object"
        ? request.data.content
        : {}) as Record<string, unknown>;
      const stateKey = typeof request.data?.state_key === "string" ? request.data.state_key : undefined;
      const roomId = typeof request.data?.room_id === "string" ? request.data.room_id : options.roomId;
      if (!options.sendEvent || !type) {
        reply(request, { error: { message: "send_event is not available", url: "", http_status: 400 } });
        return;
      }
      try {
        const result = await options.sendEvent(roomId, type, content, stateKey);
        reply(request, { room_id: roomId, event_id: result.event_id ?? `local_${Date.now()}` });
      } catch (error) {
        reply(request, {
          error: {
            message: error instanceof Error ? error.message : "send_event failed",
            url: "",
            http_status: 500,
          },
        });
      }
      return;
    }

    if (action === "send_to_device") {
      // Element Call may request to-device; acknowledge without inventing crypto APIs.
      reply(request, {});
      return;
    }

    if (action === "org.matrix.msc4039.upload_file") {
      if (!options.uploadContent) {
        reply(request, { error: { message: "upload_file is not available", url: "", http_status: 400 } });
        return;
      }
      try {
        const filename = typeof request.data?.filename === "string" ? request.data.filename : "upload.bin";
        const mimeType = typeof request.data?.contentType === "string" ? request.data.contentType : "application/octet-stream";
        const raw = typeof request.data?.data === "string" ? request.data.data : "";
        const bytes = Uint8Array.from(atob(raw), (char) => char.charCodeAt(0));
        const result = await options.uploadContent(new Blob([bytes], { type: mimeType }), filename, mimeType);
        reply(request, { content_uri: result.content_uri });
      } catch (error) {
        reply(request, {
          error: {
            message: error instanceof Error ? error.message : "upload failed",
            url: "",
            http_status: 500,
          },
        });
      }
      return;
    }

    if (action === "org.matrix.msc4039.download_file") {
      if (!options.downloadContent) {
        reply(request, { error: { message: "download_file is not available", url: "", http_status: 400 } });
        return;
      }
      try {
        const mxc = typeof request.data?.content_uri === "string"
          ? request.data.content_uri
          : typeof request.data?.url === "string" ? request.data.url : "";
        const result = await options.downloadContent(mxc);
        reply(request, result);
      } catch (error) {
        reply(request, {
          error: {
            message: error instanceof Error ? error.message : "download failed",
            url: "",
            http_status: 500,
          },
        });
      }
      return;
    }

    // Acknowledge unknown fromWidget actions so the widget does not hang.
    reply(request, {});
  }

  function onMessage(event: MessageEvent): void {
    if (event.origin !== options.targetOrigin) return;
    if (event.source !== options.getContentWindow()) return;
    if (!isWidgetRequest(event.data)) return;
    void handle(event.data);
  }

  window.addEventListener("message", onMessage);
  return () => window.removeEventListener("message", onMessage);
}
