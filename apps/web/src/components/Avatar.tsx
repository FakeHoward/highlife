const FALLBACK_COLORS = [
  "#3f6f8f",
  "#526b9a",
  "#557a61",
  "#8a6048",
  "#76588f",
  "#8a5361",
] as const;

function colorFor(id: string): string {
  let hash = 0;
  for (const point of id) hash = (hash * 31 + point.codePointAt(0)!) | 0;
  return FALLBACK_COLORS[Math.abs(hash) % FALLBACK_COLORS.length]!;
}

function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  return (words.length > 1 ? `${words[0]![0]}${words[1]![0]}` : words[0]?.slice(0, 2) || "?")
    .toLocaleUpperCase();
}

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
  const classes = `avatar avatar-${size} ${className}`.trim();
  if (src) return <img className={classes} src={src} alt={name} loading="lazy" />;
  return (
    <span
      className={`${classes} avatar-fallback`}
      role="img"
      aria-label={name}
      style={{ backgroundColor: colorFor(id) }}
    >
      {initials(name)}
    </span>
  );
}
