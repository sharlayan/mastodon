export const RETRY_DELAYS_MS = [2_000, 5_000, 15_000, 30_000] as const;
const LONGEST_WAIT_MS = 10 * 60_000;

const headerOf = (headers: unknown, name: string) => {
  if (!headers || typeof headers !== 'object') return undefined;
  const value = (headers as Record<string, unknown>)[name];
  return typeof value === 'string' ? value : undefined;
};

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

export const retryDelay = (
  error: unknown,
  tried: number,
  now = Date.now(),
): number | null => {
  const delay = RETRY_DELAYS_MS[tried];
  if (delay === undefined) return null;
  const response = (
    error as { response?: { status?: number; headers?: unknown } } | null
  )?.response;
  const status = response?.status;
  if (status === 429) {
    const asked = waitAskedFor(response?.headers, now);
    const wait = Math.max(delay, asked ?? delay);
    return wait > LONGEST_WAIT_MS ? null : wait;
  }
  if (status !== undefined && status >= 400 && status < 500 && status !== 408)
    return null;
  return delay;
};

export type PageCheckpoint = () => Promise<boolean>;

interface PageScope {
  pageWait?: { check: () => void; cancel: () => void };
  gaveUp?: () => void;
  waitForLimitedPlan?: boolean;
  wasLimited?: boolean;
  waitingFor?: Planned;
}

interface Planned extends PageScope {
  tried: number;
  timer: ReturnType<typeof setTimeout> | null;
  due: boolean;
  running: boolean;
  again: boolean;
  rateLimited: boolean;
  first: Promise<unknown>;
  resolveFirst?: (value: unknown) => void;
  rejectFirst?: (error: unknown) => void;
  finished: Promise<void>;
  finish: () => void;
  run: (nextPage: PageCheckpoint) => Promise<unknown>;
  failed?: (error: unknown) => void;
}

export interface Retries {
  keepTrying: <T>(
    key: string,
    run: (nextPage: PageCheckpoint) => Promise<T>,
    callbacks?: { failed?: (error: unknown) => void; gaveUp?: () => void },
  ) => Promise<T>;
  runPages: <T>(
    key: string,
    run: (nextPage: PageCheckpoint) => Promise<T>,
  ) => Promise<T | undefined>;
  recordFailure: (key: string, error: unknown) => void;
  planned: (key: string) => boolean;
  limited: (key: string) => boolean;
  wake: (key: string) => void;
  cancel: (key: string) => void;
  hide: () => void;
  show: () => void;
  stop: () => void;
}

