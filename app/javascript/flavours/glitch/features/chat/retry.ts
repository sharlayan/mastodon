// How the chat screen tries again what it asked for by itself: its reads, and marking rooms
// read. It cannot leave that to the stream, whose signal to read again may have come before
// the screen was there to hear it. A few tries, further apart each time, then it waits for the
// next occasion; a server that says how long to wait is waited for.
export const RETRY_DELAYS_MS = [2_000, 5_000, 15_000, 30_000] as const;
// However long a server asks to wait, nothing is planned further ahead than this.
const LONGEST_WAIT_MS = 10 * 60_000;

const headerOf = (headers: unknown, name: string) => {
  if (!headers || typeof headers !== 'object') return undefined;
  const value = (headers as Record<string, unknown>)[name];
  return typeof value === 'string' ? value : undefined;
};

// What a 429 says about when to come back: Retry-After if a proxy set it, else the reset time
// Mastodon's rate limits send (the same header the app's alerts read).
const waitAskedFor = (headers: unknown, now: number) => {
  const retryAfter = headerOf(headers, 'retry-after');
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds)) return seconds * 1000;
    const at = Date.parse(retryAfter);
    if (!Number.isNaN(at)) return at - now;
  }
  const reset = Date.parse(headerOf(headers, 'x-ratelimit-reset') ?? '');
  return Number.isNaN(reset) ? null : reset - now;
};

/**
 * How long to wait before trying again, after `tried` tries again have already been made,
 * or null when another try would not help or enough have been made.
 */
export const retryDelay = (
  error: unknown,
  tried: number,
  now = Date.now(),
): number | null => {
  const delay = RETRY_DELAYS_MS[tried];
  if (delay === undefined) return null;
  // Read as the rest of the chat screen reads failed requests.
  const response = (
    error as { response?: { status?: number; headers?: unknown } } | null
  )?.response;
  const status = response?.status;
  if (status === 429) {
    const asked = waitAskedFor(response?.headers, now);
    const wait = Math.max(delay, asked ?? delay);
    return wait > LONGEST_WAIT_MS ? null : wait;
  }
  // The server understood and said no; asking again gets the same answer.
  if (status !== undefined && status >= 400 && status < 500 && status !== 408)
    return null;
  return delay;
};

interface Planned {
  tried: number;
  timer: ReturnType<typeof setTimeout> | null;
  // Its time came while the page was hidden, and it waits to be shown.
  due: boolean;
  run: () => Promise<unknown>;
  failed?: (error: unknown) => void;
  gaveUp?: () => void;
}

export interface Retries {
  /**
   * Runs `run` now, and again later while it fails, until it works, another try would not
   * help, or it is cancelled. `failed` hears each failure, `gaveUp` when no more tries are
   * planned. Starting again under the same key replaces what was planned. The promise is the
   * first try's.
   */
  keepTrying: <T>(
    key: string,
    run: () => Promise<T>,
    callbacks?: { failed?: (error: unknown) => void; gaveUp?: () => void },
  ) => Promise<T>;
  /** Whether something is planned under this key. */
  planned: (key: string) => boolean;
  /** Plans nothing more under this key, or any key that starts with it and a colon. */
  cancel: (key: string) => void;
  /** Nothing is tried while the page is hidden. */
  hide: () => void;
  /** What came due while hidden is tried once, now. */
  show: () => void;
  stop: () => void;
}

export const createRetries = (
  hiddenAtFirst = typeof document !== 'undefined' &&
    document.visibilityState === 'hidden',
): Retries => {
  const plans = new Map<string, Planned>();
  let hidden = hiddenAtFirst;

  const settle = (key: string, entry: Planned, attempt: Promise<unknown>) => {
    void attempt
      .then(() => {
        if (plans.get(key) === entry) plans.delete(key);
      })
      .catch((error: unknown) => {
        if (plans.get(key) !== entry) return;
        entry.failed?.(error);
        if (plans.get(key) !== entry) return;
        const delay = retryDelay(error, entry.tried);
        if (delay === null) {
          plans.delete(key);
          entry.gaveUp?.();
          return;
        }
        entry.tried += 1;
        entry.timer = setTimeout(() => {
          fire(key, entry);
        }, delay);
      });
  };

  const fire = (key: string, entry: Planned) => {
    entry.timer = null;
    if (hidden) {
      entry.due = true;
      return;
    }
    entry.due = false;
    settle(key, entry, entry.run());
  };

  const drop = (key: string) => {
    const entry = plans.get(key);
    if (!entry) return;
    if (entry.timer !== null) clearTimeout(entry.timer);
    plans.delete(key);
  };

  return {
    keepTrying(key, run, callbacks = {}) {
      drop(key);
      const entry: Planned = {
        tried: 0,
        timer: null,
        due: false,
        run,
        ...callbacks,
      };
      plans.set(key, entry);
      const first = run();
      settle(key, entry, first);
      return first;
    },
    planned(key) {
      return plans.has(key);
    },
    cancel(key) {
      [...plans.keys()]
        .filter((planned) => planned === key || planned.startsWith(`${key}:`))
        .forEach(drop);
    },
    hide() {
      hidden = true;
    },
    show() {
      hidden = false;
      plans.forEach((entry, key) => {
        if (entry.due) fire(key, entry);
      });
    },
    stop() {
      [...plans.keys()].forEach(drop);
    },
  };
};
