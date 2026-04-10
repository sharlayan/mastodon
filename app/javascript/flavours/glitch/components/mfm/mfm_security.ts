const TIME_PATTERN = /^-?[0-9.]+s$/;
const COLOR_PATTERN = /^[0-9a-f]{3,6}$/i;

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