export const createRetries = (
  hiddenAtFirst = typeof document !== 'undefined' &&
    document.visibilityState === 'hidden',
  sharedCooldowns?: Map<string, number>,
): Retries => {
  const plans = new Map<string, Planned>();
  const pageScopes = new Set<PageScope>();
  const cooldowns = sharedCooldowns ?? new Map<string, number>();
  let hidden = hiddenAtFirst;

  const rememberLimit = (key: string, error: unknown, tried = 0) => {
    const response = (
      error as { response?: { status?: number; headers?: unknown } } | null
    )?.response;
    if (response?.status !== 429) return false;
    const asked = waitAskedFor(response.headers, Date.now());
    const fallback =
      RETRY_DELAYS_MS[Math.min(tried, RETRY_DELAYS_MS.length - 1)] ?? 0;
    const until = Date.now() + Math.max(asked ?? fallback, 0);
    cooldowns.set(key, Math.max(cooldowns.get(key) ?? 0, until));
    return true;
  };

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
          entry.finish();
        }
      })
      .catch((error: unknown) => {
        entry.rejectFirst?.(error);
        entry.resolveFirst = undefined;
        entry.rejectFirst = undefined;
        entry.running = false;
        entry.rateLimited = rememberLimit(key, error, entry.tried);
        if (plans.get(key) !== entry) return;
        entry.again = false;
        entry.failed?.(error);
        if (plans.get(key) !== entry) return;
        const delay = retryDelay(error, entry.tried);
        if (delay === null) {
          plans.delete(key);
          entry.finish();
          entry.gaveUp?.();
          return;
        }
        entry.tried += 1;
        entry.timer = setTimeout(() => {
          fire(key, entry);
        }, delay);
      });
  };

  const waitForPage = (
    key: string,
    entry: PageScope,
    isCurrent: () => boolean,
  ): Promise<boolean> =>
    new Promise((resolve) => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const finish = (allowed: boolean) => {
        if (timer !== undefined) clearTimeout(timer);
        if (entry.pageWait === waiting) entry.pageWait = undefined;
        resolve(allowed);
      };
      const check = () => {
        if (timer !== undefined) clearTimeout(timer);
        timer = undefined;
        if (!isCurrent()) {
          finish(false);
          return;
        }
        const remaining = (cooldowns.get(key) ?? 0) - Date.now();
        if (cooldowns.has(key)) entry.wasLimited = true;
        if (hidden) return;
        if (remaining > LONGEST_WAIT_MS) {
          entry.gaveUp?.();
          finish(false);
          return;
        }
        if (remaining > 0) {
          timer = setTimeout(check, remaining);
          return;
        }
        const planned = plans.get(key);
        if (entry.waitForLimitedPlan && entry.wasLimited && planned) {
          if (entry.waitingFor !== planned) {
            entry.waitingFor = planned;
            void planned.finished.then(() => {
              if (entry.pageWait === waiting) check();
            });
          }
          return;
        }
        entry.wasLimited = false;
        finish(true);
      };
      const waiting = {
        check,
        cancel: () => {
          finish(false);
        },
      };
      entry.pageWait = waiting;
      check();
    });

  const fire = (key: string, entry: Planned) => {
    entry.timer = null;
    if (hidden) {
      entry.due = true;
      return;
    }
    entry.due = false;
    const remaining = (cooldowns.get(key) ?? 0) - Date.now();
    if (remaining > LONGEST_WAIT_MS) {
      plans.delete(key);
      entry.finish();
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
      settle(
        key,
        entry,
        entry.run(() =>
          waitForPage(key, entry, () => plans.get(key) === entry),
        ),
      );
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
    entry.finish();
    entry.pageWait?.cancel();
    entry.rejectFirst?.(new Error('The background read was cancelled'));
    entry.resolveFirst = undefined;
    entry.rejectFirst = undefined;
  };

  return {
    recordFailure(key, error) {
      rememberLimit(key, error);
    },
    async runPages(key, run) {
      const scope: PageScope = { waitForLimitedPlan: true };
      pageScopes.add(scope);
      const nextPage = () =>
        waitForPage(key, scope, () => pageScopes.has(scope));
      try {
        if (!(await nextPage()) || !pageScopes.has(scope)) return undefined;
        return await run(nextPage);
      } catch (error) {
        rememberLimit(key, error);
        throw error;
      } finally {
        pageScopes.delete(scope);
        scope.pageWait?.cancel();
      }
    },
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
      let finish!: () => void;
      const finished = new Promise<void>((resolve) => {
        finish = resolve;
      });
      const entry: Planned = {
        tried: 0,
        timer: null,
        due: false,
        running: false,
        again: false,
        rateLimited: false,
        first,
        finished,
        finish,
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
    limited(key) {
      return (cooldowns.get(key) ?? 0) > Date.now();
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
      pageScopes.forEach((scope) => scope.pageWait?.check());
      plans.forEach((entry, key) => {
        entry.pageWait?.check();
        if (entry.due) fire(key, entry);
      });
    },
    stop() {
      [...plans.keys()].forEach(drop);
      pageScopes.forEach((scope) => scope.pageWait?.cancel());
      pageScopes.clear();
      if (!sharedCooldowns) cooldowns.clear();
    },
  };
};
