import { renderSVG } from "../vendor/uqr.js";

export function bytesToQrText(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 1) out += String.fromCharCode(bytes[i]!);
  return out;
}

export function QrCode({
  payload,
  label,
}: {
  payload: string | Uint8Array;
  label: string;
}) {
  const text = typeof payload === "string" ? payload : bytesToQrText(payload);
  const svg = renderSVG(text, { pixelSize: 4, whiteColor: "#ffffff", blackColor: "#111111" });
  return (
    <div
      className="qr-frame"
      role="img"
      aria-label={label}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
