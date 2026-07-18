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

  it('returns null when nothing is stored', () => {
    expect(loadEmojiPickerSize()).toBeNull();
  });

  it('parses a stored size', () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ width: 320, height: 400 }));

    expect(loadEmojiPickerSize()).toEqual({ width: 320, height: 400 });
  });

  it('returns null on invalid JSON', () => {
    localStorage.setItem(STORAGE_KEY, '{not json');

    expect(loadEmojiPickerSize()).toBeNull();
  });
});

describe('computeEmojiPickerStyle', () => {
  it('returns the base style when no size is set', () => {
    const style = { color: 'red' };

    expect(computeEmojiPickerStyle(style, null)).toBe(style);
  });

  it('merges width and height from the stored size', () => {
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

  it('disconnects on dispose', () => {
    const store = new EmojiPickerSizeObserver(() => undefined);

    store.observe({});
    store.dispose();

    expect(disconnected).toBe(1);
    expect(store.observer).toBeNull();
  });
});
