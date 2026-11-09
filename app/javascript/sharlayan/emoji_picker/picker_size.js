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

  constructor(onResize, shouldKeep = () => true) {
    this.onResize = onResize;
    this.shouldKeep = shouldKeep;
    this.observer = null;
    this.timeout = null;
    this.pendingSize = null;
  }

  observe(node) {
    if (!node || this.observer) {
      return;
    }

    this.observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        if (!this.shouldKeep()) {
          continue;
        }

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

    this.pendingSize = { width, height };
    this.timeout = setTimeout(() => this.flush(), SAVE_DEBOUNCE_MS);
  }

  flush() {
    if (this.timeout) {
      clearTimeout(this.timeout);
      this.timeout = null;
    }

    if (!this.pendingSize) {
      return;
    }

    const size = this.pendingSize;
    this.pendingSize = null;

    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(size));
    } catch {}
  }

  dispose() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }

    this.flush();
  }

}
