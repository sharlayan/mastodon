const TIME_PATTERN = /^-?[0-9.]+s$/;
const COLOR_PATTERN = /^[0-9a-f]{3,6}$/i;
const UNIX_TIMESTAMP_PATTERN = /^-?\d+$/;
const MAX_UNIX_TIMESTAMP_SECONDS = 8_640_000_000_000;

export function validTime(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  if (!TIME_PATTERN.test(value)) return null;
  return value;
}

export function validColor(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  if (!COLOR_PATTERN.test(value)) return null;
  return value;
}

export function safeParseFloat(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  if (value === '') return null;
  const num = parseFloat(value);
  if (isNaN(num)) return null;
  return num;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function parseUnixTimestamp(value: unknown): Date | null {
  if (typeof value !== 'string' || !UNIX_TIMESTAMP_PATTERN.test(value)) {
    return null;
  }

  const timestamp = Number(value);
  if (
    !Number.isSafeInteger(timestamp) ||
    Math.abs(timestamp) > MAX_UNIX_TIMESTAMP_SECONDS
  ) {
    return null;
  }

  const date = new Date(timestamp * 1000);
  return Number.isFinite(date.getTime()) ? date : null;
}
