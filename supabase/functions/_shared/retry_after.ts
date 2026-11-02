// Preserve long valid delays so callers can defer instead of retrying too early.
export function retryDelaySeconds(
  value: string | null,
  now = Date.now(),
): number {
  const header = value?.trim() ?? "";
  if (!header) return 0;
  const delay = /^\d+$/.test(header)
    ? Number(header)
    : Math.ceil((Date.parse(header) - now) / 1000);
  return Number.isNaN(delay) ? 0 : Math.max(0, delay);
}
