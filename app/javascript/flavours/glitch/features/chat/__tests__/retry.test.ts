import { createRetries, retryDelay } from '../retry';

const NOW = Date.UTC(2026, 10, 6, 3, 0, 0);
const refused = (status: number, headers: Record<string, string> = {}) => ({
  response: { status, headers },
});

describe('How long chat waits before trying again', () => {
  it('waits a little longer each time, and then stops', () => {
    const waits = [0, 1, 2, 3, 4].map((tried) =>
      retryDelay(new Error('offline'), tried, NOW),
    );

    expect(waits).toEqual([2_000, 5_000, 15_000, 30_000, null]);
  });

  it('waits the seconds Retry-After gives', () => {
    expect(retryDelay(refused(429, { 'retry-after': '40' }), 0, NOW)).toBe(
      40_000,
    );
  });

  it('waits until the date Retry-After gives', () => {
    const at = new Date(NOW + 30_000).toUTCString();

    expect(retryDelay(refused(429, { 'retry-after': at }), 0, NOW)).toBe(
      30_000,
    );
  });

  it('waits until the reset time of the rate limit', () => {
    const reset = new Date(NOW + 20_000).toISOString();

    expect(
      retryDelay(refused(429, { 'x-ratelimit-reset': reset }), 0, NOW),
    ).toBe(20_000);
  });

  it('never waits less than it would have anyway', () => {
    const reset = new Date(NOW - 5_000).toISOString();

    expect(
      retryDelay(refused(429, { 'x-ratelimit-reset': reset }), 1, NOW),
    ).toBe(5_000);
  });

  it('does not retry early when the rate limit resets more than ten minutes away', () => {
    const reset = new Date(NOW + 3_600_000).toISOString();

    expect(
      retryDelay(refused(429, { 'x-ratelimit-reset': reset }), 0, NOW),
    ).toBeNull();
  });

  it.each([400, 401, 403, 404, 410, 422])(
    'does not try again after the server said no with %i',
    (status) => {
      expect(retryDelay(refused(status), 0, NOW)).toBeNull();
    },
  );

  it.each([408, 500, 502, 503])(
    'tries again after a %i, which may pass',
    (status) => {
      expect(retryDelay(refused(status), 0, NOW)).toBe(2_000);
    },
  );
});

