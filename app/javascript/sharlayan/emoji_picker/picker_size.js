const STORAGE_KEY = 'mastodon-emojipicker-size';
const SAVE_DEBOUNCE_MS = 500;

export function loadEmojiPickerSize() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
}

export function computeEmojiPickerStyle(style, pickerSize) {
  if (!pickerSize) {
    return style;
  }

  return { ...style, width: pickerSize.width, height: pickerSize.height };
}

export class EmojiPickerSizeObserver {

  constructor(onResize) {
    this.onResize = onResize;
    this.observer = null;
    this.timeout = null;
  }

  observe(node) {
    if (!node || this.observer) {
      return;
    }

    this.observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        this.save(width, height);
        this.onResize({ width, height });
      }
    });

    this.observer.observe(node);
  }

  save(width, height) {
    if (this.timeout) {
      clearTimeout(this.timeout);
    }

    this.timeout = setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({ width, height }));
      } catch {
        // ignore save fail
      }
    }, SAVE_DEBOUNCE_MS);
  }

  dispose() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }

    if (this.timeout) {
      clearTimeout(this.timeout);
      this.timeout = null;
    }
  }

}
