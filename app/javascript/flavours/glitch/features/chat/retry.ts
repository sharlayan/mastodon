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
  running: boolean;
  again: boolean;
  rateLimited: boolean;
  first: Promise<unknown>;
  resolveFirst?: (value: unknown) => void;
  rejectFirst?: (error: unknown) => void;
  run: () => Promise<unknown>;
  failed?: (error: unknown) => void;
  gaveUp?: () => void;
}

export interface Retries {
  /**
   * Runs `run` now, and again later while it fails, until it works, another try would not
   * help, or it is cancelled. `failed` hears each failure, `gaveUp` when no more tries are
   * planned. Reads under the same key share their plan and rate-limit deadline. The promise
   * is the first try's.
   */
  keepTrying: <T>(
    key: string,
    run: () => Promise<T>,
    callbacks?: { failed?: (error: unknown) => void; gaveUp?: () => void },
  ) => Promise<T>;
  /** Whether something is planned under this key. */
  planned: (key: string) => boolean;
  /** A reconnect can wake an offline read, but not shorten a 429 deadline. */
  wake: (key: string) => void;
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
  sharedCooldowns?: Map<string, number>,
): Retries => {
  const plans = new Map<string, Planned>();
  const cooldowns = sharedCooldowns ?? new Map<string, number>();
  let hidden = hiddenAtFirst;

  const settle = (key: string, entry: Planned, attempt: Promise<unknown>) => {
    void attempt
      .then((value) => {
        entry.resolveFirst?.(value);
        entry.resolveFirst = undefined;
        entry.rejectFirst = undefined;
        entry.running = false;
        if (plans.get(key) !== entry) return;
        if (entry.again) {
          entry.again = false;
          fire(key, entry);
        } else {
          plans.delete(key);
        }
      })
      .catch((error: unknown) => {
        entry.rejectFirst?.(error);
        entry.resolveFirst = undefined;
        entry.rejectFirst = undefined;
        entry.running = false;
        entry.rateLimited =
          (error as { response?: { status?: number } } | null)?.response
            ?.status === 429;
        if (entry.rateLimited) {
          const response = (
            error as { response?: { headers?: unknown } } | null
          )?.response;
          const asked = waitAskedFor(response?.headers, Date.now());
          const fallback =
            RETRY_DELAYS_MS[
              Math.min(entry.tried, RETRY_DELAYS_MS.length - 1)
            ] ?? 0;
          const until = Date.now() + Math.max(asked ?? fallback, 0);
          cooldowns.set(key, Math.max(cooldowns.get(key) ?? 0, until));
        }
        if (plans.get(key) !== entry) return;
        entry.again = false;
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
    // Another screen may have received a 429 after this retry was scheduled.
    // Every path into a request (timer, reconnect, visibility, or coalescing)
    // passes here, so consult the latest account-wide deadline at that point.
    const remaining = (cooldowns.get(key) ?? 0) - Date.now();
    if (remaining > LONGEST_WAIT_MS) {
      plans.delete(key);
      entry.rejectFirst?.(new Error('The server rate limit is still active'));
      entry.resolveFirst = undefined;
      entry.rejectFirst = undefined;
      entry.gaveUp?.();
      return;
    }
    if (remaining > 0) {
      entry.rateLimited = true;
      entry.timer = setTimeout(() => {
        fire(key, entry);
      }, remaining);
      return;
    }
    cooldowns.delete(key);
    entry.rateLimited = false;
    entry.running = true;
    try {
      settle(key, entry, entry.run());
    } catch (error) {
      settle(
        key,
        entry,
        Promise.reject(
          error instanceof Error ? error : new Error(String(error)),
        ),
      );
    }
  };

  const drop = (key: string) => {
    const entry = plans.get(key);
    if (!entry) return;
    if (entry.timer !== null) clearTimeout(entry.timer);
    plans.delete(key);
    entry.rejectFirst?.(new Error('The background read was cancelled'));
    entry.resolveFirst = undefined;
    entry.rejectFirst = undefined;
  };

  return {
    keepTrying(key, run, callbacks = {}) {
      const existing = plans.get(key);
      if (existing) {
        existing.run = run;
        if (existing.running) existing.again = true;
        return existing.first as ReturnType<typeof run>;
      }
      const now = Date.now();
      cooldowns.forEach((until, cooldownKey) => {
        if (until <= now) cooldowns.delete(cooldownKey);
      });
      const remaining = (cooldowns.get(key) ?? 0) - now;
      if (remaining > LONGEST_WAIT_MS) {
        callbacks.gaveUp?.();
        return Promise.reject(
          new Error('The server rate limit is still active'),
        );
      }
      if (remaining <= 0) cooldowns.delete(key);
      let resolveFirst!: (value: unknown) => void;
      let rejectFirst!: (error: unknown) => void;
      const first = new Promise<unknown>((resolve, reject) => {
        resolveFirst = resolve;
        rejectFirst = reject;
      });
      const entry: Planned = {
        tried: 0,
        timer: null,
        due: false,
        running: false,
        again: false,
        rateLimited: false,
        first,
        resolveFirst,
        rejectFirst,
        run,
        ...callbacks,
      };
      plans.set(key, entry);
      if (remaining > 0) {
        entry.rateLimited = true;
        entry.timer = setTimeout(() => {
          fire(key, entry);
        }, remaining);
      } else {
        fire(key, entry);
      }
      return first as ReturnType<typeof run>;
    },
    planned(key) {
      return plans.has(key);
    },
    wake(key) {
      const entry = plans.get(key);
      if (entry?.timer == null || entry.rateLimited || hidden) return;
      clearTimeout(entry.timer);
      fire(key, entry);
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
      if (!sharedCooldowns) cooldowns.clear();
    },
  };
};
