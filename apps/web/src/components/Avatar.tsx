import { useEffect, useState } from "react";
import { dicebearAvatarUrl, dicebearBackground } from "../media/dicebear";

const SIZE_PX = { small: 64, medium: 96, large: 128 } as const;

export function Avatar({
  id,
  name,
  src,
  size = "medium",
  className = "",
}: {
  id: string;
  name: string;
  src?: string;
  size?: "small" | "medium" | "large";
  className?: string;
}) {
  const [failedSrc, setFailedSrc] = useState(false);
  const [failedDicebear, setFailedDicebear] = useState(false);
  const classes = `avatar avatar-${size} ${className}`.trim();

  useEffect(() => {
    setFailedSrc(false);
    setFailedDicebear(false);
  }, [id, src]);

  if (src && !failedSrc) {
    return (
      <img
        className={classes}
        src={src}
        alt={name}
        loading="lazy"
        referrerPolicy="no-referrer"
        onError={() => setFailedSrc(true)}
      />
    );
  }

  if (!failedDicebear) {
    return (
      <img
        className={classes}
        src={dicebearAvatarUrl(id, SIZE_PX[size])}
        alt={name}
        loading="lazy"
        referrerPolicy="no-referrer"
        onError={() => setFailedDicebear(true)}
      />
    );
  }

  return (
    <span
      className={`${classes} avatar-fallback`}
      role="img"
      aria-label={name}
      style={{ backgroundColor: `#${dicebearBackground(id)}` }}
    >
      {initials(name)}
    </span>
  );
}

function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  return (words.length > 1 ? `${words[0]![0]}${words[1]![0]}` : words[0]?.slice(0, 2) || "?")
    .toLocaleUpperCase();
}