describe('Chat retries while the page is hidden', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('tries nothing until the page is shown, and then once', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() => Promise.reject(new Error('offline')));
    void retries.keepTrying('read', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);

    retries.hide();
    await vi.advanceTimersByTimeAsync(600_000);
    expect(run).toHaveBeenCalledTimes(1);

    retries.show();
    await vi.advanceTimersByTimeAsync(0);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it('holds a new background request until a hidden page is shown', async () => {
    const retries = createRetries(true);
    const run = vi.fn(() => Promise.resolve('loaded'));
    const first = retries.keepTrying('invitations', run);
    expect(run).not.toHaveBeenCalled();
    retries.show();
    await expect(first).resolves.toBe('loaded');
    expect(run).toHaveBeenCalledTimes(1);
  });

  it('does not restart a pending rate limit when the same read is requested again', async () => {
    const retries = createRetries(false);
    let attempts = 0;
    const run = vi.fn(() => {
      attempts += 1;
      return attempts === 1
        ? Promise.reject(
            Object.assign(
              new Error('rate limited'),
              refused(429, { 'retry-after': '20' }),
            ),
          )
        : Promise.resolve();
    });
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(19_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it('reads once more if an event arrives during an in-flight read', async () => {
    const retries = createRetries(false);
    let finish!: () => void;
    const run = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise<void>((resolve) => {
            finish = resolve;
          }),
      )
      .mockResolvedValue(undefined);
    void retries.keepTrying('invitations', run);
    void retries.keepTrying('invitations', run);
    expect(run).toHaveBeenCalledTimes(1);
    finish();
    await vi.advanceTimersByTimeAsync(0);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it('does not reset the retry count for events during backoff', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() => Promise.reject(new Error('offline')));
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    for (const delay of [2_000, 5_000, 15_000, 30_000]) {
      void retries.keepTrying('invitations', run).catch(() => undefined);
      await vi.advanceTimersByTimeAsync(delay);
    }
    expect(run).toHaveBeenCalledTimes(5);
    expect(retries.planned('invitations')).toBe(false);
  });

  it('can try an offline read on reconnect without shortening a server rate limit', async () => {
    const retries = createRetries(false);
    const offline = vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValue(undefined);
    const limited = vi
      .fn()
      .mockRejectedValueOnce(
        Object.assign(
          new Error('rate limited'),
          refused(429, { 'retry-after': '20' }),
        ),
      )
      .mockResolvedValue(undefined);
    void retries.keepTrying('messages', offline).catch(() => undefined);
    void retries.keepTrying('invitations', limited).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    retries.wake('messages');
    retries.wake('invitations');
    await vi.advanceTimersByTimeAsync(0);
    expect(offline).toHaveBeenCalledTimes(2);
    expect(limited).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(20_000);
    expect(limited).toHaveBeenCalledTimes(2);
  });

  it('keeps a 429 deadline even when the last retry has failed', async () => {
    const retries = createRetries(false);
    const error = Object.assign(
      new Error('rate limited'),
      refused(429, { 'retry-after': '2' }),
    );
    const run = vi.fn(() => Promise.reject(error));
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(52_000);
    expect(run).toHaveBeenCalledTimes(5);
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(1_999);
    expect(run).toHaveBeenCalledTimes(5);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(6);
    retries.stop();
  });

  it('does not send a new request while a too-long rate limit is active', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() =>
      Promise.reject(
        Object.assign(
          new Error('rate limited'),
          refused(429, { 'retry-after': '3600' }),
        ),
      ),
    );
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    void retries.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(600_000);
    expect(run).toHaveBeenCalledTimes(1);
    expect(retries.planned('invitations')).toBe(false);
  });

  it('keeps a shared 429 deadline when one screen stops and another starts', async () => {
    const shared = new Map<string, number>();
    const first = createRetries(false, shared);
    const limited = Object.assign(
      new Error('rate limited'),
      refused(429, { 'retry-after': '20' }),
    );
    void first
      .keepTrying('invitations', () => Promise.reject(limited))
      .catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    first.stop();
    const second = createRetries(false, shared);
    const run = vi.fn(() => Promise.resolve());
    void second.keepTrying('invitations', run);
    await vi.advanceTimersByTimeAsync(19_999);
    expect(run).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(1);
  });

  it('honours the rate limit after the page is hidden and shown early', async () => {
    const retries = createRetries(false);
    let attempts = 0;
    const run = vi.fn(() => {
      attempts += 1;
      return attempts === 1
        ? Promise.reject(
            Object.assign(
              new Error('rate limited'),
              refused(429, { 'retry-after': '20' }),
            ),
          )
        : Promise.resolve();
    });
    void retries.keepTrying('read', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);

    await vi.advanceTimersByTimeAsync(3_000);
    retries.hide();
    await vi.advanceTimersByTimeAsync(2_000);
    retries.show();
    await vi.advanceTimersByTimeAsync(0);
    expect(run).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(15_000);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it('does not try again while hidden when a try on its way fails then', async () => {
    const retries = createRetries(false);
    let fail!: (error: Error) => void;
    const run = vi.fn(
      () =>
        new Promise<never>((_resolve, reject) => {
          fail = reject;
        }),
    );
    void retries.keepTrying('read', run).catch(() => undefined);

    retries.hide();
    fail(new Error('offline'));
    await vi.advanceTimersByTimeAsync(600_000);
    expect(run).toHaveBeenCalledTimes(1);

    retries.show();
    await vi.advanceTimersByTimeAsync(0);
    expect(run).toHaveBeenCalledTimes(2);
  });

  it('forgets what was cancelled', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() => Promise.reject(new Error('offline')));
    void retries.keepTrying('messages:A', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);

    retries.cancel('messages');
    await vi.advanceTimersByTimeAsync(600_000);

    expect(run).toHaveBeenCalledTimes(1);
    expect(retries.planned('messages:A')).toBe(false);
  });
});

