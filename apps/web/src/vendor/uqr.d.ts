export function encode(
  data: string,
  options?: { ecc?: "L" | "M" | "Q" | "H"; border?: number },
): { data: boolean[][]; size: number; version: number };

export function renderSVG(
  data: string,
  options?: {
    pixelSize?: number;
    whiteColor?: string;
    blackColor?: string;
    ecc?: "L" | "M" | "Q" | "H";
    border?: number;
  },
): string;
