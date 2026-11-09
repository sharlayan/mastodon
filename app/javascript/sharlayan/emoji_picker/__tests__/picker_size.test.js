import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  EmojiPickerSizeObserver,
  computeEmojiPickerStyle,
  loadEmojiPickerSize,
} from '../picker_size';

const STORAGE_KEY = 'mastodon-emojipicker-size';

describe('loadEmojiPickerSize', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('parses a stored size and returns null when nothing or invalid JSON is stored', () => {
    expect(loadEmojiPickerSize()).toBeNull();

    localStorage.setItem(STORAGE_KEY, JSON.stringify({ width: 320, height: 400 }));

    expect(loadEmojiPickerSize()).toEqual({ width: 320, height: 400 });

    localStorage.setItem(STORAGE_KEY, '{not json');

    expect(loadEmojiPickerSize()).toBeNull();
  });
});

describe('computeEmojiPickerStyle', () => {
  it('returns the base style without a size and merges width and height from a stored size', () => {
    const style = { color: 'red' };

    expect(computeEmojiPickerStyle(style, null)).toBe(style);

    const result = computeEmojiPickerStyle(
      { color: 'red' },
      { width: 320, height: 400 },
    );

    expect(result).toEqual({ color: 'red', width: 320, height: 400 });
  });
});

describe('EmojiPickerSizeObserver', () => {
  let observed;
  let disconnected;

  beforeEach(() => {
    observed = [];
    disconnected = 0;
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(callback) {
          this.callback = callback;
        }
        observe(node) {
          observed.push(node);
        }
        disconnect() {
          disconnected += 1;
        }
      },
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('observes a node only once', () => {
    const store = new EmojiPickerSizeObserver(() => undefined);
    const node = {};

    store.observe(node);
    store.observe(node);

    expect(observed).toEqual([node]);
  });

  it('ignores a missing node', () => {
    const store = new EmojiPickerSizeObserver(() => undefined);

    store.observe(null);

    expect(observed).toEqual([]);
  });

  it('reports the observed size to the callback', () => {
    const onResize = vi.fn();
    const store = new EmojiPickerSizeObserver(onResize);
    const node = {};

    store.observe(node);
    store.observer.callback([{ contentRect: { width: 300, height: 350 } }]);

    expect(onResize).toHaveBeenCalledWith({ width: 300, height: 350 });
  });

  describe('when the screen holds the picker below the size it was given', () => {
    beforeEach(() => {
      vi.useFakeTimers();
      localStorage.clear();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('neither remembers nor reports that size', () => {
      const onResize = vi.fn();
      const store = new EmojiPickerSizeObserver(onResize, () => false);

      store.observe({});
      store.observer.callback([{ contentRect: { width: 300, height: 150 } }]);
      vi.runAllTimers();

      expect(onResize).not.toHaveBeenCalled();
      expect(localStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it('still remembers a size the reader chose', () => {
      const onResize = vi.fn();
      const store = new EmojiPickerSizeObserver(onResize, () => true);

      store.observe({});
      store.observer.callback([{ contentRect: { width: 340, height: 280 } }]);
      vi.runAllTimers();

      expect(onResize).toHaveBeenCalledWith({ width: 340, height: 280 });
      expect(JSON.parse(localStorage.getItem(STORAGE_KEY))).toEqual({ width: 340, height: 280 });
    });

    it('keeps every size when nothing is said about the screen', () => {
      const store = new EmojiPickerSizeObserver(() => undefined);

      store.observe({});
      store.observer.callback([{ contentRect: { width: 300, height: 150 } }]);
      vi.runAllTimers();

      expect(JSON.parse(localStorage.getItem(STORAGE_KEY))).toEqual({ width: 300, height: 150 });
    });

    it('remembers a size still waiting to be saved when the picker closes', () => {
      const store = new EmojiPickerSizeObserver(() => undefined);

      store.observe({});
      store.observer.callback([{ contentRect: { width: 360, height: 420 } }]);
      store.dispose();

      expect(JSON.parse(localStorage.getItem(STORAGE_KEY))).toEqual({ width: 360, height: 420 });
      localStorage.clear();
      vi.runAllTimers();
      expect(localStorage.getItem(STORAGE_KEY)).toBeNull();
    });
  });

  it('disconnects on dispose', () => {
    const store = new EmojiPickerSizeObserver(() => undefined);

    store.observe({});
    store.dispose();

    expect(disconnected).toBe(1);
    expect(store.observer).toBeNull();
  });
});