describe('Shared deadlines arriving after a retry was planned', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const setup = async () => {
    const shared = new Map<string, number>();
    const old = createRetries(false, shared);
    let rejectOld!: (error: unknown) => void;
    void old
      .keepTrying(
        'invitations',
        () =>
          new Promise((_resolve, reject) => {
            rejectOld = reject;
          }),
      )
      .catch(() => undefined);
    old.stop();
    const current = createRetries(false, shared);
    const run = vi
      .fn()
      .mockRejectedValueOnce(refused(503))
      .mockResolvedValue(undefined);
    void current.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    rejectOld(refused(429, { 'retry-after': '20' }));
    await vi.advanceTimersByTimeAsync(0);
    return { shared, current, run };
  };

  it('rechecks an already scheduled retry and honours later extensions', async () => {
    const { shared, current, run } = await setup();
    await vi.advanceTimersByTimeAsync(2_000);
    expect(run).toHaveBeenCalledTimes(1);
    shared.set('invitations', Date.now() + 30_000);
    await vi.advanceTimersByTimeAsync(29_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
    current.stop();
  });

  it('does not let an event or reconnect wake the old timer before the new deadline', async () => {
    const { current, run } = await setup();
    void current.keepTrying('invitations', run).catch(() => undefined);
    current.wake('invitations');
    await vi.advanceTimersByTimeAsync(19_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
    current.stop();
  });

  it('rechecks the deadline when a due hidden retry is shown', async () => {
    const { current, run } = await setup();
    current.hide();
    await vi.advanceTimersByTimeAsync(2_000);
    current.show();
    await vi.advanceTimersByTimeAsync(17_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
    current.stop();
  });

  it('checks a late deadline before a coalesced follow-up to a successful request', async () => {
    const shared = new Map<string, number>();
    const old = createRetries(false, shared);
    let rejectOld!: (error: unknown) => void;
    void old
      .keepTrying(
        'invitations',
        () =>
          new Promise((_resolve, reject) => {
            rejectOld = reject;
          }),
      )
      .catch(() => undefined);
    old.stop();
    const current = createRetries(false, shared);
    let finish!: () => void;
    const run = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise<void>((resolve) => {
            finish = resolve;
          }),
      )
      .mockResolvedValue(undefined);
    void current.keepTrying('invitations', run);
    void current.keepTrying('invitations', run);
    rejectOld(refused(429, { 'retry-after': '20' }));
    await vi.advanceTimersByTimeAsync(0);
    finish();
    await vi.advanceTimersByTimeAsync(19_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
    current.stop();
  });

  it('does not shorten a long deadline when a later short 429 arrives', async () => {
    const shared = new Map<string, number>();
    const long = createRetries(false, shared);
    const short = createRetries(false, shared);
    let rejectLong!: (error: unknown) => void;
    let rejectShort!: (error: unknown) => void;
    void long
      .keepTrying(
        'invitations',
        () =>
          new Promise((_resolve, reject) => {
            rejectLong = reject;
          }),
      )
      .catch(() => undefined);
    void short
      .keepTrying(
        'invitations',
        () =>
          new Promise((_resolve, reject) => {
            rejectShort = reject;
          }),
      )
      .catch(() => undefined);
    long.stop();
    short.stop();
    const current = createRetries(false, shared);
    const run = vi
      .fn()
      .mockRejectedValueOnce(refused(503))
      .mockResolvedValue(undefined);
    void current.keepTrying('invitations', run).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(0);
    rejectLong(refused(429, { 'retry-after': '20' }));
    await vi.advanceTimersByTimeAsync(1_000);
    const earlierDeadline = shared.get('invitations');
    rejectShort(refused(429, { 'retry-after': '5' }));
    await vi.advanceTimersByTimeAsync(0);
    expect(shared.get('invitations')).toBe(earlierDeadline);
    await vi.advanceTimersByTimeAsync(18_999);
    expect(run).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(run).toHaveBeenCalledTimes(2);
    current.stop();
  });

  it('does not plan a retry beyond the maximum wait after a late long 429', async () => {
    const { shared, current, run } = await setup();
    shared.set('invitations', Date.now() + 3_600_000);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(run).toHaveBeenCalledTimes(1);
    expect(current.planned('invitations')).toBe(false);
    current.stop();
  });
});

describe('Pages within a running chat read', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('waits for visibility and then continues the same accumulated read', async () => {
    const retries = createRetries(false);
    let firstDone!: () => void;
    const first = new Promise<void>((resolve) => {
      firstDone = resolve;
    });
    const pages: number[] = [];
    const finished = retries.keepTrying('messages:A', async (nextPage) => {
      pages.push(1);
      await first;
      if (!(await nextPage())) return;
      pages.push(2);
    });
    retries.hide();
    firstDone();
    await vi.advanceTimersByTimeAsync(1_000);
    expect(pages).toEqual([1]);
    retries.show();
    await finished;
    expect(pages).toEqual([1, 2]);
  });

  it('does not continue an old read when the same key is restarted after cancellation', async () => {
    const retries = createRetries(false);
    let finishOld!: () => void;
    const oldFirst = new Promise<void>((resolve) => {
      finishOld = resolve;
    });
    const pages: string[] = [];
    void retries
      .keepTrying('messages:A', async (nextPage) => {
        pages.push('old-1');
        await oldFirst;
        if (await nextPage()) pages.push('old-2');
      })
      .catch(() => undefined);
    retries.cancel('messages:A');
    await retries.keepTrying('messages:A', () => {
      pages.push('new');
      return Promise.resolve();
    });
    finishOld();
    await vi.advanceTimersByTimeAsync(0);
    expect(pages).toEqual(['old-1', 'new']);
  });

  it('waits at the next page for a late 429 and a still later extension', async () => {
    const shared = new Map<string, number>();
    const old = createRetries(false, shared);
    let rejectOld!: (error: unknown) => void;
    void old
      .keepTrying(
        'messages:A',
        () =>
          new Promise((_resolve, reject) => {
            rejectOld = reject;
          }),
      )
      .catch(() => undefined);
    old.stop();
    const current = createRetries(false, shared);
    let finishFirst!: () => void;
    const first = new Promise<void>((resolve) => {
      finishFirst = resolve;
    });
    const pages: number[] = [];
    const done = current.keepTrying('messages:A', async (nextPage) => {
      pages.push(1);
      await first;
      if (await nextPage()) pages.push(2);
    });
    rejectOld(refused(429, { 'retry-after': '20' }));
    await vi.advanceTimersByTimeAsync(0);
    finishFirst();
    await vi.advanceTimersByTimeAsync(2_000);
    shared.set('messages:A', Date.now() + 25_000);
    await vi.advanceTimersByTimeAsync(24_999);
    expect(pages).toEqual([1]);
    await vi.advanceTimersByTimeAsync(1);
    await done;
    expect(pages).toEqual([1, 2]);
  });

  it('releases a waiting page on cancellation without sending it', async () => {
    const retries = createRetries(false);
    const pages: number[] = [];
    const done = retries.keepTrying('sent:A', async (nextPage) => {
      pages.push(1);
      retries.hide();
      if (await nextPage()) pages.push(2);
    });
    retries.cancel('sent:A');
    await expect(done).rejects.toThrow();
    retries.show();
    await vi.advanceTimersByTimeAsync(600_000);
    expect(pages).toEqual([1]);
  });
});

describe('Paged reads following a user action', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  it('preserves the action result while hidden and cancels its remaining pages on exit', async () => {
    const retries = createRetries(false);
    const pages: number[] = [];
    let finish!: () => void;
    const first = new Promise<void>((resolve) => {
      finish = resolve;
    });
    const read = retries.runPages('conversations', async (nextPage) => {
      pages.push(1);
      await first;
      if (await nextPage()) pages.push(2);
    });
    await vi.advanceTimersByTimeAsync(0);
    retries.hide();
    finish();
    await vi.advanceTimersByTimeAsync(10_000);
    expect(pages).toEqual([1]);
    retries.stop();
    await read;
    retries.show();
    expect(pages).toEqual([1]);
  });
  it('does not start a follow-up if the screen closes immediately', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() => Promise.resolve());
    const read = retries.runPages('conversations', run);
    retries.stop();
    await read;
    expect(run).not.toHaveBeenCalled();
  });
  it('does not retry or hide an error from a user action follow-up', async () => {
    const retries = createRetries(false);
    const run = vi.fn(() => Promise.reject(new Error('failed')));
    await expect(retries.runPages('conversations', run)).rejects.toThrow(
      'failed',
    );
    await vi.advanceTimersByTimeAsync(600_000);
    expect(run).toHaveBeenCalledTimes(1);
  });
});
