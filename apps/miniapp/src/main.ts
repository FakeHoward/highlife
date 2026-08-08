import "./styles.css";

type FieldType = "text" | "single" | "multi" | "number" | "date" | "scale";
type FormKind = "survey" | "rsvp" | "join" | "onboard";
type FormPolicy = "public" | "private" | "moderators";

interface Field {
  id: string;
  type: FieldType;
  label: string;
  required: boolean;
  options?: string[];
  min?: number;
  max?: number;
}

interface FormView {
  id: string;
  title: string;
  description: string;
  kind: FormKind;
  status: string;
  policy: FormPolicy;
  anonymous: boolean;
  oneResponse: boolean;
  deadlineMs: number | null;
  fields: Field[];
}

interface MatrixMiniAppApi {
  initData: string;
  initDataUnsafe?: { start_param?: string; matrix?: { startParam?: string } };
  matrix?: { startParam?: string; roomId?: string; userId?: string };
  ready: () => void;
  expand: () => void;
  close: () => void;
  sendData: (data: string | object) => void;
  MainButton: {
    setText: (text: string) => MatrixMiniAppApi["MainButton"];
    show: () => MatrixMiniAppApi["MainButton"];
    hide: () => MatrixMiniAppApi["MainButton"];
    onClick: (cb: () => void) => void;
  };
  HapticFeedback?: { notificationOccurred: (type: string) => void };
}

declare global {
  interface Window {
    MatrixMiniApp?: MatrixMiniAppApi;
    Telegram?: { WebApp?: MatrixMiniAppApi };
  }
}

const API = "/miniapp-api";
const root = document.querySelector<HTMLDivElement>("#app")!;

function app(): MatrixMiniAppApi | null {
  return window.MatrixMiniApp ?? window.Telegram?.WebApp ?? null;
}

