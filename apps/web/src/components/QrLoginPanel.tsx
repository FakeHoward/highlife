import { useEffect, useState } from "react";
import { useI18n } from "../i18n";
import { QrCode } from "./QrCode";

export type QrLoginFlow = {
  readonly code?: Uint8Array;
  readonly checkCode?: string;
  generateCode(): Promise<void>;
  negotiateProtocols(): Promise<unknown>;
  deviceAuthorizationGrant(input?: unknown): Promise<{ verificationUri?: string; userCode?: string }>;
  shareSecrets(): Promise<unknown>;
  cancel?(reason?: string): Promise<void>;
  close?(): Promise<void>;
};

function qrFailureText(reason: unknown, fallback: string): string | null {
  const message = reason instanceof Error ? reason.message : String(reason ?? "");
  if (/abort|cancel|404|not found/i.test(message)) return null;
  return message.trim() || fallback;
}

export function QrLoginPanel({
  start,
  onClose,
}: {
  start: (onFailure: (reason: string) => void, signal: AbortSignal) => Promise<QrLoginFlow>;
  onClose?: () => void;
}) {
  const { t } = useI18n();
  const [code, setCode] = useState<Uint8Array | null>(null);
  const [checkCode, setCheckCode] = useState<string | null>(null);
  const [verifyUri, setVerifyUri] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const abort = new AbortController();
    let flow: QrLoginFlow | null = null;
    void (async () => {
      try {
        setStatus(t("settings.qrWaiting"));
        flow = await start((reason) => {
          if (abort.signal.aborted) return;
          const text = qrFailureText(reason, t("login.qrUnavailable"));
          if (text) setError(text);
        }, abort.signal);
        await flow.generateCode();
        if (abort.signal.aborted) return;
        if (flow.code) setCode(flow.code);
        setCheckCode(flow.checkCode ?? null);
        await flow.negotiateProtocols();
        if (abort.signal.aborted) return;
        const grant = await flow.deviceAuthorizationGrant();
        if (abort.signal.aborted) return;
        if (grant.verificationUri) setVerifyUri(grant.verificationUri);
        setCheckCode(flow.checkCode ?? null);
        await flow.shareSecrets();
        if (!abort.signal.aborted) setStatus(t("settings.qrDone"));
      } catch (reason) {
        if (abort.signal.aborted) return;
        const text = qrFailureText(reason, t("login.qrUnavailable"));
        setError(text);
        setStatus(null);
      }
    })();
    return () => {
      abort.abort();
      void flow?.cancel?.("user_cancelled").catch(() => undefined);
      void flow?.close?.().catch(() => undefined);
    };
  }, [start, t]);

  return (
    <div className="qr-login">
      {code && <QrCode payload={code} label={t("login.signInQr")} />}
      {checkCode && (
        <p className="muted small">
          {t("settings.qrCheckCode")}: <strong>{checkCode}</strong>
        </p>
      )}
      {verifyUri && (
        <a className="button" href={verifyUri} target="_blank" rel="noreferrer">
          {t("login.confirmOnOtherDevice")}
        </a>
      )}
      {status && <p className="muted small" role="status">{status}</p>}
      {error && <p className="error" role="alert">{error}</p>}
      {onClose && (
        <button type="button" className="button" onClick={onClose}>{t("common.close")}</button>
      )}
    </div>
  );
}