function startParam(): string {
  const mini = app();
  const fromBridge =
    mini?.matrix?.startParam ||
    mini?.initDataUnsafe?.start_param ||
    mini?.initDataUnsafe?.matrix?.startParam;
  if (fromBridge) return fromBridge;
  return new URLSearchParams(location.search).get("start") ?? "build:survey";
}

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(16).slice(2, 8)}`;
}

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, init);
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || response.statusText);
  }
  return (await response.json()) as T;
}

async function authToken(): Promise<string | null> {
  const mini = app();
  if (!mini?.initData) return null;
  const result = await api<{ token: string }>("/auth", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ initData: mini.initData }),
  });
  return result.token;
}

function seedFields(kind: FormKind): Field[] {
  if (kind === "rsvp") {
    return [
      { id: uid("f"), type: "single", label: "Attendance", required: true, options: ["Going", "Maybe", "Can't make it"] },
      { id: uid("f"), type: "text", label: "Comment (optional)", required: false },
    ];
  }
  if (kind === "join") {
    return [
      { id: uid("f"), type: "text", label: "How do you know this community?", required: true },
      { id: uid("f"), type: "text", label: "Why do you want to join?", required: true },
    ];
  }
  if (kind === "onboard") {
    return [
      { id: uid("f"), type: "single", label: "I accept the room rules", required: true, options: ["Yes, I accept"] },
      { id: uid("f"), type: "single", label: "Your role", required: true, options: ["Member", "Organizer", "Guest"] },
      { id: uid("f"), type: "multi", label: "Interests", required: false, options: ["Events", "Dev", "Privacy", "Art"] },
    ];
  }
  return [
    { id: uid("f"), type: "text", label: "What should we improve?", required: true },
    { id: uid("f"), type: "single", label: "How did you hear about us?", required: true, options: ["Friend", "Matrix", "Telegram", "Other"] },
    { id: uid("f"), type: "scale", label: "Overall satisfaction", required: true, min: 1, max: 5 },
  ];
}

function renderBuilder(kind: FormKind): void {
  let title = kind === "survey" ? "Community survey" : kind === "rsvp" ? "Event RSVP" : kind === "join" ? "Join request" : "Welcome onboarding";
  let description = "Built with FormSpace on your Matrix homeserver.";
  let policy: FormPolicy = kind === "join" ? "moderators" : "public";
  let anonymous = false;
  let oneResponse = true;
  let deadlineLocal = "";
  let fields = seedFields(kind);

  const paint = () => {
    root.innerHTML = `
      <h1>FormSpace builder</h1>
      <p class="muted">${kind.toUpperCase()} · publish a form card into the current room</p>
      <div class="card stack">
        <label>Title<input id="title" value="${escapeAttr(title)}" /></label>
        <label>Description<textarea id="description">${escapeHtml(description)}</textarea></label>
        <label>Policy
          <select id="policy">
            <option value="public" ${policy === "public" ? "selected" : ""}>public summary</option>
            <option value="private" ${policy === "private" ? "selected" : ""}>private to creator</option>
            <option value="moderators" ${policy === "moderators" ? "selected" : ""}>moderators</option>
          </select>
        </label>
        <label>Deadline (local)<input id="deadline" type="datetime-local" value="${escapeAttr(deadlineLocal)}" /></label>
        <div class="row">
          <label class="chip ${anonymous ? "on" : ""}" id="anon">Anonymous</label>
          <label class="chip ${oneResponse ? "on" : ""}" id="once">One response / user</label>
        </div>
      </div>
      <div class="card stack" id="fields"></div>
      <div class="row">
        <button class="secondary" id="add">Add field</button>
        <button id="publish">Publish</button>
      </div>
      <p class="error" id="error"></p>
    `;

    const fieldsEl = root.querySelector("#fields")!;
    fieldsEl.innerHTML = fields
      .map(
        (field, index) => `
      <div class="field-row" data-i="${index}">
        <label>Label<input data-k="label" value="${escapeAttr(field.label)}" /></label>
        <label>Type
          <select data-k="type">
            ${(["text", "single", "multi", "number", "date", "scale"] as FieldType[])
              .map((type) => `<option value="${type}" ${field.type === type ? "selected" : ""}>${type}</option>`)
              .join("")}
          </select>
        </label>
        <button class="danger" data-del="${index}" type="button">Remove</button>
        <label style="grid-column:1/-1">Options (comma-separated)
          <input data-k="options" value="${escapeAttr((field.options ?? []).join(", "))}" />
        </label>
      </div>`,
      )
      .join("");

    root.querySelector("#title")!.addEventListener("input", (event) => {
      title = (event.target as HTMLInputElement).value;
    });
    root.querySelector("#description")!.addEventListener("input", (event) => {
      description = (event.target as HTMLTextAreaElement).value;
    });
    root.querySelector("#policy")!.addEventListener("change", (event) => {
      policy = (event.target as HTMLSelectElement).value as FormPolicy;
    });
    root.querySelector("#deadline")!.addEventListener("input", (event) => {
      deadlineLocal = (event.target as HTMLInputElement).value;
    });
    root.querySelector("#anon")!.addEventListener("click", () => {
      anonymous = !anonymous;
      paint();
    });
    root.querySelector("#once")!.addEventListener("click", () => {
      oneResponse = !oneResponse;
      paint();
    });
    root.querySelector("#add")!.addEventListener("click", () => {
      fields = [...fields, { id: uid("f"), type: "text", label: "New question", required: true }];
      paint();
    });
    fieldsEl.querySelectorAll("[data-del]").forEach((button) => {
      button.addEventListener("click", () => {
        const index = Number((button as HTMLElement).dataset.del);
        fields = fields.filter((_, i) => i !== index);
        paint();
      });
    });
    fieldsEl.querySelectorAll(".field-row").forEach((row) => {
      const index = Number((row as HTMLElement).dataset.i);
      row.querySelectorAll("[data-k]").forEach((input) => {
        input.addEventListener("change", () => {
          const key = (input as HTMLElement).dataset.k!;
          const value = (input as HTMLInputElement | HTMLSelectElement).value;
          const field = { ...fields[index]! };
          if (key === "label") field.label = value;
          if (key === "type") field.type = value as FieldType;
          if (key === "options") {
            field.options = value.split(",").map((part) => part.trim()).filter(Boolean);
          }
          fields = fields.map((item, i) => (i === index ? field : item));
        });
      });
    });

    const publish = () => {
      const deadlineMs = deadlineLocal ? new Date(deadlineLocal).getTime() : null;
      const payload = {
        action: "publish",
        kind,
        title,
        description,
        fields,
        policy,
        anonymous,
        oneResponse,
        deadlineMs,
      };
      const mini = app();
      if (mini) {
        mini.sendData(payload);
        mini.HapticFeedback?.notificationOccurred("success");
        mini.close();
      } else {
        root.querySelector("#error")!.textContent = "Open this MiniApp from the Matrix client to publish.";
      }
    };
    root.querySelector("#publish")!.addEventListener("click", publish);
    const mini = app();
    mini?.MainButton.setText("Publish").show().onClick(publish);
  };

  paint();
}

async function renderFiller(formId: string): Promise<void> {
  root.innerHTML = `<p class="muted">Loading form…</p>`;
  const form = await api<FormView>(`/forms/${encodeURIComponent(formId)}`);
  const answers: Record<string, unknown> = {};
  let step = 0;

  const paint = () => {
    if (form.kind === "rsvp") {
      root.innerHTML = `
        <h1>${escapeHtml(form.title)}</h1>
        <p>${escapeHtml(form.description)}</p>
        <div class="card row">
          <button data-c="going">Going</button>
          <button class="secondary" data-c="maybe">Maybe</button>
          <button class="danger" data-c="no">No</button>
        </div>
        <label>Comment (optional)<input id="comment" /></label>
      `;
      root.querySelectorAll("[data-c]").forEach((button) => {
        button.addEventListener("click", () => {
          const choice = (button as HTMLElement).dataset.c!;
          const comment = (root.querySelector("#comment") as HTMLInputElement).value;
          app()?.sendData({ action: "rsvp", formId: form.id, choice, comment });
          app()?.close();
        });
      });
      return;
    }

    const field = form.fields[step];
    if (!field) return;
    root.innerHTML = `
      <h1>${escapeHtml(form.title)}</h1>
      <p class="muted">Step ${step + 1} / ${form.fields.length}</p>
      <div class="card stack">
        <h2>${escapeHtml(field.label)}${field.required ? " *" : ""}</h2>
        ${renderFieldControl(field)}
      </div>
      <div class="row">
        <button class="secondary" id="back" ${step === 0 ? "disabled" : ""}>Back</button>
        <button id="next">${step === form.fields.length - 1 ? "Submit" : "Next"}</button>
      </div>
      <p class="error" id="error"></p>
    `;
    root.querySelector("#back")!.addEventListener("click", () => {
      step = Math.max(0, step - 1);
      paint();
    });
    root.querySelector("#next")!.addEventListener("click", () => {
      try {
        answers[field.id] = readFieldValue(field);
      } catch (error) {
        root.querySelector("#error")!.textContent = error instanceof Error ? error.message : "Invalid value";
        return;
      }
      if (step >= form.fields.length - 1) {
        app()?.sendData({ action: "submit", formId: form.id, answers });
        app()?.close();
        return;
      }
      step += 1;
      paint();
    });
  };
  paint();
}

async function renderResults(formId: string): Promise<void> {
  root.innerHTML = `<p class="muted">Loading results…</p>`;
  const token = await authToken();
  const headers: Record<string, string> = {};
  if (token) headers.authorization = `Bearer ${token}`;
  const data = await api<{
    form: FormView;
    summary: string;
    rsvp: Record<string, number> | null;
    responses: Array<{ id: string; userId: string | null; answers: Record<string, unknown> }>;
  }>(`/forms/${encodeURIComponent(formId)}/results`, { headers });

  root.innerHTML = `
    <h1>Results · ${escapeHtml(data.form.title)}</h1>
    <div class="card"><pre style="white-space:pre-wrap;margin:0">${escapeHtml(data.summary)}</pre></div>
    ${
      data.rsvp
        ? `<div class="card">Going ${data.rsvp.going} · Maybe ${data.rsvp.maybe} · No ${data.rsvp.no}</div>`
        : ""
    }
    <div class="stack">
      ${data.responses
        .map(
          (response) => `
        <article class="card">
          <strong>${escapeHtml(response.userId ?? "anonymous")}</strong>
          <pre style="white-space:pre-wrap;margin:8px 0 0">${escapeHtml(JSON.stringify(response.answers, null, 2))}</pre>
        </article>`,
        )
        .join("")}
    </div>
  `;
}

function renderFieldControl(field: Field): string {
  if (field.type === "single" || field.type === "multi") {
    return `<div class="chips" id="choices" data-multi="${field.type === "multi" ? "1" : "0"}">
      ${(field.options ?? [])
        .map((option) => `<span class="chip" data-v="${escapeAttr(option)}">${escapeHtml(option)}</span>`)
        .join("")}
    </div>`;
  }
  if (field.type === "scale" || field.type === "number") {
    return `<input id="value" type="number" min="${field.min ?? 0}" max="${field.max ?? 100}" />`;
  }
  if (field.type === "date") return `<input id="value" type="date" />`;
  return `<textarea id="value"></textarea>`;
}

function readFieldValue(field: Field): unknown {
  if (field.type === "single") {
    const selected = document.querySelector(".chip.on") as HTMLElement | null;
    if (!selected && field.required) throw new Error("Pick an option");
    return selected?.dataset.v ?? "";
  }
  if (field.type === "multi") {
    const values = [...document.querySelectorAll(".chip.on")].map((el) => (el as HTMLElement).dataset.v!);
    if (field.required && values.length === 0) throw new Error("Pick at least one");
    return values;
  }
  const input = document.querySelector("#value") as HTMLInputElement | HTMLTextAreaElement;
  const value = input.value;
  if (field.required && !value) throw new Error("Required");
  if (field.type === "number" || field.type === "scale") return Number(value);
  return value;

}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeAttr(value: string): string {
  return escapeHtml(value);
}

// Chip toggle delegation
document.addEventListener("click", (event) => {
  const target = event.target as HTMLElement;
  const choices = target.closest("#choices") as HTMLElement | null;
  if (!target.classList.contains("chip") || !choices) return;
  const multi = choices.dataset.multi === "1";
  if (!multi) {
    choices.querySelectorAll(".chip").forEach((chip) => chip.classList.remove("on"));
    target.classList.add("on");
    return;
  }
  target.classList.toggle("on");
});

async function main(): Promise<void> {
  const mini = app();
  mini?.ready();
  mini?.expand();
  const param = startParam();
  const [mode, arg = "survey"] = param.split(":");
  try {
    if (mode === "build") {
      renderBuilder((["survey", "rsvp", "join", "onboard"].includes(arg) ? arg : "survey") as FormKind);
    } else if (mode === "fill") {
      await renderFiller(arg);
    } else if (mode === "results") {
      await renderResults(arg);
    } else {
      renderBuilder("survey");
    }
  } catch (error) {
    root.innerHTML = `<p class="error">${escapeHtml(error instanceof Error ? error.message : "Failed to load FormSpace")}</p>`;
  }
}

void main();
